import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/network/webrtc_service.dart';
import '../../models/device.dart';

class HomeScreen extends StatefulWidget {
  final List<Device> devices;
  final VoidCallback onRefresh;
  final String localDeviceName;

  const HomeScreen({
    super.key,
    required this.devices,
    required this.onRefresh,
    required this.localDeviceName,
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _webRTCService.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
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
        _isTransferring = true;
        _statusMessage = 'Envoi en cours...';
      });

      for (final file in _selectedFiles) {
        final size = await file.length();
        int sent = 0;
        final stream = file.openRead();
        await for (final chunk in stream) {
          _webRTCService.sendData(Uint8List.fromList(chunk));
          sent += chunk.length;
          setState(() {
            _progress = sent / size;
            _statusMessage =
                'Envoi : ${file.path.split(Platform.pathSeparator).last}';
          });
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }

      setState(() {
        _isTransferring = false;
        _progress = 1.0;
        _statusMessage = '✅ Envoi terminé !';
        _selectedFiles = [];
      });
      _showSnack('✅ Fichiers envoyés avec succès !');
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
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
              border: Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant.withAlpha(60),
                ),
              ),
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
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: widget.onRefresh,
                        tooltip: 'Rafraîchir',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(child: _buildDevicesSection(isMobile: false)),
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
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withAlpha(40),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%  —  $_statusMessage',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
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
    return Column(
      children: _selectedFiles.map((file) {
        final name = file.path.split(Platform.pathSeparator).last;
        final ext = name.contains('.')
            ? name.split('.').last.toLowerCase()
            : '';
        final isImage = [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
        ].contains(ext);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
      }).toList(),
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
    if (widget.devices.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(isMobile ? 0 : 20),
        child: isMobile
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withAlpha(60),
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

    final deviceWidgets = widget.devices.map((device) {
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
