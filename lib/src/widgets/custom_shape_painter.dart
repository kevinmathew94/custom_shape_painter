import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/rendering.dart';
import '../models/paint_mode.dart';
import '../models/stroke_path.dart';
import '../models/path_command.dart';
import '../models/serialized_stroke_path.dart';
import '../painters/path_painter.dart';

class CustomShapePainter extends StatefulWidget {
  final String maskImagePath;
  final List<Map<String, dynamic>>? initialPaths;
  final Function(double)? onCoverageChanged;
  final GlobalKey<CustomShapePainterState>? controllerKey;

  const CustomShapePainter({
    Key? key,
    required this.maskImagePath,
    this.initialPaths,
    this.onCoverageChanged,
    this.controllerKey,
  }) : super(key: key ?? (controllerKey as Key?));

  @override
  CustomShapePainterState createState() => CustomShapePainterState();
}

class CustomShapePainterState extends State<CustomShapePainter> {
  ui.Image? maskImage;
  final List<StrokePath> _paths = [];
  Path _currentPath = Path();
  List<Offset> _currentStrokePoints = [];
  bool isLoading = true;
  double coveragePercentage = 0.0;
  Size? canvasSize;
  bool isErasing = false;
  final GlobalKey _paintKey = GlobalKey();
  bool _isDrawing = false;
  ByteData? maskByteData;

  // For externally accessing points
  List<Offset> get currentPoints => _currentStrokePoints.toList();

  @override
  void initState() {
    super.initState();
    loadMaskImage().then((_) {
      if (widget.initialPaths != null) {
        restoreInitialPaths();
      }
    });
  }

  void restoreInitialPaths() {
    if (widget.initialPaths == null) return;

    try {
      final serializedPaths = widget.initialPaths!
          .map((json) => SerializedStrokePath.fromJson(json))
          .toList();

      setState(() {
        _paths.clear();
        for (final serializedPath in serializedPaths) {
          final path = Path();

          for (final command in serializedPath.commands) {
            switch (command.type) {
              case 'moveTo':
                path.moveTo(command.values[0], command.values[1]);
                break;
              case 'lineTo':
                path.lineTo(command.values[0], command.values[1]);
                break;
              // Add other command types as needed
            }
          }

          _paths.add(StrokePath(path, serializedPath.mode));
        }
      });

    } catch (e) {
      print('Error restoring paths: $e');
    }
  }

  Future<void> loadMaskImage() async {
    final completer = Completer<ui.Image>();
    final imageProvider = AssetImage(widget.maskImagePath);
    final stream = imageProvider.resolve(ImageConfiguration.empty);

    stream.addListener(ImageStreamListener((info, _) {
      completer.complete(info.image);
    }));

    maskImage = await completer.future;
    maskByteData = await maskImage!.toByteData();

    canvasSize =
        Size(maskImage!.width.toDouble(), maskImage!.height.toDouble());

    setState(() {
      isLoading = false;
    });
  }

  List<SerializedStrokePath> getSerializedPaths() {
    return _paths.map((strokePath) {
      return SerializedStrokePath(
        strokePath.path.getCommands(),
        strokePath.mode,
      );
    }).toList();
  }

  void restorePaths(List<SerializedStrokePath> serializedPaths) {
    setState(() {
      _paths.clear();
      for (final serializedPath in serializedPaths) {
        final path = Path();

        for (final command in serializedPath.commands) {
          switch (command.type) {
            case 'moveTo':
              path.moveTo(command.values[0], command.values[1]);
              break;
            case 'lineTo':
              path.lineTo(command.values[0], command.values[1]);
              break;
          }
        }

        _paths.add(StrokePath(path, serializedPath.mode));
      }
    });

  }

  Future<Map<String, dynamic>> captureStateData() async {
    await calculateCoverage();
    final thumbnailUint8List = await captureAndShowThumbnail();
    final serializedPaths = getSerializedPaths();

    return {
      'thumbnail': thumbnailUint8List,
      'paths': serializedPaths.map((p) => p.toJson()).toList(),
      'coverage': coveragePercentage.floor(),
    };
  }

