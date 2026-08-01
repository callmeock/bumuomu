import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'unlimited_mode.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';
import 'services/vote_service.dart';
import 'pages/intro_page.dart';
import 'pages/main_navigation.dart';
import 'services/analytics_session.dart';
import 'services/analytics_helper.dart';
import 'services/analytics_route_observer.dart';
import 'services/unlock_ad_flow.dart';
import 'services/share_helper.dart';
import 'widgets/app_lifecycle_analytics.dart';
import 'analytics/analytics_constants.dart';

export 'services/analytics_helper.dart';

/// Global navigator key so services (e.g. NotificationService, for push deep-links)
/// can push routes without a BuildContext.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
  if (settings.name == '/main') {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: AnalyticsScreenNames.home),
      builder: (_) => const MainNavigationPage(),
    );
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AnalyticsSession.start();
  await Firebase.initializeApp();

  // 📱 AdMob'u başlat (8.x: InitializationStatus döner)
  try {
    final adsInit = await MobileAds.instance.initialize();
    // ignore: avoid_print
    print("✅ AdMob başlatıldı");
    for (final e in adsInit.adapterStatuses.entries) {
      final s = e.value;
      if (s.state != AdapterInitializationState.ready) {
        // ignore: avoid_print
        print(
          '[AdMob] adapter ${e.key}: ${s.state} — ${s.description}',
        );
      }
    }
    await AdService.initialize();
  } catch (e) {
    // ignore: avoid_print
    print("❌ AdMob başlatma hatası: $e");
  }

  // 🔔 Background message handler'ı kaydet
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 🔐 Anonim Auth
  try {
    await FirebaseAuth.instance.signInAnonymously();
    // ignore: avoid_print
    print("✅ Anonim kullanıcı girişi başarılı");
  } catch (e) {
    // ignore: avoid_print
    print("❌ Anonim giriş hatası: $e");
  }

  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await FirebaseAnalytics.instance.setUserId(id: user.uid);
    // ignore: avoid_print
    print("✅ Analytics userId ayarlandı: ${user.uid}");
  }

  // 🔔 Notification servisini başlat
  await NotificationService.initialize();

  await AnalyticsHelper.appOpened();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AppLifecycleAnalytics(
      child: MaterialApp(
        title: 'Bu mu O mu?',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Colors.orange,
          ),
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        navigatorObservers: <NavigatorObserver>[
          AnalyticsRouteObserver.instance,
        ],
        home: const _InitialPage(),
        onGenerateRoute: _onGenerateRoute,
      ),
    );
  }
}

/// İlk açılış kontrolü yapan sayfa
class _InitialPage extends StatefulWidget {
  const _InitialPage();

  @override
  State<_InitialPage> createState() => _InitialPageState();
}

class _InitialPageState extends State<_InitialPage> {
  bool _loading = true;
  bool _showIntro = false;
  bool _shellHomeScreenLogged = false;

  @override
  void initState() {
    super.initState();
    _checkIntroStatus();
  }

  Future<void> _checkIntroStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final introCompleted = prefs.getBool('intro_completed') ?? false;
    
    if (!mounted) return;
    setState(() {
      _showIntro = !introCompleted;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_showIntro) {
      return const IntroPage();
    }

    if (!_shellHomeScreenLogged) {
      _shellHomeScreenLogged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AnalyticsHelper.screenView(
          screenName: AnalyticsScreenNames.home,
          source: null,
        );
        AnalyticsNavigationState.setLastTabScreen(AnalyticsScreenNames.home);
      });
    }
    return const MainNavigationPage();
  }
}

class CategorySelectionPage extends StatefulWidget {
  const CategorySelectionPage({super.key});

  @override
  State<CategorySelectionPage> createState() => _CategorySelectionPageState();
}

class _CategorySelectionPageState extends State<CategorySelectionPage> {
  Map<String, dynamic> categories = {};
  bool _loading = true;
  String? _error;
  Set<String> _unlockedCategories = {}; // Açık kategoriler
  bool _loadingUnlocked = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnlockedCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final snapshot =
          await FirebaseFirestore.instance.collection('categories').get();

      final Map<String, dynamic> data = {};
      for (var doc in snapshot.docs) {
        final map = doc.data();
        final displayName = (map['name'] as String?) ?? doc.id; // name yoksa doc.id
        data[displayName] = {
          "key": doc.id,
          "items": List<String>.from(map['items'] ?? const []),
          "image": map['image'],
        };
      }

