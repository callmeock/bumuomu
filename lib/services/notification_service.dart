import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide Category;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show navigatorKey, TournamentPage;
import '../models/category.dart';

/// Firebase Cloud Messaging servisi
/// Push notification yönetimi için
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static String? _fcmToken;

  /// FCM token'ı al
  static String? get fcmToken => _fcmToken;

  static const String _prefsKey = 'notifications_enabled';

  /// Kullanıcının uygulama içi bildirim tercihi (varsayılan: açık).
  /// Uygulama ön plandayken gelen push'ların local banner olarak gösterilip
  /// gösterilmeyeceğini kontrol eder. Arka plan/kapalıyken gelen bildirimler
  /// sistem seviyesinde OS ayarlarına tabidir, bu tercih onu etkilemez.
  static Future<bool> notificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKey) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
  }

  /// Bildirim servisini başlat
  static Future<void> initialize() async {
    try {
      // Local notifications için başlat
      await _initializeLocalNotifications();

      // İzin iste (iOS için)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // İzin durumunu detaylı logla
      debugPrint('📱 İzin durumu: ${settings.authorizationStatus}');
      debugPrint('📱 Alert: ${settings.alert}');
      debugPrint('📱 Badge: ${settings.badge}');
      debugPrint('📱 Sound: ${settings.sound}');
      
      // Simulator kontrolü
      if (Platform.isIOS && settings.alert == AppleNotificationSetting.notSupported) {
        debugPrint('⚠️ iOS Simulator kullanılıyor - Push notification desteklenmez!');
        debugPrint('ℹ️ Gerçek cihazda test edin: flutter run --release (gerçek cihaz)');
        // Simulator'da token alınamaz, ama devam edelim (gerçek cihazda çalışacak)
      }

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Kullanıcı bildirim izni verdi');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('⚠️ Kullanıcı geçici bildirim izni verdi');
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('❌ Kullanıcı bildirim izni vermedi (denied)');
        // İzin verilmediyse bile token alma işlemini deneyebiliriz
        // (bazı durumlarda çalışabilir)
      } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        debugPrint('⚠️ İzin durumu belirlenmedi (notDetermined)');
      }

      // İzin verilmediyse bile token alma işlemini dene
      // (bazı durumlarda token alınabilir ama bildirim gösterilemez)

      // Token al (iOS için biraz bekle - APNS token hazır olması için)
      if (Platform.isIOS) {
        await Future.delayed(const Duration(seconds: 1));
      }
      await _getToken();

      // Token değişikliklerini dinle
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _saveTokenToFirestore(newToken);
        debugPrint('🔄 FCM Token yenilendi: $newToken');
      });

      // Foreground mesajları dinle (uygulama açıkken)
      FirebaseMessaging.onMessage.listen((message) {
        _handleForegroundMessage(message);
      });

      // Background'dan açıldığında (tıklandığında)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Uygulama kapalıyken gelen bildirimi kontrol et
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
    } catch (e) {
      debugPrint('❌ Notification servisi başlatılamadı: $e');
    }
  }

  /// FCM token'ı al ve Firestore'a kaydet
  static Future<void> _getToken() async {
    try {
      // iOS için APNS token'ın hazır olmasını bekle
      if (Platform.isIOS) {
        debugPrint('⏳ iOS: APNS token bekleniyor...');
        
        // APNS token'ın hazır olmasını bekle (max 10 saniye)
        int attempts = 0;
        bool apnsTokenFound = false;
        while (attempts < 20) {
          final apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) {
            debugPrint('✅ APNS Token alındı: $apnsToken');
            apnsTokenFound = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
          attempts++;
        }
        
        // Hala yoksa simulator olabilir
        if (!apnsTokenFound) {
          final finalCheck = await _messaging.getAPNSToken();
          if (finalCheck == null) {
            debugPrint('⚠️ APNS Token alınamadı - iOS Simulator kullanılıyor olabilir');
            debugPrint('ℹ️ Push notification için gerçek cihazda test edin');
            debugPrint('ℹ️ Simulator\'da push notification desteklenmez');
            // Simulator'da token alınamaz, ama devam edelim (gerçek cihazda çalışacak)
            return; // Simulator'da token alınamaz, sessizce çık
          }
        }
      }
      
      _fcmToken = await _messaging.getToken();
      if (_fcmToken != null) {
        debugPrint('✅ FCM Token alındı: $_fcmToken');
        await _saveTokenToFirestore(_fcmToken!);
      }
    } catch (e) {
      debugPrint('❌ FCM Token alınamadı: $e');
      
      // iOS'ta hata varsa birkaç saniye sonra tekrar dene
      if (Platform.isIOS) {
        debugPrint('🔄 3 saniye sonra tekrar deneniyor...');
        await Future.delayed(const Duration(seconds: 3));
        try {
          await _getToken(); // Tekrar dene
        } catch (retryError) {
          debugPrint('❌ Tekrar deneme başarısız: $retryError');
        }
      }
    }
  }

  /// Token'ı Firestore'a kaydet
  static Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('user_tokens')
          .doc(user.uid)
          .set({
        'fcmToken': token,
        'userId': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ FCM Token Firestore\'a kaydedildi');
    } catch (e) {
      debugPrint('❌ FCM Token Firestore\'a kaydedilemedi: $e');
    }
  }

  /// Local notifications başlat
  static Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('📱 Local bildirime tıklandı: ${details.payload}');
      },
    );

    // Android için notification channel oluştur
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        'high_importance_channel',
        'Yüksek Öncelikli Bildirimler',
        description: 'Bu kanal önemli bildirimler için kullanılır',
        importance: Importance.high,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }
  }

  /// Foreground mesaj işleme (uygulama açıkken)
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('📨 Foreground bildirim alındı: ${message.notification?.title}');

    if (!await notificationsEnabled()) {
      debugPrint('🔕 Kullanıcı uygulama içi bildirimleri kapatmış, banner gösterilmiyor.');
      return;
    }

    // Local notification göster
    if (message.notification != null) {
      final notification = message.notification!;
      
      const androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'Yüksek Öncelikli Bildirimler',
        channelDescription: 'Bu kanal önemli bildirimler için kullanılır',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        notification.hashCode,
        notification.title ?? 'Bildirim',
        notification.body ?? '',
        notificationDetails,
        payload: message.data.toString(),
      );
      
      debugPrint('✅ Local bildirim gösterildi');
    }
  }

  /// Bildirime tıklandığında — varsa categoryKey'e göre ilgili turnuvaya yönlendirir.
  static void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('👆 Bildirime tıklandı: ${message.notification?.title}');

    final categoryKey = message.data['categoryKey'];
    if (categoryKey == null || categoryKey.isEmpty) return;

    debugPrint('📂 Kategoriye yönlendiriliyor: $categoryKey');
    _navigateToCategory(categoryKey);
  }

  static Future<void> _navigateToCategory(String categoryKey) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('categories')
          .doc(categoryKey)
          .get();
      if (!doc.exists) {
        debugPrint('⚠️ Bildirimdeki kategori bulunamadı: $categoryKey');
        return;
      }

      final category = Category.fromFirestore(doc);
      if (category.items.length != 32) {
        debugPrint('⚠️ Kategori turnuva formatında değil (${category.items.length} öğe), yönlendirme atlandı.');
        return;
      }

      final state = navigatorKey.currentState;
      if (state == null) return;
      state.push(
        MaterialPageRoute(
          builder: (_) => TournamentPage(
            categoryName: category.name,
            categoryKey: category.id,
            items: category.items,
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Bildirim yönlendirme hatası: $e');
    }
  }

  /// Token'ı sil (logout vb. durumlarda)
  static Future<void> deleteToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('user_tokens')
            .doc(user.uid)
            .delete();
      }
      await _messaging.deleteToken();
      _fcmToken = null;
      debugPrint('✅ FCM Token silindi');
    } catch (e) {
      debugPrint('❌ FCM Token silinemedi: $e');
    }
  }
}

/// Background message handler
/// Bu fonksiyon top-level olmalı (class dışında)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📨 Background bildirim alındı: ${message.messageId}');
  // Background'da yapılacak işlemler
}

