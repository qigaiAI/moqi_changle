import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../services/realtime_service.dart';

// 当前玩家
final currentPlayerProvider = StateProvider<Player?>((ref) => null);

// 当前房间
final currentRoomProvider = StateProvider<Room?>((ref) => null);

// 房间内玩家列表（实时）
final playersStreamProvider = StreamProvider.family<List<Player>, String>((ref, roomId) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service.subscribeToPlayers(roomId).map(
        (list) => list.map((e) => Player.fromJson(e)).where((p) => p.isActive).toList(),
      );
});

// 房间状态（实时）
final roomStreamProvider = StreamProvider.family<Room?, String>((ref, roomId) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service.subscribeToRoom(roomId).map(
        (list) => list.isNotEmpty ? Room.fromJson(list.first) : null,
      );
});
