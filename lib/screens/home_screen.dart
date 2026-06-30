import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../services/connection_client.dart';
import '../services/network_service.dart';
import '../services/transfer_service.dart';
import '../core/widgets/notification_system.dart';
import '../core/widgets/right_panel.dart';
import '../core/widgets/send_files_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WindowListener {
  static const Color _accentGreen = Color(0xFF1ABC9C); // Plus vibrant pour le mode Pro
  static const Color _bgDark = Color(0xFF0A0A0A);
  static const Color _cardDark = Color(0xFF151515);
  static const Color _textSecondary = Color(0xFFA0A0A0);

  String _localIP = 'Non connecté';
  String _connectedDeviceName = '';
  String _connectedDeviceIP = '';
  bool _isConnected = false;
  int _currentPageIndex = 0;
  
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<ConnectedDevice>? _authSubscription;
  StreamSubscription<List<SharedMediaFile>>? _intentDataStreamSubscription;
  List<SharedMediaFile> _sharedFiles = [];

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

    _authSubscription = TransferService.instance.authRequests.listen(_handleAuthRequest);

    // Initialisation Share Intent
    if (Platform.isAndroid || Platform.isIOS) {
      // Pour les partages entrants pendant que l'app est en mémoire
      _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
          _handleSharedFiles(value);
        }, 
        onError: (err) {
          print("getIntentDataStream error: $err");
        }
      );

      // Pour le partage au lancement de l'application
      ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _handleSharedFiles(value);
        }
        ReceiveSharingIntent.instance.reset();
      });
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> sharedFiles) {
    if (sharedFiles.isEmpty) return;
    setState(() {
      _sharedFiles = sharedFiles;
    });

    if (_isConnected) {
      // Si connecté, on va directement à la page d'envoi
      setState(() {
        _currentPageIndex = 1;
      });
      NotificationOverlay.success(
        context,
        title: 'Fichiers reçus',
        message: 'Prêt à envoyer les fichiers partagés.',
      );
    } else {
      // Sinon, on demande l'IP pour se connecter
      _showIPInputDialog(isFromShare: true);
    }
  }

  void _handleAuthRequest(ConnectedDevice device) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _accentGreen.withValues(alpha: 0.3), width: 1),
        ),
        title: Text(
          'Demande de connexion',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'L\'appareil "${device.name}" (IP: ${device.ip}) souhaite se connecter.',
          style: GoogleFonts.inter(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              TransferService.instance.authorizeDevice(device.ip, false);
              Navigator.pop(context);
            },
            child: Text('Refuser', style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              TransferService.instance.authorizeDevice(device.ip, true);
              setState(() {
                _isConnected = true;
                _connectedDeviceName = device.name;
                _connectedDeviceIP = device.ip;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Accepter', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
    _authSubscription?.cancel();
    _intentDataStreamSubscription?.cancel();
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
    final sw = MediaQuery.of(context).size.width;
    final isMobile = sw < 900 || Platform.isAndroid || Platform.isIOS;
    final isPC = !isMobile;

    return Scaffold(
      backgroundColor: _bgDark,
      body: SafeArea(
        child: Stack(
          children: [
            // Effets de lumière ambiante
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accentGreen.withValues(alpha: 0.1),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
            
            _currentPageIndex == 0
                ? _buildMainPage(sh, sw, isPC, isMobile)
                : _buildSendPage(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainPage(double sh, double sw, bool isPC, bool isMobile) {
    final pad = sh < 700 ? 16.0 : sh > 900 ? 24.0 : 20.0;

    if (isPC) {
      return Row(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: sh * 0.04),
                  SlideTransition(
                    position: _headerSlide,
                    child: FadeTransition(
                      opacity: _headerFade,
                      child: _buildTitle(),
                    ),
                  ),
                  SizedBox(height: sh * 0.04),
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
          RightPanel(
            localIP: _localIP,
            isServerRunning: TransferService.instance.isRunning,
            onToggleServer: _toggleServer,
            onRefreshIP: _checkConnectivity,
            connectedDeviceName: _isConnected ? _connectedDeviceName : null,
            connectedDeviceIP: _isConnected ? _connectedDeviceIP : null,
          ),
        ],
      );
    } else {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: sh * 0.04),
            SlideTransition(
              position: _headerSlide,
              child: FadeTransition(
                opacity: _headerFade,
                child: _buildTitle(),
              ),
            ),
            SizedBox(height: sh * 0.04),
            Expanded(
              child: FadeTransition(
                opacity: _contentFade,
                child: _buildContent(),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSendPage() {
    return SendFilesPage(
      deviceName: _connectedDeviceName,
      deviceIP: _connectedDeviceIP,
      initialFiles: _sharedFiles.map((e) => e.path).toList(),
      onSendFiles: () {
        setState(() {
          _currentPageIndex = 0;
          _sharedFiles.clear(); // Reset shared files after sending
        });
      },
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GoSend Pro',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Partagez vos fichiers instantanément',
          style: GoogleFonts.inter(
            color: _accentGreen,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildModeButtons(),
        const SizedBox(height: 16),
        Expanded(child: _buildHistorySection()),
        const SizedBox(height: 16),
        _buildNoDeviceBubble(),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildHistorySection() {
    return ListenableBuilder(
      listenable: TransferService.instance,
      builder: (context, _) {
        final history = TransferService.instance.sessionHistory;
        if (history.isEmpty) {
          return Center(
            child: Text(
              'Aucun transfert récent',
              style: GoogleFonts.inter(color: _textSecondary.withValues(alpha: 0.5)),
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Historique récent',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final item = history[index];
                    final isReceived = item['type'] == 'received';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Icon(
                            isReceived ? Icons.download_rounded : Icons.upload_rounded,
                            color: isReceived ? _accentGreen : Colors.blueAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['filename'] ?? 'Fichier inconnu',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                ),
                                Text(
                                  '${item['timestamp']} • ${item['status']}',
                                  style: GoogleFonts.inter(color: _textSecondary, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _discreteButton(
                Icons.radar_rounded,
                'Connecter',
                'Chercher un appareil',
                _showConnectionDialog,
                enabled: !_isConnected,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _discreteButton(
                Icons.send_rounded,
                'Envoyer',
                'Transférer des fichiers',
                _isConnected
                    ? () {
                        setState(() {
                          _currentPageIndex = 1;
                        });
                      }
                    : null,
                enabled: _isConnected,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _discreteButton(
                Icons.router_rounded,
                'Mode Serveur',
                'Écouter les connexions',
                _toggleServer,
                enabled: true,
                isActive: TransferService.instance.isRunning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildIPDisplay(),
      ],
    );
  }

  Widget _discreteButton(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback? onTap, {
    bool enabled = true,
    bool isActive = false,
  }) {
    final color = !enabled ? Colors.grey.withValues(alpha: 0.5) : (isActive ? _accentGreen : Colors.white);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isActive
                      ? [
                          _accentGreen.withValues(alpha: 0.3),
                          _accentGreen.withValues(alpha: 0.1),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.03),
                        ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? _accentGreen.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1.5,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: _accentGreen.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIPDisplay() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _localIP != 'Non connecté' 
                    ? _accentGreen.withValues(alpha: 0.2) 
                    : Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_rounded,
                  color: _localIP != 'Non connecté'
                      ? _accentGreen
                      : _textSecondary.withValues(alpha: 0.5),
                  size: 18,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mon IP Locale',
                      style: GoogleFonts.inter(
                        color: _textSecondary.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _localIP,
                      style: GoogleFonts.outfit(
                        color: _localIP != 'Non connecté'
                            ? Colors.white
                            : _textSecondary.withValues(alpha: 0.5),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _checkConnectivity,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConnectionDialog() {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildConnectionDialogContent(),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: _buildConnectionDialogContent(),
        ),
      );
    }
  }

  Widget _buildConnectionDialogContent() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: _cardDark.withValues(alpha: 0.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connecter un appareil',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              _connectionOption(
                Icons.wifi_rounded,
                'Connexion WiFi (IP)',
                'Connectez-vous via l\'adresse IP locale',
                () {
                  Navigator.pop(context);
                  _showIPInputDialog();
                },
                showIconInTitle: true,
              ),
              const SizedBox(height: 12),
              _connectionOption(
                Icons.qr_code_rounded,
                'Scanner un Code QR',
                'Connexion rapide via appareil photo',
                () {
                  Navigator.pop(context);
                },
                showIconInTitle: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIPInputDialog({bool isFromShare = false}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: _cardDark.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adresse IP',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entrez l\'adresse IP de l\'appareil cible',
                    style: GoogleFonts.inter(color: _textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'ex: 192.168.1.10',
                      hintStyle: GoogleFonts.inter(
                        color: _textSecondary.withValues(alpha: 0.5),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _accentGreen.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          'Annuler',
                          style: GoogleFonts.inter(color: _textSecondary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          if (controller.text.isNotEmpty) {
                            Navigator.pop(context);
                            _sendConnectionRequest(controller.text, isFromShare: isFromShare);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text(
                          'Connecter',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendConnectionRequest(String targetIP, {bool isFromShare = false}) async {
    if (!NetworkService.isValidIP(targetIP)) {
      await NotificationOverlay.error(
        context,
        title: 'IP invalide',
        message: 'Veuillez entrer une adresse IP valide',
      );
      return;
    }

    await NotificationOverlay.info(
      context,
      title: 'Connexion en cours',
      message: 'Recherche de l\'appareil...',
    );

    final isReachable = await ConnectionClient.isDeviceReachable(targetIP);
    if (!isReachable) {
      await NotificationOverlay.error(
        context,
        title: 'Appareil introuvable',
        message: 'L\'appareil ne répond pas ou a refusé la connexion.',
      );
      return;
    }

    String deviceName = await TransferService.instance.getDeviceName();

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
          if (isFromShare) {
            _currentPageIndex = 1;
          }
        });

        await NotificationOverlay.success(
          context,
          title: 'Connecté',
          message: 'L\'appareil a accepté la connexion.',
        );
      } else {
        await NotificationOverlay.error(
          context,
          title: 'Refusé',
          message: 'L\'appareil a refusé la connexion',
        );
      }
    }
  }

  void _disconnect() {
    setState(() {
      _isConnected = false;
      _connectedDeviceName = '';
      _connectedDeviceIP = '';
      _currentPageIndex = 0;
    });

    NotificationOverlay.info(
      context,
      title: 'Déconnecté',
      message: 'Connexion terminée.',
    );
  }

  void _toggleServer() async {
    if (TransferService.instance.isRunning) {
      await TransferService.instance.stopServer();
      setState(() {});
      await NotificationOverlay.warning(
        context,
        title: 'Serveur arrêté',
        message: 'L\'écoute réseau est désactivée.',
      );
    } else {
      await TransferService.instance.startServer();
      setState(() {});
      await NotificationOverlay.success(
        context,
        title: 'Serveur en ligne',
        message: 'Prêt à recevoir des connexions sur $_localIP:8765',
      );
    }
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.02)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _accentGreen, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
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
              Icons.chevron_right_rounded,
              color: _textSecondary.withValues(alpha: 0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoDeviceBubble() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isConnected
              ? [
                  _accentGreen.withValues(alpha: 0.2),
                  _accentGreen.withValues(alpha: 0.05),
                ]
              : [
                  Colors.white.withValues(alpha: 0.05),
                  Colors.white.withValues(alpha: 0.02),
                ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: _isConnected
              ? _accentGreen.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.link_rounded : Icons.wifi_off_rounded,
            color: _isConnected ? _accentGreen : _textSecondary.withValues(alpha: 0.5),
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(
            _isConnected
                ? '$_connectedDeviceName'
                : 'Aucun appareil connecté',
            style: GoogleFonts.inter(
              color: _isConnected ? Colors.white : _textSecondary.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_isConnected) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _disconnect,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.redAccent,
                  size: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
