import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/telemetry/analytics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../games/catalog/game_cover.dart';
import '../../journey/models/journey.dart';
import '../domain/challenge.dart';
import '../domain/challenge_validator.dart';
import 'widgets/player_avatar.dart';

/// Okunmuş bir meydan okumanın onay ekranı.
///
/// **Okumak kabul etmek değil.** Kare okunur okunmaz oyun başlasaydı
/// oyuncu ne oynayacağını, hangi rotada ve hangi hedefe karşı olduğunu
/// görmeden yolculuğa binmiş olurdu. Burada üçü de yazılı ve tek bir
/// düğme var.
///
/// Kabul edilene kadar hiçbir kalıcı duruma dokunulmuyor: yolculuk sayacı,
/// keşif, günlük görev, rekor — hiçbiri.
class ChallengePreviewScreen extends StatelessWidget {
  const ChallengePreviewScreen({super.key, required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final social = scope.social;
    final discovery = scope.discovery;

    if (discovery == null || social == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final resolution = ChallengeValidator(
      metro: scope.metro,
      catalog: discovery.catalog,
      routes: scope.routeService,
    ).resolve(challenge, ownCode: social.me.code);

    if (!resolution.isValid) {
      return _InvalidChallenge(error: resolution.error!);
    }

    final journey = resolution.journey!;
    final game = resolution.game!;
    final line = scope.metro.lineById(journey.lineId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('MEYDAN OKUMA', style: AppText.title),
      ),
      bottomNavigationBar: _AcceptBar(
        challenge: challenge,
        journey: journey,
        gameId: game.id,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                PlayerAvatar(
                  code: challenge.creatorCode,
                  displayName: challenge.creatorName,
                  size: 44,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    '${challenge.creatorName} sana meydan okuyor',
                    style: AppText.bodyStrong,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.stack),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GameCoverCard.radius),
                  child: AspectRatio(
                    aspectRatio: GameCoverCard.aspectRatio,
                    child: GameCover(game: game),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.stack),
            _RouteRow(
              journey: journey,
              lineColor: line?.color ?? AppColors.brandNavy,
            ),
            const SizedBox(height: AppSpacing.stack),
            _TargetCard(target: challenge.targetScore, accent: game.color),
            const SizedBox(height: AppSpacing.stack),
            // Adaletin ne anlama geldiği açıkça yazılı: aynı rota, aynı
            // oyun, aynı süre ve aynı rastgelelik.
            Text(
              'AYNI ROTA · AYNI OYUN · AYNI SÜRE',
              textAlign: TextAlign.center,
              style: AppText.micro.copyWith(
                fontFamily: AppFonts.display,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.journey, required this.lineColor});

  final Journey journey;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        children: <Widget>[
          LineBadge(label: journey.lineId, color: lineColor),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${journey.origin.name} → ${journey.destination.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong,
                ),
                Text(
                  '${Formatters.approxMinutes(journey.estimatedMinutes)}'
                  ' · ${journey.stopCount} durak',
                  style: AppText.micro.copyWith(
                    color: AppColors.textMuted,
                    fontFeatures: kTabularFigures,
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

class _TargetCard extends StatelessWidget {
  const _TargetCard({required this.target, required this.accent});

  final int target;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'GEÇMEN GEREKEN',
            style: AppText.micro.copyWith(
              fontFamily: AppFonts.display,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            Formatters.score(target),
            style: AppText.display.copyWith(
              color: accent,
              fontFeatures: kTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kabul etme çubuğu.
///
/// Oyun **mevcut başlatma hattıyla** açılıyor ([AppRoutes.openGame]); V5a
/// ikinci bir oyun başlatma mimarisi kurmuyor. Keşif, günlük görev ve
/// rekor akışı bu yüzden meydan okumada da aynen çalışıyor.
class _AcceptBar extends StatelessWidget {
  const _AcceptBar({
    required this.challenge,
    required this.journey,
    required this.gameId,
  });

  final Challenge challenge;
  final Journey journey;
  final String gameId;

  Future<void> _accept(BuildContext context) async {
    final scope = AppScope.of(context);
    final session = scope.challengeSession;
    if (session == null) return;

    scope.analytics.log(
      AnalyticsEvent.challengeAccepted,
      params: <String, String>{'game_id': gameId},
    );
    // Oyun durumuna **ancak burada** dokunuluyor.
    session.begin(challenge, journey);
    await AppRoutes.openGame(context, journey, gameId: gameId);
    // Oyundan dönüldüğünde mod kapanıyor: bir sonraki Serbest Oyun koşusu
    // tohumsuz başlasın.
    session.end();
  }

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
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              FilledButton(
                onPressed: AppFeedback.onTap(context, () => _accept(context)),
                child: const Text('KABUL ET'),
              ),
              TextButton(
                onPressed: AppFeedback.onTap(
                  context,
                  () => Navigator.of(context).pop(),
                ),
                child: const Text('Vazgeç'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Doğrulamadan geçemeyen meydan okuma.
class _InvalidChallenge extends StatelessWidget {
  const _InvalidChallenge({required this.error});

  final ChallengeError error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('MEYDAN OKUMA', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.qr_code_2_rounded,
                  size: 40,
                  color: AppColors.textMuted,
                ),
                const SizedBox(height: AppSpacing.stack),
                Text(
                  error.title,
                  textAlign: TextAlign.center,
                  style: AppText.sectionTitle,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  error.detail,
                  textAlign: TextAlign.center,
                  style: AppText.body,
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                OutlinedButton(
                  onPressed: AppFeedback.onTap(
                    context,
                    () => Navigator.of(context).pop(),
                  ),
                  child: const Text('GERİ DÖN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
