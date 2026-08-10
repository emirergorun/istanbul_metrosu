import 'package:flutter/material.dart';

/// Tipografi.
///
/// metro.istanbul ile aynı font ailesi kullanılır: başlıklarda **Raleway**,
/// gövde ve butonlarda **Open Sans**. İkisi de SIL Open Font License 1.1
/// altındadır ve `assets/fonts/` içinde uygulamaya gömülüdür.
class AppFonts {
  const AppFonts._();

  /// Başlık ailesi (site başlıkları Raleway 600–800).
  static const String display = 'Raleway';

  /// Gövde ve buton ailesi.
  static const String body = 'Open Sans';
}

/// Uygulama renk paleti.
///
/// Ton olarak İstanbul metrosunun kurumsal lacivert + kırmızı düzenini
/// izler; oyun tarafı koyu kalır. Resmi logo, marka görseli veya hat
/// amblemi kullanılmaz — yalnızca renk ve tipografi dili.
/// TODO(PROD): Kurumsal renklerin ticari kullanımı için marka incelemesi.
class AppColors {
  const AppColors._();

  // --- Kurumsal ton ---
  /// Planlayıcı butonu / başlık şeridi laciverti.
  static const Color brandNavy = Color(0xFF164874);
  static const Color brandNavyDeep = Color(0xFF0E2A46);

  /// Vurgu kırmızısı (aktif sekme, A/B işaretleri, ana aksiyon).
  static const Color brandRed = Color(0xFFE1251B);

  // --- Yüzeyler ---
  static const Color background = Color(0xFF0A1826);
  static const Color surface = Color(0xFF122A40);
  static const Color surfaceHigh = Color(0xFF1A3A57);
  static const Color boardBackground = Color(0xFF0E2135);
  static const Color emptyCell = Color(0xFF1B3450);
  static const Color outline = Color(0xFF244763);

  // --- Metin ---
  static const Color textPrimary = Color(0xFFF2F6FA);
  static const Color textSecondary = Color(0xFF9FB3C8);
  static const Color textMuted = Color(0xFF7189A3);

  static const Color danger = brandRed;
  static const Color success = Color(0xFF30C48D);
  static const Color warning = Color(0xFFF2B138);

  /// Engel hücresi (zorluk profilinden gelen başlangıç doluluğu).
  static const Color blocker = Color(0xFF47607C);

  /// Blok renk ailesi. Renk körlüğü için tonlar arasında parlaklık farkı var
  /// ve bilgi asla yalnız renkle verilmez (şekil + kontur da taşır).
  static const List<Color> blocks = <Color>[
    Color(0xFFF2B138), // amber
    Color(0xFF4C9AFF), // mavi
    Color(0xFFFF6B6B), // mercan
    Color(0xFF35C3A5), // turkuaz
    Color(0xFFB98CFF), // mor
    Color(0xFFFF9F5A), // turuncu
  ];

  /// Hücre değerinden renk. 9 = engel.
  static Color forCellValue(int value) {
    if (value == 9) return blocker;
    if (value <= 0) return emptyCell;
    return blocks[(value - 1) % blocks.length];
  }
}

/// Tek tema: koyu. Metro ortamında kontrast ve göz yorgunluğu için tercih edildi.
/// TODO(PROD): Light tema ve "reduce motion" desteği eklenecek.
class AppTheme {
  const AppTheme._();

  static ThemeData dark({Color accent = const Color(0xFF00A65A)}) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
        ).copyWith(
          surface: AppColors.background,
          primary: accent,
          onPrimary: Colors.white,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      // Gövde varsayılanı Open Sans; başlıklar aşağıda Raleway'e geçer.
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

  /// Kurumsal arayüz köşe yumuşaklığı sıkıdır (site 4px kullanıyor).
  static const double cardRadius = 8;
  static const double fieldRadius = 6;
  static const double cellRadius = 6;
}
