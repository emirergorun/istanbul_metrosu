import 'package:flutter/foundation.dart';

import '../../games/catalog/mini_game.dart';

/// Başarımın hangi oyunculuk alanından geldiği.
///
/// Kartta gruplamak için: yirmi başarım tek bir listede sıralanırsa
/// oyuncu neye bakacağını bilemez.
enum AchievementCategory {
  exploration('Keşif'),
  journey('Yolculuk'),
  gameplay('Oyun'),
  daily('Günlük');

  const AchievementCategory(this.label);

  final String label;
}

/// Başarımın ilerlemesini hangi ölçüden aldığı.
///
/// Hepsinin ortak şartı: değer **zaten tutulan** bir kayıttan okunabilmeli.
/// Kendi sayacını isteyen bir başarım buraya girmez — ikinci sayaç, birinci
/// kayıttan er geç ayrı düşer.
enum AchievementMetric {
  /// Keşfedilen fiziksel durak sayısı — kalıcı keşif kaydından.
  stationsDiscovered,

  /// Keşfedilen aktarma durağı sayısı — keşif kaydı ve katalogdan türer.
  interchangesDiscovered,

  /// Tamamlanan hat sayısı — keşif kaydından türer.
  linesCompleted,

  /// Sonuna kadar götürülen yolculuk sayısı.
  journeysCompleted,

  /// Kaç farklı oyun bitirildi.
  distinctGamesPlayed,

  /// En uzun günlük seri.
  bestStreak,

  /// Ömür boyu tamamlanan günlük yolculuk sayısı.
  dailyDaysCompleted,

  /// Metro Bilgi'de kurulmuş en yüksek skor.
  ///
  /// Kayıtlı rota rekorlarından okunuyor; ikinci bir sayaç tutulmuyor.
  bestQuizScore,

  /// Tek bir oyunda bitirilen anlamlı koşu sayısı; oyun
  /// [AchievementDefinition.gameId] ile seçilir.
  gameRunsFinished,
}

/// Bir başarımın tanımı — kalıcı kimlik, metin ve hedef.
///
/// Kimlik [id]'dir, başlık değil: başlık düzeltilebilir ya da çevrilebilir,
/// kayıtlı açılma bilgisi bundan etkilenmemeli.
@immutable
class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.category,
    required this.metric,
    required this.title,
    required this.description,
    required this.target,
    this.gameId,
  });

  /// Kayıtta duran kalıcı kimlik. Değiştirilmemeli.
  final String id;

  final AchievementCategory category;
  final AchievementMetric metric;

  /// Tabela dilinde, kısa. Büyük harfle çizilir.
  final String title;

  /// Nasıl kazanıldığını söyleyen tek cümle.
  final String description;

  /// Açılması için gereken değer.
  final int target;

  /// Oyuna bağlı ölçülerde hangi oyun; diğerlerinde `null`.
  final String? gameId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AchievementDefinition && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Achievement($id, $target)';
}

/// Uygulamadaki tüm başarımlar.
///
/// Liste **ürün kararı**: kartta bu sırayla çizilir. Kolay olandan zora,
/// kategori kategori. Yeni başarım eklemek için buraya bir kayıt eklemek
/// yeterli; kart listeyi olduğu gibi çizer ve ilerlemeyi kendi hesaplar.
class Achievements {
  const Achievements._();

  static const AchievementDefinition firstJourney = AchievementDefinition(
    id: 'first_journey',
    category: AchievementCategory.journey,
    metric: AchievementMetric.journeysCompleted,
    title: 'İlk Yolculuk',
    description: 'Bir yolculuğu sonuna kadar götür.',
    target: 1,
  );

  static const AchievementDefinition firstDiscovery = AchievementDefinition(
    id: 'first_discovery',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.stationsDiscovered,
    title: 'İlk Keşif',
    description: 'İlk durağını keşfet.',
    target: 1,
  );

  static const AchievementDefinition explorerI = AchievementDefinition(
    id: 'explorer_10',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.stationsDiscovered,
    title: 'İstanbul Kâşifi I',
    description: '10 durak keşfet.',
    target: 10,
  );

  static const AchievementDefinition explorerII = AchievementDefinition(
    id: 'explorer_25',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.stationsDiscovered,
    title: 'İstanbul Kâşifi II',
    description: '25 durak keşfet.',
    target: 25,
  );

  static const AchievementDefinition explorerIII = AchievementDefinition(
    id: 'explorer_50',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.stationsDiscovered,
    title: 'İstanbul Kâşifi III',
    description: '50 durak keşfet.',
    target: 50,
  );

  /// Aktarma durakları veriden **türetilir**: birden çok hatta hizmet veren
  /// fiziksel durak aktarmadır. Elle liste tutulmaz.
  static const AchievementDefinition interchange = AchievementDefinition(
    id: 'interchange_10',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.interchangesDiscovered,
    title: 'Aktarma Ustası',
    description: '10 aktarma durağı keşfet.',
    target: 10,
  );

  static const AchievementDefinition lineComplete = AchievementDefinition(
    id: 'line_complete_1',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.linesCompleted,
    title: 'Hat Tamamlandı',
    description: 'Bir hattın bütün duraklarını keşfet.',
    target: 1,
  );

  static const AchievementDefinition threeLines = AchievementDefinition(
    id: 'line_complete_3',
    category: AchievementCategory.exploration,
    metric: AchievementMetric.linesCompleted,
    title: 'Üç Hat',
    description: 'Üç hattı baştan sona keşfet.',
    target: 3,
  );

