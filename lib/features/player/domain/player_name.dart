import 'dart:math';

/// Oyuncu adı — **oyuncu yazmaz, sistem üretir.**
///
/// Serbest metin kullanıcı adı bilinçli olarak reddedildi. Yasaklı kelime
/// listesi işe yaramıyor: boşluk, nokta, benzer harf ve Türkçe karakter
/// varyasyonuyla her liste dakikalar içinde aşılıyor. Gerçek moderasyon
/// sunucu tarafı denetim, şikayet akışı ve ad değiştirme yetkisi demek;
/// bu ürünün ölçeğinde karşılanamaz.
///
/// Bunun yerine ad iki parçadan kurulur ve **iki parça da bu dosyadaki
/// listelerden gelir**. Uygunsuz ad üretmek imkânsız, çünkü sözlüğün
/// tamamı burada yazılı.
///
/// Yan fayda: adlar oyunun temasını taşıyor. Skor tablosunda `ahmet1234`
/// değil `M4 Gece Kuşu` görünüyor.
class PlayerName {
  const PlayerName._();

  /// Adın ilk parçası.
  ///
  /// Hepsi olumlu ya da nötr. Aşağılayıcı, alaycı ya da iki anlamlı
  /// sıfat yok: oyuncu kendi adını beğenmezse yenileyebilir ama
  /// beğenmediği ad onu rahatsız etmemeli.
  static const List<String> adjectives = <String>[
    'Hızlı',
    'Sessiz',
    'Gece',
    'Sabah',
    'Erken',
    'Geç',
    'Uykusuz',
    'Dalgın',
    'Dikkatli',
    'Sabırlı',
    'Aceleci',
    'Kararlı',
    'Uyanık',
    'Yorgun',
    'Neşeli',
    'Sakin',
    'Çevik',
    'Usta',
    'Acemi',
    'Kıdemli',
    'Gezgin',
    'Şanslı',
    'Cesur',
    'Meraklı',
    'Keskin',
    'Atik',
    'Zinde',
    'Dikkatsiz',
    'Dakik',
    'Rötarlı',
    'Ayakta',
    'Oturan',
    'Koşan',
    'Yetişen',
    'Kaçıran',
    'Bekleyen',
    'Aktaran',
    'Dönen',
    'Kayan',
    'Duran',
    'Kalabalık',
    'Tenha',
    'Sıcak',
    'Serin',
    'Yağmurlu',
    'Rüzgârlı',
    'Puslu',
    'Aydınlık',
    'Karanlık',
    'Derin',
    'Yüzeydeki',
    'Son',
    'İlk',
    'Orta',
    'Yan',
    'Ters',
    'Düz',
    'Uzun',
    'Kısa',
    'Tek',
  ];

  /// Adın ikinci parçası.
  ///
  /// Üç aile karışık: metro kavramları, İstanbul semtleri ve hayvanlar.
  /// Karışıklık kasıtlı — tek aileden gelen adlar üç dört tanesinden
  /// sonra birbirine benziyor.
  static const List<String> nouns = <String>[
    'Yolcu',
    'Vagon',
    'Peron',
    'Turnike',
    'Aktarma',
    'Sefer',
    'Makinist',
    'Bilet',
    'Raylar',
    'Tünel',
    'Durak',
    'Hat',
    'Vinç',
    'Sinyal',
    'Kondüktör',
    'Kart',
    'Kapı',
    'Tabela',
    'Merdiven',
    'Asansör',
    'Kadıköylü',
    'Üsküdarlı',
    'Beşiktaşlı',
    'Levent',
    'Taksim',
    'Yenikapı',
    'Mecidiyeköy',
    'Bostancı',
    'Kartal',
    'Şişli',
    'Bakırköy',
    'Zeytinburnu',
    'Ataşehir',
    'Maltepe',
    'Eminönü',
    'Karaköy',
    'Beyoğlu',
    'Sarıyer',
    'Pendik',
    'Çekmeköy',
    'Kaplan',
    'Şahin',
    'Kartal Kuşu',
    'Baykuş',
    'Tilki',
    'Kedi',
    'Martı',
    'Balık',
    'Ayı',
    'Kurt',
    'Geyik',
    'Tavşan',
    'Sincap',
    'Köpekbalığı',
    'Yunus',
    'Kirpi',
    'Leylek',
    'Kelebek',
    'Arı',
    'Yıldız',
  ];

  /// Üretilebilecek farklı ad sayısı (sonek hariç).
  static int get combinationCount => adjectives.length * nouns.length;

  /// Rastgele bir ad üretir.
  ///
  /// Aynı ad iki oyuncuda çıkabilir ve bu **sorun değil**: rekorlar
  /// cihazda tutuluyor, ad yalnızca bir imza. İleride ortak bir skor
  /// tablosu gelirse ayırt etme işini [discriminator] yapar.
  static String random([Random? random]) {
    final rng = random ?? Random();
    final adjective = adjectives[rng.nextInt(adjectives.length)];
    final noun = nouns[rng.nextInt(nouns.length)];
    return '$adjective $noun';
  }

  /// Aynı adı taşıyan oyuncuları ayıran dört haneli sonek (`#7F3A`).
  ///
  /// Şu anda ekranda gösterilmiyor; ortak skor tablosu geldiğinde
  /// gerekecek. Cihazda bir kez üretilip saklanır, ad değişse bile
  /// aynı kalır — sonek kimliği, ad görünen yüzü.
  static String discriminator([Random? random]) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rng = random ?? Random();
    return List<String>.generate(
      4,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
  }

  /// Bu ad bu dosyadaki sözlükten üretilmiş olabilir mi?
  ///
  /// Kayıttan okunan ad doğrulanır: elle düzenlenmiş bir tercih dosyası
  /// uygulamaya rastgele metin sokamaz.
  static bool isValid(String name) {
    final parts = name.split(' ');
    if (parts.length < 2) return false;
    final adjective = parts.first;
    final noun = parts.sublist(1).join(' ');
    return adjectives.contains(adjective) && nouns.contains(noun);
  }
}
