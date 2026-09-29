import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../models/transfer_request.dart';

/// Levée quand l'utilisateur annule l'envoi côté envoyeur.
/// Permet à l'UI de distinguer "annulé" de "erreur réseau".
class TransferCancelled implements Exception {
  final String message;
  TransferCancelled([this.message = 'Transfer cancelled']);
  @override
  String toString() => message;
}

class HttpTransferService {
  // Ports inhabituels (hors 80xx classiques) pour éviter les collisions
  // avec d'autres apps et les scans automatiques.
  static const int signalingPort = 41731;
  static const int transferPort = 41732;

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
  String? _currentTransferId;
  int _completedReceiveBytes = 0;
  final Set<int> _completedFileIndexes = <int>{};
  final Map<int, int> _fileReceivedBytes = <int, int>{};
  /// Token par fichier, généré à l'acceptation (type LocalSend).
  /// L'upload exige le token, sinon 403.
  final Map<int, String> _fileTokens = <int, String>{};
  bool _isPaused = false;
  bool _isCancelled = false;
  Function(int, int, int)? _onProgress;
  Function(int, int, int)? _onFileProgress;
  Function(int, String)? _onFileComplete;
  Function()? _onAllComplete;

  Function(TransferRequest)? onTransferRequestReceived;
  Function(String, bool, Map<String, String>?)? onTransferResponse;
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
      })
      ..get('/progress', _handleProgress);

    final handler = const Pipeline().addHandler(router.call);
    _transferServer = await shelf_io.serve(handler, '0.0.0.0', transferPort);
    debugPrint('Transfer HTTP server on port $transferPort');
  }

  /// Prépare la réception et génère un token par fichier.
  /// Retourne les tokens (index -> token) à renvoyer à l'envoyeur
  /// dans la réponse d'acceptation.
  Map<int, String> prepareReceive(
    String transferId,
    List<FileInfo> files,
    String saveDir,
    Function(int fileIndex, int received, int total) onProgress,
    Function(int fileIndex, int fileReceived, int fileSize) onFileProgress,
    Function(int fileIndex, String filePath) onFileComplete,
    Function() onAllComplete,
  ) {
    _currentTransferId = transferId;
    _currentFiles = files;
    _currentSaveDir = saveDir;
    _completedReceiveBytes = 0;
    _completedFileIndexes.clear();
    _fileReceivedBytes.clear();
    _fileTokens.clear();
    final random = Random.secure();
    for (int i = 0; i < files.length; i++) {
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      _fileTokens[i] = base64UrlEncode(bytes);
      _fileReceivedBytes[i] = 0;
    }
    _isPaused = false;
    _isCancelled = false;
    _onProgress = onProgress;
    _onFileProgress = onFileProgress;
    _onFileComplete = onFileComplete;
    _onAllComplete = onAllComplete;
    return Map<int, String>.from(_fileTokens);
  }

  Future<Response> _handleFileUpload(Request request, int fileIndex) async {
    if (_currentFiles == null ||
        _currentSaveDir == null ||
        fileIndex < 0 ||
        fileIndex >= _currentFiles!.length) {
      return Response.badRequest(body: 'Invalid file index');
    }

    // Token exigé (sauf session legacy sans tokens).
    if (_fileTokens.isNotEmpty) {
      final token = request.url.queryParameters['token'] ??
          request.headers['x-file-token'];
      if (token == null || token != _fileTokens[fileIndex]) {
        return Response.forbidden('Invalid or missing file token');
      }
    }

    final fileInfo = _currentFiles![fileIndex];
    final fileName = _safeFileName(fileInfo.name);
    final subfolder = _getSubfolderForFile(fileName);
    final filePath = p.normalize(p.join(_currentSaveDir!, subfolder, fileName));
    // Confinement : le chemin final doit rester dans le dossier de réception.
    final saveRoot = p.normalize(p.absolute(_currentSaveDir!));
    if (!p.isWithin(saveRoot, p.absolute(filePath)) &&
        p.absolute(filePath) != saveRoot) {
      return Response.badRequest(body: 'Unsafe file path');
    }
    final file = File(filePath);
    await file.parent.create(recursive: true);

    // Écriture en .deogratias puis rename atomique (pas de partiel visible).
    final partFile = File('$filePath.deogratias');
    if (await partFile.exists()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }
    final sink = partFile.openWrite();
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
          try {
            await partFile.delete();
          } catch (_) {}
          return Response(499, body: 'Transfer cancelled');
        }
        while (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_isCancelled) {
            progressTimer?.cancel();
            await sink.close();
            try {
              await partFile.delete();
            } catch (_) {}
            return Response(499, body: 'Transfer cancelled');
          }
        }
        sink.add(chunk);
        received += chunk.length;
        _fileReceivedBytes[fileIndex] = received;

        // Throttle: max 1 rapport / 500ms et au moins 256KB d'écart.
        final shouldReport = progressTimer == null &&
            (received - lastReported > 256 * 1024 ||
             (fileInfo.size > 0 && (received - lastReported) > fileInfo.size ~/ 100));
        if (shouldReport) {
          reportProgress();
          progressTimer = Timer(const Duration(milliseconds: 500), () {
            progressTimer = null;
          });
        }
      }
      progressTimer?.cancel();

      // Final flush
      await sink.flush();
      await sink.close();

      // Rename atomique .deogratias -> final.
      try {
        if (await file.exists()) {
          await file.delete();
        }
        await partFile.rename(filePath);
      } catch (e) {
        debugPrint('Rename .deogratias error: $e');
        return Response.internalServerError(body: e.toString());
      }

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
      try {
        await sink.close();
      } catch (_) {}
      debugPrint('Receive file error: $e');
      return Response.internalServerError(body: e.toString());
    }
  }

  /// Octets réellement écrits côté receveur (vérité pour la barre d'envoi).
  /// GET /progress?sessionId=...
  Future<Response> _handleProgress(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null ||
        _currentTransferId == null ||
        sessionId != _currentTransferId ||
        _currentFiles == null) {
      return Response.badRequest(body: 'Unknown session');
    }
    final total = _currentFiles!.fold<int>(0, (sum, f) => sum + f.size);
    int totalReceived = _completedReceiveBytes;
    final files = <Map<String, dynamic>>[];
    for (int i = 0; i < _currentFiles!.length; i++) {
      final r = _fileReceivedBytes[i] ?? 0;
      if (!_completedFileIndexes.contains(i)) totalReceived += r;
      files.add({'index': i, 'received': r, 'size': _currentFiles![i].size});
    }
    return Response.ok(
      jsonEncode({
        'sessionId': sessionId,
        'totalReceived': totalReceived,
        'totalSize': total,
        'files': files,
      }),
      headers: {'content-type': 'application/json'},
    );
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
    Map<String, String>? tokens;
    final rawTokens = data['tokens'];
    if (rawTokens is Map) {
      tokens = rawTokens.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    onTransferResponse?.call(
      data['requestId'] as String,
      data['accepted'] as bool,
      tokens,
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

  Future<void> sendTransferResponse(
    String requestId,
    bool accepted, {
    Map<int, String>? tokens,
  }) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) {
      debugPrint('Cannot reply: sender IP unknown');
      return;
    }

    final uri = Uri.parse('http://$peerIp:$signalingPort/transfer-response');
    final response = await http
        .post(
          uri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'requestId': requestId,
            'accepted': accepted,
            if (tokens != null)
              'tokens': tokens.map((k, v) => MapEntry(k.toString(), v)),
          }),
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

  /// Envoi avec uploads parallèles (max 3 fichiers à la fois),
  /// chunks de 1 Mo, token par fichier.
  /// [onProgress] = octets poussés au socket (optimiste).
  /// La vérité (octets écrits) vient de [fetchAckedProgress] (P2).
  Future<void> sendFiles(
    List<File> files,
    String transferId,
    Function(int totalSent, int totalSize) onProgress,
    Function() onComplete, {
    Function(int fileIndex, int fileSent, int fileSize)? onFileProgress,
    Map<int, String>? tokens,
    int maxParallel = 3,
  }) async {
    if (_currentPeerIp == null) throw Exception('Pas de peer connecté');

    // Reset : les flags d'un transfert précédent ne doivent pas fuir ici.
    _isPaused = false;
    _isCancelled = false;

    final sizes = <int>[];
    int totalSize = 0;
    for (final file in files) {
      final s = await file.length();
      sizes.add(s);
      totalSize += s;
    }
    int totalSent = 0;

    Future<void> uploadOne(int i) async {
      final file = files[i];
      final fileSize = sizes[i];
      const chunkSize = 1024 * 1024; // 1 Mo

      var uri = Uri.parse(
        'http://$_currentPeerIp:$_currentPeerHttpPort/upload/$i',
      );
      final token = tokens?[i];
      if (token != null && token.isNotEmpty) {
        uri = uri.replace(queryParameters: {'token': token});
      }
      final streamedRequest = http.StreamedRequest('POST', uri)
        ..headers['content-type'] = 'application/octet-stream'
        ..headers['content-length'] = fileSize.toString();
      if (token != null && token.isNotEmpty) {
        streamedRequest.headers['x-file-token'] = token;
      }

      int lastSentReport = 0;
      void reportSent(int offset) {
        // Throttle envoyeur : 500ms min via écart 256KB (l'UI re-throttle aussi).
        if (offset - lastSentReport >= 256 * 1024 || offset == fileSize) {
          lastSentReport = offset;
          onFileProgress?.call(i, offset, fileSize);
        }
      }

      final sendFuture = () async {
        final raf = await file.open();
        try {
          int offset = 0;
          onFileProgress?.call(i, 0, fileSize);
          while (offset < fileSize) {
            // Cancel envoyeur : stoppe net la lecture du fichier.
            if (_isCancelled) throw TransferCancelled();
            // Pause envoyeur : attend au lieu de gaver les buffers TCP.
            while (_isPaused) {
              await Future.delayed(const Duration(milliseconds: 100));
              if (_isCancelled) throw TransferCancelled();
            }
            final remaining = fileSize - offset;
            final toRead = chunkSize < remaining ? chunkSize : remaining;
            final bytes = await raf.read(toRead);
            if (bytes.isEmpty) break;
            streamedRequest.sink.add(bytes);
            offset += bytes.length;
            totalSent += bytes.length;
            onProgress(totalSent, totalSize);
            reportSent(offset);
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
            'Upload failed (${response.statusCode}) $body',
            uri: uri,
          );
        }
      } finally {
        client.close();
      }

      debugPrint('File $i sent: ${file.path}');
    }

    // Pool de workers : maxParallel uploads simultanés.
    final queue = List<int>.generate(files.length, (i) => i);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final i = queue.removeAt(0);
        await uploadOne(i);
      }
    }
    final workers =
        List.generate(maxParallel.clamp(1, files.isEmpty ? 1 : files.length),
            (_) => worker());
    await Future.wait(workers);

    onComplete();
  }

  /// Progression acquittée côté receveur (vérité pour la barre d'envoi).
  /// Retourne (totalReceived, totalSize, perFile, perFileSize) ou null.
  Future<
      ({
        int totalReceived,
        int totalSize,
        Map<int, int> perFile,
        Map<int, int> perFileSize
      })?> fetchAckedProgress(String sessionId) async {
    final peerIp = _currentPeerIp;
    if (peerIp == null) return null;
    try {
      final uri = Uri.parse(
          'http://$peerIp:$_currentPeerHttpPort/progress?sessionId=$sessionId');
      final response =
          await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final perFile = <int, int>{};
      final perFileSize = <int, int>{};
      final files = data['files'] as List<dynamic>? ?? [];
      for (final f in files) {
        final m = f as Map<String, dynamic>;
        final idx = (m['index'] as num).toInt();
        perFile[idx] = (m['received'] as num).toInt();
        perFileSize[idx] = (m['size'] as num).toInt();
      }
      return (
        totalReceived: (data['totalReceived'] as num).toInt(),
        totalSize: (data['totalSize'] as num).toInt(),
        perFile: perFile,
        perFileSize: perFileSize,
      );
    } catch (_) {
      return null;
    }
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

