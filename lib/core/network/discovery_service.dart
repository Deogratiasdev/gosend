import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/device.dart';

class DiscoveryService {
  static const int broadcastPort = 50000;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  
  final ValueNotifier<List<Device>> discoveredDevices = ValueNotifier([]);
  final Map<String, Device> _devicesMap = {};

  final String localDeviceId;
  final String localDeviceName;
  final String localOs;

  DiscoveryService({
    required this.localDeviceId,
    required this.localDeviceName,
    required this.localOs,
  });

  Future<void> startDiscovery() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
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
      debugPrint('DiscoveryService started on port $broadcastPort');
    } catch (e) {
      debugPrint('Error starting DiscoveryService: $e');
    }
  }

  void _startBroadcasting() {
    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      final message = jsonEncode({
        'id': localDeviceId,
        'name': localDeviceName,
        'os': localOs,
        'port': broadcastPort,
      });

      final buffer = utf8.encode(message);
      _socket?.send(buffer, InternetAddress('255.255.255.255'), broadcastPort);
    });
  }

  void _handleIncomingDatagram(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final data = jsonDecode(message);

      if (data['id'] == localDeviceId) return; // Ignore own broadcast

      final device = Device(
        id: data['id'],
        name: data['name'],
        ip: datagram.address.address,
        port: data['port'] ?? broadcastPort,
        os: data['os'] ?? 'unknown',
      );

      if (!_devicesMap.containsKey(device.id)) {
        _devicesMap[device.id] = device;
        _updateDiscoveredDevices();
      }
    } catch (e) {
      debugPrint('Error parsing datagram: $e');
    }
  }

  void _updateDiscoveredDevices() {
    discoveredDevices.value = _devicesMap.values.toList();
  }

  void stopDiscovery() {
    _broadcastTimer?.cancel();
    _socket?.close();
    _devicesMap.clear();
    _updateDiscoveredDevices();
    debugPrint('DiscoveryService stopped');
  }
}
