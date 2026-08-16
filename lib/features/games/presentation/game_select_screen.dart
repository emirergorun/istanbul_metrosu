import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../journey/models/journey.dart';
import '../models/mini_game.dart';

/// Rota seçildikten sonra gelen oyun seçim ekranı.
///
/// Akış bilinçli olarak **önce rota, sonra oyun**: rota yolculuğun ne kadar
/// süreceğini belirler, oyun ise o süreyi neyle geçireceğini. Bu yüzden
/// yolculuk özeti üstte sabit durur — oyuncu neyi seçtiğini unutmasın.
class GameSelectScreen extends StatelessWidget {
  const GameSelectScreen({super.key, required this.journey});

  final Journey journey;

  Future<void> _start(BuildContext context, MiniGame game) async {
    if (!game.isAvailable) return;
    // Bugün tek oynanabilir oyun blok oyunu; katalog büyüdüğünde burada
    // `game.id`'ye göre dallanılacak.
    await AppRoutes.openGame(context, journey);
  }

  @override
  Widget build(BuildContext context) {
    final line = AppScope.of(context).metro.lineById(journey.lineId);
    final lineTheme = LineTheme.from(line?.color ?? AppColors.brandNavy);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Oyun seç',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          _JourneySummary(journey: journey, lineTheme: lineTheme),
          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('OYUNLAR'),
          for (final game in MiniGames.all) ...<Widget>[
            _GameCard(
              game: game,
              accent: lineTheme.accent,
              onTap: () => _start(context, game),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

/// Hangi yolculuk için oyun seçildiğini hatırlatan üst şerit.
class _JourneySummary extends StatelessWidget {
  const _JourneySummary({required this.journey, required this.lineTheme});

  final Journey journey;
  final LineTheme lineTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: AppColors.brandNavy,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                LineBadge(label: journey.lineId, color: lineTheme.color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${journey.origin.name} → ${journey.destination.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            // Süre ve açıklama alt alta: yan yana konsaydı ikisi de esnek
            // olmadığı için dar ekranda ve büyük yazı ölçeğinde (uygulama
            // 1.6'ya kadar destekliyor) satır taşardı.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${Formatters.approxMinutes(journey.estimatedMinutes)}'
                        ' · ${journey.stopCount} durak',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Seçtiğin oyun bu süre kadar sürecek.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 3, color: lineTheme.accent),
        ],
      ),
    );
  }
}

/// Tek bir oyun kartı. Kilitliyse soluk ve tıklanamaz.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.game,
    required this.accent,
    required this.onTap,
  });

  final MiniGame game;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locked = !game.isAvailable;
    final foreground = locked ? AppColors.textMuted : AppColors.textPrimary;

    return Semantics(
      button: !locked,
      enabled: !locked,
      label: locked
          ? '${game.name}, yakında eklenecek, henüz oynanamaz'
          : '${game.name}. ${game.tagline}',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: locked ? 0.55 : 1,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: InkWell(
              // Kilitli kartta `onTap: null` — dokunma geri bildirimi de olmaz,
              // böylece "bozuk mu?" hissi vermez.
              onTap: locked ? null : onTap,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(
                    color: locked ? AppColors.outline : accent,
                    width: locked ? 1 : 1.6,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: locked
                            ? AppColors.surfaceHigh
                            : accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        locked ? Icons.lock_rounded : game.icon,
                        size: 22,
                        color: locked ? AppColors.textMuted : accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: Text(
                                  game.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: foreground,
                                  ),
                                ),
                              ),
                              if (locked) ...<Widget>[
                                const SizedBox(width: AppSpacing.sm),
                                const _SoonBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            game.tagline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!locked) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.play_arrow_rounded, size: 28, color: accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoonBadge extends StatelessWidget {
  const _SoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outline),
      ),
      child: const Text(
        'YAKINDA',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}
