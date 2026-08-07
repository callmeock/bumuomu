import 'package:firebase_analytics/firebase_analytics.dart';
import '../analytics/analytics_constants.dart';
import 'analytics_session.dart';
import 'analytics_unlock_session.dart';

/// Tüm özel analytics event'leri; UI'da doğrudan [FirebaseAnalytics.logEvent] kullanılmaz.
class AnalyticsHelper {
  AnalyticsHelper._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  static Map<String, Object> _withSession(Map<String, Object> params) {
    return <String, Object>{
      'session_id': AnalyticsSession.id,
      ...params,
    };
  }

  static String _truncate(String s, [int max = 96]) {
    if (s.length <= max) return s;
    return s.substring(0, max);
  }

  static Future<void> _emit(String name, Map<String, Object> params) async {
    try {
      await _analytics.logEvent(
        name: name,
        parameters: _withSession(params),
      );
    } catch (_) {}
  }

  // --- Screen & lifecycle ---

  static Future<void> screenView({
    required String screenName,
    String? source,
  }) async {
    await _emit(AnalyticsEventNames.screenView, {
      'screen_name': _truncate(screenName),
      if (source != null && source.isNotEmpty) 'source': _truncate(source),
    });
  }

  static Future<void> screenExit({
    required String screenName,
    required int durationMs,
  }) async {
    await _emit(AnalyticsEventNames.screenExit, {
      'screen_name': _truncate(screenName),
      'duration_ms': durationMs.clamp(0, 86400000),
    });
  }

  static Future<void> appBackgrounded() async {
    await _emit(AnalyticsEventNames.appBackgrounded, {
      'screen_name': _truncate(AnalyticsNavigationState.currentScreen),
    });
  }

  static Future<void> appForegrounded() async {
    await _emit(AnalyticsEventNames.appForegrounded, {
      'screen_name': _truncate(AnalyticsNavigationState.currentScreen),
    });
  }

  // --- Unlock funnel ---

  static Future<void> categoryLockedTapped({
    required String categoryKey,
    required String categoryName,
    required String sourceScreen,
  }) async {
    await _emit(AnalyticsEventNames.categoryLockedTapped, {
      'category_key': _truncate(categoryKey),
      'category_name': _truncate(categoryName),
      'source_screen': _truncate(sourceScreen),
    });
  }

  static Future<void> unlockOfferShown({
    required String categoryKey,
    required String unlockType,
    required int adsRequired,
  }) async {
    await _emit(AnalyticsEventNames.unlockOfferShown, {
      'category_key': _truncate(categoryKey),
      'unlock_type': _truncate(unlockType),
      'ads_required': adsRequired,
    });
  }

  static Future<void> adOpened({
    required String placement,
    required String adType,
  }) async {
    await _emit(AnalyticsEventNames.adOpened, {
      'placement': _truncate(placement),
      'ad_type': _truncate(adType),
    });
  }

  static Future<void> adClosed({
    required String placement,
    required String adType,
    required bool rewardEarned,
  }) async {
    await _emit(AnalyticsEventNames.adClosed, {
      'placement': _truncate(placement),
      'ad_type': _truncate(adType),
      'reward_earned': rewardEarned,
    });
  }

  static Future<void> categoryPlayStarted({
    required String categoryKey,
    required String gameMode,
    required bool unlockedThisSession,
  }) async {
    await _emit(AnalyticsEventNames.categoryPlayStarted, {
      'category_key': _truncate(categoryKey),
      'game_mode': _truncate(gameMode),
      'unlocked_this_session': unlockedThisSession,
    });
  }

  // ========== GAMEPLAY (mevcut + session) ==========

  static Future<void> categoryPlayed({
    required String categoryKey,
    required String categoryName,
    required String gameMode,
  }) async {
    await _emit(AnalyticsEventNames.gameplayCategoryPlayed, {
      'event_category': 'gameplay',
      'game_mode': _truncate(gameMode),
      'category_key': _truncate(categoryKey),
      'category_name': _truncate(categoryName),
    });
    await categoryPlayStarted(
      categoryKey: categoryKey,
      gameMode: gameMode,
      unlockedThisSession:
          AnalyticsUnlockSession.unlockedThisSession(categoryKey),
    );
  }

