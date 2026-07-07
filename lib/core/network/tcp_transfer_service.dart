import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// TCP-based transfer service for direct peer-to-peer file/media/text transfer.
/// Uses raw TCP sockets for lower latency and no HTTP overhead.
class TcpTransferService {
  static const int defaultPort = 9090;
  static const int signalingPort = 9091;

  ServerSocket? _server;
  ServerSocket? _signalingServer;

  String? _currentPeerIp;
  int _currentPeerPort = defaultPort;
  String? _localIpAddress;

  // Callback handlers
  Function(TcpTransferRequest)? onTransferRequestReceived;
  Function(String, bool)? onTransferResponse;
  Function(String, String)? onControlMessage;
  Function(String)? onStatusUpdate;

  // Transfer state
  final Set<int> _completedFileIndexes = <int>{};
  final Map<int, int> _fileReceivedBytes = <int, int>{};
  bool _isPaused = false;
  bool _isCancelled = false;
  int _completedReceiveBytes = 0;

  // Progress callbacks
  Function(int, int, int)? _onProgress;
  Function(int, int, int)? _onFileProgress;
  Function(int, String)? _onFileComplete;
  Function()? _onAllComplete;

  List<FileInfo>? _currentFiles;
  String? _currentSaveDir;

  TcpTransferService({String? localIpAddress})
      : _localIpAddress = localIpAddress;

  void updateLocalIpAddress(String localIpAddress) {
    _localIpAddress = localIpAddress;
  }

  Future<void> startServers() async {
    await Future.wait([_startTransferServer(), _startSignalingServer()]);
    debugPrint(
        '✅ Serveurs TCP démarrés (transfert: $defaultPort, signalisation: $signalingPort)');
  }

