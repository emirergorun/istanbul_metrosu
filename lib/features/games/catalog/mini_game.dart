import 'package:flutter/material.dart';

import '../../../app/theme.dart';

import 'game_cover_art.dart';
import 'game_glyph.dart';

/// Yolculuk sırasında oynanabilecek bir oyun.
///
/// Uygulama tek oyunla başladı; artık yolculuk ve oyun ayrı seçimler.
/// Rota "ne kadar oynayacağını", oyun ise "ne oynayacağını" belirler.
@immutable
class MiniGame {
  const MiniGame({
    required this.id,
    required this.name,
    required this.tagline,
    required this.glyph,
    required this.color,
    required this.coverScene,
    required this.description,
    required this.objective,
    this.coverAsset,
    this.coverIsLight = false,
    this.howToPlay = const <String>[],
    this.isAvailable = false,
  });

  /// Kalıcı kimlik — kayıtlarda ve rekorlarda kullanılabilir, değiştirilmemeli.
  final String id;

  final String name;

  /// Kartta adın altında görünen tek cümlelik tanım.
  final String tagline;

  /// Kartta görünen elle çizilmiş şekil. Stok `Icons.*` kullanılmaz —
  /// gerekçesi [GameGlyph] üzerinde.
  final GameGlyph glyph;

  /// Glifin rengi; seçili hattan bağımsız. Yalnız glifi boyar, kutuyu
  /// değil — gerekçesi [AppColors.gameGlyphBox] üzerinde.
  final Color color;

  /// Kapak sahnesi. Galeri kartı ve tanıtım ekranı **aynı** sahneyi
  /// kullanır; oyuncu iki ekran arasında görsel sürekliliği kaybetmez.
  final GameCoverScene coverScene;

  /// Üretilmiş raster kapak. Doluysa çizim yerine bu görsel kullanılır.
  ///
  /// Bugün hiçbir oyunda dolu değil: depoda yedi oyun için üretilmiş kapak
  /// görseli yok ve kod ortamında üretilen bir yer tutucu, elde çizilmiş
  /// sahneden daha kötü sonuç verirdi. Mimari hazır — sanat çalışması
  /// bittiğinde tek yapılacak bu alanı doldurmak.
  final String? coverAsset;

  /// Detay ekranındaki tek cümlelik tanıtım. Ne oynadığını söyler.
  final String description;

  /// Detay ekranındaki **AMAÇ**: nasıl kazanılır, ne zaman biter.
  ///
  /// Her oyuna özgü yazılır; "en yüksek skoru yap" yedi oyunun hiçbirini
  /// anlatmaz.
  final String objective;

  /// Kapağın başlık alanı açık renk mi?
  ///
  /// Kapak bir görselse zemin rengi kimlik renginden türetilemez: Yolcu
  /// Topla açık mavi gökyüzü, Metro Bilgi sarı. O kapaklarda beyaz başlık
  /// okunmuyor. Değer görselin başlık bandı ölçülerek bir kez belirlendi.
  final bool coverIsLight;

  /// Kontrolü gerçekten açıklama gerektiren oyunlar için en fazla üç adım.
  ///
  /// Boş bırakılan oyunlarda detay ekranında "Nasıl oynanır?" düğmesi hiç
  /// çıkmaz: dokunup parça yerleştiren bir oyuna üç adımlık kılavuz
  /// yazmak oyuncuyu yavaşlatmaktan başka bir şey yapmaz.
  final List<String> howToPlay;

  /// `false` ise kart kilitli görünür ve seçilemez.
  final bool isAvailable;

  bool get hasHowToPlay => howToPlay.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MiniGame && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MiniGame($id, ${isAvailable ? "açık" : "kilitli"})';
}

/// Oyun kataloğu.
///
/// Yeni bir oyun eklemek için buraya kayıt eklemek ve `isAvailable`'ı `true`
/// yapmak yeterli; seçim ekranı listeyi olduğu gibi çizer.
///
/// TODO(PROD): Kilitli üç oyunun adları **yer tutucudur**; ürün kararı
/// verildiğinde değiştirilecek. `id` alanları değişmemeli.
class MiniGames {
  const MiniGames._();

