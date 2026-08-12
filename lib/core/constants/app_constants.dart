/// Uygulama genelinde kullanılan sabitler.
///
/// Magic number kullanmamak için tüm oyun boyutları ve süreleri buradan gelir.
class AppConstants {
  const AppConstants._();

  // --- Board ---
  static const int boardRows = 8;
  static const int boardCols = 8;

  // --- Tray ---
  static const int traySize = 3;

  /// Blok paletindeki renk sayısı — `AppColors.blocks` ile aynı olmalıdır.
  ///
  /// Generator bundan fazla renk üretirse fazlalık `forCellValue` içinde
  /// başa döner ve ilk renk iki kat sık görünür (ölçüm: turuncu 1985'e karşı
  /// diğerleri ~1000). Eşitliği `test/game/piece_generator_test.dart` korur.
  static const int blockColorCount = 5;

  /// Bir tray üretilirken "en az bir legal hamle" garantisi için
  /// yapılacak maksimum yeniden üretim denemesi.
  static const int maxTrayGenerationAttempts = 20;

  /// Tepsi yüksekliği = board hücre boyutu * bu katsayı.
  /// En uzun parça 4 hücre ve tepsi ölçeği 0.62 olduğu için 2.48 yeterlidir.
  static const double trayHeightFactor = 2.6;

  // --- Animasyon süreleri (kısa tutulur, metroda hız önemli) ---
  static const Duration lineClearDuration = Duration(milliseconds: 220);
  static const Duration piecePlaceDuration = Duration(milliseconds: 120);
  static const Duration progressTickDuration = Duration(milliseconds: 900);
  static const Duration overlayFadeDuration = Duration(milliseconds: 180);

  // --- Oyun döngüsü ---
  static const Duration playTick = Duration(seconds: 1);

  // --- Metin ---
  static const String appTitle = 'İstanbul Metrosu Oyunu';
  static const String tagline = 'Yolculuğun kadar oyna.';
  static const String offlineNote = 'İnternetsiz oynanabilir.';
}
