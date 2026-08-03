import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Real-time "Arkadaşlarınla Oyna" rooms.
///
/// Bumuomu has no Cloud Functions deployment (unlike the sibling
/// would_you_rather app, which does room creation server-side with a
/// per-uid rate limit — see the competitor/gap report the user shared).
/// This is a pure-Firestore-client implementation instead: a 5-digit
/// numeric code, claimed via a transaction, host-controlled round
/// advancement (currentIndex on the room doc), and per-round vote tallies
/// as a single doc per question (map of uid -> 'a'|'b') so every client can
/// listen with one stream instead of a subcollection.
///
/// Scope note (told to the user): "Favorini Bul" in a room plays through
/// the first 16 fixed pairs from the 32-item pool, not the full 32→1
/// single-elimination bracket — true bracket-in-room (where advancement
/// depends on the room's collective vote outcome per match) is a
/// meaningfully bigger state machine, scoped as a fast-follow.
class RoomService {
  RoomService._();

  static final _db = FirebaseFirestore.instance;
  static const int codeLength = 5;

  /// Fully automatic per-round countdown: starts the instant a round becomes
  /// current, votes are changeable the whole time, locks + auto-advances when
  /// it hits zero. No host button beyond the initial "Başlat" — clarified
  /// directly with the user.
  static const int roundDurationSeconds = 10;

  static Timestamp _newDeadline() => Timestamp.fromDate(
      DateTime.now().add(const Duration(seconds: roundDurationSeconds)));

  static String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'anon';

  static String _generateCode() {
    final rnd = Random();
    return List.generate(codeLength, (_) => rnd.nextInt(10)).join();
  }

  /// Creates a room with a fresh, unused 5-digit code and joins the creator
  /// as host. Returns the room code.
  static Future<String> createRoom({
    required String gameMode, // 'favorin' | 'unlimited' | 'dilemma'
    required String categoryKey,
    required String categoryName,
    required List<Map<String, String>> pairs,
    required String hostDisplayName,
  }) async {
    for (int attempt = 0; attempt < 5; attempt++) {
      final code = _generateCode();
      final ref = _db.collection('rooms').doc(code);
      try {
        final created = await _db.runTransaction<bool>((txn) async {
          final snap = await txn.get(ref);
          if (snap.exists && snap.data()?['status'] != 'finished') {
            return false; // code taken by a live room, retry
          }
          txn.set(ref, {
            'hostUid': _uid,
            'status': 'lobby',
            'gameMode': gameMode,
            'categoryKey': categoryKey,
            'categoryName': categoryName,
            'pairs': pairs,
            'currentIndex': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (created) {
          await joinRoom(code, displayName: hostDisplayName);
          return code;
        }
      } catch (_) {
        // retry with a new code
      }
    }
    throw Exception('Oda kodu oluşturulamadı, tekrar dene.');
  }

  static Future<void> joinRoom(String code, {required String displayName}) async {
    final ref = _db.collection('rooms').doc(code);
    final snap = await ref.get();
    if (!snap.exists) {
      throw Exception('Bu kodla bir oda bulunamadı.');
    }
    await ref.collection('participants').doc(_uid).set({
      'uid': _uid,
      'displayName': displayName,
      'joinedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream(String code) {
    return _db.collection('rooms').doc(code).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> participantsStream(String code) {
    return _db
        .collection('rooms')
        .doc(code)
        .collection('participants')
        .orderBy('joinedAt')
        .snapshots();
  }

  static Future<void> heartbeat(String code) async {
    try {
      await _db
          .collection('rooms')
          .doc(code)
          .collection('participants')
          .doc(_uid)
          .set({'lastSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> startRoom(String code) async {
    await _db.collection('rooms').doc(code).set({
      'status': 'playing',
      'currentIndex': 0,
      'roundDeadline': _newDeadline(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> advanceRound(String code, int nextIndex) async {
    await _db.collection('rooms').doc(code).set({
      'currentIndex': nextIndex,
      'roundDeadline': _newDeadline(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> finishRoom(String code) async {
    await _db.collection('rooms').doc(code).set({
      'status': 'finished',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> vote(String code, int questionIndex, String choice) async {
    await _db
        .collection('rooms')
        .doc(code)
        .collection('rounds')
        .doc('$questionIndex')
        .set({'choices': {_uid: choice}}, SetOptions(merge: true));
  }

  static Stream<Map<String, String>> roundChoicesStream(String code, int questionIndex) {
    return _db
        .collection('rooms')
        .doc(code)
        .collection('rounds')
        .doc('$questionIndex')
        .snapshots()
        .map((snap) {
      final raw = snap.data()?['choices'] as Map<String, dynamic>? ?? {};
      return raw.map((k, v) => MapEntry(k, v.toString()));
    });
  }

  /// Explicit host handoff — called when the host taps "Ayrıl" (leave).
  /// Ungraceful disconnects (app killed) aren't reliably detectable with
  /// pure Firestore (no onDisconnect like Realtime Database has), so this
  /// only covers the graceful-leave path; a stale-heartbeat fallback could
  /// be added later if this turns out to matter in practice.
  static Future<void> leaveRoom(String code) async {
    final roomRef = _db.collection('rooms').doc(code);
    await _db.runTransaction((txn) async {
      final roomSnap = await txn.get(roomRef);
      if (!roomSnap.exists) return;
      final isHost = roomSnap.data()?['hostUid'] == _uid;
      txn.delete(roomRef.collection('participants').doc(_uid));
      if (isHost) {
        final participants = await roomRef
            .collection('participants')
            .orderBy('joinedAt')
            .limit(2)
            .get();
        final remaining = participants.docs.where((d) => d.id != _uid).toList();
        final next = remaining.isEmpty ? null : remaining.first;
        if (next != null) {
          txn.set(roomRef, {'hostUid': next.id}, SetOptions(merge: true));
        } else {
          txn.set(roomRef, {'status': 'finished'}, SetOptions(merge: true));
        }
      }
    });
  }
}
