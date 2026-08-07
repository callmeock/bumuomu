import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/admin_config.dart';
import '../services/analytics_helper.dart';
import '../theme/app_theme.dart';
import 'sizden_gelenler_page.dart' show sgSubmittedCollection, sgQuestionsCollection;

/// Günlük AI rutininin ürettiği ikilem önerileri (bkz. plan:
/// "Günlük AI içerik üretim hattı"). Onaylanınca `categories` koleksiyonuna
/// `type: 'dilemma'` dokümanı olarak yayınlanır.
const String sdSubmittedDilemmasCollection = 'submitted_dilemmas';
const String sdCategoriesCollection = 'categories';

/// Günlük AI rutininin ürettiği "Favorini Bul" kategori fikirleri. Bunlar
/// 32 gerçek görsel gerektirdiği için AI tarafından tamamlanamaz — onay,
/// sadece "kabul ediyorum, görselleri ben tamamlayacağım" anlamına gelir;
/// hiçbir zaman otomatik olarak canlıya alınmaz.
const String sdSubmittedCategoryIdeasCollection = 'submitted_category_ideas';

/// "Sizden Gelenler" kullanıcı gönderimleri her zaman [sgQuestionsCollection]'a
/// yayınlanır; AI günlük rutini ise `targetCollection` alanıyla gerçek
/// Sınırsız Mod havuzunu hedefleyebilir. Kapalı bir allowlist — onay eylemi
/// yüksek yetkiyle çalıştığı için bu alanı serbestçe güvenmek risklidir.
const Set<String> approvableQuestionTargets = {'unlimited_questions'};

/// "Sizden Gelenler" + günlük AI içerik önerileri onay kuyruğu — sadece
/// sahibin UID'i ile erişilebilir. 3 sekme: Sorular / İkilemler / Kategori
/// Fikirleri.
///
/// Bu ekranın gizli olması sadece UX içindir; gerçek yetki sınırı Firestore
/// Rules'da aynı UID ile ayrıca tanımlanmalı (bkz. SIZDEN_GELENLER_SETUP.md).
class AdminReviewPage extends StatelessWidget {
  const AdminReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!AdminConfig.isOwner(uid)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Erişim yok')),
        body: const Center(
          child: Text('Bu ekrana erişim yetkiniz yok.', style: TextStyle(color: AppColors.mist)),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('İnceleme Kuyruğu'),
          bottom: const TabBar(
            labelColor: AppColors.cloud,
            unselectedLabelColor: AppColors.mist,
            indicatorColor: AppColors.mint,
            tabs: [
              Tab(text: 'Sorular'),
              Tab(text: 'İkilemler'),
              Tab(text: 'Kategori Fikirleri'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _QuestionsTab(),
            _DilemmasTab(),
            _CategoryIdeasTab(),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, style: const TextStyle(color: AppColors.mist)));
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  const _ErrorState(this.error);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Yüklenemedi: $error', style: const TextStyle(color: AppColors.mist)),
    );
  }
}

// ============================== Sorular ==============================

class _QuestionsTab extends StatelessWidget {
  const _QuestionsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(sgSubmittedCollection)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorState(snapshot.error!);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const _EmptyState('Bekleyen soru yok 🎉');
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _QuestionCard(doc: docs[index]),
        );
      },
    );
  }
}

