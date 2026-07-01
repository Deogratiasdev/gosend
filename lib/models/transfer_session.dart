import 'package:flutter/foundation.dart';
import 'device.dart';

enum TransferState {
  idle,
  connecting,
  transferring,
  completed,
  failed,
}

class TransferSession {
  final String sessionId;
  final Device peer;
  final bool isHost;
  final String fileName;
  final int fileSize;
  
  ValueNotifier<TransferState> state = ValueNotifier(TransferState.idle);
  ValueNotifier<double> progress = ValueNotifier(0.0);
  ValueNotifier<int> bytesTransferred = ValueNotifier(0);
  ValueNotifier<double> speedMbPerSec = ValueNotifier(0.0);
  String? errorMessage;

  TransferSession({
    required this.sessionId,
    required this.peer,
    required this.isHost,
    required this.fileName,
    required this.fileSize,
  });

  void updateState(TransferState newState) {
    state.value = newState;
  }

  void updateProgress(int transferred) {
    bytesTransferred.value = transferred;
    progress.value = fileSize > 0 ? transferred / fileSize : 0.0;
  }
}
