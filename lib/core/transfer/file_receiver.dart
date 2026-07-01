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
  String? _currentTransferId;

  Future<void> startTransfer(String transferId, TransferRequest request) async {
    _currentTransferId = transferId;
    final directory = await getApplicationDocumentsDirectory();
    final savePath = '${directory.path}/GoSend/received';
    final saveDir = Directory(savePath);

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    for (final file in request.files) {
      _fileSizes[transferId] = file.size;
      _receivedBytes[transferId] = 0;
      _fileNames[transferId] = file.name;

      final filePath = '$savePath/${file.name}';
      _filePaths[transferId] = filePath;
      _fileSinks[transferId] = File(filePath).openWrite();
    }
  }

  double receiveChunk(String transferId, Uint8List chunk) {
    if (_currentTransferId != transferId) return 0.0;

    _fileSinks[transferId]?.add(chunk);
    _receivedBytes[transferId] = (_receivedBytes[transferId] ?? 0) + chunk.length;

    final totalSize = _fileSizes[transferId] ?? 1;
    final received = _receivedBytes[transferId] ?? 0;
    return received / totalSize;
  }

  Future<String?> saveFile(String transferId) async {
    try {
      await _fileSinks[transferId]?.close();
      final filePath = _filePaths[transferId];

      _cleanup(transferId);
      return filePath;
    } catch (e) {
      debugPrint('Error saving file: $e');
      return null;
    }
  }

  void _cleanup(String transferId) {
    _fileSinks[transferId]?.close();
    _fileSinks.remove(transferId);
    _fileSizes.remove(transferId);
    _receivedBytes.remove(transferId);
    _fileNames.remove(transferId);
    _filePaths.remove(transferId);
    if (_currentTransferId == transferId) {
      _currentTransferId = null;
    }
  }

  void cancelTransfer(String transferId) {
    _cleanup(transferId);
  }
}
