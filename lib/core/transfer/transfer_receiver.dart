import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../network/webrtc_service.dart';

class TransferReceiver {
  final WebRTCService webrtc;
  final String destinationPath; // chemin final du fichier (sans .part)
  final Function(int)? onProgress;
  final VoidCallback? onComplete;
  final Function(String)? onStatus;

  RandomAccessFile? _raf;
  int _expectedSize = 0;
  int _received = 0;
  String? _tempPath;

  TransferReceiver({
    required this.webrtc,
    required this.destinationPath,
    this.onProgress,
    this.onComplete,
    this.onStatus,
  }) {
    webrtc.onChunkReceived = _handleChunk;
    webrtc.onRawTextMessage = _handleTextMessage;
  }

  Future<void> _handleTextMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String?;
    if (type == 'start') {
      _expectedSize = (msg['fileSize'] is int) ? msg['fileSize'] as int : int.parse('${msg['fileSize']}');
      _tempPath = '$destinationPath.part';
      final file = File(_tempPath!);
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      _raf = await file.open(mode: FileMode.write);
      _received = 0;
      onStatus?.call('Réception démarrée ($_expectedSize octets)');
    } else if (type == 'end') {
      await _finalize();
    }
  }

  Future<void> _handleChunk(Uint8List payload, int offset) async {
    if (_raf == null) {
      // Pas initialisé (start non reçu) -> ignorer ou créer
      onStatus?.call('Chunk reçu avant start; création du fichier temporel');
      _tempPath = '$destinationPath.part';
      final file = File(_tempPath!);
      if (!file.existsSync()) await file.create(recursive: true);
      _raf = await file.open(mode: FileMode.write);
    }

    try {
      await _raf!.setPosition(offset);
      await _raf!.writeFrom(payload);
      _received += payload.length;
      onProgress?.call(_received);

      // Envoyer ack indiquant l'offset jusqu'où nous avons reçu
      final ackOffset = offset + payload.length;
      final ack = json.encode({'type': 'ack', 'offset': ackOffset});
      webrtc.dataChannel?.send(RTCDataChannelMessage(ack));

      if (_expectedSize > 0 && _received >= _expectedSize) {
        await _finalize();
      }
    } catch (e) {
      debugPrint('Erreur écriture chunk: $e');
      onStatus?.call('Erreur écriture chunk: $e');
    }
  }

  Future<void> _finalize() async {
    try {
      await _raf?.flush();
      await _raf?.close();
      if (_tempPath != null) {
        final temp = File(_tempPath!);
        if (await temp.exists()) {
          await temp.rename(destinationPath);
        }
      }
      onStatus?.call('Fichier reçu et enregistré');
      onComplete?.call();
    } catch (e) {
      debugPrint('Erreur finalisation fichier: $e');
      onStatus?.call('Erreur finalisation: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _raf?.close();
    } catch (_) {}
    webrtc.onChunkReceived = null;
    webrtc.onRawTextMessage = null;
  }
}
