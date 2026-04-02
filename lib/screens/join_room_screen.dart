import 'package:flutter/material.dart';
import '../services/room_service.dart';
import '../utils/responsive_utils.dart';
import 'waiting_room_screen.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isJoining = false;

  Future<void> _joinRoom() async {
    if (_codeController.text.length != 6 || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入6位房间号和昵称')),
      );
      return;
    }

    setState(() => _isJoining = true);
    try {
      final room = await RoomService().getRoomByCode(_codeController.text);
      if (room == null) {
        throw Exception('房间不存在');
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingRoomScreen(
              room: room,
              isHost: false,
              playerName: _nameController.text,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加入失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('加入房间')),
      body: SafeArea(
        child: Padding(
          padding: ResponsiveUtils.getResponsivePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: '房间号',
                  hintText: '输入6位房间号',
                ),
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '昵称',
                  hintText: '输入你的昵称',
                ),
                maxLength: 20,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isJoining ? null : _joinRoom,
                  child: _isJoining
                      ? const CircularProgressIndicator()
                      : const Text('加入房间'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
