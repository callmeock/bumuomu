/// Merkezi event ve ekran adları (PII yok).

abstract class AnalyticsEventNames {
  static const screenView = 'screen_view';
  static const screenExit = 'screen_exit';
  static const appBackgrounded = 'app_backgrounded';
  static const appForegrounded = 'app_foregrounded';

  static const categoryLockedTapped = 'category_locked_tapped';
  static const unlockOfferShown = 'unlock_offer_shown';
  static const adOpened = 'ad_opened';
  static const adClosed = 'ad_closed';
  static const categoryPlayStarted = 'category_play_started';

  static const gameplayCategoryPlayed = 'gameplay_category_played';
  static const gameplayUnlimitedOpened = 'gameplay_unlimited_opened';
  static const gameplayVoteSubmitted = 'gameplay_vote_submitted';
  static const gameplayUnlimitedVote = 'gameplay_unlimited_vote';
  static const gameplayQuizStarted = 'gameplay_quiz_started';
  static const gameplayQuizVote = 'gameplay_quiz_vote';
  static const gameplayQuizCompleted = 'gameplay_quiz_completed';
  static const monetizationCategoryUnlocked = 'monetization_category_unlocked';
  static const engagementAppOpened = 'engagement_app_opened';
}

abstract class AnalyticsScreenNames {
  static const intro = 'intro';
  static const home = 'home';
  static const favorin = 'favorin';
  static const unlimited = 'unlimited';
  static const profile = 'profile';
  static const categories = 'categories';
  static const tournament = 'tournament';
  static const quiz = 'quiz';
  static const testQuiz = 'test_quiz';
  static const unlockSheet = 'unlock_sheet';
  static const categorySelection = 'category_selection';
  static const soloHub = 'solo_hub';
  static const dilemma = 'dilemma';
  static const roomsHub = 'rooms_hub';
  static const roomLobby = 'room_lobby';
  static const roomPlay = 'room_play';
}

abstract class AnalyticsAdPlacement {
  static const categoryUnlock = 'category_unlock';
  static const categoryComplete = 'category_complete';
  static const roomComplete = 'room_complete';
  static const unlimitedPeriodic = 'unlimited_periodic';
  static const appOpenResume = 'app_open_resume';
}

/// Navigator / tab ile senkron: app lifecycle ve funnel [source_screen] için.
class AnalyticsNavigationState {
  AnalyticsNavigationState._();

  static String _current = AnalyticsScreenNames.home;

  /// Alt sekme adı (route isimsiz pop sonrası geri yükleme için).
  static String _lastTabScreen = AnalyticsScreenNames.home;

  static String get currentScreen => _current;

  static String get lastTabScreen => _lastTabScreen;

  static void setScreen(String name) {
    if (name.isEmpty) return;
    _current = name;
  }

  static void setLastTabScreen(String name) {
    if (name.isEmpty) return;
    _lastTabScreen = name;
    _current = name;
  }
}
