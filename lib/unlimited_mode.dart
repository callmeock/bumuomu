import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'analytics/analytics_constants.dart';
import 'services/ad_service.dart';
import 'main.dart';
import 'theme/app_theme.dart';

class UnlimitedModePage extends StatefulWidget {
  const UnlimitedModePage({super.key, this.analyticsSource = 'bottom_tab'});

  /// [AnalyticsHelper.unlimitedOpen] için: `bottom_tab` | `home_card` vb.
  final String analyticsSource;

  @override
  State<UnlimitedModePage> createState() => _UnlimitedModePageState();
}

class _UnlimitedModePageState extends State<UnlimitedModePage> {
  bool _loading = true;
  String? _error;

  // Firestore veri modeli
  List<_UQ> _questions = [];          // tüm sorular (id, text, options)
  List<String> _order = [];           // soru id'lerinin sırası (kullanıcıya özel)
  int _cursor = 0;                    // sıradaki soru index’i
  _UQ? _current;                      // ekranda görünen soru

  // oy / sonuç state
  bool _voting = false;
  bool _showResults = false;
  int? _pctA;
  int? _pctB;
  bool? _selectedIsA; // Hangi seçenek seçildi (true = A, false = B, null = henüz seçilmedi)

  // kimin sırası? (kullanıcı)
  late final String _uid;

  // Banner Ad
  BannerAd? _bannerAd;
  bool _isBannerReady = false;
  Timer? _bannerRefreshTimer;
  bool _bannerReloadInFlight = false;

  // Sonsuz oturumda doğal bir "bitiş" noktası olmadığından, periyodik ara
  // olarak her N cevaplanan sorudan sonra bir interstitial gösteriyoruz
  // (user feedback: agresif reklam stratejisi — Part A2.6).
  int _answeredCount = 0;
  static const int _interstitialEveryNQuestions = 12;

