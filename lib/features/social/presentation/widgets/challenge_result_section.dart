import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../journey/models/journey.dart';
import '../../domain/challenge_record.dart';

/// Sonuç panelinin sosyal bölümü.
///
/// İki hâli var ve ikisi de **aynı yerde**:
///
/// - Meydan okuma oynandıysa karşılaştırma ve rövanş.
/// - Normal koşuysa "arkadaşına meydan oku".
///
/// Panel bunların hangisi olduğunu bilmiyor; bölüm kendi kararını
/// [ChallengeSession]'a bakarak veriyor. Sosyal katman kapalıysa hiç
/// çizilmiyor.
class ChallengeResultSection extends StatefulWidget {
  const ChallengeResultSection({
    super.key,
    required this.score,
    required this.journey,
    required this.gameId,
    required this.accent,
  });

  final int score;
  final Journey journey;
  final String gameId;
  final Color accent;

  @override
  State<ChallengeResultSection> createState() =>
      _ChallengeResultSectionState();
}

class _ChallengeResultSectionState extends State<ChallengeResultSection> {
  bool _recorded = false;
  ChallengeRecord? _record;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_recorded) return;
    _recorded = true;

    final scope = AppScope.of(context);
    final session = scope.challengeSession;
    final social = scope.social;
    if (session == null || social == null) return;

    final challenge = session.challenge;
    if (challenge == null) return;
    if (!session.matches(widget.gameId, widget.journey)) return;

    // Sonuç **bir kez** kaydediliyor. Panel yeniden çizildiğinde ya da
    // oyuncu tekrar oynayıp aynı panele döndüğünde ikinci satır açılmıyor;
    // [SocialController.recordResult] aynı kimliği ikinci kez kabul etmez.
    _record = social.recordResult(
      challenge: challenge,
      journey: widget.journey,
      myScore: widget.score,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final social = scope.social;
    if (social == null) return const SizedBox.shrink();

    final record = _record;
    if (record != null) {
      return _ChallengeComparison(record: record, accent: widget.accent);
    }

    // Meydan okuma değil: normal koşudan sosyal çıkış.
    //
    // Skor sıfırsa meydan okuma üretilmiyor — geçilecek bir hedef yok ve
    // "sıfırı geç" bir davet değil.
    if (widget.score <= 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.stack),
      child: OutlinedButton(
        onPressed: AppFeedback.onTap(context, () {
          final challenge = social.createChallenge(
            journey: widget.journey,
            gameId: widget.gameId,
            score: widget.score,
          );
          AppRoutes.openChallengeShare(context, challenge);
        }),
        child: const Text('ARKADAŞINA MEYDAN OKU'),
      ),
    );
  }
}

/// İki skorun karşılaştırması.
///
/// Sayı büyük, fark açık, dil ölçülü. Kaybedene "KAYBETTIN" demiyoruz:
/// bu bir arkadaş maçı ve asıl istediğimiz şey oyuncunun rövanş düğmesine
/// basması.
class _ChallengeComparison extends StatelessWidget {
  const _ChallengeComparison({required this.record, required this.accent});

  final ChallengeRecord record;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final outcome = record.outcome;
    final color = switch (outcome) {
      ChallengeOutcome.won => AppColors.success,
      ChallengeOutcome.lost => AppColors.textSecondary,
      ChallengeOutcome.tied => AppColors.warning,
    };
    final difference = record.difference;

    return Semantics(
      container: true,
      label:
          'Meydan okuma tamamlandı. Senin skorun ${record.myScore}, '
          '${record.opponentName} ${record.targetScore}. ${outcome.label}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.stack),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      outcome.label,
                      style: AppText.sectionTitle.copyWith(color: color),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: <Widget>[
                        _ScoreColumn(
                          label: 'SEN',
                          value: record.myScore,
                          strong: outcome == ChallengeOutcome.won,
                        ),
                        _ScoreColumn(
                          label: record.opponentName,
                          value: record.targetScore,
                          strong: outcome == ChallengeOutcome.lost,
                        ),
                      ],
                    ),
                    if (difference != 0) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${difference > 0 ? '+' : ''}'
                        '${Formatters.score(difference.abs())} fark',
                        style: AppText.caption.copyWith(
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.stack),
              OutlinedButton(
                onPressed: AppFeedback.onTap(context, () {
                  final social = AppScope.of(context).social;
                  if (social == null) return;
                  AppRoutes.openChallengeShare(
                    context,
                    social.rematchFrom(record),
                    isRematch: true,
                  );
                }),
                child: const Text('RÖVANŞ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.label,
    required this.value,
    required this.strong,
  });

  final String label;
  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.micro.copyWith(
              fontFamily: AppFonts.display,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            Formatters.score(value),
            maxLines: 1,
            style:
                (strong ? AppText.stat : AppText.statSmall).copyWith(
                  fontFeatures: kTabularFigures,
                  color: strong
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