      if (!mounted) return;
      setState(() {
        categories = data;
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

  /// Kullanıcının açık kategorilerini Firestore'dan çek
  Future<void> _loadUnlockedCategories() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _unlockedCategories = {};
          _loadingUnlocked = false;
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('user_progress')
          .doc(user.uid)
          .get();

      final unlocked = doc.data()?['unlockedCategories'] as List<dynamic>?;
      if (!mounted) return;
      setState(() {
        _unlockedCategories = (unlocked ?? []).map((e) => e.toString()).toSet();
        _loadingUnlocked = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _unlockedCategories = {};
        _loadingUnlocked = false;
      });
    }
  }

  /// Kategoriyi video reklam ile aç
  Future<void> _unlockCategory(String categoryKey, String categoryName) async {
    if (!mounted) return;
    try {
      final watched = await UnlockAdFlow.showRewardedForCategory(
        context,
        categoryKey: categoryKey,
        categoryName: categoryName,
      );
      if (!mounted) return;
      if (watched) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('user_progress')
              .doc(user.uid)
              .set({
            'unlockedCategories': FieldValue.arrayUnion([categoryKey]),
            'lastUnlock': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          await AnalyticsHelper.categoryUnlocked(
            categoryKey: categoryKey,
            categoryName: categoryName,
            method: 'rewarded_interstitial',
            gameMode: 'tournament',
          );

          setState(() {
            _unlockedCategories.add(categoryKey);
          });

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $categoryName kategorisi açıldı!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Reklam izlenemedi. Lütfen tekrar deneyin.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openUnlimited() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.unlimited),
        builder: (_) =>
            const UnlimitedModePage(analyticsSource: 'home_card'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gridPadding = const EdgeInsets.all(16.0);

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _loadCategories)
              : RefreshIndicator(
                  onRefresh: _loadCategories,
                  child: Padding(
                    padding: gridPadding,
                    child: GridView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: categories.length + 1, // +1: Sınırsız Mod kartı
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 1,
                        mainAxisSpacing: 16,
                        childAspectRatio: 64 / 27,
                      ),
                      itemBuilder: (context, index) {
                        // 0 -> Sınırsız Mod özel kart
                        if (index == 0) {
                          return _UnlimitedCard(onTap: _openUnlimited);
                        }

                        // diğerleri -> Firestore kategorileri
                        final categoryName =
                            categories.keys.elementAt(index - 1);
                        final category = categories[categoryName];
                        final categoryKey = category['key'] as String;
                        final imageUrl = (category['image'] ?? '').toString();
                        final items =
                            List<String>.from(category['items'] ?? const []);
                        final isLocked = !_unlockedCategories.contains(categoryKey);

                        return _CategoryCard(
                          title: categoryName,
                          imageUrl: imageUrl,
                          categoryKey: categoryKey,
                          isLocked: isLocked,
                          onTap: isLocked
                              ? () => _unlockCategory(categoryKey, categoryName)
                              : () {
                                  // 🔹 Analytics: Kategoriye girildi
                                  AnalyticsHelper.categoryPlayed(
                                    categoryKey: categoryKey,
                                    categoryName: categoryName,
                                    gameMode: 'tournament',
                                  );

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      settings: const RouteSettings(
                                        name: AnalyticsScreenNames.tournament,
                                      ),
                                      builder: (_) => TournamentPage(
                                        categoryName: categoryName,
                                        categoryKey: categoryKey,
                                        items: items,
                                      ),
                                    ),
                                  );
                                },
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}

class _UnlimitedCard extends StatelessWidget {
  final VoidCallback onTap;
  const _UnlimitedCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _FrostedCard(
      onTap: onTap,
      background: const _CardBackground.gradient(),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Yeni Mod',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.all_inclusive, size: 48, color: Colors.white),
                SizedBox(height: 12),
                Text(
                  'Sınırsız Mod',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(1, 2),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Bitmeyen sorular, anlık oy ver, akış hiç durmasın!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatefulWidget {
  final String title;
  final String imageUrl;
  final String categoryKey;
  final bool isLocked;
  final VoidCallback onTap;
  const _CategoryCard({
    required this.title,
    required this.imageUrl,
    required this.categoryKey,
    required this.isLocked,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.isLocked) {
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat(reverse: true);
      _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (widget.isLocked) {
      _animationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FrostedCard(
      onTap: widget.onTap,
      background: _CardBackground.image(url: widget.imageUrl),
      child: Stack(
        children: [
          // Kategori adı - her zaman göster
          Center(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: widget.isLocked
                    ? Colors.white.withOpacity(0.5)
                    : Colors.white,
                shadows: const [
                  Shadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(1, 2),
                  ),
                ],
              ),
            ),
          ),
          // Kilitli durum için minimal overlay
          if (widget.isLocked)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    // Sağ üst köşe - Kilit badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: AnimatedBuilder(
                        animation: _scaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.9),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.orange.withOpacity(0.5),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.lock,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Alt kısım - Video izle butonu
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B35),
                              Color(0xFFF7931E),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orange.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onTap,
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Video İzle',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FrostedCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final _CardBackground background;

  const _FrostedCard({
    required this.child,
    required this.onTap,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = background.when(
      imageBuilder: (url) => BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.05),
        image: url.isNotEmpty
            ? DecorationImage(
                image: CachedNetworkImageProvider(url),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.35),
                  BlendMode.darken,
                ),
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      gradientBuilder: () => BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF7F00FF), // mor
            Color(0xFF00B3FF), // mavi
            Color(0xFFFF6A00), // turuncu
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: decoration,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.black.withOpacity(0.08),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _CardBackground {
  final String? _imageUrl;
  final bool _isGradient;
  const _CardBackground._(this._imageUrl, this._isGradient);

  factory _CardBackground.image({required String url}) =>
      _CardBackground._(url, false);
  const _CardBackground.gradient() : this._(null, true);

  T when<T>({
    required T Function(String url) imageBuilder,
    required T Function() gradientBuilder,
  }) {
    if (_isGradient) return gradientBuilder();
    return imageBuilder(_imageUrl ?? '');
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
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
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

// -----------------------------
//        TOURNAMENT PAGE
// -----------------------------
class TournamentPage extends StatefulWidget {
  final String categoryName;
  final String categoryKey;
  final List<String> items;

  const TournamentPage({
    Key? key,
    required this.categoryName,
    required this.categoryKey,
    required this.items,
  }) : super(key: key);

  @override
  _TournamentPageState createState() => _TournamentPageState();
}

class _TournamentPageState extends State<TournamentPage> {
  late List<String> currentRound;
  List<String> nextRound = [];
  int currentIndex = 0;
  List<String> options = [];
  Map<String, dynamic> descriptions = {};
  bool hasVoted = false;
  int? selectedIndex;

  // seedIndex: item adı -> başlangıçtaki seed (items listesindeki indeks)
  late final Map<String, int> seedIndex;

  // 🔹 Maç sayaçları
  int matchesPlayed = 0; // 0'dan sayarız ama ekranda 1 gösteririz
  int get totalMatches {
    final n = widget.items.length;
    return n <= 1 ? 0 : n - 1; // toplam maç
  }

  @override
  void initState() {
    super.initState();
    currentRound = List.from(widget.items);
    seedIndex = {
      for (int i = 0; i < widget.items.length; i++) widget.items[i]: i
    };
    _loadDescriptions();
    _loadNextPair();
  }

  Future<void> _loadDescriptions() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('descriptions').get();
    final Map<String, dynamic> data = {
      for (var d in snapshot.docs) d.id: d.data()
    };
    if (!mounted) return;
    setState(() => descriptions = data);
  }

  void _loadNextPair() {
    if (currentRound.length == 1 && nextRound.isEmpty) {
      setState(() => options = [currentRound[0]]);
      return;
    }

    if (currentIndex + 1 >= currentRound.length) {
      if (nextRound.length == 1) {
        setState(() {
          options = [nextRound[0]];
          currentRound = [];
        });
        return;
      }
      currentRound = List.from(nextRound);
      nextRound.clear();
      currentIndex = 0;
    }

    setState(() {
      options = [currentRound[currentIndex], currentRound[currentIndex + 1]];
    });
  }

  Future<void> _handleVote(int index) async {
    if (hasVoted) return;

    setState(() {
      hasVoted = true;
      selectedIndex = index;
      matchesPlayed += 1; // her oy sonrası sayaç artır
    });

    final selected = options[index];
    final opponent = options[1 - index];

    // Vote using VoteService (new schema)
    await VoteService.vote(
      widget.categoryKey,
      selected,
      opponent,
      selected, // chosenId
    );

    // 🔹 Analytics: Oy verildi
    final pairId = VoteService.generatePairId(selected, opponent);
    final List<String> normalized = [selected, opponent]..sort();
    final selectedIsA = selected == normalized[0];
    
    AnalyticsHelper.voteSubmitted(
      categoryKey: widget.categoryKey,
      pairId: pairId,
      selectedIsA: selectedIsA,
      selected: selected,
      opponent: opponent,
    );

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        nextRound.add(selected);
        currentIndex += 2;
        hasVoted = false;
        selectedIndex = null;
      });
      _loadNextPair();
    });
  }

  Widget _buildVotingCard(String name, int index) {
    final bool isSelected = selectedIndex == index;
    final desc = descriptions[name];

    final opponent = options.firstWhere((e) => e != name, orElse: () => '');  

    // Overlay yoğunluğu: seçilmeyen kart = tam; seçilen (kazanan) = yarım
    final double overlayOpacity = hasVoted ? (isSelected ? 0.05 : 0.80) : 0.0;

    return GestureDetector(
      onTap:
          hasVoted || options.length == 1 ? null : () => _handleVote(index),
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.4,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Stack(
              children: [
                // Arkaplan içerik (başlık + görsel)
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Text(
                        name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: desc?['image'] ?? '',
                          placeholder: (context, url) =>
                              const Center(child: CircularProgressIndicator()),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ],
                ),

                // 🔹 Overlay efekt
                if (overlayOpacity > 0)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                          12), // kartla aynı radius (iç görsel katmanı)
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          color: Colors.black.withOpacity(overlayOpacity),
                        ),
                      ),
                    ),
                  ),

                // 🔹 Yüzdelik yazısı — overlay'in ÜSTÜNDE
                if (hasVoted && opponent.isNotEmpty)
                  StreamBuilder<Map<String, int>>(
                    stream: VoteService.getVoteCountsStream(
                      widget.categoryKey,
                      name,
                      opponent,
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      final counts = snapshot.data!;
                      final aCount = counts['aCount'] ?? 0;
                      final bCount = counts['bCount'] ?? 0;
                      final total = aCount + bCount;
                      if (total == 0) return const SizedBox.shrink();

                      // Determine which item is 'a' (normalized order)
                      final List<String> normalized = [name, opponent]..sort();
                      final bool thisIsA = name == normalized[0];

                      final pct = thisIsA
                          ? (aCount / total * 100).round()
                          : (bCount / total * 100).round();

                      // Renkler: eşitse mavi, kazanan yeşil (#008000), kaybeden kırmızı
                      Color textColor;
                      if (aCount == bCount) {
                        textColor = Colors.blue;
                      } else {
                        final thisCount = thisIsA ? aCount : bCount;
                        final oppCount = thisIsA ? bCount : aCount;
                        textColor = (thisCount > oppCount)
                            ? const Color(0xFF008000)
                            : Colors.red;
                      }

                      return Center(
                        child: Text(
                          "%$pct",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            shadows: const [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black,
                                offset: Offset(2, 2),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Voting using VoteService (new schema) ----
  // Note: Tournament algorithm still uses seedIndex for bracket logic,
  // but voting uses VoteService with deterministic pairId from SHA1

  Widget _buildWinnerScreen(String winner) {
    final desc = descriptions[winner];
    final text = desc?['text'] ?? "$winner kazandı!";
    final imageUrl = desc?['image'] ?? '';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              "🏆 Tebrikler!",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                shadows: [Shadow(blurRadius: 4, color: Colors.white54)],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              winner,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.orange[800],
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                placeholder: (context, url) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) =>
                    const Icon(Icons.error),
                fit: BoxFit.cover,
                height: MediaQuery.of(context).size.height * 0.35,
                width: double.infinity,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  )
                ],
              ),
              child: Text(
                '"$text"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ShareHelper.shareTournamentWinner(
                categoryName: widget.categoryName,
                winner: winner,
              ),
              icon: const Icon(Icons.share),
              label: const Text('Paylaş'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black87,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: const StadiumBorder(),
                side: const BorderSide(color: Colors.black54),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                shape: const StadiumBorder(),
              ),
              child: const Text("Ana Sayfaya Dön"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isFinal = options.length == 1;

    // Ekranda gösterilecek X/Y:
    // X = (matchesPlayed + 1)  → 1’den başlasın
    // Y = toplam adım olarak item sayısı → örn 32
    final int displayX = (matchesPlayed + 1).clamp(1, widget.items.length);
    final int displayY = widget.items.length;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red, Colors.red, Colors.blue, Colors.blue],
            stops: [0.0, 0.49, 0.51, 1.0],
          ),
        ),
        child: SafeArea(
          child: isFinal
              ? _buildWinnerScreen(options[0])
              : Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildVotingCard(options[0], 0),
                        _buildVotingCard(options[1], 1),
                      ],
                    ),
                    // 🔹 Tam ortada, TAM GENİŞLİKTE X/Y overlay
                    IgnorePointer(
                      ignoring: true,
                      child: Align(
                        alignment: Alignment.center,
                        child: Transform.translate(
                          offset: const Offset(0, -16),
                          child: SizedBox(
                            width: double.infinity,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 6),
                              color: Colors.black.withOpacity(0.30),
                              child: Text(
                                "$displayX / $displayY",
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 6,
                                      color: Colors.black,
                                      offset: Offset(1, 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
