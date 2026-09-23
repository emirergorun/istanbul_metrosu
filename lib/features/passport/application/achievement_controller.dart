import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/telemetry/analytics.dart';
import '../../daily/application/daily_controller.dart';
import '../../daily/domain/day_stamp.dart';
import '../../discovery/application/discovery_controller.dart';
import '../../session/run_report.dart';
import '../domain/achievement.dart';
import '../domain/player_stats.dart';

/// Yolculuk Kartı'nın rozet katmanı.
///
/// Dosya ve sınıf adları (`passport/`, `AchievementController`) kasıtlı
/// olarak korundu: kayıt anahtarları ve testler bunlara bağlı, oyuncuya
/// görünen bir yanları da yok. Ürün adı değişti, kod kimliği değil.
///
/// **Paralel bir ilerleme veritabanı değildir.** Keşfedilen durak sayısını
/// keşif kaydı, seriyi günlük sistem bilir; bu sınıf onları okur ve
/// "hangi rozet açıldı" sorusunu cevaplar. Sakladığı tek şey açılmış
/// başarımların kimlikleri ve türetilemeyen iki ömür sayacıdır.
///
/// Açılma **tek yönlüdür ve tekrarlanamaz**: açılmış bir başarım kapanmaz,
/// aynı başarım iki kez kutlanmaz, uygulama yeniden açılınca yeniden
/// açılmaz.
class AchievementController extends ChangeNotifier implements RunReporter {
  AchievementController({
    required this.discovery,
    this.daily,
    this.store,
    this.analytics = const NoopAnalytics(),
  }) {
    _stats = PlayerStats.decode(store?.playerStatsRaw);
    _unlocked.addAll(_decodeUnlocked(store?.unlockedAchievementIds));

    // İlk kurulum **sessiz**: V4'ten önce 40 durak keşfetmiş bir oyuncuya
    // uygulamayı açar açmaz beş rozet birden patlatmak kutlama değil,
    // gürültü olurdu. Hak edilen rozetler açık gelir, kutlama listesi boş.
    _evaluate(announce: false);

    discovery.addListener(_onSourceChanged);
    daily?.addListener(_onSourceChanged);
  }

  final DiscoveryController discovery;
  final DailyController? daily;
  final LocalStore? store;
  final Analytics analytics;

  PlayerStats _stats = PlayerStats.empty;

  /// Açılmış başarımlar ve açıldıkları gün.
  ///
  /// Gün `null` olabilir: rozet kayıt biçimine tarih eklenmeden önce
  /// açılmışsa ya da geriye dönük göçte verilmişse "ne zaman" sorusunun
  /// dürüst cevabı yok. Uydurulmuyor, boş bırakılıyor.
  final Map<String, DayStamp?> _unlocked = <String, DayStamp?>{};

  /// Bu oturumda **az önce** açılan başarımlar; arayüz bir kez gösterir.
  final List<AchievementDefinition> _justUnlocked = <AchievementDefinition>[];

  bool _disposed = false;

  // --- Türetilen görünüm ---

  PlayerStats get stats => _stats;

  List<AchievementDefinition> get definitions => Achievements.all;

  /// Başarım açık mı?
  ///
  /// Kayda **ve** o anki ölçüye bakar. Yalnız kayda bakılsaydı cevap
  /// kaydın ne zaman yazıldığına bağlı olurdu: keşif bildirimi bir sonraki
  /// mikro göreve erteleniyor (build sırasında yeniden çizim hatasını
  /// önlemek için), yani durak keşfedildiği an ile rozetin kaydedildiği an
  /// arasında bir aralık var. Türetilmiş cevap o aralıkta da doğru.
  bool isUnlocked(AchievementDefinition definition) =>
      _unlocked.containsKey(definition.id) ||
      _valueOf(definition) >= definition.target;

  /// Başarımın açıldığı gün; bilinmiyorsa `null`.
  DayStamp? unlockedOn(AchievementDefinition definition) =>
      _unlocked[definition.id];

  /// Kartın **tek** sıralaması.
  ///
  /// Önce açılanlar, sonra en çok ilerlenenler. Rozet rafı ve rozet
  /// sayfası aynı listeyi kullanıyor: iki ekranda iki farklı diziliş, aynı
  /// koleksiyonu iki ayrı şey gibi gösteriyordu.
  List<AchievementDefinition> get ordered {
    final sorted = <AchievementDefinition>[...definitions];
    sorted.sort((AchievementDefinition a, AchievementDefinition b) {
      final unlockedA = isUnlocked(a);
      final unlockedB = isUnlocked(b);
      if (unlockedA != unlockedB) return unlockedA ? -1 : 1;
      final byProgress = progressRatio(b).compareTo(progressRatio(a));
      if (byProgress != 0) return byProgress;
      // Eşit ilerlemede katalog sırası: liste kare kare zıplamasın.
      return definitions.indexOf(a).compareTo(definitions.indexOf(b));
    });
    return List<AchievementDefinition>.unmodifiable(sorted);
  }

  int get unlockedCount => definitions.where(isUnlocked).length;

  int get totalCount => definitions.length;

  /// Başarımın o andaki ilerlemesi; hedefi aşmaz.
  int progressOf(AchievementDefinition definition) {
    final value = _valueOf(definition);
    return value > definition.target ? definition.target : value;
  }

  double progressRatio(AchievementDefinition definition) {
    if (definition.target <= 0) return 0;
    return (progressOf(definition) / definition.target).clamp(0.0, 1.0);
  }

