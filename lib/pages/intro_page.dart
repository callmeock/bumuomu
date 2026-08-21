import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../analytics/analytics_constants.dart';
import '../services/analytics_helper.dart';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late final DateTime _introOpenedAt;

  final List<IntroSlide> _slides = [
    IntroSlide(
      title: 'Hoş Geldin! 👋',
      description: 'Bu mu O mu? ile eğlenceli anketler dünyasına adım at!',
      icon: Icons.waving_hand,
      color: Colors.orange,
    ),
    IntroSlide(
      title: 'Sınırsız Mod ♾️',
      description:
          'Bitmeyen sorular, anlık oy ver! Akış hiç durmasın, sürekli yeni sorularla karşılaş.',
      icon: Icons.all_inclusive,
      color: Colors.purple,
      details: [
        'Soru ve iki seçenek',
        'Geniş soru havuzu',
        'Anlık oy sonuçları',
        'Sürekli yeni içerik',
      ],
    ),
    IntroSlide(
      title: 'Favorin Hangisi? 🏆',
      description:
          '32\'li elemeler yap, turnuva formatında oyna! Her turda iki seçenek arasında seçim yap, en favorini bul.',
      icon: Icons.emoji_events,
      color: Colors.blue,
      details: [
        '32 öğe turnuva',
        'Her turda eleme',
        'Kazanan bir sonraki tura',
        'Son favorini bul',
      ],
    ),
    IntroSlide(
      title: 'Kategoriler 📚',
      description:
          'Spesifik kategorilerde soruları cevapla! Abur cubur, sporcular gibi konularda derinlemesine oy ver.',
      icon: Icons.category,
      color: Colors.green,
      details: [
        'Kategori bazlı sorular',
        'Spesifik konular',
        'Detaylı oy verme',
        'Kategori bazlı istatistikler',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _introOpenedAt = DateTime.now();
    AnalyticsHelper.screenView(
      screenName: AnalyticsScreenNames.intro,
      source: null,
    );
  }

  @override
  void dispose() {
    final ms = DateTime.now().difference(_introOpenedAt).inMilliseconds;
    AnalyticsHelper.screenExit(
      screenName: AnalyticsScreenNames.intro,
      durationMs: ms,
    );
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeIntro({required String method}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_completed', true);
    AnalyticsHelper.onboardingCompleted(method: method);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/main');
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeIntro(method: 'completed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1a1a2e),
              Color(0xFF16213e),
              Color(0xFF0f3460),
            ],
          ),
        ),
        child: SafeArea(
        child: Column(
          children: [
            // Skip button
            if (_currentPage > 0)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextButton(
                    onPressed: () => _completeIntro(method: 'skipped'),
                    child: const Text(
                      'Atla',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  return _IntroSlideWidget(slide: _slides[index]);
                },
              ),
            ),
            // Page indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.orange
                        : Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Next/Start button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _currentPage == _slides.length - 1
                        ? 'Başlayalım!'
                        : 'Devam Et',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
        ),
      ),
    );
  }
}

class IntroSlide {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<String>? details;

  IntroSlide({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.details,
  });
}

class _IntroSlideWidget extends StatelessWidget {
  final IntroSlide slide;

  const _IntroSlideWidget({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: slide.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 64,
              color: slide.color,
            ),
          ),
          const SizedBox(height: 48),
          // Title
          Text(
            slide.title,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Description
          Text(
            slide.description,
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withOpacity(0.8),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          // Details list
          if (slide.details != null) ...[
            const SizedBox(height: 32),
            ...slide.details!.map((detail) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: slide.color,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

