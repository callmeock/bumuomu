# "Sizden Gelenler" — kurulum notları

Bu özellik V1'de tamamen client-side çalışır (Cloud Functions yok). Kod
tarafı hazır ama devreye almadan önce iki manuel adım gerekiyor.

## 1. Sahibin (admin) UID'ini ayarla

`lib/services/admin_config.dart` içindeki `ownerUid` şu an placeholder:

```dart
static const String ownerUid = 'REPLACE_WITH_OWNER_UID';
```

Gerçek UID'ini öğrenmek için:
1. Uygulamayı çalıştır, **Profil** sekmesine git.
2. "ID: xxxxxxxx... (kopyalamak için dokun)" yazısına dokun — tam UID panoya
   kopyalanır ve bir snackbar ile gösterilir.
3. Bu UID'i `admin_config.dart`'a yapıştır.

Bu UID, "Sizden Gelenler (Admin)" ayarlar satırının Profil sayfasında
görünmesini kontrol eder (sadece bu UID ile görünür). **Bu sadece UX
görünürlüğüdür — gerçek yetki sınırı adım 2'deki Firestore Rules ile
sağlanmalı**, yoksa herhangi bir kullanıcı Firestore'a doğrudan yazarak
kendi sorusunu "approved" yapabilir.

## 2. Firestore Rules'a ekle (elle, mevcut kuralları EZMEDEN)

Bu repoda hiç `firestore.rules` dosyası yok — kurallar bugün sadece Firebase
Console'da tanımlı. Bu yüzden burada bir dosya oluşturup deploy etmek yerine,
**mevcut konsol kurallarınıza aşağıdaki bloğu elle ekleyin** (mevcut
`categories`, `unlimited_questions`, `votes`, `user_progress` vb. kuralları
görmediğimiz için bunları değiştirmeden, sadece yeni koleksiyonlar için ekleme
yapın):

```
// --- Sizden Gelenler ---
match /submitted_questions/{id} {
  allow create: if request.auth != null
    && request.resource.data.uid == request.auth.uid
    && request.resource.data.status == 'pending'
    && request.resource.data.question is string
    && request.resource.data.question.size() > 0
    && request.resource.data.question.size() <= 140
    && request.resource.data.optionA is string
    && request.resource.data.optionA.size() > 0
    && request.resource.data.optionA.size() <= 60
    && request.resource.data.optionB is string
    && request.resource.data.optionB.size() > 0
    && request.resource.data.optionB.size() <= 60
    // targetCollection opsiyonel — sadece kapalı bir allowlist'e izin ver.
    // Yoksa herhangi bir kullanıcı bu alanı istismar edip, sahibin yüksek
    // yetkili onay eylemi sırasında yanlış/istenmeyen bir koleksiyona
    // yazılmasına neden olabilir (bkz. admin_review_page.dart _approve()).
    && (!('targetCollection' in request.resource.data)
        || request.resource.data.targetCollection in ['unlimited_questions']);

  allow read: if request.auth != null
    && (resource.data.uid == request.auth.uid || request.auth.uid == '<OWNER_UID>');

  allow update: if request.auth != null && request.auth.uid == '<OWNER_UID>';

  allow delete: if false;
}

match /sizden_gelenler_questions/{id} {
  allow read: if request.auth != null;
  allow write: if request.auth != null && request.auth.uid == '<OWNER_UID>';
}

match /sizden_gelenler_polls/{id} {
  allow read: if request.auth != null;
  // unlimited_polls ile aynı desen: herkes kendi oyunu artırabilir.
  allow create, update: if request.auth != null;
}

match /sizden_gelenler_users/{uid}/state/{doc} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}

// --- Günlük AI içerik üretim hattı ---
// Rutin, admin kimlik bilgisi olmadan normal bir anonim kullanıcı gibi yazar
// (bkz. plan: "Günlük AI içerik üretim hattı"). Onay her zaman sahibin
// admin_review_page.dart ekranından geçer, bu koleksiyonlara sahip olmayan
// biri asla doğrudan `categories`/`unlimited_questions`'a yazamaz.
match /submitted_dilemmas/{id} {
  allow create: if request.auth != null
    && request.resource.data.uid == request.auth.uid
    && request.resource.data.status == 'pending'
    && request.resource.data.name is string
    && request.resource.data.items is list;

  allow read: if request.auth != null
    && (resource.data.uid == request.auth.uid || request.auth.uid == '<OWNER_UID>');

  allow update: if request.auth != null && request.auth.uid == '<OWNER_UID>';
  allow delete: if false;
}

match /submitted_category_ideas/{id} {
  allow create: if request.auth != null
    && request.resource.data.uid == request.auth.uid
    && request.resource.data.status == 'pending'
    && request.resource.data.theme is string
    && request.resource.data.itemNames is list;

  allow read: if request.auth != null
    && (resource.data.uid == request.auth.uid || request.auth.uid == '<OWNER_UID>');

  allow update: if request.auth != null && request.auth.uid == '<OWNER_UID>';
  allow delete: if false;
}

// "Kategori Fikirleri" sekmesinde "Görselleri Gir" formu, sahip görsel
// URL'lerini girip Yayınla dediğinde doğrudan bu iki koleksiyona yazıyor
// (fire-import/Excel akışını atlıyor). Sadece sahip yazabilsin:
match /categories/{id} {
  allow read: if true; // uygulamanın geneli zaten herkese açık okuyor
  allow write: if request.auth != null && request.auth.uid == '<OWNER_UID>';
}

match /descriptions/{itemName} {
  allow read: if true;
  allow write: if request.auth != null && request.auth.uid == '<OWNER_UID>';
}
```

