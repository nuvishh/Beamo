import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FileTypeMeta {
  final IconData icon;
  final Color color;
  final String label;

  const FileTypeMeta({
    required this.icon,
    required this.color,
    required this.label,
  });
}

class FileTypeHelper {
  static FileTypeMeta getMeta(String filename) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';

    switch (ext) {
      // Video
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'webm':
        return const FileTypeMeta(
          icon: Icons.movie_outlined,
          color: AppTheme.beamPurple,
          label: 'VIDEO',
        );

      // Audio
      case 'mp3':
      case 'flac':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
        return const FileTypeMeta(
          icon: Icons.music_note_outlined,
          color: AppTheme.beamRose,
          label: 'AUDIO',
        );

      // Images
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
      case 'svg':
        return const FileTypeMeta(
          icon: Icons.image_outlined,
          color: AppTheme.beamAmber,
          label: 'IMAGE',
        );

      // Android Apps
      case 'apk':
      case 'aab':
      case 'xapk':
        return const FileTypeMeta(
          icon: Icons.android_rounded,
          color: AppTheme.beamEmerald,
          label: 'APK',
        );

      // Archives
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return const FileTypeMeta(
          icon: Icons.folder_zip_outlined,
          color: AppTheme.beamCyan,
          label: 'ARCHIVE',
        );

      // Documents
      case 'pdf':
        return const FileTypeMeta(
          icon: Icons.picture_as_pdf_outlined,
          color: Color(0xFFEF4444),
          label: 'PDF',
        );
      case 'doc':
      case 'docx':
      case 'txt':
      case 'csv':
      case 'xlsx':
      case 'pptx':
        return const FileTypeMeta(
          icon: Icons.description_outlined,
          color: AppTheme.beamBlue,
          label: 'DOCUMENT',
        );

      default:
        return const FileTypeMeta(
          icon: Icons.insert_drive_file_outlined,
          color: AppTheme.beamIndigo,
          label: 'FILE',
        );
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
