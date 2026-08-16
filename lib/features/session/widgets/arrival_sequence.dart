import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/metro_train.dart';

/// Varış sahnesi: oyunun gerçek finali.
///
/// Sıra:
/// 1. Ekran kararır, oyun kilitlenir.
/// 2. Tren sağdan girer ve frenleyerek durur.
/// 3. Peron tabelası belirir.
/// 4. Kapılar yanlara açılır, içerisi görünür.
/// 5. Sonuç kartı kapı aralığından büyüyerek çıkar.
///
/// Her yere dokunulunca atlanır — yirminci yolculukta kimse animasyon
/// izlemek istemez.
class ArrivalSequence extends StatefulWidget {
  const ArrivalSequence({
    super.key,
    required this.accent,
    required this.lineId,
    required this.stationName,
    required this.child,
    this.duration = defaultDuration,
  });

  final Color accent;
  final String lineId;
  final String stationName;

  /// Kapılar açılınca ortaya çıkan içerik (sonuç kartı).
  final Widget child;

  /// Sahnenin toplam süresi. Yavaşlatılmış hâli görsel kontrol için kullanılır.
  final Duration duration;

  /// Yolculuğun tek doruk noktası; acele ettirilmemeli.
  ///
  /// 1600 ms'de tren "gelmek" yerine kayıp geçiyordu ve sonuç kartı bir anda
  /// bitmiş oluyordu. Trenin frenlemesi ve kartın açılması artık gözle takip
  /// edilebilecek kadar uzun. Sıkılan oyuncu ekrana dokunup atlayabilir.
  static const Duration defaultDuration = Duration(milliseconds: 2800);

  @override
  State<ArrivalSequence> createState() => _ArrivalSequenceState();
}

class _ArrivalSequenceState extends State<ArrivalSequence>
    with SingleTickerProviderStateMixin {
  /// Tek vagon ekranın yarısından geniş olmamalı; yoksa tren okunmuyor.
  static const int _wagons = 3;
  static const double _wagonAspect = 1.3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    // Erişilebilirlik: "hareketi azalt" açıksa sahne oynatılmaz, sonuç
    // doğrudan gösterilir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  // Zaman çizelgesi (0..1 aralığında dilimler).
  //
  // Tren dilimi toplamın yarısından uzun: `easeOutCubic` ile uzun bir fren
  // eğrisi çiziyor, "gelip duruyor" hissi buradan geliyor. Sonuç kartı da
  // sona doğru geniş bir dilime yayıldı; aniden belirmiyor.
  late final Animation<double> _scrim = _curve(0.0, 0.10, Curves.easeOut);
  late final Animation<double> _train = _curve(0.0, 0.58, Curves.easeOutCubic);
  late final Animation<double> _sign = _curve(0.56, 0.70, Curves.easeOut);
  late final Animation<double> _doors = _curve(
    0.66,
    0.88,
    Curves.easeInOutCubic,
  );
  late final Animation<double> _content = _curve(
    0.74,
    1.0,
    Curves.easeOutCubic,
  );

  Animation<double> _curve(double begin, double end, Curve curve) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: curve),
    );
  }

  bool get _isPlaying => _controller.status != AnimationStatus.completed;

  void _skip() {
    if (!_isPlaying) return;
    _controller.animateTo(
      1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;

        // Vagon yüksekliği bilinçli olarak küçük: ekranda 2-3 vagon
        // görünmezse şekil tren gibi değil, renkli blok gibi okunuyor.
        final bandHeight = (size.height * 0.15).clamp(100.0, 140.0);
        final wagonWidth = bandHeight * _wagonAspect;
        final trainWidth = MetroTrain.widthFor(
          height: bandHeight,
          wagons: _wagons,
          wagonAspect: _wagonAspect,
        );
        // Kapı, ekranın ortasındaki vagonun içinde kalmalı.
        final doorWidth = wagonWidth * 0.6;
        final bandTop = size.height * 0.28;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.78 * _scrim.value),
                ),

                // Tren: ekrandan geniş, ortadaki vagon ekranın merkezinde.
                Positioned(
                  top: bandTop,
                  left: (size.width - trainWidth) / 2,
                  child: Transform.translate(
                    offset: Offset(
                      (1 - _train.value) * (size.width + trainWidth / 2),
                      0,
                    ),
                    child: MetroTrain(
                      color: widget.accent,
                      height: bandHeight,
                      wagons: _wagons,
                      wagonAspect: _wagonAspect,
                    ),
                  ),
                ),

                // Kapı bölgesi: önce kapalı, sonra yanlara açılır.
                Positioned(
                  top: bandTop,
                  left: 0,
                  right: 0,
                  height: bandHeight,
                  child: Opacity(
                    opacity: _train.value,
                    child: _Doors(
                      accent: widget.accent,
                      width: doorWidth,
                      height: bandHeight,
                      open: _doors.value,
                    ),
                  ),
                ),

                // Peron tabelası.
                Positioned(
                  top: bandTop - 62,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: _sign.value * (1 - _content.value),
                    child: Transform.translate(
                      offset: Offset(0, (1 - _sign.value) * 10),
                      child: _PlatformSign(
                        lineId: widget.lineId,
                        stationName: widget.stationName,
                        accent: widget.accent,
                      ),
                    ),
                  ),
                ),

                // Sonuç kartı: kapı aralığından büyüyerek çıkar.
                if (_content.value > 0)
                  Opacity(
                    opacity: _content.value.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.72 + 0.28 * _content.value,
                      child: widget.child,
                    ),
                  ),

                // Atlamak için herhangi bir yere dokun.
                if (_isPlaying)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _skip,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Trenin ortasındaki çift kanatlı kapı.
