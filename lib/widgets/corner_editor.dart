import 'dart:io';

import 'package:flutter/material.dart';

/// Shows an image with a draggable quadrilateral. Corners are normalized
/// (0..1) and ordered top-left, top-right, bottom-right, bottom-left.
class CornerEditor extends StatefulWidget {
  const CornerEditor({
    super.key,
    required this.imagePath,
    required this.imageSize,
    required this.corners,
    required this.onChanged,
  });

  final String imagePath;
  final Size imageSize;
  final List<(double, double)> corners;
  final ValueChanged<List<(double, double)>> onChanged;

  @override
  State<CornerEditor> createState() => _CornerEditorState();
}

class _CornerEditorState extends State<CornerEditor> {
  static const _touchRadius = 48.0;
  static const _magnifierSize = Size(110, 110);
  static const _magnifierLift = 90.0;

  int? _active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final fitted = applyBoxFit(BoxFit.contain, widget.imageSize, constraints.biggest);
      final rect = Alignment.center.inscribe(fitted.destination, Offset.zero & constraints.biggest);
      Offset toScreen((double, double) c) =>
          rect.topLeft + Offset(c.$1 * rect.width, c.$2 * rect.height);
      final points = [for (final c in widget.corners) toScreen(c)];
      final active = _active;

      return GestureDetector(
        onPanStart: (d) {
          var best = -1;
          var bestDist = _touchRadius;
          for (var i = 0; i < points.length; i++) {
            final dist = (points[i] - d.localPosition).distance;
            if (dist < bestDist) {
              best = i;
              bestDist = dist;
            }
          }
          if (best >= 0) setState(() => _active = best);
        },
        onPanUpdate: (d) {
          final i = _active;
          if (i == null) return;
          final pos = points[i] + d.delta;
          final corners = [...widget.corners];
          corners[i] = (
            ((pos.dx - rect.left) / rect.width).clamp(0.0, 1.0),
            ((pos.dy - rect.top) / rect.height).clamp(0.0, 1.0),
          );
          widget.onChanged(corners);
        },
        onPanEnd: (_) => setState(() => _active = null),
        onPanCancel: () => setState(() => _active = null),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.file(File(widget.imagePath), fit: BoxFit.fill, cacheWidth: 1600),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _QuadPainter(points, active, Theme.of(context).colorScheme.primary),
              ),
            ),
            if (active != null)
              Positioned(
                left: points[active].dx - _magnifierSize.width / 2,
                top: points[active].dy - _magnifierLift - _magnifierSize.height / 2,
                child: const RawMagnifier(
                  size: _magnifierSize,
                  magnificationScale: 2,
                  focalPointOffset: Offset(0, _magnifierLift),
                  decoration: MagnifierDecoration(
                    shape: CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _QuadPainter extends CustomPainter {
  _QuadPainter(this.points, this.active, this.color);

  final List<Offset> points;
  final int? active;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addPolygon(points, true);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.15));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (var i = 0; i < points.length; i++) {
      final r = i == active ? 14.0 : 11.0;
      canvas.drawCircle(points[i], r, Paint()..color = Colors.white);
      canvas.drawCircle(
        points[i],
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.points != points || old.active != active || old.color != color;
}
