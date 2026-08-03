import 'package:flutter/material.dart';
import '../services/vote_service.dart';
import '../services/share_helper.dart';
import '../services/completion_ad_flow.dart';
import '../theme/app_theme.dart';
import '../widgets/result_share_row.dart';

/// "Sadece Soru" — full-bleed, text-only would-you-rather dilemma duel.
/// Reference: user-supplied screenshot (red/violet split, centered VS badge,
/// X to close, "X / Y" progress). Distinct visual language from the
/// image-based DuelVoteCard on purpose — no photos here, just statements.
///
/// Reuses VoteService/generatePairId exactly like every other duel screen —
/// dilemma statements are just item text, so global % works identically to
/// solo Favorin/quiz voting (Acrodix app #5 guardrail: one counting scheme).
class DilemmaDuelPage extends StatefulWidget {
  final String categoryName;
  final String categoryKey;
  final List<Map<String, String>> pairs; // [{'a': ..., 'b': ...}, ...]

  const DilemmaDuelPage({
    super.key,
    required this.categoryName,
    required this.categoryKey,
    required this.pairs,
  });

  @override
  State<DilemmaDuelPage> createState() => _DilemmaDuelPageState();
}

class _DilemmaDuelPageState extends State<DilemmaDuelPage> {
  int _index = 0;
  bool _hasVoted = false;
  bool? _selectedIsA;

  Map<String, String> get _current => widget.pairs[_index];

  Future<void> _vote(bool isA) async {
    if (_hasVoted) return;
    setState(() {
      _hasVoted = true;
      _selectedIsA = isA;
    });

    final a = _current['a']!;
    final b = _current['b']!;
    final selected = isA ? a : b;
    final opponent = isA ? b : a;

    await VoteService.vote(widget.categoryKey, selected, opponent, selected);

    await Future.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;

    if (_index + 1 >= widget.pairs.length) {
      await _showCompletion();
    } else {
      setState(() {
        _index++;
        _hasVoted = false;
        _selectedIsA = null;
      });
    }
  }

  Future<void> _showCompletion() async {
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
          '${widget.categoryName} ikilemlerinin tümünü tamamladın!',
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
      Navigator.pop(context);
      Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pair = _current;
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _DilemmaHalf(
                  text: pair['a']!,
                  gradient: AppTheme.sideBGradient,
                  isSelected: _selectedIsA == true,
                  dimmed: _hasVoted && _selectedIsA != true,
                  onTap: _hasVoted ? null : () => _vote(true),
                  showResult: _hasVoted,
                  categoryKey: widget.categoryKey,
                  thisText: pair['a']!,
                  opponentText: pair['b']!,
                ),
              ),
              Expanded(
                child: _DilemmaHalf(
                  text: pair['b']!,
                  gradient: AppTheme.sideAGradient,
                  isSelected: _selectedIsA == false,
                  dimmed: _hasVoted && _selectedIsA != false,
                  onTap: _hasVoted ? null : () => _vote(false),
                  showResult: _hasVoted,
                  categoryKey: widget.categoryKey,
                  thisText: pair['b']!,
                  opponentText: pair['a']!,
                ),
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.sm,
            left: AppSpacing.lg,
            child: _RoundIconButton(
              icon: Icons.close,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _VsCircle(),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.pairs.length}',
                    style: const TextStyle(
                      color: AppColors.cloud,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DilemmaHalf extends StatelessWidget {
  final String text;
  final Gradient gradient;
  final bool isSelected;
  final bool dimmed;
  final VoidCallback? onTap;
  final bool showResult;
  final String categoryKey;
  final String thisText;
  final String opponentText;

  const _DilemmaHalf({
    required this.text,
    required this.gradient,
    required this.isSelected,
    required this.dimmed,
    required this.onTap,
    required this.showResult,
    required this.categoryKey,
    required this.thisText,
    required this.opponentText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: double.infinity,
        decoration: BoxDecoration(gradient: gradient),
        child: Stack(
          children: [
            if (dimmed)
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.cloud,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            if (showResult)
              Positioned(
                bottom: AppSpacing.xl,
                left: 0,
                right: 0,
                child: Center(
                  child: _DilemmaResultBadge(
                    categoryKey: categoryKey,
                    thisText: thisText,
                    opponentText: opponentText,
                    isSelected: isSelected,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DilemmaResultBadge extends StatelessWidget {
  final String categoryKey;
  final String thisText;
  final String opponentText;
  final bool isSelected;

  const _DilemmaResultBadge({
    required this.categoryKey,
    required this.thisText,
    required this.opponentText,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, int>>(
      stream: VoteService.getVoteCountsStream(categoryKey, thisText, opponentText),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cloud),
          );
        }
        final counts = snapshot.data!;
        final aCount = counts['aCount'] ?? 0;
        final bCount = counts['bCount'] ?? 0;
        final total = aCount + bCount;
        if (total == 0) return const SizedBox.shrink();

        final normalized = [thisText, opponentText]..sort();
        final thisIsA = thisText == normalized[0];
        final pct = thisIsA
            ? (aCount / total * 100).round()
            : (bCount / total * 100).round();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.yellow : Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            '%$pct seçti',
            style: TextStyle(
              color: isSelected ? const Color(0xFF3B2400) : AppColors.cloud,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        );
      },
    );
  }
}

class _VsCircle extends StatelessWidget {
  const _VsCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.cloud,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12),
        ],
      ),
      child: const Text(
        'VS',
        style: TextStyle(
          color: AppColors.night,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.cloud, size: 20),
      ),
    );
  }
}
