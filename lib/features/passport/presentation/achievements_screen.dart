import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../daily/domain/day_stamp.dart';
import '../../discovery/presentation/widgets/discovery_progress_track.dart';
import '../application/achievement_controller.dart';
import '../domain/achievement.dart';
import 'widgets/achievement_badge.dart';

/// Yolculuk Kartı'nın rozet sayfası.
///
/// Kilitli başarımın adı **gizlenmiyor**. "???" merak uyandırmıyor, hedefi
/// yok ediyor: oyuncu neye çalışacağını bilemiyor. Keşif ekranında
/// keşfedilmemiş durakların adları da görünür — aynı kural.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final achievements = AppScope.of(context).achievements;
    if (achievements == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('ROZETLER', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: achievements,
          builder: (BuildContext context, _) {
            // Pin rafıyla **aynı** sıralama; bkz. [AchievementController.ordered].
            final definitions = achievements.ordered;
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              itemCount: definitions.length + 1,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.stack),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.stack),
                    child: _Summary(controller: achievements),
                  );
                }
                final definition = definitions[index - 1];
                return AchievementTile(
                  definition: definition,
                  unlocked: achievements.isUnlocked(definition),
                  progress: achievements.progressOf(definition),
                  unlockedOn: achievements.unlockedOn(definition),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});

  final AchievementController controller;

  @override
  Widget build(BuildContext context) {
    final unlocked = controller.unlockedCount;
    final total = controller.totalCount;

    return Semantics(
      label: '$total rozetin $unlocked tanesi kazanıldı',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text('$unlocked', style: AppText.display),
            const SizedBox(width: AppSpacing.sm),
            // Esnek: 38 puntoluk sayı 1.6× ölçekte 320 pikselin yarısını
            // yiyor, kalan metin sabit genişlikte satırı taşırıyordu.
            Expanded(
              child: Text(
                '/ $total rozet kazanıldı',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodyStrong.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tek bir rozetin satırı — kartta ve bu ekranda aynı.
class AchievementTile extends StatelessWidget {
  const AchievementTile({
    super.key,
    required this.definition,
    required this.unlocked,
    required this.progress,
    this.unlockedOn,
  });

  final AchievementDefinition definition;
  final bool unlocked;

  /// Ham ilerleme; hedefe göre oranlanır.
  final int progress;

  /// Açıldığı gün. `null` ise bilinmiyor — uydurulmuyor, yazılmıyor.
  final DayStamp? unlockedOn;

  @override
  Widget build(BuildContext context) {
    final ratio = definition.target == 0
        ? 0.0
        : (progress / definition.target).clamp(0.0, 1.0);
    final color = AchievementBadge.colorOf(definition.category);

    return Semantics(
      container: true,
      label: unlocked
          ? '${definition.title}, kazanıldı. ${definition.description}'
          : '${definition.title}, kilitli. ${definition.description} '
                '$progress bölü ${definition.target}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: unlocked
                  ? color.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AchievementBadge(definition: definition, unlocked: unlocked),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      definition.title,
                      style: AppText.tileTitle.copyWith(
                        color: unlocked
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(definition.description, style: AppText.caption),
                    if (unlocked && unlockedOn != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${unlockedOn!.day.toString().padLeft(2, '0')}.'
                        '${unlockedOn!.month.toString().padLeft(2, '0')}.'
                        '${unlockedOn!.year} tarihinde kazanıldı',
                        style: AppText.micro.copyWith(
                          color: AppColors.textMuted,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                    // İlerleme rozetin üstünde değil **kartta**: pin
                    // temiz kalıyor, "ne kadar kaldı" sorusunu satır
                    // yanıtlıyor.
                    if (!unlocked && definition.target > 1) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      DiscoveryProgressTrack(
                        value: ratio,
                        color: color,
                        // Oluk kartın zemininden **koyu**: kart rengiyle
                        // aynı verilince çubuk kartın içinde kayboluyordu.
                        background: AppColors.background,
                        thickness: 5,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              achievementRemainingText(definition, progress),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.micro.copyWith(
                                fontFamily: AppFonts.display,
                                color: color,
                              ),
                            ),
                          ),
                          Text(
                            '$progress / ${definition.target}',
                            style: AppText.micro.copyWith(
                              color: AppColors.textMuted,
                              fontFeatures: kTabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "7 DURAK KALDI" — kalanı ölçünün kendi birimiyle söyler.
///
/// Sayı tek başına ("18 / 25") ne kadar kaldığını hesaplatıyordu. Birim
/// ölçüden geliyor: durak sayan bir rozet durak, gün sayan gün der.
String achievementRemainingText(
  AchievementDefinition definition,
  int progress,
) {
  final left = (definition.target - progress).clamp(0, definition.target);
  final unit = switch (definition.metric) {
    AchievementMetric.stationsDiscovered => 'DURAK',
    AchievementMetric.interchangesDiscovered => 'AKTARMA',
    AchievementMetric.linesCompleted => 'HAT',
    AchievementMetric.journeysCompleted => 'YOLCULUK',
    AchievementMetric.distinctGamesPlayed => 'OYUN',
    AchievementMetric.bestStreak ||
    AchievementMetric.dailyDaysCompleted => 'GÜN',
    AchievementMetric.bestQuizScore => 'PUAN',
    AchievementMetric.gameRunsFinished => 'OYUN',
    AchievementMetric.escapeLevelsCompleted ||
    AchievementMetric.escapePerfectLevels => 'BÖLÜM',
    AchievementMetric.escapeStars => 'YILDIZ',
  };
  return '$left $unit KALDI';
}
