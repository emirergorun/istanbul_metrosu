import 'package:flutter/material.dart';

/// Tipografi.
///
/// Kısa, büyük başlıklarda **Bungee**; diğer her yerde
/// **Plus Jakarta Sans**. İkisi de SIL OFL 1.1.
///
/// Bungee iri, tabela karakterli bir yazı tipidir: yalnızca ~20 punto ve
/// üstündeki, **tek satıra sığan** başlıklarda okunur. İki satıra taşan
/// cümleler (onay penceresi başlıkları gibi) bu fontta ağır duruyordu; onlar
/// Plus Jakarta Sans ExtraBold'dadır. Tek ağırlığı var (400); daha kalın
/// istenirse Flutter sahte kalınlaştırma yapıp harfleri bozar. Skor, rozet ve
/// etiket gibi küçük ya da sık değişen metinler de Plus Jakarta Sans'tadır.
///
/// Bungee Türkçe için değiştirildi: özgün dosya küçük `i`'yi noktasız
/// `I` çiziyor ve Türkçe `locl` kuralı yok, "girdin" ekranda "GIRDIN"
/// okunuyordu. `cmap` içinde `i` → `İ` eşlendi; metinler değişmeden doğru
/// görünür. Plus Jakarta Sans'ın google/fonts'taki değişken dosyasından
/// 400 / 500 / 700 / 800 sabit ağırlıkları üretildi.
class AppFonts {
  const AppFonts._();

  /// Yalnızca büyük başlıklar (≥ 20 pt). Tek ağırlık: `FontWeight.w400`.
  static const String display = 'Bungee';

  /// Gövde, düğme, skor, etiketler ve uzun başlıklar.
  /// Ağırlıklar: 400, 500, 700, 800.
  static const String body = 'Plus Jakarta Sans';
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
  //
  // Tek ton (218°) üzerine kurulu, **algısal olarak eşit adımlı** bir
  // merdiven: L* değerleri 6 → 11 → 16 → 22 → 33. Daha önce ilk iki adım
  // 3 L* idi; o fark gözle seçilemediği için tahta ve kartlar zeminden
  // ayrışmıyor, arayüz düz bir leke gibi duruyordu.
  //
  // **Doygunluk bilerek düşük (%10-14).** Zemin önce doygun bir laciverttti
  // (%52) ve bu iki sorun üretiyordu:
  //
  // 1. **İşlevsel.** M8'in resmi rengi (`#447ABE`) zeminle *birebir aynı
  //    tondaydı*, M3 (`#05A8E2`) 18° uzaktaydı. Yani bu iki hatta kimlik
  //    rengi zeminin açığı oluyor, "hat rengi kimliktir" kuralı çalışmıyordu.
  // 2. **Görsel.** Dokuz hat renk çemberinin tamamına yayılmış durumda;
  //    hiçbir tona kaçarak hepsinden uzaklaşmak mümkün değil. Sıcak bir
  //    zemin bu sefer M6 (bej) ve M9 (sarı) ile akraba oluyordu.
  //
  // Çözüm tonu değiştirmek değil, **doygunluğu düşürmek**: zemin nötre
  // yaklaştıkça hiçbir hattın akrabası olmuyor ve ekrandaki tek renk hat
  // rengi kalıyor. Tamamen nötr de yapılmadı (%0 gri jenerik durur); serin
  // cast korunuyor.
  static const Color background = Color(0xFF111317);
  static const Color surface = Color(0xFF24282E);
  static const Color surfaceHigh = Color(0xFF31353D);
  static const Color boardBackground = Color(0xFF1B1E23);
  static const Color emptyCell = Color(0xFF292D34);
  static const Color outline = Color(0xFF484E58);

  /// Tahtadaki boş hücrenin ızgara çizgisi.
  ///
  /// Izgara dolgu farkıyla çizilemiyor: boş hücreyi tahta zemininden 3:1
  /// ayıracak kadar açmak gerekirdi, o açıklıkta da engel hücresiyle
  /// (`blocker`) karışırdı. Bunun yerine dolgu koyu kalır, ızgarayı bu ince
  /// çizgi çizer — zemine 3.83:1, dolguya 3.02:1, ikisi de WCAG'in ince
  /// grafik nesne sınırının (3.0) üstünde.
  static const Color cellGrid = Color(0xFF697D9F);

  /// Kurumsal lacivert — başlık şeritleri ve ikincil yüzeyler.
  static const Color brandNavy = Color(0xFF164874);
  static const Color brandNavyDeep = Color(0xFF0E2A46);

  // --- Metin ---
  static const Color textPrimary = Color(0xFFF4F5F7);
  static const Color textSecondary = Color(0xFFBBC1CC);
  static const Color textMuted = Color(0xFF99A1AF);

  // --- Aksiyon (sabit) ---
  /// Birincil buton. Koyu zeminde en parlak öge olması hiyerarşiyi kurar ve
  /// hiçbir hat rengiyle çakışmaz.
  static const Color action = Color(0xFFF4F5F7);
  static const Color onAction = Color(0xFF111317);

  // --- Semantik ---
  /// Yalnız hata ve geçersiz hamle. Aksiyon rengiyle karıştırılmamalı.
  static const Color danger = Color(0xFFFF5C5C);
  static const Color success = Color(0xFF2FB37A);
  static const Color warning = Color(0xFFF5C518);

