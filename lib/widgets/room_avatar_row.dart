import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Participant avatars (initials — no real photos in this app) for a room's
/// current question: start lined up in the middle, animate toward the side
/// ('a'/'b') the participant voted for. When more than one person shares the
/// same state (unvoted, or voted the same way), they're laid out side by
/// side in a row instead of stacking on top of each other (fixed per user
/// feedback: "kişilerin profilleri üst üste biniyor... ortaya dizilmiş gibi
/// olacak, sırada gibi bir şey").
class RoomAvatarRow extends StatelessWidget {
  final Map<String, String> names; // uid -> display name
  final Map<String, String> choices; // uid -> 'a' | 'b'
  final String selfUid;

  const RoomAvatarRow({
    super.key,
    required this.names,
    required this.choices,
    required this.selfUid,
  });

  static const double _avatarSize = 36;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final uids = names.keys.toList()..sort();
    if (uids.isEmpty) return const SizedBox.shrink();

    final topGroup = uids.where((u) => choices[u] == 'a').toList();
    final bottomGroup = uids.where((u) => choices[u] == 'b').toList();
    final centerGroup = uids.where((u) => choices[u] != 'a' && choices[u] != 'b').toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0;

        Widget rowOf(List<String> group, double centerYFraction) {
          final children = <Widget>[];
          final rowWidth = group.length * _avatarSize + (group.length - 1) * _gap;
          final startX = (width - rowWidth) / 2;
          final centerY = height * centerYFraction;
          for (int i = 0; i < group.length; i++) {
            final uid = group[i];
            final left = (startX + i * (_avatarSize + _gap))
                .clamp(0.0, (width - _avatarSize).clamp(0.0, double.infinity));
            final top = (centerY - _avatarSize / 2)
                .clamp(0.0, (height - _avatarSize).clamp(0.0, double.infinity));
            children.add(AnimatedPositioned(
              key: ValueKey(uid),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutBack,
              left: left,
              top: top,
              width: _avatarSize,
              height: _avatarSize,
              child: _Avatar(name: names[uid] ?? '?', isSelf: uid == selfUid),
            ));
          }
          return Stack(children: children);
        }

        return Stack(
          children: [
            rowOf(topGroup, 0.075),
            rowOf(centerGroup, 0.5),
            rowOf(bottomGroup, 0.925),
          ],
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  final bool isSelf;

  const _Avatar({required this.name, required this.isSelf});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelf ? AppColors.yellow : AppColors.cloud,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.night, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6),
        ],
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.night,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}
