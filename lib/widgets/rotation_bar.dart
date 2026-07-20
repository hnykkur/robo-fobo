import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Horizontal spring bar: **left** → **-1**, **right** → **+1** (normalized).
/// Released → snaps to center and reports **0**. Speed scales with distance from center.
class RotationBar extends StatefulWidget {
  const RotationBar({
    super.key,
    required this.onChanged,
    this.height = 56,
    this.thumbRadius = 16,
    this.deadZone = 0.06,
    this.accentColor = const Color(0xFF1565C0),
  });

  final ValueChanged<double> onChanged;
  final double height;
  final double thumbRadius;
  final double deadZone;

  /// Thumb colour; track is a subtle mix (match [AnalogJoystick] accent).
  final Color accentColor;

  @override
  State<RotationBar> createState() => _RotationBarState();
}

class _RotationBarState extends State<RotationBar> {
  /// Horizontal offset of thumb from center (pixels), [-maxTravel .. maxTravel].
  double _dx = 0;

  void _emit(double maxTravel) {
    if (maxTravel <= 0) return;
    var t = _dx / maxTravel;
    if (t.abs() < widget.deadZone) {
      t = 0;
    } else {
      t = t.clamp(-1.0, 1.0);
    }
    widget.onChanged(t);
  }

  void _applyTouch(double localX, double width) {
    final maxT = _maxTravel(width);
    final cx = width / 2;
    var d = localX - cx;
    if (d.abs() > maxT) {
      d = d.sign * maxT;
    }
    setState(() => _dx = d);
    _emit(maxT);
  }

  void _reset() {
    setState(() => _dx = 0);
    widget.onChanged(0);
  }

  double _maxTravel(double width) =>
      math.max(8.0, width / 2 - widget.thumbRadius - 8);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        return SizedBox(
          height: widget.height,
          width: w,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _applyTouch(d.localPosition.dx, w),
            onPanUpdate: (d) => _applyTouch(d.localPosition.dx, w),
            onPanEnd: (_) => _reset(),
            onPanCancel: _reset,
            child: CustomPaint(
              painter: _RotationBarPainter(
                dx: _dx,
                thumbRadius: widget.thumbRadius,
                trackY: widget.height / 2,
                accentColor: widget.accentColor,
                trackColor: Color.lerp(
                  const Color(0xFFB0BEC5),
                  widget.accentColor,
                  0.38,
                )!,
              ),
              size: Size(w, widget.height),
            ),
          ),
        );
      },
    );
  }
}

class _RotationBarPainter extends CustomPainter {
  _RotationBarPainter({
    required this.dx,
    required this.thumbRadius,
    required this.trackY,
    required this.accentColor,
    required this.trackColor,
  });

  final double dx;
  final double thumbRadius;
  final double trackY;
  final Color accentColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(8, trackY),
      Offset(size.width - 8, trackY),
      trackPaint,
    );

    final knobCx = cx + dx;
    final knobPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(knobCx, trackY), thumbRadius, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _RotationBarPainter oldDelegate) {
    return oldDelegate.dx != dx ||
        oldDelegate.thumbRadius != thumbRadius ||
        oldDelegate.trackY != trackY ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.trackColor != trackColor;
  }
}
