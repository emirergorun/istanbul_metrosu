import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/telemetry/analytics.dart';
import '../../session/run_report.dart';
import '../domain/daily_counters.dart';
import '../domain/daily_generator.dart';
import '../domain/daily_mission.dart';
import '../domain/daily_plan.dart';
import '../domain/day_stamp.dart';
import '../domain/streak_state.dart';

/// Günlük yolculuk, günlük görevler ve seri — tek durum.
///
/// İki kavram bilinçli olarak ayrı tutuluyor:
///
/// - **Plan** ([DailyPlan]) takvim gününden türer, saklanmaz.
/// - **İlerleme** ([DailyCounters]) oyuncunun o gün yaptığıdır, saklanır.
///
/// Kalıcı keşif bu sınıfın işi değildir ve buradan asla silinmez: günlük
/// başarısız olsa bile keşfedilen duraklar keşfedilmiş kalır.
class DailyController extends ChangeNotifier implements RunReporter {
  DailyController({
    required this.generator,
    this.store,
    this.analytics = const NoopAnalytics(),
    this.undiscoveredStations,
  }) {
    _restore();
  }

  final DailyGenerator generator;

  /// Kaç durak **henüz keşfedilmedi?**
  ///
  /// Keşif görevi oyuncunun gerçekten yapabileceği kadarını istesin diye
  /// plan üretimine veriliyor; bkz. [DailyGenerator.missionsFor]. `null`
  /// ise keşif kapalı demektir ve görev havuzu olduğu gibi kullanılır.
  final int Function()? undiscoveredStations;
  final LocalStore? store;
  final Analytics analytics;

  DayStamp _day = DayStamp.today();
  DailyPlan? _plan;
  DailyCounters _counters = DailyCounters(day: DayStamp.today());
  StreakState _streak = StreakState.empty;

  /// Bu oturumda **az önce** tamamlanan görevler.
  ///
  /// Arayüz bunu bir kez gösterir ve [consumeCompletedMissions] ile alır.
  /// Kalıcı değil: tamamlanmanın kendisi sayaçlardan türüyor, buradaki liste
  /// yalnızca "şimdi oldu" anını taşıyor.
  final List<DailyMission> _justCompleted = <DailyMission>[];

  /// Günlük yolculuk **bu oturumda** tamamlandı mı? Kutlama için.
  bool _justCompletedDaily = false;

  void _restore() {
    _streak = StreakState.decode(store?.dailyStreakRaw);
    final saved = DailyCounters.decode(store?.dailyCountersRaw);
    _day = DayStamp.today();
    // Kayıt başka bir güne aitse atılır: gün dönümü budur. Dünün sayaçları
    // bugüne taşınsaydı görevler kendiliğinden tamamlanmış görünürdü.
    _counters = (saved != null && saved.day == _day)
        ? saved
        : DailyCounters(day: _day);
    _plan = _buildPlan(_day);
  }

  DailyPlan? _buildPlan(DayStamp day) => generator.planFor(
    day,
    undiscoveredStations: undiscoveredStations?.call(),
  );

  // --- Türetilen görünüm ---

  /// Bugünün planı. Metro verisi rota vermiyorsa `null` ve günlük kapalıdır.
  DailyPlan? get plan => _plan;

  /// Bugünün takvim günü.
  DayStamp get day => _day;

  DailyCounters get counters => _counters;

  List<DailyMission> get missions => _plan?.missions ?? const <DailyMission>[];

  int progressOf(DailyMission mission) => mission.progressFrom(_counters);

  bool isMissionComplete(DailyMission mission) =>
      mission.isCompleteFor(_counters);

  int get completedMissionCount =>
      missions.where(isMissionComplete).length;

  /// Bugünün yolculuğu tamamlandı mı?
  bool get isDailyComplete => _counters.dailyDone;

  /// Bugün geçerli olan seri uzunluğu. Seri kırılmışsa 0.
  int get streak => _streak.currentOn(_day);

  /// Bugüne kadarki en uzun seri.
  int get bestStreak => _streak.best;

  /// Seri bugün tamamlandı mı? (Bugün oynandı demektir.)
  bool get streakCompletedToday => _streak.isCompletedOn(_day);

  /// Ömür boyu tamamlanan gün sayısı. Seri kırılsa da küçülmez.
  int get totalDaysCompleted => _streak.totalDays;

  /// Bir gün kaçırılmış ama seri af hakkıyla ayakta mı?
  bool get isStreakForgivenToday => _streak.isGraceActiveOn(_day);

  /// Bu seride af hakkı kullanıldı mı?
  bool get streakGraceUsed => _streak.graceUsed;

  /// Bu oturumda günlük yolculuğun tamamlandığı anı bir kez verir.
  bool consumeDailyCompletion() {
    if (!_justCompletedDaily) return false;
    _justCompletedDaily = false;
    return true;
  }

  /// Az önce tamamlanan görevleri bir kez verir; liste boşalır.
  List<DailyMission> consumeCompletedMissions() {
    if (_justCompleted.isEmpty) return const <DailyMission>[];
    final taken = List<DailyMission>.unmodifiable(_justCompleted);
    _justCompleted.clear();
    return taken;
  }

  // --- Yazma ---

  /// Gün değiştiyse plan ve sayaçlar tazelenir.
  ///
  /// Uygulama gece boyunca açık kalabilir; ekrana dönen oyuncu dünün
  /// yolculuğunu görmemeli.
  void refreshDay() {
    final today = DayStamp.today();
    if (today == _day) return;
    _day = today;
    _counters = DailyCounters(day: today);
    _plan = _buildPlan(today);
    _justCompleted.clear();
    _justCompletedDaily = false;
    unawaited(_persistCounters());
    _notifyCoalesced();
  }