  // Douglas-Peucker algorithm for path simplification
  List<Offset> _simplifyPath(List<Offset> points, double epsilon) {
    if (points.length <= 2) return points;

    double maxDistance = 0;
    int maxIndex = 0;

    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      double distance = _perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    if (maxDistance > epsilon) {
      final List<Offset> firstHalf =
          _simplifyPath(points.sublist(0, maxIndex + 1), epsilon);
      final List<Offset> secondHalf =
          _simplifyPath(points.sublist(maxIndex), epsilon);

      return [...firstHalf.take(firstHalf.length - 1), ...secondHalf];
    }

    return [start, end];
  }

  double _perpendicularDistance(
      Offset point, Offset lineStart, Offset lineEnd) {
    if (lineStart == lineEnd) return (point - lineStart).distance;

    final numerator = ((lineEnd.dx - lineStart.dx) * (lineStart.dy - point.dy) -
            (lineStart.dx - point.dx) * (lineEnd.dy - lineStart.dy))
        .abs();
    final denominator = (lineEnd - lineStart).distance;

    return numerator / denominator;
  }

  Future<void> _optimizeAndAddCurrentStroke() async {
    if (_currentStrokePoints.length < 2) return;

    final optimizedPoints = _simplifyPath(_currentStrokePoints, 2.0);
    final path = Path();

    path.moveTo(optimizedPoints[0].dx, optimizedPoints[0].dy);

    if (optimizedPoints.length == 2) {
      path.lineTo(optimizedPoints[1].dx, optimizedPoints[1].dy);
    } else {
      for (int i = 1; i < optimizedPoints.length - 1; i++) {
        final p0 = optimizedPoints[i - 1];
        final p1 = optimizedPoints[i];
        final p2 = optimizedPoints[i + 1];

        final cp1x = p1.dx - (p1.dx - p0.dx) * 0.2;
        final cp1y = p1.dy - (p1.dy - p0.dy) * 0.2;
        final cp2x = p1.dx + (p2.dx - p1.dx) * 0.2;
        final cp2y = p1.dy + (p2.dy - p1.dy) * 0.2;

        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }
    }

    setState(() {
      _paths
          .add(StrokePath(path, isErasing ? PaintMode.erase : PaintMode.draw));
      _currentPath = Path();
      _currentStrokePoints = [];
    });
  }

