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
  List<String> _allLocalIps = [];

  // IdentitÃ© locale pour la route /discover
  String _localDeviceId = '';
  String _localDeviceName = '';
  String _localDeviceOs = '';

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
  Function(String, String, DateTime)? onTextMessageReceived;

  HttpTransferService({String? localIpAddress})
    : _localIpAddress = localIpAddress;

  void updateLocalIpAddress(String localIpAddress) {
    _localIpAddress = localIpAddress;
  }

  void updateAllLocalIps(List<String> ips) {
    _allLocalIps = ips.where((ip) => ip.isNotEmpty && ip != 'Non disponible').toList();
  }

  void setIdentity({required String id, required String name, required String os}) {
    _localDeviceId = id;
    _localDeviceName = name;
    _localDeviceOs = os;
  }

  Future<void> startServers() async {
    await Future.wait([_startSignalingServer(), _startTransferServer()]);
    debugPrint(
      'âœ… Serveurs HTTP dÃ©marrÃ©s (signalisation: $signalingPort, transfert: $transferPort)',
    );
  }

  Future<void> _startSignalingServer() async {
    if (_signalingServer != null) return;

    final router = Router()
      ..post('/transfer-request', _handleTransferRequest)
      ..post('/transfer-response', _handleTransferResponse)
      ..post('/control', _handleControl)
      ..post('/text-message', _handleTextMessage)
      ..get('/discover', _handleDiscover);

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
    final subfolder = _getSubfolderForFile(fileName);
    final filePath = '$_currentSaveDir/$subfolder/$fileName';
    final file = File(filePath);
    await file.parent.create(recursive: true);

    final sink = file.openWrite();
    int received = 0;
    final total = _currentFiles!.fold<int>(0, (sum, file) => sum + file.size);
    _fileReceivedBytes[fileIndex] = 0;

    // Throttle progress callbacks to avoid flooding the UI thread.
    // Without this, each chunk triggers 2x setState() causing severe lag.
    Timer? progressTimer;
    int lastReported = 0;

    void reportProgress() {
      _onProgress?.call(fileIndex, _completedReceiveBytes + received, total);
      _onFileProgress?.call(fileIndex, received, fileInfo.size);
      lastReported = received;
    }

    try {
      await for (final chunk in request.read()) {
        if (_isCancelled) {
          progressTimer?.cancel();
          await sink.close();
          return Response(499, body: 'Transfer cancelled');
        }
        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_isCancelled) {
            progressTimer?.cancel();
            await sink.close();
            return Response(499, body: 'Transfer cancelled');
          }
        }
        sink.add(chunk);
        received += chunk.length;
        _fileReceivedBytes[fileIndex] = received;

        // Throttle: report at most every 200ms or every 1% of file
        final shouldReport = progressTimer == null &&
            (received - lastReported > 64 * 1024 || // every 64KB
             (fileInfo.size > 0 && (received - lastReported) > fileInfo.size ~/ 100));
        if (shouldReport) {
          reportProgress();
          progressTimer = Timer(const Duration(milliseconds: 200), () {
            progressTimer = null;
          });
        }
      }
      progressTimer?.cancel();

      // Final flush
      await sink.flush();
      await sink.close();

      if (_completedFileIndexes.add(fileIndex)) {
        _completedReceiveBytes += fileInfo.size;
      }
      reportProgress();
      _onFileComplete?.call(fileIndex, filePath);

      if (_completedFileIndexes.length == _currentFiles!.length) {
        _onAllComplete?.call();
      }

      return Response.ok('OK');
    } catch (e) {
      await sink.close();
      debugPrint('âŒ Erreur rÃ©ception fichier: $e');
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
    // IMPORTANT : on privilÃ©gie l'IP source TCP rÃ©elle (requestIp) sur
    // le senderIp du body. Quand l'Ã©metteur a WiFi + hotspot simultanÃ©s,
    // getWifiIP() retourne l'IP WiFi (ex: 192.168.1.100) qui est
    // injoignable depuis le client hotspot (192.168.43.x). L'IP source
    // TCP est toujours correcte car c'est l'IP rÃ©ellement utilisÃ©e pour
    // nous joindre.
    final senderIps = (data['senderIps'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .where((ip) => _validIp(ip) != null)
        .toList();
    final peerIp = _validIp(requestIp)
        ?? (senderIps != null && senderIps.isNotEmpty ? senderIps.first : null)
        ?? _validIp(data['senderIp'] as String?);
    if (peerIp != null && peerIp.isNotEmpty && peerIp != 'Non disponible') {
      _currentPeerIp = peerIp;
      _currentPeerHttpPort = data['senderHttpPort'] as int? ?? transferPort;
      debugPrint('ðŸ“¥ RequÃªte de transfert reÃ§ue de $peerIp');
    } else {
      debugPrint('âŒ IP de l\'Ã©metteur introuvable dans la requÃªte');
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
    debugPrint('Peer configurÃ©: $peerIp:$httpPort');
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
            'senderIps': _allLocalIps,
            'senderHttpPort': transferPort,
          }),
        )
        .timeout(const Duration(seconds: 10));

    _throwForBadStatus(response.statusCode, uri, 'Demande non envoyÃ©e');
  }

  Future<void> sendTransferResponse(String requestId, bool accepted) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) {
      debugPrint('âŒ Impossible de rÃ©pondre : IP de l\'Ã©metteur inconnue');
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

    _throwForBadStatus(response.statusCode, uri, 'RÃ©ponse non envoyÃ©e');
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
      'Message de contrÃ´le non envoyÃ©',
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
    Function() onComplete, {
    Function(int fileIndex, int fileSent, int fileSize)? onFileProgress,
  }) async {
    if (_currentPeerIp == null) throw Exception('Pas de peer connectÃ©');

    int totalSize = 0;
    for (final file in files) {
      totalSize += await file.length();
    }
    int totalSent = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final fileSize = await file.length();
      // Optimized: 512KB chunks for better mobile throughput
      const chunkSize = 512 * 1024;

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
          onFileProgress?.call(i, 0, fileSize);
          while (offset < fileSize) {
            final remaining = fileSize - offset;
            final toRead = chunkSize < remaining ? chunkSize : remaining;
            final bytes = await raf.read(toRead);
            if (bytes.isEmpty) break;
            streamedRequest.sink.add(bytes);
            offset += bytes.length;
            totalSent += bytes.length;
            onProgress(totalSent, totalSize);
            onFileProgress?.call(i, offset, fileSize);
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
            'Upload Ã©chouÃ© (${response.statusCode}) $body',
            uri: uri,
          );
        }
      } finally {
        client.close();
      }

      debugPrint('âœ… Fichier $i envoyÃ©: ${file.path}');
    }

    onComplete();
  }

  void dispose() {
    _signalingServer?.close(force: true);
    _transferServer?.close(force: true);
  }

  Future<Response> _handleTextMessage(Request request) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final senderName = data['senderName'] as String;
    final text = data['text'] as String;
    final timestamp = DateTime.parse(data['timestamp'] as String);

    final connectionInfo =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final requestIp = connectionInfo?.remoteAddress.address;
    if (requestIp != null && requestIp.isNotEmpty && requestIp != 'Non disponible') {
      _currentPeerIp = requestIp;
      debugPrint('ðŸ’¬ Message texte reÃ§u de $senderName ($requestIp)');
    }

    onTextMessageReceived?.call(senderName, text, timestamp);
    return Response.ok('OK');
  }

  Future<void> sendTextMessage(String text, String senderName) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) throw Exception('Pas de peer connectÃ©');

    final uri = Uri.parse('http://$peerIp:$signalingPort/text-message');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'senderName': senderName,
            'text': text,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 10));

    _throwForBadStatus(response.statusCode, uri, 'Message texte non envoyÃ©');
  }

  Future<Response> _handleDiscover(Request request) async {
    final body = jsonEncode({
      'id': _localDeviceId,
      'name': _localDeviceName,
      'os': _localDeviceOs,
      'httpPort': transferPort,
      'ip': _localIpAddress ?? '',
    });
    return Response.ok(body, headers: {'content-type': 'application/json'});
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

  String _getSubfolderForFile(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return 'files';
    }
    final ext = name.substring(dotIndex + 1).toLowerCase();

    // photos
    if (const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'svg', 'heic', 'heif'].contains(ext)) {
      return 'photos';
    }
    // videos
    if (const ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'wmv', '3gp'].contains(ext)) {
      return 'videos';
    }
    // sounds
    if (const ['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'].contains(ext)) {
      return 'sounds';
    }

    return 'files';
  }
}

