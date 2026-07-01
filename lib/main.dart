import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'ui/theme.dart';
import 'ui/screens/home_screen.dart';
import 'core/network/discovery_service.dart';
import 'models/device.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GoSendApp());
}

class GoSendApp extends StatefulWidget {
  const GoSendApp({super.key});

  @override
  State<GoSendApp> createState() => _GoSendAppState();
}

class _GoSendAppState extends State<GoSendApp> {
  late DiscoveryService _discoveryService;
  List<Device> _devices = [];
  bool _initialized = false;
  String _localDeviceName = 'Mon appareil';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _requestPermissions();
    await _initServices();
    setState(() => _initialized = true);
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.nearbyWifiDevices,
        Permission.location,
      ].request();
    }
  }

  Future<void> _initServices() async {
    String deviceName = 'Unknown Device';
    final String os = Platform.operatingSystem;
    final String deviceId = DateTime.now().millisecondsSinceEpoch.toString();

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceName = info.model;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        deviceName = info.computerName;
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }

    _localDeviceName = deviceName;

    _discoveryService = DiscoveryService(
      localDeviceId: deviceId,
      localDeviceName: deviceName,
      localOs: os,
    );

    _discoveryService.discoveredDevices.addListener(() {
      setState(() {
        _devices = _discoveryService.discoveredDevices.value;
      });
    });

    await _discoveryService.startDiscovery();
  }

  @override
  void dispose() {
    _discoveryService.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoSend',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: _initialized
          ? HomeScreen(
              devices: _devices,
              localDeviceName: _localDeviceName,
              onRefresh: () {
                _discoveryService.stopDiscovery();
                _discoveryService.startDiscovery();
              },
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
