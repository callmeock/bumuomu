import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Firestore'dan gelen görsel URL'lerini `CachedNetworkImage`'e vermeden
/// önce güvenli hale getirir. İki ayrı sorunu çözer:
///
/// 1. Tarayıcılar "ş", "ö" gibi ASCII-olmayan karakterleri otomatik
///    percent-encode eder, Dart'ın HTTP client'ı etmez — bu yüzden aynı URL
///    tarayıcıda açılırken uygulama içinde sessizce yüklenmeyebilir.
/// 2. Türkçe "ş" gibi karakterler Unicode'da iki farklı şekilde temsil
///    edilebilir: NFC (tek kod noktası) ya da NFD (taban harf + birleştirici
///    işaret) — ekranda birebir aynı görünür ama byte düzeyinde farklıdır.
///    macOS dosya adları genelde NFD, klavyeden girilen metin genelde NFC
///    olduğu için itemName (Firestore) ile gerçek dosya adı (WordPress)
///    farklı normalizasyonla üretilmiş olabilir — normalize etmeden encode
///    etmek bu farkı çözmez.
///
/// Bu fonksiyonu her görsel tüketim noktasında TAM OLARAK BİR KEZ kullanın
/// (ara katmanlarda değil) — aksi halde çifte encode olur.
String safeImageUrl(String url) {
  if (url.isEmpty) return url;
  try {
    return Uri.encodeFull(unorm.nfc(url));
  } catch (_) {
    return url;
  }
}

/// Bir sonraki karta geçilmeden ÖNCE görselini indirip diske önbelleğe alır,
/// böylece kullanıcı oraya geldiğinde spinner görünmez. `safeImageUrl` burada
/// tek noktadan çağrılır — çağıranlar url'i ayrıca normalize etmemeli.
void precacheSafeImage(BuildContext context, String? url) {
  if (url == null || url.isEmpty) return;
  precacheImage(CachedNetworkImageProvider(safeImageUrl(url)), context);
}
