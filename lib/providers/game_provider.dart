import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_session.dart';
import '../services/realtime_service.dart';
import '../services/game_service.dart';

// 游戏会话（实时）
final gameSessionStreamProvider = StreamProvider.family<GameSession?, String>((ref, roomId) {
  final service = RealtimeService();
  ref.onDispose(service.dispose);
  return service.subscribeToGameSession(roomId).map(
        (list) => list.isNotEmpty ? GameSession.fromJson(list.first) : null,
      );
});

// 游戏服务实例
final gameServiceProvider = Provider<GameService>((ref) => GameService());
