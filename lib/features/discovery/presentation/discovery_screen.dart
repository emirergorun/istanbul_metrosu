import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/telemetry/analytics.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../journey/models/station.dart';
import '../../passport/presentation/achievements_screen.dart';
import '../../passport/presentation/widgets/achievement_badge.dart';
import '../../passport/domain/achievement.dart';
import '../../passport/presentation/widgets/line_pin.dart';
import '../application/discovery_controller.dart';
import '../domain/discovery_catalog.dart';
import 'widgets/discovery_progress_track.dart';
import 'widgets/station_dot_strip.dart';

/// Yolculuk Kartım — oyuncunun İstanbul'daki kalıcı ilerlemesi.
///
/// Ürün fikri bir seyahat belgesi değil, oyuncuya ait **oyun kartı**:
/// oynadıkça dolan, koleksiyon biriktiren kişisel bir kart. Pasaport ve
/// damga benzetmesi bilinçli olarak bırakıldı; rozetler artık damga değil,
/// karta takılan pinler.
///
/// Dört soruya cevap verir, bu sırayla:
/// İstanbul'un ne kadarını keşfettim · hangi rozetleri kazandım ·
/// hangi hatları tamamladım · hangi hattın neresindeyim.
///
/// Kart **kendi ilerleme kaydını tutmaz**. Keşfedilen durakların tek
/// kaynağı kalıcı keşif kaydıdır; bu ekran onu görünür ve ödüllendirici
/// kılar, kopyalamaz.
class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  /// Açık duran hat kartı. Aynı anda bir tane: liste taranabilir kalmalı.
  String? _expandedLineId;
  bool _started = false;

  /// Ağ bu ziyaretten önce kaç duraktı?
  ///
  /// Ekran açılırken bir kez okunur ve kayıt hemen güncellenir; okunan değer
  /// bu ziyaret boyunca sabit kalır ki "yeni durak eklendi" şeridi ekran
  /// yeniden çizildiğinde kaybolmasın.
  int _seenTotal = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final scope = AppScope.of(context);
    scope.analytics.log(AnalyticsEvent.discoveryScreenViewed);

    _seenTotal = scope.store.discoverySeenTotal;
    final total = scope.discovery?.totalCount ?? 0;
    if (total > 0) scope.store.markDiscoveryTotalSeen(total);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final discovery = scope.discovery;
    final lines = scope.metro.lines();

    if (discovery == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    // Ağ büyüdüyse ve oyuncu daha önce bir toplam görmüşse söylenir.
    final addedStations = _seenTotal > 0 && discovery.totalCount > _seenTotal
        ? discovery.totalCount - _seenTotal
        : 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('YOLCULUK KARTIM', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: discovery,
          builder: (BuildContext context, _) {
            // `CustomScrollView` + `SliverList.builder`: hat kartları ancak
            // görünür olduklarında kurulur. Açık bir kart yirmi dört satır
            // ekleyebiliyor, hepsini her karede kurmanın anlamı yok.
            return CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _JourneyCard(discovery: discovery, lines: lines),
                        if (addedStations > 0) ...<Widget>[
                          const SizedBox(height: AppSpacing.stack),
                          _NetworkGrewNotice(count: addedStations),
                        ],
                        // Bölüm başlığıyla başlayan blok; bkz.
                        // [AppSpacing.sectionGap].
                        const SizedBox(height: AppSpacing.sectionGap),
                        // Sıra kartın hikâyesi: keşif → hatlar → rozetler →
                        // günlük sadakat → hat hat ayrıntı.
                        _LineCollection(discovery: discovery, lines: lines),
                        const _AchievementStrip(),
                        const _DailyRecord(),
                        const _SectionLabel('HATLAR'),
                        const SizedBox(height: AppSpacing.stack),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  sliver: SliverList.builder(
                    itemCount: lines.length,
                    itemBuilder: (BuildContext context, int index) {
                      final line = lines[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.stack,
                        ),
                        child: _LineCard(
                          line: line,
                          discovery: discovery,
                          expanded: _expandedLineId == line.id,
                          onToggle: () => setState(() {
                            _expandedLineId = _expandedLineId == line.id
                                ? null
                                : line.id;
                          }),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.sectionTitle);
}

/// Kartın günlük bölümü: seri ve sadakat.
///
/// Günlük sistem kendi durumunu **sahiplenmeye devam ediyor**; kart
/// yalnızca okuyor. İki ölçü yan yana duruyor çünkü farklı şeyler
/// anlatıyorlar: seri sürekliliği, toplam gün sadakati. Serisi kırılan
/// oyuncunun da gösterecek bir sayısı olsun.
class _DailyRecord extends StatelessWidget {
  const _DailyRecord();

  @override
  Widget build(BuildContext context) {
    final daily = AppScope.of(context).daily;
    if (daily == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: daily,
      builder: (BuildContext context, _) {
        // Hiç günlük tamamlanmadıysa bölüm hiç çizilmez: sıfırlarla dolu
        // bir tablo, olmayan bir tablodan kötüdür.
        if (daily.totalDaysCompleted == 0) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionLabel('GÜNLÜK'),
            const SizedBox(height: AppSpacing.stack),
            Semantics(
              container: true,
              label:
                  'Günlük yolculuk. Seri ${daily.streak} gün, '
                  'en uzun ${daily.bestStreak} gün, '
                  'toplam ${daily.totalDaysCompleted} gün tamamlandı.',
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  ),
                  child: Row(
                    children: <Widget>[
                      _DailyStat(label: 'SERİ', value: '${daily.streak}'),
                      _DailyStat(
                        label: 'EN UZUN',
                        value: '${daily.bestStreak}',
                      ),
                      _DailyStat(
                        label: 'TOPLAM',
                        value: '${daily.totalDaysCompleted}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
          ],
        );
      },
    );
  }
}

class _DailyStat extends StatelessWidget {
  const _DailyStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: AppText.stat.copyWith(fontFeatures: kTabularFigures),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.micro.copyWith(
              fontFamily: AppFonts.display,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartın rozet rafı.
///
/// Bütün rozetler burada listelenmiyor: raf bir **vitrin**, liste değil.
/// Altı pin yan yana duruyor, tamamı ayrı bir sayfada. Kartın ana konusu
/// hâlâ keşif; rozetler onu taçlandıran koleksiyon.
class _AchievementStrip extends StatelessWidget {
  const _AchievementStrip();

  /// Rafta kaç pin görünür.
  ///
  /// Altı: standart telefonda tek satıra sığan en büyük sayı. Sekizken raf
  /// ikinci satıra tek bir pin sarkıtıyor ve vitrin dağınık duruyordu.
  static const int _shown = 6;

  @override
  Widget build(BuildContext context) {
    final achievements = AppScope.of(context).achievements;
    if (achievements == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: achievements,
      builder: (BuildContext context, _) {
        // Sıra rozet sayfasıyla **aynı**: önce kazanılanlar, sonra en çok
        // ilerlenenler. İki ekranda iki farklı diziliş, aynı koleksiyonu
        // iki ayrı şey gibi gösteriyordu.
        final ordered = achievements.ordered;
        if (ordered.isEmpty) return const SizedBox.shrink();
        final shelf = ordered.take(_shown).toList();
        AchievementDefinition? next;
        for (final definition in ordered) {
          if (!achievements.isUnlocked(definition)) {
            next = definition;
            break;
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: _SectionLabel('ROZETLER')),
                Text(
                  '${achievements.unlockedCount} / '
                  '${achievements.totalCount}',
                  style: AppText.statSmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stack),
            Pressable(
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.achievements),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              semanticLabel:
                  '${achievements.totalCount} rozetin '
                  '${achievements.unlockedCount} tanesi kazanıldı. '
                  'Rozetleri gör',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        // Pinler sarmalanıyor: büyük yazı ölçeğinde ve dar
                        // ekranda tek satır altı pini taşıyamıyor.
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: <Widget>[
                            for (final definition in shelf)
                              AchievementBadge(
                                definition: definition,
                                unlocked: achievements.isUnlocked(definition),
                                size: 34,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (next != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              _NextBadge(
                definition: next,
                remaining: achievementRemainingText(
                  next,
                  achievements.progressOf(next),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
          ],
        );
      },
    );
  }
}

/// Rafın altındaki tek satır: sıradaki rozet ve ne kadar kaldığı.
///
/// Raf "ne topladım" diyor; bu satır "şimdi neye çalışıyorum". Sıralama
/// zaten en çok ilerlenen kilitli rozeti öne alıyor, yani hedef rastgele
/// değil, oyuncunun en yakın olduğu rozet.
class _NextBadge extends StatelessWidget {
  const _NextBadge({required this.definition, required this.remaining});

  final AchievementDefinition definition;
  final String remaining;

  @override
  Widget build(BuildContext context) {
    final color = AchievementBadge.colorOf(definition.category);
    return Semantics(
      label: 'Sıradaki rozet ${definition.title}. $remaining',
      child: ExcludeSemantics(
        // Dar ekranda ve büyük yazıda satır taşmasın: ad kısalır, kalan
        // miktar kendi yerini korur ama o da gerekirse kısalır.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: 'SIRADAKİ  ',
                      style: AppText.micro.copyWith(
                        fontFamily: AppFonts.display,
                        color: AppColors.textMuted,
                      ),
                    ),
                    TextSpan(text: definition.title),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                remaining,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: AppText.micro.copyWith(
                  fontFamily: AppFonts.display,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hat koleksiyonu — on hattın pin seti.
///
/// Kartın en somut koleksiyonu bu: her hat bir pin, tamamlanınca kendi
/// rengine kavuşuyor. Tamamlanmamış hatlar da duruyor, soluk hâlde —
/// toplanacak şey görünmezse hedef de olmaz.
///
/// Altındaki hat listesi kaldırılmadı: pin seti "ne topladım", liste
/// "neresindeyim" sorusunu yanıtlıyor. İkisi farklı sorular.
class _LineCollection extends StatelessWidget {
  const _LineCollection({required this.discovery, required this.lines});

  final DiscoveryController discovery;
  final List<MetroLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();

    final completed = discovery.completedLineCount(
      lines.map((MetroLine l) => l.id),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: _SectionLabel('HAT KOLEKSİYONU')),
            Text('$completed / ${lines.length}', style: AppText.statSmall),
          ],
        ),
        const SizedBox(height: AppSpacing.stack),
        Semantics(
          container: true,
          label:
              '${lines.length} hattın $completed tanesi tamamlandı. '
              '${_spokenLines()}',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              width: double.infinity,
              // Beşli iki sıra: on hat bir set gibi dizilsin, yedi + üç
              // artık bir satır bırakmasın. Pin boyu genişlikten türüyor.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  const perRow = 5;
                  const gap = AppSpacing.md;
                  final size =
                      ((constraints.maxWidth - gap * (perRow - 1)) / perRow)
                          .clamp(32.0, 60.0);
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    alignment: WrapAlignment.spaceBetween,
                    children: <Widget>[
                      for (final line in lines)
                        LinePin(
                          lineId: line.id.toUpperCase(),
                          color: LineTheme.from(line.color).color,
                          completed: discovery.isLineComplete(line.id),
                          size: size,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),
      ],
    );
  }

  /// Ekran okuyucuya hangi hatların tamamlandığını söyler.
  String _spokenLines() {
    final done = lines
        .where((MetroLine line) => discovery.isLineComplete(line.id))
        .map((MetroLine line) => line.id.toUpperCase())
        .toList();
    if (done.isEmpty) return 'Henüz tamamlanan hat yok.';
    return 'Tamamlananlar: ${done.join(', ')}.';
  }
}

/// Kartın kendisi — ekranın üst yarısı.
///
/// Banka kartı ya da bilet değil: oyuncuya ait bir **oyun kartı**. Üst
/// kenarda on hattın renk şeridi duruyor; tamamlanan hat kendi rengiyle,
/// kalanlar soluk. Kart oynadıkça renkleniyor — "YOLCULUĞUN KADAR OYNA"
/// sözünün ilerleme tarafı.
///
/// Kimlik yalnızca cihazda zaten olan addan geliyor (sözlükten üretilmiş ya
/// da bağlanmış Game Center takma adı). Ağ beklenmiyor, sahte hesap bilgisi
/// uydurulmuyor; sosyal katman yoksa kimlik satırı hiç çizilmiyor.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.discovery, required this.lines});

  final DiscoveryController discovery;
  final List<MetroLine> lines;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final social = scope.social;
    final achievements = scope.achievements;
    final completedLines = discovery.completedLineCount(
      lines.map((MetroLine l) => l.id),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LineBand(discovery: discovery, lines: lines),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (social != null) ...<Widget>[
                    AnimatedBuilder(
                      animation: social,
                      builder: (BuildContext context, _) {
                        final me = social.me;
                        return _CardOwner(name: me.displayName, rank: me.title);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _GlobalProgress(discovery: discovery, lines: lines),
                  if (achievements != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.lg),
                    AnimatedBuilder(
                      animation: achievements,
                      builder: (BuildContext context, _) => _CareerRow(
                        journeys: achievements.stats.journeysCompleted,
                        lines: completedLines,
                        lineTotal: lines.length,
                        badges: achievements.unlockedCount,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartın üst kenarı: her hat bir dilim, sırası veri dosyasındaki sıra.
class _LineBand extends StatelessWidget {
  const _LineBand({required this.discovery, required this.lines});

  final DiscoveryController discovery;
  final List<MetroLine> lines;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      // `stretch` zorunlu: çocuksuz `ColoredBox` gevşek kısıtta sıfır
      // yükseklik alıyor ve şerit hiç görünmüyordu.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final line in lines)
            Expanded(
              child: ColoredBox(
                color: discovery.isLineComplete(line.id)
                    ? LineTheme.from(line.color).color
                    // Pin setiyle aynı soluk ton: tamamlanmamış hat da
                    // rengini belli ediyor, ama sönük.
                    : Color.lerp(
                        LineTheme.from(line.color).color,
                        AppColors.blocker,
                        0.55,
                      )!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartın sahibi: ad ve keşiften türeyen unvan.
class _CardOwner extends StatelessWidget {
  const _CardOwner({required this.name, required this.rank});

  final String name;
  final String rank;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Kart sahibi $name, $rank',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              flex: 3,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.tileTitle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              flex: 2,
              child: Text(
                rank.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.micro.copyWith(
                  fontFamily: AppFonts.display,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yolculuk kariyeri: üç sayı, üç ayrı koleksiyon.
class _CareerRow extends StatelessWidget {
  const _CareerRow({
    required this.journeys,
    required this.lines,
    required this.lineTotal,
    required this.badges,
  });

  final int journeys;
  final int lines;
  final int lineTotal;
  final int badges;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '$journeys yolculuk tamamlandı, $lineTotal hattın $lines tanesi '
          'bitti, $badges rozet kazanıldı.',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            _DailyStat(label: 'YOLCULUK', value: '$journeys'),
            _DailyStat(label: 'HAT', value: '$lines/$lineTotal'),
            _DailyStat(label: 'ROZET', value: '$badges'),
          ],
        ),
      ),
    );
  }
}

/// Ekranın ilk ekranında görünen tek cevap: kaç durak, yüzde kaç.
class _GlobalProgress extends StatelessWidget {
  const _GlobalProgress({required this.discovery, required this.lines});

  final DiscoveryController discovery;
  final List<MetroLine> lines;

  @override
  Widget build(BuildContext context) {
    final discovered = discovery.discoveredCount;
    final total = discovery.totalCount;
    final completedLines = discovery.completedLineCount(
      lines.map((MetroLine l) => l.id),
    );

    return Semantics(
      container: true,
      label: _spokenSummary(discovered, total, completedLines),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionLabel('İSTANBUL KEŞFİ'),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text('$discovered', style: AppText.display),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '/ $total istasyon',
                    style: AppText.bodyStrong.copyWith(
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Oluk kartın zemininden koyu: kart rengiyle aynı kalınca
            // çubuğun boş kısmı kartın içinde kayboluyordu.
            DiscoveryProgressTrack(
              value: discovery.progress,
              background: AppColors.background,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _caption(discovered, completedLines),
              style: discovery.isComplete
                  ? AppText.captionStrong.copyWith(color: AppColors.success)
                  : AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  String _caption(int discovered, int completedLines) {
    if (discovered == 0) {
      return 'İlk yolculuğunu yap ve İstanbul’u keşfetmeye başla.';
    }
    if (discovery.isComplete) return 'İSTANBUL KEŞFEDİLDİ';

    // İlk birkaç durakta yüzde aşağı yuvarlanınca "%0 tamamlandı" çıkıyordu:
    // oyuncu bir durak kazanmışken hiçbir şey kazanmamış gibi okunuyor.
    final head = discovery.percent == 0
        ? 'Keşif başladı'
        : '%${discovery.percent} tamamlandı';
    return completedLines > 0 ? '$head · $completedLines hat bitti' : head;
  }

  String _spokenSummary(int discovered, int total, int completedLines) {
    if (discovered == 0) {
      return 'İstanbul keşfi. Henüz durak keşfedilmedi. '
          'İlk yolculuğunu yap ve İstanbul’u keşfetmeye başla.';
    }
    final lineText = completedLines > 0
        ? ' $completedLines hat tamamlandı.'
        : '';
    return 'İstanbul keşfi. $total durağın $discovered tanesi keşfedildi, '
        'yüzde ${discovery.percent}.$lineText';
  }
}

/// Ağa yeni durak eklendiğini söyleyen şerit.
///
/// Tamamlanma keşfedilen duraklardan türetildiği için, veri dosyasına bir
/// hat eklendiğinde bitmiş bir keşif kendiliğinden eksiğe döner. Doğru
/// davranış, ama açıklaması olmadan hata gibi okunur.
class _NetworkGrewNotice extends StatelessWidget {
  const _NetworkGrewNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.add_road_rounded,
            size: 18,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Ağa $count yeni durak eklendi. Keşif hedefi büyüdü.',
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tek hattın kartı. Dokunulunca durak listesi açılır.
class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.discovery,
    required this.expanded,
    required this.onToggle,
  });

  final MetroLine line;
  final DiscoveryController discovery;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = LineTheme.from(line.color);
    final stations = discovery.catalog.stationsOfLine(line.id);
    final states = <bool>[
      for (final station in stations) discovery.isDiscovered(station.id),
    ];
    final found = discovery.lineDiscoveredCount(line.id);
    final total = stations.length;
    final complete = discovery.isLineComplete(line.id);

    // Etiket ve durum başlıkta yazılı; ekran okuyucu için tek cümleye
    // indirilir. Durak listesi **dışarıda bırakılmaz**: kartı açmanın tek
    // amacı o listeyi okumak, susturulursa kart açılmamış sayılır.
    final headerLabel =
        '${line.id}, ${line.name}. $total duraktan $found tanesi keşfedildi'
        '${complete ? ', hat tamamlandı' : ''}. '
        '${expanded ? 'Durak listesini kapat' : 'Durakları göster'}';

    return Pressable(
      onTap: onToggle,
      semanticLabel: headerLabel,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: expanded ? AppColors.outline : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: _LineCardHeader(
                line: line,
                found: found,
                total: total,
                complete: complete,
                expanded: expanded,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            StationDotStrip(states: states, color: theme.accent),
            if (expanded) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _StationList(
                stations: stations,
                discovery: discovery,
                accent: theme.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineCardHeader extends StatelessWidget {
  const _LineCardHeader({
    required this.line,
    required this.found,
    required this.total,
    required this.complete,
    required this.expanded,
  });

  final MetroLine line;
  final int found;
  final int total;
  final bool complete;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        LineBadge(label: line.id, color: line.color, compact: true),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            line.name,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (complete)
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(
              Icons.check_rounded,
              size: 15,
              color: AppColors.success,
            ),
          ),
        // Sayaç bir tavana sığdırılıyor.
        //
        // En büyük yazı ölçeğinde (1.6×) ve en dar telefonda "12 / 25" gibi
        // iki basamaklı bir sayaç, rozet ve okla birlikte satırı 12 piksel
        // taşırıyordu. Durak adı esnek olduğu için küçülüyor ama sabit
        // ögelerin toplamı genişliği aşınca `Expanded` sıfıra inse bile
        // taşma kalıyor. `scaleDown` yalnız gerektiğinde ve yalnız sayacı
        // küçültüyor; rakamlar kırpılmıyor, üç nokta çıkmıyor.
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '$found / $total',
              style: AppText.statSmall.copyWith(
                color: complete ? AppColors.success : AppColors.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Icon(
          expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
      ],
    );
  }
}

/// Hattın durakları — keşfedilmiş ve keşfedilmemiş, hepsi görünür.
class _StationList extends StatelessWidget {
  const _StationList({
    required this.stations,
    required this.discovery,
    required this.accent,
  });

  final List<CanonicalStation> stations;
  final DiscoveryController discovery;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final station in stations)
          _StationRow(
            station: station,
            discovered: discovery.isDiscovered(station.id),
            accent: accent,
          ),
      ],
    );

    // "Hareketi azalt" açıkken liste yerinde belirir. Kural uygulamanın
    // tamamında aynı: hareket kalkar, bilgi kalır.
    if (MediaQuery.disableAnimationsOf(context)) return list;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, Widget? child) =>
          Opacity(opacity: t, child: child),
      child: list,
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.discovered,
    required this.accent,
  });

  final CanonicalStation station;
  final bool discovered;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final transfers = station.isInterchange ? station.lineIds.join(' · ') : '';

    return Semantics(
      container: true,
      label:
          '${station.name}, ${discovered ? 'keşfedildi' : 'keşfedilmedi'}'
          '${transfers.isEmpty ? '' : '. Aktarma: $transfers'}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Durum renge değil şekle dayanır: dolu onay ve boş halka.
              SizedBox(
                width: 16,
                child: discovered
                    ? Icon(Icons.check_rounded, size: 14, color: accent)
                    : const Icon(
                        Icons.circle_outlined,
                        size: 12,
                        color: AppColors.blocker,
                      ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  station.name,
                  style: discovered
                      ? AppText.captionStrong.copyWith(
                          color: AppColors.textPrimary,
                        )
                      : AppText.caption,
                ),
              ),
              // Aktarma etiketi **esnek değil, sınırlı**: `Flexible`
              // olsaydı boş alanı durak adıyla paylaşır ve sağ kenardan
              // kopardı. Sabit üst sınır hem sağa yaslı kalmasını hem de
              // büyük yazı ölçeğinde satırı taşırmamasını sağlıyor; sığmayan
              // kısım kısalır, tam hâli ekran okuyucu etiketinde duruyor.
              if (transfers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: Text(
                      transfers,
                      style: AppText.micro.copyWith(color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
