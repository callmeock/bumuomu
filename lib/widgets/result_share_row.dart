import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../services/share_helper.dart';

/// Share + "follow on Instagram" row shown at a result moment (tournament
/// win, quiz completion). Closes the app↔Instagram loop gap flagged in
/// Acrodix app #5 (7 months of Instagram posting with no follower growth
/// because there was no two-way loop) by putting a follow CTA right where
/// a user is already feeling good about the app.
class ResultShareRow extends StatelessWidget {
  final Future<bool> Function(BuildContext context) onShare;

  const ResultShareRow({super.key, required this.onShare});

  Future<void> _openInstagram(BuildContext context) async {
    final uri = Uri.parse(ShareHelper.instagramUrl);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    } catch (e) {
      debugPrint('❌ Instagram açılamadı: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Instagram açılamadı.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        OutlinedButton.icon(
          onPressed: () => onShare(context),
          icon: const Icon(Icons.share, size: 18),
          label: const Text('Paylaş'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.cloud,
            side: const BorderSide(color: AppColors.cloud),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => _openInstagram(context),
          icon: const Icon(Icons.camera_alt_outlined, size: 18),
          label: const Text('Bizi takip et'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.mint,
            side: const BorderSide(color: AppColors.mint),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}
