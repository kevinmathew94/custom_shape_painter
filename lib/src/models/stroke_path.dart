import 'dart:ui';
import 'paint_mode.dart';

/// Represents a stroke path with its painting mode
class StrokePath {
  final Path path;
  final PaintMode mode;

  StrokePath(this.path, this.mode);
}