import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Native Flutter interpretation of the 3DVR Converter's layered glass UI.
/// Translucent colors replace live backdrop blur, avoiding the repaint seams
/// seen when animated backgrounds move behind large glass panels on Windows.
class GlassPalette {
  const GlassPalette(
    this.base,
    this.base2,
    this.accent,
    this.accent2,
    this.text,
  );
  final Color base;
  final Color base2;
  final Color accent;
  final Color accent2;
  final Color text;

  static const presets = <String, GlassPalette>{
    'Aurora': GlassPalette(
      Color(0xFF070F29),
      Color(0xFF0B2B53),
      Color(0xFF75EAFF),
      Color(0xFF9A91FF),
      Color(0xFFF7FBFF),
    ),
    'Ocean': GlassPalette(
      Color(0xFF041A29),
      Color(0xFF075675),
      Color(0xFF76EFD2),
      Color(0xFF66CFFF),
      Color(0xFFF3FFFD),
    ),
    'Ember': GlassPalette(
      Color(0xFF210B21),
      Color(0xFF593051),
      Color(0xFFFFBB9A),
      Color(0xFFFF8BCA),
      Color(0xFFFFF8FB),
    ),
    'Frost': GlassPalette(
      Color(0xFFB9D8E9),
      Color(0xFFD6D3F4),
      Color(0xFF1E638E),
      Color(0xFF6266C3),
      Color(0xFF112840),
    ),
    'Purple': GlassPalette(
      Color(0xFF150D2B),
      Color(0xFF382254),
      Color(0xFFB694FF),
      Color(0xFF76DFFF),
      Color(0xFFF9F6FF),
    ),
    'Rainbow': GlassPalette(
      Color(0xFF10182F),
      Color(0xFF252C59),
      Color(0xFF79E8FF),
      Color(0xFFFF86C5),
      Color(0xFFF9FBFF),
    ),
  };
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(14),
    this.radius = 22,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final palette = GlassPalette.presets[GlassDesign.of(context).themeName]!;
    final light = palette.text.computeLuminance() < 0.5;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (light ? Colors.white : palette.text).withValues(
            alpha: light ? 0.72 : 0.29,
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (light ? Colors.white : palette.accent).withValues(
              alpha: light ? 0.40 : 0.18,
            ),
            palette.base2.withValues(alpha: light ? 0.34 : 0.70),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: light ? 0.10 : 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class GlassDesign extends InheritedWidget {
  const GlassDesign({
    required this.themeName,
    required this.motion,
    required this.speed,
    required this.backgroundStyle,
    required super.child,
    super.key,
  });
  final String themeName;
  final bool motion;
  final double speed;
  final String backgroundStyle;
  static GlassDesign of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassDesign>()!;
  @override
  bool updateShouldNotify(GlassDesign oldWidget) =>
      themeName != oldWidget.themeName ||
      motion != oldWidget.motion ||
      speed != oldWidget.speed ||
      backgroundStyle != oldWidget.backgroundStyle;
}

class GlassBackground extends StatefulWidget {
  const GlassBackground({super.key});
  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground> {
  Timer? timer;
  double tick = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    timer?.cancel();
    final design = GlassDesign.of(context);
    if (design.motion && !MediaQuery.disableAnimationsOf(context)) {
      timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (mounted) setState(() => tick += 0.033 * design.speed);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final design = GlassDesign.of(context);
    final palette = GlassPalette.presets[design.themeName]!;
    final rainbow = design.themeName == 'Rainbow';
    final shift = rainbow ? tick * 0.18 : 0.0;
    final accent = rainbow
        ? HSLColor.fromAHSL(
            1,
            (195 + 130 * math.sin(shift)) % 360,
            0.85,
            0.72,
          ).toColor()
        : palette.accent;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AtmospherePainter(
          palette,
          accent,
          design.backgroundStyle,
          tick,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter(this.palette, this.accent, this.style, this.tick);
  final GlassPalette palette;
  final Color accent;
  final String style;
  final double tick;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.base, palette.base2, palette.base],
        ).createShader(bounds),
    );
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: 0.25),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.2, size.height * 0.12),
              radius: size.longestSide * 0.65,
            ),
          );
    canvas.drawRect(bounds, glow);
    if (style == 'Orbit') {
      for (var i = 0; i < 5; i++) {
        final path = Path();
        final center = Offset(
          size.width * (0.45 + 0.05 * math.sin(tick + i)),
          size.height * 0.55,
        );
        path.addOval(
          Rect.fromCenter(
            center: center,
            width: size.width * (0.38 + i * 0.12),
            height: size.height * (0.24 + i * 0.10),
          ),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: 0.07 + i * 0.01)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    } else if (style == 'Pulse') {
      for (var i = 0; i < 7; i++) {
        final radius =
            size.shortestSide * (0.2 + 0.14 * i + 0.03 * math.sin(tick + i));
        canvas.drawCircle(
          Offset(size.width * 0.75, size.height * 0.7),
          radius,
          Paint()
            ..color = accent.withValues(alpha: 0.07)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    } else {
      for (var i = 0; i < 7; i++) {
        final path = Path();
        for (var x = 0.0; x <= size.width + 8; x += 8) {
          final y =
              size.height * (0.24 + i * 0.10) +
              math.sin(
                    x / (style == 'Ribbons' ? 85 : 135) +
                        tick * (i.isEven ? 0.7 : -0.45) +
                        i * 0.6,
                  ) *
                  (style == 'Ribbons' ? 24 : 38);
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = (i.isEven ? accent : palette.accent2).withValues(
              alpha: 0.08 + i * 0.012,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = style == 'Ribbons' ? 9 : 3,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_AtmospherePainter old) =>
      old.tick != tick ||
      old.palette != palette ||
      old.accent != accent ||
      old.style != style;
}
