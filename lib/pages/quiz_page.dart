import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart';
import '../services/vote_service.dart';
import '../services/share_helper.dart';

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
    // Eğer string ise, basit bir format oluştur
    if (q is String) {
      return {'text': q, 'optionA': '', 'optionB': ''};
    }
    return null;
  }

  List<String> get _currentOptions {
    final q = _currentQuestion;
    if (q == null) return [];
    
    // Debug: Soru formatını logla
    debugPrint('🔍 Quiz soru formatı: $q');
    
    // Farklı field isimlerini dene
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
    
    // Eğer hala boşsa, soru objesinin tüm key'lerini göster
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


  void _showCompletionScreen() {
    // Analytics: Quiz tamamlandı
    AnalyticsHelper.quizCompleted(
      categoryKey: widget.categoryKey,
      categoryName: widget.categoryName,
      totalQuestions: totalQuestions,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('🎉 Tebrikler!'),
        content: Text(
          '${widget.categoryName} kategorisindeki tüm soruları tamamladın!',
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                ShareHelper.shareQuizCompleted(categoryName: widget.categoryName),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Paylaş'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Dialog'u kapat
              Navigator.pop(context); // Quiz sayfasından çık
            },
            child: const Text('Ana Sayfaya Dön'),
          ),
        ],
      ),
    );
  }

  Widget _buildVotingCard(String name, int index) {
    final bool isSelected = _selectedIndex == index;
    final desc = _descriptions[name];
    final imageUrl = desc?['image'] ?? '';

    // Overlay yoğunluğu: seçilmeyen kart = tam; seçilen (kazanan) = yarım
    final double overlayOpacity = _hasVoted ? (isSelected ? 0.05 : 0.80) : 0.0;

    return GestureDetector(
      onTap: _hasVoted ? null : () => _handleVote(index),
      child: AnimatedScale(
        scale: isSelected ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.4,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Stack(
              children: [
                // Arkaplan içerik (başlık + görsel)
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Text(
                        name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                placeholder: (context, url) =>
                                    const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            : Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Icon(Icons.image, size: 64),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),

                // Overlay efekt
                if (overlayOpacity > 0)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          color: Colors.black.withOpacity(overlayOpacity),
                        ),
                      ),
                    ),
                  ),

                // Yüzdelik yazısı — overlay'in ÜSTÜNDE
                if (_hasVoted)
                  StreamBuilder<Map<String, int>>(
                    stream: VoteService.getVoteCountsStream(
                      widget.categoryKey,
                      _currentOptions[0],
                      _currentOptions[1],
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }
                      final counts = snapshot.data!;
                      final aCount = counts['aCount'] ?? 0;
                      final bCount = counts['bCount'] ?? 0;
                      final total = aCount + bCount;
                      if (total == 0) return const SizedBox.shrink();

                      // Determine which item is 'a' (normalized order)
                      final List<String> normalized = List.from(_currentOptions)..sort();
                      final bool thisIsA = name == normalized[0];

                      final pct = thisIsA
                          ? (aCount / total * 100).round()
                          : (bCount / total * 100).round();

                      // Renkler: eşitse mavi, kazanan yeşil, kaybeden kırmızı
                      Color textColor;
                      if (aCount == bCount) {
                        textColor = Colors.blue;
                      } else {
                        final thisCount = thisIsA ? aCount : bCount;
                        final oppCount = thisIsA ? bCount : aCount;
                        textColor = (thisCount > oppCount)
                            ? const Color(0xFF008000)
                            : Colors.red;
                      }

                      return Center(
                        child: Text(
                          "%$pct",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            shadows: const [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black,
                                offset: Offset(2, 2),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDescriptions || _currentQuestion == null) {
      return Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.red, Colors.red, Colors.blue, Colors.blue],
              stops: [0.0, 0.49, 0.51, 1.0],
            ),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.red, Colors.red, Colors.blue, Colors.blue],
            stops: [0.0, 0.49, 0.51, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildVotingCard(options[0], 0),
                  _buildVotingCard(options[1], 1),
                ],
              ),
              // İlerleme göstergesi
              IgnorePointer(
                ignoring: true,
                child: Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(0, -16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        color: Colors.black.withOpacity(0.30),
                        child: Text(
                          "$currentQuestionNumber / $totalQuestions",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black,
                                offset: Offset(1, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

