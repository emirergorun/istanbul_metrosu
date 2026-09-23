import 'package:flutter/material.dart';

/// Tipografi.
///
/// Kısa, büyük başlıklarda **Bungee**; diğer her yerde **M PLUS Rounded
/// 1c**. İkisi de SIL OFL 1.1.
///
/// Bungee iri, tabela karakterli bir yazı tipidir: yalnızca ~20 punto ve
/// üstündeki, **tek satıra sığan** başlıklarda okunur. İki satıra taşan
/// cümleler (onay penceresi başlıkları gibi) bu fontta ağır duruyordu; onlar
/// M PLUS Rounded 1c ExtraBold'dadır. Tek ağırlığı var (400); daha kalın
/// istenirse Flutter sahte kalınlaştırma yapıp harfleri bozar. Skor, rozet ve
/// etiket gibi küçük ya da sık değişen metinler de M PLUS Rounded 1c'dedir.
///
/// Bungee Türkçe için değiştirildi: özgün dosya küçük `i`'yi noktasız
/// `I` çiziyor ve Türkçe `locl` kuralı yok, "girdin" ekranda "GIRDIN"
/// okunuyordu. `cmap` içinde `i` → `İ` eşlendi; metinler değişmeden doğru
/// görünür.
///
/// M PLUS Rounded 1c yuvarlak uçlu bir gotik: metro tabelası diliyle
/// (Bungee) aynı ailede değil ama aynı karakterde — geometrik, tok, küçük
/// puntoda da kapanmayan sayaçlara sahip. Türkçe'nin tamamını kapsar
/// (Ç ç Ğ ğ İ ı Ö ö Ş ş Ü ü doğrulandı); 400 / 500 / 700 / 800 ağırlıkları
/// paketlenir.
class AppFonts {
  const AppFonts._();

  /// Yalnızca büyük başlıklar (≥ 20 pt). Tek ağırlık: `FontWeight.w400`.
  static const String display = 'Bungee';

  /// Gövde, düğme, skor, etiketler ve uzun başlıklar.
  /// Ağırlıklar: 400, 500, 700, 800.
  static const String body = 'M PLUS Rounded 1c';
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

  /// Oyun kartı simgesinin arkasındaki kutu — **her oyunda aynı**.
  ///
  /// Kutu bir zamanlar oyunun renginin soluk hâliyle doluyordu ve altı
  /// kart altı renkli lekeye dönüyordu; ekrandaki gerçek renk sistemiyle
  /// (hat kimliği) yarışıyordu. Renk artık yalnızca glifin kendisinde,
  /// yani çok küçük bir alanda. Liste sakin kalıyor, oyunun tonu yine de
  /// görünüyor.
  static const Color gameGlyphBox = Color(0xFF3A3F48);

  /// Kilitli oyunun glifi.
  static const Color gameGlyphLocked = Color(0xFF99A1AF);

  /// Oyun glif renkleri.
  ///
  /// Önceki set altı pastel tondan oluşuyordu (turuncu, gök mavisi, nane
  /// yeşili, pastel pembe, lavanta, sarı): hepsi aynı parlaklıkta, aynı
  /// doygunlukta ve birbirine yakın. Bu kombinasyon bir palet değil,
  /// varsayılan bir dolgu gibi okunuyordu.
  ///
  /// Yenisinde iki kural var:
  ///
  /// 1. **Renk çemberine yayılmış.** Ton açıları 40° / 85° / 160° / 195° /
  ///    275° / 340°; en dar aralık 35°, yani hiçbir ikisi kardeş değil.
  /// 2. **Doygun ve koyu zeminde okunur.** Hepsi glif kutusunda
  ///    ([gameGlyphBox]) en az 3.9:1 — WCAG'in ince grafik nesne sınırı
  ///    3.0.
  ///
  /// Renk **tek ayrım değil**: her oyunun kendi çizilmiş glifi ve tabela
  /// fontuyla yazılmış adı var, renk körlüğünde de kartlar ayrışır.
  static const Color gameBlocks = Color(0xFFFFB020);
  static const Color gameQuiz = Color(0xFFC77DFF);
  static const Color gameMerge = Color(0xFF4CC9F0);
  static const Color gameRail = Color(0xFF2DD4A0);
  static const Color gameDrop = Color(0xFFFF6B9D);
  static const Color gameLanes = Color(0xFFA8E05F);

