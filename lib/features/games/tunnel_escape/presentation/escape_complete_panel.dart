import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../session/widgets/run_rewards_summary.dart';
import '../application/tunnel_escape_controller.dart';
import 'escape_widgets.dart';

const Cubic _kEase = Cubic(0.32, 0.72, 0, 1);

/// Bölüm sonu: kısa, tek bakışta okunan bir panel.
///
/// Modal değil — tahtanın alt yarısına oturuyor, tahta arkada görünmeye
/// devam ediyor. Hiyerarşi: başlık, yıldızlar, hamle; en belirgin eylem
/// **sonraki durak**. Hedef duygu "bir tane daha": sonraki bölüm tek
/// dokunuş uzakta ve düğme başparmağın altında.
class EscapeCompletePanel extends StatefulWidget {
  const EscapeCompletePanel({
    super.key,
    required this.completion,
    required this.accent,
    required this.onNext,
    required this.onReplay,
    required this.onMap,
  });

  final EscapeCompletion completion;

  /// Haritadaki hattın rengi — başlık çizgisi.
  final Color accent;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onMap;

  @override
  State<EscapeCompletePanel> createState() => _EscapeCompletePanelState();
}

class _EscapeCompletePanelState extends State<EscapeCompletePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enter.status == AnimationStatus.dismissed) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Animation<double> _interval(
    double begin,
    double end, {
    Curve curve = _kEase,
  }) => CurvedAnimation(
    parent: _enter,
    curve: Interval(begin, end, curve: curve),
  );

  @override
  Widget build(BuildContext context) {
    final done = widget.completion;
    final slide = _interval(0, 0.35);
    final title = done.isFinale ? 'HAT TAMAMLANDI' : 'HAT AÇILDI';

    final String? note;
    if (done.usedHint && done.stars < 3) {
      note = 'İpucuyla bitti: üçüncü yıldız ipucusuz kazanılır.';
    } else if (done.stars < 3) {
      note = 'Üç yıldız için en fazla ${done.level.threeStarMoves} hamle.';
    } else if (done.isFinale) {
      note = '60 bölümün hepsi bitti. Yıldızlar için haritaya dön.';
    } else {
      note = null;
    }

    return FadeTransition(
      opacity: slide,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.2),
          end: Offset.zero,
        ).animate(slide),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.outline),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.background.withValues(alpha: 0.7),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (done.isFinale) ...<Widget>[
                const _LineStripe(),
                const SizedBox(height: AppSpacing.md),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppText.title.copyWith(
                    fontSize: done.isFinale ? 28 : 26,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Semantics(
                label: '3 yıldızdan ${done.stars}',
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: ScaleTransition(
                            scale: _interval(
                              0.28 + i * 0.14,
                              0.62 + i * 0.14,
                              curve: Curves.easeOutBack,
                            ),
                            child: EscapeStar(
                              filled: i < done.stars,
                              size: 38,
                              emptyColor: AppColors.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Satır değil sarmal: büyük yazı boyutunda ya da dar ekranda
              // puan alt satıra iner, taşmaz.
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  Text(
                    '${done.moves} HAMLE',
                    style: AppText.stat.copyWith(fontSize: 18),
                  ),
                  Text(
                    'EN İYİ ${done.bestMoves}',
                    style: AppText.captionStrong.copyWith(
                      color: done.isNewBest
                          ? escapeStarColor
                          : AppColors.textMuted,
                      fontFeatures: kTabularFigures,
                    ),
                  ),
                  if (done.pointsAwarded > 0)
                    Text(
                      '+${Formatters.score(done.pointsAwarded)} puan',
                      style: AppText.captionStrong.copyWith(
                        color: widget.accent,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                ],
              ),
              if (note != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(note, textAlign: TextAlign.center, style: AppText.caption),
              ],
              // Bu bölümle açılan rozet (İlk Kaçış gibi) burada, anında
              // kutlanır; koşunun sonunu beklemez.
              RunRewardsSummary(accent: widget.accent),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: AppFeedback.onTap(context, widget.onReplay),
                      child: const Text('TEKRAR'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: AppFeedback.onTap(
                        context,
                        done.hasNext ? widget.onNext : widget.onMap,
                      ),
                      child: Text(
                        done.hasNext ? 'SONRAKİ DURAK' : 'HAT HARİTASI',
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Son bölümün kutlaması: dört hattın renkleri tek şeritte — dört hat
/// baştan sona gidildi.
class _LineStripe extends StatelessWidget {
  const _LineStripe();

  static const List<Color> _colors = <Color>[
    Color(0xFF019A44), // M2
    Color(0xFF05A8E2), // M3
    Color(0xFFE72177), // M4
    Color(0xFF9B5D96), // M5, koyu zeminde açılmış
  ];

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 6,
      width: 120,
      child: Row(
        children: <Widget>[
          for (final color in _colors)
            Expanded(child: ColoredBox(color: color)),
        ],
      ),
    ),
  );
}
