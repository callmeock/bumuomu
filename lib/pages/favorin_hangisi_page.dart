import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../analytics/analytics_constants.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
import '../widgets/full_width_category_card.dart';
import 'test_page.dart';

/// Favorin Hangisi sayfası - 32'li turnuva kategorileri + Test DB'deki bot üretimi
///
/// Kategoriler artık kilitli değil (kullanıcı isteği: reklam kategoriyi
/// bitirince otomatik gösteriliyor, önceden izlenmesi gerekmiyor — bkz.
/// CompletionAdFlow).
class FavorinHangisiPage extends StatefulWidget {
  const FavorinHangisiPage({super.key});

  @override
  State<FavorinHangisiPage> createState() => _FavorinHangisiPageState();
}

/// Tek listede: turnuva (categories) + test (categories_test) birleşik öğe
class _FavorinCategoryItem {
  final String id;
  final String name;
  final String image;
  final List<String> items;
  final bool isFromTest;
  final DateTime? createdAt;

  _FavorinCategoryItem({
    required this.id,
    required this.name,
    required this.image,
    required this.items,
    required this.isFromTest,
    this.createdAt,
  });

  /// "Yeni" freshness badge — cheap, purely-visual mitigation for the top
  /// corroborated marketing finding (content/question staleness); makes the
  /// content pipeline visible instead of only real (Acrodix app #5).
  bool get isFresh =>
      createdAt != null &&
      DateTime.now().difference(createdAt!) < const Duration(days: 7);
}

class _FavorinHangisiPageState extends State<FavorinHangisiPage> {
  List<_FavorinCategoryItem> _items = [];
  bool _loading = true;
  String? _error;
  int _streakCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadStreak();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final List<_FavorinCategoryItem> loaded = [];

      // 1) categories: type == "tournament", 32 öğe
      final tournamentSnapshot = await FirebaseFirestore.instance
          .collection('categories')
          .where('type', isEqualTo: 'tournament')
          .get();

      for (var doc in tournamentSnapshot.docs) {
        try {
          final category = Category.fromFirestore(doc);
          if (category.items.length == 32) {
            loaded.add(_FavorinCategoryItem(
              id: category.id,
              name: category.name,
              image: category.image,
              items: category.items,
              isFromTest: false,
              createdAt: category.createdAt,
            ));
          } else {
            debugPrint('Tournament category ${category.id} has ${category.items.length} items, expected 32');
          }
        } catch (e) {
          debugPrint('Error parsing category ${doc.id}: $e');
        }
      }

      // 2) categories_test: bot üretimi (Favorin Hangisi'nde de göster)
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
          final createdAtValue = data['createdAt'];
          final createdAt =
              createdAtValue is Timestamp ? createdAtValue.toDate() : null;
          if (items.isNotEmpty) {
            loaded.add(_FavorinCategoryItem(
              id: 'test_${doc.id}',
              name: name,
              image: image,
              items: items,
              isFromTest: true,
              createdAt: createdAt,
            ));
          }
        } catch (e) {
          debugPrint('Error parsing test category ${doc.id}: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _items = loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Kategoriler yüklenemedi. (${e.toString()})";
        _loading = false;
      });
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

  void _openItem(_FavorinCategoryItem item) {
    if (item.isFromTest) {
      if (item.items.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu kategoride henüz yeterli öğe yok.')),
        );
        return;
      }
      final pairCount = item.items.length ~/ 2;
      final questions = <Map<String, dynamic>>[];
      for (int i = 0; i < pairCount; i++) {
        final idx = i * 2;
        if (idx + 1 < item.items.length) {
          questions.add({
            'itemA': item.items[idx],
            'itemB': item.items[idx + 1],
          });
        }
      }
      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu kategoride henüz soru yok.')),
        );
        return;
      }
      final rawKey = item.id.startsWith('test_') ? item.id.substring(5) : item.id;
      AnalyticsHelper.categoryPlayed(
        categoryKey: item.id,
        categoryName: item.name,
        gameMode: 'test_quiz',
      );
      AnalyticsHelper.coreAction(
        name: CoreActionName.favorin,
        params: {'phase': 'start', 'game_mode': 'test_quiz'},
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: AnalyticsScreenNames.testQuiz),
          builder: (_) => TestQuizPage(
            categoryName: item.name,
            categoryKey: rawKey,
            questions: questions,
          ),
        ),
      );
    } else {
      if (item.items.length != 32) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu turnuva kategorisi geçersiz. (32 öğe gerekli)')),
        );
        return;
      }
      AnalyticsHelper.categoryPlayed(
        categoryKey: item.id,
        categoryName: item.name,
        gameMode: 'tournament',
      );
      AnalyticsHelper.coreAction(
        name: CoreActionName.favorin,
        params: {'phase': 'start', 'game_mode': 'tournament'},
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: AnalyticsScreenNames.tournament),
          builder: (_) => TournamentPage(
            categoryName: item.name,
            categoryKey: item.id,
            items: item.items,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _loadCategories)
                : RefreshIndicator(
                    onRefresh: _loadCategories,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildHeader()),
                        if (_items.isEmpty)
                          const SliverFillRemaining(
                            child: Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Text(
                                  'Henüz kategori yok. Yakında eklenecek!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.mist),
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xxl),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 1,
                                mainAxisSpacing: AppSpacing.md,
                                childAspectRatio: 64 / 27,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final item = _items[index];
                                  return FullWidthCategoryCard(
                                    title: item.name,
                                    imageUrl: item.image,
                                    colorIndex: index,
                                    isNew: item.isFresh,
                                    onTap: () => _openItem(item),
                                  );
                                },
                                childCount: _items.length,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.night2,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 16, color: AppColors.cloud),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              gradient: AppTheme.sideAGradient,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text('👋', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(
            child: Text(
              'Favorin Hangisi?',
              style: TextStyle(
                fontSize: 20,
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
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.mist),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.mist)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            )
          ],
        ),
      ),
    );
  }
}
