import 'package:flutter/material.dart';

/// Represents a single path command
class PathCommand {
  final String type;
  final List<double> values;

  PathCommand(this.type, this.values);

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'values': values,
    };
  }

  static PathCommand fromJson(Map<String, dynamic> json) {
    return PathCommand(
      json['type'] as String,
      (json['values'] as List).cast<double>(),
    );
  }
}

extension PathRecording on Path {
  List<PathCommand> getCommands() {
    final commands = <PathCommand>[];

    void addCommand(String type, List<double> values) {
      commands.add(PathCommand(type, values));
    }

    computeMetrics().forEach((metric) {
      var extractPath = Path();
      extractPath.addPath(
        this,
        Offset.zero,
        matrix4: Matrix4.identity().storage,
      );

      for (var i = 0.0; i <= metric.length; i += 1) {
        final pos = metric.getTangentForOffset(i)?.position;
        if (pos != null) {
          if (i == 0) {
            addCommand('moveTo', [pos.dx, pos.dy]);
          } else {
            addCommand('lineTo', [pos.dx, pos.dy]);
          }
        }
      }
    });

    return commands;
  }
}