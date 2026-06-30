import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';

class FileThumbnailWidget extends StatelessWidget {
  final String filePath;
  final VoidCallback? onDelete;
  final bool isUploading;
  final double uploadProgress;

  const FileThumbnailWidget({
    required this.filePath,
    this.onDelete,
    this.isUploading = false,
    this.uploadProgress = 0.0,
  });

  String get fileName => filePath.split('/').last;

  String get fileSize {
    try {
      final file = File(filePath);
      final bytes = file.lengthSync();
      if (bytes < 1024) {
        return '$bytes B';
      } else if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      } else {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    } catch (e) {
      return 'N/A';
    }
  }

  IconData get fileIcon {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image_rounded;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_file_rounded;
      case 'mp3':
      case 'wav':
        return Icons.audio_file_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentGreen = Color(0xFF336B4E);
    const bgDark = Color(0xFF0D0D0D);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentGreen.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ['jpg', 'jpeg', 'png', 'gif'].contains(filePath.split('.').last.toLowerCase())
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(filePath),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            fileIcon,
                            color: accentGreen,
                            size: 20,
                          ),
                        ),
                      )
                    : Icon(
                        fileIcon,
                        color: accentGreen,
                        size: 20,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fileSize,
                      style: GoogleFonts.inter(
                        color: const Color(0xFFCCCCCC),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isUploading && onDelete != null)
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.redAccent.withValues(alpha: 0.6),
                    size: 18,
                  ),
                ),
            ],
          ),
          if (isUploading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: uploadProgress,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(accentGreen),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(uploadProgress * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.inter(
                color: accentGreen,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
