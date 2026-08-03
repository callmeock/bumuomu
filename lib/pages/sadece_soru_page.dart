import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';
import '../widgets/category_tile.dart';
import 'dilemma_duel_page.dart';

/// "Sadece Soru" picker — lists dilemma-type categories (`categories` docs
/// with `type: 'dilemma'`), auto-enters if there's exactly one, otherwise
/// shows a grid like Favorin Hangisi's.
class SadeceSoruPage extends StatefulWidget {
  const SadeceSoruPage({super.key});

  @override
  State<SadeceSoruPage> createState() => _SadeceSoruPageState();
}

class _SadeceSoruPageState extends State<SadeceSoruPage> {
  bool _loading = true;
  String? _error;
  List<Category> _sets = [];
  bool _autoEntered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .where('type', isEqualTo: 'dilemma')
          .get();
      final sets = <Category>[];
      for (final doc in snap.docs) {
        try {
          final c = Category.fromFirestore(doc);
          if (c.items.length >= 2) sets.add(c);
        } catch (e) {
          debugPrint('Error parsing dilemma category ${doc.id}: $e');
        }
      }
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'İkilemler yüklenemedi. (${e.toString()})';
        _loading = false;
      });
    }
  }

  List<Map<String, String>> _pairsFor(Category c) {
    final pairs = <Map<String, String>>[];
    final n = c.items.length ~/ 2;
    for (int i = 0; i < n; i++) {
      final idx = i * 2;
      if (idx + 1 < c.items.length) {
        pairs.add({'a': c.items[idx], 'b': c.items[idx + 1]});
      }
    }
    return pairs;
  }

  void _openSet(Category c) {
    final pairs = _pairsFor(c);
    if (pairs.isEmpty) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DilemmaDuelPage(
          categoryName: c.name,
          categoryKey: c.id,
          pairs: pairs,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _error == null && _sets.length == 1 && !_autoEntered) {
      _autoEntered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSet(_sets.first);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sadece Soru')),
      body: _loading || (_sets.length == 1 && _error == null)
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.mist),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.mist)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tekrar Dene'),
                        ),
                      ],
                    ),
                  ),
                )
              : _sets.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.forum_outlined, size: 56, color: AppColors.mistDim),
                            SizedBox(height: 16),
                            Text(
                              'Henüz ikilem eklenmedi',
                              style: TextStyle(
                                color: AppColors.cloud,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Yakında burada "hayatın boyunca sadece..." tarzı\nsoru ikilemleri olacak.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.mist),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.15,
                        ),
                        itemCount: _sets.length,
                        itemBuilder: (context, index) {
                          final c = _sets[index];
                          return CategoryTile(
                            title: c.name,
                            emoji: '💭',
                            colorIndex: index,
                            onTap: () => _openSet(c),
                          );
                        },
                      ),
                    ),
    );
  }
}
