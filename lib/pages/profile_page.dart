import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? get user => FirebaseAuth.instance.currentUser;
  int _totalVotes = 0;
  int _unlockedCategories = 0;
  bool _loading = true;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _displayName = user?.displayName?.trim().isNotEmpty == true
        ? (user!.displayName ?? '')
        : 'Anonim Kullanıcı';
    _loadStats();
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
        SnackBar(content: Text('İsim güncellenemedi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _loadStats() async {
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Unlocked categories count
      final progressDoc = await FirebaseFirestore.instance
          .collection('user_progress')
          .doc(user!.uid)
          .get();

      final unlocked = progressDoc.data()?['unlockedCategories'] as List<dynamic>?;
      _unlockedCategories = unlocked?.length ?? 0;

      _totalVotes = (progressDoc.data()?['totalVotes'] as num?)?.toInt() ?? 0;

      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF3C26FF), // Sol mavi
                Color(0xFFFF0000), // Sağ kırmızı
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User info card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.orange,
                              child: Text(
                                (_displayName.isNotEmpty ? _displayName.substring(0, 1) : user?.uid.substring(0, 1) ?? 'U').toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
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
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 20),
                                        onPressed: user == null
                                            ? null
                                            : () async {
                                                final controller = TextEditingController(text: _displayName == 'Anonim Kullanıcı' ? '' : _displayName);
                                                final result = await showDialog<String>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
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
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(ctx),
                                                        child: const Text('İptal'),
                                                      ),
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
                                              },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${user?.uid.substring(0, 8) ?? 'N/A'}...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Stats section
                    const Text(
                      'İstatistikler',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.emoji_events,
                            label: 'Açık Kategoriler',
                            value: '$_unlockedCategories',
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.how_to_vote,
                            label: 'Toplam Oy',
                            value: '$_totalVotes',
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Settings section
                    const Text(
                      'Ayarlar',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SettingsTile(
                      icon: Icons.notifications,
                      title: 'Bildirimler',
                      subtitle: 'Push bildirimleri açık',
                      onTap: () {
                        // TODO: Bildirim ayarları
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.info,
                      title: 'Hakkında',
                      subtitle: 'Uygulama bilgileri',
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Bu mu O mu?',
                          applicationVersion: '1.1.6',
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
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
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
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.orange),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