  /// Yeni koşu başladı: bekleyen kutlamalar temizlenir.
  ///
  /// Oyuncu görevi tamamlayıp oyunu yarıda bırakırsa sonuç paneli hiç
  /// açılmıyor ve "görev tamamlandı" satırı kuyrukta kalıp bir sonraki
  /// koşunun panelinde çıkıyordu.
  @override
  void reportRunStarted() {
    refreshDay();
    _justCompleted.clear();
    _justCompletedDaily = false;
  }

  /// Biten bir koşuyu işler.
  ///
  /// Yarıda bırakılan oyun hiçbir sayacı büyütmez. Aynı koşu iki kez
  /// bildirilse bile günlük tamamlanması ve seri **bir kez** işlenir.
  @override
  void reportRun(RunReport report) {
    refreshDay();
    // Açılıp iki saniyede bitirilen oyun sayılmaz; bkz.
    // [RunReport.isMeaningful].
    if (!report.isMeaningful) return;

    final before = _snapshotCompletion();
    final plan = _plan;
    final isDaily =
        plan != null &&
        report.arrived &&
        report.gameId == plan.gameId &&
        plan.matchesRoute(report.journey);

    _counters = _counters.copyWith(
      finishedRuns: _counters.finishedRuns + 1,
      arrivals: _counters.arrivals + (report.arrived ? 1 : 0),
      playedGameIds: <String>{..._counters.playedGameIds, report.gameId},
      dailyDone: _counters.dailyDone || isDaily,
    );

    if (isDaily && !before.dailyDone) {
      _justCompletedDaily = true;
      analytics.log(
        AnalyticsEvent.dailyJourneyCompleted,
        params: <String, String>{'game_id': report.gameId},
      );
      _completeStreak();
    }

    _collectNewlyCompleted(before.missions);
    unawaited(_persistCounters());
    _notifyCoalesced();
  }

  /// Kalıcı keşif yeni durak yazdığında çağrılır.
  ///
  /// Sayı [DiscoveryController] tarafından verilir ve yalnızca **ilk kez**
  /// keşfedilen durakları içerir: aynı rotayı tekrar oynamak günlük keşif
  /// görevini ilerletmez.
  void reportNewStations(int count) {
    if (count <= 0) return;
    refreshDay();
    final before = _snapshotCompletion();
    _counters = _counters.copyWith(
      newStations: _counters.newStations + count,
    );
    _collectNewlyCompleted(before.missions);
    unawaited(_persistCounters());
    _notifyCoalesced();
  }

  // --- Bildirim ---

  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Kare başına **tek** bildirim gönderir.
  ///
  /// Keşif kaydıyla aynı gerekçe: biniş durağı oyun ekranı build sırasında
  /// `start()` çağırdığı anda keşfediliyor, keşif de günlük görevi
  /// ilerletiyor. O anda doğrudan `notifyListeners` çağırmak ana ekrandaki
  /// günlük şeridini build sırasında yeniden çizmeye zorlar; Flutter bunu
  /// hata sayar ("setState() called during build").
  ///
  /// Üstelik tek karede birden çok durak geçilebiliyor; birleştirme
  /// gereksiz yeniden çizimleri de kaldırıyor.
  void _notifyCoalesced() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  void _completeStreak() {
    final next = _streak.completeOn(_day);
    if (next == _streak) return;
    final grew = next.length > _streak.currentOn(_day);
    _streak = next;
    analytics.log(
      AnalyticsEvent.streakAdvanced,
      params: <String, String>{'grew': grew ? 'true' : 'false'},
    );
    unawaited(_persistStreak());
  }

  /// Görevlerin o andaki tamamlanma hâli.
  ({bool dailyDone, List<bool> missions}) _snapshotCompletion() => (
    dailyDone: _counters.dailyDone,
    missions: <bool>[for (final m in missions) isMissionComplete(m)],
  );

  /// Eksikten tama geçen görevleri toplar.
  void _collectNewlyCompleted(List<bool> before) {
    final current = missions;
    for (var i = 0; i < current.length && i < before.length; i++) {
      if (before[i] || !isMissionComplete(current[i])) continue;
      _justCompleted.add(current[i]);
      analytics.log(
        AnalyticsEvent.dailyMissionCompleted,
        params: <String, String>{'mission': current[i].type.id},
      );
    }
  }

  // --- Kalıcılık ---

  Future<void> _persistCounters() async {
    try {
      await store?.saveDailyCounters(_counters.encode());
    } catch (error, stack) {
      debugPrint('Günlük kaydı yazılamadı: $error\n$stack');
    }
  }

  Future<void> _persistStreak() async {
    try {
      await store?.saveDailyStreak(_streak.encode());
    } catch (error, stack) {
      debugPrint('Seri kaydı yazılamadı: $error\n$stack');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Bekleyen yazımları tamamlar — uygulama arka plana düşerken.
  Future<void> flush() async {
    await _persistCounters();
    await _persistStreak();
  }

  /// Testte temiz bir başlangıç için.
  @visibleForTesting
  void debugReset() {
    _streak = StreakState.empty;
    _day = DayStamp.today();
    _counters = DailyCounters(day: _day);
    _plan = _buildPlan(_day);
    _justCompleted.clear();
    _justCompletedDaily = false;
    notifyListeners();
  }
}
