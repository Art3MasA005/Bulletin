/// Picking, downscaling, and uploading an attachment. PRD §8, DESIGN §4–§6.
///
/// The downscale is not an optimisation. A modern phone photograph is 12 MP
/// and 4 MB; the vision model reads a routine perfectly well at 2000px on the
/// long edge, the upload limit is 10 MB (PRD §8.5), and a student on campus
/// Wi-Fi pays for every byte of the difference. DESIGN §7 lists it as a
/// performance requirement rather than a nicety.
///
/// Upload happens as soon as the file is staged, not when the question is
/// sent: extraction takes seconds, and doing it while the user is still typing
/// is the difference between a wait and no wait at all.
library;

import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/config.dart';
import '../../../core/net/result.dart';
import '../../../core/providers.dart';
import '../../chat/domain/staged_attachment.dart';
import '../domain/extraction.dart';

class AttachmentState {
  const AttachmentState({this.staged, this.extraction, this.busy = false});

  final StagedAttachment? staged;

  /// What the vision model read, unconfirmed. CLAUDE.md #3: no answer may be
  /// generated from this until the user confirms it.
  final RoutineExtraction? extraction;

  final bool busy;

  bool get hasAttachment => staged != null;
  bool get canSend => staged == null || staged!.isReady;
}

class AttachmentController extends StateNotifier<AttachmentState> {
  AttachmentController(this._ref) : super(const AttachmentState());

  final Ref _ref;

  /// Stage a picked file: downscale if it is an image, then upload it.
  Future<void> stage(File file, {String? conversationId}) async {
    final name = p.basename(file.path);
    final prepared = await _downscale(file);
    final bytes = await prepared.length();

    state = AttachmentState(
      staged: StagedAttachment(file: prepared, name: name, bytes: bytes, uploading: true),
    );

    if (bytes > AppConfig.attachmentMaxMb * 1024 * 1024) {
      // Refused here rather than at the server so the user is told before
      // spending an upload on a file that cannot be accepted.
      state = AttachmentState(
        staged: state.staged!.copyWith(uploading: false, error: 'too_large'),
      );
      return;
    }

    final result = await _ref
        .read(apiClientProvider)
        .uploadAttachment(path: prepared.path, conversationId: conversationId);

    switch (result) {
      case Ok(:final value):
        state = AttachmentState(
          staged: state.staged!.copyWith(
            attachmentId: value['attachment_id'] as String?,
            uploading: false,
          ),
          extraction: RoutineExtraction.fromJson(value),
        );
      case Failure(:final kind, :final message):
        state = AttachmentState(
          staged: state.staged!.copyWith(uploading: false, error: message ?? kind.name),
        );
    }
  }

  /// Confirm the (possibly corrected) course codes. CLAUDE.md #3.
  Future<Result<void>> confirm(List<String> codes) async {
    final id = state.staged?.attachmentId;
    if (id == null) {
      return const Failure(FailureKind.conflict, message: 'nothing to confirm');
    }
    state = AttachmentState(
      staged: state.staged,
      extraction: state.extraction,
      busy: true,
    );

    final result = await _ref
        .read(apiClientProvider)
        .confirmAttachment(attachmentId: id, codes: codes);

    state = AttachmentState(
      staged: state.staged,
      extraction: state.extraction?.withConfirmed(codes),
      busy: false,
    );
    return switch (result) {
      Ok() => const Ok(null),
      Failure(:final kind, :final message) => Failure(kind, message: message),
    };
  }

  void clear() => state = const AttachmentState();

  /// Shrink a photograph before it leaves the phone.
  ///
  /// PDFs and anything not an image pass through untouched — a PDF is already
  /// compressed, and re-encoding it would lose the text layer the backend
  /// prefers to read.
  Future<File> _downscale(File file) async {
    final extension = p.extension(file.path).toLowerCase();
    const compressible = {'.jpg', '.jpeg', '.png', '.webp'};
    if (!compressible.contains(extension)) return file;

    try {
      final directory = await getTemporaryDirectory();
      final target = p.join(
        directory.path,
        'bulletin_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        target,
        minWidth: AppConfig.imageMaxEdge,
        minHeight: AppConfig.imageMaxEdge,
        quality: AppConfig.imageQuality,
        // Phone cameras write orientation in EXIF; without this a routine
        // photographed in portrait reaches the model rotated, and a rotated
        // table is exactly what the extraction cannot read.
        autoCorrectionAngle: true,
      );
      return result == null ? file : File(result.path);
    } catch (_) {
      // A compressor failure must not lose the user's photo.
      return file;
    }
  }
}

final attachmentControllerProvider =
    StateNotifierProvider<AttachmentController, AttachmentState>((ref) {
      return AttachmentController(ref);
    });
