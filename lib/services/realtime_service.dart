import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class RealtimeService {
  final _client = SupabaseService.client;
  RealtimeChannel? _channel;

  Stream<List<Map<String, dynamic>>> subscribeToPlayers(String roomId) {
    return _client
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('joined_at');
  }

  Stream<List<Map<String, dynamic>>> subscribeToRoom(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId);
  }

  Stream<List<Map<String, dynamic>>> subscribeToGameSession(String roomId) {
    return _client
        .from('game_sessions')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId);
  }

  void dispose() {
    _channel?.unsubscribe();
  }
}
