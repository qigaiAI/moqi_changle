import 'dart:async';
import 'package:flutter/material.dart';
import '../models/player.dart';
import '../models/room.dart';
import '../utils/responsive_utils.dart';
import '../config/app_theme.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'waiting_room_screen.dart';

class ResultScreen extends StatefulWidget {
  final List<Player> players;
  final String gameMode;
  final Room room;
  final Player currentPlayer;

  const ResultScreen({
    super.key,
    required this.players,
    required this.gameMode,
    required this.room,
    required this.currentPlayer,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _resetting = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // 非房主轮询房间状态，等待房主点"再来一局"后自动跳转
    if (!widget.currentPlayer.isHost) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted) return;
        final data = await SupabaseService.client
            .from('rooms')
            .select('status')
            .eq('id', widget.room.id)
            .single();
        if (data['status'] == 'waiting' && mounted) {
          _pollTimer?.cancel();
          _goToWaiting();
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _playAgain() async {
    setState(() => _resetting = true);
    try {
      // 重置所有在线玩家分数
      await SupabaseService.client
          .from('players')
          .update({'score': 0})
          .eq('room_id', widget.room.id)
          .isFilter('left_at', null);
      // 重置房间状态
      await SupabaseService.client
          .from('rooms')
          .update({'status': 'waiting'})
          .eq('id', widget.room.id);
      if (mounted) _goToWaiting();
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  void _goToWaiting() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => WaitingRoomScreen(
          room: widget.room,
          isHost: widget.currentPlayer.isHost,
          existingPlayer: widget.currentPlayer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);
    final sorted = [...widget.players]..sort((a, b) => b.score.compareTo(a.score));

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: ResponsiveUtils.getResponsivePadding(context),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Text('游戏结束！', style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 8),
                Text(
                  widget.gameMode == 'quiz' ? '默契问答' : '你画我猜',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                if (sorted.isNotEmpty) _buildPodium(context, sorted),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.builder(
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final player = sorted[index];
                      final isTop3 = index < 3;
                      final medals = ['🥇', '🥈', '🥉'];
                      return Card(
                        color: isTop3 ? AppTheme.primary.withOpacity(0.2) : null,
                        child: ListTile(
                          leading: Text(
                            index < 3 ? medals[index] : '${index + 1}',
                            style: const TextStyle(fontSize: 24),
                          ),
                          title: Text(
                            player.name,
                            style: TextStyle(
                              fontWeight: isTop3 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: Text(
                            '${player.score} 分',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: isTop3 ? AppTheme.primary : null,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // 再来一局（房主主动，非房主等待）
                if (widget.currentPlayer.isHost)
                  SizedBox(
                    width: isTablet ? 400 : double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _resetting ? null : _playAgain,
                      icon: _resetting
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.replay),
                      label: Text(_resetting ? '准备中...' : '再来一局'),
                    ),
                  )
                else
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('等待房主再来一局...'),
                    ],
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: isTablet ? 400 : double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      _pollTimer?.cancel();
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text('返回主页'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPodium(BuildContext context, List<Player> sorted) {
    final first = sorted.isNotEmpty ? sorted[0] : null;
    final second = sorted.length > 1 ? sorted[1] : null;
    final third = sorted.length > 2 ? sorted[2] : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (second != null)
          _PodiumItem(player: second, height: 80, medal: '🥈', color: Colors.grey[400]!),
        const SizedBox(width: 8),
        if (first != null)
          _PodiumItem(player: first, height: 110, medal: '🥇', color: Colors.amber),
        const SizedBox(width: 8),
        if (third != null)
          _PodiumItem(player: third, height: 60, medal: '🥉', color: Colors.brown[300]!),
      ],
    );
  }
}

class _PodiumItem extends StatelessWidget {
  final Player player;
  final double height;
  final String medal;
  final Color color;

  const _PodiumItem({
    required this.player,
    required this.height,
    required this.medal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(medal, style: const TextStyle(fontSize: 32)),
        const SizedBox(height: 4),
        Text(player.name,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Container(
          width: 80,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Text('${player.score}',
              style: Theme.of(context).textTheme.titleLarge),
        ),
      ],
    );
  }
}
