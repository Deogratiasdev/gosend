import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../widgets/file_thumbnail.dart';
import '../widgets/notification_system.dart';
import '../../services/file_client.dart';
import '../../services/transfer_service.dart';
import 'dart:io';

class SendFilesPage extends StatefulWidget {
  final String deviceName;
  final String deviceIP;
  final List<String>? initialFiles;
  final VoidCallback? onSendFiles;

  const SendFilesPage({
    super.key,
    required this.deviceName,
    required this.deviceIP,
    this.initialFiles,
    this.onSendFiles,
  });

  @override
  State<SendFilesPage> createState() => _SendFilesPageState();
}

class _SendFilesPageState extends State<SendFilesPage> {
  List<String> selectedFiles = [];
  bool isSending = false;
  double sendProgress = 0.0;
  bool isDraggingOver = false;

  static const Color _accentGreen = Color(0xFF336B4E);
  static const Color _bgDark = Color(0xFF0D0D0D);
  static const Color _textSecondary = Color(0xFFCCCCCC);

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles != null) {
      selectedFiles.addAll(widget.initialFiles!);
    }
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );

      if (result != null) {
        setState(() {
          selectedFiles.addAll(result.files.map((f) => f.path ?? ''));
          selectedFiles.removeWhere((f) => f.isEmpty);
        });

        if (!mounted) return;
        await NotificationOverlay.success(
          context,
          title: 'Fichiers sélectionnés',
          message:
              '${result.files.length} fichier(s) prêt(s) pour l\'envoi',
        );
      }
    } catch (e) {
      if (!mounted) return;
      await NotificationOverlay.error(
        context,
        title: 'Erreur',
        message: 'Impossible de sélectionner les fichiers',
      );
    }
  }

  void _removeFile(int index) {
    setState(() {
      selectedFiles.removeAt(index);
    });
  }

  Future<void> _sendFiles() async {
    if (selectedFiles.isEmpty) {
      await NotificationOverlay.warning(
        context,
        title: 'Aucun fichier',
        message: 'Sélectionnez au moins un fichier à envoyer',
      );
      return;
    }

    setState(() {
      isSending = true;
      sendProgress = 0.0;
    });

    try {
      // Envoi réel des fichiers
      final client = FileClient(
        onProgress: (progress) {
          setState(() {
            sendProgress = progress;
          });
        },
      );
      
      final files = selectedFiles.map((path) => File(path)).toList();
      final success = await client.sendFiles(widget.deviceIP, 8765, files);

      if (!success) {
        throw Exception('Échec de l\'envoi');
      }

      // Add to history
      for (final filePath in selectedFiles) {
        final file = File(filePath);
        final fileName = file.uri.pathSegments.last;
        final fileSize = file.lengthSync();
        final String formattedSize = fileSize < 1024 * 1024 
            ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
            : '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
            
        await TransferService.instance.addHistoryEntry({
          'filename': fileName,
          'size': formattedSize,
          'type': 'sent',
          'timestamp': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          'status': 'success',
        });
      }

      if (!mounted) return;
      await NotificationOverlay.success(
        context,
        title: 'Fichiers envoyés',
        message: '${selectedFiles.length} fichier(s) envoyé(s) avec succès',
      );

      setState(() {
        selectedFiles.clear();
        isSending = false;
        sendProgress = 0.0;
      });

      widget.onSendFiles?.call();
    } catch (e) {
      if (!mounted) return;
      await NotificationOverlay.error(
        context,
        title: 'Erreur d\'envoi',
        message: 'Une erreur s\'est produite lors de l\'envoi',
      );
      setState(() {
        isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Container(
      color: _bgDark,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: _accentGreen.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.send_rounded,
                      color: _accentGreen,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Envoyer des fichiers',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'À: ${widget.deviceName} (${widget.deviceIP})',
                            style: GoogleFonts.inter(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drop Zone
                  DropTarget(
                    onDragEntered: (detail) {
                      setState(() => isDraggingOver = true);
                    },
                    onDragExited: (detail) {
                      setState(() => isDraggingOver = false);
                    },
                    onDragDone: (detail) async {
                      setState(() => isDraggingOver = false);
                      final paths = detail.files
                          .map((f) => f.path)
                          .toList();
                      setState(() {
                        selectedFiles.addAll(paths);
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 40,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: isDraggingOver
                            ? _accentGreen.withValues(alpha: 0.1)
                            : Colors.white.withValues(alpha: 0.02),
                        border: Border.all(
                          color: isDraggingOver
                              ? _accentGreen.withValues(alpha: 0.5)
                              : _accentGreen.withValues(alpha: 0.2),
                          width: 2,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isDraggingOver
                            ? [
                                BoxShadow(
                                  color: _accentGreen.withValues(alpha: 0.2),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.cloud_upload_rounded,
                            color: _accentGreen,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Glissez-déposez vos fichiers ici',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ou',
                            style: GoogleFonts.inter(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _pickFiles,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                              'Sélectionner les fichiers',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Files Grid
                  if (selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Fichiers à envoyer (${selectedFiles.length})',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isMobile ? 1 : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 4,
                      ),
                      itemCount: selectedFiles.length,
                      itemBuilder: (context, index) {
                        return FileThumbnailWidget(
                          filePath: selectedFiles[index],
                          onDelete: () => _removeFile(index),
                          isUploading: isSending,
                          uploadProgress: sendProgress,
                        );
                      },
                    ),
                  ],

                  // Total Size
                  if (selectedFiles.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _accentGreen.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Taille totale',
                            style: GoogleFonts.inter(
                              color: _textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _calculateTotalSize(),
                            style: GoogleFonts.inter(
                              color: _accentGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Footer - Send Button
          if (selectedFiles.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border(
                  top: BorderSide(
                    color: _accentGreen.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isSending ? null : _sendFiles,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(
                    isSending
                        ? 'Envoi en cours... ${(sendProgress * 100).toStringAsFixed(0)}%'
                        : 'Envoyer ${selectedFiles.length} fichier(s)',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        _accentGreen.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _calculateTotalSize() {
    try {
      int totalBytes = 0;
      for (final filePath in selectedFiles) {
        final file = File(filePath);
        totalBytes += file.lengthSync();
      }

      if (totalBytes < 1024) {
        return '$totalBytes B';
      } else if (totalBytes < 1024 * 1024) {
        return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
      } else if (totalBytes < 1024 * 1024 * 1024) {
        return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      }
    } catch (e) {
      return 'N/A';
    }
  }
}
