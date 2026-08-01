import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../analytics/analytics_constants.dart';
import '../services/vote_service.dart';
import '../services/share_helper.dart';

/// Test sayfası - Test DB'den kategoriler ve oyun
class TestPage extends StatefulWidget {
  const TestPage({super.key});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  List<TestCategory> categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      // Read from categories_test collection
      final snapshot = await FirebaseFirestore.instance
          .collection('categories_test')
          .get();

      final List<TestCategory> loadedCategories = [];
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          final name = data['name'] as String? ?? doc.id;
          final itemsText = data['items_text'] as String? ?? '';
          
          // Parse pipe-separated items
          final items = itemsText.split('|')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList();

          loadedCategories.add(TestCategory(
            id: doc.id,
            name: name,
            items: items,
          ));
        } catch (e) {
          debugPrint('Error parsing test category ${doc.id}: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        categories = loadedCategories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Kategoriler yüklenemedi. (${e.toString()})";
        _loading = false;
      });
    }
  }

  void _startGame(TestCategory category) {
    if (category.items.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu kategoride henüz yeterli öğe yok.'),
        ),
      );
      return;
    }

    // Generate pairs: (items[0],items[1]), (items[2],items[3]), ...
    final int pairCount = category.items.length ~/ 2;
    final List<Map<String, dynamic>> questions = [];
    for (int i = 0; i < pairCount; i++) {
      final int idx = i * 2;
      if (idx + 1 < category.items.length) {
        questions.add({
          'itemA': category.items[idx],
          'itemB': category.items[idx + 1],
        });
      }
    }

    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu kategoride henüz soru yok.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.testQuiz),
        builder: (_) => TestQuizPage(
          categoryName: category.name,
          categoryKey: category.id,
          questions: questions,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF3C26FF),
                Color(0xFFFF0000),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _loadCategories)
              : categories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.category, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz kategori yok',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCategories,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ListView.builder(
                          itemCount: categories.length,
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                title: Text(
                                  category.name,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${category.items.length} öğe',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                  ),
                                ),
                                trailing: const Icon(Icons.play_arrow),
                                onTap: () => _startGame(category),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}

/// Test category model
class TestCategory {
  final String id;
  final String name;
  final List<String> items;

  TestCategory({
    required this.id,
    required this.name,
    required this.items,
  });
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            )
          ],
        ),
      ),
    );
  }
}

/// Test Quiz Page - descriptions_test koleksiyonunu kullanır
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
    // Replace common Turkish characters with ASCII equivalents
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
    // Replace spaces with underscores
    normalized = normalized.replaceAll(' ', '_');
    return normalized;
  }

  // Get image URL from Firebase Storage if image_url is empty
  String _getImageUrl(String itemName) {
    final descDocId = _getDescriptionDocId(itemName);
    final desc = _descriptions[descDocId];
    
    // Log any existing image_url field, but ignore it for Test DB
    final firestoreImageUrl = desc?['image_url']?.toString() ?? '';
    if (firestoreImageUrl.isNotEmpty) {
      debugPrint('🖼️ TestQuiz image_url (ignored for Test) for $descDocId -> $firestoreImageUrl');
    }

    // Always construct URL from Firebase Storage path for Test DB
    // Path format: descriptions_test/{category_id}/{normalizedItemName}.png
    // Normalization rule matches Make.com: lowercase + Turkish strip + spaces -> underscore
    final normalizedItemName = _normalizeItemNameForStorage(itemName);
    final storagePath = 'descriptions_test/${widget.categoryKey}/$normalizedItemName.png';
    // Encode each path segment separately, then join with /
    final pathSegments = storagePath.split('/');
    final encodedSegments = pathSegments.map((segment) => Uri.encodeComponent(segment)).toList();
    final encodedPath = encodedSegments.join('%2F');
    final url = 'https://firebasestorage.googleapis.com/v0/b/bumuomu-96772.firebasestorage.app/o/$encodedPath?alt=media';
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
    
    // Vote using VoteService
    await VoteService.vote(
      widget.categoryKey,
      selected,
      opponent,
      selected,
    );

    // Sonuçları göster ve sonraki soruya geç
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

  void _showCompletionScreen() {
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
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Ana Sayfaya Dön'),
          ),
        ],
      ),
    );
  }

  Widget _buildVotingCard(String name, int index) {
    final bool isSelected = _selectedIndex == index;
    
    // Get image URL - tries image_url first, then constructs from Storage path
    final imageUrl = _getImageUrl(name);

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
                                errorWidget: (context, url, error) {
                                  debugPrint('❌ TestQuiz image load error for $url -> $error');
                                  return const Icon(Icons.error);
                                },
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

                      final List<String> normalized = List.from(_currentOptions)..sort();
                      final bool thisIsA = name == normalized[0];

                      final pct = thisIsA
                          ? (aCount / total * 100).round()
                          : (bCount / total * 100).round();

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
