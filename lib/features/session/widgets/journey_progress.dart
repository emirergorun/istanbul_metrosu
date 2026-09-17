import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/metro_train.dart';
import '../../journey/models/station_progress.dart';

/// Alt sabit alandaki metro ilerleme göstergesi.
///
/// İlerleme **aktif oyun süresine** dayanır (GPS yok, konum izni yok):
/// `progress = aktifOyunSüresi / tahminiYolculukSüresi`, 0..1 arası clamp.
class JourneyProgressBar extends StatelessWidget {
  const JourneyProgressBar({
    super.key,
    required this.lineId,
    required this.originName,
    required this.destinationName,
    required this.progress,
    required this.remainingSeconds,
    required this.accent,
    this.nextStopName,
    this.isMoving = true,
    this.stopCount,
    this.stationProgress,
    this.arrivalPulse = 0,
  });

  final String lineId;
  final String originName;
  final String destinationName;

  /// 0.0 - 1.0
  final double progress;
  final int remainingSeconds;
  final Color accent;

  /// Yaklaşık "bir sonraki durak". Gerçek konumdan değil, ilerleme
  /// oranından türetilir.
  final String? nextStopName;

  /// Oyun duraklatıldığında tren de durur.
  final bool isMoving;

  /// Yolculuktaki durak arası sayısı; ara istasyon noktaları buna göre
  /// çizilir. Verilmezse eski davranış (%25 / %50 / %75) korunur.
  final int? stopCount;

  /// Yolculuğun durak düzeyindeki hâli.
  ///
  /// Verilirse üstteki sol etiket **biniş durağı** yerine trenin şu an
  /// ayrıldığı durağı gösterir ve ray üzerinde içinde bulunulan durak arası
  /// vurgulanır. Verilmezse çubuk eski hâliyle çizilir — bu widget'ı altı
  /// oyun paylaşıyor, hiçbirinin ekranı bozulmamalı.
  final StationProgress? stationProgress;

  /// Durağa varış kutlaması, 0.0 – 1.0. 0 ise kutlama yok.
  final double arrivalPulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              LineBadge(label: lineId, color: accent, compact: true),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  stationProgress?.departed.name ?? originName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  destinationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: AppText.captionStrong.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: isMoving
                ? AppConstants.progressTickDuration
                : Duration.zero,
            curve: Curves.linear,
            builder: (context, value, _) => _ProgressTrack(
              progress: value,
              accent: accent,
              stopCount: stopCount,
              stationsPassed: stationProgress?.stationsPassed,
              arrivalPulse: arrivalPulse,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  nextStopName == null ? '' : 'Sonraki durak: $nextStopName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                remainingSeconds <= 0
                    ? 'Durağına yaklaştın'
                    : '${Formatters.remaining(remainingSeconds)} kaldı',
                style: AppText.captionStrong.copyWith(
                  fontFeatures: kTabularFigures,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({
    required this.progress,
    required this.accent,
    this.stopCount,
    this.stationsPassed,
    this.arrivalPulse = 0,
  });

  final double progress;
  final Color accent;
  final int? stopCount;
  final int? stationsPassed;
  final double arrivalPulse;

  static const double _height = 30;
  static const double _trainHeight = 18;
  static double get _trainWidth => MetroTrain.widthFor(height: _trainHeight);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final travel = (width - _trainWidth).clamp(0.0, double.infinity);

        return SizedBox(
          height: _height,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: CustomPaint(
                  painter: _TrackPainter(
                    progress: progress,
                    accent: accent,
                    stopCount: stopCount,
                    stationsPassed: stationsPassed,
                    arrivalPulse: arrivalPulse,
                  ),
                ),
              ),
              Positioned(
                left: travel * progress,
                top: (_height - _trainHeight) / 2,
                child: MetroTrain(color: accent, height: _trainHeight),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.progress,
    required this.accent,
    this.stopCount,
    this.stationsPassed,
    this.arrivalPulse = 0,
  });

  final double progress;
  final Color accent;
  final int? stopCount;

  /// Geçilen durak sayısı; son geçilen durak vurgulanır.
  final int? stationsPassed;

  /// Varış kutlaması, 0.0 – 1.0.
  final double arrivalPulse;

  /// Ara istasyonların yolculuktaki konumu.
  ///
  /// Durak bonusu her gerçek durakta (`i / stopCount`) veriliyor; noktalar
  /// da orada durmalı. Sabit %25/%50/%75, tek duraklık yolculukta var
  /// olmayan üç istasyon, 17 duraklık yolculukta ise yalnız üç istasyon
  /// gösteriyordu.
  List<double> get _stationRatios {
    final stops = stopCount;
    if (stops == null) return const <double>[0.25, 0.5, 0.75];
    return <double>[for (var i = 1; i < stops; i++) i / stops];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const inset = 6.0;
    final left = inset;
    final right = size.width - inset;

    canvas.drawLine(
      Offset(left, y),
      Offset(right, y),
      Paint()
        ..color = AppColors.outline
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawLine(
      Offset(left, y),
      Offset(left + (right - left) * progress, y),
      Paint()
        ..color = accent
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Ara istasyon işaretleri.
    //
    // Az önce geçilen durak büyür ve kısa bir halka atar: oyuncu gözünü
    // tahtadan ayırmadan "bir durak daha geçtim"i görür. Kutlama çubuğun
    // içinde kalır, oyunu durdurmaz.
    final justPassed = stationsPassed;
    var index = 1;
    for (final ratio in _stationRatios) {
      final x = left + (right - left) * ratio;
      final passed = progress >= ratio;
      final isLatest = justPassed != null && index == justPassed;
      final pulse = isLatest ? arrivalPulse : 0.0;

      if (pulse > 0) {
        canvas.drawCircle(
          Offset(x, y),
          3 + 9 * pulse,
          Paint()
            ..color = accent.withValues(alpha: 0.45 * (1 - pulse))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }

      canvas.drawCircle(
        Offset(x, y),
        3 + 2.5 * pulse,
        Paint()..color = passed ? accent : AppColors.outline,
      );
      index++;
    }

    // Başlangıç ve varış noktaları.
    canvas.drawCircle(Offset(left, y), 5, Paint()..color = accent);
    canvas.drawCircle(
      Offset(right, y),
      5,
      Paint()
        ..color = progress >= 1 ? accent : AppColors.textMuted
        ..style = progress >= 1 ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.stopCount != stopCount ||
      oldDelegate.stationsPassed != stationsPassed ||
      oldDelegate.arrivalPulse != arrivalPulse;
}
