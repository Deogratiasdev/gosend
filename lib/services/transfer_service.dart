import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'file_server.dart';
import 'database_service.dart';
import 'network_service.dart';

class ConnectedDevice {
  final String name;
  final String ip;
  bool isAuthorized;
  Completer<bool>? authCompleter;

  ConnectedDevice({
    required this.name, 
    required this.ip, 
    this.isAuthorized = false,
    this.authCompleter,
  });
}

class TransferService extends ChangeNotifier {
  static final TransferService instance = TransferService._internal();
  factory TransferService() => instance;
  TransferService._internal();

  FileServer? _server;
  bool _isRunning = false;
  String? _currentIP;
  final List<ConnectedDevice> _connectedDevices = [];
  final List<Map<String, dynamic>> _sessionHistory = [];
  
  final StreamController<ConnectedDevice> _authRequestController = StreamController<ConnectedDevice>.broadcast();
  Stream<ConnectedDevice> get authRequests => _authRequestController.stream;

  bool get isRunning => _isRunning;
  String? get currentIP => _currentIP;
  List<Map<String, dynamic>> get sessionHistory => _sessionHistory;
  List<ConnectedDevice> get connectedDevices => _connectedDevices;

  Future<String> getDeviceName() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        return "${info.brand} ${info.model}";
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        return info.computerName;
      }
    } catch (_) {}
    return 'Appareil Distant';
  }

  bool isDeviceAuthorized(String ip) {
    return _connectedDevices.any((d) => d.ip == ip && d.isAuthorized);
  }

  Future<void> startServer() async {
    if (_isRunning) return;

    _currentIP = await NetworkService.getLocalIP();
    _server = FileServer(
      port: NetworkService.defaultPort,
      onFileReceived: (filename) async {
        final data = {
          'filename': filename,
          'size': 'Reçu', 
          'type': 'received',
          'timestamp': DateFormat('HH:mm').format(DateTime.now()),
          'status': 'success'
        };
        await DatabaseService.instance.insertHistory(data);
        _sessionHistory.insert(0, data);
        notifyListeners();
      },
      onAuthRequest: (deviceName, ip) {
        _connectedDevices.removeWhere((d) => d.ip == ip && !d.isAuthorized);
        final completer = Completer<bool>();
        final device = ConnectedDevice(name: deviceName, ip: ip, authCompleter: completer);
        _connectedDevices.add(device);
        _authRequestController.add(device);
        notifyListeners();
        return device;
      }
    );

    if (await _server!.start()) {
      _isRunning = true;
      notifyListeners();
    }
  }

  void authorizeDevice(String ip, bool authorized) {
    try {
      final device = _connectedDevices.firstWhere((d) => d.ip == ip);
      device.isAuthorized = authorized;
      if (device.authCompleter != null && !device.authCompleter!.isCompleted) {
        device.authCompleter!.complete(authorized);
      }
      if (!authorized) _connectedDevices.remove(device);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> stopServer() async {
    await _server?.stop();
    _server = null;
    _isRunning = false;
    _connectedDevices.clear();
    _currentIP = null;
    notifyListeners();
  }
}
