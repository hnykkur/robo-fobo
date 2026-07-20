import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Normalized output in [-1, 1]: [nx] right positive, [ny] down positive (screen coords).
///
/// The knob moves freely; emitted direction is snapped to one of [directionCount]
/// equally spaced headings (default 16). Magnitude is preserved (with dead zone).
class AnalogJoystick extends StatefulWidget {
  const AnalogJoystick({
    super.key,
    required this.onChanged,
    this.size = 240,
    this.deadZone = 0.12,
    this.directionCount = 16,
    this.accentColor = const Color(0xFF1565C0),
  });

  final void Function(double nx, double ny) onChanged;
  final double size;
  final double deadZone;

  /// Number of discrete steering headings around the wheel.
  final int directionCount;

  /// Knob colour (e.g. last LED preset). The pad is a faint tint of this hue on surface.
  final Color accentColor;

  @override
  State<AnalogJoystick> createState() => _AnalogJoystickState();
}

class _AnalogJoystickState extends State<AnalogJoystick> {
  Offset _knob = Offset.zero;

  /// Index of nearest heading, or -1 when in dead zone / centered.
  int _activeTick = -1;

  /// Snaps free knob position to one of [directionCount] headings.
  /// Returns (nx, ny, activeTick).
  (double, double, int) _quantize(Offset knob, double maxR) {
    if (maxR <= 0) return (0.0, 0.0, -1);

    final nxRaw = knob.dx / maxR;
    final nyRaw = knob.dy / maxR;
    final mag = math.sqrt(nxRaw * nxRaw + nyRaw * nyRaw);

    if (mag < widget.deadZone) {
      return (0.0, 0.0, -1);
    }

    final n = widget.directionCount;
    final angle = math.atan2(nyRaw, nxRaw);
    var idx = ((angle / (2 * math.pi) * n).round()) % n;
    if (idx < 0) idx += n;
    final snapped = idx * 2 * math.pi / n;
    final outMag = mag.clamp(0.0, 1.0);
    return (outMag * math.cos(snapped), outMag * math.sin(snapped), idx);
  }

  void _reset() {
    setState(() {
      _knob = Offset.zero;
      _activeTick = -1;
    });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final center = Offset(s / 2, s / 2);
    final maxDist = s / 2 * 0.85 - s * 0.14;

    final surface = Theme.of(context).colorScheme.surface;
    // Visible pad ring: very light wash of accent hue (knob stays strong accent).
    final baseColor = Color.lerp(surface, widget.accentColor, 0.10)!;
    final outline = Color.lerp(surface, widget.accentColor, 0.35)!;

    return SizedBox(
      width: s,
      height: s,
      child: GestureDetector(
        onPanDown: (d) => _pan(center, maxDist, d.localPosition),
        onPanUpdate: (d) => _pan(center, maxDist, d.localPosition),
        onPanEnd: (_) => _reset(),
        onPanCancel: _reset,
        child: CustomPaint(
          painter: _JoystickPainter(
            knobCenter: center + _knob,
            baseRadius: s / 2 * 0.85,
            knobRadius: s * 0.14,
            knobColor: widget.accentColor,
            baseColor: baseColor,
            tickColor: outline,
            activeTickColor: widget.accentColor,
            directionCount: widget.directionCount,
            activeTick: _activeTick,
          ),
        ),
      ),
    );
  }

  void _pan(Offset center, double maxDist, Offset local) {
    var d = local - center;
    final dist = d.distance;
    if (dist > maxDist && dist > 0) {
      d = d * (maxDist / dist);
    }
    late final double nx;
    late final double ny;
    late final int tick;
    setState(() {
      _knob = d;
      (nx, ny, tick) = _quantize(d, maxDist);
      _activeTick = tick;
    });
    widget.onChanged(nx, ny);
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({
    required this.knobCenter,
    required this.baseRadius,
    required this.knobRadius,
    required this.knobColor,
    required this.baseColor,
    required this.tickColor,
    required this.activeTickColor,
    required this.directionCount,
    required this.activeTick,
  });

  final Offset knobCenter;
  final double baseRadius;
  final double knobRadius;
  final Color knobColor;
  final Color baseColor;
  final Color tickColor;
  final Color activeTickColor;
  final int directionCount;
  final int activeTick;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(c, baseRadius, basePaint);

    final tickOuter = baseRadius;
    final tickInner = baseRadius * 0.78;
    final activeInner = baseRadius * 0.72;

    for (var i = 0; i < directionCount; i++) {
      final a = i * 2 * math.pi / directionCount;
      final isActive = i == activeTick;
      final inner = isActive ? activeInner : tickInner;
      final p0 = Offset(c.dx + inner * math.cos(a), c.dy + inner * math.sin(a));
      final p1 = Offset(c.dx + tickOuter * math.cos(a), c.dy + tickOuter * math.sin(a));
      final paint = Paint()
        ..color = isActive ? activeTickColor : tickColor
        ..strokeWidth = isActive ? 4.0 : 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(p0, p1, paint);
    }

    final knobPaint = Paint()
      ..color = knobColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.knobCenter != knobCenter ||
        oldDelegate.baseRadius != baseRadius ||
        oldDelegate.knobRadius != knobRadius ||
        oldDelegate.knobColor != knobColor ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.activeTickColor != activeTickColor ||
        oldDelegate.directionCount != directionCount ||
        oldDelegate.activeTick != activeTick;
  }
}