class _QuestionCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _QuestionCard({required this.doc});

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _busy = false;

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final id = widget.doc.id;
    final data = widget.doc.data();
    try {
      final rawTarget = data['targetCollection'] as String?;
      final targetCollection = (rawTarget != null && approvableQuestionTargets.contains(rawTarget))
          ? rawTarget
          : sgQuestionsCollection;

      final batch = FirebaseFirestore.instance.batch();
      final publishedRef = FirebaseFirestore.instance.collection(targetCollection).doc(id);
      batch.set(publishedRef, {
        'active': true,
        'question': data['question'],
        'optionA': data['optionA'],
        'optionB': data['optionB'],
        'weight': 1.0,
      });
      final submissionRef = FirebaseFirestore.instance.collection(sgSubmittedCollection).doc(id);
      batch.update(submissionRef, {
        'status': 'approved',
        'publishedQuestionId': id,
        'reviewedBy': ownerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      await AnalyticsHelper.submissionApproved(submissionId: id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Onaylanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = await _askRejectionReason(context);
    if (reason == null) return;

    setState(() => _busy = true);
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final id = widget.doc.id;
    try {
      await FirebaseFirestore.instance.collection(sgSubmittedCollection).doc(id).update({
        'status': 'rejected',
        'rejectionReason': reason.isEmpty ? null : reason,
        'reviewedBy': ownerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await AnalyticsHelper.submissionRejected(submissionId: id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reddedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final question = (data['question'] ?? '') as String;
    final optionA = (data['optionA'] ?? '') as String;
    final optionB = (data['optionB'] ?? '') as String;

    return _ReviewCard(
      busy: _busy,
      onApprove: _approve,
      onReject: _reject,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question,
              style: const TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          Text('$optionA  vs  $optionB', style: const TextStyle(color: AppColors.mist)),
        ],
      ),
    );
  }
}

// ============================== İkilemler ==============================

class _DilemmasTab extends StatelessWidget {
  const _DilemmasTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(sdSubmittedDilemmasCollection)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorState(snapshot.error!);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const _EmptyState('Bekleyen ikilem yok 🎉');
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _DilemmaCard(doc: docs[index]),
        );
      },
    );
  }
}

class _DilemmaCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _DilemmaCard({required this.doc});

  @override
  State<_DilemmaCard> createState() => _DilemmaCardState();
}

class _DilemmaCardState extends State<_DilemmaCard> {
  bool _busy = false;

