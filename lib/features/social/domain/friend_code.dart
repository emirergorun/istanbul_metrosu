import 'dart:math';

/// Oyuncuları birbirine bağlayan paylaşılabilir kod.
///
/// **Kullanıcı adı değil.** Ad zaten sözlükten üretiliyor ve oyuncu onu
/// seçiyor; bu kod ise kimliğin makine tarafı: karşı taraf onu okuyup seni
/// listesine ekliyor. İkisini ayırmak, adın değişebilir kalmasını ve kodun
/// sabit kalmasını sağlıyor.
///
/// Alfabe **Crockford Base32**: `I`, `L`, `O` ve `U` yok. İlk üçü 1 ve 0 ile
/// karışıyor — kodu metroda birinin telefonundan okuyup kendi telefonuna
/// yazan biri için bu gerçek bir hata kaynağı. `U` ise kazara küfür üretmemek
/// için dışarıda; standardın kendisi de aynı sebeple çıkarıyor.
///
/// Sekiz karakter: 32⁸ ≈ 1,1 × 10¹² olasılık. Kod sunucuda değil cihazda
/// üretildiği için çakışma ihtimali doğum günü problemiyle hesaplanır;
/// bir milyon oyuncuda çakışma olasılığı binde birin altında kalıyor.
class FriendCode {
  const FriendCode._();

  /// Crockford Base32 — okunurken karışan harfler yok.
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Kod uzunluğu (tire hariç).
  static const int length = 8;

  /// Görünen biçimdeki tire konumu: `ABCD-EFGH`.
  static const int groupSize = 4;

  /// Yeni bir kod üretir.
  ///
  /// [random] verilmezse `Random.secure` kullanılır: kod tahmin edilebilir
  /// olmamalı, yoksa bir oyuncu başkasının kodunu üretip onun adına
  /// meydan okuma yayabilir.
  static String generate({Random? random}) {
    final rng = random ?? Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[rng.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Elle yazılmış kodu kanonik hâle getirir; geçersizse `null`.
  ///
  /// Crockford'un okuma kuralları uygulanır: `I` ve `L` → `1`, `O` → `0`,
  /// `U` → `V`. Tire, boşluk ve küçük harf serbest — oyuncu kodu gördüğü
  /// gibi yazar, biçimi biz düzeltiriz.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final buffer = StringBuffer();
    for (final rune in raw.toUpperCase().runes) {
      final char = String.fromCharCode(rune);
      if (char == '-' || char == ' ') continue;
      final mapped = switch (char) {
        'I' || 'L' => '1',
        'O' => '0',
        'U' => 'V',
        _ => char,
      };
      if (!alphabet.contains(mapped)) return null;
      buffer.write(mapped);
    }
    final code = buffer.toString();
    return code.length == length ? code : null;
  }

  /// Ekranda gösterilen biçim: `ABCD-EFGH`.
  static String format(String code) {
    if (code.length != length) return code;
    return '${code.substring(0, groupSize)}-${code.substring(groupSize)}';
  }

  static bool isValid(String? raw) => normalize(raw) != null;
}
