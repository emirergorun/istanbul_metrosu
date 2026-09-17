import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../journey/models/journey.dart';
import 'game_glyph.dart';
import 'mini_game.dart';

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
    await AppRoutes.openGame(context, journey, gameId: game.id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final line = scope.metro.lineById(journey.lineId);
    final lineTheme = LineTheme.from(line?.color ?? AppColors.brandNavy);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Oyun seç', style: AppText.title),
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
              // Rekor **oyuna ve rotaya** birlikte bağlı: aynı rotada Blok
              // Metro'daki rekor, Ray Uçuşu'ndakiyle karşılaştırılamaz.
              record: scope.store.bestScoreForGameRoute(
                gameId: game.id,
                originId: journey.origin.id,
                destinationId: journey.destination.id,
              ),
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
                    style: AppText.lead.copyWith(color: Colors.white),
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
                        style: AppText.caption.copyWith(
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
                  style: AppText.caption.copyWith(
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
    required this.record,
    required this.onTap,
  });

  final MiniGame game;

  /// Bu oyunun **bu rotadaki** rekoru; 0 ise rotada henüz oynanmamış.
  final int record;

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
          child: Pressable(
            // Kilitli kartta `onTap: null` — dokunma geri bildirimi de olmaz,
            // böylece "bozuk mu?" hissi vermez.
            onTap: locked ? null : onTap,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                // Kenarlık nötr: altı kartın da hat renginde çerçevesi
                // olunca hepsi "seçili" gibi görünüyor ve aralarında
                // hiyerarşi kalmıyordu. Hat kimliği yukarıdaki yolculuk
                // şeridinde zaten var; kart burada içeriğiyle ayrışmalı.
                border: Border.all(
                  color: locked ? AppColors.outline : AppColors.surfaceHigh,
                  width: locked ? 1 : 1.6,
                ),
              ),
              child: Row(
                children: <Widget>[
                  // Kutu ve glif **nötr**. Altı oyuna altı ayrı pastel ton
                  // verilmişti; hepsi aynı ağırlıktaydı, hiçbiri bir şey
                  // söylemiyordu ve ekrandaki gerçek renk sistemiyle —
                  // hat kimliğiyle — yarışıyordu. Ayrımı glif ve ad yapar.
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.gameGlyphBox,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: GameGlyphIcon(
                      glyph: locked ? GameGlyph.locked : game.glyph,
                      color: locked ? AppColors.gameGlyphLocked : game.color,
                      size: 26,
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
                                // Oyun adı tabela fontunda: ekran başlığı
                                // ("OYUN SEÇ") ile aynı ses. Kart adı gövde
                                // fontundayken başlıkla aynı hiyerarşide
                                // duruyor ve liste bir ayar ekranı gibi
                                // okunuyordu.
                                style: AppText.tileTitle.copyWith(
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
                          style: AppText.caption,
                        ),
                        // Seçim körlemesine yapılmasın: oyuncu bu oyunu bu
                        // rotada oynadıysa geçmesi gereken sayı kartta yazar.
                        // Rekor oyunun kendi renginde — hangi oyuna ait
                        // olduğu bir bakışta anlaşılır.
                        if (!locked) ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                            record > 0
                                ? 'BU ROTADA REKORUN  ${Formatters.score(record)}'
                                : 'BU ROTADA İLK KEZ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.micro.copyWith(
                              fontFeatures: kTabularFigures,
                              color: record > 0
                                  ? game.color
                                  : AppColors.textMuted.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!locked) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    // Oynat oku bir eylem çağrısı, kimlik değil: hattan
                    // bağımsız sabit aksiyon renginde kalır.
                    const Icon(
                      Icons.play_arrow_rounded,
                      size: 28,
                      color: AppColors.action,
                    ),
                  ],
                ],
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
      child: const Text('YAKINDA', style: AppText.micro),
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
        style: AppText.micro.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
