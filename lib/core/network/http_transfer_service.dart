import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../../models/transfer_request.dart';

class HttpTransferService {
  static const int signalingPort = 8080;
  static const int transferPort = 8081;

  HttpServer? _signalingServer;
  HttpServer? _transferServer;

  String? _currentPeerIp;
  int _currentPeerHttpPort = 8081;

  // ── Callbacks (même interface qu'avant pour HomeScreen) ──
  Function(TransferRequest)? onTransferRequestReceived;
  Function(String, bool)? onTransferResponse;
  Function(String, String)? onControlMessage;
  Function(Uint8List, int)? onChunkReceived;
  Function(String)? onStatusUpdate;

  // ── Réception : serveur signalisation (port 8080) ──
  Future<void> startSignalingServer() async {
    final router = Router()
      ..post('/transfer-request', _handleTransferRequest)
      ..post('/transfer-response', _handleTransferResponse)
      ..post('/control', _handleControl);

    final handler = const Pipeline().addHandler(router.call);
    _signalingServer = await shelf_io.serve(handler, '0.0.0.0', signalingPort);
    debugPrint('Signaling HTTP server on port $signalingPort');
  }

  // ── Réception : serveur transfert de fichiers (port 8081) ──
  Future<void> startTransferServer(
    String transferId,
    List<FileInfo> files,
    String saveDir,
    Function(int fileIndex, int received, int total) onProgress,
    Function(int fileIndex, String filePath) onFileComplete,
    Function() onAllComplete,
  ) async {
    final router = Router()
      ..post('/upload/<fileIndex>', (Request request, String fileIndex) =>
          _handleFileUpload(
            request,
            int.parse(fileIndex),
            transferId,
            files,
            saveDir,
            onProgress,
            onFileComplete,
            onAllComplete,
          ));

    final handler = const Pipeline().addHandler(router.call);
    _transferServer = await shelf_io.serve(handler, '0.0.0.0', transferPort);
    debugPrint('Transfer HTTP server on port $transferPort');
  }

  Future<Response> _handleFileUpload(
    Request request,
    int fileIndex,
    String transferId,
    List<FileInfo> files,
    String saveDir,
    Function(int, int, int) onProgress,
    Function(int, String) onFileComplete,
    Function() onAllComplete,
  ) async {
    if (fileIndex >= files.length) {
      return Response.badRequest(body: 'Invalid file index');
    }

    final fileInfo = files[fileIndex];
    final filePath = '$saveDir/${fileInfo.name}';
    final file = File(filePath);
    final sink = file.openWrite();

    int received = 0;
    final total = fileInfo.size;

    try {
      // ⚡ STREAMING : écriture directe depuis le flux HTTP sans charger en mémoire
      await for (final chunk in request.read()) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(fileIndex, received, total);
      }
      await sink.flush();
      await sink.close();

      onFileComplete(fileIndex, filePath);

      if (fileIndex == files.length - 1) {
        onAllComplete();
      }

      return Response.ok('OK');
    } catch (e) {
      await sink.close();
      debugPrint('❌ Erreur réception fichier: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  // ── Signalisation : réception des demandes de transfert ──
  Future<Response> _handleTransferRequest(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final transferRequest = TransferRequest.fromJson(
      data['payload'] as Map<String, dynamic>,
    );
    onTransferRequestReceived?.call(transferRequest);
    return Response.ok('OK');
  }

  Future<Response> _handleTransferResponse(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    onTransferResponse?.call(data['requestId'] as String, data['accepted'] as bool);
    return Response.ok('OK');
  }

  Future<Response> _handleControl(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    onControlMessage?.call(data['requestId'] as String, data['action'] as String);
    return Response.ok('OK');
  }

  // ── Émission : connexion au peer ──
  void connectToPeer(String peerIp, {int httpPort = 8081}) {
    _currentPeerIp = peerIp;
    _currentPeerHttpPort = httpPort;
    debugPrint('Peer configuré: $peerIp:$httpPort');
  }

  // ── Émission : envoyer une demande de transfert ──
  Future<void> sendTransferRequest(TransferRequest request) async {
    if (_currentPeerIp == null) return;
    await http.post(
      Uri.parse('http://$_currentPeerIp:$signalingPort/transfer-request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'type': 'transfer_request', 'payload': request.toJson()}),
    ).timeout(const Duration(seconds: 10));
  }

  // ── Émission : accepter ou refuser ──
  Future<void> sendTransferResponse(String requestId, bool accepted) async {
    if (_currentPeerIp == null) return;
    await http.post(
      Uri.parse('http://$_currentPeerIp:$signalingPort/transfer-response'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'requestId': requestId, 'accepted': accepted}),
    ).timeout(const Duration(seconds: 5));
  }

  // ── Émission : envoyer un message de contrôle ──
  Future<void> sendControlMessage(String requestId, String action) async {
    if (_currentPeerIp == null) return;
    await http.post(
      Uri.parse('http://$_currentPeerIp:$signalingPort/control'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'requestId': requestId, 'action': action}),
    ).timeout(const Duration(seconds: 5));
  }

  // ── Émission : envoyer les fichiers ──
  // ⚡ C'EST ICI QUE LA MAGIE OPÈRE : streaming HTTP sans ACK, vitesse max
  Future<void> sendFiles(
    List<File> files,
    String transferId,
    Function(int totalSent, int totalSize) onProgress,
    Function() onComplete,
  ) async {
    if (_currentPeerIp == null) throw Exception('Pas de peer connecté');

    int totalSize = 0;
    for (final f in files) totalSize += await f.length();
    int totalSent = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileSize = await file.length();
      const chunkSize = 256 * 1024; // 256 KB par chunk

      // Créer une requête HTTP streamée
      final uri = Uri.parse(
        'http://$_currentPeerIp:$_currentPeerHttpPort/upload/$i',
      );
      final streamedRequest = http.StreamedRequest('POST', uri)
        ..headers['content-type'] = 'application/octet-stream'
        ..headers['content-length'] = fileSize.toString();

      // ⚡ Lire et envoyer le fichier en flux continu
      final sendFuture = () async {
        final raf = await file.open();
        try {
          int offset = 0;
          while (offset < fileSize) {
            final toRead = chunkSize < fileSize - offset
                ? chunkSize
                : fileSize - offset;
            final bytes = await raf.read(toRead);
            if (bytes.isEmpty) break;
            streamedRequest.sink.add(bytes);
            offset += bytes.length;
            totalSent += bytes.length;
            onProgress(totalSent, totalSize);
          }
        } finally {
          await raf.close();
          await streamedRequest.sink.close();
        }
      }();

      final client = http.Client();
      try {
        final responseFuture = client.send(streamedRequest);
        await Future.wait([sendFuture, responseFuture]);
      } finally {
        client.close();
      }

      debugPrint('✅ Fichier $i envoyé: ${file.path}');
    }

    onComplete();
  }

  void dispose() {
    _signalingServer?.close(force: true);
    _transferServer?.close(force: true);
  }
}