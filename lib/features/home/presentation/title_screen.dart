import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/metro_train.dart';
import '../../game/application/game_snapshot.dart';
import '../../game/domain/game_state.dart';
import '../../journey/models/journey.dart';
import '../../journey/models/station.dart';
import '../../journey/presentation/widgets/onboarding_sheet.dart';

/// Açılış ekranı.
///
/// Arka planda gerçek hat renklerinde trenler kendi raylarında akar; ağ
/// canlıymış gibi durur. Ön planda tek bir birincil eylem vardır.
///
/// Hız hiyerarşisi bilinçli: daha önce oynanmış bir rota varsa **birincil
/// buton onu tekrar oynatır**. Her sabah aynı hatta binen biri uygulamayı
/// açıp tek dokunuşla oyuna girer; rota seçmek ikincil yoldur.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _traffic = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  bool _checkedOnboarding = false;

  @override
  void initState() {
    super.initState();
    // "Hareketi azalt" açıksa trenler sabit durur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) _traffic.repeat();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedOnboarding) return;
    _checkedOnboarding = true;

    final store = AppScope.of(context).store;
    if (store.hasSeenOnboarding) return;

    // İlk kare çizildikten sonra aç: build sırasında route açılamaz.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const OnboardingSheet(),
      );
      await store.markOnboardingSeen();
    });
  }

  @override
  void dispose() {
    _traffic.dispose();
    super.dispose();
  }

  /// Yarım kalan oyun varsa oturumu döner.
  GameSession? get _savedGame {
    final scope = AppScope.of(context);
    final raw = scope.store.savedGame;
    if (raw == null || raw.isEmpty) return null;
    return GameSnapshot.decode(raw, scope.routeService);
  }

  Future<void> _resumeSaved(GameSession session) async {
    await AppRoutes.openGame(context, session.journey, resumeFrom: session);
    if (mounted) setState(() {});
  }

  Future<void> _discardSaved() async {
    await AppScope.of(context).store.clearSavedGame();
    if (mounted) setState(() {});
  }

  Journey? get _lastRoute {
    final scope = AppScope.of(context);
    final last = scope.store.lastRoute;
    if (last == null) return null;
    return scope.routeService
        .estimate(last.originId, last.destinationId)
        .journey;
  }

  Future<void> _openPlanner() async {
    await AppRoutes.openPlanner(context);
    if (mounted) setState(() {});
  }

  Future<void> _replay(Journey journey) async {
    final store = AppScope.of(context).store;
    await store.rememberRoute(journey.origin.id, journey.destination.id);
    if (!mounted) return;
    await AppRoutes.openGame(context, journey);
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await AppRoutes.openSettings(context);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final saved = _savedGame;
    final last = _lastRoute;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _TrafficBackdrop(
              animation: _traffic,
              lines: scope.metro.lines(),
            ),
          ),
          // Alt yarıyı karartarak metnin okunmasını garanti et.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0x260B1622),
                    Color(0x990B1622),
                    AppColors.background,
                  ],
                  stops: <double>[0.0, 0.40, 0.62],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: IconButton(
                      onPressed: _openSettings,
                      tooltip: 'Ayarlar',
                      icon: const Icon(Icons.settings_rounded),
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                const _Wordmark(),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.xl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (saved != null) ...<Widget>[
                        _SavedGameCard(
                          session: saved,
                          lineTheme: LineTheme.from(
                            scope.metro.lineById(saved.journey.lineId)?.color ??
                                AppColors.brandNavy,
                          ),
                          onResume: () => _resumeSaved(saved),
                          onDiscard: _discardSaved,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                          onPressed: _openPlanner,
                          child: const Text('Yeni bir yolculuk başlat'),
                        ),
                      ] else if (last != null) ...<Widget>[
                        _ResumeButton(
                          journey: last,
                          record: scope.store.bestScoreForRoute(
                            last.origin.id,
                            last.destination.id,
                          ),
                          lineTheme: LineTheme.from(
                            scope.metro.lineById(last.lineId)?.color ??
                                AppColors.brandNavy,
                          ),
                          onTap: () => _replay(last),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextButton(
                          onPressed: _openPlanner,
                          child: const Text('Başka bir rota seç'),
                        ),
                      ] else
                        FilledButton(
                          onPressed: _openPlanner,
                          child: const Text('OYUNA BAŞLA'),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      const _OfflineNote(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const AppLogo(size: 84),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'İSTANBUL\nMETROSU OYUNU',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontSize: 30, height: 1.1),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppConstants.tagline,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Uygulama markası: metro treni, hat renginde pencerelerle.
///
/// Aynı [MetroTrain] çizimini kullanır — ikon, alt çubuktaki tren ve varış
/// sahnesindeki tren aynı şekildir.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: size * 0.02,
        ),
      ),
      child: MetroTrain(color: AppColors.success, height: size * 0.30),
    );
  }
}

