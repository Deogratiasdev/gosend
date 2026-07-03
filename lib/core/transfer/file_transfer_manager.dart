import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileTransferManager {
  static const int chunkSize = 256 * 1024; // 256 KB

  final Function(Uint8List) sendDataCallback;
  final Function(int) onProgress;
  final VoidCallback onComplete;

  FileTransferManager({
    required this.sendDataCallback,
    required this.onProgress,
    required this.onComplete,
  });

  Future<void> sendFile(File file) async {
    final fileLength = await file.length();
    final stream = file.openRead();
    int offset = 0;

    await for (final chunk in stream) {
      sendDataCallback(Uint8List.fromList(chunk));
      offset += chunk.length;
      onProgress(offset);
      // Small delay to prevent overwhelming the WebRTC buffer
      await Future.delayed(const Duration(milliseconds: 5));
    }

    debugPrint('Sent ${fileLength}B in total');
    onComplete();
  }

  // Receive logic
  File? _receivingFile;
  IOSink? _fileSink;
  int _receivedBytes = 0;

  Future<void> handleIncomingData(Uint8List data, String fileName) async {
    if (_fileSink == null) {
      final dir = await getDownloadsDirectory();
      final goSendDir = Directory('${dir?.path}/GoSend');
      if (!await goSendDir.exists()) {
        await goSendDir.create(recursive: true);
      }
      final savePath = '${goSendDir.path}/$fileName';
      _receivingFile = File(savePath);
      _fileSink = _receivingFile!.openWrite();
    }

    _fileSink?.add(data);
    _receivedBytes += data.length;
    onProgress(_receivedBytes);
  }

  Future<void> finishReceiving() async {
    await _fileSink?.close();
    _fileSink = null;
    onComplete();
  }
}
