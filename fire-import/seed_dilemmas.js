// seed_dilemmas.js
//
// One-off seed for the "Sadece Soru" mode: `categories` docs with
// type:'dilemma' and paired statements (items[0] vs items[1],
// items[2] vs items[3], ...). Multiple sets on purpose — with only one,
// SadeceSoruPage auto-enters it and skips the picker (user feedback: "bir
// kaç tane daha kategori üretelim... kategoriyi arttırınca kullanıcı seçsin").
//
// The initial seeds (2026-08-02/03) were written directly via the Firestore
// REST API using an anonymous auth token, since no serviceAccount.json was
// available in this environment — same write path the app itself uses.
// This script follows import_data.js's admin-SDK pattern instead, for
// re-running/editing later once serviceAccount.json is in place.

const admin = require("firebase-admin");
const fs = require("fs");

const serviceAccount = JSON.parse(
  fs.readFileSync("./serviceAccount.json", "utf8")
);

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

const SETS = [
  {
    docId: "dilemma_hayatin_boyunca",
    name: "Hayatın Boyunca Sadece...",
    pairs: [
      ["Hayatın boyunca sadece pizza yemek", "Hayatın boyunca sadece hamburger yemek"],
      ["Hayatın boyunca her gün çok erken uyanmak", "Hayatın boyunca her gün çok geç uyumak"],
      ["Uçabilme yeteneğine sahip olmak", "Görünmez olabilme yeteneğine sahip olmak"],
      ["Zengin ama yalnız olmak", "Fakir ama çok arkadaşı olmak"],
      ["Hayatın boyunca sürekli yağmurlu bir yerde yaşamak", "Hayatın boyunca sürekli çok sıcak bir yerde yaşamak"],
      ["1 hafta boyunca telefonsuz kalmak", "1 ay boyunca internetsiz kalmak"],
      ["Geçmişe dönüp hatalarını düzeltebilmek", "Geleceği önceden görebilmek"],
      ["Hiç yalan söyleyememek", "Söylediğin her yalanın hemen anlaşılması"],
      ["Uzayda yaşamak", "Okyanusun dibinde yaşamak"],
      ["Telefonunun şarjının asla bitmemesi", "Hayatın boyunca hiç trafiğe takılmamak"],
    ],
  },
  {
    docId: "dilemma_super_guc",
    name: "Süper Güç Seçimi",
    pairs: [
      ["Uçabilme yeteneği", "Zamanı durdurabilme yeteneği"],
      ["Görünmez olabilme", "Zihin okuyabilme"],
      ["Süper hız", "Süper güç (kaldırma)"],
      ["Ateşi kontrol edebilme", "Suyu kontrol edebilme"],
      ["Işınlanabilme", "İstediğin şekle girebilme"],
      ["Geleceği görebilme", "Geçmişe dönüp bir şeyi değiştirebilme"],
      ["Hayvanlarla konuşabilme", "Dünyadaki tüm dilleri konuşabilme"],
      ["Sonsuz para", "Sonsuz boş zaman"],
    ],
  },
  {
    docId: "dilemma_gunluk_hayat",
    name: "Günlük Hayat İkilemleri",
    pairs: [
      ["Sabahları çok erken kalkan biri olmak", "Gece kuşu olmak"],
      ["Her zaman yazın yaşamak", "Her zaman kışın yaşamak"],
      ["Dağda tatil yapmak", "Denizde tatil yapmak"],
      ["Hep kahve içmek", "Hep çay içmek"],
      ["Kitap okuyarak vakit geçirmek", "Film/dizi izleyerek vakit geçirmek"],
      ["Tek başına yaşamak", "Ev arkadaşıyla yaşamak"],
      ["Kalabalık bir şehirde yaşamak", "Sakin bir kasabada yaşamak"],
      ["Erken emekli olup az kazanmak", "Geç emekli olup çok kazanmak"],
    ],
  },
];

async function seedDilemmas() {
  for (const set of SETS) {
    const items = set.pairs.flat();
    await db.collection("categories").doc(set.docId).set(
      {
        type: "dilemma",
        mode: "normal",
        name: set.name,
        image: "",
        items,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    console.log(`✅ ${set.docId}: ${set.pairs.length} ikilem yazıldı.`);
  }
}

seedDilemmas().catch((e) => {
  console.error("❌ Seed başarısız:", e);
  process.exit(1);
});