  static const MiniGame blocks = MiniGame(
    id: 'blocks',
    coverAsset: 'assets/images/games/blok_metro_cover.png',
    coverIsLight: true,
    name: 'Blok Metro',
    tagline: 'Parçaları yerleştir, dolan satır ve sütunları temizle.',
    glyph: GameGlyph.blocks,
    color: AppColors.gameBlocks,
    coverScene: GameCoverScene.blocks,
    description:
        'Tepsideki parçaları tahtaya sürükle, dolan satır ve sütunları '
        'temizle.',
    objective:
        'Tam dolan her satır ve sütun temizlenir ve puan yazar. Tepsideki '
        'üç parçadan hiçbiri tahtaya sığmadığında oyun biter.',
    isAvailable: true,
  );

  static const MiniGame metroMerge = MiniGame(
    id: 'metro_merge',
    coverAsset: 'assets/images/games/hat_birlestir_cover.png',
    name: 'Hat Birleştir',
    tagline: 'M1 hatlarını birleştir, M2 ve M3 seviyelerine yükselt.',
    glyph: GameGlyph.merge,
    color: AppColors.gameMerge,
    coverScene: GameCoverScene.merge,
    description:
        'Karoları kaydır, aynı hattaki iki treni birleştir ve bir üst hatta '
        'çıkar.',
    objective:
        'Birleşen her karo değeri kadar puan yazar ve bir üst hattın treni '
        'olur. Tahta dolduğunda ve birleşecek komşu karo kalmadığında oyun '
        'biter.',
    isAvailable: true,
  );

  static const MiniGame railFlight = MiniGame(
    id: 'rail_flight',
    coverAsset: 'assets/images/games/ray_ucusu_cover.png',
    coverIsLight: true,
    name: 'Ray Uçuşu',
    tagline: 'Treni uçur, raylara çarpmadan tünellerden geç.',
    glyph: GameGlyph.tunnel,
    color: AppColors.gameRail,
    coverScene: GameCoverScene.tunnel,
    description:
        'Treni havada tut ve tünel duvarları arasındaki açıklıklardan '
        'geçir.',
    objective:
        'Geçtiğin her açıklık puan yazar. Tünele ya da ekranın altına '
        'çarptığında oyun biter.',
    howToPlay: <String>[
      'Ekrana her dokunuşta tren bir tık yukarı çıkar.',
      'Dokunmazsan alçalır; açıklığın hizasını dokunuş ritmiyle tuttur.',
      'Duvara ya da zemine değdiğinde yolculuk orada biter.',
    ],
    isAvailable: true,
  );

  static const MiniGame mergeDrop = MiniGame(
    id: 'merge_drop',
    coverAsset: 'assets/images/games/hat_dusur_cover.png',
    name: 'Hat Düşür',
    tagline: 'M1 rozetlerini düşür, aynı hatları M7’ye kadar büyüt.',
    glyph: GameGlyph.drop,
    color: AppColors.gameDrop,
    coverScene: GameCoverScene.drop,
    description:
        'Hat rozetlerini havuza bırak; değen iki eş rozet birleşip bir üst '
        'hatta büyür.',
    objective:
        'Aynı hattan iki rozet birleşince bir üst hat doğar ve puan yazar. '
        'Yığın tepedeki tehlike çizgisine oturduğunda oyun biter.',
    isAvailable: true,
  );

  /// Eski `station_memory` (Durak Hafıza) oyununun yerini aldı.
  ///
  /// Kimlik bilerek yeni: oyun ezberden bilgiye döndü, eski rekorlar bu
  /// oyunla karşılaştırılabilir değil. Eski kimliğin rekorları kayıtlarda
  /// duruyor ama hiçbir ekranda görünmüyor.
  static const MiniGame metroQuiz = MiniGame(
    id: 'metro_quiz',
    coverAsset: 'assets/images/games/metro_bilgi_cover.png',
    coverIsLight: true,
    name: 'Metro Bilgi',
    tagline: 'Durakları ve İstanbul’u bil, seriyi bozma.',
    glyph: GameGlyph.quiz,
    color: AppColors.gameQuiz,
    coverScene: GameCoverScene.quiz,
    description:
        'İstanbul ve metro üzerine sorular; dört şıktan doğru olanı süre '
        'dolmadan seç.',
    objective:
        'Doğru cevap puan yazar, seri büyüdükçe kazanç artar. Üç canın da '
        'bitmesi oyunu bitirir; cevaplayamadığın soru da bir can götürür.',
    isAvailable: true,
  );

