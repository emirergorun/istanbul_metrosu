import 'package:flutter/material.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/line_badge.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../games/catalog/mini_game.dart';
import '../../domain/daily_plan.dart';
import 'streak_badge.dart';

/// Ana ekrandaki günlük yolculuk girişi.
///
/// Keşif şeridiyle **aynı dil**: tek satır yükseklikte, aynı zemin, aynı
/// köşe. İkisi bir arada "kalıcı ilerleme" grubunu kuruyor; birincil eylem
/// (oyna) onların altında ve tek başına kalıyor.
///
/// Günlük yolculuk **zorunlu değil**. Kart oyuncunun önünü kesmez, ekranı
/// kaplamaz ve serbest oyuna giden yolu daraltmaz — yalnızca ikinci bir
/// kapı açar.
class DailyEntryStrip extends StatelessWidget {
  const DailyEntryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final daily = AppScope.of(context).daily;
    if (daily == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: daily,
      builder: (BuildContext context, _) {
        final plan = daily.plan;
        // Metro verisi oynanabilir bir günlük rota vermediyse şerit hiç
        // çizilmez: boş bir kart, olmayan bir karttan kötüdür.
        if (plan == null) return const SizedBox.shrink();

        final game = MiniGames.byId(plan.gameId);
        final done = daily.isDailyComplete;
        final completed = daily.completedMissionCount;
        final total = daily.missions.length;

        return Pressable(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.daily),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          semanticLabel: _spokenLabel(
            plan: plan,
            gameName: game?.name,
            done: done,
            completed: completed,
            total: total,
            streak: daily.streak,
            streakDoneToday: daily.streakCompletedToday,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'BUGÜNÜN YOLCULUĞU',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.sectionTitle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // Görev sayacı **şeritte**: "bugün yapacak işim kaldı
                      // mı" sorusunun cevabı için ekran açmak gerekmiyor.
                      Text.rich(
                        TextSpan(
                          text: '$completed',
                          style: AppText.stat,
                          children: <InlineSpan>[
                            TextSpan(
                              text: ' / $total',
                              style: AppText.captionStrong.copyWith(
                                color: AppColors.textMuted,
                                fontFeatures: kTabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      LineBadge(
                        label: plan.journey.lineId,
                        color:
                            AppScope.of(
                              context,
                            ).metro.lineById(plan.journey.lineId)?.color ??
                            AppColors.brandNavy,
                        compact: true,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '${plan.journey.origin.name} → '
                          '${plan.journey.destination.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      // Seri rozeti burada, oyunun glifi yerine.
                      //
                      // 16 piksellik glif okunmuyordu ve hangi oyun olduğu
                      // zaten bir dokunuş ötede. Seri ise ana ekranda
                      // görünmeye değer: oyuncunun kaybetmek istemediği tek
                      // şey o.
                      if (done)
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: AppColors.success,
                        )
                      else
                        StreakBadge(
                          days: daily.streak,
                          completedToday: daily.streakCompletedToday,
                        ),
                    ],
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

/// Şeridin ekran okuyucuya söylediği tek cümle.
///
/// Rozetler ve sayaçlar `ExcludeSemantics` altında çiziliyor; buradaki metin
/// **hepsini** taşımak zorunda. Seri bir zamanlar dışarıda kalmıştı: ekranda
/// duruyor ama VoiceOver hiç okumuyordu.
String _spokenLabel({
  required DailyPlan plan,
  required String? gameName,
  required bool done,
  required int completed,
  required int total,
  required int streak,
  required bool streakDoneToday,
}) {
  final buffer = StringBuffer('Bugünün yolculuğu');
  if (done) {
    buffer.write(' tamamlandı');
  } else {
    buffer.write(
      ': ${plan.journey.lineId} hattı, ${plan.journey.origin.name} '
      'durağından ${plan.journey.destination.name} durağına'
      '${gameName == null ? '' : ', $gameName'}',
    );
  }
  buffer.write('. $total görevin $completed tanesi bitti.');
  if (streak > 0) {
    buffer.write(
      ' $streak günlük seri, bugün '
      '${streakDoneToday ? 'tamamlandı' : 'henüz tamamlanmadı'}.',
    );
  }
  buffer.write(' Günlük yolculuğu gör');
  return buffer.toString();
}