`<OWNER_UID>` yerine adım 1'deki gerçek UID'i yazın (altı yerde geçiyor).

Not: `categories`/`descriptions` için yukarıdaki kural sadece **yeni yazma**
yolunu (uygulama içi form) kapsıyor — bu repodan mevcut production
kurallarını göremediğimiz için, bu koleksiyonlarda zaten farklı bir kural
varsa (örn. `fire-import`'un servis hesabıyla yazması hep serbestti çünkü o
Admin SDK kullanıyor, rules'u tamamen bypass ediyor) onunla çakışmadığını
Console'da kontrol edin.

Not: yukarıdaki rutin yazma işlemleri her seferinde **yeni bir anonim
Firebase kullanıcısı** olarak giriş yapıyor (`uid` = o oturumun kendi UID'i,
`request.resource.data.uid == request.auth.uid` şartını otomatik sağlıyor) —
sabit bir UID veya gizli anahtar taşımaya gerek yok.

**Neden burada bir `firestore.rules` dosyası oluşturup deploy etmedik:**
mevcut production kurallarının içeriğini bu repodan göremiyoruz (Console'da
yaşıyorlar). Yarım bir `firestore.rules` dosyası oluşturup
`firebase deploy --only firestore:rules` çalıştırmak, görmediğimiz mevcut
kuralların üzerine yazıp diğer koleksiyonlara erişimi kırma riski taşır. Bu
yüzden yukarıdaki bloğu Console'daki Rules editöründe mevcut kuralların
**yanına** elle eklemeniz daha güvenli.

## 3. Günlük AI içerik üretim hattı (routine)

`admin_review_page.dart` artık 3 sekmeli: **Sorular**, **İkilemler**,
**Kategori Fikirleri**. İlk sekme hem gerçek kullanıcı gönderimlerini hem de
`targetCollection: 'unlimited_questions'` etiketli AI günlük sorularını
gösterir (aynı kart, aynı onay akışı). Diğer iki sekme, günlük zamanlanmış
bulut ajanının (`RemoteTrigger` routine) yazdığı `submitted_dilemmas` /
`submitted_category_ideas` dokümanlarını listeler.

Routine'in çalışabilmesi için: `callmeock/bumuomu` reposu için GitHub App
bağlantısının kurulmuş olması gerekiyor
(`https://claude.ai/code/onboarding?magic=github-app-setup`). Routine hiçbir
admin kimlik bilgisi taşımaz — normal anonim Firebase Auth ile REST API
üzerinden `submitted_questions` / `submitted_dilemmas` /
`submitted_category_ideas`'a `status: 'pending'` yazar; yayın her zaman
sahibin onayıyla olur.

"Kategori Fikirleri" sekmesinde "Kabul Et" demek **hiçbir zaman** otomatik
yayın anlamına gelmez — sadece durumu `accepted_awaiting_images` yapar.
Gerçek yayın, öğe adlarına karşılık gelen 32 gerçek görsel WordPress'e
yüklenip mevcut `fire-import/` script'i (ya da elle) çalıştırıldığında olur.

## V1 kapsamı dışında bırakılanlar (bkz. plan)

- AI ön-filtre moderasyon, Cloud Functions
- Onay/red push bildirimi (kullanıcı durumu "Gönderdiklerim" sekmesinden
  kontrol ediyor)
- Sunucu taraflı gönderim hız sınırlaması (şu an sadece client-side "en fazla
  5 bekleyen soru" kontrolü var — `sgMaxPendingPerUser` sabiti,
  `lib/pages/sizden_gelenler_page.dart`)