  /// Az önce açılanları bir kez verir; liste boşalır.
  List<AchievementDefinition> consumeUnlocked() {
    if (_justUnlocked.isEmpty) return const <AchievementDefinition>[];
    final taken = List<AchievementDefinition>.unmodifiable(_justUnlocked);
    _justUnlocked.clear();
    return taken;
  }

  int _valueOf(AchievementDefinition definition) => switch (definition.metric) {
    AchievementMetric.gameRunsFinished => _stats.runsOf(
      definition.gameId ?? '',
    ),
    final metric => _metric(metric),
  };

  int _metric(AchievementMetric metric) => switch (metric) {
    AchievementMetric.stationsDiscovered => discovery.discoveredCount,
    AchievementMetric.interchangesDiscovered =>
      discovery.interchangeDiscoveredCount,
    AchievementMetric.linesCompleted => _completedLineCount(),
    AchievementMetric.journeysCompleted => _stats.journeysCompleted,
    AchievementMetric.distinctGamesPlayed => _stats.playedGameIds.length,
    AchievementMetric.bestStreak => daily?.bestStreak ?? 0,
    AchievementMetric.dailyDaysCompleted => daily?.totalDaysCompleted ?? 0,
    AchievementMetric.bestQuizScore =>
      store?.bestScoreForGame(_quizGameId) ?? 0,
    // Oyuna bağlı; [_valueOf] çözüyor.
    AchievementMetric.gameRunsFinished => 0,
  };

  /// Metro Bilgi'nin kalıcı kimliği.
  static const String _quizGameId = 'metro_quiz';

  int _completedLineCount() =>
      discovery.completedLineCount(discovery.catalog.lineIds);

  // --- Yazma ---

  /// Yeni koşu başladı: bekleyen kutlamalar temizlenir.
  @override
  void reportRunStarted() => _justUnlocked.clear();

  @override
  void reportRun(RunReport report) {
    // Açılıp iki saniyede bitirilen oyun sayılmaz; bkz.
    // [RunReport.isMeaningful].
    if (!report.isMeaningful) return;
    _stats = _stats.copyWith(
      journeysCompleted: _stats.journeysCompleted + (report.arrived ? 1 : 0),
      playedGameIds: <String>{..._stats.playedGameIds, report.gameId},
      gameRuns: <String, int>{
        ..._stats.gameRuns,
        report.gameId: _stats.runsOf(report.gameId) + 1,
      },
    );
    unawaited(_persistStats());
    _evaluate();
    notifyListeners();
  }

  void _onSourceChanged() {
    if (_disposed) return;
    _evaluate();
  }

  /// Bütün başarımları yeniden değerlendirir; yeni açılanları toplar.
  ///
  /// Saf bir tarama: ilerleme her zaman kaynaktan okunur, hiçbir yerde
  /// biriktirilmez. Aynı çağrının iki kez yapılması hiçbir şeyi
  /// değiştirmez — [_unlocked] bir küme.
  void _evaluate({bool announce = true}) {
    final fresh = <AchievementDefinition>[];
    for (final definition in definitions) {
      if (_unlocked.containsKey(definition.id)) continue;
      if (_valueOf(definition) < definition.target) continue;
      // Geriye dönük göçte tarih yazılmaz: rozet dün mü üç ay önce mi hak
      // edildi bilinmiyor, uydurmak yerine boş bırakılıyor.
      _unlocked[definition.id] = announce ? DayStamp.today() : null;
      fresh.add(definition);
    }
    if (fresh.isEmpty) return;

    if (announce) {
      _justUnlocked.addAll(fresh);
      for (final definition in fresh) {
        analytics.log(
          AnalyticsEvent.achievementUnlocked,
          params: <String, String>{'achievement': definition.id},
        );
      }
    }
    unawaited(_persistUnlocked());
    if (announce) notifyListeners();
  }

  /// Kayıt biçimi: `kimlik` ya da `kimlik@yyyy-MM-dd`.
  ///
  /// Tarihsiz biçim eski kayıtlarla uyumluluk için okunmaya devam ediyor;
  /// o rozetler açık ama tarihsiz görünür.
  static Map<String, DayStamp?> _decodeUnlocked(Set<String>? raw) {
    final map = <String, DayStamp?>{};
    for (final entry in raw ?? const <String>{}) {
      final at = entry.indexOf('@');
      if (at <= 0) {
        map[entry] = null;
        continue;
      }
      map[entry.substring(0, at)] = DayStamp.tryParse(entry.substring(at + 1));
    }
    return map;
  }

  Set<String> _encodeUnlocked() => <String>{
    for (final entry in _unlocked.entries)
      entry.value == null ? entry.key : '${entry.key}@${entry.value}',
  };

  Future<void> _persistUnlocked() async {
    try {
      await store?.saveUnlockedAchievements(_encodeUnlocked());
    } catch (error, stack) {
      debugPrint('Başarım kaydı yazılamadı: $error\n$stack');
    }
  }

  Future<void> _persistStats() async {
    try {
      await store?.savePlayerStats(_stats.encode());
    } catch (error, stack) {
      debugPrint('Oyuncu kaydı yazılamadı: $error\n$stack');
    }
  }

  /// Bekleyen yazımları tamamlar — uygulama arka plana düşerken.
  Future<void> flush() async {
    await _persistStats();
    await _persistUnlocked();
  }

  @override
  void dispose() {
    _disposed = true;
    discovery.removeListener(_onSourceChanged);
    daily?.removeListener(_onSourceChanged);
    super.dispose();
  }
}
