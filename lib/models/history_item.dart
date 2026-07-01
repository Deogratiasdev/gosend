class HistoryItem {
  final String id;
  final String type; // 'send' or 'receive'
  final String peerName;
  final String fileName;
  final String filePath;
  final int size;
  final int timestamp;
  final String status; // 'completed', 'cancelled'

  HistoryItem({
    required this.id,
    required this.type,
    required this.peerName,
    required this.fileName,
    required this.filePath,
    required this.size,
    required this.timestamp,
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'peerName': peerName,
      'fileName': fileName,
      'filePath': filePath,
      'size': size,
      'timestamp': timestamp,
      'status': status,
    };
  }

  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'] as String,
      type: map['type'] as String,
      peerName: map['peerName'] as String,
      fileName: map['fileName'] as String,
      filePath: map['filePath'] as String,
      size: map['size'] as int,
      timestamp: map['timestamp'] as int,
      status: map['status'] as String,
    );
  }
}
