import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class OptimizedTransferManager {
  // Tailles de chunks adaptatives
  static const int minChunkSize = 256 * 1024; // 256 KB
  static const int maxChunkSize = 2 * 1024 * 1024; // 2 MB
  static const int bufferedAmountLowThreshold = 4 * 1024 * 1024; // 4 MB
  static const int bufferedAmountHighThreshold = 16 * 1024 * 1024; // 16 MB

  int _currentChunkSize = minChunkSize;
  int _consecutiveSuccesses = 0;
  int _consecutiveFailures = 0;
  final int _maxSuccessesBeforeIncrease = 10;
  final int _maxFailuresBeforeDecrease = 3;

  final RTCDataChannel dataChannel;
  final Function(int) onProgress;
  final VoidCallback onComplete;
  final Function(double)? onSpeedUpdate;
  final Function(String)? onStatusUpdate;

  bool _isPaused = false;
  bool _isCancelled = false;
  DateTime? _lastSpeedUpdate;
  int _bytesSinceLastUpdate = 0;

  OptimizedTransferManager({
    required this.dataChannel,
    required this.onProgress,
    required this.onComplete,
    this.onSpeedUpdate,
    this.onStatusUpdate,
  });

  Future<void> sendFile(File file) async {
    final fileLength = await file.length();
    int offset = 0;
    _lastSpeedUpdate = DateTime.now();
    _bytesSinceLastUpdate = 0;

    final raf = await file.open(mode: FileMode.read);

    while (offset < fileLength && !_isCancelled) {
      if (_isPaused) {
        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // Vérifier le buffer WebRTC
      if (dataChannel.bufferedAmount != null &&
          dataChannel.bufferedAmount! > bufferedAmountHighThreshold) {
        _onStatus('Buffer plein, attente...');
        await _waitForBufferLow();
        if (_isCancelled) break;
      }

      // Calculer la taille du chunk à lire
      final remainingBytes = fileLength - offset;
      final chunkSize = _currentChunkSize > remainingBytes
          ? remainingBytes
          : _currentChunkSize;

      // Lecture du chunk avec openRead pour un streaming efficace
      final chunk = await raf.read(chunkSize);
      if (chunk.isEmpty) break;

      // Envoi via WebRTC
      dataChannel.send(
        RTCDataChannelMessage.fromBinary(Uint8List.fromList(chunk)),
      );

      offset += chunk.length;
      _bytesSinceLastUpdate += chunk.length;
      onProgress(offset);

      // Mise à jour des métriques de vitesse
      _updateSpeedMetrics();

      // Ajustement adaptatif de la taille des chunks
      _adjustChunkSize(dataChannel.bufferedAmount ?? 0);
    }

    await raf.close();

    if (!_isCancelled) {
      debugPrint('Transfert terminé: $fileLength octets');
      onComplete();
    }
  }

  Future<void> _waitForBufferLow() async {
    if (dataChannel.bufferedAmountLowThreshold == null) {
      dataChannel.bufferedAmountLowThreshold = bufferedAmountLowThreshold;
    }

    final completer = Completer<void>();

    dataChannel.onBufferedAmountLow = (_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    };

    // Timeout de sécurité
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await completer.future;

    // Restaurer le callback original
    dataChannel.onBufferedAmountLow = null;
  }

  void _adjustChunkSize(int bufferedAmount) {
    // Si le buffer est faible, on peut augmenter la taille des chunks
    if (bufferedAmount < bufferedAmountLowThreshold) {
      _consecutiveSuccesses++;
      _consecutiveFailures = 0;

      if (_consecutiveSuccesses >= _maxSuccessesBeforeIncrease &&
          _currentChunkSize < maxChunkSize) {
        _currentChunkSize = (_currentChunkSize * 2).clamp(
          minChunkSize,
          maxChunkSize,
        );
        _consecutiveSuccesses = 0;
        debugPrint('Chunk size augmenté à ${_currentChunkSize ~/ 1024} KB');
      }
    }
    // Si le buffer est élevé, on réduit la taille des chunks
    else if (bufferedAmount > bufferedAmountLowThreshold * 2) {
      _consecutiveFailures++;
      _consecutiveSuccesses = 0;

      if (_consecutiveFailures >= _maxFailuresBeforeDecrease &&
          _currentChunkSize > minChunkSize) {
        _currentChunkSize = (_currentChunkSize ~/ 2).clamp(
          minChunkSize,
          maxChunkSize,
        );
        _consecutiveFailures = 0;
        debugPrint('Chunk size réduit à ${_currentChunkSize ~/ 1024} KB');
      }
    }
  }

  void _updateSpeedMetrics() {
    final now = DateTime.now();
    if (_lastSpeedUpdate != null) {
      final elapsed = now.difference(_lastSpeedUpdate!).inMilliseconds;
      if (elapsed >= 500) {
        // Mise à jour toutes les 500ms
        final speedMBps =
            (_bytesSinceLastUpdate / (1024 * 1024)) / (elapsed / 1000);
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
    _onStatus('Transfert en pause');
  }

  void resume() {
    _isPaused = false;
    _onStatus('Transfert repris');
  }

  void cancel() {
    _isCancelled = true;
    _onStatus('Transfert annulé');
  }

  int getCurrentChunkSize() => _currentChunkSize;
  int getBufferedAmount() => dataChannel.bufferedAmount ?? 0;
}