  /// Ton açısı ~234°: gameMerge (195°) ve gameQuiz (275°) arasındaki en
  /// geniş boşluğa yerleşir, ikisinden de en az 35° uzak. [gameGlyphBox]
  /// üzerinde ~4.0:1 kontrast — 3.9:1 sınırının üstünde.
  static const Color gameSnake = Color(0xFF8C97FF);

  /// Ton açısı ~122°: gameLanes (85°) ile gameRail (160°) arasındaki tek
  /// kalan boşluk, ikisine de 37-38° uzak. Sekizinci oyun eklenirken
  /// çemberde bundan daha geniş bir aralık kalmamıştı; dokuzuncu oyun
  /// gelirse kuralı 35°'nin altına çekmek yerine renk **tek ayrım
  /// olmadığı** için gliften ayrışmak daha doğru olur.
  static const Color gameCrossing = Color(0xFF57DB5B);

  /// Ton açısı ~308°: çemberde kalan en geniş boşluk olan gameQuiz (276°)
  /// ile gameDrop (340°) arasının tam ortası — ikisine de ~32° uzak.
  /// Dokuzuncu oyunda 35° kuralı artık tutmuyor (bkz. [gameCrossing]);
  /// ayrımın yükünü glif taşıyor, renk destekliyor. Glif kutusunda
  /// kontrast 3,96:1 — 3:1 sınırının üstünde.
  static const Color gameMetroLine = Color(0xFFEB70DA);

  /// Ton açısı ~11°: çemberde kalan en geniş boşluk gameDrop (340°) ile
  /// gameBlocks (40°) arasıydı; ikisine de ~29° uzak. Tünele Kaç'ın
  /// kırmızı metrosunun açılmış tonu — oyunun kimliği o metro. Glif
  /// kutusunda kontrast ~4,1:1.
  static const Color gameTunnelEscape = Color(0xFFFF7A5C);

