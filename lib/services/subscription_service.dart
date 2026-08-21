import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'analytics_helper.dart';

/// Haftalık reklamsız abonelik (`com.ock.bumuomu.premium.weekly`).
/// Sunucu taraflı receipt doğrulama yok — mağaza seviyesi koruma bu ölçekte
/// yeterli kabul edildi. Anonim Firebase Auth kullanıldığı için yeniden
/// yüklemede UID değişir; gerçek kurtarma yolu [restore] (App Store/Play
/// hesabına bağlı), Firestore/`shared_preferences` sadece hızlı offline cache.
class SubscriptionService {
  SubscriptionService._();

  static const String premiumWeeklyId = 'com.ock.bumuomu.premium.weekly';
  static const _prefsKey = 'is_premium';

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;
  static ProductDetails? _weeklyProduct;

  static final ValueNotifier<bool> isPremiumNotifier = ValueNotifier<bool>(false);
  static bool get isPremium => isPremiumNotifier.value;
  static ProductDetails? get weeklyProduct => _weeklyProduct;

  static void _log(String message) {
    // ignore: avoid_print
    print('[IAP] $message');
  }

  static Future<void> initialize() async {
    isPremiumNotifier.value = await _loadCachedEntitlement();

    final available = await _iap.isAvailable();
    if (!available) {
      _log('store unavailable');
      return;
    }

    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) => _log('purchase stream error: $e'),
    );

    await _queryProduct();
    await _iap.restorePurchases();
  }

  static Future<void> _queryProduct() async {
    try {
      final response = await _iap.queryProductDetails({premiumWeeklyId});
      if (response.error != null) {
        _log('query error: ${response.error}');
      }
      if (response.notFoundIDs.isNotEmpty) {
        _log('product not found on this store: ${response.notFoundIDs}');
      }
      if (response.productDetails.isNotEmpty) {
        _weeklyProduct = response.productDetails.first;
      }
    } catch (e) {
      _log('query EXCEPTION: $e');
    }
  }

  /// Satın alma başlatır. Ürün henüz sorgulanmadıysa önce sorgular.
  /// Ürün mağazada yoksa (henüz onaylanmamış/oluşturulmamışsa) sessizce
  /// çıkar — çağıran taraf [weeklyProduct] null ise butonu zaten
  /// devre dışı bırakmalı.
  static Future<void> buyWeekly() async {
    if (_weeklyProduct == null) {
      await _queryProduct();
    }
    final product = _weeklyProduct;
    if (product == null) {
      _log('buy ABORT: product not available');
      return;
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  static Future<void> restore() => _iap.restorePurchases();

  static Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == premiumWeeklyId) {
        switch (purchase.status) {
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            await _grantEntitlement();
            AnalyticsHelper.purchaseSucceeded(
              productId: purchase.productID,
              method: purchase.status == PurchaseStatus.restored ? 'restored' : 'purchased',
              valueUsd: _weeklyProduct?.rawPrice,
              currency: _weeklyProduct?.currencyCode,
            );
            break;
          case PurchaseStatus.error:
            _log('purchase error: ${purchase.error}');
            AnalyticsHelper.purchaseFailed(
              productId: purchase.productID,
              reason: purchase.error?.message,
            );
            break;
          case PurchaseStatus.pending:
          case PurchaseStatus.canceled:
            break;
        }
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  static Future<void> _grantEntitlement() async {
    isPremiumNotifier.value = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance.collection('user_progress').doc(uid).set({
          'isPremium': true,
          'premiumUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {
        // Non-critical cache write; ignore failures.
      }
    }
  }

  static Future<bool> _loadCachedEntitlement() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? false;
  }
}