  static Future<void> unlimitedOpen({String? source, String gameMode = 'unlimited'}) async {
    await _emit(AnalyticsEventNames.gameplayUnlimitedOpened, {
      'event_category': 'gameplay',
      'game_mode': gameMode,
      'source': _truncate(source ?? 'unknown'),
    });
  }

  static Future<void> voteSubmitted({
    required String categoryKey,
    required String pairId,
    required bool selectedIsA,
    required String selected,
    required String opponent,
  }) async {
    await _emit(AnalyticsEventNames.gameplayVoteSubmitted, {
      'event_category': 'gameplay',
      'game_mode': 'tournament',
      'category_key': _truncate(categoryKey),
      'pair_id': _truncate(pairId),
      'selected_is_a': selectedIsA,
      'selected': _truncate(selected),
      'opponent': _truncate(opponent),
    });
  }

  static Future<void> unlimitedVoteSubmitted({
    required String questionId,
    required bool choseA,
    required String selected,
    required String opponent,
    String gameMode = 'unlimited',
  }) async {
    await _emit(AnalyticsEventNames.gameplayUnlimitedVote, {
      'event_category': 'gameplay',
      'game_mode': gameMode,
      'question_id': _truncate(questionId),
      'chose': choseA ? 'A' : 'B',
      'selected': _truncate(selected),
      'opponent': _truncate(opponent),
    });
  }

  static Future<void> quizStarted({
    required String categoryKey,
    required String categoryName,
    required int totalQuestions,
  }) async {
    await _emit(AnalyticsEventNames.gameplayQuizStarted, {
      'event_category': 'gameplay',
      'game_mode': 'quiz',
      'category_key': _truncate(categoryKey),
      'category_name': _truncate(categoryName),
      'total_questions': totalQuestions,
    });
  }

  static Future<void> quizVoteSubmitted({
    required String categoryKey,
    required String categoryName,
    required int questionIndex,
    required String questionId,
    required bool selectedIsA,
    required String selected,
    required String opponent,
  }) async {
    await _emit(AnalyticsEventNames.gameplayQuizVote, {
      'event_category': 'gameplay',
      'game_mode': 'quiz',
      'category_key': _truncate(categoryKey),
      'category_name': _truncate(categoryName),
      'question_index': questionIndex,
      'question_id': _truncate(questionId),
      'selected_is_a': selectedIsA,
      'selected': _truncate(selected),
      'opponent': _truncate(opponent),
    });
  }

  static Future<void> quizCompleted({
    required String categoryKey,
    required String categoryName,
    required int totalQuestions,
  }) async {
    await _emit(AnalyticsEventNames.gameplayQuizCompleted, {
      'event_category': 'gameplay',
      'game_mode': 'quiz',
      'category_key': _truncate(categoryKey),
      'category_name': _truncate(categoryName),
      'total_questions': totalQuestions,
    });
  }

  // ========== MONETIZATION ==========

  static Future<void> categoryUnlocked({
    required String categoryKey,
    required String categoryName,
    required String method,
    String? gameMode,
  }) async {
    AnalyticsUnlockSession.markUnlocked(categoryKey);
    await _emit(AnalyticsEventNames.monetizationCategoryUnlocked, {
      'event_category': 'monetization',
      'category_key': _truncate(categoryKey),
      'category_name': _truncate(categoryName),
      'unlock_method': _truncate(method),
      if (gameMode != null) 'game_mode': _truncate(gameMode),
    });
  }

  // ========== ENGAGEMENT ==========

  static Future<void> appOpened() async {
    await _emit(AnalyticsEventNames.engagementAppOpened, {
      'event_category': 'engagement',
    });
  }

  // ========== SIZDEN GELENLER ==========

  static Future<void> submissionCreated({required String submissionId}) async {
    await _emit(AnalyticsEventNames.submissionCreated, {
      'event_category': 'sizden_gelenler',
      'submission_id': _truncate(submissionId),
    });
  }

  static Future<void> submissionApproved({required String submissionId}) async {
    await _emit(AnalyticsEventNames.submissionApproved, {
      'event_category': 'sizden_gelenler',
      'submission_id': _truncate(submissionId),
    });
  }

  static Future<void> submissionRejected({required String submissionId}) async {
    await _emit(AnalyticsEventNames.submissionRejected, {
      'event_category': 'sizden_gelenler',
      'submission_id': _truncate(submissionId),
    });
  }
}
