import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/room_service.dart';
import '../config/app_config.dart';
import '../utils/responsive_utils.dart';
import 'waiting_room_screen.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  String _gameMode = 'quiz';
  int _maxPlayers = 6;
  int _rounds = 3;
  int _drawingTime = 80;
  bool _isCreating = false;
  final _nameController = TextEditingController(text: '房主');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    setState(() => _isCreating = true);
    try {
      final room = await RoomService().createRoom(
        gameMode: _gameMode,
        maxPlayers: _maxPlayers,
        rounds: _rounds,
        drawingTime: _drawingTime,
      );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingRoomScreen(
                    room: room,
                    isHost: true,
                    playerName: _nameController.text.trim().isEmpty
                        ? '房主'
                        : _nameController.text.trim(),
                  ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建房间失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建房间')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ResponsiveUtils.getResponsivePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('我的昵称', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: '输入你的昵称'),
                maxLength: 20,
              ),
              const SizedBox(height: 16),
              Text('游戏模式', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'quiz', label: Text('默契问答')),
                  ButtonSegment(value: 'draw', label: Text('你画我猜')),
                ],
                selected: {_gameMode},
                onSelectionChanged: (v) => setState(() => _gameMode = v.first),
              ),
              const SizedBox(height: 24),
              Text('最大人数: $_maxPlayers', style: Theme.of(context).textTheme.titleLarge),
              Slider(
                value: _maxPlayers.toDouble(),
                min: AppConfig.minPlayers.toDouble(),
                max: AppConfig.maxPlayers.toDouble(),
                divisions: AppConfig.maxPlayers - AppConfig.minPlayers,
                onChanged: (v) => setState(() => _maxPlayers = v.toInt()),
              ),
              const SizedBox(height: 24),
              if (_gameMode == 'quiz') ...[
                Text('轮次数: $_rounds', style: Theme.of(context).textTheme.titleLarge),
                Slider(
                  value: _rounds.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) => setState(() => _rounds = v.toInt()),
                ),
              ] else ...[
                Text('作画时间: $_drawingTime 秒', style: Theme.of(context).textTheme.titleLarge),
                Slider(
                  value: _drawingTime.toDouble(),
                  min: 30,
                  max: 120,
                  divisions: 9,
                  onChanged: (v) => setState(() => _drawingTime = v.toInt()),
                ),
              ],
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating ? null : _createRoom,
                  child: _isCreating
                      ? const CircularProgressIndicator()
                      : const Text('创建房间'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
