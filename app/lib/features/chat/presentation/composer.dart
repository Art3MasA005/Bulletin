/// The composer, and the attach sheet behind its `+`. Handoff spec §4, §5.
///
/// Crystal glass (README §1; prototype composer: 16 px from the sides, 28
/// from the bottom, radius 28, padding 6), because it is fixed chrome — one
/// of the two `BackdropFilter` layers the blur budget allows on a screen
/// (DESIGN §7).
///
/// The send button has three states and they are not decoration:
///   inert     nothing typed and nothing attached
///   waiting   an attachment is still uploading — sending now would ask a
///             question about a file the server has not read
///   ready     brand, white arrow
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/motion/motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/bulletin_sheet.dart';
import '../../../core/widgets/crystal_glass.dart';
import '../../../core/widgets/line_icons.dart';
import '../../../l10n/app_localizations.dart';
import '../../attachments/data/attachment_controller.dart';
import '../domain/staged_attachment.dart';

class Composer extends ConsumerWidget {
  const Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.hint,
    this.sending = false,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final String hint;
  final bool sending;

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final attachment = ref.watch(attachmentControllerProvider);

    // Crystal glass with its blur: fixed chrome, one of the screen's two
    // BackdropFilters (CLAUDE.md #11). Placement is the parent's job.
    return CrystalGlass(
      borderRadius: _radius,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            if (attachment.staged case final staged?)
              _AttachmentPreview(
                staged: staged,
                onRemove: () => ref.read(attachmentControllerProvider.notifier).clear(),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 6,
              children: [
                _AttachButton(
                  semanticLabel: l.attachAction,
                  onTap: sending ? null : () => openAttachFlow(context, ref),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    // 124 px at most, as in the prototype: four lines.
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: BulletinText.messageBody,
                    cursorColor: BulletinColors.brandStrong,
                    decoration: InputDecoration(
                      hintText: hint,
                      // One line: a long Bangla hint must not make the bar taller.
                      hintMaxLines: 1,
                      hintStyle: BulletinText.resolve(
                        BulletinText.messageBody.copyWith(color: BulletinColors.muted),
                        hint,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      // 11 + 25.6 + 11: a 48 px line, level with the buttons.
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 11,
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final hasText = value.text.trim().isNotEmpty;
                    final blocked = sending || !attachment.canSend;
                    return _SendButton(
                      enabled: hasText && !blocked,
                      waiting: attachment.staged?.uploading ?? false,
                      label: l.sendAction,
                      onTap: onSend,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the attach sheet, picks the file and stages it. Used by the
/// composer's attach button and Home's "Attach routine" chip.
Future<void> openAttachFlow(BuildContext context, WidgetRef ref) async {
  final source = await showBulletinSheet<_AttachSource>(
    context,
    builder: (context) => const _AttachSheet(),
  );
  if (source == null) return;

  final file = await _pick(source);
  if (file != null) {
    await ref.read(attachmentControllerProvider.notifier).stage(file);
  }
}

Future<File?> _pick(_AttachSource source) async {
  switch (source) {
    case _AttachSource.camera:
      final shot = await ImagePicker().pickImage(source: ImageSource.camera);
      return shot == null ? null : File(shot.path);
    case _AttachSource.gallery:
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      return picked == null ? null : File(picked.path);
    case _AttachSource.files:
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      final path = result?.files.single.path;
      return path == null ? null : File(path);
  }
}

enum _AttachSource { camera, gallery, files }

/// The attach sheet (README §2.8; prototype `sh.attach`): "Add to your
/// question", then camera, gallery and file rows fading up in turn (120,
/// 160, 200 ms), and the note (240). The note carries the size limit and
/// the privacy line PRD §8.4 requires: the user has to see that the file
/// answers this question only and joins no institution documents.
class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  /// PRD §8.5; the attachment controller enforces it.
  static const _limit = '10 MB';

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    void pick(_AttachSource source) => Navigator.pop(context, source);
    final note = BulletinText.resolve(BulletinText.fieldHelper, l.attachNote);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.attachTitle,
            style: BulletinText.resolve(BulletinText.screenTitle, l.attachTitle),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 4,
          children: [
            _SourceRow(
              delay: 120,
              glyph: LineIcons.camera,
              title: l.attachCamera,
              detail: l.attachCameraSub,
              onTap: () => pick(_AttachSource.camera),
            ),
            _SourceRow(
              delay: 160,
              glyph: LineIcons.image,
              title: l.attachGallery,
              detail: l.attachGallerySub,
              onTap: () => pick(_AttachSource.gallery),
            ),
            _SourceRow(
              delay: 200,
              glyph: LineIcons.file,
              title: l.attachFiles,
              detail: l.attachFilesSub,
              onTap: () => pick(_AttachSource.files),
            ),
          ],
        ),
        FadeUp(
          delay: const Duration(milliseconds: 240),
          duration: MotionDurations.stepIn,
          child: Text.rich(
            TextSpan(
              style: note,
              children: [
                TextSpan(text: l.attachLimitBefore),
                const TextSpan(
                  text: _limit,
                  style: TextStyle(fontFamily: Fonts.mono),
                ),
                TextSpan(text: '${l.attachLimitAfter} ${l.attachNote}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One source: a 48 px peach tile with its icon, the name 16/500, a detail
/// line 12 muted, 64 px tall. Its pressed fill reaches 12 px past the
/// content on either side, as the prototype's negative margin does.
class _SourceRow extends StatefulWidget {
  const _SourceRow({
    required this.delay,
    required this.glyph,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final int delay;
  final LineGlyph glyph;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  State<_SourceRow> createState() => _SourceRowState();
}

class _SourceRowState extends State<_SourceRow> {
  bool _down = false;

  static const _radius = BorderRadius.all(Radius.circular(20));
  static const _tile = BorderRadius.all(Radius.circular(12));
  static const _bleed = 12.0;

  void _press(bool down) => setState(() => _down = down);

  @override
  Widget build(BuildContext context) {
    final row = Row(
      spacing: 14,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: BulletinColors.peach,
            borderRadius: _tile,
          ),
          alignment: Alignment.center,
          child: LineIcon(widget.glyph, color: BulletinColors.brandStrong, size: 22),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: BulletinText.resolve(BulletinText.sourceRowTitle, widget.title),
              ),
              Text(
                widget.detail,
                style: BulletinText.resolve(
                  BulletinText.pillCaption,
                  widget.detail,
                ).copyWith(height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );

    return FadeUp(
      delay: Duration(milliseconds: widget.delay),
      duration: MotionDurations.stepIn,
      child: Semantics(
        button: true,
        label: '${widget.title}, ${widget.detail}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _down ? 0.98 : 1,
            duration: MotionDurations.micro,
            curve: MotionCurves.spring,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: -_bleed,
                  right: -_bleed,
                  top: 0,
                  bottom: 0,
                  child: AnimatedContainer(
                    duration: MotionDurations.micro,
                    decoration: BoxDecoration(
                      borderRadius: _radius,
                      color: _down
                          ? BulletinColors.chipFill
                          : BulletinColors.chipFill.withValues(alpha: 0),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: row,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The staged file, above the field, with a remove button.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.staged, required this.onRemove});

  final StagedAttachment staged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        color: const Color(0xDBFFFFFF),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        border: Border.all(color: BulletinColors.hairline),
      ),
      child: Row(
        children: [
          _Thumbnail(staged: staged, width: 34, height: 40),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  staged.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BulletinText.sourceTitle.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  staged.uploading ? l.uploading : '${staged.sizeLabel} · 7-day TTL',
                  style: BulletinText.courseCode.copyWith(
                    fontSize: 11,
                    color: staged.error != null
                        ? BulletinColors.danger
                        : BulletinColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: l.removeAttachment,
            iconSize: 18,
            constraints: const BoxConstraints(
              minWidth: Sizes.minTouchTarget,
              minHeight: Sizes.minTouchTarget,
            ),
            icon: const Icon(Icons.close, color: BulletinColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.staged, required this.width, required this.height});

  final StagedAttachment staged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(5)),
      child: SizedBox(
        width: width,
        height: height,
        child: staged.isImage
            ? Image.file(staged.file, fit: BoxFit.cover)
            : Container(
                color: BulletinColors.chipFillStrong,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.description_outlined,
                  size: 16,
                  color: BulletinColors.inkMuted,
                ),
              ),
      ),
    );
  }
}

/// 48 px, a radial white → peach glow, the paperclip in brand.
class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.semanticLabel, required this.onTap});

  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressScale.icon(
        enabled: onTap != null,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: Sizes.minTouchTarget,
            height: Sizes.minTouchTarget,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              // CSS `radial-gradient(circle, …)` ends at the farthest corner.
              gradient: RadialGradient(
                radius: 0.7071,
                stops: [0, 0.6, 1],
                colors: [
                  BulletinColors.white,
                  BulletinColors.peach,
                  BulletinColors.attachGlow,
                ],
              ),
            ),
            alignment: Alignment.center,
            child: LineIcon(
              LineIcons.paperclip,
              color: BulletinColors.brandStrong,
              strokeWidth: 1.9,
            ),
          ),
        ),
      ),
    );
  }
}

/// 48 px. Brand with a white arrow when there is something to send; peach
/// with a grey arrow when not; a spinner while an attachment uploads.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.waiting,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final bool waiting;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = enabled ? BulletinColors.white : BulletinColors.sendInert;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale.icon(
        enabled: enabled,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: MotionDurations.micro,
            curve: MotionCurves.out,
            width: Sizes.minTouchTarget,
            height: Sizes.minTouchTarget,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? BulletinColors.brandStrong : BulletinColors.peach,
            ),
            alignment: Alignment.center,
            child: waiting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BulletinColors.sendInert,
                    ),
                  )
                : LineIcon(LineIcons.arrowUp, color: ink, strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}
