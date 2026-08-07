import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../analytics/analytics_constants.dart';
import '../services/analytics_helper.dart';
import '../theme/app_theme.dart';
import '../unlimited_mode.dart';

/// "Sizden Gelenler" — kullanıcı katkılı soru modu.
///
/// V1 kapsamı: AI moderasyonu ve Cloud Functions yok, tamamen manuel onay
/// (bkz. admin_review_page.dart). Onaylanan sorular kendi ayrı koleksiyon
/// setinde ([sgQuestionsCollection] vb.) yaşar, mevcut Sınırsız Mod içeriğine
/// karışmaz.
const String sgSubmittedCollection = 'submitted_questions';
const String sgQuestionsCollection = 'sizden_gelenler_questions';
const String sgPollsCollection = 'sizden_gelenler_polls';
const String sgUsersCollection = 'sizden_gelenler_users';

const int sgMaxPendingPerUser = 5;
const int sgMaxQuestionLength = 140;
const int sgMaxOptionLength = 60;
const Duration sgSubmitCooldown = Duration(minutes: 10);

class SizdenGelenlerPage extends StatefulWidget {
  const SizdenGelenlerPage({super.key});

  @override
  State<SizdenGelenlerPage> createState() => _SizdenGelenlerPageState();
}

class _SizdenGelenlerPageState extends State<SizdenGelenlerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    AnalyticsHelper.screenView(
      screenName: AnalyticsScreenNames.sizdenGelenler,
      source: AnalyticsScreenNames.soloHub,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sizden Gelenler'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.cloud,
          unselectedLabelColor: AppColors.mist,
          indicatorColor: AppColors.mint,
          tabs: const [
            Tab(text: 'Oyna'),
            Tab(text: 'Soru Gönder'),
            Tab(text: 'Gönderdiklerim'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _PlayTab(),
          _SubmitTab(onSubmitted: () => _tabController.animateTo(2)),
          const _MySubmissionsTab(),
        ],
      ),
    );
  }
}

class _PlayTab extends StatelessWidget {
  const _PlayTab();

  void _openPlay(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AnalyticsScreenNames.sizdenGelenler),
        builder: (_) => const UnlimitedModePage(
          analyticsSource: 'sizden_gelenler',
          questionsCollection: sgQuestionsCollection,
          pollsCollection: sgPollsCollection,
          usersCollection: sgUsersCollection,
          gameMode: 'sizden_gelenler',
          title: 'Sizden Gelenler',
          emoji: '🙋',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🙋', style: TextStyle(fontSize: 56)),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'Diğer kullanıcıların gönderip onaylanan sorularını oyna',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.cloud,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'A ya da B — hangisini seçerdin?',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.mist),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton.icon(
            onPressed: () => _openPlay(context),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Oyna'),
          ),
        ],
      ),
    );
  }
}

class _SubmitTab extends StatefulWidget {
  final VoidCallback onSubmitted;
  const _SubmitTab({required this.onSubmitted});

  @override
  State<_SubmitTab> createState() => _SubmitTabState();
}

