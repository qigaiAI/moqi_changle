import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room.dart';
import '../models/player.dart';
import '../services/room_service.dart';
import '../services/supabase_service.dart';
import '../utils/responsive_utils.dart';
import 'quiz_game_screen.dart';
import 'draw_game_screen.dart';

class WaitingRoomScreen extends ConsumerStatefulWidget {
  final Room room;
  final bool isHost;
  final String? playerName;
  final Player? existingPlayer; // 再来一局时传入，跳过 joinRoom

  const WaitingRoomScreen({
    super.key,
    required this.room,
    required this.isHost,
    this.playerName,
    this.existingPlayer,
  });

  @override
  ConsumerState<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends ConsumerState<WaitingRoomScreen> {
  final _roomService = RoomService();
  Player? _currentPlayer;
  List<Player> _players = [];
  bool _joining = true;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _joinAndSubscribe();
  }

  bool _navigating = false; // 防止重复跳转

  Future<void> _joinAndSubscribe() async {
    if (widget.existingPlayer != null) {
      // 再来一局：直接使用已有玩家记录，不重新 join
      if (mounted) setState(() { _currentPlayer = widget.existingPlayer!; _joining = false; });
    } else {
      try {
        final player = await _roomService.joinRoom(
          roomId: widget.room.id,
          playerName: widget.playerName ?? '房主',
          isHost: widget.isHost,
        );
        if (mounted) setState(() { _currentPlayer = player; _joining = false; });
      } catch (e) {
        if (mounted) {
          setState(() => _joining = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加入房间失败: $e')),
          );
        }
      }
    }

    // 先拉一次
    await _fetchPlayersAndCheckStatus();

    // Realtime 订阅 players + rooms 表变化
    SupabaseService.client
        .channel('room-${widget.room.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.room.id,
          ),
          callback: (_) => _fetchPlayersAndCheckStatus(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.room.id,
          ),
          callback: (_) => _fetchPlayersAndCheckStatus(),
        )
        .subscribe();

    // 轮询兜底（每2秒），同时检查房间状态和玩家列表
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _fetchPlayersAndCheckStatus());
  }

  Future<void> _fetchPlayersAndCheckStatus() async {
    if (!mounted || _navigating) return;

    // 同时获取房间状态和玩家列表
    final results = await Future.wait([
      SupabaseService.client
          .from('rooms')
          .select('status, game_mode')
          .eq('id', widget.room.id)
          .single(),
      SupabaseService.client
          .from('players')
          .select()
          .eq('room_id', widget.room.id)
          .isFilter('left_at', null)
          .order('joined_at'),
    ]);

    if (!mounted || _navigating) return;

    final roomData = results[0] as Map<String, dynamic>;
    final playersData = results[1] as List;
    final players = playersData.map((e) => Player.fromJson(e)).toList();

    setState(() => _players = players);

    // 房间状态变为 playing → 所有玩家跳转游戏
    if (roomData['status'] == 'playing' && _currentPlayer != null) {
      _navigateToGame(players);
    }
  }

  void _navigateToGame(List<Player> players) {
    if (_navigating || !mounted) return;
    setState(() => _navigating = true);
    _pollTimer?.cancel();

    final screen = widget.room.gameMode == 'quiz'
        ? QuizGameScreen(
            room: widget.room,
            currentPlayer: _currentPlayer!,
            allPlayers: players,
          )
        : DrawGameScreen(
            room: widget.room,
            currentPlayer: _currentPlayer!,
            allPlayers: players,
          );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    SupabaseService.client.channel('room-${widget.room.id}').unsubscribe();
    // 只有不是跳转到游戏时才标记离开（跳转游戏不算真的离开）
    if (_currentPlayer != null && !_navigating) {
      _roomService.leaveRoom(_currentPlayer!.id);
    }
    super.dispose();
  }

  Future<void> _startGame() async {
    if (_currentPlayer == null || _navigating) return;
    // 更新房间状态为 playing，其他人的轮询会检测到并自动跳转
    await _roomService.updateRoomStatus(widget.room.id, 'playing');
    // 房主自己也通过 _fetchPlayersAndCheckStatus 跳转，保持统一逻辑
    await _fetchPlayersAndCheckStatus();
  }

  void _copyRoomCode() {
    try {
      Clipboard.setData(ClipboardData(text: widget.room.code));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间号已复制')),
      );
    } catch (_) {
      // Web HTTP 环境下剪贴板可能不可用
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('房间号: ${widget.room.code}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('等待房间'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: ResponsiveUtils.getResponsivePadding(context),
            child: Column(
              children: [
                // 房间号卡片
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('房间号', style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(height: 4),
                              Text(
                                widget.room.code,
                                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                  letterSpacing: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: _copyRoomCode,
                          tooltip: '复制房间号',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 游戏模式标签
                Row(
                  children: [
                    Chip(
                      label: Text(widget.room.gameMode == 'quiz' ? '默契问答' : '你画我猜'),
                      avatar: Icon(
                        widget.room.gameMode == 'quiz' ? Icons.quiz : Icons.brush,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Chip(label: Text('${widget.room.maxPlayers}人')),
                  ],
                ),
                const SizedBox(height: 16),
                // 玩家列表标题
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '玩家列表 (${_players.length}/${widget.room.maxPlayers})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_joining)
                      const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // 玩家网格
                Expanded(
                  child: _players.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.people_outline, size: 48, color: Colors.grey),
                              const SizedBox(height: 8),
                              Text(
                                _joining ? '正在加入...' : '等待玩家加入',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isTablet ? 4 : 2,
                            childAspectRatio: 2.5,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _players.length,
                          itemBuilder: (context, index) {
                            final player = _players[index];
                            final isMe = player.id == _currentPlayer?.id;
                            return Card(
                              color: isMe
                                  ? Theme.of(context).colorScheme.primary.withAlpha(40)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(
                                      player.isHost ? Icons.star : Icons.person,
                                      color: player.isHost
                                          ? Colors.amber
                                          : Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            player.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: isMe ? FontWeight.bold : null,
                                            ),
                                          ),
                                          if (isMe)
                                            const Text('(我)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                // 开始/等待按钮
                if (widget.isHost) ...[
                  if (_players.length < 2)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('至少需要2名玩家才能开始', style: TextStyle(color: Colors.grey)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _players.length >= 2 ? _startGame : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始游戏'),
                    ),
                  ),
                ] else
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('等待房主开始游戏...'),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