  /// Oyun kimlik renkleri — her mini oyunun kendi tonu.
  ///
  /// Hat renginden **bağımsız**: oyun kataloğu hangi rotayı seçtiğinle
  /// değişmez, altı oyun her zaman aynı altı renkte görünür. Aksi hâlde
  /// (eskiden olduğu gibi) tüm kartlar seçili hattın tonuna boyanıyor ve
  /// birbirinden ayırt edilemiyordu.
  ///
  /// Renk tek ayrım değil: her oyunun ayrıca kendi çizilmiş glifi var
  /// (`GameGlyph`), yani renk körlüğünde de kartlar ayrışır. Hepsi
  /// [surfaceHigh] üzerinde en az 5.2:1 kontrasta sahip.
  static const Color gameBlocks = Color(0xFFE8A33D);
  static const Color gameMerge = Color(0xFF5BB8E8);
  static const Color gameTunnel = Color(0xFF4FC08D);
  static const Color gameDrop = Color(0xFFD98BB8);
  static const Color gameSequence = Color(0xFFC9A0F0);
  static const Color gameLanes = Color(0xFFF0D95E);

  /// Engel hücresi (zorluk profilinden gelen başlangıç doluluğu).
  static const Color blocker = Color(0xFF535A66);

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
      onColor: readableOn(official),
      onAccent: readableOn(accent),
    );
  }

  /// [background] üzerinde okunabilir metin rengi.
  ///
  /// Sabit bir parlaklık eşiği yetmiyordu: M3 (`#05A8E2`) eşiğin altında
  /// kalıp beyaz metin alıyor, kontrast 2.7:1'de kalıyordu. Bunun yerine iki
  /// aday (beyaz ve koyu zemin) arasından **kontrastı yüksek olan** seçilir;
  /// böylece her hat rengi için elde edilebilecek en iyi okunurluk garanti
  /// olur ve yeni hat eklendiğinde ayar gerekmez.
  static Color readableOn(Color background) =>
      _contrast(Colors.white, background) >=
          _contrast(AppColors.background, background)
      ? Colors.white
      : AppColors.background;

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
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          height: 1.05,
        ),
        headlineSmall: TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 17,
          fontWeight: FontWeight.w700,
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
      // Onay penceresi başlıkları cümle uzunluğunda ve iki satıra taşıyor;
      // başlık fontunda ağır duruyordu.
      dialogTheme: const DialogThemeData(titleTextStyle: AppText.heading),
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

/// Tipografi ölçeği.
///
/// Uygulamada daha önce **85 ayrı `TextStyle`** elle yazılmıştı ve içlerinde
/// 19 farklı punto vardı: 9, 9.5, 10, 11, 12, 12.5, 13, 13.5, 14, 14.5, 15,
/// 15.5, 16, 17, 18, 19, 20, 22, 32. Bu bir ölçek değil, birikmiş
/// tercihlerdi; iki ekranda aynı işi yapan yazı iki farklı boyuttaydı ve
/// tema değiştiğinde hangi yazının nereden beslendiği görünmüyordu.
///
/// Ölçek yedi basamak: **10 · 12 · 13 · 15 · 17 · 20 · 28**. Basamaklar
/// arası oran ~1.15-1.25; bitişik iki basamak gözle ayırt edilebiliyor ama
/// sıçrama yapmıyor. Her basamağın bir işi var:
///
/// | Rol | Punto | Nerede |
/// |---|---|---|
/// | [display] | 28 | açılış tabelası |
/// | [title] | 20 | ekran başlığı |
/// | [lead] | 17 | kart başlığı, panel başlığı |
/// | [body] | 15 | gövde metni |
/// | [caption] | 13 | yardımcı açıklama |
/// | [label] | 12 | büyük harf bölüm etiketi |
/// | [micro] | 10 | rozet, sayaç etiketi |
///
/// Renk **taşınmaz**: her rol kendi varsayılan rengiyle gelir, farklı renk
/// gerektiğinde `copyWith(color: ...)` yazılır. Böylece "bu yazı neden bu
/// renkte" sorusunun cevabı tek satırda görünür.
class AppText {
  const AppText._();

  /// Açılış tabelası. Bungee, sıkı satır arası.
  static const TextStyle display = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.12,
    color: AppColors.textPrimary,
  );

  /// İki satıra taşabilen başlık: onay penceresi, hata ekranı.
  static const TextStyle heading = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  /// Ekran başlığı (AppBar, panel başlığı).
  static const TextStyle title = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  /// Kart başlığı, öne çıkan satır.
  ///
  /// Aile açıkça yazılı: `TextPainter` ile tuvale çizilen rozetler temadan
  /// yazı tipi devralmaz.
  static const TextStyle lead = TextStyle(
    fontFamily: AppFonts.body,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Gövde metni.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  /// Vurgulu gövde.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  /// Yardımcı açıklama.
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.3,
    color: AppColors.textMuted,
  );

  /// Vurgulu yardımcı metin (durak adı, süre).
  static const TextStyle captionStrong = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
  );

  /// Büyük harf bölüm etiketi. Metro tabelası dili: harf arası açık.
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.0,
    color: AppColors.textMuted,
  );

  /// Rozet ve minik sayaç etiketi.
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: AppColors.textMuted,
  );

  /// Değişen büyük sayı — skor, sayaç. Rakamlar sabit genişlikte.
  static const TextStyle stat = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    fontFeatures: kTabularFigures,
    color: AppColors.textPrimary,
  );

  /// Değişen küçük sayı.
  static const TextStyle statSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    fontFeatures: kTabularFigures,
    color: AppColors.textPrimary,
  );
}

/// Değişen sayılar için ortak stil parçası.
///
/// Plus Jakarta Sans'ta rakam genişlikleri eşit değildir: skor 1'den 2'ye geçerken
/// metnin kapladığı yer değişir ve satır oynar. Saniyede bir güncellenen
/// sayaçta ve her hamlede artan skorda bu titreme sürekli görünür.
/// [FontFeature.tabularFigures] rakamları sabit genişliğe sabitler.
const List<FontFeature> kTabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

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