  static const MiniGame laneRunner = MiniGame(
    id: 'lane_runner',
    coverAsset: 'assets/images/games/ray_degistir_cover.png',
    name: 'Ray Değiştir',
    tagline: 'Kapalı raylardan kaç, treni M7’ye kadar yükselt.',
    glyph: GameGlyph.lanes,
    color: AppColors.gameLanes,
    coverScene: GameCoverScene.lanes,
    description:
        'Üç ray arasında geçiş yap, kapalı raylara çarpmadan ilerlemeyi '
        'sürdür.',
    objective:
        'Geçtiğin her engel puan yazar ve tren sırayla üst hatlara çıkar. '
        'Kapalı bir raya çarptığında oyun biter.',
    howToPlay: <String>[
      'Ekranın soluna ya da sağına dokunarak tren bir ray yana kayar.',
      'Alttaki iki düğme de aynı işi yapar.',
      'Kapalı rayın hizasına gelmeden şerit değiştir.',
    ],
    isAvailable: true,
  );

  static const MiniGame trainSnake = MiniGame(
    id: 'train_snake',
    coverAsset: 'assets/images/games/yolcu_topla_cover.png',
    coverIsLight: true,
    name: 'Yolcu Topla',
    tagline: 'Yolcuları topla, vagon vagon uzayıp M11’e kadar büyü.',
    glyph: GameGlyph.snake,
    color: AppColors.gameSnake,
    coverScene: GameCoverScene.snake,
    description:
        'Treni ızgarada yönlendir, yolcuları topla ve her yolcuda bir vagon '
        'daha uza.',
    objective:
        'Toplanan her beş yolcu bir üst hatta taşır; elli yolcuda M11’e '
        'ulaşıp yolculuğu kazanırsın. Kenardan çıkan tren karşıdan girer; '
        'kendi vagonuna çarpınca biter.',
    howToPlay: <String>[
      'Alttaki yön pedinin bir koluna bas; tren o yöne döner.',
      'Tahtada parmağını kaydırmak da aynı işi yapar.',
      'Geldiğin yönün tam tersine dönülemez; o kol sönük durur.',
    ],
    isAvailable: true,
  );

  static const MiniGame transfer = MiniGame(
    id: 'transfer',
    name: 'Aktarma',
    tagline: 'Yolcuları doğru hatta yönlendir.',
    glyph: GameGlyph.locked,
    color: AppColors.gameGlyphLocked,
    coverScene: GameCoverScene.locked,
    description: 'Bu oyun henüz hazır değil.',
    objective: 'Yakında eklenecek.',
  );

  static const MiniGame signal = MiniGame(
    id: 'signal',
    name: 'Sinyal',
    tagline: 'Işıkları zamanında çevir, trenleri çarpıştırma.',
    glyph: GameGlyph.locked,
    color: AppColors.gameGlyphLocked,
    coverScene: GameCoverScene.locked,
    description: 'Bu oyun henüz hazır değil.',
    objective: 'Yakında eklenecek.',
  );

  static const MiniGame wagon = MiniGame(
    id: 'wagon',
    name: 'Vagon',
    tagline: 'Vagonları en verimli şekilde doldur.',
    glyph: GameGlyph.locked,
    color: AppColors.gameGlyphLocked,
    coverScene: GameCoverScene.locked,
    description: 'Bu oyun henüz hazır değil.',
    objective: 'Yakında eklenecek.',
  );

  /// Oynanabilir oyunlar — galeri ve detay bu listeyi kullanır.
  static List<MiniGame> get playable =>
      all.where((MiniGame g) => g.isAvailable).toList();

  /// Kimliği verilen oyun; katalogda yoksa `null`.
  static MiniGame? byId(String id) {
    for (final game in all) {
      if (game.id == id) return game;
    }
    return null;
  }

  /// Listedeki sıra **ürün kararı**: kartlar bu sırayla çizilir.
  ///
  /// Metro Bilgi ikinci sırada. Katalog önce eklenme sırasındaydı ve
  /// oyunun en çok oynanması beklenen ikinci başlığı listenin beşinci
  /// kartıydı — ekranda kaydırmadan görünmüyordu.
  static const List<MiniGame> all = <MiniGame>[
    blocks,
    metroQuiz,
    metroMerge,
    railFlight,
    mergeDrop,
    laneRunner,
    trainSnake,
    transfer,
    signal,
    wagon,
  ];
}
