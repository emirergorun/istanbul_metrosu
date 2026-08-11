import 'package:flutter/material.dart';

/// Tipografi.
///
/// metro.istanbul ile aynı font ailesi kullanılır: başlıklarda **Raleway**,
/// gövde ve butonlarda **Open Sans**. İkisi de SIL Open Font License 1.1
/// altındadır ve `assets/fonts/` içinde uygulamaya gömülüdür.
class AppFonts {
  const AppFonts._();

  static const String display = 'Raleway';
  static const String body = 'Open Sans';
}

/// Uygulama renk paleti.
///
/// **Hiyerarşi** — her rengin tek bir işi var:
///
/// | Katman | Rol | Davranış |
/// |---|---|---|
/// | Nötr lacivert skalası | zemin, yüzey, kenarlık | sabit |
/// | [action] | birincil buton | **sabit** — hatla değişmez |
/// | Hat rengi | kimlik: rozet, tren, ray, ilerleme | hatla değişir |
/// | [danger] | yalnız hata ve geçersiz hamle | sabit |
/// | [blocks] | oyun tahtası | sabit, tüm hatlarda aynı |
///
/// En önemli kural: **hat rengi aksiyon rengi değildir.** Buton her hatta
/// aynı kalır, yoksa hiyerarşi kaybolur ve bazı hat renklerinde kontrast
/// düşer. Bloklar da hattan bağımsızdır; aksi hâlde renk körlüğü ayarını
/// her hat için ayrı yapmak gerekirdi.
class AppColors {
  const AppColors._();

  // --- Nötr skala ---
  static const Color background = Color(0xFF0B1622);
  static const Color surface = Color(0xFF142335);
  static const Color surfaceHigh = Color(0xFF1D3149);
  static const Color boardBackground = Color(0xFF0F1D2C);
  static const Color emptyCell = Color(0xFF1A2C41);
  static const Color outline = Color(0xFF26405C);

  /// Kurumsal lacivert — başlık şeritleri ve ikincil yüzeyler.
  static const Color brandNavy = Color(0xFF164874);
  static const Color brandNavyDeep = Color(0xFF0E2A46);

  // --- Metin ---
  static const Color textPrimary = Color(0xFFF2F6FA);
  static const Color textSecondary = Color(0xFF9BB0C6);
  static const Color textMuted = Color(0xFF6F87A0);

  // --- Aksiyon (sabit) ---
  /// Birincil buton. Koyu zeminde en parlak öge olması hiyerarşiyi kurar ve
  /// hiçbir hat rengiyle çakışmaz.
  static const Color action = Color(0xFFF2F6FA);
  static const Color onAction = Color(0xFF0B1622);

  // --- Semantik ---
  /// Yalnız hata ve geçersiz hamle. Aksiyon rengiyle karıştırılmamalı.
  static const Color danger = Color(0xFFFF5C5C);
  static const Color success = Color(0xFF2FB37A);
  static const Color warning = Color(0xFFF5C518);

  /// Engel hücresi (zorluk profilinden gelen başlangıç doluluğu).
  static const Color blocker = Color(0xFF40566F);

  /// Blok renkleri — **Okabe–Ito** renk körlüğü güvenli paletinden, İstanbul
  /// metro palet ailesine en yakın beş ton seçilerek.
  ///
  /// Okabe–Ito, protanopi/döteranopi/tritanopi altında ayırt edilebilirliği
  /// kanıtlanmış bir settir; buradaki beşi aynı zamanda gerçek hat renklerini
  /// (turuncu-bej M6, gök mavisi M3, yeşil M2, pembe M4/M7, sarı M9)
  /// çağrıştırır. Altı yerine beş: göz zaten altıncıyı takip etmiyor.
  static const List<Color> blocks = <Color>[
    Color(0xFFE69F00), // turuncu
    Color(0xFF56B4E9), // gök mavisi
    Color(0xFF009E73), // yeşil
    Color(0xFFCC79A7), // pembe
    Color(0xFFF0E442), // sarı
  ];

  /// Hücre değerinden renk. 9 = engel.
  static Color forCellValue(int value) {
    if (value == 9) return blocker;
    if (value <= 0) return emptyCell;
    return blocks[(value - 1) % blocks.length];
  }
}

/// Bir hattın renginden türetilen kullanılabilir varyantlar.
///
/// Resmi hat renkleri arayüz için tasarlanmadı: M5 (#693064) koyu zeminde
/// neredeyse görünmüyor, M9 (#FFD300) üstünde beyaz metin okunmuyor.
/// Bu sınıf resmi rengi kimlik olarak korur, kullanım yerine göre
/// düzeltilmiş varyantlarını üretir.
@immutable
class LineTheme {
  const LineTheme({
    required this.color,
    required this.accent,
    required this.onColor,
    required this.onAccent,
  });

  /// Resmi hat rengi — rozet ve tren gövdesi.
  final Color color;

  /// Koyu zeminde okunabilir varyant — ince çizgiler, ray, ikonlar, metin.
  final Color accent;

  /// [color] üzerine yazılacak metin rengi.
  final Color onColor;

  /// [accent] üzerine yazılacak metin rengi.
  final Color onAccent;

  /// Kontrast eşiği: ince ögeler için WCAG'in grafik nesne sınırı.
  static const double _minContrast = 3.2;

  factory LineTheme.from(Color official) {
    final accent = _liftForDarkBackground(official);
    return LineTheme(
      color: official,
      accent: accent,
      onColor: _readableOn(official),
      onAccent: _readableOn(accent),
    );
  }

  static Color _readableOn(Color background) =>
      background.computeLuminance() > 0.42
      ? AppColors.background
      : Colors.white;

  /// Koyu zeminde yeterli kontrasta ulaşana kadar rengi açar.
  static Color _liftForDarkBackground(Color color) {
    var hsl = HSLColor.fromColor(color);
    // Çok doygun olmayan koyu renkler açılırken grileşmesin.
    if (hsl.saturation < 0.25) {
      hsl = hsl.withSaturation((hsl.saturation + 0.15).clamp(0.0, 1.0));
    }
    var candidate = hsl.toColor();
    var guard = 0;
    while (_contrast(candidate, AppColors.background) < _minContrast &&
        hsl.lightness < 0.82 &&
        guard < 40) {
      hsl = hsl.withLightness((hsl.lightness + 0.03).clamp(0.0, 1.0));
      candidate = hsl.toColor();
      guard++;
    }
    return candidate;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// Tek tema: koyu. Metro ortamında kontrast ve göz yorgunluğu için tercih edildi.
/// TODO(PROD): Light tema ve "reduce motion" desteği eklenecek.
class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brandNavy,
          brightness: Brightness.dark,
        ).copyWith(
          surface: AppColors.background,
          primary: AppColors.action,
          onPrimary: AppColors.onAction,
          error: AppColors.danger,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          height: 1.05,
          letterSpacing: -0.5,
        ),
        headlineSmall: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 15,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
        bodySmall: TextStyle(fontSize: 13, color: AppColors.textMuted),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.action,
          foregroundColor: AppColors.onAction,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Ortak ölçüler.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  static const double cardRadius = 8;
  static const double fieldRadius = 6;
  static const double cellRadius = 6;
}
