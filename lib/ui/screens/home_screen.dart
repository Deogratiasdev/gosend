import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/audio/audio_service.dart';
import '../../core/network/discovery_service.dart';
import '../../core/network/http_transfer_service.dart';
import '../../core/network/network_util.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/theme_service.dart';
import '../../models/device.dart';
import '../../models/transfer_request.dart';
import '../theme.dart';
import '../widgets/custom_title_bar.dart';
import 'settings_screen.dart';
import 'text_compose_screen.dart';
import 'text_message_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<Device> devices;
  final VoidCallback onRefresh;
  final String localDeviceName;
  final String localIpAddress;
  final String localDeviceId;
  final String localOs;
  final DiscoveryService discoveryService;

  const HomeScreen({
    super.key,
    required this.devices,
    required this.onRefresh,
    required this.localDeviceName,
    required this.localIpAddress,
    required this.localDeviceId,
    required this.localOs,
    required this.discoveryService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Device? _selectedDevice;
  List<File> _selectedFiles = [];
  bool _isDragging = false;
  bool _isConnecting = false;
  bool _isTransferring = false;
  double _progress = 0.0;
  int _totalBytesToReceive = 0;
  String _statusMessage = 'Prêt à envoyer';
  final Map<int, double> _fileProgress = <int, double>{};
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late final HttpTransferService _httpService;
  final List<TransferRequest> _incomingRequests = [];

  // 0 = Envoi, 1 = Paramètres (desktop uniquement)
  int _selectedTab = 0;

  String? _currentTransferId;
  bool _isPaused = false;
  final TextEditingController _deviceSearchController = TextEditingController();
  String _deviceSearchQuery = '';
  static const platform = MethodChannel('com.example.gosend/share');
  String? _receiveDirectoryPath;
  OverlayEntry? _currentNotification;
  Map<int, String> _fileTokens = <int, String>{};
  final Map<String, int> _cachedFileSizes = <String, int>{};
  double _speedMbps = 0.0;
  int _etaSeconds = 0;
  int _ackedBytes = 0;
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastAckedForSpeed = 0;
  DateTime _lastSpeedSample = DateTime.fromMillisecondsSinceEpoch(0);

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
    _httpService = HttpTransferService(localIpAddress: widget.localIpAddress);
    _httpService.setIdentity(
      id: widget.localDeviceId,
      name: widget.localDeviceName,
      os: widget.localOs,
    );
    _httpService.startServers().catchError((Object e) {
      debugPrint('Erreur démarrage serveurs HTTP: $e');
      _notify('Erreur ouverture ports 41731/41732 : $e', icon: Icons.error_outline);
    });
    // Récupère toutes les IP locales pour les inclure dans les requêtes
    // de transfert (utile quand l'appareil a WiFi + hotspot simultanés).
    NetworkUtil.allLocalIps().then((ips) {
      _httpService.updateAllLocalIps(ips);
    });
    _httpService.onTransferRequestReceived = _handleTransferRequest;
    _httpService.onTransferResponse = _handleTransferResponse;
    _httpService.onControlMessage = _handleControlMessage;
    _httpService.onTextMessageReceived = _handleTextMessageReceived;
    WidgetsBinding.instance.addObserver(this);
    _deviceSearchController.addListener(() {
      setState(
        () => _deviceSearchQuery = _deviceSearchController.text.toLowerCase(),
      );
    });
    _checkSharedFiles();
    _getReceiveDirectory();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localIpAddress != widget.localIpAddress) {
      _httpService.updateLocalIpAddress(widget.localIpAddress);
      // Met à jour la liste de toutes les IP locales pour que le service
      // HTTP puisse les inclure dans les requêtes (utile en WiFi + hotspot).
      NetworkUtil.allLocalIps().then((ips) {
        _httpService.updateAllLocalIps(ips);
      });
    }
  }

  Future<Directory> _resolveReceiveDirectory() async {
    if (Platform.isAndroid) {
      final downloadDir = Directory(
        '/storage/emulated/0/Download/GoSend/received',
      );
      try {
        await downloadDir.create(recursive: true);
        return downloadDir;
      } catch (e) {
        debugPrint('Impossible d\'utiliser Downloads, fallback app dir: $e');
      }
    }
    final directory = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${directory.path}/GoSend/received');
    await saveDir.create(recursive: true);
    return saveDir;
  }

  Future<void> _getReceiveDirectory() async {
    try {
      final saveDir = await _resolveReceiveDirectory();
      setState(() => _receiveDirectoryPath = saveDir.path);
    } catch (e) {
      debugPrint('Error getting receive directory: $e');
    }
  }

  Future<void> _openReceiveDirectory() async {
    if (_receiveDirectoryPath != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ouvrir le dossier de réception'),
          content: const Text(
            'Vous allez être redirigé vers le dossier où les fichiers reçus sont enregistrés.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ouvrir'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final path = _receiveDirectoryPath!;
      try {
        if (Platform.isWindows) {
          await Process.run('explorer.exe', [path.replaceAll('/', '\\')]);
        } else if (Platform.isAndroid) {
          await platform.invokeMethod('openReceiveDirectory', {'path': path});
        } else {
          _notify('Ouverture du dossier non supportée sur cette plateforme', icon: Icons.folder_off_outlined);
        }
      } catch (e) {
        debugPrint('Erreur ouverture dossier: $e');
        _notify('Erreur ouverture dossier : $e', icon: Icons.error_outline);
      }
    }
  }

  Future<void> _checkSharedFiles() async {
    if (Platform.isAndroid) {
      try {
        final List<dynamic>? sharedFiles = await platform.invokeMethod(
          'getSharedFiles',
        );
        if (sharedFiles != null && sharedFiles.isNotEmpty) {
          final List<File> files = [];
          for (final item in sharedFiles) {
            try {
              if (item is String) {
                var path = item;
                if (path.startsWith('file://')) {
                  path = path.replaceFirst('file://', '');
                }
                final file = File(path);
                if (await file.exists()) {
                  files.add(file);
                }
              }
            } catch (e) {
              debugPrint('Erreur traitement shared item $item: $e');
            }
          }
          if (files.isNotEmpty) {
            setState(() {
              _selectedFiles = files;
              _statusMessage = '${files.length} fichier(s) partagé(s) prêt(s)';
            });
          }
        }
      } catch (e) {
        debugPrint('Erreur récupération fichiers partagés: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _deviceSearchController.dispose();
    _httpService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkSharedFiles();
  }

  void _handleTransferRequest(TransferRequest request) {
    setState(() => _incomingRequests.add(request));
    _showTransferRequestDialog(request);
  }

  void _handleTransferResponse(
      String requestId, bool accepted, Map<String, String>? tokens) {
    if (accepted) {
      _currentTransferId = requestId;
      if (tokens != null) {
        _fileTokens = tokens.map((k, v) => MapEntry(int.tryParse(k) ?? -1, v))
          ..removeWhere((k, _) => k < 0);
      }
      _notify(
        '✅ Demande acceptée - transfert en cours…',
        icon: Icons.check_circle_outline_rounded,
      );
      _startFileTransfer();
    } else {
      setState(() {
        _statusMessage = 'Transfert refusé';
        _isConnecting = false;
        _isTransferring = false;
      });
      _notify(
        '❌ Demande refusée par l\'appareil distant',
        icon: Icons.cancel_outlined,
      );
    }
  }

  void _handleControlMessage(String requestId, String action) {
    if (action == 'pause') {
      setState(() => _isPaused = true);
      _httpService.pauseTransfer();
    } else if (action == 'resume') {
      setState(() => _isPaused = false);
      _httpService.resumeTransfer();
    } else if (action == 'cancel') {
      widget.discoveryService.setDiscoverable(true);
      setState(() {
        _isTransferring = false;
        _statusMessage = 'Transfert annulé par l\'autre appareil';
      });
      _httpService.cancelTransfer();
      // Supprime immédiatement les fichiers .deogratias en cours d'écriture.
      _httpService.deleteActivePartFiles();
    }
  }

  void _pauseTransfer() {
    setState(() => _isPaused = true);
    _httpService.pauseTransfer();
    if (_currentTransferId != null) {
      _httpService.sendControlMessage(_currentTransferId!, 'pause');
    }
  }

  void _resumeTransfer() {
    setState(() => _isPaused = false);
    _httpService.resumeTransfer();
    if (_currentTransferId != null) {
      _httpService.sendControlMessage(_currentTransferId!, 'resume');
    }
  }

  void _cancelTransfer() {
    widget.discoveryService.setDiscoverable(true);
    setState(() {
      _isTransferring = false;
      _statusMessage = 'Transfert annulé';
    });
    _httpService.cancelTransfer();
    if (_currentTransferId != null) {
      _httpService.sendControlMessage(_currentTransferId!, 'cancel');
    }
  }

  void _showTransferRequestDialog(TransferRequest request) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Demande de transfert',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text('De: ${request.senderName}'),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Fichiers:',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              ...request.files.map(
                (file) => Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    '• ${file.name} (${_formatSize(file.size)})',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _httpService.sendTransferResponse(request.id, false);
              setState(() => _incomingRequests.remove(request));
            },
            child: Text(
              'Refuser',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              int totalSize = 0;
              for (final f in request.files) {
                totalSize += f.size;
              }
              final saveDirectory = await _resolveReceiveDirectory();
              final saveDir = saveDirectory.path;
              _receiveDirectoryPath = saveDir;
              final tokens = _httpService.prepareReceive(
                request.id,
                request.files,
                saveDir,
                (fileIndex, received, total) {
                  _throttledReceiveUi(
                      total, received, request.files[fileIndex].name);
                },
                (fileIndex, fileReceived, fileSize) {
                  _throttledFileUi(fileIndex, fileReceived, fileSize);
                },
                (fileIndex, filePath) {
                  debugPrint('Fichier reçu: $filePath');
                },
                () {
                  widget.discoveryService.setDiscoverable(true);
                  setState(() {
                    _isTransferring = false;
                    _progress = 0.0;
                    _statusMessage = 'Transfert terminé !';
                    _fileProgress.clear();
                    _speedMbps = 0.0;
                    _etaSeconds = 0;
                  });
                  AudioService.instance.playFileReceived();
                  _notify('Tous les fichiers enregistrés !', icon: Icons.check_circle_outline_rounded);
                  NotificationService().showNotification(
                    title: 'Transfert terminé',
                    body: '${request.files.length} fichier(s) reçu(s)',
                  );
                },
              );
              await _httpService.sendTransferResponse(request.id, true,
                  tokens: tokens);
              // Indispensable : sans ça, pause/cancel côté réception
              // n'envoient aucun message (id null) et restent locaux.
              _currentTransferId = request.id;
              widget.discoveryService.setDiscoverable(false);
              setState(() {
                _incomingRequests.remove(request);
                _totalBytesToReceive = totalSize;
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.paths.isNotEmpty) {
      setState(
        () => _selectedFiles.addAll(
          result.paths.whereType<String>().map(File.new),
        ),
      );
      AudioService.instance.playFileAdded();
    }
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(
        () => _selectedFiles.addAll(pickedFiles.map((x) => File(x.path))),
      );
      AudioService.instance.playFileAdded();
    }
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result != null && result.paths.isNotEmpty) {
      setState(
        () => _selectedFiles.addAll(
          result.paths.whereType<String>().map(File.new),
        ),
      );
      AudioService.instance.playFileAdded();
    }
  }

  // ─────────────── ADD CHOICE (fichiers / texte) ───────────────

  void _showAddMobileSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photos'),
              onTap: () {
                Navigator.pop(context);
                _pickPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Vidéos'),
              onTap: () {
                Navigator.pop(context);
                _pickVideos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Fichiers'),
              onTap: () {
                Navigator.pop(context);
                _pickFiles();
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Texte'),
              onTap: () {
                Navigator.pop(context);
                _showTextInputDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDesktopMenu(BuildContext context) async {
    final choice = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 200, 0, 0),
      items: [
        const PopupMenuItem(
          value: 'files',
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 18),
              SizedBox(width: 10),
              Text('Fichiers'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'text',
          child: Row(
            children: [
              Icon(Icons.text_snippet_outlined, size: 18),
              SizedBox(width: 10),
              Text('Texte'),
            ],
          ),
        ),
      ],
    );
    if (choice == 'files') {
      _pickFiles();
    } else if (choice == 'text') {
      _showTextInputDialog();
    }
  }

  Future<void> _showTextInputDialog() async {
    // Vérifier qu'un destinataire est sélectionné
    if (_selectedDevice == null) {
      _notify('Sélectionne d\'abord un appareil dans la liste', icon: Icons.info_outline);
      return;
    }

    final isMobile = MediaQuery.of(context).size.width <= 800;

    if (isMobile) {
      // Mobile : page entière similaire à l'écran de réception
      final text = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => TextComposeScreen(
            recipientName: _selectedDevice!.name,
          ),
        ),
      );
      if (text != null && text.isNotEmpty) {
        await _sendTextMessage(text);
      }
    } else {
      // Desktop : carte centrée
      await _showDesktopComposeDialog();
    }
  }

  Future<void> _showDesktopComposeDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.text_snippet_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Envoyer du texte',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            'À ${_selectedDevice!.name}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Text field
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: colorScheme.onSurface.withAlpha(5),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: 'Tape ton texte ici…',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        height: 1.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Annuler',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () {
                        final value = controller.text.trim();
                        if (value.isNotEmpty) Navigator.pop(context, value);
                      },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Envoyer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (text != null && text.isNotEmpty) {
      await _sendTextMessage(text);
    }
  }

  Future<void> _sendTextMessage(String text) async {
    if (_selectedDevice == null) {
      _notify('Sélectionne d\'abord un appareil dans la liste', icon: Icons.info_outline);
      return;
    }
    try {
      _httpService.connectToPeer(
        _selectedDevice!.ip,
        httpPort: _selectedDevice!.httpPort,
      );
      await _httpService.sendTextMessage(text, widget.localDeviceName);
      _notify('Message envoyé à ${_selectedDevice!.name}', icon: Icons.send_outlined);
    } catch (e) {
      _notify('Erreur: $e', icon: Icons.error_outline);
    }
  }

  // ─────────────── RÉCEPTION TEXTE ───────────────

  void _handleTextMessageReceived(String senderName, String text, DateTime timestamp) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    NotificationService().showNotification(
      title: 'Message de $senderName',
      body: text.length > 60 ? '${text.substring(0, 60)}…' : text,
    );
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextMessageScreen(
            senderName: senderName,
            text: text,
            timestamp: timestamp,
          ),
        ),
      );
    } else {
      _showTextMessageDialog(senderName, text, timestamp);
    }
  }

  void _showTextMessageDialog(String senderName, String text, DateTime timestamp) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Message de $senderName',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} - '
                            '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Content
                Flexible(
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 360),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: colorScheme.onSurface.withAlpha(5),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          height: 1.6,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: text));
                        Navigator.pop(context);
                        _notify('Texte copié !', icon: Icons.content_copy);
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copier'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendFiles() async {
    if (_selectedDevice == null) {
      _notify('Sélectionne d\'abord un appareil dans la liste', icon: Icons.info_outline);
      return;
    }
    if (_selectedFiles.isEmpty) {
      _notify('Sélectionne d\'abord des fichiers à envoyer', icon: Icons.info_outline);
      return;
    }
    setState(() {
      _isConnecting = true;
      _statusMessage = 'Connexion à ${_selectedDevice!.name}...';
    });
    try {
      _httpService.connectToPeer(
        _selectedDevice!.ip,
        httpPort: _selectedDevice!.httpPort,
      );
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
      await _httpService.sendTransferRequest(request);
      _currentTransferId = request.id;
      _notify(
        '⏳ Demande envoyée à ${_selectedDevice!.name}…',
        icon: Icons.schedule_rounded,
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Erreur de connexion';
      });
      _notify('Erreur: $e', icon: Icons.error_outline);
    }
  }

  /// UI réception throttlée : max 1 setState / 500ms.
  void _throttledReceiveUi(int total, int received, String fileName) {
    final now = DateTime.now();
    _totalBytesToReceive = total;
    _isTransferring = true;
    _updateSpeedEta(received, total, now);
    if (now.difference(_lastUiUpdate).inMilliseconds < 500 &&
        received < total) {
      return;
    }
    _lastUiUpdate = now;
    if (!mounted) return;
    setState(() {
      _progress = total > 0 ? received / total : 0.0;
      _statusMessage = 'Réception : $fileName'
          '${_speedLabel()}';
    });
  }

  void _throttledFileUi(int fileIndex, int fileReceived, int fileSize) {
    final now = DateTime.now();
    if (now.difference(_lastUiUpdate).inMilliseconds < 500 &&
        fileReceived < fileSize) {
      _fileProgress[fileIndex] =
          fileSize > 0 ? fileReceived / fileSize : 0.0;
      return;
    }
    if (!mounted) return;
    setState(() {
      _fileProgress[fileIndex] =
          fileSize > 0 ? fileReceived / fileSize : 0.0;
    });
  }

  /// Débit (EMA) + ETA à partir des octets acquittés.
  void _updateSpeedEta(int acked, int total, DateTime now) {
    if (_lastSpeedSample.millisecondsSinceEpoch == 0) {
      _lastSpeedSample = now;
      _lastAckedForSpeed = acked;
      return;
    }
    final dt =
        now.difference(_lastSpeedSample).inMilliseconds / 1000.0;
    if (dt >= 1.0) {
      final delta = acked - _lastAckedForSpeed;
      final instantMbps = dt > 0 ? (delta / (1024 * 1024)) / dt : 0.0;
      _speedMbps = _speedMbps == 0.0
          ? instantMbps
          : _speedMbps * 0.6 + instantMbps * 0.4;
      _lastSpeedSample = now;
      _lastAckedForSpeed = acked;
      if (_speedMbps > 0.05 && total > acked) {
        _etaSeconds =
            ((total - acked) / (1024 * 1024) / _speedMbps).round();
      } else {
        _etaSeconds = 0;
      }
    }
  }

  String _speedLabel() {
    if (_speedMbps <= 0) return '';
    final eta = _etaSeconds > 0 ? ' • ${_formatEta(_etaSeconds)}' : '';
    return ' • ${_speedMbps.toStringAsFixed(1)} Mo/s$eta';
  }

  String _formatEta(int seconds) {
    if (seconds < 60) return '${seconds}s restantes';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m${s.toString().padLeft(2, '0')} restantes';
  }

  Future<void> _startFileTransfer() async {
    // La découverte (broadcast/sweep/ARP) consomme CPU + réseau :
    // pause pendant le transfert, reprise à la fin.
    widget.discoveryService.setDiscoverable(false);
    setState(() {
      _isTransferring = true;
      _isPaused = false;
      _statusMessage = 'Envoi en cours...';
      _speedMbps = 0.0;
      _etaSeconds = 0;
      _ackedBytes = 0;
      _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
      _lastSpeedSample = DateTime.now();
      _lastAckedForSpeed = 0;
    });
    final sessionId = _currentTransferId!;
    // Polling des octets réellement écrits (vérité receveur).
    late final Timer ackTimer;
    ackTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isTransferring || !mounted) return;
      final ack = await _httpService.fetchAckedProgress(sessionId);
      if (ack == null || !mounted) return;
      final now = DateTime.now();
      _ackedBytes = ack.totalReceived;
      _totalBytesToReceive = ack.totalSize;
      _updateSpeedEta(ack.totalReceived, ack.totalSize, now);
      for (final e in ack.perFile.entries) {
        final size = ack.perFileSize[e.key] ?? 0;
        _fileProgress[e.key] = size > 0 ? e.value / size : 0.0;
      }
      setState(() {
        _progress = ack.totalSize > 0
            ? ack.totalReceived / ack.totalSize
            : 0.0;
        // Badge court : le détail (Mo/%) est déjà dans la section progrès.
        _statusMessage = 'Envoi en cours...${_speedLabel()}';
      });
      // Fractions par fichier à partir des octets acquittés.
      // (Tailles connues via _cachedFileSizes si dispo.)
    });
    try {
      await _httpService.sendFiles(
        _selectedFiles,
        sessionId,
        (totalSent, totalSize) {
          // Optimiste (socket) : n'écrase pas la barre si l'ack est dispo.
          if (_ackedBytes == 0) {
            final now = DateTime.now();
            if (now.difference(_lastUiUpdate).inMilliseconds < 500 &&
                totalSent < totalSize) {
              return;
            }
            _lastUiUpdate = now;
            if (!mounted) return;
            setState(() {
              _totalBytesToReceive = totalSize;
              _progress = totalSize > 0 ? totalSent / totalSize : 0.0;
              _statusMessage = 'Envoi en cours...';
            });
          }
        },
        () {
          ackTimer.cancel();
          widget.discoveryService.setDiscoverable(true);
          setState(() {
            _isTransferring = false;
            _progress = 1.0;
            _statusMessage = 'Envoi terminé !';
            _currentTransferId = null;
            _fileProgress.clear();
            _speedMbps = 0.0;
            _etaSeconds = 0;
            _ackedBytes = 0;
          });
          AudioService.instance.playFileReceived();
          _notify('Fichiers envoyés avec succès !', icon: Icons.check_circle_outline_rounded);
        },
        onFileProgress: (fileIndex, fileSent, fileSize) {
          if (_ackedBytes > 0) return; // l'ack pilote l'UI dès qu'il arrive
          final now = DateTime.now();
          if (now.difference(_lastUiUpdate).inMilliseconds < 500 &&
              fileSent < fileSize) {
            return;
          }
          if (!mounted) return;
          setState(() {
            _fileProgress[fileIndex] = fileSize > 0 ? fileSent / fileSize : 0.0;
          });
        },
        tokens: _fileTokens.isEmpty ? null : _fileTokens,
      );
    } catch (e) {
      ackTimer.cancel();
      widget.discoveryService.setDiscoverable(true);
      // Cancel (local ou 499 receveur) n'est pas une erreur : état propre.
      // Ne pas écraser un message plus précis déjà affiché (ex. annulé
      // par l'autre appareil via le canal de contrôle).
      final cancelled = e is TransferCancelled || e.toString().contains('(499)');
      final alreadyCancelled = _statusMessage.toLowerCase().contains('annul');
      setState(() {
        _isConnecting = false;
        _isTransferring = false;
        if (!alreadyCancelled) {
          _statusMessage = cancelled ? 'Transfert annulé' : 'Erreur : $e';
        }
      });
      if (!cancelled) {
        _notify('Erreur de transfert', icon: Icons.error_outline);
      }
    }
  }

  // ─────────────── SETTINGS ───────────────

  void _openSettings(BuildContext context) {
    final themeService = context.read<ThemeService>();
    final isMobile = MediaQuery.of(context).size.width <= 800;
    if (isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            themeService: themeService,
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: 480,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SettingsScreen(
                themeService: themeService,
              ),
            ),
          ),
        ),
      );
    }
  }

  /// Notification unifiée - colorée, une seule à la fois.
  void _notify(String msg, {IconData? icon}) {
    // Retire la notification précédente
    if (_currentNotification != null && _currentNotification!.mounted) {
      _currentNotification!.remove();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: 60,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () {
                if (_currentNotification != null &&
                    _currentNotification!.mounted) {
                  _currentNotification!.remove();
                  _currentNotification = null;
                }
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                builder: (_, v, child) => Opacity(
                  opacity: v.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, -10 * (1 - v)),
                    child: child,
                  ),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.primary.withAlpha(60)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          msg,
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _currentNotification = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentNotification != null &&
          _currentNotification!.mounted &&
          _currentNotification == entry) {
        _currentNotification!.remove();
        _currentNotification = null;
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

  // ─────────────── MOBILE ───────────────

  Widget _buildMobileLayout() {
    final colorScheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: colorScheme.surfaceContainerLow,
        statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: colorScheme.surface,
        systemNavigationBarIconBrightness: isLight
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: colorScheme.surfaceContainerLow,
          title: Text(
            'GoSend',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: colorScheme.primary,
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
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                  onPressed: widget.onRefresh,
                  tooltip: 'Rafraîchir la découverte',
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Paramètres',
              onPressed: () => _openSettings(context),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'invisible') {
                  setState(() => widget.discoveryService.toggleDiscoverability());
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
              const SizedBox(height: 8),
              _buildSearchField(),
              const SizedBox(height: 16),
              if (_selectedDevice != null) _buildSendButton(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── DESKTOP ───────────────

  Widget _buildDesktopLayout() {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar ──
          Container(
            width: 300,
            margin: const EdgeInsets.fromLTRB(16, 16, 8, 16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Brand
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: colorScheme.surface),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(borderRadius: const BorderRadius.all(Radius.circular(12)), color: colorScheme.primary),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GoSend', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: colorScheme.onSurface, letterSpacing: -0.5)),
                            const SizedBox(height: 3),
                            Row(children: [
                              AnimatedBuilder(
                                animation: _pulseAnimation,
                                builder: (_, __) => Transform.scale(
                                  scale: _pulseAnimation.value,
                                  child: Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.success)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(widget.localDeviceName, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                            ]),
                          ],
                        )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _buildSearchField()),
                const SizedBox(height: 20),
                // Status pill
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: colorScheme.onSurface.withAlpha(8)),
                    child: Row(children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (_, __) => Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.devices.isNotEmpty ? colorScheme.onSurface : colorScheme.onSurfaceVariant)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        widget.devices.isNotEmpty ? '${widget.devices.length} appareil(s)' : 'Recherche...',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500),
                      )),
                      IconButton(
                        icon: Icon(widget.discoveryService.isDiscoverable ? Icons.visibility : Icons.visibility_off, size: 16, color: colorScheme.onSurfaceVariant),
                        onPressed: () => setState(() => widget.discoveryService.toggleDiscoverability()),
                        tooltip: 'Visibilité', constraints: const BoxConstraints(), padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.refresh, size: 16, color: colorScheme.onSurfaceVariant),
                        onPressed: widget.onRefresh, tooltip: 'Rafraîchir',
                        constraints: const BoxConstraints(), padding: EdgeInsets.zero,
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: _buildDevicesSection(isMobile: false)),
              ],
            ),
          ),

          // ── Zone droite : onglets Envoi / Paramètres ──
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 16, 16, 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(50)),
              ),
              child: Column(
                children: [
                  // Titre bar + tab bar
                  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
                    CustomTitleBar(isLight: Theme.of(context).brightness == Brightness.light),
                  // Tab selector
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Row(
                      children: [
                        _buildTabButton(0, Icons.send_rounded, 'Envoi'),
                        const SizedBox(width: 8),
                        _buildTabButton(1, Icons.settings_outlined, 'Paramètres'),
                        const Spacer(),
                        if (_selectedTab == 0) ...[
                          Expanded(child: _buildStatusBadge()),
                          const SizedBox(width: 16),
                          if (_selectedDevice != null) _buildSendButton(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Contenu de l'onglet sélectionné
                  Expanded(
                    child: _selectedTab == 0
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                            child: _buildFilesCard(isMobile: false),
                          )
                        : SettingsScreen(
                            themeService: context.read<ThemeService>(),
                            receiveDirectoryPath: _receiveDirectoryPath,
                            onOpenReceiveDirectory: _openReceiveDirectory,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? colorScheme.primary.withAlpha(15) : Colors.transparent,
          border: Border.all(
            color: selected ? colorScheme.primary.withAlpha(60) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final colorScheme = Theme.of(context).colorScheme;
    if (widget.devices.isEmpty) return const SizedBox.shrink();
    return TextField(
      controller: _deviceSearchController,
      style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
      decoration: InputDecoration(
        hintText: 'Rechercher un appareil...',
        hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        filled: true,
        fillColor: colorScheme.onSurface.withAlpha(6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
    );
  }

  // ─────────────── STATUS CARD (Mobile) ───────────────

  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = widget.devices.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? colorScheme.primary.withAlpha(20)
                          : colorScheme.tertiary.withAlpha(20),
                    ),
                    child: Icon(
                      Icons.wifi_tethering,
                      size: 24,
                      color:
                          isActive ? colorScheme.primary : colorScheme.tertiary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? 'Réseau actif' : 'Recherche en cours...',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isActive
                          ? '${widget.devices.length} appareil(s) détecté(s)'
                          : 'En attente d\'autres appareils GoSend sur le Wi-Fi',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_receiveDirectoryPath != null) ...[
            const SizedBox(height: 12),
            _buildDownloadPath(),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadPath() {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _openReceiveDirectory,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: colorScheme.onSurface.withAlpha(5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.download_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  _receiveDirectoryPath ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: _isTransferring
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: colorScheme.onSurface,
                  ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _statusMessage,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────── FILES CARD ───────────────

  Widget _buildFilesCard({required bool isMobile}) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragDone: (details) {
        setState(() {
          _selectedFiles.addAll(details.files.map((f) => File(f.path)));
          _isDragging = false;
        });
        if (details.files.isNotEmpty) {
          AudioService.instance.playFileAdded();
        }
      },
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.all(isMobile ? 20 : 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: _isDragging
              ? colorScheme.primary.withAlpha(8)
              : colorScheme.surface,
          border: Border.all(
            color: _isDragging
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: _isDragging ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: colorScheme.secondary.withAlpha(25),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Fichiers à envoyer',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: isMobile ? 16 : 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => isMobile ? _showAddMobileSheet() : _showAddDesktopMenu(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(isMobile ? 'Ajouter' : 'Ajouter'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    textStyle: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Empty state or file list
            if (_selectedFiles.isEmpty)
              _buildEmptyDropZone(isMobile: isMobile)
            else
              _buildFilesList(),

            // Progress section
            if (_isTransferring) ...[
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              _buildProgressSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDropZone({required bool isMobile}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: isMobile ? 160 : 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            size: isMobile ? 40 : 52,
            color: colorScheme.onSurfaceVariant.withAlpha(100),
          ),
          const SizedBox(height: 14),
          Text(
            isMobile ? 'Appuie sur "Ajouter"' : 'Glisse tes fichiers ici',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(height: 4),
            Text(
              'ou clique sur "Ajouter" pour choisir',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Progress bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colorScheme.onSurface.withAlpha(5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatProgress(_progress, _totalBytesToReceive),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withAlpha(150),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      // Background track
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      // Barre de progression - couleur primaire unie
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 300),
                        widthFactor: _progress,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.circular(6)),
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Control buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Pause / Resume
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    if (_isPaused) {
                      _resumeTransfer();
                    } else {
                      _pauseTransfer();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _isPaused ? Icons.play_arrow : Icons.pause,
                      size: 20,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Cancel
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    _cancelTransfer();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilesList() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth > 400;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _selectedFiles.map((file) {
                final name = file.path.split(Platform.pathSeparator).last;
                return SizedBox(
                  width: isDesktop
                      ? (constraints.maxWidth - 10) / 2
                      : double.infinity,
                  child: _buildFileItem(file, name),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => setState(() => _selectedFiles.clear()),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: colorScheme.onSurface.withAlpha(5),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.clear_all,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Vider',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileItem(File file, String name) {
    final colorScheme = Theme.of(context).colorScheme;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
    final fileIndex = _selectedFiles.indexOf(file);
    final progress = _fileProgress[fileIndex] ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.onSurface.withAlpha(5),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Row(
        children: [
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
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                _buildCachedSizeText(file, colorScheme),
                if (_isTransferring && progress > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: colorScheme.outlineVariant,
                            ),
                          ),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 300),
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _selectedFiles.remove(file)),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileIconBox(String name) {
    final ext = name.contains('.') ? name.split('.').last : '';
    final c = AppTheme.fileTypeColor(ext);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: c.withAlpha(25),
      ),
      child: Icon(
        _iconForFile(name),
        size: 22,
        color: c,
      ),
    );
  }

  // ─────────────── DEVICES SECTION ───────────────

  Widget _buildDevicesSection({required bool isMobile}) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredDevices = widget.devices
        .where(
          (d) =>
              d.name.toLowerCase().contains(_deviceSearchQuery) ||
              d.ip.contains(_deviceSearchQuery),
        )
        .toList();

    return Column(
      mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
      children: [
        _buildLocalDeviceCard(isMobile),
        const SizedBox(height: 12),
        if (widget.devices.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 0 : 16,
              vertical: 8,
            ),
            child: Row(
              children: [
                Text(
                  'Appareils détectés',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isMobile ? 15 : 13,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.devices.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _buildSelectionHint(isMobile),
          const SizedBox(height: 8),
        ],
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

  Widget _buildSelectionHint(bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 0 : 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.onSurface.withAlpha(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Astuce : sélectionne un appareil ci-dessous, puis appuie sur Envoyer pour transmettre tes fichiers.',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalDeviceCard(bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: isMobile ? null : const EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 16,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withAlpha(20),
                ),
                child: Icon(
                  _iconForOs(Platform.operatingSystem),
                  size: isMobile ? 16 : 18,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.localDeviceName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: isMobile ? 13 : 12,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: colorScheme.onSurface.withAlpha(8),
                      ),
                      child: Text(
                        widget.localIpAddress,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: isMobile ? 11 : 10,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: colorScheme.primary.withAlpha(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint, size: 10, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            widget.localDeviceId.length >= 8
                                ? widget.localDeviceId.substring(0, 8).toUpperCase()
                                : widget.localDeviceId.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w400,
                              color: colorScheme.primary.withAlpha(180),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Badge droite : Moi
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: colorScheme.primary.withAlpha(15),
                ),
                child: Text(
                  'Moi',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDevicesState(bool isMobile) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.all(isMobile ? 0 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_other,
            size: 40,
            color: colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 12),
          Text(
            'Aucun appareil',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Ouvre GoSend sur un autre appareil sur le même Wi-Fi',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesList(bool isMobile, List<dynamic> devices) {
    final deviceWidgets = devices.map((device) {
      final isSelected = _selectedDevice?.id == device.id;
      final colorScheme = Theme.of(context).colorScheme;
      return GestureDetector(
        onTap: () =>
            setState(() => _selectedDevice = isSelected ? null : device),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.symmetric(
            horizontal: isMobile ? 0 : 16,
            vertical: 5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected
                ? colorScheme.primary.withAlpha(10)
                : colorScheme.surface,
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withAlpha(60),
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
                  color: isSelected 
                      ? colorScheme.primary.withAlpha(25)
                      : colorScheme.onSurface.withAlpha(10),
                ),
                child: Icon(
                  _iconForOs(device.os),
                  size: 20,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: colorScheme.onSurface.withAlpha(8),
                      ),
                      child: Text(
                        device.ip,
                        style: GoogleFonts.jetBrainsMono(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: colorScheme.primary.withAlpha(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fingerprint,
                            size: 9,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            device.id.length >= 8
                                ? device.id.substring(0, 8).toUpperCase()
                                : device.id.toUpperCase(),
                            style: GoogleFonts.jetBrainsMono(
                              color: colorScheme.primary.withAlpha(180),
                              fontSize: 9,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: colorScheme.onPrimary,
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: deviceWidgets,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: deviceWidgets,
    );
  }

  // ─────────────── SEND BUTTON ───────────────

  Widget _buildSendButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return FilledButton.icon(
      onPressed: _isConnecting || _isTransferring ? null : _sendFiles,
      icon: _isConnecting || _isTransferring
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            )
          : const Icon(Icons.send_rounded, size: 18),
      label: Text(
        _isConnecting
            ? 'Connexion...'
            : _isTransferring
            ? 'Envoi...'
            : 'Envoyer',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Taille disque cachée : 1 seul stat par fichier (pas par rebuild).
  Widget _buildCachedSizeText(File file, ColorScheme colorScheme) {
    final cached = _cachedFileSizes[file.path];
    if (cached == null) {
      file.length().then((size) {
        if (!mounted) return;
        _cachedFileSizes[file.path] = size;
        setState(() {});
      });
      return const SizedBox();
    }
    return Text(
      _formatSize(cached),
      style: TextStyle(
        fontSize: 11,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  // ─────────────── HELPERS ───────────────

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatProgress(double progress, int totalBytes) {
    final receivedMB = (progress * totalBytes) / (1024 * 1024);
    final totalMB = totalBytes / (1024 * 1024);
    final percent = (progress * 100).toStringAsFixed(1);
    return '${receivedMB.toStringAsFixed(1)} / ${totalMB.toStringAsFixed(1)} MB ($percent%)';
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
    
    // Images
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'ico', 'tiff', 'heic', 'heif'].contains(ext)) {
      return Icons.image;
    }
    
    // Videos
    if (['mp4', 'avi', 'mov', 'mkv', 'wmv', 'flv', 'webm', 'm4v', '3gp'].contains(ext)) {
      return Icons.movie;
    }
    
    // Audio
    if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus'].contains(ext)) {
      return Icons.music_note;
    }
    
    // Documents
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    
    // Code
    if (['js', 'ts', 'jsx', 'tsx'].contains(ext)) return Icons.javascript;
    if (['html', 'css', 'scss', 'sass'].contains(ext)) return Icons.code;
    if (['dart', 'java', 'kt', 'swift'].contains(ext)) return Icons.developer_mode;
    if (['py', 'rb', 'php', 'go'].contains(ext)) return Icons.terminal;
    if (['json', 'xml', 'yaml', 'yml'].contains(ext)) return Icons.data_object;
    
    // Archives
    if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2'].contains(ext)) return Icons.archive;
    
    // Executables
    if (['exe', 'msi', 'dmg', 'app', 'apk', 'ipa'].contains(ext)) return Icons.apps;
    
    // Fonts
    if (['ttf', 'otf', 'woff', 'woff2'].contains(ext)) return Icons.font_download;
    
    // 3D / CAD
    if (['obj', 'fbx', 'stl', 'blend', '3ds'].contains(ext)) return Icons.view_in_ar;
    
    // Database
    if (['db', 'sqlite', 'sql', 'mdb'].contains(ext)) return Icons.storage;
    
    // Text / Config
    if (['txt', 'md', 'rtf', 'log'].contains(ext)) return Icons.article;
    
    return Icons.insert_drive_file;
  }
}

// Animated version of FractionallySizedBox for smooth progress
class AnimatedFractionallySizedBox extends ImplicitlyAnimatedWidget {
  final double widthFactor;
  final Widget child;

  const AnimatedFractionallySizedBox({
    super.key,
    required super.duration,
    required this.widthFactor,
    required this.child,
  });

  @override
  AnimatedFractionallySizedBoxState createState() =>
      AnimatedFractionallySizedBoxState();
}

class AnimatedFractionallySizedBoxState
    extends AnimatedWidgetBaseState<AnimatedFractionallySizedBox> {
  Tween<double>? _widthTween;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _widthTween =
        visitor(
              _widthTween,
              widget.widthFactor,
              (value) => Tween<double>(begin: value as double),
            )
            as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: _widthTween?.evaluate(animation) ?? widget.widthFactor,
      child: widget.child,
    );
  }
}
