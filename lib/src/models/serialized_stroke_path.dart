import 'path_command.dart';
import 'paint_mode.dart';

class SerializedStrokePath {
  final List<PathCommand> commands;
  final PaintMode mode;

  SerializedStrokePath(this.commands, this.mode);

  Map<String, dynamic> toJson() {
    return {
      'commands': commands.map((c) => c.toJson()).toList(),
      'mode': mode.toString(),
    };
  }

  static SerializedStrokePath fromJson(Map<String, dynamic> json) {
    return SerializedStrokePath(
      (json['commands'] as List).map((c) => PathCommand.fromJson(c)).toList(),
      PaintMode.values.firstWhere((e) => e.toString() == json['mode']),
    );
  }
}