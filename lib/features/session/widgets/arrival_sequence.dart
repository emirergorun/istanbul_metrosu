import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/metro_train.dart';

/// Varış sahnesi: oyunun gerçek finali.
///
/// Sıra:
/// 1. Ekran kararır, oyun kilitlenir.
/// 2. Tren sağdan girer ve frenleyerek durur. **Kapı trenin üstündedir**,
///    onunla birlikte gelir.
/// 3. Tren durur, kısa bir bekleme olur.
/// 4. Peron tabelası belirir.
/// 5. Kapılar yanlara açılır, içerisi görünür.
/// 6. Sonuç kartı kapı aralığından büyüyerek çıkar.
///
/// Kapı bir ara ekranın ortasında sabit duruyordu ve yalnızca saydamlığı
/// trenle birlikte artıyordu: tren daha yolun yarısındayken kapı havada
/// belirmiş oluyordu. Artık kapı da trenin taşıdığı öteleme ile hareket
/// ediyor — önce metro gelir, sonra kapı açılır.
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
    this.onSkipped,
  });

  final Color accent;
  final String lineId;
  final String stationName;

  /// Kapılar açılınca ortaya çıkan içerik (sonuç kartı).
  final Widget child;

  /// Sahnenin toplam süresi. Yavaşlatılmış hâli görsel kontrol için kullanılır.
  final Duration duration;

  /// Oyuncu sahneyi atladığında çağrılır.
  ///
  /// Tören sesi sahneden uzun (4 sn); atlandığında kesilmezse sonuç
  /// panelini okurken arka planda tren sesi kalıyor.
  final VoidCallback? onSkipped;

  /// Kapı katmanının test anahtarı.
  ///
  /// Kapının trenle birlikte hareket ettiğini doğrulamak için gerekli;
  /// ikisi ayrılırsa sahne yine "kapı havada belirdi" hâline döner.
  static const Key doorsKey = Key('arrival-doors');

  /// Trenin test anahtarı.
  static const Key trainKey = Key('arrival-train');

  /// Kapı kanatlarının test anahtarları; açılma aralığı bunlardan ölçülür.
  static const Key leftDoorKey = Key('arrival-door-left');
  static const Key rightDoorKey = Key('arrival-door-right');

  /// Yolculuğun tek doruk noktası; acele ettirilmemeli.
  ///
  /// 1600 ms'de tren "gelmek" yerine kayıp geçiyordu ve sonuç kartı bir anda
  /// bitmiş oluyordu. Trenin frenlemesi ve kartın açılması artık gözle takip
  /// edilebilecek kadar uzun. Sıkılan oyuncu ekrana dokunup atlayabilir.
  ///
  /// **Süre `arrival.wav`'e göre seçildi.** Ses 4,03 saniye ve enerjisi
  /// düz değil: 0,0–0,5 sn sessize yakın (tren uzakta), 0,5–1,6 yükseliyor
  /// (yaklaşıyor), 1,6–2,3 en yüksek (varış ve kapı), 3,0'dan sonra
  /// sönüyor. Sahne bu eğriye oturtuldu — tren ses yükselişini bitirdiği
  /// anda duruyor, kapı sesin en gür olduğu aralıkta açılıyor, sonuç kartı
  /// ses sönerken tamamlanıyor.
  static const Duration defaultDuration = Duration(milliseconds: 3200);

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
  // Dilimler `arrival.wav`'in enerji eğrisiyle hizalı (3200 ms üzerinden):
  //
  //   tren   0,00 - 1,60 sn   sesin yaklaşma yükselişi de 1,6'da bitiyor
  //   bekle  1,60 - 1,79 sn   tren durdu, kapı henüz açılmadı
  //   tabela 1,66 - 2,05 sn
  //   kapı   1,79 - 2,50 sn   sesin en gür aralığı 1,6 - 2,3
  //   kart   2,18 - 3,20 sn   ses 3,0'dan sonra sönüyor
  //
  // Tren dilimi `easeOutCubic` ile uzun bir fren eğrisi çiziyor; "gelip
  // duruyor" hissi buradan geliyor. Sonuç kartı da geniş bir dilime
  // yayıldı, aniden belirmiyor.
  late final Animation<double> _scrim = _curve(0.0, 0.09, Curves.easeOut);
  late final Animation<double> _train = _curve(0.0, 0.50, Curves.easeOutCubic);
  late final Animation<double> _sign = _curve(0.52, 0.64, Curves.easeOut);

  /// Kapılar **tren durduktan sonra** açılmaya başlar.
  ///
  /// Aralığın başı [_train] bittikten sonra: kapının açılması varışın
  /// sonucu, eşlikçisi değil.
  late final Animation<double> _doors = _curve(
    0.56,
    0.78,
    Curves.easeInOutCubic,
  );
  late final Animation<double> _content = _curve(
    0.68,
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
    widget.onSkipped?.call();
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
            // Tren ve kapı **aynı** ötelemeyi taşır: kapı trenin üstünde,
            // ayrı bir katman değil.
            final arrivalShift = Offset(
              (1 - _train.value) * (size.width + trainWidth / 2),
              0,
            );

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
                    offset: arrivalShift,
                    child: MetroTrain(
                      key: ArrivalSequence.trainKey,
                      color: widget.accent,
                      height: bandHeight,
                      wagons: _wagons,
                      wagonAspect: _wagonAspect,
                    ),
                  ),
                ),

                // Kapı bölgesi: trenle birlikte gelir, tren durunca açılır.
                Positioned(
                  top: bandTop,
                  left: 0,
                  right: 0,
                  height: bandHeight,
                  child: Transform.translate(
                    offset: arrivalShift,
                    child: _Doors(
                      key: ArrivalSequence.doorsKey,
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
    super.key,
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
                    key: isLeft
                        ? ArrivalSequence.leftDoorKey
                        : ArrivalSequence.rightDoorKey,
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
    super.key,
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
                style: AppText.title,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
