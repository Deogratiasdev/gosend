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
  int _currentPeerHttpPort = transferPort;
  String? _localIpAddress;

  List<FileInfo>? _currentFiles;
  String? _currentSaveDir;
  int _completedReceiveBytes = 0;
  final Set<int> _completedFileIndexes = <int>{};
  final Map<int, int> _fileReceivedBytes = <int, int>{};
  bool _isPaused = false;
  bool _isCancelled = false;
  Function(int, int, int)? _onProgress;
  Function(int, int, int)? _onFileProgress;
  Function(int, String)? _onFileComplete;
  Function()? _onAllComplete;

  Function(TransferRequest)? onTransferRequestReceived;
  Function(String, bool)? onTransferResponse;
  Function(String, String)? onControlMessage;
  Function(Uint8List, int)? onChunkReceived;
  Function(String)? onStatusUpdate;

  HttpTransferService({String? localIpAddress})
    : _localIpAddress = localIpAddress;

  void updateLocalIpAddress(String localIpAddress) {
    _localIpAddress = localIpAddress;
  }

  Future<void> startServers() async {
    await Future.wait([_startSignalingServer(), _startTransferServer()]);
    debugPrint(
      '✅ Serveurs HTTP démarrés (signalisation: $signalingPort, transfert: $transferPort)',
    );
  }

  Future<void> _startSignalingServer() async {
    if (_signalingServer != null) return;

    final router = Router()
      ..post('/transfer-request', _handleTransferRequest)
      ..post('/transfer-response', _handleTransferResponse)
      ..post('/control', _handleControl);

    final handler = const Pipeline().addHandler(router.call);
    _signalingServer = await shelf_io.serve(handler, '0.0.0.0', signalingPort);
    debugPrint('Signaling HTTP server on port $signalingPort');
  }

  Future<void> _startTransferServer() async {
    if (_transferServer != null) return;

    final router = Router()
      ..post('/upload/<fileIndex>', (Request request, String fileIndex) {
        return _handleFileUpload(request, int.parse(fileIndex));
      });

    final handler = const Pipeline().addHandler(router.call);
    _transferServer = await shelf_io.serve(handler, '0.0.0.0', transferPort);
    debugPrint('Transfer HTTP server on port $transferPort');
  }

  void prepareReceive(
    String transferId,
    List<FileInfo> files,
    String saveDir,
    Function(int fileIndex, int received, int total) onProgress,
    Function(int fileIndex, int fileReceived, int fileSize) onFileProgress,
    Function(int fileIndex, String filePath) onFileComplete,
    Function() onAllComplete,
  ) {
    _currentFiles = files;
    _currentSaveDir = saveDir;
    _completedReceiveBytes = 0;
    _completedFileIndexes.clear();
    _fileReceivedBytes.clear();
    _isPaused = false;
    _isCancelled = false;
    _onProgress = onProgress;
    _onFileProgress = onFileProgress;
    _onFileComplete = onFileComplete;
    _onAllComplete = onAllComplete;
  }

  Future<Response> _handleFileUpload(Request request, int fileIndex) async {
    if (_currentFiles == null ||
        _currentSaveDir == null ||
        fileIndex < 0 ||
        fileIndex >= _currentFiles!.length) {
      return Response.badRequest(body: 'Invalid file index');
    }

    final fileInfo = _currentFiles![fileIndex];
    final fileName = _safeFileName(fileInfo.name);
    final filePath = '$_currentSaveDir/$fileName';
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final sink = file.openWrite();
    int received = 0;
    final total = _currentFiles!.fold<int>(0, (sum, file) => sum + file.size);
    _fileReceivedBytes[fileIndex] = 0;

    try {
      await for (final chunk in request.read()) {
        if (_isCancelled) {
          await sink.close();
          return Response(499, body: 'Transfer cancelled');
        }
        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_isCancelled) {
            await sink.close();
            return Response(499, body: 'Transfer cancelled');
          }
        }
        sink.add(chunk);
        received += chunk.length;
        _fileReceivedBytes[fileIndex] = received;
        _onProgress?.call(fileIndex, _completedReceiveBytes + received, total);
        _onFileProgress?.call(fileIndex, received, fileInfo.size);
      }
      await sink.flush();
      await sink.close();

      if (_completedFileIndexes.add(fileIndex)) {
        _completedReceiveBytes += fileInfo.size;
      }
      _onProgress?.call(fileIndex, _completedReceiveBytes, total);
      _onFileComplete?.call(fileIndex, filePath);

      if (_completedFileIndexes.length == _currentFiles!.length) {
        _onAllComplete?.call();
      }

      return Response.ok('OK');
    } catch (e) {
      await sink.close();
      debugPrint('❌ Erreur réception fichier: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _handleTransferRequest(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final transferRequest = TransferRequest.fromJson(
      data['payload'] as Map<String, dynamic>,
    );

    final connectionInfo =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final requestIp = connectionInfo?.remoteAddress.address;
    final peerIp = _validIp(data['senderIp'] as String?) ?? _validIp(requestIp);
    if (peerIp != null && peerIp.isNotEmpty && peerIp != 'Non disponible') {
      _currentPeerIp = peerIp;
      _currentPeerHttpPort = data['senderHttpPort'] as int? ?? transferPort;
      debugPrint('📥 Requête de transfert reçue de $peerIp');
    } else {
      debugPrint('❌ IP de l\'émetteur introuvable dans la requête');
    }

    onTransferRequestReceived?.call(transferRequest);
    return Response.ok('OK');
  }

  Future<Response> _handleTransferResponse(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    onTransferResponse?.call(
      data['requestId'] as String,
      data['accepted'] as bool,
    );
    return Response.ok('OK');
  }

  Future<Response> _handleControl(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    onControlMessage?.call(
      data['requestId'] as String,
      data['action'] as String,
    );
    return Response.ok('OK');
  }

  void connectToPeer(String peerIp, {int httpPort = transferPort}) {
    _currentPeerIp = peerIp;
    _currentPeerHttpPort = httpPort;
    debugPrint('Peer configuré: $peerIp:$httpPort');
  }

  Future<void> sendTransferRequest(TransferRequest request) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) return;

    final uri = Uri.parse('http://$peerIp:$signalingPort/transfer-request');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'type': 'transfer_request',
            'payload': request.toJson(),
            'senderIp': _localIpAddress,
            'senderHttpPort': transferPort,
          }),
        )
        .timeout(const Duration(seconds: 10));

    _throwForBadStatus(response.statusCode, uri, 'Demande non envoyée');
  }

  Future<void> sendTransferResponse(String requestId, bool accepted) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) {
      debugPrint('❌ Impossible de répondre : IP de l\'émetteur inconnue');
      return;
    }

    final uri = Uri.parse('http://$peerIp:$signalingPort/transfer-response');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'requestId': requestId, 'accepted': accepted}),
        )
        .timeout(const Duration(seconds: 5));

    _throwForBadStatus(response.statusCode, uri, 'Réponse non envoyée');
  }

  Future<void> sendControlMessage(String requestId, String action) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) return;

    final uri = Uri.parse('http://$peerIp:$signalingPort/control');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'requestId': requestId, 'action': action}),
        )
        .timeout(const Duration(seconds: 5));

    _throwForBadStatus(
      response.statusCode,
      uri,
      'Message de contrôle non envoyé',
    );
  }

  void pauseTransfer() {
    _isPaused = true;
  }

  void resumeTransfer() {
    _isPaused = false;
  }

  void cancelTransfer() {
    _isCancelled = true;
  }

  Future<void> sendFiles(
    List<File> files,
    String transferId,
    Function(int totalSent, int totalSize) onProgress,
    Function() onComplete,
  ) async {
    if (_currentPeerIp == null) throw Exception('Pas de peer connecté');

    int totalSize = 0;
    for (final file in files) {
      totalSize += await file.length();
    }
    int totalSent = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileSize = await file.length();
      const chunkSize = 256 * 1024;

      final uri = Uri.parse(
        'http://$_currentPeerIp:$_currentPeerHttpPort/upload/$i',
      );
      final streamedRequest = http.StreamedRequest('POST', uri)
        ..headers['content-type'] = 'application/octet-stream'
        ..headers['content-length'] = fileSize.toString();

      final sendFuture = () async {
        final raf = await file.open();
        try {
          int offset = 0;
          while (offset < fileSize) {
            final remaining = fileSize - offset;
            final toRead = chunkSize < remaining ? chunkSize : remaining;
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
        final results = await Future.wait<dynamic>([
          sendFuture,
          responseFuture,
        ]);
        final response = results[1] as http.StreamedResponse;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final body = await response.stream.bytesToString();
          throw HttpException(
            'Upload échoué (${response.statusCode}) $body',
            uri: uri,
          );
        }
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

  void _throwForBadStatus(int statusCode, Uri uri, String message) {
    if (statusCode < 200 || statusCode >= 300) {
      throw HttpException('$message ($statusCode)', uri: uri);
    }
  }

  String _safeFileName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'received_file' : sanitized;
  }

  String? _validIp(String? ip) {
    if (ip == null || ip.isEmpty || ip == 'Non disponible') return null;
    if (ip == '0.0.0.0' || ip == '::') return null;
    return ip;
  }
}
