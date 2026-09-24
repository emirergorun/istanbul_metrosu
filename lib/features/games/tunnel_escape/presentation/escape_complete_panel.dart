import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../session/widgets/run_rewards_summary.dart';
import '../application/tunnel_escape_controller.dart';
import 'escape_widgets.dart';

const Cubic _kEase = Cubic(0.32, 0.72, 0, 1);

/// Bölüm sonu: tek sütun, üç katman.
///
/// Okuma sırası sabit: **başarı** (başlık), **performans** (yıldız, hamle),
/// **sıradaki eylem**. Her şey ortada hizalı; sütunun tek baskın ögesi tam
/// genişlikteki SONRAKİ DURAK düğmesi. Tekrar oynamak ikinci sırada, düz
/// metin düğme: iki eşit ağırlıklı düğme göz için iki ayrı hedef demekti.
///
/// Panel tahtanın alt kısmına oturur, düğme denetimlerin yerine gelir:
/// oyuncunun başparmağı zaten oradadır. Tahta arkada, karartılmış olarak
/// görünür kalır.
///
/// Giriş kısa ve kademeli (~0,75 sn): panel, başlık, yıldızlar tek tek,
/// hamle, en son düğmeler. Düğmeler görünene kadar dokunuş almaz — yıldız
/// izlerken yanlışlıkla bir sonraki bölüme geçilmesin.
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

  /// Haritadaki hattın rengi — puan satırı ve rozet özeti.
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
    duration: const Duration(milliseconds: 760),
  );

  /// Düğmelerin dokunuş almaya başladığı an.
  static const double _actionsFrom = 0.62;

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

  /// Aşağıdan hafifçe yükselerek belirir.
  Widget _rise(Animation<double> animation, Widget child, {double by = 0.25}) =>
      FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, by),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final done = widget.completion;
    final title = done.isFinale ? 'HAT TAMAMLANDI' : 'HAT AÇILDI';

    final String? note;
    if (done.usedHint && done.stars < 3) {
      note = 'İpucuyla bitti: üçüncü yıldız ipucusuz kazanılır.';
    } else if (done.stars < 3) {
      note = 'Üç yıldız için en fazla ${done.level.threeStarMoves} hamle.';
    } else if (done.isFinale) {
      note = 'Bütün bölümler bitti. Yıldızlar için haritaya dön.';
    } else {
      note = null;
    }

    final actions = _interval(_actionsFrom, 1);

    return _rise(
      _interval(0, 0.34),
      by: 0.12,
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 1. Başarı.
            _rise(
              _interval(0.06, 0.4),
              Column(
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
                      style: AppText.title.copyWith(fontSize: 28, height: 1.05),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // 2. Performans: yıldızlar, hamle, en iyi.
            Semantics(
              label: '3 yıldızdan ${done.stars}',
              child: ExcludeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: FadeTransition(
                          opacity: _interval(0.2 + i * 0.12, 0.36 + i * 0.12),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.4, end: 1).animate(
                              _interval(
                                0.2 + i * 0.12,
                                0.52 + i * 0.12,
                                curve: Curves.easeOutBack,
                              ),
                            ),
                            child: EscapeStar(
                              filled: i < done.stars,
                              size: 36,
                              emptyColor: AppColors.outline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _rise(
              _interval(0.42, 0.74),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${done.moves} HAMLE',
                    textAlign: TextAlign.center,
                    style: AppText.stat.copyWith(fontSize: 26, height: 1.1),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _PerformanceLine(completion: done, accent: widget.accent),
                  if (note != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      note,
                      textAlign: TextAlign.center,
                      style: AppText.caption,
                    ),
                  ],
                ],
              ),
            ),
            // Bu bölümle açılan rozet (İlk Kaçış gibi) burada, anında
            // kutlanır; koşunun sonunu beklemez.
            RunRewardsSummary(accent: widget.accent),
            const SizedBox(height: AppSpacing.xl),
            // 3. Sıradaki eylem.
            AnimatedBuilder(
              animation: _enter,
              builder: (BuildContext context, Widget? child) => IgnorePointer(
                ignoring: _enter.value < _actionsFrom,
                child: child,
              ),
              child: _rise(
                actions,
                by: 0.15,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FilledButton(
                      onPressed: AppFeedback.onTap(
                        context,
                        done.hasNext ? widget.onNext : widget.onMap,
                      ),
                      child: Text(
                        done.hasNext ? 'SONRAKİ DURAK' : 'HAT HARİTASI',
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    TextButton(
                      onPressed: AppFeedback.onTap(context, widget.onReplay),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Tekrar oyna'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hamlenin altındaki tek satır: kaydın durumu ve kazanılan puan.
///
/// İlk sonuçta "en iyi" yazmak anlamsız (az önce yazılan hamlenin
/// kendisi); yalnız bu bulmacada önceden bir sonuç varsa kayıtla
/// karşılaştırılır. Yeni en iyi
/// sinyal sarısıyla — ekranda o renk yalnız yıldızlarda ve burada.
class _PerformanceLine extends StatelessWidget {
  const _PerformanceLine({required this.completion, required this.accent});

  final EscapeCompletion completion;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final done = completion;
    final previousBest = done.record.previous?.bestMoves;
    final parts = <InlineSpan>[];
    const base = TextStyle(fontFeatures: kTabularFigures);

    if (previousBest != null && done.isNewBest) {
      parts.add(
        TextSpan(
          text: 'YENİ EN İYİ · önceki $previousBest',
          style: base.copyWith(
            color: escapeStarColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (previousBest != null) {
      parts.add(TextSpan(text: 'En iyi ${done.bestMoves}', style: base));
    }
    if (done.pointsAwarded > 0) {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: '  ·  '));
      parts.add(
        TextSpan(
          text: '+${Formatters.score(done.pointsAwarded)} puan',
          style: base.copyWith(color: accent, fontWeight: FontWeight.w700),
        ),
      );
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: parts),
      textAlign: TextAlign.center,
      style: AppText.caption.copyWith(color: AppColors.textSecondary),
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
