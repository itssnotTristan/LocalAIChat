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
    'Chat Dark': GlassPalette(
      Color(0xFF171717),
      Color(0xFF212121),
      Color(0xFFE8E8E8),
      Color(0xFF777777),
      Color(0xFFF3F3F3),
    ),
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
    'Emerald': GlassPalette(
      Color(0xFF071B19),
      Color(0xFF11443A),
      Color(0xFF83E5BC),
      Color(0xFF74BFE1),
      Color(0xFFF4FFFA),
    ),
    'Rose': GlassPalette(
      Color(0xFF200F21),
      Color(0xFF572944),
      Color(0xFFFFAFC9),
      Color(0xFFD9A5FF),
      Color(0xFFFFF7FB),
    ),
    'Solar': GlassPalette(
      Color(0xFF21170E),
      Color(0xFF594126),
      Color(0xFFFFD084),
      Color(0xFFFF8C72),
      Color(0xFFFFFAF0),
    ),
    'Custom': GlassPalette(
      Color(0xFF071625),
      Color(0xFF19324B),
      Color(0xFF55C8FF),
      Color(0xFF95E5FF),
      Color(0xFFFFFFFF),
    ),
  };

  static GlassPalette resolve(String name, Color customColor) {
    if (name != 'Custom') return presets[name] ?? presets['Aurora']!;
    final hsl = HSLColor.fromColor(customColor);
    return GlassPalette(
      hsl
          .withLightness(0.10)
          .withSaturation((hsl.saturation * 0.65).clamp(0.15, 0.7))
          .toColor(),
      hsl
          .withLightness(0.23)
          .withSaturation((hsl.saturation * 0.78).clamp(0.18, 0.8))
          .toColor(),
      hsl.withLightness(hsl.lightness.clamp(0.52, 0.76)).toColor(),
      hsl.withHue((hsl.hue + 36) % 360).withLightness(0.70).toColor(),
      const Color(0xFFF7FBFF),
    );
  }
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
    final design = GlassDesign.of(context);
    final palette = GlassPalette.resolve(design.themeName, design.customColor);
    final light = palette.text.computeLuminance() < 0.5;
    final quiet = design.themeName == 'Chat Dark';
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (light ? Colors.white : palette.text).withValues(
            alpha: light
                ? 0.72
                : quiet
                ? 0.12
                : 0.29,
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (light ? Colors.white : palette.accent).withValues(
              alpha: light
                  ? 0.40
                  : quiet
                  ? 0.07
                  : 0.18,
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
    required this.customColor,
    required this.motion,
    required this.speed,
    required this.backgroundStyle,
    required super.child,
    super.key,
  });
  final String themeName;
  final Color customColor;
  final bool motion;
  final double speed;
  final String backgroundStyle;
  static GlassDesign of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassDesign>()!;
  @override
  bool updateShouldNotify(GlassDesign oldWidget) =>
      themeName != oldWidget.themeName ||
      customColor != oldWidget.customColor ||
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
    final palette = GlassPalette.resolve(design.themeName, design.customColor);
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
    if (style == 'Quiet') return;
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
    if (style == 'Nebula') {
      for (var i = 0; i < 4; i++) {
        final center = Offset(
          size.width * (0.15 + i * 0.23 + 0.06 * math.sin(tick * 0.3 + i)),
          size.height *
              (0.22 + (i % 2) * 0.46 + 0.05 * math.cos(tick * 0.4 + i)),
        );
        final radius = size.shortestSide * (0.34 + i * 0.08);
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                (i.isEven ? accent : palette.accent2).withValues(alpha: 0.15),
                Colors.transparent,
              ],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        );
      }
    } else if (style == 'Starfield') {
      for (var i = 0; i < 90; i++) {
        final x = ((i * 0.61803398875 + 0.11) % 1) * size.width;
        final y = ((i * 0.38196601125 + 0.37) % 1) * size.height;
        final pulse = 0.5 + 0.5 * math.sin(tick * 0.8 + i * 1.7);
        canvas.drawCircle(
          Offset(x, y),
          i % 8 == 0 ? 1.8 : 0.8,
          Paint()..color = accent.withValues(alpha: 0.12 + pulse * 0.34),
        );
      }
    } else if (style == 'Mesh') {
      final spacing = math.max(38.0, size.shortestSide / 12);
      for (var row = 0; row * spacing < size.height + spacing; row++) {
        final path = Path();
        for (var x = 0.0; x <= size.width + 12; x += 12) {
          final y = row * spacing + 10 * math.sin(x / 90 + tick * 0.4 + row);
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = accent.withValues(alpha: 0.09)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    } else if (style == 'Orbit') {
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