  Future<void> _startTransferServer() async {
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind('0.0.0.0', defaultPort);
      _server!.listen(_handleIncomingConnection);
      debugPrint('TCP server listening on port $defaultPort');
    } catch (e) {
      debugPrint('❌ Erreur démarrage serveur TCP: $e');
    }
  }

  Future<void> _startSignalingServer() async {
    if (_signalingServer != null) return;
    try {
      _signalingServer = await ServerSocket.bind('0.0.0.0', signalingPort);
      _signalingServer!.listen(_handleSignalingConnection);
      debugPrint('TCP signaling server listening on port $signalingPort');
    } catch (e) {
      debugPrint('❌ Erreur démarrage serveur signalisation TCP: $e');
    }
  }

  void _handleIncomingConnection(Socket socket) async {
    debugPrint('📥 Connexion TCP entrante de ${socket.remoteAddress.address}');
    _currentPeerIp = socket.remoteAddress.address;

    try {
      await for (final data in socket) {
        await _processIncomingData(socket, data);
      }
    } catch (e) {
      debugPrint('❌ Erreur traitement connexion: $e');
    } finally {
      socket.close();
    }
  }

  void _handleSignalingConnection(Socket socket) async {
    try {
      await for (final data in socket) {
        await _processSignalingData(socket, data);
      }
    } catch (e) {
      debugPrint('❌ Erreur signalisation: $e');
    } finally {
      socket.close();
    }
  }

  Future<void> _processIncomingData(Socket socket, Uint8List data) async {
    if (data.length < 4) return;

    // Protocol: [4 bytes message type][4 bytes data length][data]
    final messageType = _bytesToInt(data.sublist(0, 4));
    final dataLength = _bytesToInt(data.sublist(4, 8));
    final payload = data.sublist(8, 8 + dataLength);

    switch (messageType) {
      case 0x01: // File chunk
        await _handleFileChunk(socket, payload);
        break;
      case 0x02: // File metadata
        await _handleFileMetadata(socket, payload);
        break;
      case 0x03: // Transfer complete
        await _handleTransferComplete(socket);
        break;
      case 0x04: // Ping
        socket.add(utf8.encode('pong'));
        break;
    }
  }

  Future<void> _processSignalingData(Socket socket, Uint8List data) async {
    final message = utf8.decode(data);
    final json = jsonDecode(message) as Map<String, dynamic>;
    final type = json['type'] as String;

    switch (type) {
      case 'transfer_request':
        onTransferRequestReceived?.call(TcpTransferRequest.fromJson(json));
        break;
      case 'transfer_response':
        onTransferResponse?.call(
          json['requestId'] as String,
          json['accepted'] as bool,
        );
        break;
      case 'control':
        onControlMessage?.call(
          json['requestId'] as String,
          json['action'] as String,
        );
        break;
      case 'discover':
        // Discovery response
        socket.add(utf8.encode(jsonEncode({
              'type': 'discover_response',
              'ip': _localIpAddress,
              'port': defaultPort,
            })));
        break;
    }
  }

  Future<void> _handleFileChunk(Socket socket, Uint8List chunk) async {
    if (_currentFiles == null || _currentSaveDir == null) return;
    if (chunk.length < 8) return;

    final fileIndex = _bytesToInt(chunk.sublist(0, 4));
    final chunkData = chunk.sublist(4);

    if (fileIndex < 0 || fileIndex >= _currentFiles!.length) return;

    final fileInfo = _currentFiles![fileIndex];
    final fileName = _safeFileName(fileInfo.name);
    final subfolder = _getSubfolderForFile(fileName);
    final filePath = '$_currentSaveDir/$subfolder/$fileName';

    final file = File(filePath);
    await file.parent.create(recursive: true);

    final raf = await file.open(mode: FileMode.append);
    try {
      await raf.writeFrom(chunkData);
      _fileReceivedBytes[fileIndex] = (_fileReceivedBytes[fileIndex] ?? 0) + chunkData.length;

      final total = _currentFiles!.fold<int>(0, (sum, f) => sum + f.size);
      _onProgress?.call(fileIndex, _completedReceiveBytes + _fileReceivedBytes[fileIndex]!, total);
      _onFileProgress?.call(fileIndex, _fileReceivedBytes[fileIndex]!, fileInfo.size);

      // Check if this file is complete
      if (_fileReceivedBytes[fileIndex]! >= fileInfo.size) {
        _onFileComplete?.call(fileIndex, filePath);
      }

      // Send ACK
      final ack = Uint8List(8);
      _intToBytes(fileIndex, ack, 0);
      _intToBytes(chunkData.length, ack, 4);
      socket.add(ack);
    } finally {
      await raf.close();
    }
  }

  Future<void> _handleFileMetadata(Socket socket, Uint8List metadata) async {
    // Metadata contains: fileIndex(4) + totalFiles(4) + JSON file info
    if (metadata.length < 8) return;

    final fileIndex = _bytesToInt(metadata.sublist(0, 4));
    // final totalFiles = _bytesToInt(metadata.sublist(4, 8));

    debugPrint('📁 Métadonnées fichier $fileIndex reçu');
  }

  Future<void> _handleTransferComplete(Socket socket) async {
    if (_currentFiles == null) return;

    for (int i = 0; i < _currentFiles!.length; i++) {
      if (_completedFileIndexes.add(i)) {
        _completedReceiveBytes += _currentFiles![i].size;
      }
    }

    _onAllComplete?.call();
    debugPrint('✅ Transfert TCP terminé');
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

  void connectToPeer(String peerIp, {int port = defaultPort}) {
    _currentPeerIp = peerIp;
    _currentPeerPort = port;
    debugPrint('Peer TCP configuré: $peerIp:$port');
  }

  /// Send file using TCP protocol
  Future<void> sendFiles(
    List<File> files,
    String transferId,
    Function(int totalSent, int totalSize) onProgress,
    Function() onComplete, {
    Function(int fileIndex, int fileSent, int fileSize)? onFileProgress,
  }) async {
    if (_currentPeerIp == null) {
      throw Exception('Pas de peer TCP connecté');
    }

    Socket? socket;
    try {
      socket = await Socket.connect(_currentPeerIp, _currentPeerPort);
      debugPrint('✅ Connecté au peer TCP: $_currentPeerIp:$_currentPeerPort');

      int totalSize = 0;
      for (final file in files) {
        totalSize += await file.length();
      }
      int totalSent = 0;

      const chunkSize = 64 * 1024; // 64KB chunks

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final fileSize = await file.length();

        // Send metadata first
        final metadata = {
          'index': i,
          'name': file.path.split(Platform.pathSeparator).last,
          'size': fileSize,
        };
        final metadataBytes = utf8.encode(jsonEncode(metadata));
        final metaHeader = Uint8List(8 + metadataBytes.length);
        _intToBytes(0x02, metaHeader, 0); // Metadata message type
        _intToBytes(metadataBytes.length, metaHeader, 4);
        metaHeader.setRange(8, metaHeader.length, metadataBytes);
        socket.add(metaHeader);

        // Stream file in chunks
        final raf = await file.open();
        try {
          int offset = 0;
          onFileProgress?.call(i, 0, fileSize);

          while (offset < fileSize) {
            while (_isPaused) {
              await Future.delayed(const Duration(milliseconds: 100));
              if (_isCancelled) break;
            }

            if (_isCancelled) break;

            final remaining = fileSize - offset;
            final toRead = chunkSize < remaining ? chunkSize : remaining;
            final bytes = await raf.read(toRead);

            // Send chunk: type(4) + fileIndex(4) + data
            final chunk = Uint8List(8 + bytes.length);
            _intToBytes(0x01, chunk, 0); // File chunk type
            _intToBytes(i, chunk, 4);
            chunk.setRange(8, chunk.length, bytes);
            socket.add(chunk);

            offset += bytes.length;
            totalSent += bytes.length;
            onProgress(totalSent, totalSize);
            onFileProgress?.call(i, offset, fileSize);

            // Small delay to prevent overwhelming the socket
            await Future.delayed(const Duration(microseconds: 100));
          }
        } finally {
          await raf.close();
        }

        debugPrint('✅ Fichier $i envoyé via TCP: ${file.path}');
      }

      // Send completion marker
      final complete = Uint8List(4);
      _intToBytes(0x03, complete, 0);
      socket.add(complete);

      onComplete();
    } catch (e) {
      debugPrint('❌ Erreur envoi TCP: $e');
      rethrow;
    } finally {
      socket?.close();
    }
  }

  /// Send transfer request via TCP signaling
  Future<void> sendTransferRequest(TcpTransferRequest request) async {
    if (_currentPeerIp == null) return;

    Socket? socket;
    try {
      socket = await Socket.connect(_currentPeerIp, signalingPort);
      socket.add(utf8.encode(jsonEncode({
            'type': 'transfer_request',
            'requestId': request.requestId,
            'senderName': request.senderName,
            'fileCount': request.fileCount,
            'totalSize': request.totalSize,
            'senderIp': _localIpAddress,
            'senderTcpPort': defaultPort,
          })));
      await socket.flush();
    } finally {
      socket?.close();
    }
  }

  /// Send transfer response
  Future<void> sendTransferResponse(String requestId, bool accepted) async {
    if (_currentPeerIp == null) return;

    Socket? socket;
    try {
      socket = await Socket.connect(_currentPeerIp, signalingPort);
      socket.add(utf8.encode(jsonEncode({
            'type': 'transfer_response',
            'requestId': requestId,
            'accepted': accepted,
          })));
      await socket.flush();
    } finally {
      socket?.close();
    }
  }

  /// Discover peers on the network
  Future<List<DiscoveredPeer>> discoverPeers(List<String> broadcastIps) async {
    final peers = <DiscoveredPeer>[];

    for (final ip in broadcastIps) {
      Socket? socket;
      try {
        socket = await Socket.connect(ip, signalingPort,
            timeout: const Duration(seconds: 2));
        socket.add(utf8.encode(jsonEncode({'type': 'discover'})));
        await socket.flush();

        await for (final data in socket.timeout(const Duration(seconds: 2))) {
          final response = utf8.decode(data);
          final json = jsonDecode(response) as Map<String, dynamic>;
          peers.add(DiscoveredPeer(
            ip: json['ip'] as String,
            port: json['port'] as int,
          ));
        }
      } catch (_) {
        // Timeout or error, skip this IP
      } finally {
        socket?.close();
      }
    }

    return peers;
  }

  void pauseTransfer() => _isPaused = true;
  void resumeTransfer() => _isPaused = false;
  void cancelTransfer() => _isCancelled = true;

  void dispose() {
    _server?.close();
    _signalingServer?.close();
  }

  // Utility methods
  int _bytesToInt(List<int> bytes) {
    int result = 0;
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) | bytes[i];
    }
    return result;
  }

  void _intToBytes(int value, Uint8List bytes, int offset) {
    for (int i = 3; i >= 0; i--) {
      bytes[offset + i] = value & 0xFF;
      value >>= 8;
    }
  }

  String _safeFileName(String name) {
    final sanitized =
        name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? 'received_file' : sanitized;
  }

  String _getSubfolderForFile(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) {
      return 'files';
    }
    final ext = name.substring(dotIndex + 1).toLowerCase();

    if (const [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'tiff',
          'svg',
          'heic',
          'heif'
        ].contains(ext)) {
      return 'photos';
    }
    if (const [
          'mp4',
          'mkv',
          'avi',
          'mov',
          'webm',
          'flv',
          'wmv',
          '3gp'
        ].contains(ext)) {
      return 'videos';
    }
    if (const [
          'mp3',
          'wav',
          'flac',
          'aac',
          'ogg',
          'm4a',
          'wma'
        ].contains(ext)) {
      return 'sounds';
    }

    return 'files';
  }
}

/// File information for transfer
class FileInfo {
  final String name;
  final int size;

  const FileInfo({required this.name, required this.size});
}

/// TCP transfer request
class TcpTransferRequest {
  final String requestId;
  final String senderName;
  final int fileCount;
  final int totalSize;
  final String senderIp;
  final int senderTcpPort;

  TcpTransferRequest({
    required this.requestId,
    required this.senderName,
    required this.fileCount,
    required this.totalSize,
    required this.senderIp,
    required this.senderTcpPort,
  });

  factory TcpTransferRequest.fromJson(Map<String, dynamic> json) {
    return TcpTransferRequest(
      requestId: json['requestId'] as String,
      senderName: json['senderName'] as String,
      fileCount: json['fileCount'] as int,
      totalSize: json['totalSize'] as int,
      senderIp: json['senderIp'] as String,
      senderTcpPort: json['senderTcpPort'] as int,
    );
  }
}

/// Discovered peer info
class DiscoveredPeer {
  final String ip;
  final int port;

  DiscoveredPeer({required this.ip, required this.port});
}
