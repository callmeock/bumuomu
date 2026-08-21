import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_helper.dart';

/// Native "puanla" isteği (StoreKit `requestReview` / Android in-app review).
/// Sıklık sınırlaması yapar: mağazaların kendi yıllık gösterim kotasını boşa
/// harcamamak için belirli sayıda "mutlu an"dan sonra, belirli bir bekleme
/// süresiyle ve ömür boyu üst sınırla çağırır.
class RateService {
  RateService._();

  static const _keyCompletionCount = 'rate_completion_count';
  static const _keyLastShownAtMs = 'rate_last_shown_at_ms';
  static const _keyLifetimeShownCount = 'rate_lifetime_shown_count';

  static const int _completionsRequired = 3;
  static const Duration _cooldown = Duration(days: 60);
  static const int _lifetimeMax = 3;

  static void _log(String message) {
    // ignore: avoid_print
    print('[Rate] $message');
  }

  /// "Mutlu an" tetikleyicisinden çağrılır (ör. kategori tamamlama). Best-effort:
  /// asla throw etmez, çağıranı asla bloklamaz.
  static Future<void> maybePromptForReview({required String trigger}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final completionCount = (prefs.getInt(_keyCompletionCount) ?? 0) + 1;
      await prefs.setInt(_keyCompletionCount, completionCount);

      final lifetimeShown = prefs.getInt(_keyLifetimeShownCount) ?? 0;
      if (lifetimeShown >= _lifetimeMax) return;
      if (completionCount < _completionsRequired) return;

      final lastShownAtMs = prefs.getInt(_keyLastShownAtMs);
      if (lastShownAtMs != null) {
        final since = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(lastShownAtMs),
        );
        if (since < _cooldown) return;
      }

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return;

      await prefs.setInt(_keyLastShownAtMs, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_keyLifetimeShownCount, lifetimeShown + 1);
      await prefs.setInt(_keyCompletionCount, 0);

      await AnalyticsHelper.ratePromptShown(trigger: trigger);
      await inAppReview.requestReview();
      await AnalyticsHelper.ratePromptResult(result: 'shown');
    } catch (e) {
      _log('maybePromptForReview EXCEPTION: $e');
    }
  }
}
