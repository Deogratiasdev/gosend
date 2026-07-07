import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:window_manager/window_manager.dart';

import 'core/network/discovery_service.dart';
import 'core/network/network_util.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/theme_service.dart';
import 'models/device.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure window for desktop platforms
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const WindowOptions windowOptions = WindowOptions(
      size: Size(1100, 720),
      minimumSize: Size(800, 550),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'GoSend',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setBackgroundColor(Colors.transparent);
    });
  }

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
  String _localDeviceId = '';
  String _localOs = '';
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

  /// Récupère le nom de l'appareil et l'IP locale actuelle.
  ///
  /// CAS CRITIQUE : téléphone connecté au WiFi ET hotspot actif.
  /// getWifiIP() retourne l'IP WiFi (ex: 192.168.1.100) mais les clients
  /// hotspot ne peuvent joindre que l'IP hotspot (ex: 192.168.43.1).
  /// On détecte donc si on est hôte hotspot et on override l'IP.
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

    // Fallback : getWifiIP() retourne souvent null en mode hotspot Android
    // (interface STA éteinte). On énumère alors les interfaces pour trouver
    // l'IP hotspot (ex: 192.168.43.1).
    if (ipAddress.isEmpty || ipAddress == 'Non disponible') {
      ipAddress = await NetworkUtil.detectLocalIp();
    }

    // CAS WiFi + Hotspot : getWifiIP() retourne l'IP WiFi, mais si on est
    // aussi hôte hotspot, les clients hotspot ne peuvent joindre que l'IP
    // hotspot. On détecte et override.
    if (ipAddress != 'Non disponible' && await NetworkUtil.isHotspotHost()) {
      final hotspotIp = await NetworkUtil.detectLocalIp();
      if (hotspotIp != 'Non disponible' && hotspotIp != ipAddress) {
        debugPrint('Hotspot détecté : override IP $ipAddress → $hotspotIp');
        ipAddress = hotspotIp;
      }
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
      _discoveryService.updateLocalInfo(name: info.name, ipAddress: info.ip);
      // Redémarre la découverte avec la nouvelle IP/nom
      await _discoveryService.stopDiscovery();
      await _discoveryService.startDiscovery();
    }
  }

  Future<void> _initServices() async {
    final String os = Platform.operatingSystem;

    // ID persistant : genere une fois, stocke dans SharedPreferences.
    // Survit aux redemarrages -> identification fiable meme en multi-interface.
    final prefs = await SharedPreferences.getInstance();
    String deviceId = prefs.getString('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('device_id', deviceId);
    }

    _localOs = os;
    _localDeviceId = deviceId;

    final info = await _fetchNetworkInfo();
    _localDeviceName = info.name;
    _localIpAddress = info.ip;

    _discoveryService = DiscoveryService(
      localDeviceId: deviceId,
      localDeviceName: info.name,
      localOs: os,
      localIpAddress: info.ip,
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
    return ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'GoSend',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeService.materialThemeMode,
            home: _initialized
                ? HomeScreen(
                    devices: _devices,
                    localDeviceName: _localDeviceName,
                    localIpAddress: _localIpAddress,
                    localDeviceId: _localDeviceId,
                    localOs: _localOs,
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
                      _discoveryService.updateLocalInfo(
                        name: info.name,
                        ipAddress: info.ip,
                      );
                      await _discoveryService.stopDiscovery();
                      await _discoveryService.startDiscovery();
                    },
                  )
                : const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ),
          );
        },
      ),
    );
  }
}
