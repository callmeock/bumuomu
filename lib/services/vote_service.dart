import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Service for handling votes in the new schema
/// Uses votes/{categoryId}/pairs/{pairId} structure
class VoteService {
  /// Generate deterministic pairId from two item IDs
  /// Normalizes order (lexicographically sorted) and creates SHA1 hash
  static String generatePairId(String aId, String bId) {
    // Normalize: sort lexicographically
    final List<String> normalized = [aId, bId]..sort();
    final String combined = '${normalized[0]}|${normalized[1]}';
    
    // Generate SHA1 hash
    final bytes = utf8.encode(combined);
    final digest = sha1.convert(bytes);
    final hashString = digest.toString();
    
    // Take first 16 characters and prefix with "p_"
    return 'p_${hashString.substring(0, 16)}';
  }

  /// Vote on a pair (increments counter)
  /// 
  /// [categoryId] - The category ID
  /// [aId] - First item ID
  /// [bId] - Second item ID
  /// [chosenId] - The ID that was chosen (must be either aId or bId)
  static Future<void> vote(
    String categoryId,
    String aId,
    String bId,
    String chosenId,
  ) async {
    // Generate deterministic pairId
    final pairId = generatePairId(aId, bId);
    
    // Determine which counter to increment (aCount or bCount)
    // Normalize order to match pairId generation
    final List<String> normalized = [aId, bId]..sort();
    final bool chosenIsA = chosenId == normalized[0];
    
    // Get reference to the pair document
    final ref = FirebaseFirestore.instance
        .collection('votes')
        .doc(categoryId)
        .collection('pairs')
        .doc(pairId);
    
    // Use transaction to ensure atomic updates
    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(ref);
      
      if (!snap.exists) {
        // Create document with initial values
        txn.set(ref, {
          'aId': normalized[0],
          'bId': normalized[1],
          'aCount': 0,
          'bCount': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      
      // Increment the appropriate counter
      txn.update(ref, {
        chosenIsA ? 'aCount' : 'bCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await incrementUserVoteCount();
    await updateDailyStreak();
  }

  /// Increment the current user's lifetime vote counter (user_progress.totalVotes)
  /// Used by ProfilePage's "Toplam Oy" stat — separate from per-pair counts above.
  static Future<void> incrementUserVoteCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('user_progress')
          .doc(user.uid)
          .set({
        'totalVotes': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-critical stat; ignore failures rather than blocking the vote flow.
    }
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Update the current user's daily return streak (user_progress.streakCount/longestStreak/lastActiveDate).
  /// Called once per vote — only the first vote of a calendar day actually moves the streak.
  static Future<void> updateDailyStreak() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseFirestore.instance.collection('user_progress').doc(user.uid);
    final today = DateTime.now();
    final todayKey = _dateKey(today);
    final yesterdayKey = _dateKey(today.subtract(const Duration(days: 1)));

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final data = snap.data() ?? {};
        final lastActiveDate = data['lastActiveDate'] as String?;

        if (lastActiveDate == todayKey) return; // already counted today

        final currentStreak = (data['streakCount'] as num?)?.toInt() ?? 0;
        final longestStreak = (data['longestStreak'] as num?)?.toInt() ?? 0;
        final newStreak = lastActiveDate == yesterdayKey ? currentStreak + 1 : 1;

        txn.set(
          ref,
          {
            'streakCount': newStreak,
            'longestStreak': newStreak > longestStreak ? newStreak : longestStreak,
            'lastActiveDate': todayKey,
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {
      // Non-critical stat; ignore failures rather than blocking the vote flow.
    }
  }

  /// Get vote counts for a pair (returns aCount and bCount)
  static Future<Map<String, int>> getVoteCounts(
    String categoryId,
    String aId,
    String bId,
  ) async {
    final pairId = generatePairId(aId, bId);
    final ref = FirebaseFirestore.instance
        .collection('votes')
        .doc(categoryId)
        .collection('pairs')
        .doc(pairId);
    
    final snap = await ref.get();
    if (!snap.exists) {
      return {'aCount': 0, 'bCount': 0};
    }
    
    final data = snap.data() ?? {};
    return {
      'aCount': (data['aCount'] ?? 0) as int,
      'bCount': (data['bCount'] ?? 0) as int,
    };
  }

  /// Get a stream of vote counts for a pair (for real-time updates)
  static Stream<Map<String, int>> getVoteCountsStream(
    String categoryId,
    String aId,
    String bId,
  ) {
    final pairId = generatePairId(aId, bId);
    final ref = FirebaseFirestore.instance
        .collection('votes')
        .doc(categoryId)
        .collection('pairs')
        .doc(pairId);
    
    return ref.snapshots().map((snap) {
      if (!snap.exists) {
        return {'aCount': 0, 'bCount': 0};
      }
      
      final data = snap.data() ?? {};
      return {
        'aCount': (data['aCount'] ?? 0) as int,
        'bCount': (data['bCount'] ?? 0) as int,
      };
    });
  }
}

