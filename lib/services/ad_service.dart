import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_units.dart';
import 'analytics_helper.dart';
import 'subscription_service.dart';

/// AdMob: kategori açmak için **ödüllü geçiş (Rewarded Interstitial)** reklamı.
class AdService {
  /// Reklamlar sadece premium olmayan kullanıcılara gösterilir — haftalık
  /// abonelik ([SubscriptionService.isPremium]) satın alınca tüm reklam
  /// çağrıları (banner/rewarded/interstitial/app open) sessizce atlanır.
  static bool get adsEnabled => !SubscriptionService.isPremium;

  static RewardedInterstitialAd? _rewardedInterstitialAd;
  static bool _isCategoryUnlockAdReady = false;
  static Future<void>? _rewardedLoadFuture;

  static InterstitialAd? _interstitialAd;
  static bool _isInterstitialReady = false;
  static Future<void>? _interstitialLoadFuture;

  static void _log(String message) {
    // Release dahil cihaz loglarında görünsün (Xcode / logcat).
    // ignore: avoid_print
    print('[AdMob] $message');
  }

  static String get _bannerAdUnitId =>
      AdMobAdUnits.bannerFixed(useTestAds: kDebugMode);

  static String get _categoryUnlockAdUnitId =>
      AdMobAdUnits.rewardedInterstitial(useTestAds: kDebugMode);

  static String get _interstitialAdUnitId =>
      AdMobAdUnits.interstitial(useTestAds: kDebugMode);

  /// Ödüllü geçiş reklamını önceden yükle (kategori açma).
  static Future<void> loadRewardedInterstitialAd() async {
    if (!adsEnabled) {
      _log('rewarded_interstitial load SKIPPED (adsEnabled=false)');
      return;
    }
    if (_isCategoryUnlockAdReady && _rewardedInterstitialAd != null) {
      _log('rewarded_interstitial load skipped (already loaded)');
      return;
    }

    if (_rewardedLoadFuture != null) {
      _log('rewarded_interstitial load awaiting in-flight');
      await _rewardedLoadFuture;
      return;
    }

    _rewardedLoadFuture = _performRewardedInterstitialLoad();
    try {
      await _rewardedLoadFuture;
    } finally {
      _rewardedLoadFuture = null;
    }
  }

