import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../analytics/analytics_constants.dart';
import '../services/analytics_helper.dart';
import '../theme/app_theme.dart';
import '../unlimited_mode.dart';
import '../widgets/mode_card.dart';
import 'daily_quiz_page.dart';
import 'favorin_hangisi_page.dart';
import 'sadece_soru_page.dart';
import 'sizden_gelenler_page.dart';

/// Solo Oyna hub — 3-tab bottom nav'ın ilk sekmesi. Kullanıcı isteği üzerine
/// Günün Quizi artık ayrı bir tab değil, buradaki "Bugünün Önerisi" kartı
/// (aynı DailyQuizPage'e yönlendiriyor, mantık aynı) + üç solo mod seçeneği:
/// Favorini Bul, Sınırsız Mod, Sadece Soru.
class SoloPlayPage extends StatefulWidget {
  const SoloPlayPage({super.key});

  @override
  State<SoloPlayPage> createState() => _SoloPlayPageState();
}

class _SoloPlayPageState extends State<SoloPlayPage> {
  int _streakCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('user_progress')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      setState(() {
        _streakCount = (doc.data()?['streakCount'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  void _openDaily() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.home),
        builder: (_) => const DailyQuizPage(),
      ),
    );
  }

  void _openFavorin() {
    AnalyticsHelper.screenView(
      screenName: AnalyticsScreenNames.favorin,
      source: AnalyticsScreenNames.soloHub,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.favorin),
        builder: (_) => const FavorinHangisiPage(),
      ),
    );
  }

  void _openUnlimited() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.unlimited),
        builder: (_) => const UnlimitedModePage(analyticsSource: 'solo_hub'),
      ),
    );
  }

  void _openDilemma() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.dilemma),
        builder: (_) => const SadeceSoruPage(),
      ),
    );
  }

  void _openSizdenGelenler() {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.sizdenGelenler),
        builder: (_) => const SizdenGelenlerPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Solo Oyna',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.cloud,
                      ),
                    ),
                  ),
                  if (_streakCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.yellow,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        '🔥 $_streakCount',
                        style: const TextStyle(
                          color: Color(0xFF3B2400),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _DailySuggestionCard(onTap: _openDaily),
              const SizedBox(height: AppSpacing.xxl),
              const Text(
                'Bir mod seç',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cloud,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ModeCard(
                emoji: '🏆',
                title: 'Favorini Bul',
                subtitle: '32\'lik turnuva — şampiyonunu seç',
                gradient: AppTheme.sideAGradient,
                onTap: _openFavorin,
              ),
              const SizedBox(height: AppSpacing.md),
              ModeCard(
                emoji: '♾️',
                title: 'Sınırsız Mod',
                subtitle: 'Bitmeyen sorular, anlık oy ver',
                gradient: AppTheme.sideBGradient,
                onTap: _openUnlimited,
              ),
              const SizedBox(height: AppSpacing.md),
              ModeCard(
                emoji: '💭',
                title: 'Sadece Soru',
                subtitle: '"Hayatın boyunca sadece..." ikilemleri',
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFD766), Color(0xFFE8A93A)],
                ),
                foreground: const Color(0xFF3B2400),
                onTap: _openDilemma,
              ),
              const SizedBox(height: AppSpacing.md),
              ModeCard(
                emoji: '🙋',
                title: 'Sizden Gelenler',
                subtitle: 'Kendi sorunu gönder, başkalarınınkileri oyna',
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2DBE8F), Color(0xFF15805C)],
                ),
                onTap: _openSizdenGelenler,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailySuggestionCard extends StatelessWidget {
  final VoidCallback onTap;
  const _DailySuggestionCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.violet, Color(0xFF4C1D95)],
          ),
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('📅 Bugünün Önerisi',
                      style: TextStyle(
                        color: AppColors.mist,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      )),
                  SizedBox(height: 6),
                  Text(
                    'Günün Quizi',
                    style: TextStyle(
                      color: AppColors.cloud,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.yellow,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: const Text(
                'Başla →',
                style: TextStyle(
                  color: Color(0xFF3B2400),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

