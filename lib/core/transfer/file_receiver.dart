import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/transfer_request.dart';
import '../network/webrtc_service.dart'; // Pour envoyer les ACK

class FileReceiver {
  final Map<String, RandomAccessFile> _fileRafs = {};
  final Map<String, int> _fileSizes = {};
  final Map<String, int> _receivedBytes = {};
  final Map<String, String> _fileNames = {};
  final Map<String, String> _filePaths = {};
  final Map<String, int> _fileIndexes = {};
  String? _currentTransferId;
  int _totalFiles = 0;
  int _currentFileIndex = 0;
  WebRTCService? _webRTCService; // Référence pour envoyer les ACK

  /// Lier le service WebRTC pour envoyer les ACK
  void setWebRTCService(WebRTCService service) {
    _webRTCService = service;
  }

  /// Envoyer un accusé de réception
  void _sendAck(String transferId, int offset) {
    if (_webRTCService != null) {
      _webRTCService!.sendJson({
        'type': 'ack',
        'transferId': transferId,
        'offset': offset,
      });
    }
  }

  Future<void> startTransfer(String transferId, TransferRequest request) async {
    _currentTransferId = transferId;
    _totalFiles = request.files.length;
    _currentFileIndex = 0;

    final directory = await getApplicationDocumentsDirectory();
    final savePath = '${directory.path}/GoSend/received';
    final saveDir = Directory(savePath);

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    // Initialiser chaque fichier avec un ID unique
    for (int i = 0; i < request.files.length; i++) {
      final file = request.files[i];
      final fileId = '${transferId}_$i';

      _fileSizes[fileId] = file.size;
      _receivedBytes[fileId] = 0;
      _fileNames[fileId] = file.name;
      _fileIndexes[fileId] = i;

      final filePath = '$savePath/${file.name}';
      _filePaths[fileId] = filePath;
      // Ouvrir en mode write pour écrire aux offsets
      _fileRafs[fileId] = await File(filePath).open(mode: FileMode.write);
    }

    debugPrint('📁 Transfert initialisé: $_totalFiles fichier(s)');
  }

  /// Recevoir un chunk à un offset précis (appelé depuis WebRTCService.onChunkReceived)
  double receiveChunkAtOffset(String transferId, Uint8List chunk, int offset) {
    if (_currentTransferId != transferId) {
      debugPrint('⚠️ Transfert ID mismatch: $transferId vs $_currentTransferId');
      return 0.0;
    }

    final currentFileId = '${transferId}_$_currentFileIndex';

    if (_fileRafs[currentFileId] == null) {
      debugPrint('❌ Erreur: aucun RAF pour $currentFileId');
      return 0.0;
    }

    try {
      // Écrire à l'offset exact (permet la reprise) de façon synchrone
      _fileRafs[currentFileId]!.setPositionSync(offset);
      _fileRafs[currentFileId]!.writeFromSync(chunk);
    } catch (e) {
      debugPrint('❌ Erreur écriture offset $offset: $e');
      return 0.0;
    }

    _receivedBytes[currentFileId] =
        (_receivedBytes[currentFileId] ?? 0) + chunk.length;

    final totalSize = _fileSizes[currentFileId] ?? 1;
    final received = _receivedBytes[currentFileId] ?? 0;

    // Envoyer un ACK immédiatement
    _sendAck(transferId, offset + chunk.length);

    // Log tous les 500 KB
    if (received % (500 * 1024) == 0 || received >= totalSize) {
      debugPrint('📥 Réception: ${(received / 1024 / 1024).toStringAsFixed(1)} MB / ${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB');
    }

    return totalSize > 0 ? received / totalSize : 0.0;
  }

  /// Ancienne méthode sans offset (gardée pour compatibilité)
  double receiveChunk(String transferId, Uint8List chunk) {
    // Fallback: on écrit à la suite (offset = bytes déjà reçus)
    final currentFileId = '${transferId}_$_currentFileIndex';
    final received = _receivedBytes[currentFileId] ?? 0;
    return receiveChunkAtOffset(transferId, chunk, received);
  }

  /// Marquer un fichier comme complété et passer au suivant
  Future<String?> completeCurrentFile(String transferId) async {
    try {
      final currentFileId = '${transferId}_$_currentFileIndex';

      final receivedBytes = _receivedBytes[currentFileId] ?? 0;
      final totalSize = _fileSizes[currentFileId] ?? 0;

      // Fermer le RAF
      await _fileRafs[currentFileId]?.close();
      final filePath = _filePaths[currentFileId];

      // Vérifier si le fichier est complet
      if (receivedBytes < totalSize && totalSize > 0) {
        debugPrint('⚠️ Fichier incomplet: $receivedBytes/$totalSize bytes');
        // On continue quand même
      }

      _cleanupFile(currentFileId);

      // Envoyer ACK final pour ce fichier
      _sendAck(transferId, totalSize);

      // Passer au fichier suivant
      _currentFileIndex++;

      debugPrint('✅ Fichier complété: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Error completing file: $e');
      return null;
    }
  }

  // Garder l'ancienne méthode pour compatibilité
  Future<String?> saveCurrentFile(String transferId) async {
    return completeCurrentFile(transferId);
  }

  // Garder l'ancienne méthode pour compatibilité
  Future<String?> saveFile(String transferId) async {
    return completeCurrentFile(transferId);
  }

  void _cleanupFile(String fileId) {
    _fileRafs[fileId]?.close();
    _fileRafs.remove(fileId);
    _fileSizes.remove(fileId);
    _receivedBytes.remove(fileId);
    _fileNames.remove(fileId);
    _filePaths.remove(fileId);
    _fileIndexes.remove(fileId);
  }

  void _cleanup(String transferId) {
    for (int i = 0; i < _totalFiles; i++) {
      final fileId = '${transferId}_$i';
      _cleanupFile(fileId);
    }
    _currentTransferId = null;
    _totalFiles = 0;
    _currentFileIndex = 0;
  }

  void cancelTransfer(String transferId) {
    _cleanup(transferId);
  }

  int getCurrentFileIndex() => _currentFileIndex;
  int getTotalFiles() => _totalFiles;
  String? getCurrentFileName() {
    final currentFileId = '${_currentTransferId}_$_currentFileIndex';
    return _fileNames[currentFileId];
  }

  int getTotalReceivedBytes(String transferId) {
    int total = 0;
    for (int i = 0; i < _totalFiles; i++) {
      final fileId = '${transferId}_$i';
      total += _receivedBytes[fileId] ?? 0;
    }
    return total;
  }
}