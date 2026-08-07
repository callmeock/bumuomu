import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../utils/image_url.dart';

/// Full-width category card using the category's real Firestore `image` as
/// background (pre-rebuild behavior, restored per user feedback — falls back
/// to a color-block gradient when a category has no image, e.g. some bot
/// `categories_test` entries or text-only dilemma sets). Shared between
/// Favorin Hangisi and Oda Kur's set pickers so both look the same.
class FullWidthCategoryCard extends StatelessWidget {
  final String title;
  final String imageUrl;
  final int colorIndex;
  final bool isNew;
  final VoidCallback onTap;

  const FullWidthCategoryCard({
    super.key,
    required this.title,
    required this.imageUrl,
    required this.colorIndex,
    required this.onTap,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Container(
          decoration: BoxDecoration(
            gradient: imageUrl.isEmpty ? AppTheme.categoryGradient(colorIndex) : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: safeImageUrl(imageUrl),
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const ColoredBox(color: AppColors.night2),
                  errorWidget: (context, url, error) =>
                      DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.categoryGradient(colorIndex))),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.md,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.cloud,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
              if (isNew)
                Positioned(
                  top: AppSpacing.md,
                  right: AppSpacing.md,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.yellow,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: const Text(
                      'YENİ',
                      style: TextStyle(
                        color: Color(0xFF3B2400),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: 0.4,
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
