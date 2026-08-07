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
import 'services/ad_service.dart';
import 'services/app_open_ad_service.dart';
import 'services/notification_service.dart';
import 'services/subscription_service.dart';
import 'services/vote_service.dart';
import 'pages/intro_page.dart';
import 'pages/main_navigation.dart';
import 'services/analytics_session.dart';
import 'services/analytics_helper.dart';
import 'services/analytics_route_observer.dart';
import 'services/share_helper.dart';
import 'services/completion_ad_flow.dart';
import 'theme/app_theme.dart';
import 'utils/image_url.dart';
import 'widgets/app_lifecycle_analytics.dart';
import 'widgets/duel_card.dart';
import 'widgets/result_share_row.dart';
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

  try {
    await SubscriptionService.initialize();
  } catch (e) {
    // ignore: avoid_print
    print("❌ Abonelik durumu başlatılamadı: $e");
  }

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
    AppOpenAdService.initialize();
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
        theme: AppTheme.dark(),
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
  int _streakCount = 0;
  bool _completionAdTriggered = false;

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
    _loadStreak();
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
    _precacheUpcomingPair();
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
    _precacheUpcomingPair();
  }

  /// Kullanıcı mevcut eşleşmeye bakarken, aynı round içindeki bir sonraki
  /// eşleşmenin görsellerini arka planda indirmeye başlar — böylece oraya
  /// geçtiğinde spinner görünmez. Yeni round'un eşleşmesi kazanana bağlı
  /// olduğundan önceden bilinemez, bu yüzden sadece aynı round'a bakılır.
  void _precacheUpcomingPair() {
    if (!mounted || descriptions.isEmpty) return;
    final nextA = currentIndex + 2;
    final nextB = currentIndex + 3;
    if (nextB >= currentRound.length) return;
    precacheSafeImage(
        context, descriptions[currentRound[nextA]]?['image'] as String?);
    precacheSafeImage(
        context, descriptions[currentRound[nextB]]?['image'] as String?);
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

  Widget _buildWinnerScreen(String winner) {
    final desc = descriptions[winner];
    final text = desc?['text'] ?? "$winner kazandı!";
    final imageUrl = (desc?['image'] as String?) ?? '';

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '🏆 Tebrikler!',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: AppColors.cloud,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              winner,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.yellow,
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.xl),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: safeImageUrl(imageUrl),
                      placeholder: (context, url) => const SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) {
                        debugPrint('❌ Winner image load error for $url -> $error');
                        return Container(
                          height: 240,
                          color: AppColors.night2,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined,
                                size: 48, color: AppColors.mistDim),
                          ),
                        );
                      },
                      fit: BoxFit.cover,
                      height: 240,
                      width: double.infinity,
                    )
                  : Container(
                      height: 240,
                      width: double.infinity,
                      color: AppColors.night2,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            size: 48, color: AppColors.mistDim),
                      ),
                    ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.night2,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Text(
                '"$text"',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: AppColors.mist,
                ),
              ),
            ),
            const SizedBox(height: 20),
            ResultShareRow(
              onShare: (ctx) => ShareHelper.shareTournamentWinner(
                ctx,
                categoryName: widget.categoryName,
                winner: winner,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ana Sayfaya Dön'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isFinal = options.length == 1;
    final int displayX = (matchesPlayed + 1).clamp(1, widget.items.length);
    final int displayY = widget.items.length;

    if (isFinal && !_completionAdTriggered) {
      _completionAdTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        CompletionAdFlow.onCategoryCompleted(
          context,
          categoryKey: widget.categoryKey,
          categoryName: widget.categoryName,
        );
      });
    }

    return Scaffold(
      body: SafeArea(
        child: isFinal
            ? _buildWinnerScreen(options[0])
            : Column(
                children: [
                  DuelHeaderBar(
                    categoryName: widget.categoryName,
                    streakCount: _streakCount,
                    roundLabel:
                        "${widget.items.length}'LIK TURNUVA · $displayX / $displayY",
                    roundProgress: displayY == 0 ? 0 : displayX / displayY,
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            DuelVoteCard(
                              name: options[0],
                              imageUrl:
                                  (descriptions[options[0]]?['image'] as String?) ?? '',
                              opponentName:
                                  options.length > 1 ? options[1] : '',
                              categoryKey: widget.categoryKey,
                              isSelected: selectedIndex == 0,
                              hasVoted: hasVoted,
                              enabled: options.length == 2,
                              accent: AppColors.violet,
                              onTap: () => _handleVote(0),
                            ),
                            DuelVoteCard(
                              name: options.length > 1 ? options[1] : '',
                              imageUrl: options.length > 1
                                  ? (descriptions[options[1]]?['image'] as String?) ?? ''
                                  : '',
                              opponentName: options[0],
                              categoryKey: widget.categoryKey,
                              isSelected: selectedIndex == 1,
                              hasVoted: hasVoted,
                              enabled: options.length == 2,
                              accent: AppColors.coral,
                              onTap: () => _handleVote(1),
                            ),
                          ],
                        ),
                        if (options.length == 2) const VsBadge(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