/// Yarım kalan oyun kartı.
///
/// Uygulama kapansa bile oyun kaybolmaz; metroda telefon sürekli cebe girip
/// çıktığı için bu akış varsayılan davranış olmalı.
class _SavedGameCard extends StatelessWidget {
  const _SavedGameCard({
    required this.session,
    required this.lineTheme,
    required this.onResume,
    required this.onDiscard,
  });

  final GameSession session;
  final LineTheme lineTheme;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final journey = session.journey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: AppColors.action,
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          child: InkWell(
            onTap: onResume,
            borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: <Widget>[
                  LineBadge(label: journey.lineId, color: lineTheme.color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'YARIM KALAN OYUN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: AppColors.onAction.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${journey.origin.name} → ${journey.destination.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onAction,
                          ),
                        ),
                        Text(
                          'Skor ${Formatters.score(session.score)} · '
                          '${Formatters.remaining(session.remainingSeconds)} kaldı',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.onAction.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 28,
                    color: AppColors.onAction,
                  ),
                ],
              ),
            ),
          ),
        ),
        TextButton(onPressed: onDiscard, child: const Text('Bu oyunu bırak')),
      ],
    );
  }
}

class _ResumeButton extends StatelessWidget {
  const _ResumeButton({
    required this.journey,
    required this.record,
    required this.lineTheme,
    required this.onTap,
  });

  final Journey journey;
  final int record;
  final LineTheme lineTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.action,
      borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              LineBadge(label: journey.lineId, color: lineTheme.color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${journey.origin.name} → ${journey.destination.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAction,
                      ),
                    ),
                    Text(
                      record > 0
                          ? '~${journey.estimatedMinutes} dk · rekorun ${Formatters.score(record)}'
                          : '~${journey.estimatedMinutes} dk · ilk yolculuk',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.onAction.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.play_arrow_rounded,
                size: 28,
                color: AppColors.onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.textMuted),
        SizedBox(width: AppSpacing.sm),
        Text(
          AppConstants.offlineNote,
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Arka plandaki hareketli ağ: her hat kendi rayında, kendi renginde.
class _TrafficBackdrop extends StatelessWidget {
  const _TrafficBackdrop({required this.animation, required this.lines});

  final Animation<double> animation;
  final List<MetroLine> lines;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => CustomPaint(
          painter: _TrafficPainter(progress: animation.value, lines: lines),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter({required this.progress, required this.lines});

  final double progress;
  final List<MetroLine> lines;

  /// Her ray için: dikey konum oranı, hız çarpanı, yön, faz.
  ///
  /// Raylar ekranın üst bölgesinde tutulur; alt yarı marka ve butona ayrılmış
  /// olduğu için oraya tren girmez — hareket metni okumayı zorlaştırmasın.
  static const List<({double y, double speed, int direction, double phase})>
  _tracks = <({double y, double speed, int direction, double phase})>[
    (y: 0.16, speed: 0.85, direction: 1, phase: 0.0),
    (y: 0.23, speed: 1.30, direction: -1, phase: 0.35),
    (y: 0.30, speed: 0.60, direction: 1, phase: 0.7),
    (y: 0.37, speed: 1.05, direction: -1, phase: 0.15),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      final line = lines[i % lines.length];
      final theme = LineTheme.from(line.color);
      final y = size.height * track.y;

      // Ray
      canvas.drawLine(
        Offset(-4, y),
        Offset(size.width + 4, y),
        Paint()
          ..color = theme.accent.withValues(alpha: 0.30)
          ..strokeWidth = 2,
      );

      // Durak işaretleri
      final dotPaint = Paint()..color = theme.accent.withValues(alpha: 0.22);
      const dots = 7;
      for (var d = 0; d <= dots; d++) {
        canvas.drawCircle(Offset(size.width * d / dots, y), 2.5, dotPaint);
      }

      // Tren
      final trainHeight = size.height * 0.030;
      final width = MetroTrain.widthFor(height: trainHeight);
      final travel = size.width + width * 2;
      final t = (progress * track.speed + track.phase) % 1.0;
      final x = track.direction > 0
          ? -width + travel * t
          : size.width + width - travel * t;

      canvas.save();
      canvas.translate(x, y - trainHeight / 2);
      if (track.direction < 0) {
        // Ters yöndeki treni aynala ki burnu gittiği yöne baksın.
        canvas.translate(width, 0);
        canvas.scale(-1, 1);
      }
      MetroTrainPainter(
        color: theme.accent.withValues(alpha: 0.85),
      ).paint(canvas, Size(width, trainHeight));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_TrafficPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.lines != lines;
}
