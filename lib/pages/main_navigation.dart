import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'solo_play_page.dart';
import 'rooms_hub_page.dart';
import 'profile_page.dart';
import '../analytics/analytics_constants.dart';
import '../services/analytics_helper.dart';
import '../services/ad_service.dart';
import '../theme/app_theme.dart';

/// Bottom nav — 3 tabs per user spec: Solo Oyna / Arkadaşlarınla Oyna /
/// Profil. Replaces the earlier 4-tab layout (Günün Quizi/Favorin/Sınırsız/
/// Profil); Günün Quizi now lives as a suggestion card inside Solo Oyna.
class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  late DateTime _tabEnteredAt;

  static const List<String> _tabNames = [
    AnalyticsScreenNames.soloHub,
    AnalyticsScreenNames.roomsHub,
    AnalyticsScreenNames.profile,
  ];

  static const List<_NavItem> _navItems = [
    _NavItem(Icons.person_outline_rounded, 'Solo'),
    _NavItem(Icons.groups_rounded, 'Odalar'),
    _NavItem(Icons.person_rounded, 'Profil'),
  ];

  final List<Widget> _pages = const [
    SoloPlayPage(),
    RoomsHubPage(),
    ProfilePage(),
  ];

  // Alt nav'da kalıcı banner reklam — kullanıcı isteği. AdService.loadBannerAd
  // artık paylaşılan static state tutmuyor (bkz. ad_service.dart), yani bu
  // banner ile Sınırsız Mod'un kendi banner'ı birbirini bozmadan bağımsız
  // yaşayabiliyor.
  BannerAd? _bannerAd;
  bool _isBannerReady = false;
  Timer? _bannerRefreshTimer;
  static const Duration _bannerRefreshInterval = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    _tabEnteredAt = DateTime.now();
    AnalyticsNavigationState.setLastTabScreen(_tabNames[0]);
    _loadBannerAd();
    _bannerRefreshTimer = Timer.periodic(_bannerRefreshInterval, (_) {
      if (mounted) _loadBannerAd();
    });
  }

  @override
  void dispose() {
    _bannerRefreshTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    AdService.loadBannerAd(
      adSize: AdSize.banner,
      onAdLoaded: (ad) {
        if (!mounted) {
          ad.dispose();
          return;
        }
        final old = _bannerAd;
        setState(() {
          _bannerAd = ad;
          _isBannerReady = true;
        });
        old?.dispose();
      },
      onAdFailedToLoad: (error) {
        debugPrint('Alt nav banner yüklenemedi: ${error.message}');
      },
    );
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    final oldName = _tabNames[_currentIndex];
    final ms = DateTime.now().difference(_tabEnteredAt).inMilliseconds;
    AnalyticsHelper.screenExit(screenName: oldName, durationMs: ms);
    setState(() {
      _currentIndex = index;
      _tabEnteredAt = DateTime.now();
    });
    final newName = _tabNames[index];
    AnalyticsNavigationState.setLastTabScreen(newName);
    AnalyticsHelper.screenView(screenName: newName, source: oldName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isBannerReady && _bannerAd != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: SizedBox(
                  width: _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.night2,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (int i = 0; i < _navItems.length; i++)
                    Expanded(
                      child: _PillNavButton(
                        item: _navItems[i],
                        isActive: i == _currentIndex,
                        onTap: () => _onTabSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillNavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _PillNavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.cloud : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 20,
                color: isActive ? AppColors.night : AppColors.mistDim,
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.night,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
