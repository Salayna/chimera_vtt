import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthState, SupabaseClient, User;

import 'theme.dart';
import 'ui/cv.dart';

/// The signed-in GM, or null: anonymous users (every player, and anyone who
/// hasn't signed in) don't count.
User? signedInGm(SupabaseClient client) {
  final user = client.auth.currentUser;
  return user == null || user.isAnonymous ? null : user;
}

/// Rebuilds [builder] with the signed-in GM whenever sign-in changes.
class GmAccount extends StatelessWidget {
  const GmAccount({super.key, required this.client, required this.builder});

  final SupabaseClient client;
  final Widget Function(BuildContext context, User? gm) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: client.auth.onAuthStateChange,
        builder: (context, _) => builder(context, signedInGm(client)),
      );
}

/// Email and password, to sign in or create a GM account.
class GmSignIn extends StatefulWidget {
  const GmSignIn({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<GmSignIn> createState() => _GmSignInState();
}

class _GmSignInState extends State<GmSignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter an email and a password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final auth = widget.client.auth;
    try {
      if (create) {
        final response = await auth.signUp(email: email, password: password);
        // With email confirmation on (hosted projects), there's no session
        // until the link in the email is followed.
        if (response.session == null && mounted) {
          setState(() => _notice =
              'Check your email to confirm the account, then sign in.');
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: CvSpacing.s4,
        children: [
          CvTextInput(controller: _email, label: 'Email', placeholder: 'gm@example.com'),
          CvTextInput(
            controller: _password,
            label: 'Password',
            obscure: true,
            error: _error,
            onSubmitted: (_) => _submit(create: false),
          ),
          if (_notice case final notice?)
            Text(notice,
                style: CvTypography.caption.copyWith(color: CvColors.gold300)),
          CvButton(
            label: 'Sign in',
            icon: Lucide.logIn,
            variant: CvButtonVariant.primary,
            block: true,
            onPressed: _busy ? null : () => _submit(create: false),
          ),
          CvButton(
            label: 'Create account',
            variant: CvButtonVariant.ghost,
            block: true,
            onPressed: _busy ? null : () => _submit(create: true),
          ),
        ],
      );
}