class _SubmitTabState extends State<_SubmitTab> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _optionAController = TextEditingController();
  final _optionBController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _questionController.dispose();
    _optionAController.dispose();
    _optionBController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? v, int maxLength) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Bu alan boş olamaz';
    if (value.length > maxLength) return 'En fazla $maxLength karakter';
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final pendingSnap = await FirebaseFirestore.instance
          .collection(sgSubmittedCollection)
          .where('uid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .get();

      if (pendingSnap.docs.length >= sgMaxPendingPerUser) {
        throw Exception(
            'İncelenmeyi bekleyen çok fazla sorun var. Onaylanmasını bekle veya sonra tekrar dene.');
      }

      final doc = await FirebaseFirestore.instance.collection(sgSubmittedCollection).add({
        'uid': user.uid,
        'question': _questionController.text.trim(),
        'optionA': _optionAController.text.trim(),
        'optionB': _optionBController.text.trim(),
        'status': 'pending',
        'rejectionReason': null,
        'reviewedBy': null,
        'reviewedAt': null,
        'publishedQuestionId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await AnalyticsHelper.submissionCreated(submissionId: doc.id);

      if (!mounted) return;
      _questionController.clear();
      _optionAController.clear();
      _optionBController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sorun gönderildi! İncelendikten sonra oynanabilir olacak.')),
      );
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gönderilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kendi ikilemini gönder',
              style: TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Onaylanırsa "Sizden Gelenler" modunda diğer kullanıcılar tarafından oynanır.',
              style: TextStyle(color: AppColors.mist),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextFormField(
              controller: _questionController,
              maxLength: sgMaxQuestionLength,
              decoration: const InputDecoration(
                labelText: 'Soru / bağlam',
                hintText: 'Örn: Hayatın boyunca sadece...',
                border: OutlineInputBorder(),
              ),
              validator: (v) => _requiredValidator(v, sgMaxQuestionLength),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _optionAController,
              maxLength: sgMaxOptionLength,
              decoration: const InputDecoration(
                labelText: 'Seçenek A',
                border: OutlineInputBorder(),
              ),
              validator: (v) => _requiredValidator(v, sgMaxOptionLength),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _optionBController,
              maxLength: sgMaxOptionLength,
              decoration: const InputDecoration(
                labelText: 'Seçenek B',
                border: OutlineInputBorder(),
              ),
              validator: (v) => _requiredValidator(v, sgMaxOptionLength),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Gönder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MySubmissionsTab extends StatelessWidget {
  const _MySubmissionsTab();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Giriş yapılmadı.', style: TextStyle(color: AppColors.mist)));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(sgSubmittedCollection)
          .where('uid', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('Yüklenemedi: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.mist), textAlign: TextAlign.center),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Henüz bir soru göndermedin. "Soru Gönder" sekmesinden başlayabilirsin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.mist),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => _SubmissionCard(doc: docs[index]),
        );
      },
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _SubmissionCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final status = (data['status'] ?? 'pending') as String;
    final question = (data['question'] ?? '') as String;
    final optionA = (data['optionA'] ?? '') as String;
    final optionB = (data['optionB'] ?? '') as String;
    final rejectionReason = data['rejectionReason'] as String?;
    final publishedQuestionId = data['publishedQuestionId'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    question,
                    style: const TextStyle(color: AppColors.cloud, fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('$optionA  vs  $optionB', style: const TextStyle(color: AppColors.mist)),
            if (status == 'rejected' && rejectionReason != null && rejectionReason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Sebep: $rejectionReason',
                  style: const TextStyle(color: AppColors.coral, fontSize: 12)),
            ],
            if (status == 'approved' && publishedQuestionId != null) ...[
              const SizedBox(height: AppSpacing.md),
              _LiveStats(questionId: publishedQuestionId),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color color;
    switch (status) {
      case 'approved':
        label = 'Onaylandı';
        color = AppColors.mint;
        break;
      case 'rejected':
        label = 'Reddedildi';
        color = AppColors.coral;
        break;
      default:
        label = 'Beklemede';
        color = AppColors.yellow;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}

class _LiveStats extends StatelessWidget {
  final String questionId;
  const _LiveStats({required this.questionId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection(sgPollsCollection).doc(questionId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Oy verisi okunamadı: ${snapshot.error}',
              style: const TextStyle(color: AppColors.coral, fontSize: 11));
        }
        final data = snapshot.data?.data();
        final aCount = (data?['aCount'] ?? 0) as int;
        final bCount = (data?['bCount'] ?? 0) as int;
        final total = aCount + bCount;
        if (total == 0) {
          return const Text('Henüz oy yok.', style: TextStyle(color: AppColors.mistDim, fontSize: 12));
        }
        final pctA = ((aCount / total) * 100).round();
        final pctB = 100 - pctA;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$total oy', style: const TextStyle(color: AppColors.mistDim, fontSize: 12)),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: pctA / 100,
                minHeight: 8,
                backgroundColor: AppColors.coral.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(AppColors.violet),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('A: %$pctA   B: %$pctB', style: const TextStyle(color: AppColors.mist, fontSize: 12)),
          ],
        );
      },
    );
  }
}