  static const AchievementDefinition journeyFive = AchievementDefinition(
    id: 'journey_5',
    category: AchievementCategory.journey,
    metric: AchievementMetric.journeysCompleted,
    title: 'Sık Yolcu',
    description: '5 yolculuğu sonuna kadar götür.',
    target: 5,
  );

  static const AchievementDefinition journeyTwenty = AchievementDefinition(
    id: 'journey_20',
    category: AchievementCategory.journey,
    metric: AchievementMetric.journeysCompleted,
    title: 'Abonman',
    description: '20 yolculuğu sonuna kadar götür.',
    target: 20,
  );

  static const AchievementDefinition gameTraveler = AchievementDefinition(
    id: 'game_traveler',
    category: AchievementCategory.gameplay,
    metric: AchievementMetric.distinctGamesPlayed,
    title: 'Oyun Gezgini',
    description: 'Beş farklı oyun bitir.',
    target: 5,
  );

  /// Metro Bilgi kilometre taşı.
  ///
  /// Eşik mevcut kurallardan hesaplandı: doğru cevap 10 puan, seri çarpanı
  /// en fazla ×4, hız bonusu en fazla 6. Yani iyi giden bir koşuda soru
  /// başına ~30-46 puan. 400 puan, seriyi bir süre ayakta tutmayı gerektiren
  /// ama tek bir uzun rotayla ulaşılabilir bir hedef.
  static const AchievementDefinition quizMilestone = AchievementDefinition(
    id: 'quiz_400',
    category: AchievementCategory.gameplay,
    metric: AchievementMetric.bestQuizScore,
    title: 'Bilgi Yolcusu',
    description: 'Metro Bilgi\'de tek yolculukta 400 puan yap.',
    target: 400,
  );

  /// Günlük sadakat — seriden ayrı ölçü.
  ///
  /// Seri sürekliliği ölçüyor, bu sayı toplam gelişi. Serisi kırılan oyuncu
  /// da ilerlemeye devam edebilsin.
  static const AchievementDefinition thirtyDays = AchievementDefinition(
    id: 'daily_30',
    category: AchievementCategory.daily,
    metric: AchievementMetric.dailyDaysCompleted,
    title: 'Otuz Gün',
    description: 'Toplam 30 gün günün yolculuğunu tamamla.',
    target: 30,
  );

  static const AchievementDefinition streakThree = AchievementDefinition(
    id: 'streak_3',
    category: AchievementCategory.daily,
    metric: AchievementMetric.bestStreak,
    title: 'Üç Günlük Seri',
    description: 'Üç gün üst üste günün yolculuğunu tamamla.',
    target: 3,
  );

  static const AchievementDefinition streakSeven = AchievementDefinition(
    id: 'streak_7',
    category: AchievementCategory.daily,
    metric: AchievementMetric.bestStreak,
    title: 'Yedi Günlük Seri',
    description: 'Yedi gün üst üste günün yolculuğunu tamamla.',
    target: 7,
  );

  /// Bütün oyunları bitirmek — hedef katalogdan **türer**.
  ///
  /// Sabit yazılsaydı sekizinci oyun eklendiği gün başarım yalan söylerdi.
  static AchievementDefinition get everyGame => AchievementDefinition(
    id: 'every_game',
    category: AchievementCategory.gameplay,
    metric: AchievementMetric.distinctGamesPlayed,
    title: 'Bütün Oyunlar',
    description: 'Katalogdaki her oyunu bir kez bitir.',
    target: MiniGames.playable.length,
  );

  static const AchievementDefinition journeyHundred = AchievementDefinition(
    id: 'journey_100',
    category: AchievementCategory.journey,
    metric: AchievementMetric.journeysCompleted,
    title: 'Yüz Yolculuk',
    description: '100 yolculuğu sonuna kadar götür.',
    target: 100,
  );

  /// Oyun ustalığı: koşu sayısı, skor değil — puan rotanın ortak havuzunda.
  ///
  /// Kimlikler oyun controller'larındaki kalıcı kimliklerle aynı; burada
  /// düz metin, çünkü alan katmanı oyun paketlerini içe aktarmamalı.
  static const AchievementDefinition blocksMaster = AchievementDefinition(
    id: 'blocks_runs_10',
    category: AchievementCategory.gameplay,
    metric: AchievementMetric.gameRunsFinished,
    gameId: 'blocks',
    title: 'Blok Ustası',
    description: 'Blok Metro\'da 10 oyun bitir.',
    target: 10,
  );

  static const AchievementDefinition crossingMaster = AchievementDefinition(
    id: 'crossing_runs_10',
    category: AchievementCategory.gameplay,
    metric: AchievementMetric.gameRunsFinished,
    gameId: 'crossing',
    title: 'Karşı Peron',
    description: 'Karşıdan Karşıya\'da 10 oyun bitir.',
    target: 10,
  );

  /// Çizim sırası.
  static List<AchievementDefinition> get all => <AchievementDefinition>[
    firstDiscovery,
    firstJourney,
    explorerI,
    explorerII,
    lineComplete,
    gameTraveler,
    journeyFive,
    streakThree,
    explorerIII,
    interchange,
    quizMilestone,
    blocksMaster,
    crossingMaster,
    threeLines,
    journeyTwenty,
    everyGame,
    streakSeven,
    thirtyDays,
    journeyHundred,
  ];

  static AchievementDefinition? byId(String id) {
    for (final definition in all) {
      if (definition.id == id) return definition;
    }
    return null;
  }
}
