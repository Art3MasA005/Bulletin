/// Sign in, and join an institution by invite code. PRD §4, DESIGN §6.
///
/// Two screens in one file because they are two halves of one flow: a new
/// student signs up, then joins. Neither can do anything useful without the
/// other, and splitting them across files would hide that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/net/result.dart';
import '../../../core/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../l10n/app_localizations.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Shown after a sign-up that needs an email confirmation.
  ///
  /// This is not an error and must not be styled as one: the account was
  /// created successfully, the user simply cannot sign in until they click the
  /// link. Reporting it in red would tell them the opposite of what happened.
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool signUp}) async {
    final l = L.of(context);
    final email = _email.text.trim();

    // Checked here rather than left to the server: Supabase answers an empty
    // email with a validation message about the request body, which tells the
    // user nothing about what they did.
    if (email.isEmpty) {
      setState(() => _error = l.emailRequired);
      return;
    }
    if (signUp && _password.text.length < 6) {
      setState(() => _error = l.passwordTooShort);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final auth = ref.read(supabaseProvider).auth;
      if (signUp) {
        final response = await auth.signUp(email: email, password: _password.text);
        // The project requires email confirmation (`mailer_autoconfirm` is
        // off), so a successful sign-up returns a user and NO session. Without
        // this branch the button appeared to do nothing at all: no error, no
        // navigation, because the router only moves when a session exists.
        if (response.session == null) {
          setState(() => _notice = l.checkYourEmail(email));
        }
      } else {
        await auth.signInWithPassword(email: email, password: _password.text);
      }
      // The router watches auth state; nothing to navigate to by hand.
    } on AuthException catch (error) {
      // Supabase writes these for users, so they are shown as-is rather than
      // flattened into "something went wrong".
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.appTitle, style: BulletinText.wordmark),
                  const SizedBox(height: Space.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 290),
                    child: Text(
                      l.tagline,
                      style: BulletinText.resolve(BulletinText.supporting, l.tagline),
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(hintText: l.emailLabel),
                  ),
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(signUp: false),
                    decoration: InputDecoration(hintText: l.passwordLabel),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      _error!,
                      style: BulletinText.meta.copyWith(color: BulletinColors.danger),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: Space.md),
                    Container(
                      padding: const EdgeInsets.all(Space.md),
                      decoration: const BoxDecoration(
                        color: BulletinColors.successTint,
                        borderRadius: Radii.chipAll,
                      ),
                      child: Text(
                        _notice!,
                        style: BulletinText.resolve(
                          BulletinText.meta.copyWith(color: BulletinColors.success),
                          _notice!,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(signUp: false),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BulletinColors.paper,
                            ),
                          )
                        : Text(l.signInAction),
                  ),
                  const SizedBox(height: Space.sm),
                  TextButton(
                    onPressed: _busy ? null : () => _submit(signUp: true),
                    child: Text(l.signUpAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed in, but not a member of anything yet (PRD §4).
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final l = L.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(apiClientProvider)
        .joinInstitution(
          _code.text.trim(),
          displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        );

    if (!mounted) return;
    switch (result) {
      case Ok():
        // Re-resolving membership is what moves the router forward.
        ref.invalidate(membershipProvider);
      case Failure(:final message, :final kind):
        setState(
          () => _error =
              message ?? (kind == FailureKind.offline ? l.errorOffline : l.errorGeneric),
        );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
            child: Text(l.signOutAction),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.joinTitle, style: BulletinText.screenTitle),
                  const SizedBox(height: Space.sm),
                  Text(
                    l.joinSubtitle,
                    style: BulletinText.resolve(
                      BulletinText.messageBody.copyWith(color: BulletinColors.inkMuted),
                      l.joinSubtitle,
                    ),
                  ),
                  const SizedBox(height: Space.xl),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    // An invite code is data: mono, so O and 0 are told apart.
                    style: BulletinText.courseCode.copyWith(
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(hintText: l.inviteCodeLabel),
                  ),
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(hintText: l.displayNameLabel),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      _error!,
                      style: BulletinText.resolve(
                        BulletinText.meta.copyWith(color: BulletinColors.danger),
                        _error!,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  FilledButton(
                    onPressed: _busy ? null : _join,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BulletinColors.paper,
                            ),
                          )
                        : Text(l.joinAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
