import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/audio/audio_service.dart';
import '../core/telemetry/analytics.dart';
import '../core/storage/local_store.dart';
import '../data/metro/metro_repository.dart';
import '../data/questions/question_repository.dart';
import '../features/daily/application/daily_controller.dart';
import '../features/discovery/application/discovery_controller.dart';
import '../features/discovery/application/journey_discovery.dart';
import '../features/games/tunnel_escape/application/escape_progress_controller.dart';
import '../features/passport/application/achievement_controller.dart';
import '../features/session/composite_run_reporter.dart';
import '../features/social/application/challenge_session.dart';
import '../features/social/application/social_controller.dart';
import '../features/session/run_report.dart';
import '../features/journey/models/journey.dart';
import '../features/journey/services/route_service.dart';

/// Uygulama seviyesindeki servisleri widget ağacına taşır.
///
/// Ekstra state-management paketi eklememek için sade bir
/// [InheritedWidget] kullanılır.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.store,
    required this.audio,
    required this.metro,
    this.questions = const EmptyQuestionRepository(),
    required this.routeService,
    this.discovery,
    this.daily,
    this.achievements,
    this.escapeProgress,
    this.social,
    this.challengeSession,
    this.analytics = const NoopAnalytics(),
    required super.child,
  });

  final LocalStore store;
  final AudioService audio;
  final MetroRepository metro;

  /// Elle yazılmış bilgi soruları. Dosya okunamazsa boş havuz gelir ve
  /// Metro Bilgi yalnızca üretilen sorularla oynanır.
  final QuestionRepository questions;

  final RouteService routeService;

  /// İstanbul keşfi. `null` ise keşif kapalıdır ve oyun aynen çalışır —
  /// testler bu yoldan geçer.
  final DiscoveryController? discovery;

  /// Günün yolculuğu, görevleri ve seri. `null` ise günlük kapalıdır:
  /// ana ekranda kart çıkmaz, oyun aynen oynanır.
  final DailyController? daily;

  /// Yolculuk Kartı'nın rozetleri. `null` ise rozet bölümü çizilmez.
  final AchievementController? achievements;

  /// Tünele Kaç'ın bölüm ilerlemesi — rozetlerle paylaşılan tek kaynak.
  /// `null` ise oyun ekranı kendi yerel kopyasını kurar (tek ekran testleri).
  final EscapeProgressController? escapeProgress;

  /// Kimlik, arkadaşlar ve meydan okuma geçmişi. `null` ise sosyal katman
  /// kapalıdır; oyunun kendisi aynen çalışır.
  final SocialController? social;

  /// Oynanmakta olan meydan okuma. `null` ise her koşu Serbest Oyun'dur.
  final ChallengeSession? challengeSession;

  /// Bu koşunun rastgelelik kaynağı.
  ///
  /// Meydan okuma modunda tohumlu bir [Random], normalde `null`. Oyun
  /// ekranları bunu controller'a verip unutuyor; hangi modda olduklarını
  /// bilmeleri gerekmiyor.
  Random? challengeRandomFor(Journey journey, String gameId) =>
      challengeSession?.randomFor(gameId, journey);

  /// Biten koşunun bildirileceği yer.
  ///
  /// Oyun ekranı controller'ı kurduktan sonra bunu ona verir. Hangi
  /// sistemlerin dinlediği burada birleşir; oyun ekranı tek bir alan görür.
  /// İkisi de kapalıysa `null` döner ve koşu sessizce bildirilmez.
  RunReporter? get runReporter {
    final targets = <RunReporter>[?daily, ?achievements];
    if (targets.isEmpty) return null;
    if (targets.length == 1) return targets.first;
    return CompositeRunReporter(targets);
  }

  /// Bu yolculuk için bir keşif defteri açar.
  ///
  /// Oyun ekranları keşif kuralını bilmez; controller'a bunu verip
  /// unuturlar.
  JourneyDiscovery? discoveryFor(Journey journey, String gameId) {
    final controller = discovery;
    if (controller == null) return null;
    return JourneyDiscovery(
      journey: journey,
      discovery: controller,
      gameId: gameId,
    );
  }

  /// Kullanım ölçümü. Varsayılan hiçbir şey yapmaz — testler ve ölçümün
  /// kapalı olduğu durum aynı yoldan geçer.
  final Analytics analytics;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope widget ağacında bulunamadı');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      store != oldWidget.store ||
      audio != oldWidget.audio ||
      metro != oldWidget.metro ||
      questions != oldWidget.questions ||
      discovery != oldWidget.discovery ||
      social != oldWidget.social ||
      challengeSession != oldWidget.challengeSession ||
      daily != oldWidget.daily ||
      achievements != oldWidget.achievements ||
      escapeProgress != oldWidget.escapeProgress ||
      analytics != oldWidget.analytics ||
      routeService != oldWidget.routeService;
}