  List<String> get _items =>
      ((widget.doc.data()['items'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();

  Future<void> _approve() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final id = widget.doc.id;
    final data = widget.doc.data();
    try {
      final batch = FirebaseFirestore.instance.batch();
      final categoryRef = FirebaseFirestore.instance.collection(sdCategoriesCollection).doc(id);
      batch.set(categoryRef, {
        'name': data['name'],
        'type': 'dilemma',
        'mode': 'normal',
        'image': '',
        'items': _items,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final submissionRef =
          FirebaseFirestore.instance.collection(sdSubmittedDilemmasCollection).doc(id);
      batch.update(submissionRef, {
        'status': 'approved',
        'reviewedBy': ownerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Onaylanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    final reason = await _askRejectionReason(context);
    if (reason == null) return;

    setState(() => _busy = true);
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final id = widget.doc.id;
    try {
      await FirebaseFirestore.instance.collection(sdSubmittedDilemmasCollection).doc(id).update({
        'status': 'rejected',
        'rejectionReason': reason.isEmpty ? null : reason,
        'reviewedBy': ownerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reddedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final name = (data['name'] ?? '') as String;
    final items = _items;
    final pairs = <String>[];
    for (int i = 0; i + 1 < items.length; i += 2) {
      pairs.add('${items[i]}  vs  ${items[i + 1]}');
    }

    return _ReviewCard(
      busy: _busy,
      onApprove: _approve,
      onReject: _reject,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name,
              style: const TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          for (final p in pairs)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(p, style: const TextStyle(color: AppColors.mist, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ========================== Kategori Fikirleri ==========================

class _CategoryIdeasTab extends StatelessWidget {
  const _CategoryIdeasTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(sdSubmittedCategoryIdeasCollection)
          // 'accepted_awaiting_images' eski bir ara durumdan kalma — henüz o
          // durumda takılı kalmış fikirlerin de burada görünmeye devam etmesi
          // için sorguya dahil edildi. Yeni akışta artık kullanılmıyor: onay
          // artık doğrudan görsel URL'i girip yayınlamak.
          .where('status', whereIn: ['pending', 'accepted_awaiting_images'])
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return _ErrorState(snapshot.error!);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const _EmptyState('Bekleyen kategori fikri yok 🎉');
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _CategoryIdeaCard(doc: docs[index]),
        );
      },
    );
  }
}

class _CategoryIdeaCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _CategoryIdeaCard({required this.doc});

  @override
  State<_CategoryIdeaCard> createState() => _CategoryIdeaCardState();
}

class _CategoryIdeaCardState extends State<_CategoryIdeaCard> {
  bool _busy = false;

  Future<void> _reject() async {
    if (_busy) return;
    final reason = await _askRejectionReason(context);
    if (reason == null) return;

    setState(() => _busy = true);
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final id = widget.doc.id;
    try {
      await FirebaseFirestore.instance.collection(sdSubmittedCategoryIdeasCollection).doc(id).update({
        'status': 'rejected',
        'rejectionReason': reason.isEmpty ? null : reason,
        'reviewedBy': ownerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reddedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPublishForm() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _PublishCategoryPage(doc: widget.doc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final theme = (data['theme'] ?? '') as String;
    final itemNames =
        ((data['itemNames'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();

    return _ReviewCard(
      busy: _busy,
      onApprove: _openPublishForm,
      approveLabel: 'Görselleri Gir',
      onReject: _reject,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(theme,
              style: const TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: AppSpacing.sm),
          Text('${itemNames.length} öğe: ${itemNames.join(', ')}',
              style: const TextStyle(color: AppColors.mist, fontSize: 13)),
          const SizedBox(height: AppSpacing.sm),
          const Text('"Görselleri Gir" ile her öğe için bir görsel URL\'i yapıştırıp doğrudan yayınlayabilirsin.',
              style: TextStyle(color: AppColors.mistDim, fontSize: 11, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// Kategori fikrini gerçek bir "Favorini Bul" turnuvasına dönüştüren form.
/// fire-import/Excel akışını atlar — sahip her öğe için bir görsel URL'i
/// yapıştırır, "Yayınla" tam olarak doğru şemayla (`type: 'tournament'`,
/// `mode: 'normal'`) `categories` + `descriptions` dokümanlarını yazar.
class _PublishCategoryPage extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _PublishCategoryPage({required this.doc});

  @override
  State<_PublishCategoryPage> createState() => _PublishCategoryPageState();
}

/// İsimden kaba bir dosya adı tahmini üretir: küçük harfe çevirir, boşlukları
/// tireye çevirir. Türkçe karakterleri BİLEREK silmiyor — gerçek WordPress
/// yüklemelerinde (örn. "gözleme.png", "suşi.png") bazen korunuyor, bazen
/// ("dünyaca ünlü lezzetler" → "dunyaca-unlu-lezzetler.png") sadeleşiyor;
/// tutarlı bir kural yok. Bu yüzden bu sadece bir BAŞLANGIÇ tahmini — sahip
/// formda her alanı gerekirse elle düzeltebilir.
String _guessSlug(String name) {
  return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');
}

class _PublishCategoryPageState extends State<_PublishCategoryPage> {
  late final String _theme;
  late final List<String> _itemNames;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _extensionController;
  late final TextEditingController _coverFileController;
  late final List<TextEditingController> _itemFileControllers;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data();
    _theme = (data['theme'] ?? '') as String;
    _itemNames = ((data['itemNames'] as List<dynamic>?) ?? const []).map((e) => e.toString()).toList();
    _baseUrlController =
        TextEditingController(text: 'https://callmeock.com/wp-content/uploads/2026/02/');
    _extensionController = TextEditingController(text: '.webp');
    _coverFileController = TextEditingController(text: _guessSlug(_theme));
    _itemFileControllers =
        _itemNames.map((n) => TextEditingController(text: _guessSlug(n))).toList();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _extensionController.dispose();
    _coverFileController.dispose();
    for (final c in _itemFileControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _urlFor(String filename) {
    final base = _baseUrlController.text.trim();
    final ext = _extensionController.text.trim();
    return '$base$filename$ext';
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final baseUrl = _baseUrlController.text.trim();
    final coverFile = _coverFileController.text.trim();
    final itemFiles = _itemFileControllers.map((c) => c.text.trim()).toList();
    if (baseUrl.isEmpty || coverFile.isEmpty || itemFiles.any((f) => f.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taban URL, kapak ve tüm öğe dosya adları girilmeli.')),
      );
      return;
    }

    setState(() => _publishing = true);
    final ownerUid = FirebaseAuth.instance.currentUser!.uid;
    final id = widget.doc.id;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (int i = 0; i < _itemNames.length; i++) {
        final descRef = FirebaseFirestore.instance.collection('descriptions').doc(_itemNames[i]);
        batch.set(descRef, {'image': _urlFor(itemFiles[i]), 'text': ''}, SetOptions(merge: true));
      }
      final categoryRef = FirebaseFirestore.instance.collection(sdCategoriesCollection).doc(id);
      batch.set(categoryRef, {
        'name': _theme,
        'type': 'tournament',
        'mode': 'normal',
        'image': _urlFor(coverFile),
        'items': _itemNames,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final ideaRef = FirebaseFirestore.instance.collection(sdSubmittedCategoryIdeasCollection).doc(id);
      batch.update(ideaRef, {
        'status': 'published',
        'reviewedBy': ownerUid,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$_theme" yayınlandı 🎉')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yayınlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_theme)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Text('Taban URL (görsellerin bulunduğu klasör)',
              style: TextStyle(color: AppColors.mist, fontSize: 12)),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              hintText: 'https://callmeock.com/wp-content/uploads/2026/02/',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Dosya uzantısı', style: TextStyle(color: AppColors.mist, fontSize: 12)),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _extensionController,
            decoration: const InputDecoration(hintText: '.webp', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Kapak dosya adı (uzantısız)', style: TextStyle(color: AppColors.mist, fontSize: 12)),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _coverFileController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_urlFor(_coverFileController.text.trim()),
                style: const TextStyle(color: AppColors.mistDim, fontSize: 11)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('${_itemNames.length} öğe — dosya adları isimden otomatik tahmin edildi, gerekirse düzelt',
              style: const TextStyle(color: AppColors.mist, fontSize: 12)),
          const SizedBox(height: AppSpacing.sm),
          for (int i = 0; i < _itemNames.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _itemFileControllers[i],
                    decoration: InputDecoration(
                      labelText: _itemNames[i],
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_urlFor(_itemFileControllers[i].text.trim()),
                        style: const TextStyle(color: AppColors.mistDim, fontSize: 11)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _publishing ? null : _publish,
              child: _publishing
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Yayınla'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================== Ortak yardımcılar ==============================

Future<String?> _askRejectionReason(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final controller = TextEditingController();
      return AlertDialog(
        backgroundColor: AppColors.night2,
        title: const Text('Reddetme sebebi'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Örn: uygunsuz içerik, spam, anlaşılmıyor...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Reddet'),
          ),
        ],
      );
    },
  );
}

class _ReviewCard extends StatelessWidget {
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String approveLabel;
  final Widget child;

  const _ReviewCard({
    required this.busy,
    required this.onApprove,
    required this.onReject,
    this.approveLabel = 'Onayla',
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child,
            const SizedBox(height: AppSpacing.md),
            if (busy)
              const Center(child: CircularProgressIndicator(strokeWidth: 2))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close, color: AppColors.coral),
                      label: const Text('Reddet', style: TextStyle(color: AppColors.coral)),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onApprove,
                      icon: const Icon(Icons.check),
                      label: Text(approveLabel),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
