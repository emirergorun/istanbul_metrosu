import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../journey/models/journey.dart';
import 'game_cover.dart';
import 'mini_game.dart';

/// Tek bir oyunun tanıtım ekranı — **yedi oyun için ortak**.
///
/// Oyuna özel detay ekranı yok ve olmamalı: başlık, kapak, tanım, amaç ve
/// kontrol adımları kataloğun kendisinden ([MiniGame]) okunuyor. Yeni bir
/// oyun eklemek için buraya dokunmak gerekmez.
///
/// Ekran **sunum**dur: açılması yolculuk sayacını başlatmaz, puan yazmaz,
/// durak keşfetmez. İstanbul Keşfi yalnızca OYNA ile, mevcut oyun başlatma
/// hattı üzerinden başlar.
class GameDetailScreen extends StatelessWidget {
  const GameDetailScreen({
    super.key,
    required this.journey,
    required this.game,
  });

  final Journey journey;
  final MiniGame game;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final line = scope.metro.lineById(journey.lineId);
    final lineTheme = LineTheme.from(line?.color ?? AppColors.brandNavy);
    final record = scope.store.bestScoreForGameRoute(
      gameId: game.id,
      originId: journey.origin.id,
      destinationId: journey.destination.id,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: BackButton(
          onPressed: AppFeedback.onTap(
            context,
            () => Navigator.of(context).pop(),
          ),
        ),
      ),
      // Alt eylem sabit: OYNA ekranın en belirgin ögesi ve başparmağın
      // eriştiği bantta. İçerik uzun olsa da kaydırma gerektirmiyor.
      bottomNavigationBar: _PlayBar(journey: journey, game: game),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: <Widget>[
            // Oyunun adı kapağın **içinde**; ayrıca üstte tekrarlanmıyor.
            _Hero(game: game),
            const SizedBox(height: AppSpacing.stack),
            // Tanıtım cümlesi ekranın vaadi: gövdeden bir basamak yukarıda
            // ve tam kontrastta. AMAÇ metni gövde puntosunda kalıyor, ikisi
            // arasında hiyerarşi oluşuyor.
            Text(
              game.description,
              style: AppText.bodyStrong.copyWith(height: 1.35),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            const _SectionLabel('AMAÇ'),
            const SizedBox(height: AppSpacing.stack),
            Text(game.objective, style: AppText.body),
            if (game.hasHowToPlay) ...<Widget>[
              const SizedBox(height: AppSpacing.stack),
              _HowToPlayButton(game: game),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
            const _SectionLabel('YOLCULUĞUN'),
            const SizedBox(height: AppSpacing.stack),
            _JourneyCard(journey: journey, lineTheme: lineTheme),
            if (record > 0) ...<Widget>[
              const SizedBox(height: AppSpacing.stack),
              Text(
                'Bu rotada rekorun  ${Formatters.score(record)}',
                style: AppText.caption.copyWith(
                  color: game.color,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Galeri kartıyla **aynı** sahne, büyük hâli.
///
/// Kapak iki ekranda farklı olsaydı oyuncu dokunduğu kartla açılan ekranı
/// bağdaştıramazdı; süreklilik kimliğin yarısı.
class _Hero extends StatelessWidget {
  const _Hero({required this.game});

  final MiniGame game;

  /// Poster yüksekliğinin üst sınırı.
  ///
  /// Kapak oranı 0,55 — poster oranı. Tam genişlikte çizilirse detay
  /// ekranını tek başına dolduruyor ve oyuncu tanımı görmek için kaydırmak
  /// zorunda kalıyordu; ekranın üç saniyede anlaşılması şartı bozuluyor.
  /// Ortalanmış poster hem kompozisyonu kırpmıyor hem metne yer bırakıyor.
  static const double _maxHeight = 330;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GameCoverCard.radius + 2),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.outline),
              borderRadius: BorderRadius.circular(GameCoverCard.radius + 2),
            ),
            child: AspectRatio(
              // Galerideki kartla **aynı** oran: kapak görselleri bu orana
              // göre kesildi, başka bir orana sokmak kompozisyonu kırpar.
              aspectRatio: GameCoverCard.aspectRatio,
              child: GameCover(game: game),
            ),
          ),
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

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.journey, required this.lineTheme});

  final Journey journey;
  final LineTheme lineTheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '${journey.lineId} hattı, ${journey.origin.name} durağından '
          '${journey.destination.name} durağına, yaklaşık '
          '${journey.estimatedMinutes} dakika, ${journey.stopCount} durak',
      child: ExcludeSemantics(
        // Hat rengi şerit olarak çiziliyor; tek kenarı kalın bir kenarlık
        // yuvarlatılmış köşeyle birlikte çizilemez.
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.outline),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(width: 3, color: lineTheme.accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: <Widget>[
                        LineBadge(
                          label: journey.lineId,
                          color: lineTheme.color,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                journey.origin.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodyStrong,
                              ),
                              Row(
                                children: <Widget>[
                                  const Icon(
                                    Icons.south_rounded,
                                    size: 13,
                                    color: AppColors.textMuted,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      '${Formatters.approxMinutes(journey.estimatedMinutes)}'
                                      ' · ${journey.stopCount} durak',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.micro.copyWith(
                                        color: AppColors.textMuted,
                                        fontFeatures: kTabularFigures,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                journey.destination.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodyStrong,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kontrolü gerçekten açıklama gerektiren oyunlarda çıkan yardım.
class _HowToPlayButton extends StatelessWidget {
  const _HowToPlayButton({required this.game});

  final MiniGame game;

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('NASIL OYNANIR?', style: AppText.sectionTitle),
              const SizedBox(height: AppSpacing.stack),
              for (var i = 0; i < game.howToPlay.length; i++) ...<Widget>[
                _Step(index: i + 1, text: game.howToPlay[i], color: game.color),
                if (i != game.howToPlay.length - 1)
                  const SizedBox(height: AppSpacing.stack),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: AppFeedback.onTap(context, () => _open(context)),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('Nasıl oynanır?'),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text, required this.color});

  final int index;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('$index', style: AppText.micro.copyWith(color: color)),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(text, style: AppText.body)),
      ],
    );
  }
}

/// Ekranın birincil eylemi.
///
/// Oyunu **mevcut** başlatma hattıyla açar ([AppRoutes.openGame]); V2 ikinci
/// bir başlatma mimarisi kurmuyor. İstanbul Keşfi'nin oyuna bağlanması buna
/// dayanıyor.
class _PlayBar extends StatelessWidget {
  const _PlayBar({required this.journey, required this.game});

  final Journey journey;
  final MiniGame game;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Semantics(
            button: true,
            label: '${game.name} oyununu başlat',
            child: ExcludeSemantics(
              child: FilledButton(
                onPressed: AppFeedback.onTap(
                  context,
                  () => AppRoutes.openGame(context, journey, gameId: game.id),
                ),
                child: const Text('OYNA'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
