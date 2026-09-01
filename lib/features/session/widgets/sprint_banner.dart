import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Son durak sprinti başladığında bir kez geçen bildirim — **ortak**.
///
/// Sprint sessizce başlarsa oyuncu skorunun neden hızlandığını anlamıyor.
/// Bu şerit bir kez iner, kısa süre durur ve kalkar; oyunu durdurmaz.
/// Sprint sürdüğü sürece üstteki `SprintChip` görünmeye devam eder.
class SprintBanner extends StatefulWidget {
  const SprintBanner({super.key, required this.pulse});

  /// Her sprint başlangıcında artan sayaç. Değişince şerit gösterilir.
  final int pulse;

  @override
  State<SprintBanner> createState() => _SprintBannerState();
}

class _SprintBannerState extends State<SprintBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  Timer? _hideTimer;
  int _seenPulse = 0;

  @override
  void initState() {
    super.initState();
    _seenPulse = widget.pulse;
  }

  @override
  void didUpdateWidget(SprintBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse == _seenPulse) return;
    _seenPulse = widget.pulse;
    _show();
  }

  void _show() {
    _hideTimer?.cancel();
    _animation.forward();
    _hideTimer = Timer(const Duration(milliseconds: 2200), () {
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
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final t = _animation.value;
          if (t == 0) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * -28),
                  // Girerken hafifçe büyür: "bir şey oldu" hissi.
                  child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
                ),
              ),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.md),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.warning,
            borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.flag_rounded, size: 18, color: AppColors.background),
              SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'SON DURAK BONUSU ×2',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppColors.background,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
