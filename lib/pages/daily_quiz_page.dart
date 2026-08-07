import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import '../analytics/analytics_constants.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
import '../utils/image_url.dart';
import 'quiz_page.dart';
import 'test_page.dart';

/// Günün Quizi sayfası - Günlük quiz kategorisi; yoksa Favorin Hangisi'nden rastgele biri
///
/// Artık kilitli değil (kullanıcı isteği: reklam bir kategori/oyun bitince
/// otomatik gösteriliyor — bkz. CompletionAdFlow, izlenen ekranlarda tetiklenir).
class DailyQuizPage extends StatefulWidget {
  const DailyQuizPage({super.key});

  @override
  State<DailyQuizPage> createState() => _DailyQuizPageState();
}

/// Günlük quiz yokken Favorin pool'dan seçilen öğe (tournament veya test)
class _DailyFallbackItem {
  final String id;
  final String name;
  final String image;
  final List<String> items;
  final bool isFromTest;

  _DailyFallbackItem({
    required this.id,
    required this.name,
    required this.image,
    required this.items,
    required this.isFromTest,
  });
}

class _DailyQuizPageState extends State<DailyQuizPage> {
  Category? _dailyQuiz;
  _DailyFallbackItem? _dailyFallback;
  bool _loading = true;
  String? _error;
  int _streakCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDailyQuiz();
    _loadStreak();
  }

  Future<void> _loadDailyQuiz() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      // Prefer categories created within last 24 hours (any mode).
      // Sadece Soru'nun 'dilemma' tipi kategorileri Günün Quizi'nde
      // görünmemeli (kullanıcı isteği) — bu ekran resim tabanlı DuelVoteCard
      // kullanıyor, dilemma içeriği kendi tam ekran modunda kalmalı. Firestore
      // tarafında type== + createdAt orderBy birleşimi composite index
      // gerektirebileceğinden (ve bu index'in var olduğu garanti değil),
      // sunucu tarafında filtrelemek yerine birkaç sonuç çekip ilk
      // dilemma-olmayanı client-side seçiyoruz.
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(hours: 24));

      QuerySnapshot? snapshot;
      try {
        snapshot = await FirebaseFirestore.instance
            .collection('categories')
            .where('createdAt', isGreaterThan: Timestamp.fromDate(yesterday))
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();
      } catch (e) {
        // Index might not exist yet, fallback to simple query
        debugPrint('Index query failed, using fallback: $e');
        snapshot = null;
      }

      final picked = _firstNonDilemma(snapshot);
      if (picked != null) {
        try {
          final category = Category.fromFirestore(picked);
          if (!mounted) return;
          setState(() {
            _dailyQuiz = category;
            _dailyFallback = null;
            _loading = false;
          });
          return;
        } catch (e) {
          debugPrint('Error parsing category: $e');
        }
      }

      // Fallback: latest category (any mode) - index gerekebilir, atlarsak Favorin'e düşeriz
      QuerySnapshot? fallbackSnapshot;
      try {
        fallbackSnapshot = await FirebaseFirestore.instance
            .collection('categories')
            .orderBy('createdAt', descending: true)
            .limit(10)
            .get();
      } catch (e) {
        debugPrint('Fallback createdAt query failed (index?): $e');
        fallbackSnapshot = null;
      }

      final pickedFallback = _firstNonDilemma(fallbackSnapshot);
      if (pickedFallback != null) {
        try {
          final category = Category.fromFirestore(pickedFallback);
          if (!mounted) return;
          setState(() {
            _dailyQuiz = category;
            _dailyFallback = null;
            _loading = false;
          });
          return;
        } catch (e) {
          debugPrint('Error parsing category: $e');
        }
      }

      // Günün quiz'i yok: Favorin Hangisi'ndekilerden rastgele birini göster
      final fallback = await _loadRandomFavorinCategory();
      if (!mounted) return;
      setState(() {
        _dailyQuiz = null;
        _dailyFallback = fallback;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Günün quiz'i yüklenemedi. (${e.toString()})";
        _loading = false;
      });
    }
  }

  /// Verilen snapshot'taki dokümanlar arasından ilk `type != 'dilemma'` olanı
  /// döner (Sadece Soru içeriği Günün Quizi'nde çıkmasın diye).
  QueryDocumentSnapshot? _firstNonDilemma(QuerySnapshot? snapshot) {
    if (snapshot == null) return null;
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data?['type'] != 'dilemma') return doc;
    }
    return null;
  }

  /// Favorin Hangisi kaynaklarından (tournament + categories_test) rastgele bir kategori seç
  Future<_DailyFallbackItem?> _loadRandomFavorinCategory() async {
    final List<_DailyFallbackItem> pool = [];

    try {
      final tournamentSnapshot = await FirebaseFirestore.instance
          .collection('categories')
          .where('type', isEqualTo: 'tournament')
          .get();

      for (var doc in tournamentSnapshot.docs) {
        try {
          final category = Category.fromFirestore(doc);
          if (category.items.length == 32) {
            pool.add(_DailyFallbackItem(
              id: category.id,
              name: category.name,
              image: category.image,
              items: category.items,
              isFromTest: false,
            ));
          }
        } catch (_) {}
      }

      final testSnapshot = await FirebaseFirestore.instance
          .collection('categories_test')
          .get();

      for (var doc in testSnapshot.docs) {
        try {
          final data = doc.data();
          final name = data['name'] as String? ?? doc.id;
          final itemsText = data['items_text'] as String? ?? '';
          final image = (data['image'] as String? ?? '').toString();
          final items = itemsText
              .split('|')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (items.isNotEmpty) {
            pool.add(_DailyFallbackItem(
              id: 'test_${doc.id}',
              name: name,
              image: image,
              items: items,
              isFromTest: true,
            ));
          }
        } catch (_) {}
      }

      if (pool.isEmpty) return null;
      pool.shuffle(Random());
      return pool.first;
    } catch (e) {
      debugPrint('Fallback Favorin load failed: $e');
      return null;
    }
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
    } catch (_) {
      // Non-critical UI decoration; ignore failures.
    }
  }

  void _playDailyQuiz() {
    if (_dailyQuiz == null) return;
    final items = _dailyQuiz!.items;
    if (items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu quiz\'de henüz yeterli öğe yok.')),
      );
      return;
    }
    final pairCount = items.length ~/ 2;
    final List<Map<String, dynamic>> questions = [];
    for (int i = 0; i < pairCount; i++) {
      final idx = i * 2;
      if (idx + 1 < items.length) {
        questions.add({'itemA': items[idx], 'itemB': items[idx + 1]});
      }
    }
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu quiz\'de henüz soru yok.')),
      );
      return;
    }
    AnalyticsHelper.categoryPlayed(
      categoryKey: _dailyQuiz!.id,
      categoryName: _dailyQuiz!.name,
      gameMode: 'quiz',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.quiz),
        builder: (_) => QuizPage(
          categoryName: _dailyQuiz!.name,
          categoryKey: _dailyQuiz!.id,
          questions: questions,
        ),
      ),
    );
  }

  void _playDailyFallback() {
    final f = _dailyFallback;
    if (f == null) return;
    if (f.isFromTest) {
      if (f.items.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu kategoride henüz yeterli öğe yok.')),
        );
        return;
      }
      final pairCount = f.items.length ~/ 2;
      final questions = <Map<String, dynamic>>[];
      for (int i = 0; i < pairCount; i++) {
        final idx = i * 2;
        if (idx + 1 < f.items.length) {
          questions.add({'itemA': f.items[idx], 'itemB': f.items[idx + 1]});
        }
      }
      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu kategoride henüz soru yok.')),
        );
        return;
      }
      final rawKey = f.id.startsWith('test_') ? f.id.substring(5) : f.id;
      AnalyticsHelper.categoryPlayed(
        categoryKey: f.id,
        categoryName: f.name,
        gameMode: 'test_quiz',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: AnalyticsScreenNames.testQuiz),
          builder: (_) => TestQuizPage(
            categoryName: f.name,
            categoryKey: rawKey,
            questions: questions,
          ),
        ),
      );
    } else {
      if (f.items.length != 32) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu turnuva kategorisi geçersiz. (32 öğe gerekli)'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      AnalyticsHelper.categoryPlayed(
        categoryKey: f.id,
        categoryName: f.name,
        gameMode: 'tournament',
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: AnalyticsScreenNames.tournament),
          builder: (_) => TournamentPage(
            categoryName: f.name,
            categoryKey: f.id,
            items: f.items,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Günün Quizi'),
        actions: [
          if (_streakCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 4),
                      Text(
                        '$_streakCount gün',
                        style: const TextStyle(
                          color: Color(0xFF3B2400),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Yükleniyor...', style: TextStyle(color: AppColors.mist)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.mist),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.mist),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadDailyQuiz,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tekrar Dene'),
                        )
                      ],
                    ),
                  ),
                )
              : _dailyQuiz == null && _dailyFallback == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.quiz, size: 72, color: AppColors.mistDim),
                            const SizedBox(height: 20),
                            const Text(
                              'Bugün için quiz henüz hazır değil',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                color: AppColors.cloud,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Yarın tekrar kontrol et veya aşağıdan yenile.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: AppColors.mist),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadDailyQuiz,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DailyQuizCard(
                              name: _dailyQuiz?.name ?? _dailyFallback!.name,
                              image: _dailyQuiz?.image ?? _dailyFallback!.image,
                              itemCount: _dailyQuiz?.items.length ?? _dailyFallback!.items.length,
                              onPlay: _dailyQuiz != null
                                  ? () => _playDailyQuiz()
                                  : () => _playDailyFallback(),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}

class _DailyQuizCard extends StatelessWidget {
  final String name;
  final String image;
  final int itemCount;
  final VoidCallback onPlay;

  const _DailyQuizCard({
    required this.name,
    required this.image,
    required this.itemCount,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final questionCount = itemCount ~/ 2;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 240,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.isNotEmpty)
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withValues(alpha: 0.5),
                  BlendMode.darken,
                ),
                child: CachedNetworkImage(
                  imageUrl: safeImageUrl(image),
                  fit: BoxFit.cover,
                  height: 240,
                  width: double.infinity,
                  errorWidget: (context, url, error) =>
                      const ColoredBox(color: AppColors.night2),
                ),
              )
            else
              const ColoredBox(color: AppColors.night2),
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.cloud,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.quiz, size: 18, color: AppColors.violet),
                          const SizedBox(width: 8),
                          Text(
                            '$questionCount soru',
                            style: const TextStyle(color: AppColors.mist, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: onPlay,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Başla'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
