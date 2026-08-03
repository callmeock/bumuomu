import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/vote_service.dart';
import '../services/share_helper.dart';
import '../services/completion_ad_flow.dart';
import '../theme/app_theme.dart';
import '../widgets/duel_card.dart';
import '../widgets/result_share_row.dart';

/// Test Quiz Page - descriptions_test koleksiyonunu kullanır (bot üretimi içerik)
class TestQuizPage extends StatefulWidget {
  final String categoryName;
  final String categoryKey;
  final List<Map<String, dynamic>> questions;

  const TestQuizPage({
    Key? key,
    required this.categoryName,
    required this.categoryKey,
    required this.questions,
  }) : super(key: key);

  @override
  State<TestQuizPage> createState() => _TestQuizPageState();
}

class _TestQuizPageState extends State<TestQuizPage> {
  int _currentQuestionIndex = 0;
  bool _hasVoted = false;
  int? _selectedIndex;
  Map<String, dynamic> _descriptions = {};
  bool _loadingDescriptions = true;

  int get totalQuestions => widget.questions.length;
  int get currentQuestionNumber => _currentQuestionIndex + 1;

  @override
  void initState() {
    super.initState();
    _loadDescriptions();
  }

  Future<void> _loadDescriptions() async {
    try {
      // Load from descriptions_test collection
      final snapshot = await FirebaseFirestore.instance
          .collection('descriptions_test')
          .get();

      final Map<String, dynamic> data = {};
      for (var doc in snapshot.docs) {
        data[doc.id] = doc.data();
      }

      if (!mounted) return;
      setState(() {
        _descriptions = data;
        _loadingDescriptions = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDescriptions = false;
      });
    }
  }

  Map<String, dynamic>? get _currentQuestion {
    if (_currentQuestionIndex >= widget.questions.length) return null;
    return widget.questions[_currentQuestionIndex];
  }

  List<String> get _currentOptions {
    final q = _currentQuestion;
    if (q == null) return [];

    final optionA = q['itemA']?.toString() ?? '';
    final optionB = q['itemB']?.toString() ?? '';

    if (optionA.isEmpty || optionB.isEmpty) return [];

    return [optionA, optionB];
  }

  // Get description document ID for test DB format: {category_id}_{itemName}
  String _getDescriptionDocId(String itemName) {
    return '${widget.categoryKey}_$itemName';
  }

  // Normalize item name to match Storage file naming (Make.com):
  // lowercase + Turkish char strip + spaces -> underscore
  String _normalizeItemNameForStorage(String itemName) {
    var normalized = itemName.trim().toLowerCase();
    const turkishMap = {
      'ç': 'c',
      'ğ': 'g',
      'ı': 'i',
      'ö': 'o',
      'ş': 's',
      'ü': 'u',
    };
    turkishMap.forEach((key, value) {
      normalized = normalized.replaceAll(key, value);
    });
    normalized = normalized.replaceAll(' ', '_');
    return normalized;
  }

  /// Get image URL for an item. Prefers the real `image_url` field stored on
  /// the `descriptions_test` doc; only falls back to a guessed Storage path
  /// when that field is empty. Previously this ignored the stored field
  /// unconditionally — a diagnosed bug (Acrodix app #5).
  String _getImageUrl(String itemName) {
    final descDocId = _getDescriptionDocId(itemName);
    final desc = _descriptions[descDocId];

    final firestoreImageUrl = desc?['image_url']?.toString() ?? '';
    if (firestoreImageUrl.isNotEmpty) {
      return firestoreImageUrl;
    }

    // Fallback: construct URL from Firebase Storage path.
    // Path format: descriptions_test/{category_id}/{normalizedItemName}.png
    final normalizedItemName = _normalizeItemNameForStorage(itemName);
    final storagePath =
        'descriptions_test/${widget.categoryKey}/$normalizedItemName.png';
    final pathSegments = storagePath.split('/');
    final encodedSegments =
        pathSegments.map((segment) => Uri.encodeComponent(segment)).toList();
    final encodedPath = encodedSegments.join('%2F');
    final url =
        'https://firebasestorage.googleapis.com/v0/b/bumuomu-96772.firebasestorage.app/o/$encodedPath?alt=media';
    debugPrint('🖼️ TestQuiz image (from Storage path) for $descDocId -> $url');
    return url;
  }

  Future<void> _handleVote(int index) async {
    if (_hasVoted || _currentQuestion == null) return;

    setState(() {
      _hasVoted = true;
      _selectedIndex = index;
    });

    final selected = _currentOptions[index];
    final opponent = _currentOptions[1 - index];

    await VoteService.vote(
      widget.categoryKey,
      selected,
      opponent,
      selected,
    );

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;

      if (_currentQuestionIndex + 1 >= widget.questions.length) {
        _showCompletionScreen();
      } else {
        setState(() {
          _currentQuestionIndex++;
          _hasVoted = false;
          _selectedIndex = null;
        });
      }
    });
  }

  Future<void> _showCompletionScreen() async {
    await CompletionAdFlow.onCategoryCompleted(
      context,
      categoryKey: widget.categoryKey,
      categoryName: widget.categoryName,
    );
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.night2,
        title: const Text('🎉 Tebrikler!', style: TextStyle(color: AppColors.cloud)),
        content: Text(
          '${widget.categoryName} kategorisindeki tüm soruları tamamladın!',
          style: const TextStyle(color: AppColors.mist),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          ResultShareRow(
            onShare: (ctx) => ShareHelper.shareQuizCompleted(
              ctx,
              categoryName: widget.categoryName,
            ),
          ),
        ],
      ),
    ).then((_) {
      if (!mounted) return;
      Navigator.pop(context); // Quiz sayfasından çık
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDescriptions || _currentQuestion == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final options = _currentOptions;
    if (options.length != 2) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.categoryName)),
        body: const Center(
          child: Text('Soru formatı hatalı. İki seçenek gerekli.'),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DuelHeaderBar(
              categoryName: widget.categoryName,
              roundLabel: '$currentQuestionNumber / $totalQuestions',
              roundProgress:
                  totalQuestions == 0 ? 0 : currentQuestionNumber / totalQuestions,
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      DuelVoteCard(
                        name: options[0],
                        imageUrl: _getImageUrl(options[0]),
                        opponentName: options[1],
                        categoryKey: widget.categoryKey,
                        isSelected: _selectedIndex == 0,
                        hasVoted: _hasVoted,
                        accent: AppColors.violet,
                        onTap: () => _handleVote(0),
                      ),
                      DuelVoteCard(
                        name: options[1],
                        imageUrl: _getImageUrl(options[1]),
                        opponentName: options[0],
                        categoryKey: widget.categoryKey,
                        isSelected: _selectedIndex == 1,
                        hasVoted: _hasVoted,
                        accent: AppColors.coral,
                        onTap: () => _handleVote(1),
                      ),
                    ],
                  ),
                  const VsBadge(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
