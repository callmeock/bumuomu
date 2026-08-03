import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../services/vote_service.dart';

/// Top bar shown above a duel: back button, category pill, streak chip and
/// an optional round-progress track (e.g. "3. tur" in a tournament).
class DuelHeaderBar extends StatelessWidget {
  final String categoryName;
  final int streakCount;
  final String? roundLabel;
  final double? roundProgress; // 0.0 - 1.0

  const DuelHeaderBar({
    super.key,
    required this.categoryName,
    this.streakCount = 0,
    this.roundLabel,
    this.roundProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Chip(
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 16, color: AppColors.cloud),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const Spacer(),
              _Chip(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text(categoryName,
                      style: const TextStyle(
                        color: AppColors.cloud,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      )),
                ),
              ),
              const Spacer(),
              if (streakCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text('🔥 $streakCount',
                      style: const TextStyle(
                        color: Color(0xFF3B2400),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      )),
                )
              else
                const SizedBox(width: 34),
            ],
          ),
          if (roundLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              roundLabel!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mist,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
            if (roundProgress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: roundProgress!.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppColors.cloud.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Widget child;
  const _Chip({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.night2,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: child,
    );
  }
}

/// Small circular "VS" badge meant to sit between the two duel cards.
class VsBadge extends StatelessWidget {
  const VsBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.night,
        shape: BoxShape.circle,
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.yellow, width: 3),
        ),
      ),
      child: const Text(
        'VS',
        style: TextStyle(
          color: AppColors.cloud,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// One side of a duel: image, title, tap-to-vote, and (post-vote) a thin
/// result bar instead of a screen-filling percentage number.
///
/// Wraps the live vote-count stream with explicit loading/error/retry states
/// (Acrodix app #5, bizdev backlog #1) so a Firestore hiccup on bumuomu's one
/// real differentiator — the live reveal — degrades visibly instead of
/// silently.
class DuelVoteCard extends StatefulWidget {
  final String name;
  final String imageUrl;
  final String opponentName;
  final String categoryKey;
  final bool isSelected;
  final bool hasVoted;
  final bool enabled;
  final Color accent;
  final VoidCallback? onTap;

  const DuelVoteCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.opponentName,
    required this.categoryKey,
    required this.isSelected,
    required this.hasVoted,
    required this.accent,
    this.enabled = true,
    this.onTap,
  });

  @override
  State<DuelVoteCard> createState() => _DuelVoteCardState();
}

class _DuelVoteCardState extends State<DuelVoteCard> {
  int _retryToken = 0;

  @override
  Widget build(BuildContext context) {
    final overlayOpacity =
        widget.hasVoted ? (widget.isSelected ? 0.0 : 0.55) : 0.0;

    return GestureDetector(
      onTap: widget.enabled && !widget.hasVoted ? widget.onTap : null,
      child: AnimatedScale(
        scale: widget.isSelected ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.32,
              width: double.infinity,
              color: AppColors.night2,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImage(),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (overlayOpacity > 0)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      color: Colors.black.withValues(alpha: overlayOpacity),
                    ),
                  Positioned(
                    left: AppSpacing.lg,
                    right: AppSpacing.lg,
                    bottom: AppSpacing.md,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            color: AppColors.cloud,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        if (widget.hasVoted) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _buildResult(),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    top: AppSpacing.md,
                    left: AppSpacing.md,
                    child: Container(
                      width: 6,
                      height: 28,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (widget.imageUrl.isEmpty) {
      return const ColoredBox(
        color: AppColors.night2,
        child: Center(
          child: Icon(Icons.image_outlined, size: 48, color: AppColors.mistDim),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      errorWidget: (context, url, error) {
        debugPrint('❌ DuelVoteCard image load error for $url -> $error');
        return const ColoredBox(
          color: AppColors.night2,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                size: 40, color: AppColors.mistDim),
          ),
        );
      },
    );
  }

  Widget _buildResult() {
    return StreamBuilder<Map<String, int>>(
      key: ValueKey(_retryToken),
      stream: VoteService.getVoteCountsStream(
        widget.categoryKey,
        widget.name,
        widget.opponentName,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 14,
            child: LinearProgressIndicator(
              minHeight: 4,
              backgroundColor: Color(0x22F7F3FF),
              valueColor: AlwaysStoppedAnimation(AppColors.mistDim),
            ),
          );
        }
        if (snapshot.hasError) {
          debugPrint('❌ Vote count stream error: ${snapshot.error}');
          return GestureDetector(
            onTap: () => setState(() => _retryToken++),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh, size: 14, color: AppColors.mist),
                SizedBox(width: 4),
                Text('Sonuçlar yüklenemedi, tekrar dene',
                    style: TextStyle(color: AppColors.mist, fontSize: 11)),
              ],
            ),
          );
        }

        final counts = snapshot.data ?? const {'aCount': 0, 'bCount': 0};
        final aCount = counts['aCount'] ?? 0;
        final bCount = counts['bCount'] ?? 0;
        final total = aCount + bCount;
        if (total == 0) return const SizedBox.shrink();

        final normalized = [widget.name, widget.opponentName]..sort();
        final thisIsA = widget.name == normalized[0];
        final pct = thisIsA
            ? (aCount / total * 100).round()
            : (bCount / total * 100).round();

        return Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 8,
                  backgroundColor: AppColors.cloud.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(widget.accent),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '%$pct',
              style: const TextStyle(
                color: AppColors.cloud,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
      },
    );
  }
}
