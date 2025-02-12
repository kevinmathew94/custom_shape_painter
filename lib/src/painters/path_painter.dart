import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../models/stroke_path.dart';
import '../models/paint_mode.dart';

class PathPainter extends CustomPainter {
  final List<StrokePath> paths;
  final Path currentPath;
  final PaintMode currentMode;
  final ui.Image maskImage;

  PathPainter({
    required this.paths,
    required this.currentPath,
    required this.currentMode,
    required this.maskImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(maskImage, Offset.zero, Paint());
    canvas.saveLayer(Offset.zero & size, Paint());

    final drawPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 30.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final erasePaint = Paint()
      ..color = Colors.transparent
      ..strokeWidth = 30.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.clear;

    for (final strokePath in paths) {
      final paint = strokePath.mode == PaintMode.draw ? drawPaint : erasePaint;
      canvas.drawPath(strokePath.path, paint);
    }

    if (currentPath.computeMetrics().isNotEmpty) {
      final paint = currentMode == PaintMode.draw ? drawPaint : erasePaint;
      canvas.drawPath(currentPath, paint);
    }

    canvas.drawImage(
        maskImage, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
    canvas.restore();
  }

  @override
  bool shouldRepaint(PathPainter oldDelegate) => true;
}