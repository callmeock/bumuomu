import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../analytics/analytics_constants.dart';
import '../services/admin_config.dart';
import '../services/analytics_helper.dart';
import '../services/notification_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'admin_review_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _LeaderboardRow {
  final String name;
  final int totalVotes;
  const _LeaderboardRow(this.name, this.totalVotes);
}

class _ProfilePageState extends State<ProfilePage> {
  User? get user => FirebaseAuth.instance.currentUser;
  int _totalVotes = 0;
  int _unlockedCategories = 0;
  int _streakCount = 0;
  bool _loading = true;
  String _displayName = '';
  bool _notificationsEnabled = true;

  List<_LeaderboardRow>? _leaderboard; // null while loading
  bool _leaderboardUnavailable = false;

  @override
  void initState() {
    super.initState();
    _displayName = user?.displayName?.trim().isNotEmpty == true
        ? (user!.displayName ?? '')
        : 'Anonim Kullanıcı';
    _loadStats();
    _loadNotificationPreference();
    _loadLeaderboard();
  }

  Future<void> _loadNotificationPreference() async {
    final enabled = await NotificationService.notificationsEnabled();
    if (!mounted) return;
    setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    await NotificationService.setNotificationsEnabled(value);
  }

  Future<void> _updateDisplayName(String newName) async {
    final u = user;
    if (u == null) return;
    final name = newName.trim();
    try {
      await u.updateDisplayName(name.isEmpty ? 'Anonim Kullanıcı' : name);
      await u.reload();
      final updated = FirebaseAuth.instance.currentUser;
      if (!mounted) return;
      setState(() {
        _displayName = updated?.displayName?.trim().isNotEmpty == true
            ? (updated!.displayName ?? '')
            : 'Anonim Kullanıcı';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İsim güncellenemedi: $e')),
      );
    }
  }

  Future<void> _loadStats() async {
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final progressDoc = await FirebaseFirestore.instance
          .collection('user_progress')
          .doc(user!.uid)
          .get();

      final unlocked = progressDoc.data()?['unlockedCategories'] as List<dynamic>?;
      _unlockedCategories = unlocked?.length ?? 0;

      _totalVotes = (progressDoc.data()?['totalVotes'] as num?)?.toInt() ?? 0;
      _streakCount = (progressDoc.data()?['streakCount'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Lightweight global leaderboard MVP (Acrodix app #5 bizdev backlog #4):
  /// entirely derived from `user_progress.totalVotes`, no friend-graph
  /// infrastructure required. Degrades gracefully — a fresh Firestore
  /// project's default security rules will likely reject this
  /// collection-wide read until rules are updated for it; that's a
  /// deliberate backend follow-up (flagged separately), not something this
  /// screen should crash or silently omit-explain over.
  Future<void> _loadLeaderboard() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_progress')
          .orderBy('totalVotes', descending: true)
          .limit(10)
          .get();
      if (!mounted) return;
      setState(() {
        _leaderboard = snap.docs
            .map((d) => _LeaderboardRow(
                  d.id.substring(0, d.id.length.clamp(0, 6)),
                  (d.data()['totalVotes'] as num?)?.toInt() ?? 0,
                ))
            .where((r) => r.totalVotes > 0)
            .toList();
      });
    } catch (e) {
      debugPrint('❌ Liderlik tablosu yüklenemedi (muhtemelen güvenlik kuralları): $e');
      if (!mounted) return;
      setState(() {
        _leaderboardUnavailable = true;
        _leaderboard = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIdentityCard(),
                  const SizedBox(height: AppSpacing.lg),
                  const _PremiumCard(),
                  const SizedBox(height: AppSpacing.xxl),
                  const Text('İstatistikler', style: _sectionTitleStyle),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          emoji: '🏆',
                          label: 'Açık Kategoriler',
                          value: '$_unlockedCategories',
                          color: AppColors.violet,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatCard(
                          emoji: '🗳️',
                          label: 'Toplam Oy',
                          value: '$_totalVotes',
                          color: AppColors.mint,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _StatCard(
                          emoji: '🔥',
                          label: 'Gün Serisi',
                          value: '$_streakCount',
                          color: AppColors.yellow,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const Text('Liderlik Tablosu', style: _sectionTitleStyle),
                  const SizedBox(height: AppSpacing.md),
                  _buildLeaderboard(),
                  const SizedBox(height: AppSpacing.xxl),
                  const Text('Ayarlar', style: _sectionTitleStyle),
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: SwitchListTile(
                      secondary: const Icon(Icons.notifications, color: AppColors.yellow),
                      title: const Text('Bildirimler'),
                      subtitle: Text(
                        _notificationsEnabled
                            ? 'Uygulama açıkken bildirimler gösteriliyor'
                            : 'Uygulama açıkken bildirimler gizli',
                        style: const TextStyle(color: AppColors.mist),
                      ),
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                    ),
                  ),
                  _SettingsTile(
                    icon: Icons.info,
                    title: 'Hakkında',
                    subtitle: 'Uygulama bilgileri',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Bu mu O mu?',
                        applicationVersion: '1.2.0',
                        applicationLegalese: '© 2025',
                      );
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.refresh,
                    title: 'Verileri Yenile',
                    subtitle: 'İstatistikleri güncelle',
                    onTap: () {
                      setState(() => _loading = true);
                      _loadStats();
                      _loadLeaderboard();
                    },
                  ),
                  if (AdminConfig.isOwner(user?.uid))
                    _SettingsTile(
                      icon: Icons.fact_check,
                      title: 'Sizden Gelenler (Admin)',
                      subtitle: 'Bekleyen soruları incele',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminReviewPage()),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  static const _sectionTitleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: AppColors.cloud,
  );

  Widget _buildIdentityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: AppTheme.sideAGradient,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                (_displayName.isNotEmpty
                        ? _displayName.substring(0, 1)
                        : user?.uid.substring(0, 1) ?? 'U')
                    .toUpperCase(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.cloud,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.cloud,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: AppColors.mist),
                        onPressed: user == null ? null : _editDisplayName,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: user == null ? null : () => _copyFullUid(context, user!.uid),
                    child: Text(
                      'ID: ${user?.uid.substring(0, 8) ?? 'N/A'}... (kopyalamak için dokun)',
                      style: const TextStyle(fontSize: 12, color: AppColors.mistDim),
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

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(
        text: _displayName == 'Anonim Kullanıcı' ? '' : _displayName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.night2,
        title: const Text('Kullanıcı adı'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Adınız veya takma ad',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (result != null) {
      await _updateDisplayName(result.isEmpty ? 'Anonim Kullanıcı' : result);
    }
  }

  Future<void> _copyFullUid(BuildContext context, String uid) async {
    await Clipboard.setData(ClipboardData(text: uid));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('UID kopyalandı: $uid')),
    );
  }

  Widget _buildLeaderboard() {
    if (_leaderboard == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_leaderboardUnavailable || _leaderboard!.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: const [
              Icon(Icons.emoji_events_outlined, color: AppColors.mistDim),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Liderlik tablosu yakında burada — ilk oyları veren sen ol!',
                  style: TextStyle(color: AppColors.mist),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (int i = 0; i < _leaderboard!.length; i++)
            ListTile(
              leading: Text(
                i == 0 ? '🥇' : (i == 1 ? '🥈' : (i == 2 ? '🥉' : '${i + 1}.')),
                style: const TextStyle(fontSize: 16),
              ),
              title: Text(_leaderboard![i].name,
                  style: const TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w700)),
              trailing: Text(
                '${_leaderboard![i].totalVotes} oy',
                style: const TextStyle(color: AppColors.mint, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

class _PremiumCard extends StatefulWidget {
  const _PremiumCard();

  @override
  State<_PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<_PremiumCard> {
  bool _paywallShownLogged = false;

  Future<void> _buy(BuildContext context) async {
    try {
      await SubscriptionService.buyWeekly();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Satın alma başlatılamadı: $e')),
      );
    }
  }

  Future<void> _restore(BuildContext context) async {
    try {
      await SubscriptionService.restore();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Satın alımlar kontrol ediliyor...')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Geri yükleme başarısız: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionService.isPremiumNotifier,
      builder: (context, isPremium, _) {
        if (isPremium) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: const [
                  Icon(Icons.workspace_premium, color: AppColors.yellow),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Premium aktif — reklamsız oynuyorsun',
                      style: TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!_paywallShownLogged) {
          _paywallShownLogged = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AnalyticsHelper.paywallShown(source: AnalyticsScreenNames.profile);
          });
        }

        final product = SubscriptionService.weeklyProduct;
        final priceLabel = product?.price ?? '~20 TL';

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.workspace_premium, color: AppColors.yellow),
                    SizedBox(width: AppSpacing.sm),
                    Text('Premium',
                        style: TextStyle(
                            color: AppColors.cloud, fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Haftalık $priceLabel ile tüm reklamları kaldır.',
                  style: const TextStyle(color: AppColors.mist),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: product == null ? null : () => _buy(context),
                        child: Text(product == null ? 'Şu an kullanılamıyor' : 'Satın Al'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => _restore(context),
                      child: const Text('Geri Yükle'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.mistDim),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: AppColors.yellow),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.mist)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.mistDim),
        onTap: onTap,
      ),
    );
  }
}
