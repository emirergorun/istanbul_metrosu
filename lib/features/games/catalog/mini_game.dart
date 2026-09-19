import 'package:flutter/material.dart';

import '../../../app/theme.dart';

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

  /// `false` ise kart kilitli görünür ve seçilemez.
  final bool isAvailable;

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
    name: 'Blok Metro',
    tagline: 'Parçaları yerleştir, dolan satır ve sütunları temizle.',
    glyph: GameGlyph.blocks,
    color: AppColors.gameBlocks,
    isAvailable: true,
  );

  static const MiniGame metroMerge = MiniGame(
    id: 'metro_merge',
    name: 'Hat Birleştir',
    tagline: 'M1 hatlarını birleştir, M2 ve M3 seviyelerine yükselt.',
    glyph: GameGlyph.merge,
    color: AppColors.gameMerge,
    isAvailable: true,
  );

  static const MiniGame railFlight = MiniGame(
    id: 'rail_flight',
    name: 'Ray Uçuşu',
    tagline: 'Treni uçur, raylara çarpmadan tünellerden geç.',
    glyph: GameGlyph.tunnel,
    color: AppColors.gameRail,
    isAvailable: true,
  );

  static const MiniGame mergeDrop = MiniGame(
    id: 'merge_drop',
    name: 'Hat Düşür',
    tagline: 'M1 rozetlerini düşür, aynı hatları M7’ye kadar büyüt.',
    glyph: GameGlyph.drop,
    color: AppColors.gameDrop,
    isAvailable: true,
  );

  /// Eski `station_memory` (Durak Hafıza) oyununun yerini aldı.
  ///
  /// Kimlik bilerek yeni: oyun ezberden bilgiye döndü, eski rekorlar bu
  /// oyunla karşılaştırılabilir değil. Eski kimliğin rekorları kayıtlarda
  /// duruyor ama hiçbir ekranda görünmüyor.
  static const MiniGame metroQuiz = MiniGame(
    id: 'metro_quiz',
    name: 'Metro Bilgi',
    tagline: 'Durakları ve İstanbul’u bil, seriyi bozma.',
    glyph: GameGlyph.quiz,
    color: AppColors.gameQuiz,
    isAvailable: true,
  );

  static const MiniGame laneRunner = MiniGame(
    id: 'lane_runner',
    name: 'Ray Değiştir',
    tagline: 'Kapalı raylardan kaç, treni M7’ye kadar yükselt.',
    glyph: GameGlyph.lanes,
    color: AppColors.gameLanes,
    isAvailable: true,
  );

  static const MiniGame trainSnake = MiniGame(
    id: 'train_snake',
    name: 'Yolcu Topla',
    tagline: 'Yolcuları topla, vagon vagon uzayıp M11’e kadar büyü.',
    glyph: GameGlyph.snake,
    color: AppColors.gameSnake,
    isAvailable: true,
  );

  static const MiniGame transfer = MiniGame(
    id: 'transfer',
    name: 'Aktarma',
    tagline: 'Yolcuları doğru hatta yönlendir.',
    glyph: GameGlyph.locked,
    color: AppColors.gameGlyphLocked,
  );

  static const MiniGame signal = MiniGame(
    id: 'signal',
    name: 'Sinyal',
    tagline: 'Işıkları zamanında çevir, trenleri çarpıştırma.',
    glyph: GameGlyph.locked,
    color: AppColors.gameGlyphLocked,
  );

  static const MiniGame wagon = MiniGame(
    id: 'wagon',
    name: 'Vagon',
    tagline: 'Vagonları en verimli şekilde doldur.',
    glyph: GameGlyph.locked,
    color: AppColors.gameGlyphLocked,
  );

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
