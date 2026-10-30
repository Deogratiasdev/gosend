class Device {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String os;
  final int httpPort; // port du serveur HTTP de réception des fichiers

  Device({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.os,
    this.httpPort = 41732,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'os': os,
      'httpPort': httpPort,
    };
  }

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      os: json['os'] as String,
      httpPort: json['httpPort'] ?? 41732,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Device &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
