class Player {
  final String id;
  final String roomId;
  final String name;
  final bool isHost;
  final int score;
  final DateTime joinedAt;
  final DateTime? leftAt;

  const Player({
    required this.id,
    required this.roomId,
    required this.name,
    required this.isHost,
    required this.score,
    required this.joinedAt,
    this.leftAt,
  });

  bool get isActive => leftAt == null;

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        name: json['name'] as String,
        isHost: json['is_host'] as bool,
        score: json['score'] as int,
        joinedAt: DateTime.parse(json['joined_at'] as String),
        leftAt: json['left_at'] != null
            ? DateTime.parse(json['left_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'name': name,
        'is_host': isHost,
        'score': score,
        'joined_at': joinedAt.toIso8601String(),
        'left_at': leftAt?.toIso8601String(),
      };

  Player copyWith({
    int? score,
    bool? isHost,
    DateTime? leftAt,
  }) =>
      Player(
        id: id,
        roomId: roomId,
        name: name,
        isHost: isHost ?? this.isHost,
        score: score ?? this.score,
        joinedAt: joinedAt,
        leftAt: leftAt ?? this.leftAt,
      );
}
