import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Centralized share text/links so every screen shares the same message format.
///
/// All share calls are awaited with try/catch and pass a sharePositionOrigin
/// (required on iPad; share_plus 10.x can fail silently without it) — fixes
/// the "share button does nothing" bug diagnosed for bumuomu (Acrodix app #5).
class ShareHelper {
  static const String _appStoreUrl = 'https://apps.apple.com/app/id6746716144';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ock.bumuomu';
  static const String instagramUrl = 'https://instagram.com/bumuomuapp';

  static String _links() => '🍎 iOS: $_appStoreUrl\n🤖 Android: $_playStoreUrl';

  static Rect? _originFromContext(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  static Future<bool> _share(BuildContext context, String text) async {
    try {
      final result = await Share.share(
        text,
        sharePositionOrigin: _originFromContext(context),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('❌ Paylaşım başarısız: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşım açılamadı, tekrar dene.')),
        );
      }
      return false;
    }
  }

  static Future<bool> shareTournamentWinner(
    BuildContext context, {
    required String categoryName,
    required String winner,
  }) {
    final text =
        'Bumuomu\'da "$categoryName" turnuvasında kazanan: $winner! 🏆\n\nSen ne seçerdin? Hemen indir, karşılaştır:\n\n${_links()}';
    return _share(context, text);
  }

  static Future<bool> shareQuizCompleted(
    BuildContext context, {
    required String categoryName,
  }) {
    final text =
        'Bumuomu\'da "$categoryName" quizini bitirdim! Sen de dene, seçimlerimiz aynı mı görelim:\n\n${_links()}';
    return _share(context, text);
  }

  static Future<bool> shareRoomInvite(
    BuildContext context, {
    required String code,
    required String categoryName,
  }) {
    final text =
        'Bumuomu\'da bir oda kurdum, "$categoryName" oynayalım! 🎉\n\nOda kodu: $code\n\nÖnce uygulamayı indir, sonra "Arkadaşlarınla Oyna" > "Odaya Katıl"dan kodu gir:\n\n${_links()}';
    return _share(context, text);
  }
}
