import 'dart:async';

import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/audio/audio_service.dart';
import '../core/storage/local_store.dart';
import '../core/telemetry/analytics.dart';
import '../core/telemetry/error_reporter.dart';
import '../data/metro/metro_repository.dart';
import '../data/questions/question_repository.dart';
import '../features/daily/application/daily_controller.dart';
import '../features/daily/domain/daily_generator.dart';
import '../features/discovery/application/discovery_controller.dart';
import '../features/discovery/domain/discovery_catalog.dart';
import '../features/journey/services/route_service.dart';
import '../features/passport/application/achievement_controller.dart';
import '../features/social/application/challenge_session.dart';
import '../features/social/application/game_center_service.dart';
import '../features/social/application/social_controller.dart';
import 'app_scope.dart';
import 'routes.dart';
import 'theme.dart';

/// Uygulama kökü.
class MetroGameApp extends StatefulWidget {
  const MetroGameApp({
    super.key,
    required this.store,
    required this.audio,
    required this.metro,
    this.questions = const EmptyQuestionRepository(),
    this.analytics = const NoopAnalytics(),
    this.errors,
  });

  final LocalStore store;
  final AudioService audio;
  final MetroRepository metro;
  final QuestionRepository questions;

  /// Kullanım ölçümü — cihazda kalır, ağa çıkmaz.
  final Analytics analytics;

  /// Yakalanan hataların kaydı; ayarlardan görüntülenir.
  final ErrorReporter? errors;

  @override
  State<MetroGameApp> createState() => _MetroGameAppState();
}

class _MetroGameAppState extends State<MetroGameApp>
    with WidgetsBindingObserver {
  /// Keşif kataloğu ve durumu uygulama ömrü boyunca **bir kez** kurulur.
  ///
  /// Katalog metro verisini tarar; her `build`'de yeniden kurulsaydı durak
  /// listesi saniyede altmış kez baştan türetilirdi.
  late final DiscoveryCatalog _catalog = DiscoveryCatalog.fromRepository(
    widget.metro,
  );
  late final RouteService _routes = RouteService(widget.metro);

  /// Günlük sistem keşiften **önce** kuruluyor.
  ///
  /// Keşif, yeni durak yazdığında günlüğe haber veriyor; bağlantı bu yönde
  /// olduğu için günlüğün önce var olması gerekiyor. Ters kurulsaydı
  /// keşif kendi sayacını günlüğe kopyalamak zorunda kalır ve iki kayıt
  /// zamanla ayrı düşerdi.
  late final DailyController _daily = DailyController(
    generator: DailyGenerator(metro: widget.metro, routes: _routes),
    store: widget.store,
    analytics: widget.analytics,
    // Keşif görevi oyuncunun gerçekten yapabileceği kadarını istesin diye
    // kalan durak sayısı **geç bağlanıyor**: keşif kaydı bu satırdan
    // sonra kuruluyor, doğrudan referans döngü olurdu.
    undiscoveredStations: () => _discovery.undiscoveredCount,
  );

  late final DiscoveryController _discovery = DiscoveryController(
    catalog: _catalog,
    store: widget.store,
    analytics: widget.analytics,
    onDiscovered: (DiscoveryResult result) =>
        _daily.reportNewStations(result.stations.length),
  );

  /// Meydan okuma oturumu: kabul edildiğinde başlar, sonuçtan sonra biter.
  late final ChallengeSession _challengeSession = ChallengeSession();

  /// Kimlik, arkadaşlar ve meydan okuma geçmişi.
  ///
  /// Keşif kaydını **okur**: kimlik kartındaki istasyon sayısı oradan
  /// geliyor, kopyalanmıyor.
  late final SocialController _social = SocialController(
    store: widget.store,
    discovery: _discovery,
    analytics: widget.analytics,
    // Game Center yalnız Apple platformlarında; başka her yerde kimlik
    // yereldir ve hiçbir şey eksik değildir. Bağlanma oyuncunun kararı —
    // açılışta kendiliğinden oturum açma penceresi çıkmıyor.
    platform: const GameCenterService(),
  );

  /// Pasaport başarımları keşfi ve günlüğü **okur**, kopyalamaz.
  late final AchievementController _achievements = AchievementController(
    discovery: _discovery,
    daily: _daily,
    store: widget.store,
    analytics: widget.analytics,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Uygulama arka plana düşerken keşif kaydı diske **beklenerek** yazılır.
  ///
  /// Oyun sırasındaki yazım bilinçli olarak beklenmiyor: bir durak
  /// geçildiğinde kareyi diske bekletmek kabul edilemez. Bedeli, yazım
  /// tamamlanmadan öldürülen bir oturumda son durağın kaybolması. iOS
  /// arka plandaki uygulamayı haber vermeden sonlandırdığı için tek
  /// güvenli an burası.
  ///
  /// `inactive` de dinleniyor: iOS'ta uygulama çoğu zaman `paused`
  /// aşamasına gelmeden `inactive` üzerinden arka plana geçer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_discovery.flush());
      unawaited(_daily.flush());
      unawaited(_achievements.flush());
      unawaited(_social.flush());
    }
    // Ekrana dönen oyuncu dünün yolculuğunu görmemeli: uygulama gece
    // boyunca arka planda kalmış olabilir.
    if (state == AppLifecycleState.resumed) _daily.refreshDay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _achievements.dispose();
    _social.dispose();
    _challengeSession.dispose();
    _discovery.dispose();
    _daily.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: widget.store,
      audio: widget.audio,
      metro: widget.metro,
      questions: widget.questions,
      analytics: widget.analytics,
      discovery: _discovery,
      daily: _daily,
      achievements: _achievements,
      social: _social,
      challengeSession: _challengeSession,
      routeService: _routes,
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        // Erişilebilirlik: kullanıcının yazı tipi tercihine saygı gösterilir.
        //
        // Üst sınır tamamen kaldırılmadı çünkü oyun tahtası sabit oranlı;
        // aşırı ölçekte HUD tahtayı eziyor. 1.6 iOS'un "Büyük" kademelerini
        // kapsar ve düzen bu değere kadar test edildi.
        // TODO(PROD): Tahta/HUD düzenini ölçekten bağımsız hale getirip
        // sınırı tamamen kaldır.
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(maxScaleFactor: 1.6),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        initialRoute: AppRoutes.home,
        onGenerateRoute: AppRoutes.onGenerateRoute,
      ),
    );
  }
}

/// Metro verisi okunamadığında gösterilen tek ekran.
///
/// Oyunun tamamı `assets/data/metro.json` üzerine kurulu; veri yoksa
/// yapılabilecek bir şey yok. Sessizce çökmek yerine ne olduğunu söyler.
class MetroDataErrorApp extends StatelessWidget {
  const MetroDataErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.wrong_location_rounded,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Metro verisi yüklenemedi',
                  textAlign: TextAlign.center,
                  style: AppText.heading,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Hat ve istasyon bilgisi okunamadığı için oyun '
                  'başlatılamıyor. Uygulamayı kapatıp yeniden açmayı dene; '
                  'sorun sürerse uygulamayı yeniden yükle.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