  /// Periyodik banner yenileme aralığı (manuel istek; politika için çok agresif yapmayın).
  static const Duration _bannerRefreshInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    AnalyticsHelper.unlimitedOpen(source: widget.analyticsSource);
    _uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    _boot();
    // İlk yükleme başarısız olsa bile sayfada kalındıkça yeniden dene.
    _startBannerRefreshTimer();
    _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerRefreshTimer?.cancel();
    _bannerRefreshTimer = null;
    _bannerAd?.dispose();
    _bannerAd = null;
    super.dispose();
  }

  void _startBannerRefreshTimer() {
    _bannerRefreshTimer?.cancel();
    _bannerRefreshTimer = Timer.periodic(_bannerRefreshInterval, (_) {
      if (!mounted) return;
      _reloadBannerAd();
    });
  }

  /// Ağaçtan kaldırdıktan sonra eski reklamı dispose edip yenisini yükler.
  void _reloadBannerAd() {
    if (!mounted || _bannerReloadInFlight) return;
    _bannerReloadInFlight = true;
    final old = _bannerAd;
    setState(() {
      _bannerAd = null;
      _isBannerReady = false;
    });
    old?.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _bannerReloadInFlight = false;
        return;
      }
      AdService.loadBannerAd(
        adSize: AdSize.banner,
        forceNewLoad: true,
        onAdLoaded: (ad) {
          _bannerReloadInFlight = false;
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad;
            _isBannerReady = true;
          });
        },
        onAdFailedToLoad: (error) {
          _bannerReloadInFlight = false;
          debugPrint('Banner yenileme başarısız: ${error.message}');
          if (!mounted) return;
          Future<void>.delayed(const Duration(seconds: 30), () {
            if (!mounted) return;
            _reloadBannerAd();
          });
        },
      );
    });
  }

  void _loadBannerAd({bool isRefresh = false}) {
    AdService.loadBannerAd(
      adSize: AdSize.banner,
      forceNewLoad: isRefresh,
      onAdLoaded: (ad) {
        if (!mounted) {
          ad.dispose();
          return;
        }
        setState(() {
          _bannerAd = ad;
          _isBannerReady = true;
        });
      },
      onAdFailedToLoad: (error) {
        debugPrint('Banner ad yüklenemedi: ${error.message}');
        if (!mounted) return;
        // İlk yükleme de başarısız olursa kısa bekleme sonrası tekrar dene.
        Future<void>.delayed(const Duration(seconds: 30), () {
          if (!mounted) return;
          _reloadBannerAd();
        });
      },
    );
  }

  Future<void> _boot() async {
    try {
      setState(() { _loading = true; _error = null; });

      // 1) Soruları Firestore'dan çek
      await _loadQuestions();

      if (_questions.isEmpty) {
        throw Exception('Soru bulunamadı (unlimited_questions boş)'); 
      }

      // 2) Kullanıcıya özel sıra / cursor yükle veya oluştur
      await _loadOrCreateUserOrder();

      // 3) İlk soruyu seç
      _syncCurrentFromCursor();

      setState(() { _loading = false; });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadQuestions() async {
    final snap = await FirebaseFirestore.instance
        .collection('unlimited_questions')
        .where('active', isEqualTo: true)
        .get();

    final items = <_UQ>[];
    for (final d in snap.docs) {
      final m = d.data();
      items.add(_UQ(
        id: d.id,
        question: (m['question'] ?? '').toString(),
        optionA: (m['optionA'] ?? '').toString(),
        optionB: (m['optionB'] ?? '').toString(),
        imageA: (m['imageA'] ?? '')?.toString(),
        imageB: (m['imageB'] ?? '')?.toString(),
        weight: (m['weight'] is num) ? (m['weight'] as num).toDouble() : 1.0,
      ));
    }
    _questions = items;
  }

  Future<void> _loadOrCreateUserOrder() async {
    final stateRef = FirebaseFirestore.instance
        .collection('unlimited_users')
        .doc(_uid)
        .collection('state')
        .doc('default');

    final stateSnap = await stateRef.get();

    final allIds = _questions.map((q) => q.id).toList();

    if (stateSnap.exists) {
      final data = stateSnap.data()!;
      final List<dynamic> storedOrderDyn = (data['order'] ?? []) as List<dynamic>;
      final int storedCursor = (data['cursor'] ?? 0) as int;

      final storedOrder = storedOrderDyn.map((e) => e.toString()).toList();

      // Koleksiyondaki sorular değişmiş olabilir -> storedOrder'ı normalize et
      final validInOrder = storedOrder.where(allIds.contains).toList();

      // yeni eklenen soruları sona ekle
      final missing = allIds.where((id) => !validInOrder.contains(id)).toList();

      _order = [...validInOrder, ...missing];
      _cursor = _clampCursor(storedCursor, _order.length);

      // Eğer storedOrder boş ya da tutarsızsa, sıfırdan oluştur
      if (_order.isEmpty) {
        _order = _deterministicShuffle(allIds, seed: _uid.hashCode);
        _cursor = 0;
      }

      // normalize edilmiş halini kaydet
      await stateRef.set({
        'order': _order,
        'cursor': _cursor,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } else {
      // İlk kez giren kullanıcı -> deterministik karıştır
      _order = _deterministicShuffle(allIds, seed: _uid.hashCode);
      _cursor = 0;

      await stateRef.set({
        'order': _order,
        'cursor': _cursor,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  int _clampCursor(int c, int len) {
    if (len == 0) return 0;
    if (c < 0) return 0;
    if (c >= len) return len - 1;
    return c;
  }

  List<String> _deterministicShuffle(List<String> input, {required int seed}) {
    final list = List<String>.from(input);
    final rnd = Random(seed);
    // basit Fisher-Yates
    for (int i = list.length - 1; i > 0; i--) {
      final j = rnd.nextInt(i + 1);
      final tmp = list[i];
      list[i] = list[j];
      list[j] = tmp;
    }
    return list;
  }

  void _syncCurrentFromCursor() {
    if (_order.isEmpty) {
      _current = null;
      return;
    }
    final currentId = _order[_cursor % _order.length];
    _current = _questions.firstWhere((q) => q.id == currentId, orElse: () => _questions.first);
  }

  Future<void> _vote(bool chooseA) async {
    if (_current == null || _voting) return;
    setState(() { _voting = true; });

    final q = _current!;
    final pollRef = FirebaseFirestore.instance.collection('unlimited_polls').doc(q.id);

    try {
      // Sayaç artır (transaction)
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(pollRef);
        if (!snap.exists) {
          txn.set(pollRef, {
            'aCount': 0,
            'bCount': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        txn.update(pollRef, {
          chooseA ? 'aCount' : 'bCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // Analytics
      await AnalyticsHelper.unlimitedVoteSubmitted(
        questionId: q.id,
        choseA: chooseA,
        selected: chooseA ? q.optionA : q.optionB,
        opponent: chooseA ? q.optionB : q.optionA,
      );

      // Yüzdeleri oku ve göster
      final afterSnap = await pollRef.get();
      final aCount = (afterSnap.data()?['aCount'] ?? 0) as int;
      final bCount = (afterSnap.data()?['bCount'] ?? 0) as int;
      final total = (aCount + bCount).clamp(0, 1 << 31);

      int pctA = 0;
      int pctB = 0;
      if (total > 0) {
        pctA = ((aCount / total) * 100).round();
        pctB = ((bCount / total) * 100).round();
      }

      if (!mounted) return;
      setState(() {
        _pctA = pctA;
        _pctB = pctB;
        _showResults = true;
        _selectedIsA = chooseA;
      });

      // Küçük gösterim süresi
      await Future.delayed(const Duration(milliseconds: 900));

      // Soru kuyruğunu döndür: Cevaplanan en sona gitsin
      await _rotateQueueAndPersist();

      if (!mounted) return;
      setState(() {
        _showResults = false;
        _pctA = null;
        _pctB = null;
        _voting = false;
        _selectedIsA = null;
      });

      _answeredCount++;
      if (_answeredCount % _interstitialEveryNQuestions == 0) {
        AdService.showInterstitialAd(
          placement: AnalyticsAdPlacement.unlimitedPeriodic,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _voting = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Oy verirken hata oluştu: $e')),
      );
    }
  }

  Future<void> _rotateQueueAndPersist() async {
    if (_order.isEmpty) return;

    // mevcut index'teki soruyu kuyruğun sonuna taşı
    final currentId = _order[_cursor];
    final newOrder = List<String>.from(_order);
    newOrder.removeAt(_cursor);
    newOrder.add(currentId);

    // cursor aynı index'te kalsın (artık yeni soru orada)
    // yani bir sonraki soru otomatik olarak sıradaki olacak.
    _order = newOrder;

    // Firestore'a yaz
    final stateRef = FirebaseFirestore.instance
        .collection('unlimited_users')
        .doc(_uid)
        .collection('state')
        .doc('default');

    await stateRef.set({
      'order': _order,
      'cursor': _cursor,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // ekranda yeni current'ı yükle
    _syncCurrentFromCursor();
  }

  Future<void> _skip() async {
    if (_voting) return; // oy sırasında skip yok
    // Skip = oy kullanmadan sıradakine geç; aynı rotasyon kuralı
    await _rotateQueueAndPersist();
    setState(() {}); // UI refresh
  }

  @override
  Widget build(BuildContext context) {

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sınırsız Mod')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sınırsız Mod')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _boot,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar Dene'),
                )
              ],
            ),
          ),
        ),
      );
    }

    if (_current == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sınırsız Mod')),
        body: const Center(child: Text('Soru bulunamadı.')),
      );
    }

    final q = _current!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
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
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.night2,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: const Text('♾️ Sınırsız Mod',
                        style: TextStyle(
                          color: AppColors.cloud,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        )),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _voting ? null : _skip,
                    icon: const Icon(Icons.skip_next, size: 18, color: AppColors.mist),
                    label: const Text('Geç',
                        style: TextStyle(color: AppColors.mist, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            // Ana içerik
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _QuestionCard(
                    key: ValueKey(q.id),
                    data: q,
                    votingLocked: _voting,
                    showResults: _showResults,
                    pctA: _pctA,
                    pctB: _pctB,
                    selectedIsA: _selectedIsA,
                    onVoteA: () => _vote(true),
                    onVoteB: () => _vote(false),
                  ),
                ),
              ),
            ),
            // Banner reklam - sadece ad yüklendiyse ve hazırsa göster
            if (_isBannerReady && _bannerAd != null)
              Container(
                alignment: Alignment.center,
                width: double.infinity,
                height: _bannerAd!.size.height.toDouble(),
                color: Colors.transparent,
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }
}

class _UQ {
  final String id;
  final String question;
  final String optionA;
  final String optionB;
  final String? imageA;
  final String? imageB;
  final double weight;

  _UQ({
    required this.id,
    required this.question,
    required this.optionA,
    required this.optionB,
    this.imageA,
    this.imageB,
    this.weight = 1.0,
  });
}

class _QuestionCard extends StatelessWidget {
  final _UQ data;
  final bool votingLocked;
  final bool showResults;
  final int? pctA;
  final int? pctB;
  final bool? selectedIsA; // true = A seçildi, false = B seçildi, null = henüz seçilmedi
  final VoidCallback onVoteA;
  final VoidCallback onVoteB;

  const _QuestionCard({
    Key? key,
    required this.data,
    required this.votingLocked,
    required this.showResults,
    required this.pctA,
    required this.pctB,
    this.selectedIsA,
    required this.onVoteA,
    required this.onVoteB,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          data.question,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.cloud,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: _ChoiceTile(
            label: data.optionA,
            imageUrl: data.imageA,
            accent: AppColors.violet,
            onTap: votingLocked ? null : onVoteA,
            showResults: showResults,
            pct: pctA,
            isSelected: selectedIsA == true,
            questionId: data.id,
            isOptionA: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _ChoiceTile(
            label: data.optionB,
            imageUrl: data.imageB,
            accent: AppColors.coral,
            onTap: votingLocked ? null : onVoteB,
            showResults: showResults,
            pct: pctB,
            isSelected: selectedIsA == false,
            questionId: data.id,
            isOptionA: false,
          ),
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final String label;
  final String? imageUrl;
  final Color accent;
  final VoidCallback? onTap;
  final bool showResults;
  final int? pct;
  final bool isSelected; // Bu seçenek seçildi mi?
  final String questionId;
  final bool isOptionA; // Bu seçenek A mı B mi?

  const _ChoiceTile({
    Key? key,
    required this.label,
    required this.imageUrl,
    required this.accent,
    required this.onTap,
    required this.showResults,
    required this.pct,
    required this.isSelected,
    required this.questionId,
    required this.isOptionA,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double overlayOpacity = showResults && !isSelected ? 0.55 : 0.0;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          color: AppColors.night2,
          image: (imageUrl != null && imageUrl!.isNotEmpty)
              ? DecorationImage(
                  image: CachedNetworkImageProvider(imageUrl!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.35),
                    BlendMode.darken,
                  ),
                )
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                  ),
                ),
              ),
            ),
            if (overlayOpacity > 0)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                color: Colors.black.withValues(alpha: overlayOpacity),
              ),
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              child: Container(
                width: 6,
                height: 28,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.cloud,
                  ),
                ),
              ),
            ),
            if (showResults && pct != null)
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.md,
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('unlimited_polls')
                      .doc(questionId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const SizedBox.shrink();
                    }
                    final data = snapshot.data!.data()!;
                    final aCount = (data['aCount'] ?? 0) as int;
                    final bCount = (data['bCount'] ?? 0) as int;
                    final total = aCount + bCount;
                    if (total == 0) return const SizedBox.shrink();

                    final thisPct = pct!;
                    return Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            child: LinearProgressIndicator(
                              value: thisPct / 100,
                              minHeight: 8,
                              backgroundColor: AppColors.cloud.withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '%$thisPct',
                          style: const TextStyle(
                            color: AppColors.cloud,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}