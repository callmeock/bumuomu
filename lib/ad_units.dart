import 'package:flutter/foundation.dart';

/// Tek yerde AdMob kimlikleri (publisher `ca-app-pub-7853141950552414`).
///
/// **Uygulama kimlikleri** (`~…`) Info.plist (`GADApplicationIdentifier`) ve
/// AndroidManifest ile eşleşmeli — burada yalnızca referans.
abstract final class AdMobApplicationIds {
  static const ios = 'ca-app-pub-7853141950552414~7793582650';
  static const android = 'ca-app-pub-7853141950552414~3823683523';
}

/// Yayın ve test **reklam birimi** ID’leri.
abstract final class AdMobAdUnits {
  // --- Rewarded interstitial (kategori kilidi) ---
  static const androidRewardedInterstitial =
      'ca-app-pub-7853141950552414/7442211630';
  static const iosRewardedInterstitial =
      'ca-app-pub-7853141950552414/6735634627';

  /// Google demo birimleri — Rewarded Interstitial formatı (Rewarded değil).
  static const androidTestRewardedInterstitial =
      'ca-app-pub-3940256099942544/5354046379';
  static const iosTestRewardedInterstitial =
      'ca-app-pub-3940256099942544/6978759866';

  // --- Banner ---
  static const androidBanner = 'ca-app-pub-7853141950552414/6523026728';
  static const iosBanner = 'ca-app-pub-7853141950552414/8711094414';

  static const androidTestBannerFixed =
      'ca-app-pub-3940256099942544/6300978111';
  static const iosTestBannerFixed =
      'ca-app-pub-3940256099942544/2934735716';

  // --- Interstitial (Sınırsız Mod periyodik ara) ---
  static const androidInterstitial = 'ca-app-pub-7853141950552414/1204657026';
  static const iosInterstitial = 'ca-app-pub-7853141950552414/1069191582';

  static const androidTestInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const iosTestInterstitial =
      'ca-app-pub-3940256099942544/4411468910';

  // --- App Open (soğuk açılış / arka plandan dönüş) ---
  static const androidAppOpen = 'ca-app-pub-7853141950552414/7714225058';
  static const iosAppOpen = 'ca-app-pub-7853141950552414/1839347776';

  static const androidTestAppOpen =
      'ca-app-pub-3940256099942544/9257395921';
  static const iosTestAppOpen = 'ca-app-pub-3940256099942544/5575463023';

  /// Şu anki platform ve [useTestAds] için rewarded interstitial birimi.
  static String rewardedInterstitial({required bool useTestAds}) {
    if (useTestAds) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return androidTestRewardedInterstitial;
        case TargetPlatform.iOS:
          return iosTestRewardedInterstitial;
        default:
          return androidTestRewardedInterstitial;
      }
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? androidRewardedInterstitial
        : iosRewardedInterstitial;
  }

  /// Şu anki platform ve [useTestAds] için banner birimi.
  static String bannerFixed({required bool useTestAds}) {
    if (useTestAds) {
      return defaultTargetPlatform == TargetPlatform.android
          ? androidTestBannerFixed
          : iosTestBannerFixed;
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? androidBanner
        : iosBanner;
  }

  /// Şu anki platform ve [useTestAds] için interstitial birimi.
  static String interstitial({required bool useTestAds}) {
    if (useTestAds) {
      return defaultTargetPlatform == TargetPlatform.android
          ? androidTestInterstitial
          : iosTestInterstitial;
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? androidInterstitial
        : iosInterstitial;
  }

  /// Şu anki platform ve [useTestAds] için App Open birimi.
  static String appOpen({required bool useTestAds}) {
    if (useTestAds) {
      return defaultTargetPlatform == TargetPlatform.android
          ? androidTestAppOpen
          : iosTestAppOpen;
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? androidAppOpen
        : iosAppOpen;
  }
}
