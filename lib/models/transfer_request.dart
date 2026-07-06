class TransferRequest {
  final String id;
  final String senderId;
  final String senderName;
  final List<FileInfo> files;
  final DateTime timestamp;
  TransferStatus status;

  TransferRequest({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.files,
    required this.timestamp,
    this.status = TransferStatus.pending,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'senderName': senderName,
      'files': files.map((f) => f.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
      'status': status.toString(),
    };
  }

  factory TransferRequest.fromJson(Map<String, dynamic> json) {
    return TransferRequest(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      files: (json['files'] as List)
          .map((f) => FileInfo.fromJson(f as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: TransferStatus.values.firstWhere(
        (e) => e.toString() == json['status'],
        orElse: () => TransferStatus.pending,
      ),
    );
  }
}

class FileInfo {
  final String name;
  final int size;
  final String type;

  FileInfo({
    required this.name,
    required this.size,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'size': size,
      'type': type,
    };
  }

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] as String,
      size: json['size'] as int,
      type: json['type'] as String,
    );
  }
}

class TextMessage {
  final String senderName;
  final String text;
  final DateTime timestamp;

  TextMessage({
    required this.senderName,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'senderName': senderName,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory TextMessage.fromJson(Map<String, dynamic> json) {
    return TextMessage(
      senderName: json['senderName'] as String,
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

enum TransferStatus {
  pending,
  accepted,
  rejected,
  transferring,
  completed,
  failed,
}
