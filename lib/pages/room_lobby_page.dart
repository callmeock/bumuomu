import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/room_service.dart';
import '../services/share_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad_slot.dart';
import 'room_play_page.dart';

class RoomLobbyPage extends StatefulWidget {
  final String code;
  final bool isCreator;

  const RoomLobbyPage({super.key, required this.code, required this.isCreator});

  @override
  State<RoomLobbyPage> createState() => _RoomLobbyPageState();
}

class _RoomLobbyPageState extends State<RoomLobbyPage> {
  bool _joined = false;
  bool _joinError = false;
  bool _navigatedToPlay = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.isCreator) {
      _joined = true;
    } else {
      _joinAsGuest();
    }
  }

  Future<void> _joinAsGuest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final name = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!
          : 'Misafir';
      await RoomService.joinRoom(widget.code, displayName: name);
      if (!mounted) return;
      setState(() => _joined = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _joinError = true);
    }
  }

  Future<void> _leave() async {
    await RoomService.leaveRoom(widget.code);
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (_joinError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Odaya Katıl')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Bu kodla bir oda bulunamadı.', style: TextStyle(color: AppColors.mist)),
          ),
        ),
      );
    }
    if (!_joined) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) RoomService.leaveRoom(widget.code);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Oda Lobisi'),
          actions: [
            TextButton(
              onPressed: _leave,
              child: const Text('Ayrıl', style: TextStyle(color: AppColors.coral)),
            ),
          ],
        ),
        body: StreamBuilder(
          stream: RoomService.roomStream(widget.code),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !(snapshot.data!.exists)) {
              return const Center(child: CircularProgressIndicator());
            }
            final room = snapshot.data!.data() as Map<String, dynamic>;
            final status = room['status'] as String? ?? 'lobby';
            final isHost = room['hostUid'] == _uid;
            final categoryName = room['categoryName'] as String? ?? '';

            if (status == 'playing' && !_navigatedToPlay) {
              _navigatedToPlay = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoomPlayPage(code: widget.code),
                  ),
                );
              });
            }
            if (status == 'finished') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.of(context).popUntil((r) => r.isFirst);
              });
            }

            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    decoration: BoxDecoration(
                      color: AppColors.night2,
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                    ),
                    child: Column(
                      children: [
                        const Text('ODA KODU',
                            style: TextStyle(color: AppColors.mist, fontSize: 12, letterSpacing: 2)),
                        const SizedBox(height: AppSpacing.sm),
                        Text(widget.code,
                            style: const TextStyle(
                              color: AppColors.yellow,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                            )),
                        const SizedBox(height: AppSpacing.sm),
                        Text(categoryName,
                            style: const TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w700)),
                        const SizedBox(height: AppSpacing.lg),
                        OutlinedButton.icon(
                          onPressed: () => ShareHelper.shareRoomInvite(
                            context,
                            code: widget.code,
                            categoryName: categoryName,
                          ),
                          icon: const Icon(Icons.share, size: 18),
                          label: const Text('Arkadaşlarını Davet Et'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.cloud,
                            side: const BorderSide(color: AppColors.cloud),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text('Katılımcılar',
                      style: TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: StreamBuilder(
                      stream: RoomService.participantsStream(widget.code),
                      builder: (context, pSnap) {
                        if (!pSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = pSnap.data!.docs;
                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final d = docs[i].data();
                            final name = d['displayName'] as String? ?? '?';
                            final uid = d['uid'] as String? ?? '';
                            final isThisHost = uid == room['hostUid'];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.violet,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: AppColors.cloud),
                                ),
                              ),
                              title: Text(name, style: const TextStyle(color: AppColors.cloud)),
                              trailing: isThisHost
                                  ? const Text('👑', style: TextStyle(fontSize: 16))
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (isHost)
                    ElevatedButton(
                      onPressed: () => RoomService.startRoom(widget.code),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Başlat'),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text('Ev sahibinin başlatmasını bekliyorsun...',
                            style: TextStyle(color: AppColors.mist)),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  const BannerAdSlot(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
