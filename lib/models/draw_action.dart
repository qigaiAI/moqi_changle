import 'dart:ui';

class DrawAction {
  final String type; // 'draw', 'erase', 'clear', 'undo'
  final Offset? point;
  final Color? color;
  final double? strokeWidth;
  final int timestamp;

  const DrawAction({
    required this.type,
    this.point,
    this.color,
    this.strokeWidth,
    required this.timestamp,
  });

  factory DrawAction.fromJson(Map<String, dynamic> json) => DrawAction(
        type: json['type'] as String,
        point: json['point'] != null
            ? Offset(json['point']['dx'] as double, json['point']['dy'] as double)
            : null,
        color: json['color'] != null ? Color(json['color'] as int) : null,
        strokeWidth: json['strokeWidth'] as double?,
        timestamp: json['timestamp'] as int,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'point': point != null ? {'dx': point!.dx, 'dy': point!.dy} : null,
        'color': color?.toARGB32(),
        'strokeWidth': strokeWidth,
        'timestamp': timestamp,
      };
}