  /// Metro Bilgi kategori simgelerinin renkleri.
  ///
  /// Hat renklerinden ve oyun kimlik renklerinden **bağımsız**: kategori
  /// hangi hatta oynandığınla ilgili değil. Okabe–Ito ailesinden seçildi,
  /// altısı da renk körlüğü altında ayrışıyor ve kart yüzeyinde
  /// ([surfaceHigh]) en az 3.6:1 kontrasta sahip — WCAG'in ince grafik
  /// nesne sınırı 3.0.
  ///
  /// Renk **tek ayrım değil**: her kategorinin ayrıca kendi çizilmiş
  /// simgesi ve yanında tam adı var.
  static const Color categoryHistory = Color(0xFFE69F00);
  static const Color categoryCultureArt = Color(0xFFCC79A7);
  static const Color categorySports = Color(0xFF009E73);
  static const Color categoryGeography = Color(0xFF56B4E9);
  static const Color categoryIstanbul = Color(0xFFF0E442);
  static const Color categoryGeneral = Color(0xFFB08AE8);

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
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          // Birincil eylem tabela fontunda: ekranın en yüksek sesli ögesi
          // ve metni kısa, büyük harf — Bungee'nin tam işi.
          //
          // 16 punto ölçülerek seçildi: en dar ekranda (320 px) ve en büyük
          // yazı ölçeğinde (1.6×) "SONUCU PAYLAŞ" 221 px, kullanılabilir
          // genişlik 240 px. Tek taşan metin "YOLCULUĞU BAŞLAT"tı (276 px);
          // o yüzden "BAŞLA" olarak kısaltıldı.
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(50),
          side: const BorderSide(color: AppColors.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 14,
            letterSpacing: 0.5,
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
    fontSize: 38,
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
  ///
  /// Kart başlığından ([tileTitle], 17) belirgin şekilde büyük olmalı:
  /// ikisi 24/18 iken aynı hiyerarşide okunuyor, "OYUN SEÇ" ile oyun
  /// adları yarışıyordu. 26/17 arası %53 fark var.
  static const TextStyle title = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 26,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  /// Liste kartı başlığı — oyun adı, tabela dili.
  ///
  /// Bungee tek ağırlıklıdır ve iri çizer; 17 punto bu ailenin pratik
  /// küçük sınırı. Ekran başlığıyla ([title], 26) aynı ses ama açıkça
  /// bir basamak aşağıda.
  static const TextStyle tileTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.2,
    letterSpacing: 0.2,
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
  ///
  /// 14'ten 15'e çıkarıldı ve satır arası açıldı: oyun tanıtım ekranındaki
  /// açıklama ve AMAÇ metni 14 puntoda telefonu uzağa tutan bir oyuncu için
  /// küçük kalıyordu. Ölçümde 15 punto, 320 px genişlikte en uzun amaç
  /// metnini 4 satırda bitiriyor (16 puntoda 5 satır).
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  /// Vurgulu gövde — şık kutusu, listede seçilebilir satır.
  ///
  /// Gövdeden **hem punto hem ağırlıkla** ayrılır. İkisi 15 punto ve yalnız
  /// ağırlıkla ayrışırken fark M PLUS Rounded 1c'de kayboluyordu: yuvarlak
  /// uçlar kalınlık farkını yutuyor. w700 yerine w500, çünkü 17 puntoda
  /// kalınlığa ihtiyaç kalmıyor ve w700 şık kutusunu bağırtıyordu.
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
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

  /// Ekran bölümü başlığı — **tabela fontunda ve okunur puntoda**.
  ///
  /// İSTANBUL KEŞFİ, HATLAR, AMAÇ, YOLCULUĞUN, YENİ KEŞİFLER: bunlar bir
  /// rozet yazısı değil, ekranın bölümlerini ayıran başlıklar. [label] ile
  /// aynı 13 puntodayken devasa sayaçların ve kartların yanında kayboluyor,
  /// bölüm başlığı gibi değil dipnot gibi okunuyorlardı.
  ///
  /// 16 punto ölçüldü: en dar ekranda (320 px) 1.6× yazı ölçeğinde en uzun
  /// başlık 239 px, kullanılabilir 288 px.
  ///
  /// [label]'dan ayrı tutuluyor çünkü o, oyun içi HUD'da ve ayarlarda da
  /// kullanılıyor; oradaki dar satırları büyütmek taşma üretir.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 16,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  /// Küçük büyük harf etiket — **tabela fontunda**.
  ///
  /// AMAÇ, YOLCULUĞUN, İSTANBUL KEŞFİ, HATLAR, YENİ KEŞİFLER: hepsi kısa,
  /// büyük harf ve kullanıcı verisi değil. Bungee'nin doğru kullanımı tam
  /// olarak burası. Gövde fontundayken bölüm başlıkları metnin içinde
  /// kayboluyordu.
  ///
  /// 13 punto ölçüldü: en dar ekranda (320 px) 1.6× ölçekte en uzun etiket
  /// ("NASIL OYNANIR?") 194 px, kullanılabilir 288 px.
  ///
  /// Harf arası Bungee'de açılmıyor: font zaten geniş, 1.0 boşluk kelimeyi
  /// dağıtıyordu.
  static const TextStyle label = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 13,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
  );

  /// Rozet ve minik sayaç etiketi.
  static const TextStyle micro = TextStyle(
    fontSize: 11,
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
/// M PLUS Rounded 1c'de rakam genişlikleri eşit değildir: skor 1'den 2'ye geçerken
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

  /// Üst üste dizilen bloklar arasındaki **tek** boşluk.
  ///
  /// Kural: bir sütunda alt alta duran kartlar, şeritler ve düğmeler her
  /// zaman bu değerle ayrılır. Ayrı ayrı seçilmiş boşluklar (8 burada, 24
  /// şurada, 12 ötede) ekranda dağınık bir ritim üretiyordu — bloklar aynı
  /// aileye ait görünmüyordu.
  ///
  /// Hiyerarşi boşlukla değil **başlıkla** kurulur: yeni bir bölüm
  /// başlıyorsa araya [sectionGap] ve bir bölüm başlığı girer. Bir bloğu
  /// öne çıkarmak için boşluğu büyütmek yerine bloğun kendi ağırlığı
  /// (dolgu rengi, punto, kenarlık) kullanılır.
  ///
  /// Yeni ekran eklerken bu iki değerin dışına çıkma.
  static const double stack = md;

  /// Bölüm başlığıyla başlayan yeni bir bloğun üstündeki boşluk.
  static const double sectionGap = xl;

  static const double cardRadius = 8;
  static const double fieldRadius = 6;
  static const double cellRadius = 6;
}
