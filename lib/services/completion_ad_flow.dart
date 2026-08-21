import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../analytics/analytics_constants.dart';
import 'ad_service.dart';
import 'analytics_helper.dart';
import 'rate_service.dart';

/// Kategori/oyun tamamlama sonrası otomatik reklam akışı.
///
/// Önceden kategoriler ödüllü reklam izlenmeden oynanamıyordu (watch-to-unlock).
/// Kullanıcı isteği üzerine bu kaldırıldı: artık her şey serbestçe oynanabiliyor,
/// reklam bir kategori/oyun BİTİNCE otomatik gösteriliyor. Aynı ad birim
/// (rewarded interstitial) yeniden kullanılıyor — yeni bir AdMob birimi
/// gerekmiyor, sadece tetikleme anı değişti.
class CompletionAdFlow {
  CompletionAdFlow._();

  /// Bir kategori/oyun bittiğinde çağrılır: reklamı best-effort gösterir
  /// (yüklenmemişse sessizce atlar, akışı bloklamaz) ve `unlockedCategories`
  /// alanına (artık "tamamlanan kategoriler" anlamında) categoryKey'i ekler.
  static Future<void> onCategoryCompleted(
    BuildContext context, {
    required String categoryKey,
    required String categoryName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('user_progress')
            .doc(user.uid)
            .set({
          'unlockedCategories': FieldValue.arrayUnion([categoryKey]),
        }, SetOptions(merge: true));
      } catch (_) {
        // Non-critical stat; ignore failures.
      }
    }

    try {
      final watched = await AdService.showRewardedInterstitialAd(
        placement: AnalyticsAdPlacement.categoryComplete,
      );
      await AnalyticsHelper.categoryUnlocked(
        categoryKey: categoryKey,
        categoryName: categoryName,
        method: watched ? 'auto_rewarded_interstitial' : 'auto_rewarded_interstitial_skipped',
        gameMode: 'completion',
      );
    } catch (_) {
      // Ad not ready / failed — never block the completion screen for this.
    }

    RateService.maybePromptForReview(trigger: 'category_completed');
  }
}
