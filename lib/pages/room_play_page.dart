import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../analytics/analytics_constants.dart';
import '../services/ad_service.dart';
import '../services/room_service.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_ad_slot.dart';
import '../widgets/room_avatar_row.dart';

/// Host-paced, real-time synced play screen. Every client renders the same
/// `currentIndex` from the room doc; votes are room-scoped (not the global
/// VoteService counters used by solo modes — "kendi aralarındaki oylamaları
/// görmeleri gerekiyor" was explicit in the brief).
///
/// Round pacing is fully automatic (clarified with the user): each round gets
/// a `roundDeadline` (set by RoomService.startRoom/advanceRound), everyone can
/// vote/re-vote until it passes, and the host's client auto-advances when it
/// hits zero — no manual "İleri" button.
class RoomPlayPage extends StatefulWidget {
  final String code;
  const RoomPlayPage({super.key, required this.code});

  @override
  State<RoomPlayPage> createState() => _RoomPlayPageState();
}

class _RoomPlayPageState extends State<RoomPlayPage> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Timer? _ticker;
  int? _advancedForIndex;
  bool _endAdTriggered = false;

  @override
  void initState() {
    super.initState();
    // Cheap 1s rebuild tick to recompute the countdown display and check
    // deadline expiry — actual timing authority is roundDeadline on the room
    // doc, this is just what drives the local re-render.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _leave() async {
    await RoomService.leaveRoom(widget.code);
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder(
        stream: RoomService.roomStream(widget.code),
        builder: (context, roomSnap) {
          if (!roomSnap.hasData || !(roomSnap.data!.exists)) {
            return const Center(child: CircularProgressIndicator());
          }
          final room = roomSnap.data!.data() as Map<String, dynamic>;
          final status = room['status'] as String? ?? 'playing';
          if (status == 'finished') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).popUntil((r) => r.isFirst);
            });
            return const Center(child: CircularProgressIndicator());
          }

          final pairsRaw = room['pairs'] as List<dynamic>? ?? [];
          final pairs = pairsRaw
              .map((p) => Map<String, String>.from(p as Map))
              .toList();
          final currentIndex = (room['currentIndex'] as num?)?.toInt() ?? 0;
          final isHost = room['hostUid'] == _uid;
          final categoryName = room['categoryName'] as String? ?? '';
          final deadline = (room['roundDeadline'] as Timestamp?)?.toDate();
          final remaining = deadline == null
              ? Duration.zero
              : deadline.difference(DateTime.now());
          final remainingSeconds = remaining.isNegative ? 0 : remaining.inSeconds + 1;
          final locked = deadline == null || remaining.isNegative;

          if (currentIndex >= pairs.length) {
            if (!_endAdTriggered) {
              _endAdTriggered = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                AdService.showRewardedInterstitialAd(
                  placement: AnalyticsAdPlacement.roomComplete,
                );
              });
            }
            return _EndScreen(
              code: widget.code,
              isHost: isHost,
              onFinish: () => RoomService.finishRoom(widget.code),
            );
          }

          if (isHost && locked && _advancedForIndex != currentIndex) {
            _advancedForIndex = currentIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              RoomService.advanceRound(widget.code, currentIndex + 1);
            });
          }

          final pair = pairs[currentIndex];

          return SafeArea(
            child: StreamBuilder(
              stream: RoomService.participantsStream(widget.code),
              builder: (context, pSnap) {
                final names = <String, String>{};
                if (pSnap.hasData) {
                  for (final d in pSnap.data!.docs) {
                    final m = d.data();
                    names[m['uid'] as String? ?? d.id] = m['displayName'] as String? ?? '?';
                  }
                }
                return StreamBuilder<Map<String, String>>(
                  stream: RoomService.roundChoicesStream(widget.code, currentIndex),
                  builder: (context, choiceSnap) {
                    final choices = choiceSnap.data ?? const {};
                    final myChoice = choices[_uid];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: _leave,
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: const BoxDecoration(
                                    color: AppColors.night2,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.close, size: 18, color: AppColors.cloud),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.night2,
                                  borderRadius: BorderRadius.circular(AppRadii.pill),
                                ),
                                child: Text('#${widget.code} · $categoryName',
                                    style: const TextStyle(
                                      color: AppColors.cloud,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    )),
                              ),
                              const Spacer(),
                              Text('${currentIndex + 1} / ${pairs.length}',
                                  style: const TextStyle(
                                    color: AppColors.mist,
                                    fontWeight: FontWeight.w800,
                                  )),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _RoomChoiceCard(
                                    label: pair['a'] ?? '',
                                    imageUrl: pair['imageA'] ?? '',
                                    accent: AppColors.violet,
                                    isSelected: myChoice == 'a',
                                    dimmed: myChoice != null && myChoice != 'a',
                                    onTap: locked
                                        ? null
                                        : () => RoomService.vote(widget.code, currentIndex, 'a'),
                                  ),
                                  _RoomChoiceCard(
                                    label: pair['b'] ?? '',
                                    imageUrl: pair['imageB'] ?? '',
                                    accent: AppColors.coral,
                                    isSelected: myChoice == 'b',
                                    dimmed: myChoice != null && myChoice != 'b',
                                    onTap: locked
                                        ? null
                                        : () => RoomService.vote(widget.code, currentIndex, 'b'),
                                  ),
                                ],
                              ),
                              RoomAvatarRow(names: names, choices: choices, selfUid: _uid),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: locked ? AppColors.night2 : AppColors.yellow,
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Text(
                                locked ? 'Sıradaki soruya geçiliyor…' : '⏱ $remainingSeconds sn',
                                style: TextStyle(
                                  color: locked ? AppColors.mist : const Color(0xFF3B2400),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RoomChoiceCard extends StatelessWidget {
  final String label;
  final String imageUrl;
  final Color accent;
  final bool isSelected;
  final bool dimmed;
  final VoidCallback? onTap;

  const _RoomChoiceCard({
    required this.label,
    required this.imageUrl,
    required this.accent,
    required this.isSelected,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.28,
            width: double.infinity,
            color: AppColors.night2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const ColoredBox(color: AppColors.night2),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                    ),
                  ),
                ),
                if (dimmed) Container(color: Colors.black.withValues(alpha: 0.45)),
                Positioned(
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  child: Container(
                    width: 6,
                    height: 24,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.cloud,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    bottom: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.mint,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 14, color: Color(0xFF0B3B2C)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndScreen extends StatelessWidget {
  final String code;
  final bool isHost;
  final VoidCallback onFinish;

  const _EndScreen({required this.code, required this.isHost, required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  const Text('Oda tamamlandı!',
                      style: TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w900, fontSize: 20)),
                  const SizedBox(height: 24),
                  if (isHost)
                    ElevatedButton(onPressed: onFinish, child: const Text('Odayı Kapat'))
                  else
                    const Text('Ev sahibinin odayı kapatmasını bekliyorsun...',
                        style: TextStyle(color: AppColors.mist)),
                ],
              ),
            ),
          ),
        ),
        const BannerAdSlot(),
      ],
    );
  }
}
