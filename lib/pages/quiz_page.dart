import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../services/vote_service.dart';
import '../services/share_helper.dart';
import '../services/completion_ad_flow.dart';
import '../theme/app_theme.dart';
import '../widgets/duel_card.dart';
import '../widgets/result_share_row.dart';

/// Quiz sayfası - Kategoriler ve Günün Quizi için
class QuizPage extends StatefulWidget {
  final String categoryName;
  final String categoryKey;
  final List<Map<String, dynamic>> questions; // questions listesi (Map<String, dynamic> içerir)

  const QuizPage({
    Key? key,
    required this.categoryName,
    required this.categoryKey,
    required this.questions,
  }) : super(key: key);

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int _currentQuestionIndex = 0;
  bool _hasVoted = false;
  int? _selectedIndex;
  Map<String, dynamic> _descriptions = {};
  bool _loadingDescriptions = true;

  // İlerleme sayaçları
  int get totalQuestions => widget.questions.length;
  int get currentQuestionNumber => _currentQuestionIndex + 1;

  @override
  void initState() {
    super.initState();
    _loadDescriptions();

    // Analytics: Quiz başlatıldı
    AnalyticsHelper.quizStarted(
      categoryKey: widget.categoryKey,
      categoryName: widget.categoryName,
      totalQuestions: totalQuestions,
    );
  }

  Future<void> _loadDescriptions() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('descriptions').get();
      final Map<String, dynamic> data = {
        for (var d in snapshot.docs) d.id: d.data()
      };
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
    final q = widget.questions[_currentQuestionIndex];
    if (q is Map<String, dynamic>) {
      return q;
    }
    if (q is String) {
      return {'text': q, 'optionA': '', 'optionB': ''};
    }
    return null;
  }

  List<String> get _currentOptions {
    final q = _currentQuestion;
    if (q == null) return [];

    final optionA = q['itemA'] ??
        q['optionA'] ??
        q['a'] ??
        q['choiceA'] ??
        q['first'] ??
        '';
    final optionB = q['itemB'] ??
        q['optionB'] ??
        q['b'] ??
        q['choiceB'] ??
        q['second'] ??
        '';

    if (optionA.toString().isEmpty || optionB.toString().isEmpty) {
      debugPrint('⚠️ Seçenekler bulunamadı. Mevcut key\'ler: ${q.keys.toList()}');
      return [];
    }

    return [optionA.toString(), optionB.toString()];
  }

  Future<void> _handleVote(int index) async {
    if (_hasVoted || _currentQuestion == null) return;

    setState(() {
      _hasVoted = true;
      _selectedIndex = index;
    });

    final selected = _currentOptions[index];
    final opponent = _currentOptions[1 - index];

    // Vote using VoteService (new schema)
    await VoteService.vote(
      widget.categoryKey,
      selected,
      opponent,
      selected, // chosenId
    );

    // Analytics: Quiz oy verildi
    AnalyticsHelper.quizVoteSubmitted(
      categoryKey: widget.categoryKey,
      categoryName: widget.categoryName,
      questionIndex: _currentQuestionIndex,
      questionId: '${selected}|${opponent}', // Use pair as questionId
      selectedIsA: index == 0,
      selected: selected,
      opponent: opponent,
    );

    // Sonuçları göster ve sonraki soruya geç
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;

      if (_currentQuestionIndex + 1 >= widget.questions.length) {
        // Quiz tamamlandı
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
    // Analytics: Quiz tamamlandı
    AnalyticsHelper.quizCompleted(
      categoryKey: widget.categoryKey,
      categoryName: widget.categoryName,
      totalQuestions: totalQuestions,
    );

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
                        imageUrl: (_descriptions[options[0]]?['image'] as String?) ?? '',
                        opponentName: options[1],
                        categoryKey: widget.categoryKey,
                        isSelected: _selectedIndex == 0,
                        hasVoted: _hasVoted,
                        accent: AppColors.violet,
                        onTap: () => _handleVote(0),
                      ),
                      DuelVoteCard(
                        name: options[1],
                        imageUrl: (_descriptions[options[1]]?['image'] as String?) ?? '',
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
