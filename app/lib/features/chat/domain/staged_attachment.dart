/// A file the user picked but has not sent yet. PRD §8, DESIGN §4 (composer).
///
/// It exists in three states and the composer renders each differently:
/// staged (preview with a remove button), uploading (send disabled), and
/// uploaded (an `attachment_id` the question can be sent with).
library;

import 'dart:io';

class StagedAttachment {
  const StagedAttachment({
    required this.file,
    required this.name,
    required this.bytes,
    this.attachmentId,
    this.uploading = false,
    this.error,
  });

  final File file;
  final String name;

  /// Size after client-side downscaling — the number shown to the user, and
  /// the one that has to clear the 10 MB limit (PRD §8.5).
  final int bytes;

  /// Set once `POST /attachments` returns. Until then no question can carry it.
  final String? attachmentId;

  final bool uploading;
  final String? error;

  bool get isImage {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  bool get isReady => attachmentId != null && !uploading;

  /// "1.4 MB" — mono meta in the preview and in the sent bubble.
  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  StagedAttachment copyWith({
    String? attachmentId,
    bool? uploading,
    String? error,
    int? bytes,
  }) => StagedAttachment(
    file: file,
    name: name,
    bytes: bytes ?? this.bytes,
    attachmentId: attachmentId ?? this.attachmentId,
    uploading: uploading ?? this.uploading,
    error: error,
  );
}
