import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../daily/domain/daily_mission.dart';
import '../../passport/domain/achievement.dart';
import '../../passport/presentation/widgets/achievement_badge.dart';

/// Koşunun meta ödülleri — sonuç panelinin içinde, **toplu** olarak.
///
/// Günün yolculuğu bitmiş, iki görev tamamlanmış ve bir başarım açılmış
/// olabilir. Bunların her biri kendi penceresini açsaydı oyuncu oyun
/// bittikten sonra üç kez "tamam"a basardı. Hepsi burada, tek yerde ve
/// oyunun akışını kesmeyen bir anda: sonuç paneli.
///
/// Ödül yoksa hiç çizilmez.
class RunRewardsSummary extends StatefulWidget {
  const RunRewardsSummary({super.key, required this.accent});

  final Color accent;

  @override
  State<RunRewardsSummary> createState() => _RunRewardsSummaryState();
}

class _RunRewardsSummaryState extends State<RunRewardsSummary> {
  bool _taken = false;

  bool _dailyDone = false;
  int _streak = 0;
  List<DailyMission> _missions = const <DailyMission>[];
  List<AchievementDefinition> _achievements = const <AchievementDefinition>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_taken) return;
    _taken = true;

    // Ödüller **bir kez** alınır ve durumda saklanır: panel yeniden
    // çizildiğinde kaybolmasınlar, ikinci bir koşuda tekrar çıkmasınlar.
    final scope = AppScope.of(context);
    final daily = scope.daily;
    if (daily != null) {
      _dailyDone = daily.consumeDailyCompletion();
      _streak = daily.streak;
      _missions = daily.consumeCompletedMissions();
    }
    _achievements = scope.achievements?.consumeUnlocked() ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final hasAnything =
        _dailyDone || _missions.isNotEmpty || _achievements.isNotEmpty;
    if (!hasAnything) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.stack),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_dailyDone) _DailyDoneBanner(streak: _streak),
          for (final mission in _missions) ...<Widget>[
            const SizedBox(height: AppSpacing.stack),
            _RewardRow(
              icon: Icons.task_alt_rounded,
              color: AppColors.success,
              label: 'GÖREV TAMAMLANDI',
              detail: mission.title,
            ),
          ],
          for (final achievement in _achievements) ...<Widget>[
            const SizedBox(height: AppSpacing.stack),
            _AchievementRow(definition: achievement),
          ],
        ],
      ),
    );
  }
}

/// Günün tamamlandığını söyleyen şerit.
///
/// Konfeti yok: kutlama, oyunun kendi diline ait bir onay damgası ve serinin
/// bir gün daha uzadığı bilgisiyle veriliyor. Kumarhane tonu, her gün
/// tekrarlanan bir ana yakışmaz.
class _DailyDoneBanner extends StatelessWidget {
  const _DailyDoneBanner({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: streak > 1
          ? 'Bugünün yolculuğu tamamlandı. Seri $streak gün.'
          : 'Bugünün yolculuğu tamamlandı.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            children: <Widget>[
              Text(
                'BUGÜNÜN YOLCULUĞU TAMAMLANDI',
                textAlign: TextAlign.center,
                style: AppText.micro.copyWith(
                  fontFamily: AppFonts.display,
                  color: AppColors.success,
                ),
              ),
              if (streak > 1) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  '$streak gün üst üste',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label. $detail',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: AppText.micro.copyWith(
                      fontFamily: AppFonts.display,
                      color: color,
                    ),
                  ),
                  Text(
                    detail,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.definition});

  final AchievementDefinition definition;

  @override
  Widget build(BuildContext context) {
    final color = AchievementBadge.colorOf(definition.category);

    return Semantics(
      container: true,
      label: 'Başarım açıldı. ${definition.title}',
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            AchievementBadge(
              definition: definition,
              unlocked: true,
              progress: 1,
              size: 28,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'BAŞARIM AÇILDI',
                    style: AppText.micro.copyWith(
                      fontFamily: AppFonts.display,
                      color: color,
                    ),
                  ),
                  Text(
                    definition.title,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
