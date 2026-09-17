import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../journey/models/station.dart';
import '../../journey/models/station_progress.dart';
import '../journey_run.dart';

/// Durağa varış bildirimi — **altı oyun için ortak**.
///
/// Yolculuk ilerlemesi oyuncunun gözünden kaçıyordu: ilerleme çubuğundaki
/// tren sessizce kayıyor, geçilen durak hiçbir yerde söylenmiyordu. Bu şerit
/// her durak geçişinde durağın adını gösterir; o duraktan beri kayda değer
/// bir şey yapıldıysa kazanılan bonusu da ekler.
///
/// Tetikleyici [JourneyRun.stationPulse]: bonus değil, **durağın kendisi**.
/// Bonus yalnızca hak edildiğinde gelir, oysa durak her hâlükârda geçilir.
///
/// Oyunu durdurmaz: kısa bir şerit iner, bekler, kalkar.
class StationBanner extends StatefulWidget {
  const StationBanner({
    super.key,
    required this.run,
    required this.lineStations,
    required this.accent,
  });

  final JourneyRun run;

  /// Hattın sıraya dizilmiş istasyonları; durak adı buradan çözülür.
  final List<Station> lineStations;

  final Color accent;

  /// Şeridin ekranda kalma süresi.
  static const Duration visibleFor = Duration(milliseconds: 1600);

  @override
  State<StationBanner> createState() => _StationBannerState();
}

class _StationBannerState extends State<StationBanner>
    with SingleTickerProviderStateMixin {
  /// `late final` **değil**: bu widget hiç şerit göstermeden yok edilebilir
  /// (hiç durak geçilmeyen kısa bir oyun). Tembel alan o durumda ilk kez
  /// `dispose` içinde oluşturulmaya çalışılıyor ve Flutter, yok edilmekte
  /// olan bir ağaçta ticker kurmaya izin vermiyor.
  late AnimationController _animation;

  Timer? _hideTimer;
  int _seenPulse = 0;

  /// Gösterilen durak; sayaç arttığı anda çözülür.
  ///
  /// Şerit görünürken tren ilerlemeye devam ediyor, yani "şu anki durak"
  /// değişebilir. Ad o an dondurulmazsa şeridin ortasında değişirdi.
  String? _stationName;
  int _bonus = 0;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _seenPulse = widget.run.stationPulse;
  }

  @override
  void didUpdateWidget(StationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pulse = widget.run.stationPulse;
    if (pulse == _seenPulse) {
      // Yeniden başlatma sayacı sıfırlar.
      if (pulse < _seenPulse) _seenPulse = pulse;
      return;
    }
    _seenPulse = pulse;
    _show();
  }

  void _show() {
    final reached = stationProgressFor(
      journey: widget.run.journey,
      lineStations: widget.lineStations,
      progress: widget.run.progress,
    )?.departed;
    if (reached == null) return;

    setState(() {
      _stationName = reached.name;
      // Bonus aynı karede veriliyor; sayaç arttıysa bonus da bu durağındır.
      _bonus = widget.run.stationBonusPulse > 0
          ? widget.run.lastStationBonus
          : 0;
    });

    _hideTimer?.cancel();
    _animation.forward();
    _hideTimer = Timer(StationBanner.visibleFor, () {
      if (mounted) _animation.reverse();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _stationName;
    if (name == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        if (t == 0) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 8),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: widget.accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          border: Border.all(color: widget.accent.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.trip_origin_rounded, size: 15, color: widget.accent),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                _bonus > 0 ? '$name · +$_bonus' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.captionStrong.copyWith(color: widget.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
