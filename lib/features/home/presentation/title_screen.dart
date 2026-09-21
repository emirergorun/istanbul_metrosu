import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/metro_train.dart';
import '../../../core/widgets/pressable.dart';
import '../../games/blocks/application/game_snapshot.dart';
import '../../games/catalog/mini_game.dart';
import '../../daily/presentation/widgets/daily_entry_strip.dart';
import '../../discovery/presentation/widgets/discovery_entry_strip.dart';
import '../../journey/models/journey.dart';
import '../../journey/models/station.dart';
import '../../journey/presentation/widgets/onboarding_sheet.dart';
import '../../player/presentation/name_picker_sheet.dart';

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

  /// Karşılama akışı: tanıtım, ardından ad seçimi.
  ///
  /// Ad seçimi tanıtımdan **sonra** geliyor. Uygulamayı ilk açan kişiye
  /// ne olduğunu anlatmadan "adını seç" demek, kararı bağlamsız
  /// bırakıyordu.
  bool _pickingName = false;

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
      // Kayıt tanıtım kapanmadan önce yazılır: kullanıcı tanıtım açıkken
      // uygulamayı kapatırsa bir dahaki açılışta yeniden karşılamamalı.
      await store.markOnboardingSeen();
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
      if (!mounted) return;
      await _ensurePlayerName(store);
    });
  }

  /// Adı henüz onaylanmamışsa seçim sayfasını açar.
  ///
  /// Tanıtımı daha önce görmüş ama adını seçmemiş oyuncular da buradan
  /// geçer: sürüm yükseltmesiyle gelen kullanıcılar için tek yol bu.
  Future<void> _ensurePlayerName(LocalStore store) async {
    if (store.isPlayerNameLocked || _pickingName) return;
    _pickingName = true;
    final picked = await NamePickerSheet.show(context, store.playerName);
    if (picked != null) await store.confirmPlayerName(picked);
    _pickingName = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _traffic.dispose();
    super.dispose();
  }

  /// Yarım kalan oyun varsa döner.
  SavedGame? get _savedGame {
    final scope = AppScope.of(context);
    final raw = scope.store.savedGame;
    if (raw == null || raw.isEmpty) return null;
    return GameSnapshot.decode(raw, scope.routeService);
  }

  Future<void> _resumeSaved(SavedGame saved) async {
    await AppRoutes.resumeGame(context, saved);
    if (mounted) setState(() {});
  }

  /// Yarım kalan oyunu siler.
  ///
  /// Onay isteniyor: kayıt geri getirilemez ve buton, oyuna devam eden
  /// birincil kartın hemen altında duruyor — yanlış dokunuşun bedeli
  /// yolculuğun ortasında biriktirilmiş skorun kaybı.
  Future<void> _discardSaved() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Yarım kalan oyun silinsin mi?'),
        content: const Text(
          'Bu yolculuktaki skorun ve kalan süren silinecek. '
          'Bu geri alınamaz.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: AppFeedback.onTap(
              context,
              () => Navigator.of(context).pop(false),
            ),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: AppFeedback.onTap(
              context,
              () => Navigator.of(context).pop(true),
            ),
            child: const Text('Sil', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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

  /// Son rotayla oyun seçimine gider.
  ///
  /// Doğrudan Blok Metro açılıyordu; kart artık rotanın rekorunu hangi
  /// oyunda kurulduğuyla gösterdiği için oyuncu oyunu kendisi seçer.
  Future<void> _replay(Journey journey) async {
    final store = AppScope.of(context).store;
    await store.rememberRoute(journey.origin.id, journey.destination.id);
    if (!mounted) return;
    await AppRoutes.openGameSelect(context, journey);
    if (mounted) setState(() {});
  }

  Future<void> _openFriends() async {
    await AppRoutes.openFriends(context);
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
          //
          // Renk [AppColors.background]'tan **türetilir**, elle yazılmaz:
          // önceki palet değişiminde buradaki sabit güncellenmeden kalmış,
          // ekranın üstü yeni zemini, altı eski lacivertini gösteriyordu.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // Alt uçta bilerek tam opak değil (%95): arkadaki uzak
                  // raylar hafifçe okunsun, ekran düz bir zemine dönmesin.
                  // Metin kontrastı yine 15:1'in üstünde kalıyor.
                  colors: <Color>[
                    AppColors.background.withValues(alpha: 0.12),
                    AppColors.background.withValues(alpha: 0.56),
                    AppColors.background.withValues(alpha: 0.95),
                    AppColors.background.withValues(alpha: 0.95),
                  ],
                  stops: const <double>[0.0, 0.38, 0.60, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            // Esnek boşluklar önce sıfıra iner, sonra taşar. En dar
            // telefonda (320×568) uygulamanın izin verdiği en büyük yazı
            // ölçeğiyle birlikte içerik ekrandan uzun olabiliyor —
            // keşif şeridi eklendikten sonra sınır aşıldı.
            //
            // Kaydırma yalnızca o durumda devreye giriyor: `IntrinsicHeight`
            // sütuna doğal yüksekliğini verir, `ConstrainedBox` en az ekran
            // kadar uzun olmasını sağlar. İçerik sığdığında düzen bire bir
            // aynı kalır, esnek boşluklar payını alır.
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: <Widget>[
                          // Üst satırdaki iki ikincil giriş.
                          //
                          // Arkadaşlar ayarların **içine gömülmedi**:
                          // sosyal katman bir tercih değil, oynama yolu.
                          // Alt gezinme çubuğu da eklenmedi — ekranın
                          // dibi birincil eylemin yeri ve orayı üç sekmeyle
                          // paylaşmak o eylemi zayıflatırdı.
                          Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  IconButton(
                                    onPressed: AppFeedback.onTap(
                                      context,
                                      _openFriends,
                                    ),
                                    tooltip: 'Arkadaşlar',
                                    icon: const Icon(Icons.groups_rounded),
                                    color: AppColors.textSecondary,
                                  ),
                                  IconButton(
                                    onPressed: AppFeedback.onTap(
                                      context,
                                      _openSettings,
                                    ),
                                    tooltip: 'Ayarlar',
                                    icon: const Icon(Icons.settings_rounded),
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Dikey boşluk 3-2-1 bölünüyor: marka biraz aşağıda, kart
                          // ise ekranın **dibinde değil**, dipten bir tutam yukarıda
                          // duruyor.
                          //
                          // Eşit bölünmüşken marka ile kart arasında ekranın %15'i
                          // bomboş kalıyor, kart da en alta yapışıyordu; ikisi birden
                          // kartı ekrana sonradan iliştirilmiş gibi gösteriyordu.
                          // Alta bırakılan pay hem o boşluğu kapatıyor hem de kartı
                          // başparmağın rahat eriştiği banda taşıyor: uzun telefonda
                          // ekranın **en** dibi, ortasından daha zor erişilen yerdir.
                          const Spacer(flex: 3),
                          const _Wordmark(),
                          const Spacer(flex: 2),
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
                                // Alt alta dizilen her blok arasında
                                // **aynı** boşluk var: keşif şeridi,
                                // günün yolculuğu, birincil kart ve
                                // ikincil bağlantı tek bir ritimde
                                // duruyor. Üçü üç farklı değerdeyken
                                // (8 / 24 / 12) bloklar aynı aileye ait
                                // görünmüyordu. Birincil eylem boşlukla
                                // değil kendi ağırlığıyla öne çıkıyor:
                                // beyaz zemin, kalın punto.
                                const DiscoveryEntryStrip(),
                                const SizedBox(height: AppSpacing.stack),
                                const DailyEntryStrip(),
                                const SizedBox(height: AppSpacing.stack),
                                if (saved != null) ...<Widget>[
                                  _SavedGameCard(
                                    saved: saved,
                                    lineTheme: LineTheme.from(
                                      scope.metro
                                              .lineById(
                                                saved.session.journey.lineId,
                                              )
                                              ?.color ??
                                          AppColors.brandNavy,
                                    ),
                                    onResume: () => _resumeSaved(saved),
                                    onDiscard: _discardSaved,
                                  ),
                                  const SizedBox(height: AppSpacing.stack),
                                  TextButton(
                                    onPressed: AppFeedback.onTap(
                                      context,
                                      _openPlanner,
                                    ),
                                    child: const Text(
                                      'Yeni bir yolculuk başlat',
                                    ),
                                  ),
                                ] else if (last != null) ...<Widget>[
                                  _ResumeButton(
                                    journey: last,
                                    record: scope.store.bestRecordForRoute(
                                      last.origin.id,
                                      last.destination.id,
                                    ),
                                    lineTheme: LineTheme.from(
                                      scope.metro
                                              .lineById(last.lineId)
                                              ?.color ??
                                          AppColors.brandNavy,
                                    ),
                                    onTap: () => _replay(last),
                                  ),
                                  const SizedBox(height: AppSpacing.stack),
                                  TextButton(
                                    onPressed: AppFeedback.onTap(
                                      context,
                                      _openPlanner,
                                    ),
                                    child: const Text('Başka bir rota seç'),
                                  ),
                                ] else
                                  FilledButton(
                                    onPressed: AppFeedback.onTap(
                                      context,
                                      _openPlanner,
                                    ),
                                    child: const Text('OYUNA BAŞLA'),
                                  ),
                              ],
                            ),
                          ),
                          const Spacer(flex: 1),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Açılışın markası: perona asılı **istasyon tabelası**.
///
/// Önce burada uygulama ikonunun kendisi duruyordu (mavi köşeli kare +
/// tren). İkonun ana ekranda işi yok: kullanıcı zaten uygulamanın
/// içinde, ikon ona hangi uygulamayı açtığını ikinci kez anlatıyor ve
/// ekrana yapıştırılmış bir çıkartma gibi duruyor.
///
/// Tabela ise ekranın kendi dünyasına ait: arkasından trenler geçiyor,
/// üstündeki renk şeridi bu istasyondan geçen hatları söylüyor — gerçek
/// peron tabelalarındaki gibi. Yazı ortalanmış değil sola yaslı, çünkü
/// tabela okunacak bir levha, poster değil.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final lines = AppScope.of(context).metro.lines();
    // Veri yüklenememişse tabela renksiz kalmasın.
    final colors = lines.isEmpty
        ? <Color>[AppColors.action]
        : <Color>[for (final line in lines) LineTheme.from(line.color).accent];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Tavandan inen iki askı — tabelanın havada asılı durduğunu
          // anlatan tek detay. Olmayınca levha ekrana çakılı bir kutu.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _SignStem(),
              const SizedBox(width: 120),
              _SignStem(),
            ],
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.brandNavyDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Bu istasyondan geçen hatlar. Şerit hat sayısı kadar
                // eşit parçaya bölünüyor; yeni hat eklenince kendiliğinden
                // güncellenir.
                SizedBox(
                  height: 6,
                  // `stretch` şart: `Row`'un varsayılan hizası `center` ve
                  // çocuksuz bir `ColoredBox`'ın kendi yüksekliği sıfırdır —
                  // şerit çizilir ama 0 piksel yüksekliğinde, yani görünmez.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final color in colors)
                        Expanded(child: ColoredBox(color: color)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Text(
                    'İSTANBUL\nMETROSU OYUNU',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 28,
                      height: 1.12,
                    ),
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

/// Tabelayı tavana bağlayan ince askı.
class _SignStem extends StatelessWidget {
  const _SignStem();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 20,
      color: AppColors.outline.withValues(alpha: 0.7),
    );
  }
}

/// Yarım kalan oyun kartı.
///
/// Uygulama kapansa bile oyun kaybolmaz; metroda telefon sürekli cebe girip
/// çıktığı için bu akış varsayılan davranış olmalı.
class _SavedGameCard extends StatelessWidget {
  const _SavedGameCard({
    required this.saved,
    required this.lineTheme,
    required this.onResume,
    required this.onDiscard,
  });

  final SavedGame saved;
  final LineTheme lineTheme;

  /// Kayıttaki kalan süre.
  ///
  /// Motorun [JourneyGameController.remainingSeconds] kuralıyla aynı:
  /// `floor` kullanılır ki yolculuk tahmin edilen saniye dolmadan bitmiş
  /// görünmesin.
  int get _remainingSeconds {
    final left =
        saved.session.journey.estimatedSeconds - saved.progress.elapsedSeconds;
    return left < 0 ? 0 : left;
  }

  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final journey = saved.session.journey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Pressable(
          onTap: onResume,
          onLightSurface: true,
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          child: Material(
            color: AppColors.action,
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
                          style: AppText.micro.copyWith(
                            letterSpacing: 0.9,
                            color: AppColors.onAction.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${journey.origin.name} → ${journey.destination.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.lead.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.onAction,
                          ),
                        ),
                        Text(
                          'Skor ${Formatters.score(saved.progress.score)} · '
                          '${Formatters.remaining(_remainingSeconds)} kaldı',
                          style: AppText.caption.copyWith(
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
        // Yıkıcı eylem geri çekiliyor: normal akış ("yeni yolculuk") ile
        // kaydı silmek aynı gri metinde, aynı genişlikte duruyordu. Artık
        // bu buton yalnızca yazısı kadar geniş, daha küçük ve daha soluk;
        // ekranı tarayan göz önce devam etmeyi görüyor.
        Center(
          child: TextButton(
            onPressed: AppFeedback.onTap(context, onDiscard),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              textStyle: AppText.caption.copyWith(fontWeight: FontWeight.w600),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
            ),
            child: const Text('Bu oyunu bırak'),
          ),
        ),
      ],
    );
  }
}

/// "Blok Metro rekorun 143" — rekor, kurulduğu oyunun adıyla gösterilir.
String _recordText(RouteRecord? record) {
  if (record == null) return 'ilk yolculuk';
  final game = MiniGames.byId(record.gameId ?? LocalStore.legacyRouteGameId);
  final score = Formatters.score(record.score);
  return game == null ? 'rekorun $score' : '${game.name} rekorun $score';
}

class _ResumeButton extends StatelessWidget {
  const _ResumeButton({
    required this.journey,
    required this.record,
    required this.lineTheme,
    required this.onTap,
  });

  final Journey journey;

  /// Rotanın rekoru ve kurulduğu oyun; `null` ise rotada ilk yolculuk.
  final RouteRecord? record;
  final LineTheme lineTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      onLightSurface: true,
      borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
      child: Material(
        color: AppColors.action,
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
                      style: AppText.lead.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.onAction,
                      ),
                    ),
                    Text(
                      '${Formatters.approxMinutes(journey.estimatedMinutes)} · '
                      '${_recordText(record)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
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

  /// Her ray için: dikey konum oranı, hız çarpanı, yön, faz, solukluk ve
  /// **üstündeki tren sayısı**.
  ///
  /// Üç kural:
  ///
  /// 1. **Aralıklar eşit değil.** Eşit aralıklı yatay çizgiler ağ değil,
  ///    desen gibi okunuyor. Sıklık yukarıda fazla, aşağıda seyrek.
  /// 2. **Bir rayda birden fazla tren olabilir.** Tek trenle ray zamanın
  ///    çoğunda boş kalıyor, ağ ölü görünüyordu. İkinci tren yarım faz
  ///    ötelenmiş girer.
  /// 3. **Üstte ve altta yasak bölgeler var.** 0.07'nin üstünde saat ve
  ///    Dynamic Island, 0.09-0.14 arasında sağ üstteki ayar çarkı, 0.72'nin
  ///    altında kart ve metin butonları duruyor. Ray bunların içinden
  ///    geçerse ikisi de okunmuyor.
  static const List<
    ({
      double y,
      double speed,
      int direction,
      double phase,
      double fade,
      int trains,
    })
  >
  _tracks =
      <
        ({
          double y,
          double speed,
          int direction,
          double phase,
          double fade,
          int trains,
        })
      >[
        (
          y: 0.078,
          speed: 0.85,
          direction: 1,
          phase: 0.00,
          fade: 1.00,
          trains: 2,
        ),
        (
          y: 0.150,
          speed: 1.30,
          direction: -1,
          phase: 0.35,
          fade: 1.00,
          trains: 1,
        ),
        (
          y: 0.200,
          speed: 0.60,
          direction: 1,
          phase: 0.70,
          fade: 0.95,
          trains: 2,
        ),
        (
          y: 0.252,
          speed: 1.05,
          direction: -1,
          phase: 0.15,
          fade: 0.86,
          trains: 1,
        ),
        (
          y: 0.300,
          speed: 0.72,
          direction: 1,
          phase: 0.50,
          fade: 0.74,
          trains: 2,
        ),
        (
          y: 0.345,
          speed: 1.15,
          direction: -1,
          phase: 0.90,
          fade: 0.58,
          trains: 1,
        ),
        // Marka ile kartın arasını dolduran uzak raylar: daha soluk, daha
        // yavaş, daha küçük tren — mesafe hissi.
        (
          y: 0.575,
          speed: 0.42,
          direction: 1,
          phase: 0.25,
          fade: 0.46,
          trains: 2,
        ),
        (
          y: 0.628,
          speed: 0.32,
          direction: -1,
          phase: 0.60,
          fade: 0.34,
          trains: 1,
        ),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    // Hat yoksa çizilecek ray da yok. Korumasız bırakılırsa `% lines.length`
    // sıfıra bölme hatası verir ve açılış ekranı komple çöker.
    if (lines.isEmpty) return;

    for (var i = 0; i < _tracks.length; i++) {
      final track = _tracks[i];
      // Sırayla alınırsa ilk iki ray M1A ve M1B oluyor; ikisi de aynı
      // kırmızı, yan yana tek bir kalın çizgi gibi okunuyordu. Üçer atlayarak
      // dolaşmak (10 hat ile aynı hatta dönmeden hepsini gezer) renkleri
      // ayırıyor.
      final line = lines[(i * 3) % lines.length];
      final theme = LineTheme.from(line.color);
      final y = size.height * track.y;

      // Ray
      canvas.drawLine(
        Offset(-4, y),
        Offset(size.width + 4, y),
        Paint()
          ..color = theme.accent.withValues(alpha: 0.30 * track.fade)
          ..strokeWidth = 2,
      );

      // Durak işaretleri
      final dotPaint = Paint()
        ..color = theme.accent.withValues(alpha: 0.22 * track.fade);
      const dots = 7;
      for (var d = 0; d <= dots; d++) {
        canvas.drawCircle(Offset(size.width * d / dots, y), 2.5, dotPaint);
      }

      // Trenler
      // Uzaklık yalnız solmayla değil **boyutla** da anlatılır. Ölçek
      // 0.72-1.00 arasında oynarken aradaki fark gözle seçilmiyordu; alttaki
      // trenler uzak değil, yalnızca soluk görünüyordu.
      final trainHeight = size.height * 0.030 * (0.45 + 0.55 * track.fade);
      final width = MetroTrain.widthFor(height: trainHeight);
      final travel = size.width + width * 2;
      final trainPaint = MetroTrainPainter(
        color: theme.accent.withValues(alpha: 0.85 * track.fade),
        opacity: track.fade,
      );

      for (var n = 0; n < track.trains; n++) {
        final t =
            (progress * track.speed + track.phase + n / track.trains) % 1.0;
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
        trainPaint.paint(canvas, Size(width, trainHeight));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_TrafficPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.lines != lines;
}
