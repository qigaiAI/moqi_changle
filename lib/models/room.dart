class Room {
  final String id;
  final String code;
  final String gameMode; // 'quiz' | 'draw'
  final String status;   // 'waiting' | 'playing' | 'finished'
  final int maxPlayers;
  final int rounds;
  final int drawingTime;
  final String? hostId;
  final DateTime createdAt;

  const Room({
    required this.id,
    required this.code,
    required this.gameMode,
    required this.status,
    required this.maxPlayers,
    required this.rounds,
    required this.drawingTime,
    this.hostId,
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        id: json['id'] as String,
        code: json['code'] as String,
        gameMode: json['game_mode'] as String,
        status: json['status'] as String,
        maxPlayers: json['max_players'] as int,
        rounds: json['rounds'] as int,
        drawingTime: json['drawing_time'] as int,
        hostId: json['host_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'game_mode': gameMode,
        'status': status,
        'max_players': maxPlayers,
        'rounds': rounds,
        'drawing_time': drawingTime,
        'host_id': hostId,
        'created_at': createdAt.toIso8601String(),
      };

  Room copyWith({
    String? status,
    String? hostId,
  }) =>
      Room(
        id: id,
        code: code,
        gameMode: gameMode,
        status: status ?? this.status,
        maxPlayers: maxPlayers,
        rounds: rounds,
        drawingTime: drawingTime,
        hostId: hostId ?? this.hostId,
        createdAt: createdAt,
      );
}