class _Doors extends StatelessWidget {
  const _Doors({
    required this.accent,
    required this.width,
    required this.height,
    required this.open,
  });

  final Color accent;
  final double width;
  final double height;

  /// 0 = kapalı, 1 = tamamen açık.
  final double open;

  @override
  Widget build(BuildContext context) {
    final doorHeight = height * 0.74;
    final half = width / 2;
    final travel = half * open;

    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: <Widget>[
            // Kapı aralığından görünen karanlık iç.
            Container(
              width: width,
              height: doorHeight,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            for (final isLeft in const <bool>[true, false])
              Transform.translate(
                offset: Offset(isLeft ? -travel : travel, 0),
                child: Align(
                  alignment: isLeft
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: _DoorPanel(
                    accent: accent,
                    width: half,
                    height: doorHeight,
                    isLeft: isLeft,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DoorPanel extends StatelessWidget {
  const _DoorPanel({
    required this.accent,
    required this.width,
    required this.height,
    required this.isLeft,
  });

  final Color accent;
  final double width;
  final double height;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isLeft ? 6 : 0),
          right: Radius.circular(isLeft ? 0 : 6),
        ),
        border: Border(
          // İç kenarda lastik conta: kapıların ayrıldığı yer belli olsun.
          left: isLeft
              ? BorderSide.none
              : BorderSide(
                  color: Colors.black.withValues(alpha: 0.35),
                  width: 2,
                ),
          right: isLeft
              ? BorderSide(
                  color: Colors.black.withValues(alpha: 0.35),
                  width: 2,
                )
              : BorderSide.none,
        ),
      ),
      child: Column(
        children: <Widget>[
          SizedBox(height: height * 0.12),
          Container(
            width: width * 0.62,
            height: height * 0.34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Perondaki istasyon levhası.
class _PlatformSign extends StatelessWidget {
  const _PlatformSign({
    required this.lineId,
    required this.stationName,
    required this.accent,
  });

  final String lineId;
  final String stationName;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandNavyDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            LineBadge(label: lineId, color: accent, compact: true),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                stationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
