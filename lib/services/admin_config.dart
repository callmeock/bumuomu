/// Uygulamanın tek sahibinin (admin) Firebase Auth UID'i.
///
/// "Sizden Gelenler" onay ekranını sadece bu UID'e sahip cihaz görebilir.
/// Bu, sadece UX görünürlüğü içindir — gerçek yetki sınırı Firestore
/// Rules'da aynı UID ile ayrıca tanımlanmalıdır (bkz. firestore.rules).
///
/// Gerçek UID'i öğrenmek için: Profil sayfasını aç, "ID: ..." satırındaki
/// UID'in tamamını görmek için üzerine dokun/kopyala (bkz. profile_page.dart),
/// ya da Firebase Console > Authentication > Users listesinden bul.
class AdminConfig {
  AdminConfig._();

  static const String ownerUid = 'TnNQRbGYqGXAF2JobWb8cemIUSH2';

  static bool isOwner(String? uid) => uid != null && uid == ownerUid;
}
