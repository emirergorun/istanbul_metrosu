/// Kullanıcıya gösterilen süre/sayı metinleri.
///
/// Ürün dili kararı: uygulama asla "kesin varış" iddiası yapmaz.
/// Bu yüzden metinlerde "yaklaşık / tahmini" kullanılır.
class Formatters {
  const Formatters._();

  /// Türkçe büyük harf.
  ///
  /// Dart'ın `toUpperCase()` metodu locale bağımsızdır ve `i` harfini `I`
  /// yapar. Türkçede doğrusu `İ`'dir ("Gidilecek" -> "GİDİLECEK").
  static String upperTr(String value) =>
      value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

  /// `14` -> `14 dk`
  static String minutes(int value) => '$value dk';

  /// `14` -> `~14 dk`
  static String approxMinutes(int value) => '~$value dk';

  /// Kalan saniyeyi kullanıcı diline çevirir.
  /// 90 -> `~2 dk`, 45 -> `<1 dk`, 0 -> `Varış`
  static String remaining(int seconds) {
    if (seconds <= 0) return 'Varış';
    if (seconds < 60) return '<1 dk';
    return '~${(seconds / 60).ceil()} dk';
  }

  /// `mm:ss` — sadece debug/HUD detayında kullanılır.
  static String clock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Binlik ayraçlı skor: 1234 -> 1.234
  static String score(int value) {
    final text = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
      buffer.write(text[i]);
    }
    return '${value < 0 ? '-' : ''}$buffer';
  }
}