  static Future<void> _performRewardedInterstitialLoad() async {
    final unitId = _categoryUnlockAdUnitId;
    final modeLabel = kDebugMode ? 'test' : 'production';

    _log(
      'rewarded_interstitial load START | unit=$unitId | mode=$modeLabel | '
      'AdRequest()',
    );

    try {
      await RewardedInterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedInterstitialAd = ad;
            _isCategoryUnlockAdReady = true;
            _log('rewarded_interstitial load SUCCESS | unit=$unitId');
          },
          onAdFailedToLoad: (error) {
            _isCategoryUnlockAdReady = false;
            _log(
              'rewarded_interstitial load FAIL | unit=$unitId | '
              'code=${error.code} | domain=${error.domain} | '
              '${error.message}',
            );
          },
        ),
      );
    } catch (e, st) {
      _isCategoryUnlockAdReady = false;
      _log('rewarded_interstitial load EXCEPTION | $e | $st');
    }
  }

  /// Kategori açma reklamını göster. Ödül kazanılırsa `true`.
  static Future<bool> showRewardedInterstitialAd({
    String placement = 'unknown',
    String adType = 'rewarded_interstitial',
  }) async {
    if (!adsEnabled) {
      _log('rewarded_interstitial show SKIPPED (adsEnabled=false)');
      return false;
    }
    if (!_isCategoryUnlockAdReady || _rewardedInterstitialAd == null) {
      await loadRewardedInterstitialAd();
      if (!_isCategoryUnlockAdReady || _rewardedInterstitialAd == null) {
        _log(
          'rewarded_interstitial show ABORT (not loaded after load) | '
          'placement=$placement',
        );
        return false;
      }
    }

    final unitId = _categoryUnlockAdUnitId;
    final modeLabel = kDebugMode ? 'test' : 'production';
    _log(
      'rewarded_interstitial show ATTEMPT | placement=$placement | '
      'unit=$unitId | mode=$modeLabel',
    );

    final completer = Completer<bool>();
    var rewardEarned = false;

    await AnalyticsHelper.adOpened(
      placement: placement,
      adType: adType,
    );
    AnalyticsHelper.adImpression(placement: placement, adType: adType);

    _rewardedInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        AnalyticsHelper.adClosed(
          placement: placement,
          adType: adType,
          rewardEarned: rewardEarned,
        );
        ad.dispose();
        _rewardedInterstitialAd = null;
        _isCategoryUnlockAdReady = false;
        if (!completer.isCompleted) {
          completer.complete(rewardEarned);
        }
        _log(
          'rewarded_interstitial dismissed | placement=$placement | '
          'reward_earned=$rewardEarned',
        );
        loadRewardedInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AnalyticsHelper.adClosed(
          placement: placement,
          adType: adType,
          rewardEarned: false,
        );
        ad.dispose();
        _rewardedInterstitialAd = null;
        _isCategoryUnlockAdReady = false;
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        _log(
          'rewarded_interstitial show FAIL | placement=$placement | '
          'code=${error.code} | ${error.message}',
        );
        loadRewardedInterstitialAd();
      },
    );

    _rewardedInterstitialAd!.show(
      onUserEarnedReward: (ad, reward) {
        rewardEarned = true;
        _log(
          'rewarded_interstitial REWARD EARNED | placement=$placement | '
          'type=${reward.type} | amount=${reward.amount}',
        );
        AnalyticsHelper.adRewarded(
          placement: placement,
          rewardType: reward.type,
          rewardAmount: reward.amount,
        );
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      },
    );

    return completer.future;
  }

  /// Kategori kilidi reklamı hazır mı (isteğe bağlı kontrol).
  static bool get isCategoryUnlockAdReady => _isCategoryUnlockAdReady;

  /// Uygulama açılışında kategori kilidi ve interstitial reklamlarını
  /// önceden yükle.
  static Future<void> initialize() async {
    await loadRewardedInterstitialAd();
    await loadInterstitialAd();
  }

  /// Banner ad yükle. Her çağrı kendi bağımsız `BannerAd` örneğini oluşturur
  /// (paylaşılan static state yok) — birden fazla ekran (ör. alt nav'daki
  /// kalıcı banner + Sınırsız Mod'un kendi banner'ı) aynı anda bağımsız
  /// banner tutabilsin diye; tek paylaşılan örnek olsaydı biri dispose
  /// ettiğinde diğerinin elindeki referans da native tarafta ölmüş olurdu.
  /// [forceNewLoad] artık no-op — geriye dönük uyumluluk için parametre
  /// olarak duruyor, çağıran taraflar değiştirilmeden çalışmaya devam etsin.
  static Future<void> loadBannerAd({
    required AdSize adSize,
    required Function(BannerAd) onAdLoaded,
    required Function(LoadAdError) onAdFailedToLoad,
    bool forceNewLoad = false,
  }) async {
    if (!adsEnabled) {
      _log('banner load SKIPPED (adsEnabled=false)');
      onAdFailedToLoad(LoadAdError(-1, 'ads_disabled', 'adsEnabled=false', null));
      return;
    }
    try {
      final adUnitId = _bannerAdUnitId;
      _log('banner load START | unit=$adUnitId | test=$kDebugMode');

      final bannerAd = BannerAd(
        adUnitId: adUnitId,
        size: adSize,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            _log('banner load SUCCESS | unit=$adUnitId');
            onAdLoaded(ad as BannerAd);
          },
          onAdFailedToLoad: (ad, error) {
            _log(
              'banner load FAIL | unit=$adUnitId | '
              'code=${error.code} | ${error.message}',
            );
            ad.dispose();
            onAdFailedToLoad(error);
          },
          onAdOpened: (ad) {
            _log('banner opened');
          },
          onAdClosed: (ad) {
            _log('banner closed');
          },
        ),
      );

      await bannerAd.load();
    } catch (e) {
      _log('banner load EXCEPTION | $e');
      onAdFailedToLoad(LoadAdError(
        -1,
        'banner_load_error',
        e.toString(),
        null,
      ));
    }
  }

  /// Interstitial önceden yükle (Sınırsız Mod periyodik ara).
  static Future<void> loadInterstitialAd() async {
    if (!adsEnabled) {
      _log('interstitial load SKIPPED (adsEnabled=false)');
      return;
    }
    if (_isInterstitialReady && _interstitialAd != null) {
      _log('interstitial load skipped (already loaded)');
      return;
    }
    if (_interstitialLoadFuture != null) {
      await _interstitialLoadFuture;
      return;
    }
    _interstitialLoadFuture = _performInterstitialLoad();
    try {
      await _interstitialLoadFuture;
    } finally {
      _interstitialLoadFuture = null;
    }
  }

  static Future<void> _performInterstitialLoad() async {
    final unitId = _interstitialAdUnitId;
    try {
      await InterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _interstitialAd = ad;
            _isInterstitialReady = true;
            _log('interstitial load SUCCESS | unit=$unitId');
          },
          onAdFailedToLoad: (error) {
            _isInterstitialReady = false;
            _log('interstitial load FAIL | unit=$unitId | ${error.message}');
          },
        ),
      );
    } catch (e, st) {
      _isInterstitialReady = false;
      _log('interstitial load EXCEPTION | $e | $st');
    }
  }

  /// Interstitial'ı göster (best-effort — yüklenmemişse sessizce atlar).
  static Future<void> showInterstitialAd({
    String placement = 'unknown',
    String adType = 'interstitial',
  }) async {
    if (!adsEnabled) {
      _log('interstitial show SKIPPED (adsEnabled=false)');
      return;
    }
    if (!_isInterstitialReady || _interstitialAd == null) {
      _log('interstitial show ABORT (not loaded) | placement=$placement');
      loadInterstitialAd();
      return;
    }

    await AnalyticsHelper.adOpened(placement: placement, adType: adType);
    AnalyticsHelper.adImpression(placement: placement, adType: adType);

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        AnalyticsHelper.adClosed(placement: placement, adType: adType, rewardEarned: false);
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
        loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        AnalyticsHelper.adClosed(placement: placement, adType: adType, rewardEarned: false);
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
        loadInterstitialAd();
      },
    );

    await _interstitialAd!.show();
  }
}
