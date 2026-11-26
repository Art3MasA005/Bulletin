/// Home and the chat (handoff README §2.6–2.7; prototype `L.main`).
///
/// One screen, as in the prototype: before the first question it shows Home
/// ([HomeView]: orb, greeting, suggestions); after it, the thread. Both sit
/// under the same floating chrome: the top bar at y = 56 and the glass
/// composer 16 px from the sides and 28 from the bottom. Those two glass
/// surfaces are the screen's two BackdropFilters (CLAUDE.md #11); nothing
/// else here blurs.
///
/// The thread is a reverse `ListView`: new messages appear at the bottom
/// without a scroll animation to fight, and the list holds its position when
/// the keyboard opens. `addAutomaticKeepAlives: false` because a long thread
/// of settled messages does not need to stay alive off-screen. The thread
/// itself (bubbles, steps, sources) lives in `thread/`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/motion.dart';
import '../../../core/net/api_client.dart' show Membership;
import '../../../core/net/result.dart';
import '../../../core/providers.dart';
import '../../../core/routing/push_route.dart';
import '../../../l10n/app_localizations.dart';
import '../../attachments/data/attachment_controller.dart';
import '../../attachments/presentation/confirm_sheet.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/presentation/settings_screen.dart';
import '../data/chat_controller.dart';
import '../data/model_picker.dart';
import '../domain/citation.dart';
import '../domain/home_greeting.dart';
import 'composer.dart';
import 'home/home_top_bar.dart';
import 'home/home_view.dart';
import 'thread/chat_thread.dart';
import 'thread/offline_banner.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({this.conversationId, this.openingQuestion, super.key});

  final String? conversationId;

  /// A suggested question tapped elsewhere, sent on first frame.
  final String? openingQuestion;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  /// The prototype's chrome, in its 390 x 844 frame.
  static const _chromeTop = 56.0;
  static const _barHeight = 48.0;
  static const _composerBottom = 28.0;
  static const _composerHeight = 60.0;

  /// What an attachment row adds to the composer.
  static const _attachmentRow = 64.0;

  /// What the offline banner pushes the first message down by.
  static const _bannerRoom = 52.0;

  @override
  void initState() {
    super.initState();
    final opening = widget.openingQuestion;
    if (opening != null && opening.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_send(opening)));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Send, with the confirmation gate in front of it.
  ///
  /// CLAUDE.md #3: a question carrying an attachment cannot reach the backend
  /// until the user has confirmed the extracted course codes. The gate lives
  /// here rather than in the controller because confirming is a conversation
  /// with the user, and backing out of it must leave the typed question
  /// untouched in the field.
  Future<void> _send([String? text]) async {
    final question = text ?? _input.text;
    if (question.trim().isEmpty) return;

    final attachments = ref.read(attachmentControllerProvider.notifier);
    var attachment = ref.read(attachmentControllerProvider);

    // How many courses the routine photo gave, for the "Read N courses" step.
    int? readCourses = attachment.staged == null
        ? null
        : attachment.extraction?.courses.length;

    if (attachment.staged != null) {
      // Still uploading: the server has not read the file, so there is nothing
      // to confirm yet. The send button is disabled in this state; this is the
      // keyboard-submit path.
      if (!attachment.staged!.isReady) return;

      final extraction = attachment.extraction;
      if (extraction != null && !extraction.confirmed) {
        final codes = await showConfirmExtractionSheet(context, extraction);
        if (codes == null) return; // dismissed — nothing confirmed, nothing sent
        final result = await attachments.confirm(codes);
        if (!mounted) return;
        if (result case Failure(:final message)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message ?? L.of(context).errorGeneric)));
          return;
        }
        attachment = ref.read(attachmentControllerProvider);
        readCourses = codes.length;
      }
    }

    _input.clear();
    unawaited(
      ref
          .read(chatControllerProvider(widget.conversationId).notifier)
          .send(
            question,
            attachmentId: attachment.staged?.attachmentId,
            model: ref.read(currentModelProvider)?.key,
            readCourses: readCourses,
          ),
    );
    // The attachment belongs to the question that carried it; the next one
    // starts from an empty composer.
    attachments.clear();

    // The list is reversed, so "scroll to newest" is offset zero.
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: MotionDurations.section, curve: MotionCurves.out);
    }
  }

  void _openSource(Citation citation) {
    // The source viewer is a route of its own (DESIGN §6.5); until it exists,
    // say so rather than silently doing nothing on a tap the card advertises.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L.of(context).openPage(citation.pageNo))));
  }

  /// Back to Home: the thread is dropped (it is saved on the server) and the
  /// composer starts empty.
  void _newChat() {
    ref.invalidate(chatControllerProvider(widget.conversationId));
    ref.read(attachmentControllerProvider.notifier).clear();
    _input.clear();
    _focus.unfocus();
  }

  void _openSettings() {
    _focus.unfocus();
    unawaited(
      Navigator.of(
        context,
      ).push(PushRoute<void>.of(context, (_) => const SettingsScreen())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(chatControllerProvider(widget.conversationId));
    final hasFile = ref.watch(
      attachmentControllerProvider.select((a) => a.staged != null),
    );
    final membership = ref.watch(membershipProvider).valueOrNull;
    final messages = state.messages.reversed.toList(growable: false);

    // The chrome keeps the prototype's distances, but never closer than
    // 8 px to the real status bar, nor 12 px to the navigation bar; with the
    // keyboard up the composer sits 12 px above it.
    final insets = MediaQuery.viewPaddingOf(context);
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
    final top = math.max(_chromeTop, insets.top + 8);
    final bottom = keyboardUp ? 12.0 : math.max(_composerBottom, insets.bottom + 12);
    final composerTop = bottom + _composerHeight + (hasFile ? _attachmentRow : 0);

    final hint = hasFile
        ? l.askAboutFile
        : (messages.isEmpty ? l.askHome : l.askFollowUp);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: messages.isEmpty
                ? Padding(
                    padding: EdgeInsets.only(
                      top: top + _barHeight + 8,
                      bottom: composerTop + 20,
                    ),
                    child: HomeView(
                      greeting: _greeting(l, membership),
                      institutionLine: switch (membership?.institutionName) {
                        final name? => l.homeInstitutionLine(name),
                        null => l.homeInstitutionLineGeneric,
                      },
                      onAsk: (q) => unawaited(_send(q)),
                      onAttach: () => unawaited(openAttachFlow(context, ref)),
                    ),
                  )
                : ChatThread(
                    messages: state.messages,
                    role: membership?.role ?? 'student',
                    controller: _scroll,
                    topInset: top + _barHeight + 20 + (state.offline ? _bannerRoom : 0),
                    bottomInset: composerTop + 40,
                    onOpenSource: _openSource,
                    onRetry: () => ref
                        .read(chatControllerProvider(widget.conversationId).notifier)
                        .retryLast(),
                  ),
          ),
          if (state.offline && messages.isNotEmpty)
            Positioned(
              top: top + _barHeight + 12,
              left: 20,
              right: 20,
              child: const OfflineBanner(),
            ),
          Positioned(
            top: top,
            left: 16,
            right: 16,
            child: HomeTopBar(
              inThread: messages.isNotEmpty,
              onNewChat: state.sending ? null : _newChat,
              onMenu: _openSettings,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom,
            child: Composer(
              controller: _input,
              focusNode: _focus,
              sending: state.sending,
              hint: hint,
              onSend: () => unawaited(_send()),
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(L l, Membership? membership) {
    final name = greetingName(
      displayName: membership?.displayName,
      fullName: ref.read(authRepositoryProvider).fullName,
    );
    return name == null ? l.homeGreetingNoName : l.homeGreeting(name);
  }
}
