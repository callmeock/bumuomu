import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Color-blocked category tile (Konsept 3's home-screen grid) with an
/// optional "Yeni" freshness tag.
///
/// The freshness tag is a cheap, purely-visual mitigation for the #1
/// corroborated marketing finding (content/question staleness) — see
/// Acrodix app #5 notes #40/#41/#42. Categories are always playable (no
/// watch-to-unlock gate — that moved to CompletionAdFlow, shown
/// automatically after finishing instead).
class CategoryTile extends StatelessWidget {
  final String title;
  final String emoji;
  final int colorIndex;
  final bool isNew;
  final VoidCallback onTap;

  const CategoryTile({
    super.key,
    required this.title,
    required this.colorIndex,
    required this.onTap,
    this.emoji = '🎲',
    this.isNew = false,
    // Kept for callers migrating off the old lock UI; no longer rendered.
    bool isLocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.categoryForeground(colorIndex);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 108),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: AppTheme.categoryGradient(colorIndex),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (isNew)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.yellow,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: const Text(
                    'YENİ',
                    style: TextStyle(
                      color: Color(0xFF3B2400),
                      fontWeight: FontWeight.w900,
                      fontSize: 9,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
