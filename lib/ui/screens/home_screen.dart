import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/network/discovery_service.dart';
import '../../core/network/http_transfer_service.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/theme/theme_service.dart';
import '../../models/device.dart';
import '../../models/transfer_request.dart';
import '../widgets/custom_title_bar.dart';
import 'text_message_screen.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  String? _currentTransferId;
  bool _isPaused = false;
  final TextEditingController _deviceSearchController = TextEditingController();
  String _deviceSearchQuery = '';
  static const platform = MethodChannel('com.example.gosend/share');
  String? _receiveDirectoryPath;

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
    _httpService.startServers().catchError((Object e) {
      debugPrint('Erreur démarrage serveurs HTTP: $e');
      _showSnack('Erreur ouverture ports 8080/8081 : $e');
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
          _showSnack('Ouverture du dossier non supportée sur cette plateforme');
        }
      } catch (e) {
        debugPrint('Erreur ouverture dossier: $e');
        _showSnack('Erreur ouverture dossier : $e');
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

  void _handleTransferResponse(String requestId, bool accepted) {
    if (accepted) {
      _currentTransferId = requestId;
      _showStatusBanner(
        '✅ Demande acceptée — transfert en cours…',
        type: 'success',
      );
      _startFileTransfer();
    } else {
      setState(() {
        _statusMessage = 'Transfert refusé';
        _isConnecting = false;
        _isTransferring = false;
      });
      _showStatusBanner(
        '❌ Demande refusée par l\'appareil distant',
        type: 'error',
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
      setState(() {
        _isTransferring = false;
        _statusMessage = 'Transfert annulé par l\'autre appareil';
      });
      _httpService.cancelTransfer();
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
              _httpService.prepareReceive(
                request.id,
                request.files,
                saveDir,
                (fileIndex, received, total) {
                  setState(() {
                    _totalBytesToReceive = total;
                    _isTransferring = true;
                    _progress = total > 0 ? received / total : 0.0;
                    _statusMessage =
                        'Réception : ${request.files[fileIndex].name}';
                  });
                },
                (fileIndex, fileReceived, fileSize) {
                  setState(() {
                    _fileProgress[fileIndex] = fileSize > 0
                        ? fileReceived / fileSize
                        : 0.0;
                  });
                },
                (fileIndex, filePath) {
                  debugPrint('Fichier reçu: $filePath');
                },
                () {
                  setState(() {
                    _isTransferring = false;
                    _progress = 0.0;
                    _statusMessage = 'Transfert terminé !';
                    _fileProgress.clear();
                  });
                  _showSnack('Tous les fichiers enregistrés !');
                  NotificationService().showNotification(
                    title: 'Transfert terminé',
                    body: '${request.files.length} fichier(s) reçu(s)',
                  );
                },
              );
              await _httpService.sendTransferResponse(request.id, true);
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
    if (result != null) {
      setState(
        () => _selectedFiles.addAll(
          result.paths.whereType<String>().map(File.new),
        ),
      );
    }
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(
        () => _selectedFiles.addAll(pickedFiles.map((x) => File(x.path))),
      );
    }
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result != null) {
      setState(
        () => _selectedFiles.addAll(
          result.paths.whereType<String>().map(File.new),
        ),
      );
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
    final colorScheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.text_snippet_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Envoyer du texte',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Tape ton texte ici…',
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
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
    );

    if (text != null && text.isNotEmpty) {
      await _sendTextMessage(text);
    }
  }

  Future<void> _sendTextMessage(String text) async {
    if (_selectedDevice == null) {
      _showSnack('Sélectionne d\'abord un appareil dans la liste');
      return;
    }
    try {
      _httpService.connectToPeer(
        _selectedDevice!.ip,
        httpPort: _selectedDevice!.httpPort,
      );
      await _httpService.sendTextMessage(text, widget.localDeviceName);
      _showSnack('Message envoyé à ${_selectedDevice!.name}');
    } catch (e) {
      _showSnack('Erreur: $e');
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
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Message de $senderName',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} — '
                    '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')}/${timestamp.year}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.onSurface.withAlpha(6),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      height: 1.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              _showSnack('Texte copié !');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copier'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFiles() async {
    if (_selectedDevice == null) {
      _showSnack('Sélectionne d\'abord un appareil dans la liste');
      return;
    }
    if (_selectedFiles.isEmpty) {
      _showSnack('Sélectionne d\'abord des fichiers à envoyer');
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
      _showStatusBanner(
        '⏳ Demande envoyée à ${_selectedDevice!.name}…',
        type: 'pending',
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = 'Erreur de connexion';
      });
      _showSnack('Erreur: $e');
    }
  }

  Future<void> _startFileTransfer() async {
    setState(() {
      _isTransferring = true;
      _isPaused = false;
      _statusMessage = 'Envoi en cours...';
    });
    try {
      await _httpService.sendFiles(
        _selectedFiles,
        _currentTransferId!,
        (totalSent, totalSize) {
          setState(() {
            _totalBytesToReceive = totalSize;
            _progress = totalSize > 0 ? totalSent / totalSize : 0.0;
            _statusMessage = 'Envoi en cours...';
          });
        },
        () {
          setState(() {
            _isTransferring = false;
            _progress = 1.0;
            _statusMessage = 'Envoi terminé !';
            _currentTransferId = null;
            _fileProgress.clear();
          });
          _showSnack('Fichiers envoyés avec succès !');
        },
        onFileProgress: (fileIndex, fileSent, fileSize) {
          setState(() {
            _fileProgress[fileIndex] = fileSize > 0 ? fileSent / fileSize : 0.0;
          });
        },
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isTransferring = false;
        _statusMessage = 'Erreur : $e';
      });
      _showSnack('Erreur de transfert');
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFE8E7E5)
                      : const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  msg,
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF141414)
                        : Colors.white,
                    fontSize: 14,
                  ),
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

  /// Affiche un banner non-bloquant stylisé pour les statuts de transfert.
  /// [type]: 'pending' | 'success' | 'error'
  void _showStatusBanner(String message, {String type = 'pending'}) {
    OverlayEntry? entry;

    final colors = switch (type) {
      'success' => (
          const Color(0xFF1A7A4A),
          const Color(0xFFDCF5E9),
          Icons.check_circle_outline_rounded
        ),
      'error' => (
          const Color(0xFF9B2525),
          const Color(0xFFFFEBEB),
          Icons.cancel_outlined
        ),
      _ => (
          const Color(0xFF2A4B8A),
          const Color(0xFFE8EEFF),
          Icons.schedule_rounded
        ),
    };
    final (darkBg, lightBg, icon) = colors;

    entry = OverlayEntry(
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final bg = isDark ? darkBg : lightBg;
        final textColor = isDark ? Colors.white : darkBg;
        return Positioned(
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
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  builder: (_, v, child) =>
                      Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -10 * (1 - v)), child: child)),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: darkBg.withAlpha(isDark ? 60 : 80),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: darkBg.withAlpha(isDark ? 40 : 25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: textColor),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            message,
                            style: TextStyle(
                              color: textColor,
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
        );
      },
    );

    Overlay.of(context).insert(entry!);
    Future.delayed(const Duration(seconds: 3), () {
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

  // ─────────────── MOBILE ───────────────

  Widget _buildMobileLayout() {
    final colorScheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: isLight
            ? const Color(0xFFFAF9F7)
            : const Color(0xFF141414),
        statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: colorScheme.surface,
        systemNavigationBarIconBrightness: isLight
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: isLight
              ? const Color(0xFFFAF9F7)
              : const Color(0xFF141414),
          title: Text(
            'GoSend',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800,
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
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                  onPressed: widget.onRefresh,
                  tooltip: 'Rafraîchir la découverte',
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Dossier de réception',
              onPressed: _openReceiveDirectory,
            ),
            IconButton(
              icon: const Icon(Icons.brightness_medium),
              tooltip: 'Thème',
              onPressed: () => _showThemeDialog(context),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'invisible') {
                  setState(
                    () => widget.discoveryService.toggleDiscoverability(),
                  );
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem(
                  value: 'invisible',
                  child: Row(
                    children: [
                      Icon(
                        widget.discoveryService.isDiscoverable
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.discoveryService.isDiscoverable
                            ? 'Rendre invisible'
                            : 'Rendre visible',
                      ),
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
              border: Border.all(
                color: colorScheme.outlineVariant.withAlpha(50),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Logo / Brand Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: colorScheme.surface,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: colorScheme.onSurface.withAlpha(10),
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            color: colorScheme.onSurface,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'GoSend',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (_, __) => Transform.scale(
                                      scale: _pulseAnimation.value,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      widget.localDeviceName,
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildSearchField(),
                ),
                const SizedBox(height: 20),
                // Status pill
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: colorScheme.onSurface.withAlpha(8),
                    ),
                    child: Row(
                      children: [
                        AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (_, __) => Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.devices.isNotEmpty
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.devices.isNotEmpty
                                ? '${widget.devices.length} appareil(s)'
                                : 'Recherche...',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            widget.discoveryService.isDiscoverable
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () => setState(
                            () =>
                                widget.discoveryService.toggleDiscoverability(),
                          ),
                          tooltip: 'Visibilité',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.refresh,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          onPressed: widget.onRefresh,
                          tooltip: 'Rafraîchir',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: _buildDevicesSection(isMobile: false)),
                const Divider(height: 1),
                _buildSidebarFooter(),
              ],
            ),
          ),

          // ── Main Content ──
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 16, 16, 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outlineVariant.withAlpha(50),
                ),
              ),
              child: Column(
                children: [
                  // Custom window title bar (desktop only)
                  if (Platform.isWindows ||
                      Platform.isMacOS ||
                      Platform.isLinux)
                    CustomTitleBar(
                      isLight: Theme.of(context).brightness == Brightness.light,
                    ),
                  // Top bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 24, 40, 0),
                    child: Row(
                      children: [
                        Expanded(child: _buildStatusBadge()),
                        const SizedBox(width: 20),
                        if (_selectedDevice != null) _buildSendButton(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Files area
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
                      child: _buildFilesCard(isMobile: false),
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

  Widget _buildSidebarFooter() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_receiveDirectoryPath != null)
          InkWell(
            onTap: _openReceiveDirectory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dossier de réception',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        InkWell(
          onTap: () => _showThemeDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.brightness_medium,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Thème',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _showThemeDialog(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    if (isMobile) {
      _showThemeBottomSheet(context);
    } else {
      _showThemeDesktopDialog(context);
    }
  }

  void _showThemeBottomSheet(BuildContext context) {
    final themeService = context.read<ThemeService>();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('Système'),
              subtitle: const Text('Utilise le thème du système'),
              onTap: () async {
                await themeService.setThemeMode(AppThemeMode.system);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.wb_sunny),
              title: const Text('Clair'),
              subtitle: const Text('Thème clair'),
              onTap: () async {
                await themeService.setThemeMode(AppThemeMode.light);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.nightlight_round),
              title: const Text('Sombre'),
              subtitle: const Text('Thème sombre'),
              onTap: () async {
                await themeService.setThemeMode(AppThemeMode.dark);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeDesktopDialog(BuildContext context) {
    final themeService = context.read<ThemeService>();

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          final colorScheme = Theme.of(ctx).colorScheme;
          final modes = [
            (AppThemeMode.system, Icons.brightness_auto, 'Système'),
            (AppThemeMode.light, Icons.wb_sunny_outlined, 'Clair'),
            (AppThemeMode.dark, Icons.nightlight_outlined, 'Sombre'),
          ];
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 24,
            ),
            alignment: Alignment.center,
            backgroundColor: colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      children: [
                        const Icon(Icons.palette_outlined, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          'Apparence',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ...modes.map((item) {
                    final (mode, icon, label) = item;
                    final selected = themeService.themeMode == mode;
                    return ListTile(
                      leading: Icon(
                        icon,
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      trailing: selected
                          ? Icon(Icons.check_rounded,
                              size: 18, color: colorScheme.primary)
                          : null,
                      onTap: () async {
                        await themeService.setThemeMode(mode);
                        setInner(() {});
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    );
                  }),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          );
        },
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
      child: Row(
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
                  color: colorScheme.onSurface.withAlpha(10),
                ),
                child: Icon(
                  Icons.wifi_tethering,
                  size: 24,
                  color: colorScheme.onSurface,
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
                    color: colorScheme.onSurface.withAlpha(10),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    size: 18,
                    color: colorScheme.onSurface,
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
                      // Animated progress fill
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 300),
                        widthFactor: _progress,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: colorScheme.onSurface,
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
                FutureBuilder<int>(
                  future: file.length(),
                  builder: (_, snap) {
                    if (!snap.hasData) return const SizedBox();
                    return Text(
                      _formatSize(snap.data!),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.onSurface.withAlpha(10),
      ),
      child: Icon(
        _iconForFile(name),
        size: 22,
        color: colorScheme.onSurfaceVariant,
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
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.onSurface.withAlpha(10),
            ),
            child: Icon(
              _iconForOs(Platform.operatingSystem),
              size: isMobile ? 16 : 18,
              color: colorScheme.onSurface,
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
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.localIpAddress,
                  style: GoogleFonts.inter(
                    fontSize: isMobile ? 11 : 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
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
                ? colorScheme.onSurface.withAlpha(10)
                : colorScheme.surface,
            border: Border.all(
              color: isSelected
                  ? colorScheme.onSurface
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
                  color: colorScheme.onSurface.withAlpha(10),
                ),
                child: Icon(
                  _iconForOs(device.os),
                  size: 20,
                  color: colorScheme.onSurface,
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
                    Text(
                      device.ip,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.onSurface,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: colorScheme.surface,
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
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Icons.image;
    if (['mp4', 'avi', 'mov', 'mkv'].contains(ext)) return Icons.movie;
    if (['mp3', 'wav', 'flac', 'aac'].contains(ext)) return Icons.music_note;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.archive;
    if (['doc', 'docx', 'txt'].contains(ext)) return Icons.description;
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
