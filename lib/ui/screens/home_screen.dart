import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/history_db.dart';
import '../../core/network/discovery_service.dart';
import '../../core/network/webrtc_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/transfer/file_receiver.dart';
import '../../models/device.dart';
import '../../models/history_item.dart';
import '../../models/transfer_request.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<Device> devices;
  final VoidCallback onRefresh;
  final String localDeviceName;
  final String localIpAddress;
  final DiscoveryService discoveryService;

  const HomeScreen({
    super.key,
    required this.devices,
    required this.onRefresh,
    required this.localDeviceName,
    required this.localIpAddress,
    required this.discoveryService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  Device? _selectedDevice;
  List<File> _selectedFiles = [];
  bool _isDragging = false;
  bool _isConnecting = false;
  bool _isTransferring = false;
  double _progress = 0.0;
  String _statusMessage = 'Prêt à envoyer';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final WebRTCService _webRTCService = WebRTCService();
  final FileReceiver _fileReceiver = FileReceiver();
  final List<TransferRequest> _incomingRequests = [];
  TransferRequest? _currentReceivingRequest;
  String? _currentTransferId;
  bool _isPaused = false;
  bool _isCancelled = false;
  final TextEditingController _deviceSearchController = TextEditingController();
  String _deviceSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _webRTCService.startSignalingServer();
    _webRTCService.onTransferRequestReceived = _handleTransferRequest;
    _webRTCService.onTransferResponse = _handleTransferResponse;
    _webRTCService.onDataReceived = _handleDataReceived;
    _webRTCService.onControlMessage = _handleControlMessage;
    _deviceSearchController.addListener(() {
      setState(() => _deviceSearchQuery = _deviceSearchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _deviceSearchController.dispose();
    _webRTCService.dispose();
    super.dispose();
  }

  void _handleTransferRequest(TransferRequest request) {
    setState(() {
      _incomingRequests.add(request);
    });
    _showTransferRequestDialog(request);
  }

  void _handleTransferResponse(String requestId, bool accepted) {
    if (accepted) {
      _currentTransferId = requestId;
      _startFileTransfer();
    } else {
      setState(() {
        _statusMessage = 'Transfert refusé';
        _isTransferring = false;
      });
    }
  }

  void _handleControlMessage(String requestId, String action) {
    if (action == 'pause') {
      setState(() => _isPaused = true);
    } else if (action == 'resume') {
      setState(() => _isPaused = false);
    } else if (action == 'cancel') {
      setState(() {
        _isCancelled = true;
        _isTransferring = false;
        _statusMessage = 'Transfert annulé par l\'autre appareil';
        if (_currentReceivingRequest != null) {
          _fileReceiver.cancelTransfer(requestId);
          _currentReceivingRequest = null;
        }
      });
    }
  }

  void _handleDataReceived(Uint8List data) {
    if (_currentReceivingRequest != null) {
      final progress = _fileReceiver.receiveChunk(
        _currentReceivingRequest!.id,
        data,
      );
      setState(() {
        _progress = progress;
        _statusMessage =
            'Réception : ${_currentReceivingRequest!.files.first.name}';
      });

      if (progress >= 1.0) {
        _saveReceivedFile();
      }
    }
  }

  Future<void> _saveReceivedFile() async {
    if (_currentReceivingRequest == null) return;

    final filePath = await _fileReceiver.saveFile(_currentReceivingRequest!.id);
    if (filePath != null) {
      setState(() {
        _statusMessage = '✅ Fichier reçu : $filePath';
        _progress = 0.0;
      });
      _showSnack('✅ Fichier enregistré avec succès !');
      
      NotificationService().showNotification(
        title: 'Transfert terminé',
        body: 'Fichier ${_currentReceivingRequest!.files.first.name} reçu',
      );
      
      final historyItem = HistoryItem(
        id: const Uuid().v4(),
        type: 'receive',
        peerName: _currentReceivingRequest!.senderName,
        fileName: _currentReceivingRequest!.files.first.name,
        filePath: filePath,
        size: _currentReceivingRequest!.files.first.size,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'completed',
      );
      HistoryDB.instance.insertItem(historyItem);
      
      _currentReceivingRequest = null;
    }
  }

  void _showTransferRequestDialog(TransferRequest request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Demande de transfert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('De: ${request.senderName}'),
            const SizedBox(height: 8),
            const Text('Fichiers:'),
            ...request.files.map(
              (file) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text('• ${file.name} (${_formatSize(file.size)})'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _webRTCService.sendTransferResponse(request.id, false);
              setState(() {
                _incomingRequests.remove(request);
              });
            },
            child: const Text('Refuser'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _fileReceiver.startTransfer(request.id, request);
              _webRTCService.sendTransferResponse(request.id, true);
              setState(() {
                _incomingRequests.remove(request);
                _currentReceivingRequest = request;
                _isCancelled = false;
                _isPaused = false;
                _isTransferring = true;
                _statusMessage = 'Réception en cours...';
              });
            },
            child: const Text('Accepter'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles() async {
    if (MediaQuery.of(context).size.width <= 800 && Platform.isAndroid || Platform.isIOS) {
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Images / Vidéos (Galerie)'),
                onTap: () async {
                  Navigator.pop(context);
                  final picker = ImagePicker();
                  final pickedFiles = await picker.pickMultipleMedia();
                  if (pickedFiles.isNotEmpty) {
                    setState(() {
                      _selectedFiles.addAll(pickedFiles.map((x) => File(x.path)));
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Fichiers'),
                onTap: () async {
                  Navigator.pop(context);
                  final result = await FilePicker.platform.pickFiles(allowMultiple: true);
                  if (result != null) {
                    setState(() {
                      _selectedFiles.addAll(result.paths.whereType<String>().map(File.new));
                    });
                  }
                },
              ),
            ],
          ),
        ),
      );
    } else {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null) {
        setState(() {
          _selectedFiles = result.paths
              .whereType<String>()
              .map(File.new)
              .toList();
        });
      }
    }
  }

  Future<void> _sendFiles() async {
    if (_selectedDevice == null) {
      _showSnack('⚠️ Sélectionne d\'abord un appareil dans la liste');
      return;
    }
    if (_selectedFiles.isEmpty) {
      _showSnack('⚠️ Sélectionne d\'abord des fichiers à envoyer');
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connexion à ${_selectedDevice!.name}...';
    });

    try {
      await _webRTCService.connectToPeer(_selectedDevice!.ip);
      setState(() {
        _isConnecting = false;
        _statusMessage = 'En attente d\'acceptation...';
      });

      final filesInfo = await Future.wait(
        _selectedFiles.map((file) async {
          final size = await file.length();
          return FileInfo(
            name: file.path.split(Platform.pathSeparator).last,
            size: size,
            type: file.path.split('.').last,
          );
        }),
      );

      final request = TransferRequest(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: 'local',
        senderName: widget.localDeviceName,
        files: filesInfo,
        timestamp: DateTime.now(),
      );

      _webRTCService.sendTransferRequest(request);
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Erreur de connexion';
      });
      _showSnack('❌ Erreur: $e');
    }
  }

  Future<void> _startFileTransfer() async {
    setState(() {
      _isTransferring = true;
      _isCancelled = false;
      _isPaused = false;
      _statusMessage = 'Envoi en cours...';
    });

    try {
      for (final file in _selectedFiles) {
        if (_isCancelled) break;
        final size = await file.length();
        int sent = 0;
        final raf = await file.open(mode: FileMode.read);
        const chunkSize = 16 * 1024; // 16KB to prevent WebRTC crashes
        while (sent < size) {
          if (_isCancelled) break;
          if (_isPaused) {
            await Future.delayed(const Duration(milliseconds: 200));
            continue;
          }
          final chunk = await raf.read(chunkSize);
          if (chunk.isEmpty) break;
          _webRTCService.sendData(chunk);
          sent += chunk.length;
          setState(() {
            _progress = sent / size;
            _statusMessage =
                'Envoi : ${file.path.split(Platform.pathSeparator).last}';
          });
          await Future.delayed(const Duration(milliseconds: 1));
        }
        await raf.close();
      }

      if (_isCancelled) return;

      setState(() {
        _isTransferring = false;
        _progress = 1.0;
        _statusMessage = '✅ Envoi terminé !';
        _selectedFiles = [];
        _currentTransferId = null;
      });
      _showSnack('✅ Fichiers envoyés avec succès !');

      final historyItem = HistoryItem(
        id: const Uuid().v4(),
        type: 'send',
        peerName: _selectedDevice?.name ?? 'Inconnu',
        fileName: 'Plusieurs fichiers', // simplifcation for now
        filePath: '',
        size: 0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'completed',
      );
      HistoryDB.instance.insertItem(historyItem);
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isTransferring = false;
        _statusMessage = '❌ Erreur : $e';
      });
      _showSnack('❌ Erreur de transfert');
    }
  }

  void _showSnack(String msg) {
    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 60,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {
                entry?.remove();
                entry = null;
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text(
                  msg,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry!);
    Future.delayed(const Duration(seconds: 4), () {
      if (entry != null && entry!.mounted) {
        entry!.remove();
        entry = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) return _buildDesktopLayout();
        return _buildMobileLayout();
      },
    );
  }

  // ─────────────────────── MOBILE ───────────────────────

  Widget _buildMobileLayout() {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'GoSend',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        actions: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Transform.scale(
              scale: _pulseAnimation.value,
              child: IconButton(
                icon: Icon(
                  Icons.wifi_tethering,
                  color: widget.devices.isNotEmpty
                      ? Colors.green
                      : Colors.orange,
                ),
                onPressed: widget.onRefresh,
                tooltip: 'Rafraîchir la découverte',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historique',
            onPressed: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (c, a, b) => const HistoryScreen(),
                transitionsBuilder: (c, a, b, child) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.05),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                    child: child,
                  ),
                ),
                transitionDuration: const Duration(milliseconds: 300),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'invisible') {
                setState(() {
                  widget.discoveryService.toggleDiscoverability();
                });
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'invisible',
                child: Row(
                  children: [
                    Icon(widget.discoveryService.isDiscoverable ? Icons.visibility : Icons.visibility_off),
                    const SizedBox(width: 8),
                    Text(widget.discoveryService.isDiscoverable ? 'Rendre invisible' : 'Rendre visible'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildFilesCard(isMobile: true),
            const SizedBox(height: 16),
            _buildDevicesSection(isMobile: true),
            const SizedBox(height: 16),
            if (_selectedDevice != null) _buildSendButton(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── DESKTOP ───────────────────────

  Widget _buildDesktopLayout() {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          // Sidebar gauche : appareils
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant.withAlpha(60),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(12),
                  blurRadius: 16,
                  offset: const Offset(4, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'GoSend',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    widget.localDeviceName,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (_, __) => Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: widget.devices.isNotEmpty
                                  ? Colors.green
                                  : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.devices.isNotEmpty
                            ? '${widget.devices.length} appareil(s) trouvé(s)'
                            : 'Recherche...',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          widget.discoveryService.isDiscoverable ? Icons.visibility : Icons.visibility_off,
                          size: 18,
                        ),
                        onPressed: () => setState(() => widget.discoveryService.toggleDiscoverability()),
                        tooltip: 'Visibilité',
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: widget.onRefresh,
                        tooltip: 'Rafraîchir',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildDevicesSection(isMobile: false)),
                // ─── Historique en bas du panel ───
                const Divider(height: 1),
                InkWell(
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(20),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (c, a, b) => const HistoryScreen(),
                      transitionsBuilder: (c, a, b, child) => FadeTransition(
                        opacity: a,
                        child: child,
                      ),
                      transitionDuration: const Duration(milliseconds: 250),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(
                          'Historique',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_right_rounded, size: 18, color: colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // Zone principale
          Expanded(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
                  child: Row(
                    children: [
                      _buildStatusBadge(),
                      const Spacer(),
                      if (_selectedDevice != null) _buildSendButton(),
                    ],
                  ),
                ),
                // Zone fichiers + drop
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    child: _buildFilesCard(isMobile: false),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── WIDGETS COMMUNS ───────────────────────

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.devices.isNotEmpty
              ? [
                  const Color(0xFF1DB954).withAlpha(30),
                  const Color(0xFF1DB954).withAlpha(10),
                ]
              : [Colors.orange.withAlpha(30), Colors.orange.withAlpha(10)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.devices.isNotEmpty
              ? Colors.green.withAlpha(80)
              : Colors.orange.withAlpha(80),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Transform.scale(
              scale: _pulseAnimation.value,
              child: Icon(
                Icons.wifi_tethering,
                size: 36,
                color: widget.devices.isNotEmpty ? Colors.green : Colors.orange,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.devices.isNotEmpty
                      ? 'Réseau actif'
                      : 'Recherche en cours...',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.devices.isNotEmpty
                      ? '${widget.devices.length} appareil(s) détecté(s)'
                      : 'En attente d\'autres appareils GoSend sur le Wi-Fi',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _isTransferring
            ? Colors.blue.withAlpha(20)
            : Colors.green.withAlpha(20),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isTransferring
              ? Colors.blue.withAlpha(80)
              : Colors.green.withAlpha(80),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isTransferring ? Icons.sync : Icons.check_circle,
            size: 16,
            color: _isTransferring ? Colors.blue : Colors.green,
          ),
          const SizedBox(width: 8),
          Text(
            _statusMessage,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesCard({required bool isMobile}) {
    return DropTarget(
      onDragDone: (details) {
        setState(() {
          _selectedFiles = details.files.map((f) => File(f.path)).toList();
          _isDragging = false;
        });
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isDragging
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
            width: _isDragging ? 2.5 : 1.5,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          color: _isDragging
              ? Theme.of(context).colorScheme.primary.withAlpha(15)
              : Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header de la zone
            Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fichiers à envoyer',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                  style: TextButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withAlpha(15),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Zone vide ou liste
            if (_selectedFiles.isEmpty)
              _buildEmptyDropZone(isMobile: isMobile)
            else
              _buildFilesList(),
            // Barre de progression
            if (_isTransferring) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: Theme.of(context).colorScheme.outlineVariant.withAlpha(40),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${(_progress * 100).toStringAsFixed(0)}%  —  $_statusMessage',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, size: 20),
                        onPressed: () {
                          final action = _isPaused ? 'resume' : 'pause';
                          if (_currentReceivingRequest != null) {
                            _webRTCService.sendControlMessage(_currentReceivingRequest!.id, action);
                          } else if (_currentTransferId != null) {
                            _webRTCService.sendControlMessage(_currentTransferId!, action);
                          }
                          setState(() => _isPaused = !_isPaused);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20, color: Colors.red),
                        onPressed: () {
                          if (_currentReceivingRequest != null) {
                            _webRTCService.sendControlMessage(_currentReceivingRequest!.id, 'cancel');
                            _fileReceiver.cancelTransfer(_currentReceivingRequest!.id);
                          } else if (_currentTransferId != null) {
                            _webRTCService.sendControlMessage(_currentTransferId!, 'cancel');
                          }
                          setState(() {
                            _isCancelled = true;
                            _isTransferring = false;
                            _statusMessage = 'Annulé';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDropZone({required bool isMobile}) {
    return Container(
      height: isMobile ? 140 : 240,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.onSurface.withAlpha(5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withAlpha(120),
          ),
          const SizedBox(height: 12),
          Text(
            isMobile ? 'Appuie sur "Ajouter"' : 'Glisse tes fichiers ici',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isMobile)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ou clique sur "Ajouter" pour choisir des fichiers',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(150),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilesList() {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isDesktop = constraints.maxWidth > 400;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _selectedFiles.map((file) {
          final name = file.path.split(Platform.pathSeparator).last;
          final content = _buildFileItemContent(file, name);
          return SizedBox(
            width: isDesktop ? (constraints.maxWidth - 8) / 2 : double.infinity,
            child: content,
          );
        }).toList(),
      );
    });
  }

  Widget _buildFileItemContent(File file, String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withAlpha(25),
        ),
      ),
      child: Row(
        children: [
          // Vraie miniature pour les images, icône sinon
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isImage
                ? Image.file(
                    file,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fileIconBox(name),
                  )
                : _fileIconBox(name),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                FutureBuilder<int>(
                  future: file.length(),
                  builder: (_, snap) {
                    if (!snap.hasData) return const SizedBox();
                    return Text(
                      _formatSize(snap.data!),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () => setState(() => _selectedFiles.remove(file)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _fileIconBox(String name) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        _iconForFile(name),
        size: 24,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildDevicesSection({required bool isMobile}) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredDevices = widget.devices
        .where((d) =>
            d.name.toLowerCase().contains(_deviceSearchQuery) ||
            d.ip.contains(_deviceSearchQuery))
        .toList();

    return Column(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      children: [
        // Barre de recherche
        if (widget.devices.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 0 : 12,
              vertical: 4,
            ),
            child: TextField(
              controller: _deviceSearchController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher un appareil...',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withAlpha(150),
                ),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _deviceSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _deviceSearchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.onSurface.withAlpha(6),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(60),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(60),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: colorScheme.primary.withAlpha(120),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        // Appareil local
        _buildLocalDeviceCard(isMobile),
        const SizedBox(height: 12),
        // Liste des appareils découverts (filtrés)
        if (isMobile)
          filteredDevices.isEmpty
              ? _buildEmptyDevicesState(isMobile)
              : _buildDevicesList(isMobile, filteredDevices)
        else
          Expanded(
            child: filteredDevices.isEmpty
                ? _buildEmptyDevicesState(isMobile)
                : _buildDevicesList(isMobile, filteredDevices),
          ),
      ],
    );
  }

  Widget _buildLocalDeviceCard(bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(40),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.computer,
            color: colorScheme.onSurfaceVariant,
            size: isMobile ? 16 : 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.localDeviceName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.localIpAddress,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isMobile ? 10 : 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            color: colorScheme.primary,
            size: isMobile ? 14 : 16,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDevicesState(bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 0 : 20),
      child: isMobile
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: colorScheme.surface,
                border: Border.all(
                  color: colorScheme.outlineVariant.withAlpha(60),
                ),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.devices_other, size: 36, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'Aucun appareil détecté',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Assure-toi que GoSend est ouvert sur l\'autre appareil sur le même Wi-Fi',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: const [
                Icon(Icons.devices_other, size: 36, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'Aucun appareil',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Ouvre GoSend sur un autre appareil sur le même Wi-Fi',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDevicesList(bool isMobile, List<dynamic> devices) {
    final deviceWidgets = devices.map((device) {
      final isSelected = _selectedDevice?.id == device.id;
      return GestureDetector(
        onTap: () =>
            setState(() => _selectedDevice = isSelected ? null : device),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.symmetric(
            horizontal: isMobile ? 0 : 12,
            vertical: 5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withAlpha(20)
                : Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary.withAlpha(15),
                ),
                child: Icon(
                  _iconForOs(device.os),
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      device.ip,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
            ],
          ),
        ),
      );
    }).toList();

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appareils détectés',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...deviceWidgets,
        ],
      );
    }
    return ListView(children: deviceWidgets);
  }

  Widget _buildSendButton() {
    return ElevatedButton.icon(
      onPressed: _isConnecting || _isTransferring ? null : _sendFiles,
      icon: _isConnecting || _isTransferring
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.send_rounded, size: 20),
      label: Text(
        _isConnecting
            ? 'Connexion...'
            : _isTransferring
            ? 'Envoi...'
            : 'Envoyer vers ${_selectedDevice?.name ?? ""}',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
    );
  }

  IconData _iconForOs(String os) {
    final lower = os.toLowerCase();
    if (lower.contains('android')) return Icons.android;
    if (lower.contains('ios') || lower.contains('mac')) return Icons.apple;
    if (lower.contains('windows')) return Icons.window;
    return Icons.devices;
  }

  IconData _iconForFile(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Icons.image;
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return Icons.movie;
    if (['mp3', 'wav', 'flac', 'aac'].contains(ext)) return Icons.music_note;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.archive;
    if (['doc', 'docx', 'txt'].contains(ext)) return Icons.description;
    return Icons.insert_drive_file;
  }
}
