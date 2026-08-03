import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/category.dart';
import '../services/room_service.dart';
import '../theme/app_theme.dart';
import '../widgets/full_width_category_card.dart';
import '../widgets/mode_card.dart';
import 'room_lobby_page.dart';

/// Host-side room setup: pick a mode, then a category/set, then create.
class CreateRoomPage extends StatefulWidget {
  const CreateRoomPage({super.key});

  @override
  State<CreateRoomPage> createState() => _CreateRoomPageState();
}

class _CreateRoomPageState extends State<CreateRoomPage> {
  String? _mode; // 'favorin' | 'unlimited' | 'dilemma'
  bool _loadingSets = false;
  List<Category> _sets = [];
  bool _creating = false;

  Future<void> _pickMode(String mode) async {
    setState(() {
      _mode = mode;
      _loadingSets = true;
      _sets = [];
    });

    if (mode == 'unlimited') {
      // Sınırsız Mod'da kategori seçimi yok — direkt oluştur.
      await _createRoomFromUnlimited();
      return;
    }

    final type = mode == 'favorin' ? 'tournament' : 'dilemma';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('type', isEqualTo: type)
          .get();
      final sets = <Category>[];
      for (final doc in snap.docs) {
        try {
          final c = Category.fromFirestore(doc);
          if (c.items.length >= 2) sets.add(c);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _loadingSets = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSets = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategoriler yüklenemedi: $e')),
      );
    }
  }

  List<Map<String, String>> _sequentialPairs(List<String> items, {int? limit}) {
    final pairs = <Map<String, String>>[];
    final n = items.length ~/ 2;
    for (int i = 0; i < n; i++) {
      final idx = i * 2;
      if (idx + 1 < items.length) {
        pairs.add({'a': items[idx], 'b': items[idx + 1]});
      }
      if (limit != null && pairs.length >= limit) break;
    }
    return pairs;
  }

  Future<void> _createRoomFromUnlimited() async {
    setState(() => _creating = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('unlimited_questions')
          .where('active', isEqualTo: true)
          .get();
      final all = snap.docs.toList()..shuffle(Random());
      final batch = all.take(20).toList();
      final pairs = batch.map((d) {
        final m = d.data();
        return {
          'a': (m['optionA'] ?? '').toString(),
          'b': (m['optionB'] ?? '').toString(),
          'imageA': (m['imageA'] ?? '').toString(),
          'imageB': (m['imageB'] ?? '').toString(),
        };
      }).where((p) => p['a']!.isNotEmpty && p['b']!.isNotEmpty).toList();

      if (pairs.isEmpty) throw Exception('Sınırsız Mod soruları bulunamadı.');

      await _createAndEnter(
        gameMode: 'unlimited',
        categoryKey: 'unlimited',
        categoryName: 'Sınırsız Mod',
        pairs: pairs,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Oda oluşturulamadı: $e')),
      );
    }
  }

  Future<void> _pickSet(Category c) async {
    setState(() => _creating = true);
    // Favorini Bul odada tam 32→1 bracket değil, ilk 16 eşleşmeyi sırayla
    // oynatır (bkz. RoomService doc yorumu — tam bracket-in-room ayrı bir
    // state machine gerektiriyor, sonraki iterasyona bırakıldı).
    final limit = _mode == 'favorin' ? 16 : null;
    var pairs = _sequentialPairs(c.items, limit: limit);
    if (pairs.isEmpty) {
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu sette yeterli öğe yok.')),
      );
      return;
    }

    // Favorini Bul: item adları görsel taşımıyor, gerçek görseller
    // `descriptions` koleksiyonunda (bkz. TournamentPage._loadDescriptions).
    // Bu lookup yapılmazsa oda ekranında görseller boş kalır.
    if (_mode == 'favorin') {
      try {
        final descSnap = await FirebaseFirestore.instance.collection('descriptions').get();
        final descByName = {for (final d in descSnap.docs) d.id: d.data()};
        pairs = pairs.map((p) {
          final imageA = (descByName[p['a']]?['image'] as String?) ?? '';
          final imageB = (descByName[p['b']]?['image'] as String?) ?? '';
          return {...p, 'imageA': imageA, 'imageB': imageB};
        }).toList();
      } catch (e) {
        debugPrint('descriptions lookup failed for room pairs: $e');
      }
    }

    await _createAndEnter(
      gameMode: _mode!,
      categoryKey: c.id,
      categoryName: c.name,
      pairs: pairs,
    );
  }

  Future<void> _createAndEnter({
    required String gameMode,
    required String categoryKey,
    required String categoryName,
    required List<Map<String, String>> pairs,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final hostName = user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!
          : 'Ev Sahibi';
      final code = await RoomService.createRoom(
        gameMode: gameMode,
        categoryKey: categoryKey,
        categoryName: categoryName,
        pairs: pairs,
        hostDisplayName: hostName,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RoomLobbyPage(code: code, isCreator: true)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Oda oluşturulamadı: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Oda Kur')),
      body: _creating
          ? const Center(child: CircularProgressIndicator())
          : _mode == null
              ? _buildModePicker()
              : _buildSetPicker(),
    );
  }

  Widget _buildModePicker() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Hangi modu oynayacaksınız?',
              style: TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: AppSpacing.lg),
          ModeCard(
            emoji: '🏆',
            title: 'Favorini Bul',
            subtitle: '32\'lik turnuva — şampiyonunu seç',
            gradient: AppTheme.sideAGradient,
            onTap: () => _pickMode('favorin'),
          ),
          const SizedBox(height: AppSpacing.md),
          ModeCard(
            emoji: '♾️',
            title: 'Sınırsız Mod',
            subtitle: 'Bitmeyen sorular, anlık oy ver',
            gradient: AppTheme.sideBGradient,
            onTap: () => _pickMode('unlimited'),
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
            onTap: () => _pickMode('dilemma'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetPicker() {
    if (_loadingSets) return const Center(child: CircularProgressIndicator());
    if (_sets.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Bu modda henüz içerik yok.',
              style: TextStyle(color: AppColors.mist)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _sets.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final c = _sets[index];
        return AspectRatio(
          aspectRatio: 64 / 27,
          child: FullWidthCategoryCard(
            title: c.name,
            imageUrl: c.image,
            colorIndex: index,
            onTap: () => _pickSet(c),
          ),
        );
      },
    );
  }
}
