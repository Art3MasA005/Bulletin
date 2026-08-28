/// The composer, and the attach sheet behind its `+`. Handoff spec §4, §5.
///
/// Frosted, because it is fixed chrome — one of the two `BackdropFilter`
/// layers the blur budget allows on a screen (DESIGN §7). The message list
/// below it is opaque for the same reason.
///
/// The send button has three states and they are not decoration:
///   inert     nothing typed and nothing attached
///   waiting   an attachment is still uploading — sending now would ask a
///             question about a file the server has not read
///   ready     accent, with the accent lift
library;

import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/theme.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context);
    final attachment = ref.watch(attachmentControllerProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Sizes.screenPadding,
          Space.sm,
          Sizes.screenPadding,
          Space.md,
        ),
        child: ClipRRect(
          borderRadius: Radii.composerAll,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: BlurBudget.sigma, sigmaY: BlurBudget.sigma),
            child: Container(
              decoration: BoxDecoration(
                color: BulletinColors.frostedComposer,
                borderRadius: Radii.composerAll,
                border: Border.all(color: BulletinColors.hairline),
                boxShadow: Lifts.composer,
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (attachment.staged case final staged?) ...[
                    _AttachmentPreview(
                      staged: staged,
                      onRemove: () =>
                          ref.read(attachmentControllerProvider.notifier).clear(),
                    ),
                    const SizedBox(height: Space.md),
                  ],
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    onChanged: (_) => (context as Element).markNeedsBuild(),
                    style: BulletinText.messageBody,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: BulletinText.resolve(
                        BulletinText.messageBody.copyWith(color: BulletinColors.inkFaint),
                        hint,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Row(
                    children: [
                      _CircleButton(
                        icon: Icons.add,
                        semanticLabel: l.attachAction,
                        onTap: sending ? null : () => _openAttachSheet(context, ref),
                      ),
                      const Spacer(),
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
          ),
        ),
      ),
    );
  }

  Future<void> _openAttachSheet(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<_AttachSource>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: BulletinColors.scrim,
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
}

enum _AttachSource { camera, gallery, files }

/// The attach sheet. The privacy line is required by PRD §8.4 and is the
/// reason this is a sheet rather than a menu: the user has to see it.
class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: BulletinColors.paper,
        borderRadius: Radii.sheetTop,
      ),
      padding: const EdgeInsets.fromLTRB(
        Sizes.sheetPadding,
        Sizes.sheetPadding,
        Sizes.sheetPadding,
        Space.sm,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.attachTitle, style: BulletinText.sheetTitle),
            const SizedBox(height: Space.sm),
            Text(
              l.attachNote,
              style: BulletinText.resolve(
                BulletinText.meta.copyWith(fontSize: 13, height: 1.6),
                l.attachNote,
              ),
            ),
            const SizedBox(height: Space.lg),
            _SheetRow(
              icon: Icons.photo_camera_outlined,
              label: l.attachCamera,
              onTap: () => Navigator.pop(context, _AttachSource.camera),
            ),
            _SheetRow(
              icon: Icons.photo_library_outlined,
              label: l.attachGallery,
              onTap: () => Navigator.pop(context, _AttachSource.gallery),
            ),
            _SheetRow(
              icon: Icons.folder_outlined,
              label: l.attachFiles,
              onTap: () => Navigator.pop(context, _AttachSource.files),
            ),
            _SheetRow(
              label: l.cancelAction,
              muted: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.onTap,
    this.icon,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.chipAll,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: BulletinColors.ink),
              const SizedBox(width: Space.md),
            ],
            Text(
              label,
              style: BulletinText.resolve(
                BulletinText.messageBody.copyWith(
                  color: muted ? BulletinColors.inkMuted : BulletinColors.ink,
                ),
                label,
              ),
            ),
          ],
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

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Center(
          child: Material(
            color: BulletinColors.chipFillStrong,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(icon, size: 20, color: BulletinColors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: enabled ? Lifts.accentButton : const [],
            ),
            child: Material(
              color: enabled ? BulletinColors.accent : BulletinColors.inert,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: enabled ? onTap : null,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: waiting
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BulletinColors.paper,
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward,
                          size: 20,
                          color: BulletinColors.paper,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
