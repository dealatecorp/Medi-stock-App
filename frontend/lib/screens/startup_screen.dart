import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// The first Flutter frame while the local workspace is being prepared.
class StartupScreen extends StatefulWidget {
  const StartupScreen({
    super.key,
    this.error,
    this.onRetry,
    this.status = 'Preparing your workspace',
  });

  final Object? error;
  final VoidCallback? onRetry;
  final String status;

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(covariant StartupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
  }

  void _updateMotion() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion || widget.error != null) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final illustrationSize = math.min(
              math.max(160.0, constraints.maxHeight * 0.39),
              math.min(330.0, math.max(0.0, constraints.maxWidth - 48)),
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 48),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.forestSoft,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            'A LITTLE CARE. EVERY DAY.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.forestDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ExcludeSemantics(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size.square(illustrationSize),
                              painter: _MedicinePainter(_motion),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          header: true,
                          child: const Text(
                            'MediStock',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.forestDark,
                              fontSize: 40,
                              height: 1.1,
                              letterSpacing: -1.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your pharmacy, beautifully in order.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 36),
                        if (hasError) ...[
                          Semantics(
                            liveRegion: true,
                            child: const Text(
                              'We couldn’t open your workspace.\nPlease try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (widget.onRetry != null) ...[
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: widget.onRetry,
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                              label: const Text('Try again'),
                            ),
                          ],
                        ] else ...[
                          ExcludeSemantics(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                size: const Size(56, 14),
                                painter: _LoadingDotsPainter(_motion),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            label: 'Loading. ${widget.status}',
                            child: ExcludeSemantics(
                              child: Text(
                                widget.status,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MedicinePainter extends CustomPainter {
  _MedicinePainter(this.motion) : super(repaint: motion);

  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 340, size.height / 340);
    final phase = motion.value * math.pi * 2;
    final float = math.sin(phase);
    final paint = Paint()..isAntiAlias = true;

    // A soft mint halo keeps the illustration light on the cream canvas.
    canvas.drawCircle(
      const Offset(170, 165),
      129,
      paint
        ..shader = const RadialGradient(
          colors: [Color(0xFFE0F0E9), Color(0xFFEEF3EC)],
        ).createShader(const Rect.fromLTWH(41, 36, 258, 258)),
    );
    paint.shader = null;
    canvas.drawCircle(
      const Offset(170, 165),
      143,
      paint
        ..color = AppColors.forest.withValues(alpha: 0.075)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    paint.style = PaintingStyle.fill;

    // Slowly moving accents, rather than a busy spinning loading wheel.
    for (var i = 0; i < 3; i++) {
      final angle = math.sin(phase) * 0.18 + i * math.pi * 2 / 3 - 0.8;
      canvas.drawCircle(
        Offset(170 + math.cos(angle) * 143, 165 + math.sin(angle) * 143),
        i == 1 ? 4 : 3,
        paint
          ..color = i == 1 ? const Color(0xFFD9BA7E) : const Color(0xFF91B8A8),
      );
    }
    _sparkle(canvas, Offset(102, 62 + float * 3), 7, AppColors.gold);
    _sparkle(canvas, Offset(272, 221 - float * 4), 6, AppColors.forest);
    _sparkle(canvas, const Offset(60, 199), 4, const Color(0xFF93B4A4));

    // Ground shadows subtly breathe in the opposite direction to the objects.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(169, 277),
        width: 106 - float * 4,
        height: 12,
      ),
      paint..color = AppColors.forest.withValues(alpha: 0.07),
    );
    _bottle(canvas, Offset(161, 174 + float * 5), -0.11 + float * 0.025);
    _capsule(
      canvas,
      Offset(257, 123 + math.sin(phase + 0.9) * 9),
      -0.61 + math.sin(phase + 0.9) * 0.06,
    );
    _tablet(canvas, Offset(79, 227 - float * 7), -0.33 + float * 0.05);

    canvas.restore();
  }

  void _bottle(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final paint = Paint()..isAntiAlias = true;
    final bottle = RRect.fromRectAndCorners(
      const Rect.fromLTWH(-48, -58, 96, 144),
      topLeft: const Radius.circular(25),
      topRight: const Radius.circular(25),
      bottomLeft: const Radius.circular(23),
      bottomRight: const Radius.circular(23),
    );
    canvas.drawRRect(
      bottle.shift(const Offset(3, 5)),
      paint..color = AppColors.forest.withValues(alpha: 0.065),
    );
    canvas.drawRRect(
      bottle,
      paint
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF6F8F1), Color(0xFFE8EEE4)],
          stops: [0, 0.65, 1],
        ).createShader(const Rect.fromLTWH(-48, -58, 96, 144)),
    );
    paint.shader = null;
    canvas.drawRRect(
      bottle,
      paint
        ..color = const Color(0xFFDCE7DD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-33, -69, 66, 21),
        const Radius.circular(7),
      ),
      paint..color = const Color(0xFFCFE0D3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-39, -83, 78, 31),
        const Radius.circular(9),
      ),
      paint
        ..shader = const LinearGradient(
          colors: [Color(0xFF288774), AppColors.forestDark],
        ).createShader(const Rect.fromLTWH(-39, -83, 78, 31)),
    );
    paint.shader = null;
    for (var x = -28.0; x < 34; x += 10) {
      canvas.drawLine(
        Offset(x, -77),
        Offset(x, -58),
        paint
          ..color = Colors.white.withValues(alpha: 0.17)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-48, -19, 96, 70),
        const Radius.circular(4),
      ),
      paint..color = const Color(0xFFD5EAE0),
    );
    canvas.drawCircle(
      const Offset(0, 11),
      22,
      paint..color = Colors.white.withValues(alpha: 0.8),
    );
    _cross(canvas, const Offset(0, 11), 20, AppColors.forest);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-18, 41, 36, 3),
        const Radius.circular(2),
      ),
      paint..color = AppColors.forest.withValues(alpha: 0.24),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-35, -42, 6, 17),
        const Radius.circular(3),
      ),
      paint..color = Colors.white,
    );
    canvas.restore();
  }

  void _capsule(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final paint = Paint()..isAntiAlias = true;
    final shape = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-22, -46, 44, 92),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      shape.shift(const Offset(3, 4)),
      paint..color = AppColors.forest.withValues(alpha: 0.07),
    );
    canvas.drawRRect(shape, paint..color = const Color(0xFFFFFDFA));
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      const Rect.fromLTWH(-22, -46, 44, 46),
      paint
        ..shader = const LinearGradient(
          colors: [Color(0xFF65AE97), Color(0xFF20816C)],
        ).createShader(const Rect.fromLTWH(-22, -46, 44, 46)),
    );
    paint.shader = null;
    canvas.drawLine(
      const Offset(-22, 0),
      const Offset(22, 0),
      paint
        ..color = const Color(0xFFD3E1D6)
        ..strokeWidth = 1.2,
    );
    canvas.restore();
    canvas.drawRRect(
      shape,
      paint
        ..color = const Color(0xFFD5E3D9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-13, -33, 5, 23),
        const Radius.circular(3),
      ),
      paint..color = Colors.white.withValues(alpha: 0.42),
    );
    canvas.restore();
  }

  void _tablet(Canvas canvas, Offset center, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawCircle(
      const Offset(1, 3),
      25,
      paint..color = const Color(0xFFD7C7A3),
    );
    canvas.drawCircle(
      Offset.zero,
      25,
      paint
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF6DD), Color(0xFFEEDBAA)],
        ).createShader(const Rect.fromLTWH(-25, -25, 50, 50)),
    );
    paint.shader = null;
    canvas.drawLine(
      const Offset(-17, 0),
      const Offset(17, 0),
      paint
        ..color = const Color(0xFFCDB987)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      const Rect.fromLTWH(-19, -19, 38, 38),
      math.pi * 1.08,
      math.pi * 0.62,
      false,
      paint
        ..color = Colors.white.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.restore();
  }

  void _cross(Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size, height: size * 0.34),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size * 0.34, height: size),
        const Radius.circular(2),
      ),
      paint,
    );
  }

  void _sparkle(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center - Offset(radius, 0),
      center + Offset(radius, 0),
      paint,
    );
    canvas.drawLine(
      center - Offset(0, radius),
      center + Offset(0, radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MedicinePainter oldDelegate) =>
      oldDelegate.motion != motion;
}

class _LoadingDotsPainter extends CustomPainter {
  _LoadingDotsPainter(this.motion) : super(repaint: motion);

  final Animation<double> motion;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < 3; i++) {
      final pulse = (math.sin(motion.value * math.pi * 4 - i * 0.9) + 1) / 2;
      canvas.drawCircle(
        Offset(size.width / 2 + (i - 1) * 17, size.height / 2),
        3 + pulse * 1.2,
        paint..color = AppColors.forest.withValues(alpha: 0.25 + pulse * 0.65),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoadingDotsPainter oldDelegate) =>
      oldDelegate.motion != motion;
}
