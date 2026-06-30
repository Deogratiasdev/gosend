import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/connection_client.dart';
import '../services/network_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WindowListener {
  static const Color _accentGreen = Color(0xFF336B4E);
  static const Color _bgDark = Color(0xFF0D0D0D);
  static const Color _textSecondary = Color(0xFFCCCCCC);

  String _localIP = 'Non connecté';
  String _connectedDeviceName = '';
  String _connectedDeviceIP = '';
  bool _isConnected = false;
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  late final AnimationController _headerController;
  late final AnimationController _contentController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }

    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _headerController,
            curve: Curves.easeOutCubic,
          ),
        );

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _contentFade = CurvedAnimation(
      parent: _contentController,
      curve: Curves.easeOut,
    );

    _startAnimations();
    _checkConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((_) {
      _checkConnectivity();
    });
  }

  void _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 150));
    _headerController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _contentController.forward();
  }

  Future<void> _checkConnectivity() async {
    try {
      String? ip;

      if (Platform.isAndroid || Platform.isIOS) {
        final wifiName = await _networkInfo.getWifiName();
        final wifiIP = await _networkInfo.getWifiIP();
        if (wifiName != null && wifiName.isNotEmpty) {
          ip = wifiIP;
        }
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Pour PC, essayer d'obtenir l'IP locale via network_info_plus
        ip = await _networkInfo.getWifiIP();
      }

      if (mounted) {
        setState(() {
          _localIP = ip ?? 'Non connecté';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localIP = 'Non connecté';
        });
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    _headerController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sh = MediaQuery.of(context).size.height;
    final pad = sh < 700
        ? 16.0
        : sh > 900
        ? 24.0
        : 20.0;

    return Scaffold(
      backgroundColor: _bgDark,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: sh * 0.02),
              SlideTransition(
                position: _headerSlide,
                child: FadeTransition(
                  opacity: _headerFade,
                  child: _buildTitle(),
                ),
              ),
              SizedBox(height: sh * 0.02),
              Expanded(
                child: FadeTransition(
                  opacity: _contentFade,
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return const SizedBox.shrink();
  }

  Widget _buildContent() {
    return Column(
      children: [
        const SizedBox(height: 6),
        _buildModeButtons(),
        const Spacer(),
        _buildNoDeviceBubble(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildModeButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _discreteButton(
                Icons.link_rounded,
                'Connecter',
                _showConnectionDialog,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildIPDisplay(),
      ],
    );
  }

  Widget _discreteButton(IconData icon, String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _accentGreen, size: 18),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIPDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.wifi_rounded,
            color: _localIP != 'Non connecté'
                ? _accentGreen
                : _textSecondary.withValues(alpha: 0.5),
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _localIP,
              style: GoogleFonts.inter(
                color: _localIP != 'Non connecté'
                    ? Colors.white
                    : _textSecondary.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          GestureDetector(
            onTap: _checkConnectivity,
            child: Icon(
              Icons.refresh_rounded,
              color: _textSecondary.withValues(alpha: 0.5),
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _showConnectionDialog() {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: _bgDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mode de connexion',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 24),
              _connectionOption(
                Icons.wifi_rounded,
                'Par WiFi',
                'Les deux appareils sont sur le même réseau WiFi',
                () {
                  Navigator.pop(context);
                  _showIPInputDialog();
                },
                showIconInTitle: true,
              ),
              SizedBox(height: 12),
              _connectionOption(
                Icons.router_rounded,
                'Par Hotspot',
                'Se connecter au hotspot de l\'un ou l\'autre appareil',
                () {
                  Navigator.pop(context);
                },
                showIconInTitle: true,
              ),
              SizedBox(height: 16),
            ],
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _bgDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Mode de connexion',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _connectionOption(
                Icons.wifi_rounded,
                'Par WiFi',
                'Les deux appareils sont sur le même réseau WiFi',
                () {
                  Navigator.pop(context);
                  _showIPInputDialog();
                },
                showIconInTitle: true,
              ),
              const SizedBox(height: 12),
              _connectionOption(
                Icons.router_rounded,
                'Par Hotspot',
                'Se connecter au hotspot de l\'un ou l\'autre appareil',
                () {
                  Navigator.pop(context);
                },
                showIconInTitle: true,
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showIPInputDialog() {
    final controller = TextEditingController();
    final isMobile = Platform.isAndroid || Platform.isIOS;

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => Container(
          decoration: BoxDecoration(
            color: _bgDark,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Adresse IP du destinataire',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Entrez l\'adresse IP de l\'appareil auquel vous souhaitez vous connecter',
                style: GoogleFonts.inter(color: _textSecondary, fontSize: 14),
              ),
              SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: '192.168.1.100',
                  hintStyle: GoogleFonts.inter(
                    color: _textSecondary.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (controller.text.isNotEmpty) {
                      Navigator.pop(context);
                      _sendConnectionRequest(controller.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Connecter',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
            ],
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _bgDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Adresse IP du destinataire',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entrez l\'adresse IP de l\'appareil auquel vous souhaitez vous connecter',
                style: GoogleFonts.inter(color: _textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: '192.168.1.100',
                  hintStyle: GoogleFonts.inter(
                    color: _textSecondary.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Annuler',
                style: GoogleFonts.inter(color: _textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.pop(context);
                  _sendConnectionRequest(controller.text);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Connecter',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _sendConnectionRequest(String targetIP) async {
    // Vérifier si l'IP est valide
    if (!NetworkService.isValidIP(targetIP)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Adresse IP invalide'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Vérifier si l'appareil est accessible
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vérification de l\'appareil...'),
          backgroundColor: _accentGreen,
        ),
      );
    }

    final isReachable = await ConnectionClient.isDeviceReachable(targetIP);
    if (!isReachable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appareil non accessible ou hors ligne'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Obtenir le nom de l'appareil
    String deviceName = 'Appareil';
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceName = androidInfo.model;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceName = iosInfo.model;
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfo.windowsInfo;
        deviceName = windowsInfo.computerName;
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        deviceName = macInfo.computerName;
      } else if (Platform.isLinux) {
        deviceName = 'PC Linux';
      }
    } catch (e) {
      deviceName = 'Appareil';
    }

    // Envoyer la demande de connexion réelle
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Envoi de la demande de connexion...'),
          backgroundColor: _accentGreen,
        ),
      );
    }

    final authorized = await ConnectionClient.sendConnectionRequest(
      targetIP,
      deviceName,
    );

    if (mounted) {
      if (authorized) {
        setState(() {
          _connectedDeviceIP = targetIP;
          _connectedDeviceName = 'Appareil distant';
          _isConnected = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connexion acceptée !'),
            backgroundColor: _accentGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connexion refusée'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _disconnect() {
    setState(() {
      _isConnected = false;
      _connectedDeviceName = '';
      _connectedDeviceIP = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Déconnecté'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Widget _connectionOption(
    IconData icon,
    String title,
    String desc,
    VoidCallback onTap, {
    bool showIconInTitle = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            if (!showIconInTitle)
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _accentGreen, size: 20),
              ),
            if (!showIconInTitle) SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showIconInTitle)
                        Icon(icon, color: _accentGreen, size: 20),
                      if (showIconInTitle) SizedBox(width: 8),
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      color: _textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: _textSecondary.withValues(alpha: 0.5),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDeviceBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _isConnected
            ? _accentGreen.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected
                ? Icons.check_circle_rounded
                : Icons.devices_other_rounded,
            color: _isConnected
                ? _accentGreen
                : _textSecondary.withValues(alpha: 0.5),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected
                ? 'Connecté: $_connectedDeviceName ($_connectedDeviceIP)'
                : 'Aucun appareil connecté',
            style: GoogleFonts.inter(
              color: _isConnected
                  ? _accentGreen
                  : _textSecondary.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (_isConnected) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _disconnect,
              child: Icon(
                Icons.close_rounded,
                color: _textSecondary.withValues(alpha: 0.5),
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
