import 'package:flutter/material.dart';
import '../utils/responsive_utils.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveUtils.isTablet(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: ResponsiveUtils.getResponsivePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.games,
                size: isTablet ? 120 : 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                '默契挑战',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: isTablet ? 48 : 36,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: isTablet ? 400 : double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
                  ),
                  child: const Text('创建房间'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: isTablet ? 400 : double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JoinRoomScreen()),
                  ),
                  child: const Text('加入房间'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
