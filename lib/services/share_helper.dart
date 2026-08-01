import 'package:share_plus/share_plus.dart';

/// Centralized share text/links so every screen shares the same message format.
class ShareHelper {
  static const String _appStoreUrl = 'https://apps.apple.com/app/id6746716144';
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.ock.bumuomu';

  static String _links() => '🍎 iOS: $_appStoreUrl\n🤖 Android: $_playStoreUrl';

  static Future<void> shareTournamentWinner({
    required String categoryName,
    required String winner,
  }) {
    final text =
        'Bumuomu\'da "$categoryName" turnuvasında kazanan: $winner! 🏆\n\nSen ne seçerdin? Hemen indir, karşılaştır:\n\n${_links()}';
    return Share.share(text);
  }

  static Future<void> shareQuizCompleted({required String categoryName}) {
    final text =
        'Bumuomu\'da "$categoryName" quizini bitirdim! Sen de dene, seçimlerimiz aynı mı görelim:\n\n${_links()}';
    return Share.share(text);
  }
}
