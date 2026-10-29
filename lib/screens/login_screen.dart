import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'map_screen.dart';

enum _AuthTab { login, register }

/// Login / Register over the mountain-lake photo.
///
/// Matches the website (`AuthContext.jsx` / `Login.jsx`):
/// - Login: client-side username + password check (no auth HTTP API).
/// - Register: website button is disabled and there is no register endpoint,
///   payload, or field list — so this tab shows a distinct form with
///   client-side validation only, then reports that registration is unavailable.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _bg = 'assets/images/welcome_mountain_lake.jpg';

  final _loginUser = TextEditingController();
  final _loginPass = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _regUser = TextEditingController();
  final _regPass = TextEditingController();
  final _regConfirm = TextEditingController();

  String? _error;
  bool _busy = false;
  bool _loginObscure = true;
  bool _regObscure = true;
  bool _confirmObscure = true;
  _AuthTab _tab = _AuthTab.login;

  @override
  void dispose() {
    _loginUser.dispose();
    _loginPass.dispose();
    _fullName.dispose();
    _email.dispose();
    _regUser.dispose();
    _regPass.dispose();
    _regConfirm.dispose();
    super.dispose();
  }

  void _setTab(_AuthTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _error = null;
      _busy = false;
    });
  }

  Future<void> _submitLogin() async {
    final u = _loginUser.text.trim();
    final p = _loginPass.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Please enter both username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AuthService.instance.login(u, p);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Invalid username or password';
      });
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MapScreen()),
    );
  }

  Future<void> _submitRegister() async {
    final name = _fullName.text.trim();
    final email = _email.text.trim();
    final user = _regUser.text.trim();
    final pass = _regPass.text;
    final confirm = _regConfirm.text;

    if (name.isEmpty || email.isEmpty || user.isEmpty || pass.isEmpty || confirm.isEmpty) {
      setState(() => _error = 'Please fill in all registration fields');
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() => _error = 'Please enter a valid email address');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    // Website: Register New User is disabled; api.js has no auth/register route.
    setState(() =>
        _error = 'User registration is not available yet. Please sign in.');
  }

  bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    final dot = value.lastIndexOf('.');
    return at > 0 && dot > at + 1 && dot < value.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF1A6B8A),
      body: LayoutBuilder(
        builder: (context, c) {
          final tight = c.maxHeight < 700;
          final maxCardW = c.maxWidth >= 900
              ? 300.0
              : (c.maxWidth >= 600 ? 290.0 : 280.0);
          final bottomPad = 16 + mq.padding.bottom;
          final topSafe = mq.padding.top + 12;
          // Lower-middle: leave scenery above; avoid hugging the very bottom.
          final cardBottom = bottomPad + (tight ? 8.0 : 28.0);

          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Image.asset(
                  _bg,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.08),
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF1A6B8A)),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.28),
                      ],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: cardBottom,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxCardW,
                      maxHeight: c.maxHeight - cardBottom - topSafe,
                    ),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: _card(tight),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(bool tight) {
    const gap = 6.0;
    const fieldH = 36.0;
    const fieldBox = BoxConstraints.tightFor(height: fieldH);
    const iconBox = BoxConstraints(minWidth: 34, minHeight: fieldH);
    final isLogin = _tab == _AuthTab.login;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.fromLTRB(12, tight ? 10 : 12, 12, tight ? 10 : 12),
          decoration: BoxDecoration(
            color: AppColors.deepForest.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.mint.withValues(alpha: 0.36)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: BrandLogo(size: tight ? 16 : 17)),
              if (!isLogin) ...[
                const SizedBox(height: 4),
                Text(
                  'Join ClimateEye',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: tight ? 15 : 16,
                    color: AppColors.cloudWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              GlassPanel(
                radius: 18,
                opacity: 0.32,
                padding: const EdgeInsets.all(2),
                child: GlassSegmented<_AuthTab>(
                  values: _AuthTab.values,
                  selected: _tab,
                  dense: true,
                  expand: true,
                  label: (t) => t == _AuthTab.login ? 'Login' : 'Register',
                  onChanged: _setTab,
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: gap),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              if (isLogin)
                _loginFields(gap: gap, fieldBox: fieldBox, iconBox: iconBox)
              else
                _registerFields(gap: gap, fieldBox: fieldBox, iconBox: iconBox),
              const SizedBox(height: 8),
              GradientButton(
                label: isLogin ? 'Sign In' : 'Create Account',
                height: 38,
                busy: _busy,
                onPressed: _busy
                    ? null
                    : () => isLogin ? _submitLogin() : _submitRegister(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginFields({
    required double gap,
    required BoxConstraints fieldBox,
    required BoxConstraints iconBox,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginUser,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            isDense: true,
            constraints: fieldBox,
            labelText: 'Username',
            prefixIcon: const Icon(Icons.person_outline, size: 17),
            prefixIconConstraints: iconBox,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _loginPass,
          obscureText: _loginObscure,
          onSubmitted: (_) => _submitLogin(),
          decoration: InputDecoration(
            isDense: true,
            constraints: fieldBox,
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, size: 17),
            prefixIconConstraints: iconBox,
            suffixIconConstraints: iconBox,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: IconButton(
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _loginObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _loginObscure = !_loginObscure),
            ),
          ),
        ),
      ],
    );
  }

  Widget _registerFields({
    required double gap,
    required BoxConstraints fieldBox,
    required BoxConstraints iconBox,
  }) {
    InputDecoration deco(String label, IconData icon, {Widget? suffix}) =>
        InputDecoration(
          isDense: true,
          constraints: fieldBox,
          labelText: label,
          prefixIcon: Icon(icon, size: 17),
          prefixIconConstraints: iconBox,
          suffixIconConstraints: iconBox,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          suffixIcon: suffix,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _fullName,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          decoration: deco('Full name', Icons.badge_outlined),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: deco('Email address', Icons.mail_outline),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _regUser,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: deco('Username', Icons.person_outline),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _regPass,
          obscureText: _regObscure,
          textInputAction: TextInputAction.next,
          decoration: deco(
            'Password',
            Icons.lock_outline,
            suffix: IconButton(
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _regObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _regObscure = !_regObscure),
            ),
          ),
        ),
        SizedBox(height: gap),
        TextField(
          controller: _regConfirm,
          obscureText: _confirmObscure,
          onSubmitted: (_) => _submitRegister(),
          decoration: deco(
            'Confirm password',
            Icons.lock_outline,
            suffix: IconButton(
              iconSize: 17,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _confirmObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () =>
                  setState(() => _confirmObscure = !_confirmObscure),
            ),
          ),
        ),
      ],
    );
  }
}
