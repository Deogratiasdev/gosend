import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'ui/theme.dart';
import 'ui/screens/home_screen.dart';
import 'core/network/discovery_service.dart';
import 'core/notifications/notification_service.dart';
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
  String _localIpAddress = 'En cours...';
  Timer? _networkMonitorTimer;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      await _requestPermissions();
    } catch (e) {
      debugPrint('Permissions error: $e');
    }

    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint('Notification init error: $e');
    }

    try {
      await _initServices();
    } catch (e) {
      debugPrint('Services init error: $e');
    }

    // Surveille l'IP et le nom toutes les 10 secondes
    _networkMonitorTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkNetworkChange();
    });

    if (mounted) {
      setState(() => _initialized = true);
    }
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

  /// Récupère le nom de l'appareil et l'IP Wi-Fi actuels
  Future<({String name, String ip})> _fetchNetworkInfo() async {
    String deviceName = _localDeviceName;
    String ipAddress = 'Non disponible';

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

    try {
      final info = NetworkInfo();
      ipAddress = await info.getWifiIP() ?? 'Non disponible';
    } catch (e) {
      debugPrint('Error getting IP: $e');
    }

    return (name: deviceName, ip: ipAddress);
  }

  /// Vérifie si IP ou nom ont changé et redémarre la découverte si nécessaire
  Future<void> _checkNetworkChange() async {
    final info = await _fetchNetworkInfo();
    final bool changed =
        info.ip != _localIpAddress || info.name != _localDeviceName;

    if (changed) {
      debugPrint('Réseau changé → IP: ${info.ip}, Nom: ${info.name}');
      if (mounted) {
        setState(() {
          _localIpAddress = info.ip;
          _localDeviceName = info.name;
        });
      }
      // Redémarre la découverte avec la nouvelle IP/nom
      _discoveryService.stopDiscovery();
      await _discoveryService.startDiscovery();
    }
  }

  Future<void> _initServices() async {
    final String os = Platform.operatingSystem;
    final String deviceId = DateTime.now().millisecondsSinceEpoch.toString();

    final info = await _fetchNetworkInfo();
    _localDeviceName = info.name;
    _localIpAddress = info.ip;

    _discoveryService = DiscoveryService(
      localDeviceId: deviceId,
      localDeviceName: info.name,
      localOs: os,
    );

    _discoveryService.discoveredDevices.addListener(() {
      if (mounted) {
        setState(() {
          _devices = _discoveryService.discoveredDevices.value;
        });
      }
    });

    await _discoveryService.startDiscovery();
  }

  @override
  void dispose() {
    _networkMonitorTimer?.cancel();
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
              localIpAddress: _localIpAddress,
              discoveryService: _discoveryService,
              onRefresh: () async {
                // Rafraîchissement manuel : met à jour IP + nom + redémarre découverte
                final info = await _fetchNetworkInfo();
                if (mounted) {
                  setState(() {
                    _localIpAddress = info.ip;
                    _localDeviceName = info.name;
                  });
                }
                _discoveryService.stopDiscovery();
                await _discoveryService.startDiscovery();
              },
            )
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
