class GameSession {
  final String id;
  final String roomId;
  final int currentRound;
  final String? currentQuestion;
  final String? currentWord;
  final String? drawerId;
  final String? questionerId;
  final Map<String, dynamic> answers;   // playerId -> answer
  final Map<String, dynamic> guesses;   // playerId -> {time, correct}
  final List<dynamic> drawingActions;
  final DateTime startedAt;
  final DateTime? endedAt;

  const GameSession({
    required this.id,
    required this.roomId,
    required this.currentRound,
    this.currentQuestion,
    this.currentWord,
    this.drawerId,
    this.questionerId,
    required this.answers,
    required this.guesses,
    required this.drawingActions,
    required this.startedAt,
    this.endedAt,
  });

  factory GameSession.fromJson(Map<String, dynamic> json) => GameSession(
        id: json['id'] as String,
        roomId: json['room_id'] as String,
        currentRound: json['current_round'] as int,
        currentQuestion: json['current_question'] as String?,
        currentWord: json['current_word'] as String?,
        drawerId: json['drawer_id'] as String?,
        questionerId: json['questioner_id'] as String?,
        answers: Map<String, dynamic>.from(json['answers'] as Map? ?? {}),
        guesses: Map<String, dynamic>.from(json['guesses'] as Map? ?? {}),
        drawingActions: List<dynamic>.from(json['drawing_actions'] as List? ?? []),
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: json['ended_at'] != null
            ? DateTime.parse(json['ended_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'room_id': roomId,
        'current_round': currentRound,
        'current_question': currentQuestion,
        'current_word': currentWord,
        'drawer_id': drawerId,
        'questioner_id': questionerId,
        'answers': answers,
        'guesses': guesses,
        'drawing_actions': drawingActions,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
      };
}
