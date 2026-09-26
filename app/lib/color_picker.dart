import 'package:flutter/material.dart';

/// A full saturation/value picker with hue and exact hex input.
Future<Color?> pickCustomColor(BuildContext context, Color initial) =>
    showDialog<Color>(
      context: context,
      builder: (_) => _ColorPicker(initial: initial),
    );

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.initial});
  final Color initial;
  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController hex = TextEditingController(
    text: widget.initial
        .toARGB32()
        .toRadixString(16)
        .substring(2)
        .toUpperCase(),
  );

  void select(Color color) {
    setState(() {
      hsv = HSVColor.fromColor(color);
      hex.text = color.toARGB32().toRadixString(16).substring(2).toUpperCase();
    });
  }

  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose color'),
    content: SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 280,
            height: 200,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onTapDown: (details) => _point(details.localPosition, box),
                onPanUpdate: (details) => _point(details.localPosition, box),
                child: CustomPaint(
                  painter: _SaturationValuePainter(hsv.hue),
                  child: Align(
                    alignment: Alignment(
                      hsv.saturation * 2 - 1,
                      1 - hsv.value * 2,
                    ),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hsv.toColor(),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 3),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Slider(
            value: hsv.hue,
            min: 0,
            max: 360,
            onChanged: (value) => select(hsv.withHue(value).toColor()),
          ),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: hsv.toColor(),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: hex,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Hex',
                    prefixText: '#',
                    counterText: '',
                  ),
                  onChanged: (value) {
                    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
                      setState(
                        () => hsv = HSVColor.fromColor(
                          Color(0xFF000000 | int.parse(value, radix: 16)),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, hsv.toColor()),
        child: const Text('Use color'),
      ),
    ],
  );

  void _point(Offset point, BoxConstraints box) {
    select(
      hsv
          .withSaturation((point.dx / box.maxWidth).clamp(0.0, 1.0))
          .withValue((1 - point.dy / box.maxHeight).clamp(0.0, 1.0))
          .toColor(),
    );
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hue);
  final double hue;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter oldDelegate) =>
      oldDelegate.hue != hue;
}
