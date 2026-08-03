import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'create_room_page.dart';
import 'room_lobby_page.dart';

/// "Arkadaşlarınla Oyna" tab entry — Oda Kur / Odaya Katıl.
class RoomsHubPage extends StatefulWidget {
  const RoomsHubPage({super.key});

  @override
  State<RoomsHubPage> createState() => _RoomsHubPageState();
}

class _RoomsHubPageState extends State<RoomsHubPage> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _createRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateRoomPage()),
    );
  }

  void _joinRoom() {
    final code = _codeController.text.trim();
    if (code.length != 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('5 haneli oda kodunu gir.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomLobbyPage(code: code, isCreator: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Arkadaşlarınla Oyna',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.cloud,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Bir oda kur ya da arkadaşının kodunu gir, aynı anda oyna.',
                style: TextStyle(color: AppColors.mist),
              ),
              const SizedBox(height: AppSpacing.xxl),
              GestureDetector(
                onTap: _createRoom,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    gradient: AppTheme.sideAGradient,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: Row(
                    children: [
                      const Text('🎉', style: TextStyle(fontSize: 30)),
                      const SizedBox(width: AppSpacing.md),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Oda Kur',
                                style: TextStyle(
                                    color: AppColors.cloud,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16)),
                            SizedBox(height: 2),
                            Text('Bir mod seç, arkadaşlarını davet et',
                                style: TextStyle(color: AppColors.mist, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.mist),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const Text(
                'Odaya Katıl',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cloud,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 5,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.cloud,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: 6,
                      ),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '00000',
                        hintStyle: TextStyle(color: AppColors.mistDim, letterSpacing: 6),
                        filled: true,
                        fillColor: AppColors.night2,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(AppRadii.md)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  ElevatedButton(
                    onPressed: _joinRoom,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('Katıl'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
