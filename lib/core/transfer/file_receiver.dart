import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/transfer_request.dart';

class FileReceiver {
  final Map<String, IOSink> _fileSinks = {};
  final Map<String, int> _fileSizes = {};
  final Map<String, int> _receivedBytes = {};
  final Map<String, String> _fileNames = {};
  final Map<String, String> _filePaths = {};
  final Map<String, int> _fileIndexes =
      {}; // Index du fichier dans le transfert
  String? _currentTransferId;
  int _totalFiles = 0;
  int _currentFileIndex = 0;

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
      final fileId = '${transferId}_$i'; // ID unique par fichier

      _fileSizes[fileId] = file.size;
      _receivedBytes[fileId] = 0;
      _fileNames[fileId] = file.name;
      _fileIndexes[fileId] = i;

      final filePath = '$savePath/${file.name}';
      _filePaths[fileId] = filePath;
      _fileSinks[fileId] = File(filePath).openWrite();
    }
  }

  double receiveChunk(String transferId, Uint8List chunk) {
    if (_currentTransferId != transferId) return 0.0;

    // Trouver le fichier actuel à recevoir
    final currentFileId = '${transferId}_$_currentFileIndex';

    if (_fileSinks[currentFileId] == null) {
      debugPrint('Erreur: aucun sink pour $currentFileId');
      return 0.0;
    }

    _fileSinks[currentFileId]?.add(chunk);
    _receivedBytes[currentFileId] =
        (_receivedBytes[currentFileId] ?? 0) + chunk.length;

    final totalSize = _fileSizes[currentFileId] ?? 1;
    final received = _receivedBytes[currentFileId] ?? 0;

    debugPrint('Progression fichier $_currentFileIndex: $received/$totalSize');

    return received / totalSize;
  }

  Future<String?> saveCurrentFile(String transferId) async {
    try {
      final currentFileId = '${transferId}_$_currentFileIndex';

      // Vérifier si le fichier a reçu des données
      final receivedBytes = _receivedBytes[currentFileId] ?? 0;
      if (receivedBytes == 0) {
        debugPrint('Fichier vide, suppression: $currentFileId');
        _cleanupFile(currentFileId);
        return null;
      }

      await _fileSinks[currentFileId]?.close();
      final filePath = _filePaths[currentFileId];

      _cleanupFile(currentFileId);

      // Passer au fichier suivant
      _currentFileIndex++;

      return filePath;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return null;
    }
  }

  // Garder l'ancienne méthode pour compatibilité
  Future<String?> saveFile(String transferId) async {
    return saveCurrentFile(transferId);
  }

  void _cleanupFile(String fileId) {
    _fileSinks[fileId]?.close();
    _fileSinks.remove(fileId);
    _fileSizes.remove(fileId);
    _receivedBytes.remove(fileId);
    _fileNames.remove(fileId);
    _filePaths.remove(fileId);
    _fileIndexes.remove(fileId);
  }

  void _cleanup(String transferId) {
    // Nettoyer tous les fichiers du transfert
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
}
