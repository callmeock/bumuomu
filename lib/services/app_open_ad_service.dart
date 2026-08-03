import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../ad_units.dart';
import '../analytics/analytics_constants.dart';
import 'ad_service.dart';
import 'analytics_helper.dart';

/// AdMob App Open reklamı: soğuk açılışta değil, arka plandan öne dönüşte
/// gösterilir (kötü ilk izlenim yaratmaması için ilk resume atlanır — normal
/// başlangıç sırasında [AppLifecycleListener.onResume] da bir kere tetiklenir,
/// bu "gerçek" bir dönüş değildir). Sık uygulama geçişlerinde spam olmasın
/// diye son gösterimden bu yana en az [_minGapBetweenShows] geçmesi gerekir.
class AppOpenAdService {
  AppOpenAdService._();

  static AppOpenAd? _ad;
  static bool _isLoading = false;
  static bool _hasSeenFirstResume = false;
  static DateTime? _lastShownAt;
  static AppLifecycleListener? _listener;

  static const _minGapBetweenShows = Duration(minutes: 5);

  static String get _adUnitId => AdMobAdUnits.appOpen(useTestAds: kDebugMode);

  static void _log(String message) {
    // ignore: avoid_print
    print('[AdMob][AppOpen] $message');
  }

  static void initialize() {
    if (!AdService.adsEnabled) {
      _log('initialize SKIPPED (adsEnabled=false)');
      return;
    }
    _loadAd();
    _listener ??= AppLifecycleListener(onResume: _onResume);
  }

  static void _onResume() {
    if (!_hasSeenFirstResume) {
      // İlk resume = normal app başlangıcı, gerçek bir "dönüş" değil.
      _hasSeenFirstResume = true;
      return;
    }
    if (!AdService.adsEnabled) return;

    final now = DateTime.now();
    if (_lastShownAt != null && now.difference(_lastShownAt!) < _minGapBetweenShows) {
      return;
    }
    _showAdIfReady();
  }

  static void _loadAd() {
    if (_isLoading || _ad != null) return;
    _isLoading = true;
    final unitId = _adUnitId;
    AppOpenAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoading = false;
          _ad = ad;
          _log('load SUCCESS | unit=$unitId');
        },
        onAdFailedToLoad: (error) {
          _isLoading = false;
          _log('load FAIL | unit=$unitId | ${error.message}');
        },
      ),
    );
  }

  static void _showAdIfReady() {
    final ad = _ad;
    if (ad == null) {
      _loadAd();
      return;
    }

    _lastShownAt = DateTime.now();
    AnalyticsHelper.adOpened(
      placement: AnalyticsAdPlacement.appOpenResume,
      adType: 'app_open',
    );

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        AnalyticsHelper.adClosed(
          placement: AnalyticsAdPlacement.appOpenResume,
          adType: 'app_open',
          rewardEarned: false,
        );
        ad.dispose();
        _ad = null;
        _loadAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _ad = null;
        _loadAd();
      },
    );

    ad.show();
    _ad = null;
  }
}
