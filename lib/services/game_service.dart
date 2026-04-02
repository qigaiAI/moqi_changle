import '../models/game_session.dart';
import 'supabase_service.dart';

class GameService {
  final _client = SupabaseService.client;

  Future<GameSession> createSession(String roomId) async {
    final data = await _client.from('game_sessions').insert({
      'room_id': roomId,
      'current_round': 1,
      'answers': {},
      'guesses': {},
      'drawing_actions': [],
    }).select().single();
    return GameSession.fromJson(data);
  }

  Future<GameSession?> getActiveSession(String roomId) async {
    final data = await _client
        .from('game_sessions')
        .select()
        .eq('room_id', roomId)
        .isFilter('ended_at', null)
        .maybeSingle();
    return data != null ? GameSession.fromJson(data) : null;
  }

  Future<void> updateSession(String sessionId, Map<String, dynamic> updates) async {
    await _client.from('game_sessions').update(updates).eq('id', sessionId);
  }

  Future<void> submitAnswer(String sessionId, String playerId, String answer) async {
    final session = await _client
        .from('game_sessions')
        .select('answers')
        .eq('id', sessionId)
        .single();
    final answers = Map<String, dynamic>.from(session['answers'] as Map);
    answers[playerId] = answer;
    await _client
        .from('game_sessions')
        .update({'answers': answers}).eq('id', sessionId);
  }

  Future<void> submitGuess(
      String sessionId, String playerId, bool correct, int timestamp) async {
    final session = await _client
        .from('game_sessions')
        .select('guesses')
        .eq('id', sessionId)
        .single();
    final guesses = Map<String, dynamic>.from(session['guesses'] as Map);
    if (!guesses.containsKey(playerId)) {
      guesses[playerId] = {'correct': correct, 'time': timestamp};
      await _client
          .from('game_sessions')
          .update({'guesses': guesses}).eq('id', sessionId);
    }
  }

  Future<void> appendDrawActions(
      String sessionId, List<Map<String, dynamic>> newActions) async {
    final session = await _client
        .from('game_sessions')
        .select('drawing_actions')
        .eq('id', sessionId)
        .single();
    final existing = List<dynamic>.from(session['drawing_actions'] as List);
    existing.addAll(newActions);
    await _client
        .from('game_sessions')
        .update({'drawing_actions': existing}).eq('id', sessionId);
  }

  Future<void> updatePlayerScore(String playerId, int scoreDelta) async {
    final data = await _client
        .from('players')
        .select('score')
        .eq('id', playerId)
        .single();
    final newScore = (data['score'] as int) + scoreDelta;
    await _client
        .from('players')
        .update({'score': newScore}).eq('id', playerId);
  }

  Future<void> endSession(String sessionId) async {
    await _client.from('game_sessions').update({
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }
}
