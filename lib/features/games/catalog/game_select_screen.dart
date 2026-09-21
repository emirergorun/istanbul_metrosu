import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../discovery/presentation/widgets/discovery_progress_track.dart';
import '../../journey/models/journey.dart';
import 'game_cover.dart';
import 'mini_game.dart';

/// Rota seçildikten sonra gelen **oyun galerisi**.
///
/// Akış bilinçli olarak önce rota, sonra oyun: rota yolculuğun ne kadar
/// süreceğini belirler, oyun o süreyi neyle geçireceğini.
///
/// Ekran eskiden alt alta metin kartlarından oluşan bir listeydi; her kart
/// ad, tanım, rekor ve bir oynat oku taşıyordu ve sonuç bir oyun
/// koleksiyonundan çok bir ayar menüsü gibi okunuyordu. Artık kararı
/// **görsel** veriyor: iki sütun kapak, altında yalnız oyunun adı. "Bu oyun
/// ne?" sorusunu kapak, "ne yapacağım?" sorusunu detay ekranı yanıtlıyor.
///
/// Kapağa dokunmak oyunu **başlatmaz**, detayını açar. Yolculuk sayacı ve
/// İstanbul Keşfi yalnızca detaydaki OYNA ile başlar.
class GameSelectScreen extends StatelessWidget {
  const GameSelectScreen({super.key, required this.journey});

  final Journey journey;

  /// İki sütuna geçmek için gereken en küçük genişlik.
  ///
  /// Altında tek sütuna düşülür: 320 piksellik bir ekranda iki kapak, kenar
  /// boşlukları düşüldükten sonra 130 pikselin altına iner ve başlık
  /// okunmaz olur.
  static const double _twoColumnMinWidth = 340;

  void _openDetail(BuildContext context, MiniGame game) {
    if (!game.isAvailable) return;
    AppRoutes.openGameDetail(context, journey, gameId: game.id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final line = scope.metro.lineById(journey.lineId);
    final lineTheme = LineTheme.from(line?.color ?? AppColors.brandNavy);
    final games = MiniGames.all;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('OYUNUNU SEÇ', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final columns = constraints.maxWidth >= _twoColumnMinWidth ? 2 : 1;

            return CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _JourneyStrip(
                          journey: journey,
                          lineTheme: lineTheme,
                          onChangeRoute: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _DiscoveryRow(),
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
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: GameCoverCard.aspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate((
                      BuildContext context,
                      int index,
                    ) {
                      final game = games[index];
                      return GameCoverCard(
                        game: game,
                        onTap: () => _openDetail(context, game),
                      );
                    }, childCount: games.length),
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

/// Yolculuğu hatırlatan **ince** şerit.
///
/// Oyuncu rotayı az önce seçti; ekranı bir kez daha rota kartına vermek
/// gerekmiyor. Hat, iki uç ve süre tek satırda; asıl alan oyunların.
class _JourneyStrip extends StatelessWidget {
  const _JourneyStrip({
    required this.journey,
    required this.lineTheme,
    required this.onChangeRoute,
  });

  final Journey journey;
  final LineTheme lineTheme;
  final VoidCallback onChangeRoute;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Yolculuğun: ${journey.lineId} hattı, ${journey.origin.name} '
          'durağından ${journey.destination.name} durağına, '
          'yaklaşık ${journey.estimatedMinutes} dakika',
      // Hat rengi kenarlık değil **şerit**: tek kenarı kalın bir kenarlık
      // yuvarlatılmış köşeyle birlikte çizilemiyor (Flutter üniform kenarlık
      // şart koşuyor). Şerit aynı işi yapıyor, köşeler duruyor.
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ExcludeSemantics(
                        child: Row(
                          children: <Widget>[
                            LineBadge(
                              label: journey.lineId,
                              color: lineTheme.color,
                              compact: true,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '${journey.origin.name} → '
                                '${journey.destination.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodyStrong,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              Formatters.approxMinutes(
                                journey.estimatedMinutes,
                              ),
                              style: AppText.micro.copyWith(
                                color: AppColors.textSecondary,
                                fontFeatures: kTabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                              vertical: AppSpacing.xs,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: AppFeedback.onTap(context, onChangeRoute),
                          child: Text(
                            'Rotayı değiştir',
                            style: AppText.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
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
    );
  }
}

/// İstanbul Keşfi girişi — oyun seçimini gölgelemeyen tek satır.
///
/// Galeri bir pano değil: rota, keşif ve oyunlar aynı ağırlıkta olsaydı
/// ekranın asıl işi (oyun seçmek) kaybolurdu. Keşif burada yalnızca
/// erişilebilir kalıyor.
class _DiscoveryRow extends StatelessWidget {
  const _DiscoveryRow();

  @override
  Widget build(BuildContext context) {
    final discovery = AppScope.of(context).discovery;
    if (discovery == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: discovery,
      builder: (BuildContext context, _) {
        final total = discovery.totalCount;
        if (total == 0) return const SizedBox.shrink();

        return Pressable(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.discovery),
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          semanticLabel:
              'İstanbul keşfi: $total durağın ${discovery.discoveredCount} '
              'tanesi keşfedildi. Keşfi gör',
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: ExcludeSemantics(
              // Etiket ve sayaç üstte, çubuk altta. Üçü tek satırdayken en
              // dar ekranda 1.6× yazı ölçeğinde taşıyordu: Bungee etiket
              // 194 px, sayaç ve ok 76 px, kullanılabilir 280 px.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'İSTANBUL KEŞFİ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.sectionTitle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${discovery.discoveredCount} / $total',
                        style: AppText.captionStrong.copyWith(
                          color: AppColors.textPrimary,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  DiscoveryProgressTrack(
                    value: discovery.progress,
                    background: AppColors.surface,
                    thickness: 5,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
