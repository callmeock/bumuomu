import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Gradient mode-picker card (emoji + title + subtitle + chevron). Shared
/// between Solo Oyna's hub and Oda Kur's mode picker so both look the same
/// (user feedback: "Oda Kur'daki favori ve sınırsız mod ui'ları da solodaki
/// gibi olsun").
class ModeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Gradient gradient;
  final Color foreground;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.foreground = AppColors.cloud,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.8),
                        fontSize: 12.5,
                      )),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: foreground.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }
}
