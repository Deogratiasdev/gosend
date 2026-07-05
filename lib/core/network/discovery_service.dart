import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/device.dart';

class DiscoveryService {
  static const int broadcastPort = 50000;
  static const Duration deviceTimeout = Duration(seconds: 10);
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool isDiscoverable = true;

  final ValueNotifier<List<Device>> discoveredDevices = ValueNotifier([]);
  final Map<String, Device> _devicesMap = {};
  final Map<String, DateTime> _lastSeenMap = {};

  final String localDeviceId;
  String localDeviceName;
  final String localOs;
  String localIpAddress;

  DiscoveryService({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localOs,
    required this.localIpAddress,
  });

  Future<void> startDiscovery() async {
    try {
      _broadcastTimer?.cancel();
      _cleanupTimer?.cancel();
      _socket?.close();

      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        broadcastPort,
      );
      _socket?.broadcastEnabled = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? datagram = _socket?.receive();
          if (datagram != null) {
            _handleIncomingDatagram(datagram);
          }
        }
      });

      _startBroadcasting();
      _startCleanupTimer();
      debugPrint('DiscoveryService started on port $broadcastPort');
    } catch (e) {
      debugPrint('Error starting DiscoveryService: $e');
    }
  }

  void _startBroadcasting() {
    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!isDiscoverable) return;

      final message = jsonEncode({
        'id': localDeviceId,
        'name': localDeviceName,
        'os': localOs,
        'port': broadcastPort,
        'httpPort': 8081, // NOUVEAU : port HTTP pour réception des fichiers
      });

      final buffer = utf8.encode(message);
      _socket?.send(buffer, InternetAddress('255.255.255.255'), broadcastPort);
    });
  }

  void toggleDiscoverability() {
    isDiscoverable = !isDiscoverable;
  }

  void updateLocalInfo({required String name, required String ipAddress}) {
    localDeviceName = name;
    localIpAddress = ipAddress;
    _removeLocalEchoes();
  }

  void _handleIncomingDatagram(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = jsonDecode(message);

      if (_isLocalDatagram(data, datagram.address.address)) return;

      final device = Device(
        id: data['id'],
        name: data['name'],
        ip: datagram.address.address,
        port: data['port'] ?? broadcastPort,
        os: data['os'] ?? 'unknown',
        httpPort: data['httpPort'] ?? 8081, // NOUVEAU
      );

      final uniqueKey = device.id;
      _devicesMap[uniqueKey] = device;
      _lastSeenMap[uniqueKey] = DateTime.now();
      _updateDiscoveredDevices();
    } catch (e) {
      debugPrint('Error parsing datagram: $e');
    }
  }

  void _updateDiscoveredDevices() {
    discoveredDevices.value = _devicesMap.values
        .where((device) => !_isLocalDevice(device))
        .toList();
  }

  bool _isLocalDatagram(Map<String, dynamic> data, String senderIp) {
    if (data['id'] == localDeviceId) return true;
    if (_isSameIp(senderIp, localIpAddress)) return true;
    return false;
  }

  bool _isLocalDevice(Device device) {
    if (device.id == localDeviceId) return true;
    if (_isSameIp(device.ip, localIpAddress)) return true;
    return false;
  }

  bool _isSameIp(String a, String b) {
    if (a.isEmpty || b.isEmpty || b == 'Non disponible') return false;
    return a == b;
  }

  void _removeLocalEchoes() {
    _devicesMap.removeWhere((_, device) => _isLocalDevice(device));
    _lastSeenMap.removeWhere((key, _) => !_devicesMap.containsKey(key));
    _updateDiscoveredDevices();
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _cleanupInactiveDevices();
    });
  }

  void _cleanupInactiveDevices() {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _lastSeenMap.entries) {
      if (now.difference(entry.value) > deviceTimeout) {
        toRemove.add(entry.key);
      }
    }

    for (final deviceId in toRemove) {
      _devicesMap.remove(deviceId);
      _lastSeenMap.remove(deviceId);
      debugPrint('Removed inactive device: $deviceId');
    }

    if (toRemove.isNotEmpty) {
      _updateDiscoveredDevices();
    }
  }

  void stopDiscovery() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    _devicesMap.clear();
    _lastSeenMap.clear();
    _updateDiscoveredDevices();
    debugPrint('DiscoveryService stopped');
  }
}
