import 'dart:math';
import '../models/room.dart';
import '../models/player.dart';
import 'supabase_service.dart';

class RoomService {
  final _client = SupabaseService.client;

  String _generateRoomCode() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  Future<Room> createRoom({
    required String gameMode,
    required int maxPlayers,
    required int rounds,
    required int drawingTime,
  }) async {
    final code = _generateRoomCode();
    final data = await _client.from('rooms').insert({
      'code': code,
      'game_mode': gameMode,
      'max_players': maxPlayers,
      'rounds': rounds,
      'drawing_time': drawingTime,
      'status': 'waiting',
    }).select().single();

    return Room.fromJson(data);
  }

  Future<Room?> getRoomByCode(String code) async {
    final data = await _client
        .from('rooms')
        .select()
        .eq('code', code)
        .maybeSingle();
    return data != null ? Room.fromJson(data) : null;
  }

  Future<void> updateRoomStatus(String roomId, String status) async {
    await _client.from('rooms').update({'status': status}).eq('id', roomId);
  }

  Future<Player> joinRoom({
    required String roomId,
    required String playerName,
    required bool isHost,
  }) async {
    final data = await _client.from('players').insert({
      'room_id': roomId,
      'name': playerName,
      'is_host': isHost,
      'score': 0,
    }).select().single();

    return Player.fromJson(data);
  }

  Future<List<Player>> getPlayers(String roomId) async {
    final data = await _client
        .from('players')
        .select()
        .eq('room_id', roomId)
        .isFilter('left_at', null);
    return (data as List).map((e) => Player.fromJson(e)).toList();
  }

  Future<void> leaveRoom(String playerId) async {
    await _client
        .from('players')
        .update({'left_at': DateTime.now().toIso8601String()}).eq('id', playerId);
  }
}