  Future<void> autoFill() async {
    if (maskImage == null || maskByteData == null) return;

    final width = maskImage!.width;
    final height = maskImage!.height;

    // Clear existing paths
    setState(() {
      _paths.clear();
      _currentPath = Path();
      _currentStrokePoints = [];
    });

    // Scan the image horizontally with a step of 5 pixels
    for (int y = 0; y < height; y += 5) {
      bool isDrawing = false;
      int startX = 0;
      Path rowPath = Path();

      for (int x = 0; x < width; x++) {
        final pixelOffset = (y * width + x) * 4;
        final alpha = maskByteData!.getUint8(pixelOffset + 3);

        if (alpha > 0 && !isDrawing) {
          // Start a new line
          isDrawing = true;
          startX = x;
          rowPath.moveTo(startX.toDouble(), y.toDouble());
        } else if ((alpha == 0 || x == width - 1) && isDrawing) {
          // End the current line
          isDrawing = false;
          rowPath.lineTo(x.toDouble(), y.toDouble());
        }
      }

      if (rowPath
          .computeMetrics()
          .isNotEmpty) {
        setState(() {
          _paths.add(StrokePath(rowPath, PaintMode.draw));
        });
      }
    }
  }
  Future<Uint8List?> captureAndShowThumbnail() async {
    if (_paintKey.currentContext == null) return null;

    try {
      final boundary =
          _paintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  Future<void> clearCanvas() async {
    setState(() {
      _paths.clear();
      _currentPath = Path();
      _currentStrokePoints = [];
      coveragePercentage = 0.0;
    });
    widget.onCoverageChanged?.call(0.0);
  }

  void _handlePanStart(DragStartDetails details) {
    final pos = _getLocalPosition(details.globalPosition);
    setState(() {
      _isDrawing = true;
      _currentPath = Path()..moveTo(pos.dx, pos.dy);
      _currentStrokePoints = [pos];
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (!_isDrawing) return;

    final pos = _getLocalPosition(details.globalPosition);
    setState(() {
      _currentPath.lineTo(pos.dx, pos.dy);
      _currentStrokePoints.add(pos);
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (!_isDrawing) return;

    _isDrawing = false;
    _optimizeAndAddCurrentStroke();
  }

  Offset _getLocalPosition(Offset globalPosition) {
    final box = _paintKey.currentContext!.findRenderObject() as RenderBox;
    final localPos = box.globalToLocal(globalPosition);
    final scaleX = canvasSize!.width / box.size.width;
    final scaleY = canvasSize!.height / box.size.height;
    return Offset(localPos.dx * scaleX, localPos.dy * scaleY);
  }

  Future<void> calculateCoverage() async {
    if (canvasSize == null) return;

    final recorder = ui.PictureRecorder();
    final trackingCanvas = Canvas(recorder);

    // Save the canvas state to handle masking
    trackingCanvas.saveLayer(
      Rect.fromLTWH(0, 0, canvasSize!.width, canvasSize!.height),
      Paint(),
    );

    final drawPaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 20.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final erasePaint = Paint()
      ..color = Colors.transparent
      ..strokeWidth = 20.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.clear;

    // Draw all completed paths
    for (final strokePath in _paths) {
      final paint = strokePath.mode == PaintMode.draw ? drawPaint : erasePaint;
      trackingCanvas.drawPath(strokePath.path, paint);
    }

    // Draw current path if it exists
    if (_currentPath.computeMetrics().isNotEmpty) {
      final paint = isErasing ? erasePaint : drawPaint;
      trackingCanvas.drawPath(_currentPath, paint);
    }

    // Apply the mask
    if (maskImage != null) {
      trackingCanvas.drawImage(
        maskImage!,
        Offset.zero,
        Paint()..blendMode = BlendMode.dstIn,
      );
    }

    trackingCanvas.restore();

    final picture = recorder.endRecording();
    final trackingImage = await picture.toImage(
      canvasSize!.width.toInt(),
      canvasSize!.height.toInt(),
    );

    final ByteData? byteData = await trackingImage.toByteData();

    if (byteData != null && maskByteData != null) {
      int paintedPixels = 0;
      int totalMaskPixels = 0;

      // Compare pixels
      for (int i = 0; i < byteData.lengthInBytes; i += 4) {
        final maskAlpha = maskByteData!.getUint8(i + 3);
        if (maskAlpha > 0) {
          totalMaskPixels++;
          final paintedAlpha = byteData.getUint8(i + 3);
          if (paintedAlpha > 0) {
            paintedPixels++;
          }
        }
      }

      final newCoveragePercentage =
          totalMaskPixels > 0 ? (paintedPixels / totalMaskPixels) * 100 : 0.0;

      setState(() {
        coveragePercentage = newCoveragePercentage;
      });

      widget.onCoverageChanged?.call(coveragePercentage);
    }

    trackingImage.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                Card(
                    shape: const ContinuousRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8.0)),
                    ),
                    color: Colors.white,
                    elevation: 1,
                    child: IconButton(
                        icon: const Icon(
                          Icons.accessibility_new_rounded,
                          color: Colors.red,
                        ),
                        onPressed: autoFill)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Select Full'),
                )
              ],
            ),
            Column(
              children: [
                Card(
                    shape: const ContinuousRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8.0)),
                    ),
                    color: Colors.white,
                    elevation: 1,
                    child: IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        color: Colors.green,
                      ),
                      onPressed: clearCanvas,
                    )),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Reset'))
              ],
            ),
            Column(
              children: [
                Card(
                    shape: const ContinuousRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8.0)),
                    ),
                    color: Colors.white,
                    elevation: 1,
                    child: IconButton(
                      icon: isErasing
                          ? const Icon(Icons.deblur, color: Colors.red)
                          : const Icon(Icons.deblur, color: Colors.grey),
                      onPressed: () => setState(() {
                        isErasing = !isErasing;
                      }),
                    )),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(isErasing ? 'Eraser On' : 'Eraser Off'),
                )
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: RepaintBoundary(
            key: _paintKey,
            child: CustomPaint(
              painter: PathPainter(
                paths: _paths,
                currentPath: _currentPath,
                currentMode: isErasing ? PaintMode.erase : PaintMode.draw,
                maskImage: maskImage!,
              ),
              size: canvasSize!,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    maskImage?.dispose();
    super.dispose();
  }
}
