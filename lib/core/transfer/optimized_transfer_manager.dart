import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class OptimizedTransferManager {
  static const int minChunkSize = 90 * 1024; // 32 KB
  static const int maxChunkSize = 90 * 1024; // 60 KB (taille de sécurité maximale SCTP)
  static const int bufferedAmountLowThreshold = 256 * 1024; // 256 KB
  static const int bufferedAmountHighThreshold = 1024 * 1024; // 1 MB

  int _currentChunkSize = maxChunkSize; // Démarrer directement à la taille maximale de sécurité pour un débit optimal
  int _consecutiveSuccesses = 0;
  int _consecutiveFailures = 0;
  final int _maxSuccessesBeforeIncrease = 10;
  final int _maxFailuresBeforeDecrease = 3;

  final RTCDataChannel dataChannel;
  final Function(int) onProgress;
  final VoidCallback onComplete;
  final Function(double)? onSpeedUpdate;
  final Function(String)? onStatusUpdate;

  /// Callback pour que le manager reçoive les ACK sans écraser onMessage
  Function(Map<String, dynamic>)? onControlMessage;

  bool _isPaused = false;
  bool _isCancelled = false;
  DateTime? _lastSpeedUpdate;
  int _bytesSinceLastUpdate = 0;

  // Protocole résumable
  int _lastAckOffset = 0;
  Completer<void>? _ackCompleter;
  // L'attente d'ACK bloquante a été supprimée au profit du streaming en continu régulé par le buffer d'envoi

  /// ID unique du manager pour ne pas confondre les ACK
  final String _managerId = DateTime.now().microsecondsSinceEpoch.toString();
  String _currentFileName = '';

  OptimizedTransferManager({
    required this.dataChannel,
    required this.onProgress,
    required this.onComplete,
    this.onSpeedUpdate,
    this.onStatusUpdate,
  }) {
    // NE PAS toucher à dataChannel.onMessage ici !
    // Les ACK seront routés via onControlMessage
  }

  /// Route un message de contrôle vers ce manager
  /// Appelé depuis WebRTCService pour les messages 'ack'
  bool handleControlMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    
    if (type == 'ack') {
      final ackOffset = (data['offset'] is int) 
          ? data['offset'] as int 
          : int.parse(data['offset'].toString());
      
      _lastAckOffset = ackOffset;
      
      if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
        _ackCompleter!.complete();
        return true;
      }
    }
    return false;
  }

  Future<void> sendFile(File file) async {
    final fileLength = await file.length();

    int offset = _lastAckOffset;
    if (offset > fileLength) {
      offset = 0;
    }

    _lastSpeedUpdate = DateTime.now();
    _bytesSinceLastUpdate = 0;

    _currentFileName = file.path.split(Platform.pathSeparator).last;
    
    // Send start metadata
    _sendControl({
      'type': 'start',
      'fileName': _currentFileName,
      'fileSize': fileLength,
      'chunkSize': _currentChunkSize,
    });

    debugPrint('📤 Envoi fichier: $_currentFileName ($fileLength bytes) depuis offset=$offset');

    final raf = await file.open();
    try {
      while (offset < fileLength) {
        if (_isCancelled) break;

        if (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        final toRead = math.min(_currentChunkSize, fileLength - offset);

        await raf.setPosition(offset);
        final bytes = await raf.read(toRead);
        if (bytes.isEmpty) break;

        // Prefix chunk with 8-byte header
        final header = ByteData(8)..setUint64(0, offset, Endian.big);
        final out = Uint8List(8 + bytes.length);
        out.setRange(0, 8, header.buffer.asUint8List());
        out.setRange(8, 8 + bytes.length, bytes);

        // Gestion du buffer
        if ((dataChannel.bufferedAmount ?? 0) > bufferedAmountHighThreshold) {
          _onStatus('Buffer plein, attente...');
          await _waitForBufferLow();
          if (_isCancelled) break;
        }

        // Envoyer le chunk directement (WebRTC SCTP s'occupe de la fiabilité en arrière-plan)
        dataChannel.send(RTCDataChannelMessage.fromBinary(out));

        // Avancer l'offset localement
        offset += bytes.length;
        onProgress(offset);
        _bytesSinceLastUpdate += bytes.length;
        _updateSpeedMetrics();
        _adjustChunkSize(dataChannel.bufferedAmount ?? 0);

        // Laisser respirer la boucle Dart pour traiter les événements réseau
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (!_isCancelled) {
        _sendControl({
          'type': 'file_complete',
          'fileName': _currentFileName,
          'fileSize': fileLength,
        });
        debugPrint('📤 Fichier terminé: $_currentFileName');
      }
    } finally {
      await raf.close();
    }
  }

  void sendAllComplete() {
    _sendControl({'type': 'end'});
    debugPrint('📤 Tous les fichiers envoyés');
    onComplete();
  }

  void _sendControl(Map<String, dynamic> m) {
    try {
      dataChannel.send(RTCDataChannelMessage(json.encode(m)));
    } catch (e) {
      debugPrint('Error sending control: $e');
    }
  }

  Future<void> _waitForBufferLow() async {
    dataChannel.bufferedAmountLowThreshold = bufferedAmountLowThreshold;

    final completer = Completer<void>();
    dataChannel.onBufferedAmountLow = (_) {
      if (!completer.isCompleted) completer.complete();
    };

    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) completer.complete();
    });

    await completer.future;
    dataChannel.onBufferedAmountLow = null;
  }

  void _adjustChunkSize(int bufferedAmount) {
    if (bufferedAmount < bufferedAmountLowThreshold) {
      _consecutiveSuccesses++;
      _consecutiveFailures = 0;
      if (_consecutiveSuccesses >= _maxSuccessesBeforeIncrease && _currentChunkSize < maxChunkSize) {
        _currentChunkSize = (_currentChunkSize * 2).clamp(minChunkSize, maxChunkSize);
        _consecutiveSuccesses = 0;
        debugPrint('Chunk augmenté: ${_currentChunkSize ~/ 1024} KB');
      }
    } else if (bufferedAmount > bufferedAmountLowThreshold * 2) {
      _consecutiveFailures++;
      _consecutiveSuccesses = 0;
      if (_consecutiveFailures >= _maxFailuresBeforeDecrease && _currentChunkSize > minChunkSize) {
        _currentChunkSize = (_currentChunkSize ~/ 2).clamp(minChunkSize, maxChunkSize);
        _consecutiveFailures = 0;
        debugPrint('Chunk réduit: ${_currentChunkSize ~/ 1024} KB');
      }
    }
  }

  void _updateSpeedMetrics() {
    final now = DateTime.now();
    if (_lastSpeedUpdate != null) {
      final elapsed = now.difference(_lastSpeedUpdate!).inMilliseconds;
      if (elapsed >= 500) {
        final speedMBps = (_bytesSinceLastUpdate / (1024 * 1024)) / (elapsed / 1000);
        onSpeedUpdate?.call(speedMBps);
        _bytesSinceLastUpdate = 0;
        _lastSpeedUpdate = now;
      }
    }
  }

  void _onStatus(String status) {
    onStatusUpdate?.call(status);
    debugPrint(status);
  }

  void pause() {
    _isPaused = true;
    _onStatus('⏸️ Pause');
  }

  void resume() {
    _isPaused = false;
    _onStatus('▶️ Reprise');
  }

  void cancel() {
    _isCancelled = true;
    if (_ackCompleter != null && !_ackCompleter!.isCompleted) {
      _ackCompleter!.completeError(Exception('Annulé'));
    }
    _onStatus('⏹️ Annulé');
  }

  int getCurrentChunkSize() => _currentChunkSize;
  int getBufferedAmount() => dataChannel.bufferedAmount ?? 0;
  String get managerId => _managerId;
}