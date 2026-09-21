import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';
import '../state/app_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _loginError;
  _LoginMode _mode = _LoginMode.admin;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: AppController.validEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _loginError = null);

    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSubmitting = true);
    try {
      final authenticated = _mode == _LoginMode.admin
          ? await widget.controller.login(
              _emailController.text,
              _passwordController.text,
            )
          : await widget.controller.loginStaff(
              _emailController.text,
              _passwordController.text,
            );
      if (!mounted) return;

      if (!authenticated) {
        setState(() {
          _loginError = _mode == _LoginMode.admin
              ? 'The admin email or password is incorrect. Please try again.'
              : 'The staff email or PIN is incorrect, or this account is inactive.';
          _passwordController.clear();
        });
        _passwordFocusNode.requestFocus();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loginError = 'Unable to sign in right now. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F7F2), AppColors.forestSoft],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 840;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 40 : 20,
                  vertical: isWide ? 40 : 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (isWide ? 80 : 48),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: isWide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Expanded(flex: 11, child: _BrandPanel()),
                                const SizedBox(width: 28),
                                Expanded(
                                  flex: 9,
                                  child: Center(child: _buildLoginCard()),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const _CompactBrandHeader(),
                                const SizedBox(height: 28),
                                _buildLoginCard(),
                              ],
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 470),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _mode == _LoginMode.admin
                        ? 'ADMIN ACCESS'
                        : 'STAFF CHECK-IN',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome back',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == _LoginMode.admin
                        ? 'Sign in to manage inventory, billing, branches, and staff.'
                        : 'Sign in for today and continue to the pharmacy workspace.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SegmentedButton<_LoginMode>(
                    segments: const [
                      ButtonSegment(
                        value: _LoginMode.admin,
                        icon: Icon(Icons.admin_panel_settings_outlined),
                        label: Text('Admin'),
                      ),
                      ButtonSegment(
                        value: _LoginMode.staff,
                        icon: Icon(Icons.badge_outlined),
                        label: Text('Staff'),
                      ),
                    ],
                    selected: {_mode},
                    showSelectedIcon: false,
                    onSelectionChanged: _isSubmitting
                        ? null
                        : (selection) => _changeMode(selection.first),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: ValueKey('email:${_mode.name}'),
                    controller: _emailController,
                    enabled: !_isSubmitting,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email,
                    ],
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: _mode == _LoginMode.admin
                          ? AppController.validEmail
                          : 'staff@pharmacy.com',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return 'Enter your email address.';
                      if (!email.contains('@') || !email.contains('.')) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                    onChanged: (_) => _clearLoginError(),
                    onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: ValueKey('secret:${_mode.name}'),
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    enabled: !_isSubmitting,
                    obscureText: _obscurePassword,
                    keyboardType: _mode == _LoginMode.staff
                        ? TextInputType.number
                        : TextInputType.visiblePassword,
                    inputFormatters: _mode == _LoginMode.staff
                        ? <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(8),
                          ]
                        : const <TextInputFormatter>[],
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: _mode == _LoginMode.admin
                          ? 'Password'
                          : 'Staff PIN',
                      hintText: _mode == _LoginMode.admin
                          ? 'Enter password'
                          : 'Enter 4–8 digit PIN',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return _mode == _LoginMode.admin
                            ? 'Enter your password.'
                            : 'Enter your staff PIN.';
                      }
                      if (_mode == _LoginMode.staff && value.length < 4) {
                        return 'PIN must contain at least 4 digits.';
                      }
                      return null;
                    },
                    onChanged: (_) => _clearLoginError(),
                    onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _loginError == null
                        ? const SizedBox(height: 24)
                        : Padding(
                            key: ValueKey(_loginError),
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: _LoginError(message: _loginError!),
                          ),
                  ),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: _isSubmitting
                          ? const SizedBox.square(
                              key: ValueKey('loading'),
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              key: ValueKey('label:${_mode.name}'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _mode == _LoginMode.admin
                                      ? 'Sign in'
                                      : 'Check in & continue',
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.cloud_off_outlined,
                        color: AppColors.muted,
                        size: 17,
                      ),
                      SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Your pharmacy data stays on this device',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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

  void _clearLoginError() {
    if (_loginError == null) return;
    setState(() => _loginError = null);
  }

  void _changeMode(_LoginMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _loginError = null;
      _obscurePassword = true;
      _passwordController.clear();
      _emailController.text = mode == _LoginMode.admin
          ? AppController.validEmail
          : '';
    });
  }
}

enum _LoginMode { admin, staff }

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 570),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forestDark, AppColors.forest],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestDark.withValues(alpha: 0.2),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _PatternPainter()),
                ),
              ),
            ),
          ),
          const Positioned(
            right: -50,
            top: -54,
            child: _DecorativeCircle(size: 210, opacity: 0.07),
          ),
          const Positioned(
            left: -72,
            bottom: -96,
            child: _DecorativeCircle(size: 260, opacity: 0.05),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BrandLockup(light: true),
              const Spacer(),
              Text(
                'Manage every branch\nfrom one pharmacy\nworkspace.',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 22),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: const Text(
                  'Track medicine quantities, receive low-stock alerts, create invoices, and check branch availability—even offline.',
                  style: TextStyle(
                    color: Color(0xFFD9EEE8),
                    fontSize: 17,
                    height: 1.55,
                  ),
                ),
              ),
              const SizedBox(height: 34),
              const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FeaturePill(
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventory',
                  ),
                  _FeaturePill(
                    icon: Icons.receipt_long_outlined,
                    label: 'Billing',
                  ),
                  _FeaturePill(icon: Icons.store_outlined, label: 'Branches'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactBrandHeader extends StatelessWidget {
  const _CompactBrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _BrandLockup(light: false),
        SizedBox(height: 18),
        Text(
          'Your pharmacy workspace, in your pocket.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.light});

  final bool light;

  @override
  Widget build(BuildContext context) {
    final foreground = light ? Colors.white : AppColors.ink;
    final secondary = light ? const Color(0xFFD9EEE8) : AppColors.muted;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: light ? Colors.white : AppColors.forest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: light
                ? null
                : [
                    BoxShadow(
                      color: AppColors.forest.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Text(
            'Rx',
            style: TextStyle(
              color: light ? AppColors.forestDark : Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MediStock',
              style: TextStyle(
                color: foreground,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Pharmacy inventory',
              style: TextStyle(
                color: secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  const _DecorativeCircle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter();

  static const _spacing = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.075)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.028)
      ..strokeWidth = 1;

    for (var x = 14.0; x < size.width; x += _spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
      for (var y = 14.0; y < size.height; y += _spacing) {
        canvas.drawCircle(Offset(x, y), 1.15, dotPaint);
      }
    }
    for (var y = 14.0; y < size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginError extends StatelessWidget {
  const _LoginError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: AppColors.danger,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
