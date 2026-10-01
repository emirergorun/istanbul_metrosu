import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../application/lane_runner_controller.dart';
import '../domain/lane_runner_state.dart';

/// Ray Değiştir sahnesi: oyuncunun treninin arkasından bakan 3B kamera.
///
/// Subway Surfers / Temple Run havası: parlak, düz gölgeli renkler; hafifçe
/// kıvrılıp inip çıkan yol; tünelden çıkıp gün batımında İstanbul silüeti
/// altında açık hendekte koşan bölümler; karşıdan farları yanan trenler ve
/// hızla artan hız çizgileri.
///
/// Motor yok; Makinist'teki gibi elle yansıtılan sahte-3B. Dünya: z ileri,
/// x sağa, y yukarı (m). Kesit (tünel ya da hendek) z boyunca dilimlenip
/// uzaktan yakına boyanır; nesneler (lambalar, ağaçlar, trenler) kendi
/// derinliklerinde araya girer.
///
/// Oyun mantığı değişmedi: engel koordinatı `y` (−0.12 doğar, 0.78 oyuncu,
/// 1.14 silinir) [unit] metreyle dünyaya taşınır. Çarpışma penceresi
/// ±0.07 olduğu için karşı trenin boyu 2 × 0.07 × [unit].
class LaneRunnerScenePainter extends CustomPainter {
  LaneRunnerScenePainter({
    required this.controller,
    required this.colorForLevel,
    Listenable? frame,
  }) : super(repaint: frame ?? controller);

  final LaneRunnerController controller;

  /// Oyuncunun hat seviyesine göre tren rengi (ekranla aynı palet).
  final Color Function(int level) colorForLevel;

  /// Engel koordinatının bir biriminin metre karşılığı.
  static const double unit = 110;

  /// Controller'daki çarpışma penceresi (|y − trenY| < 0.07).
  static const double _hitWindow = 0.07;
  static const double _obstacleHalf = _hitWindow * unit;

  static const double laneSpacing = 4.0;
  static const double _carLength = 14.5;
  static const double _carGap = 1.0;
  static const double _trainLength = 2 * _carLength + _carGap;

  /// Kamera: trenin arkasından ve üstünden, ~17° aşağı bakar. Oyuncunun
  /// treni yolu kapatmasın, karşıdan gelen trenler üstünden görünsün.
  static const double _pitch = 0.3;
  static const double _camHeight = 8.6;
  static const double _camBack = 11.0;

  /// Kaçış noktasının ekrandaki yüksekliği (oran). Bakış aşağı eğildikçe
  /// ufuk yukarı kayar; merkez biraz aşağı alınır ki gökyüzü kalsın.
  static const double _centerY = 0.5;

  /// Trenlerin ölçeği: gerçek metro boyutunun %78'i. Tam boyda oyuncunun
  /// treni üç rayın ortasını kapatıyordu.
  static const double _k = 0.78;

  static const double _near = 0.8;
  static const double _far = 240;

  /// Bölge döngüsü (1240 m): tünel → çimenlik vadi → tünel → Haliç
  /// köprüsü → hendek → (başa). Tünel ağızları her açık bölgeyi ayırır.
  static const double _period = 1240;
  static const List<(double, _Zone)> _layout = <(double, _Zone)>[
    (0, _Zone.tunnel),
    (280, _Zone.meadow),
    (580, _Zone.tunnel),
    (780, _Zone.bridge),
    (1080, _Zone.cut),
  ];

  /// Köprü kuleleri (döngü içindeki konum).
  static const List<double> _pylons = <double>[860, 1000];

  // ------------------------------------------------------------ palet

  static const Color _skyTop = Color(0xFF3A2C7A);
  static const Color _skyMid = Color(0xFFE8638A);
  static const Color _skyLow = Color(0xFFFFC27A);
  static const Color _haze = Color(0xFFF6C9A3);
  static const Color _tunnelFog = Color(0xFF1C1512);

  static const Color _grass = Color(0xFF6CC24A);
  static const Color _meadowGrass = Color(0xFF7BCB4F);
  static const Color _water = Color(0xFF2F86B0);
  static const Color _seaHorizon = Color(0xFFAAD6E4);
  static const Color _waterNear = Color(0xFF4FB0D6);
  static const Color _deck = Color(0xFF9EA4AA);
  static const Color _openWall = Color(0xFFE9A55B);
  static const Color _openFloor = Color(0xFF8C7F70);
  static const Color _tunnelWall = Color(0xFFF1E4C3);
  static const Color _tunnelVault = Color(0xFFD9C9A8);
  static const Color _tunnelFloor = Color(0xFF6E6A66);

  static const List<Color> _graffiti = <Color>[
    Color(0xFFFF5A5F),
    Color(0xFFFFC93C),
    Color(0xFF3DDC97),
    Color(0xFF4D9DE0),
    Color(0xFFB66DFF),
  ];

  static const List<Color> _oncoming = <Color>[
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF00897B),
  ];

  // ---------------------------------------------------------- kesitler

  static final List<_Seg> _tunnel = _buildTunnel();

  /// Çimenlik vadi: hat hafif bir set üstünde, iki yanı uçsuz bucaksız çimen.
  static final List<_Seg> _meadow = <_Seg>[
    const _Seg(Offset(-120, -0.6), Offset(-9, -0.6), _K.meadow),
    const _Seg(Offset(-9, -0.6), Offset(-8, 0), _K.meadow),
    const _Seg(Offset(-8, 0), Offset(8, 0), _K.floor),
    const _Seg(Offset(8, 0), Offset(9, -0.6), _K.meadow),
    const _Seg(Offset(9, -0.6), Offset(120, -0.6), _K.meadow),
  ];

  /// Köprü: önce deniz, sonra tabliye. Tabliyenin yan yüzleri kameradan
  /// görünmez (kamera hep tabliyenin içinde), çizilmez.
  static final List<_Seg> _bridge = <_Seg>[
    const _Seg(Offset(-400, -16), Offset(400, -16), _K.water),
    const _Seg(Offset(-6.8, 0), Offset(6.8, 0), _K.deck),
  ];
  static final List<_Seg> _open = <_Seg>[
    const _Seg(Offset(-40, 3.2), Offset(-8.6, 3.2), _K.grass),
    const _Seg(Offset(-8.6, 3.2), Offset(-8, 0), _K.wall),
    const _Seg(Offset(-8, 0), Offset(8, 0), _K.floor),
    const _Seg(Offset(8, 0), Offset(8.6, 3.2), _K.wall),
    const _Seg(Offset(8.6, 3.2), Offset(40, 3.2), _K.grass),
  ];

  static List<_Seg> _buildTunnel() {
    final segs = <_Seg>[
      const _Seg(Offset(-8, 0), Offset(8, 0), _K.floor),
      const _Seg(Offset(8, 0), Offset(8, 6.0), _K.wall),
    ];
    var prev = const Offset(8, 6.0);
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      final a = math.pi * i / steps;
      final p = Offset(8 * math.cos(a), 6.0 + 5.0 * math.sin(a));
      segs.add(_Seg(prev, p, _K.vault));
      prev = p;
    }
    segs.add(const _Seg(Offset(-8, 6.0), Offset(-8, 0), _K.wall));
    return segs;
  }

  static final List<Offset> _tunnelOutline = <Offset>[
    for (final s in _tunnel) s.a,
  ];

  // ------------------------------------------------------------ durum

  late _Cam _cam;

  /// Ön ucun yanal konum geçmişi: (z, x) çiftleri, eskiden yeniye.
  ///
  /// Şerit değiştirirken vagonlar tek parça kaymaz; gövde ön ucun izini
  /// takip eder (bkz. [_followRatio]).
  final List<double> _trailZ = <double>[];
  final List<double> _trailX = <double>[];

  void _recordTrail(double z, double x) {
    // Yeniden başlatmada konum geri gider: geçmiş geçersiz.
    if (_trailZ.isNotEmpty && z < _trailZ.last - 1) {
      _trailZ.clear();
      _trailX.clear();
    }
    if (_trailZ.isEmpty || z - _trailZ.last > 0.25) {
      _trailZ.add(z);
      _trailX.add(x);
    } else {
      // Aynı karede tekrar boyanırsa son örneği tazele.
      _trailX[_trailX.length - 1] = x;
    }
    final keepFrom = z - _trainLength - 6;
    var drop = 0;
    while (drop < _trailZ.length - 2 && _trailZ[drop + 1] < keepFrom) {
      drop++;
    }
    if (drop > 0) {
      _trailZ.removeRange(0, drop);
      _trailX.removeRange(0, drop);
    }
  }

  /// Gövde ön ucun izini kısaltılmış mesafeyle izler: trenin arka ucu
  /// (30 m geride) ön ucun yalnız 6 m önceki konumunu alır. Birebir
  /// mesafe kullanılınca arka vagon şerit değişiminden sonra yarım
  /// saniye komşu rayda çapraz kalıyordu; böyle hafif bir yılan
  /// kıvrımıyla geçip hemen yeni rayına oturuyor.
  static const double _followRatio = 0.2;

  /// Gövdenin [z] noktasının yanal konumu.
  double _bodyX(double z, double current) =>
      _trailAt(_zp - (_zp - z) * _followRatio, current);

  /// Ön ucun [z] noktasından geçerken bulunduğu yanal konum.
  double _trailAt(double z, double current) {
    if (_trailZ.isEmpty || z >= _trailZ.last) return current;
    if (z <= _trailZ.first) return _trailX.first;
    var lo = 0;
    var hi = _trailZ.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_trailZ[mid] <= z) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t = (z - _trailZ[lo]) / (_trailZ[hi] - _trailZ[lo]);
    return _trailX[lo] + (_trailX[hi] - _trailX[lo]) * t;
  }

  double _zp = 0;
  double _speedN = 0;
  double _t = 0;

  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _vertPaint = Paint();
  final Path _path = Path();

  // Dilim köşeleri (tek drawVertices çağrısı için).
  final List<Offset> _pos = <Offset>[];
  final List<Color> _col = <Color>[];

  /// Yolun yanal kıvrımı (m): iki dalga üst üste, Temple Run kıvrımı.
  static double _curve(double z) =>
      9 * math.sin(z / 260) + 3.5 * math.sin(z / 97 + 1.3);

  /// Yolun inişi çıkışı (m).
  static double _hill(double z) =>
      2.2 * math.sin(z / 330 + 0.7) + 0.8 * math.sin(z / 121);

  static double _cycle(double z) => ((z % _period) + _period) % _period;

  static _Zone _zoneAt(double z) {
    final m = _cycle(z);
    for (var i = _layout.length - 1; i >= 0; i--) {
      if (m >= _layout[i].$1) return _layout[i].$2;
    }
    return _layout.first.$2;
  }

  static bool _isTunnel(double z) => _zoneAt(z) == _Zone.tunnel;

  /// Bölgenin döngüdeki başlangıç ve bitişi.
  static (double, double) _zoneSpan(double m) {
    for (var i = _layout.length - 1; i >= 0; i--) {
      if (m >= _layout[i].$1) {
        final end = i + 1 < _layout.length ? _layout[i + 1].$1 : _period;
        return (_layout[i].$1, end);
      }
    }
    return (0, _layout[1].$1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final adv = _warmTravel == null ? controller.renderAdvance : 0.0;
    final travel = _warmTravel ?? controller.travel + adv;
    _zp = travel * unit;
    _speedN = (math.min(controller.passes, 35) / 35).toDouble();
    _t = _zp / 30;

    final lane = controller.trainLaneVisual;
    final px = (lane - 1) * laneSpacing;
    _recordTrail(_zp, px);
    final camZ = _zp - _trainLength - _camBack;
    final look = camZ + 45;
    final base = _curve(camZ);
    final slope = (_curve(look) - base) / 45;
    final hBase = _hill(camZ);
    final hSlope = (_hill(look) - hBase) / 45;
    // Koşu sallantısı: hızla birlikte.
    final bob = math.sin(_t * 2.1) * 0.05 * (0.3 + _speedN);
    final f =
        math.min(size.width * 0.95, size.height * 0.62) * (1 - 0.08 * _speedN);
    _cam = _Cam(
      z: camZ,
      // Kamera trenin iki ucunun ortasını izler: şerit değişiminde ön
      // vagon geçince görüntü birden kaymaz.
      x: (px + _bodyX(_zp - _trainLength, px)) / 2 * 0.8,
      y: _camHeight + bob,
      base: base,
      slope: slope,
      hBase: hBase,
      hSlope: hSlope,
      cosP: math.cos(_pitch),
      sinP: math.sin(_pitch),
      f: f,
      cx: size.width / 2,
      cy: size.height * _centerY,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Virajda kamera hafifçe yatar.
    final curvature =
        (_curve(_zp + 20) - 2 * _curve(_zp) + _curve(_zp - 20)) / 400;
    canvas.translate(size.width / 2, size.height * _centerY);
    canvas.rotate((-curvature * 18).clamp(-0.06, 0.06));
    canvas.translate(-size.width / 2, -size.height * _centerY);

    _drawBackdrop(canvas, size);

    final start = camZ + _near;
    final end = camZ + _far;
    if (_isTunnel(end)) _drawFarCap(canvas, end);

    final objects = _collectObjects(start, end)
      ..sort((a, b) => b.z.compareTo(a.z));
    final rear = _zp - _trainLength;
    var next = 0;
    var trainDrawn = false;
    final cuts = _cuts(start, end, rear);
    for (var i = cuts.length - 1; i > 0; i--) {
      final za = cuts[i - 1];
      final zb = cuts[i];
      if (!trainDrawn && zb <= rear + 1e-6) {
        _drawPlayer(canvas, lane, px);
        trainDrawn = true;
      }
      while (next < objects.length && objects[next].z >= zb) {
        objects[next++].draw(canvas);
      }
      _drawPortal(canvas, zb);
      _drawSlice(canvas, za, zb);
      while (next < objects.length && objects[next].z >= za) {
        objects[next++].draw(canvas);
      }
    }
    if (!trainDrawn) _drawPlayer(canvas, lane, px);
    canvas.restore();

    _drawSpeedLines(canvas, size);
    _drawVignette(canvas, size);
  }

  // ------------------------------------------------------- arka plan

  /// Gökyüzü, güneş, bulutlar ve İstanbul silüeti. Tünelde kesit hepsini
  /// örter; yalnız tünel ağzından görünür.
  void _drawBackdrop(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = _cam.cy - _cam.f * math.tan(_pitch);
    final rect = Rect.fromLTRB(-w * 0.2, -h * 0.2, w * 1.2, h * 1.2);
    _fill.shader = ui.Gradient.linear(
      Offset(0, horizon - h * 0.55),
      Offset(0, horizon),
      <Color>[_skyTop, _skyMid, _skyLow],
      <double>[0, 0.6, 1],
    );
    canvas.drawRect(rect, _fill);
    _fill.shader = null;

    // Parallaks: kameranın yanal kaymasıyla silüet ağır ağır kayar.
    final shift = -(_cam.base + _cam.x) * 3.0;

    // Güneş.
    final sun = Offset(w * 0.68 + shift * 0.2, horizon - h * 0.08);
    _fill.shader = ui.Gradient.radial(sun, w * 0.45, <Color>[
      const Color(0x88FFE6A0),
      const Color(0x00FFE6A0),
    ]);
    canvas.drawCircle(sun, w * 0.45, _fill);
    _fill.shader = null;
    _fill.color = const Color(0xFFFFE7A6);
    canvas.drawCircle(sun, w * 0.11, _fill);

    // Bulutlar.
    _fill.color = const Color(0x66FFF1E6);
    for (var i = 0; i < 4; i++) {
      final cx =
          ((i * 0.31 + 0.1) * w * 1.4 + shift * 0.4 - _t * 0.6) % (w * 1.4) -
          w * 0.2;
      final cy = horizon - h * (0.2 + 0.08 * (i % 2));
      for (final (dx, r) in <(double, double)>[(0, 22), (24, 16), (-22, 14)]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx + dx, cy),
            width: r * 3.2,
            height: r * 1.4,
          ),
          _fill,
        );
      }
    }

    // Martılar: gökyüzünde süzülen küçük "v"ler.
    _stroke
      ..color = const Color(0xCCFFFFFF)
      ..strokeWidth = 1.6;
    for (var i = 0; i < 5; i++) {
      final gx =
          ((_hash(i + 300) * w * 1.6 + _t * (6 + i * 2) + shift * 0.3) %
              (w * 1.6)) -
          w * 0.3;
      final gy =
          horizon -
          h * (0.12 + _hash(i + 310) * 0.18) +
          math.sin(_t * 0.8 + i) * 6;
      final flap = 3 + 2 * math.sin(_t * 3 + i * 2);
      final s = 6 + _hash(i + 320) * 5;
      _path
        ..reset()
        ..moveTo(gx - s, gy - flap)
        ..quadraticBezierTo(gx - s * 0.4, gy - flap * 0.2, gx, gy)
        ..quadraticBezierTo(gx + s * 0.4, gy - flap * 0.2, gx + s, gy - flap);
      canvas.drawPath(_path, _stroke);
    }

    // Köprüye yaklaştıkça ufkun altı denize döner.
    final sea = _seaness();

    // Uzakta Boğaz'ın asma köprüsü (yalnız denizde).
    if (sea > 0.01) {
      _bosphorusBridge(canvas, w, horizon, shift * 0.35, sea);
    }

    // Silüet: arkada soluk katman, önde koyu katman.
    _skyline(canvas, w, horizon, shift * 0.55, const Color(0xFFB98AA6), 0.7, 3);
    _skyline(canvas, w, horizon, shift, const Color(0xFF5B3B6E), 1.0, 0);

    // Ufkun altı: puslu yeşil vadi ya da deniz.
    final below = Rect.fromLTRB(-w * 0.2, horizon, w * 1.2, h * 1.2);
    _fill.shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, h), <Color>[
      const Color(0xFFB9C98A),
      const Color(0xFF6CB24A),
    ]);
    canvas.drawRect(below, _fill);
    _fill.shader = null;
    if (sea > 0.01) {
      _fill.shader = ui.Gradient.linear(
        Offset(0, horizon),
        Offset(0, h),
        <Color>[
          Color.fromRGBO(170, 214, 228, sea),
          Color.fromRGBO(47, 134, 176, sea),
        ],
      );
      canvas.drawRect(below, _fill);
      _fill.shader = null;
      // Güneşin denizdeki yansıması: titreşen yatay çizgiler.
      for (var k = 0; k < 9; k++) {
        final y = horizon + 3 + k * k * 1.6;
        final half =
            w *
            (0.05 + 0.012 * k) *
            (0.6 + 0.4 * math.sin(_t * 1.3 + k * 1.9).abs());
        _stroke
          ..color = Color.fromRGBO(255, 231, 166, 0.55 * sea)
          ..strokeWidth = 1.5 + k * 0.2;
        canvas.drawLine(
          Offset(sun.dx - half, y),
          Offset(sun.dx + half, y),
          _stroke,
        );
      }
      _maidensTower(canvas, w, horizon, shift * 1.2, sea);
    }
  }

  /// Görünen yolun ne kadarı köprü (0–1): ufuk yavaş yavaş denize döner.
  double _seaness() {
    var n = 0;
    const samples = 24;
    for (var i = 0; i < samples; i++) {
      final z = _cam.z + 40 + i * 9.0;
      if (_zoneAt(z) == _Zone.bridge) n++;
    }
    return n / samples;
  }

  /// Kubbeler ve minarelerle İstanbul silüeti. Sırayla: Sultanahmet esinli
  /// altı minareli cami, ev sırası, Galata Kulesi, Süleymaniye esinli dört
  /// minareli cami, küçük cami. [seed] katmanı kaydırır.
  void _skyline(
    Canvas canvas,
    double w,
    double horizon,
    double shift,
    Color color,
    double scale,
    int seed,
  ) {
    _fill.color = color;
    final band = w * 1.9;
    final s = w * 0.16 * scale;
    // Ev sıraları: kesintisiz alçak taban.
    final houses = Path()..moveTo(-w, horizon + 2);
    final startX = -w + ((shift % (w * 0.08)) - w * 0.08);
    var x = startX;
    var k = seed * 31;
    while (x < w * 2) {
      final hh = s * (0.16 + 0.14 * _hash(k++));
      final ww = w * (0.03 + 0.03 * _hash(k++));
      houses
        ..lineTo(x, horizon - hh)
        ..lineTo(x + ww, horizon - hh);
      x += ww;
    }
    houses
      ..lineTo(w * 2, horizon + 2)
      ..close();
    canvas.drawPath(houses, _fill);

    final first = ((-w * 0.6 - shift) / band).floor() - 1;
    for (var b = first; b <= first + 3; b++) {
      void at(double fx, void Function(double cx) draw) {
        final cx = shift + (b + (fx + seed * 0.13) % 1.0) * band;
        if (cx > -w * 0.6 && cx < w * 1.6) draw(cx);
      }

      at(0.08, (cx) => _mosque(canvas, cx, horizon, s * 1.1, 6));
      at(0.42, (cx) => _galata(canvas, cx, horizon, s));
      at(0.66, (cx) => _mosque(canvas, cx, horizon, s * 1.25, 4));
      at(0.9, (cx) => _mosque(canvas, cx, horizon, s * 0.6, 2));
    }
  }

  /// Basamaklı kubbeli cami: ana kubbe, yarım kubbeler, [minarets] minare.
  void _mosque(Canvas c, double cx, double base, double s, int minarets) {
    // Gövde.
    c.drawRect(
      Rect.fromLTWH(cx - s * 0.62, base - s * 0.34, s * 1.24, s * 0.34),
      _fill,
    );
    // Yarım kubbeler ve köşe kubbecikleri.
    for (final side in <double>[-1, 1]) {
      c.drawArc(
        Rect.fromCenter(
          center: Offset(cx + side * s * 0.36, base - s * 0.34),
          width: s * 0.5,
          height: s * 0.36,
        ),
        math.pi,
        math.pi,
        true,
        _fill,
      );
      c.drawArc(
        Rect.fromCenter(
          center: Offset(cx + side * s * 0.56, base - s * 0.34),
          width: s * 0.2,
          height: s * 0.16,
        ),
        math.pi,
        math.pi,
        true,
        _fill,
      );
    }
    // Kasnak ve ana kubbe, tepede alem.
    c.drawRect(
      Rect.fromLTWH(cx - s * 0.3, base - s * 0.48, s * 0.6, s * 0.14),
      _fill,
    );
    c.drawArc(
      Rect.fromCenter(
        center: Offset(cx, base - s * 0.48),
        width: s * 0.66,
        height: s * 0.62,
      ),
      math.pi,
      math.pi,
      true,
      _fill,
    );
    c.drawRect(
      Rect.fromLTWH(cx - s * 0.012, base - s * 0.86, s * 0.024, s * 0.08),
      _fill,
    );
    // Minareler: ince gövde, şerefe, sivri külah.
    final xs = <double>[
      if (minarets >= 2) ...<double>[-0.78, 0.78],
      if (minarets >= 4) ...<double>[-1.02, 1.02],
      if (minarets >= 6) ...<double>[-1.2, 1.2],
    ];
    for (var i = 0; i < xs.length; i++) {
      final mx = cx + xs[i] * s;
      final mh = s * (i < 2 ? 1.25 : 1.05);
      final mw = s * 0.045;
      c.drawRect(Rect.fromLTWH(mx - mw / 2, base - mh, mw, mh), _fill);
      c.drawRect(
        Rect.fromLTWH(mx - mw, base - mh * 0.72, mw * 2, mw * 0.5),
        _fill,
      );
      c.drawPath(
        Path()
          ..moveTo(mx - mw * 0.7, base - mh)
          ..lineTo(mx, base - mh - s * 0.16)
          ..lineTo(mx + mw * 0.7, base - mh)
          ..close(),
        _fill,
      );
    }
  }

  /// Galata Kulesi: silindir gövde, seyir balkonu, konik külah.
  void _galata(Canvas c, double cx, double base, double s) {
    final bw = s * 0.26;
    final bh = s * 1.05;
    c.drawRect(Rect.fromLTWH(cx - bw / 2, base - bh, bw, bh), _fill);
    c.drawRect(
      Rect.fromLTWH(cx - bw * 0.62, base - bh - s * 0.03, bw * 1.24, s * 0.05),
      _fill,
    );
    c.drawRect(
      Rect.fromLTWH(cx - bw * 0.45, base - bh - s * 0.14, bw * 0.9, s * 0.12),
      _fill,
    );
    c.drawPath(
      Path()
        ..moveTo(cx - bw * 0.55, base - bh - s * 0.14)
        ..lineTo(cx, base - bh - s * 0.55)
        ..lineTo(cx + bw * 0.55, base - bh - s * 0.14)
        ..close(),
      _fill,
    );
    c.drawRect(
      Rect.fromLTWH(cx - s * 0.008, base - bh - s * 0.64, s * 0.016, s * 0.1),
      _fill,
    );
  }

  /// Uzakta asma köprü: iki kule, sarkan ana kablo, ince tabliye.
  void _bosphorusBridge(
    Canvas c,
    double w,
    double horizon,
    double shift,
    double sea,
  ) {
    final color = Color.fromRGBO(120, 90, 140, 0.75 * sea);
    final x0 = w * 0.02 + shift;
    final x1 = w * 0.98 + shift;
    final t0 = x0 + (x1 - x0) * 0.22;
    final t1 = x0 + (x1 - x0) * 0.78;
    final deckY = horizon - w * 0.035;
    final towerTop = horizon - w * 0.16;
    _stroke
      ..color = color
      ..strokeWidth = 2.2;
    c.drawLine(Offset(x0, deckY), Offset(x1, deckY), _stroke);
    for (final tx in <double>[t0, t1]) {
      c.drawLine(
        Offset(tx, horizon),
        Offset(tx, towerTop),
        _stroke..strokeWidth = 3,
      );
    }
    _stroke.strokeWidth = 1.4;
    c.drawPath(
      Path()
        ..moveTo(x0, deckY)
        ..quadraticBezierTo((x0 + t0) / 2, deckY - w * 0.02, t0, towerTop)
        ..quadraticBezierTo((t0 + t1) / 2, deckY + w * 0.06, t1, towerTop)
        ..quadraticBezierTo((t1 + x1) / 2, deckY - w * 0.02, x1, deckY),
      _stroke,
    );
  }

  /// Kız Kulesi: denizin içinde küçük adacık, beyaz yapı ve kule.
  void _maidensTower(
    Canvas c,
    double w,
    double horizon,
    double shift,
    double sea,
  ) {
    final cx = (w * 0.2 + shift) % (w * 1.4);
    final base = horizon + w * 0.035;
    final s = w * 0.07;
    _fill.color = Color.fromRGBO(110, 98, 90, sea);
    c.drawOval(
      Rect.fromCenter(
        center: Offset(cx, base),
        width: s * 2.4,
        height: s * 0.35,
      ),
      _fill,
    );
    _fill.color = Color.fromRGBO(245, 238, 225, sea);
    c.drawRect(
      Rect.fromLTWH(cx - s * 0.9, base - s * 0.55, s * 1.4, s * 0.5),
      _fill,
    );
    c.drawRect(
      Rect.fromLTWH(cx + s * 0.1, base - s * 1.5, s * 0.36, s * 1.5),
      _fill,
    );
    _fill.color = Color.fromRGBO(120, 130, 140, sea);
    c.drawPath(
      Path()
        ..moveTo(cx + s * 0.04, base - s * 1.5)
        ..lineTo(cx + s * 0.28, base - s * 1.95)
        ..lineTo(cx + s * 0.52, base - s * 1.5)
        ..close(),
      _fill,
    );
    _fill.color = Color.fromRGBO(200, 60, 50, sea);
    c.drawRect(
      Rect.fromLTWH(cx - s * 0.9, base - s * 0.6, s * 1.0, s * 0.07),
      _fill,
    );
  }

  /// Çizim mesafesinin sonu tünelde kalıyorsa ağzı koyu bir kapakla kapat;
  /// yoksa uzak uçtan gökyüzü görünürdü.
  void _drawFarCap(Canvas canvas, double z) {
    final pts = <Offset>[];
    for (final o in _tunnelOutline) {
      final p = _cam.project(o.dx, o.dy, z);
      if (p == null) return;
      pts.add(p);
    }
    _path
      ..reset()
      ..addPolygon(pts, true);
    _fill.color = _tunnelFog;
    canvas.drawPath(_path, _fill);
  }

  // ----------------------------------------------------------- dilimler

  List<double> _cuts(double start, double end, double rear) {
    final cuts = <double>[start, if (rear > start) rear];
    var z = start;
    while (z < end) {
      final dz = z - _cam.z;
      z += math.max(0.5, dz * 0.09);
      cuts.add(math.min(z, end));
    }
    // Bölge sınırları dilim sınırına eklenir: kesit tam orada değişir.
    final k0 = (start / _period).floor();
    for (var k = k0; k <= (end / _period).floor() + 1; k++) {
      for (final (m, _) in _layout) {
        final b = k * _period + m;
        if (b > start && b < end) cuts.add(b);
      }
    }
    cuts.sort();
    return cuts;
  }

  double _fog(double z, bool tunnel) {
    final dz = z - _cam.z;
    return 1 - math.exp(-dz / (tunnel ? 95 : 200));
  }

  /// Tünel lambalarının (10 m'de bir) havuzu.
  double _lamp(double z) {
    final m = ((z % 10) + 10) % 10 - 5;
    return math.exp(-m * m / 6);
  }

  /// Tünel ağzından içeri taşan gün ışığı; tünel dışında 1.
  double _daylight(double z) {
    if (!_isTunnel(z)) return 1;
    final m = _cycle(z);
    final (a, b) = _zoneSpan(m);
    final d = math.min(m - a, b - m);
    return math.exp(-d / 14);
  }

  Color _segColor(_Seg seg, double z, _Zone zone) {
    final tunnel = zone == _Zone.tunnel;
    final Color base;
    var light = 1.0;
    if (tunnel) {
      base = switch (seg.kind) {
        _K.floor => _tunnelFloor,
        _K.wall => _tunnelWall,
        _ => _tunnelVault,
      };
      light = 0.62 + _lamp(z) * 0.22 + _daylight(z) * 0.3;
      if (seg.kind == _K.vault) light *= 0.92;
    } else {
      base = switch (seg.kind) {
        _K.floor => _openFloor,
        _K.wall => _openWall,
        _K.meadow => _meadowGrass,
        _K.water => Color.lerp(
          _waterNear,
          _water,
          ((z - _cam.z) / 120).clamp(0.0, 1.0),
        )!,
        _K.deck => _deck,
        _ => _grass,
      };
      // Güneş solda: sol duvar (sağa bakan) aydınlık, sağ duvar gölgede.
      if (seg.kind == _K.wall) light = seg.a.dx < 0 ? 1.05 : 0.78;
    }
    final lit = _lit(base, light);
    // Deniz uzakta ufuktaki denizin rengine karışır; yoksa çizim
    // mesafesinin bittiği yerde renk kırılıyordu.
    final fogColor = tunnel
        ? _tunnelFog
        : seg.kind == _K.water
        ? _seaHorizon
        : _haze;
    return Color.lerp(lit, fogColor, _fog(z, tunnel))!;
  }

  void _drawSlice(Canvas canvas, double za, double zb) {
    final zm = (za + zb) / 2;
    final zone = _zoneAt(zm);
    final tunnel = zone == _Zone.tunnel;
    final profile = switch (zone) {
      _Zone.tunnel => _tunnel,
      _Zone.meadow => _meadow,
      _Zone.bridge => _bridge,
      _Zone.cut => _open,
    };
    _pos.clear();
    _col.clear();
    for (final seg in profile) {
      final a0 = _cam.project(seg.a.dx, seg.a.dy, za);
      final b0 = _cam.project(seg.b.dx, seg.b.dy, za);
      final b1 = _cam.project(seg.b.dx, seg.b.dy, zb);
      final a1 = _cam.project(seg.a.dx, seg.a.dy, zb);
      if (a0 == null || b0 == null || b1 == null || a1 == null) continue;
      final c0 = _segColor(seg, za, zone);
      final c1 = _segColor(seg, zb, zone);
      _pos.addAll(<Offset>[a0, b0, b1, a0, b1, a1]);
      _col.addAll(<Color>[c0, c0, c1, c0, c1, c1]);
    }
    if (_pos.isNotEmpty) {
      canvas.drawVertices(
        ui.Vertices(ui.VertexMode.triangles, _pos, colors: _col),
        BlendMode.dst,
        _vertPaint,
      );
    }
    final fog = _fog(zm, tunnel);
    final fogColor = tunnel ? _tunnelFog : _haze;
    switch (zone) {
      case _Zone.tunnel:
        // Duvarlarda hat renginde şerit ve koyu süpürgelik; tavanda ışık.
        final band = Color.lerp(
          colorForLevel(controller.lineLevel),
          fogColor,
          fog,
        )!;
        for (final x in <double>[-7.98, 7.98]) {
          _planeX(canvas, x, 1.7, 2.3, za, zb, band);
          _planeX(
            canvas,
            x,
            0,
            0.45,
            za,
            zb,
            Color.lerp(const Color(0xFF4A3F38), fogColor, fog)!,
          );
        }
        _planeY(
          canvas,
          10.92,
          -0.7,
          0.7,
          za,
          zb,
          Color.lerp(const Color(0xFFFFF6D8), fogColor, fog * 0.7)!,
        );
      case _Zone.cut:
        // Duvar tepesinde açık renk harpuşta.
        for (final x in <double>[-8.6, 8.6]) {
          _planeY(
            canvas,
            3.22,
            x - 0.35,
            x + 0.35,
            za,
            zb,
            Color.lerp(const Color(0xFFF7E3C0), fogColor, fog)!,
          );
        }
      case _Zone.bridge:
        _drawBridgeDeckDecor(canvas, za, zb, fog);
      case _Zone.meadow:
        break;
    }
    _drawTracks(canvas, za, zb, tunnel, fog, fogColor);
  }

  /// Köprü tabliyesinin kenar kirişi, korkuluğu ve dikmeleri.
  void _drawBridgeDeckDecor(Canvas canvas, double za, double zb, double fog) {
    Color f(Color c) => Color.lerp(c, _haze, fog)!;
    for (final side in <double>[-1, 1]) {
      final x = side * 6.8;
      // Kenar kirişi: tabliyenin dışına taşan beyaz bordür.
      _planeY(
        canvas,
        0.02,
        x - 0.5,
        x + 0.5,
        za,
        zb,
        f(const Color(0xFFE9ECEF)),
      );
      // Korkuluk: iki yatay boru.
      for (final y in <double>[0.55, 1.15]) {
        final a = _cam.project(x - side * 0.2, y, za);
        final b = _cam.project(x - side * 0.2, y, zb);
        if (a == null || b == null) continue;
        _stroke
          ..color = f(const Color(0xFFD7DCE1))
          ..strokeWidth = math.max(_px(0.08, za), 0.8);
        canvas.drawLine(a, b, _stroke);
      }
      // Dikmeler, 2,5 m'de bir (yakında).
      if (za - _cam.z < 90) {
        for (var k = (za / 2.5).ceil(); k * 2.5 < zb; k++) {
          final z = k * 2.5;
          final a = _cam.project(x - side * 0.2, 0, z);
          final b = _cam.project(x - side * 0.2, 1.2, z);
          if (a == null || b == null) continue;
          _stroke
            ..color = f(const Color(0xFFBFC6CD))
            ..strokeWidth = math.max(_px(0.07, z), 0.8);
          canvas.drawLine(a, b, _stroke);
        }
      }
    }
  }

  void _drawTracks(
    Canvas canvas,
    double za,
    double zb,
    bool tunnel,
    double fog,
    Color fogColor,
  ) {
    final dz = za - _cam.z;
    Color f(Color c) => Color.lerp(c, fogColor, fog)!;
    final light = tunnel ? 0.8 + _lamp(za) * 0.2 : 1.0;
    for (var lane = 0; lane < laneRunnerLaneCount; lane++) {
      final lx = (lane - 1) * laneSpacing;
      // Balast yatağı.
      _planeY(
        canvas,
        0.04,
        lx - 1.75,
        lx + 1.75,
        za,
        zb,
        f(_lit(const Color(0xFF9A8370), light)),
      );
      // Traversler.
      if (dz < 85) {
        final first = (za / 0.75).ceil();
        final last = (zb / 0.75).floor();
        // Hızda traversler göz için kaynaşır: koyu-açık farkı azalır.
        final wood = Color.lerp(
          const Color(0xFF7A4E2E),
          const Color(0xFF8E7462),
          _speedN * 0.6,
        )!;
        _fill.color = f(_lit(wood, light));
        for (var k = first; k <= last; k++) {
          final z = k * 0.75;
          final p0 = _cam.project(lx - 1.3, 0.12, z);
          final p1 = _cam.project(lx + 1.3, 0.12, z);
          final p2 = _cam.project(lx + 1.3, 0.12, z + 0.26);
          final p3 = _cam.project(lx - 1.3, 0.12, z + 0.26);
          if (p0 == null || p1 == null || p2 == null || p3 == null) continue;
          _quad(canvas, p0, p1, p2, p3);
        }
      }
      // Raylar: koyu iç yüz, parlak üst.
      for (final side in <double>[-1, 1]) {
        final x = lx + side * 0.72;
        _planeX(
          canvas,
          x - side * 0.045,
          0.12,
          0.28,
          za,
          zb,
          f(const Color(0xFF5B4A3E)),
        );
        _planeY(
          canvas,
          0.28,
          x - 0.045,
          x + 0.045,
          za,
          zb,
          f(const Color(0xFFEAF0F5)),
        );
      }
    }
  }

  /// Hendekten tünele girişteki taş cephe: kemerli ağız, üstte hat
  /// renginde kuşak.
  void _drawPortal(Canvas canvas, double z) {
    final m = _cycle(z);
    final isMouth = _layout.any(
      (e) =>
          e.$2 == _Zone.tunnel &&
          ((m - e.$1).abs() < 1e-6 || (m - e.$1 - _period).abs() < 1e-6),
    );
    if (!isMouth) return;
    if (z - _cam.z < 2) return;
    _drawHill(canvas, z);
    final face = Path()..fillType = PathFillType.evenOdd;
    final outer = <Offset>[];
    for (final o in const <Offset>[
      Offset(-14, -0.5),
      Offset(14, -0.5),
      Offset(14, 14.5),
      Offset(-14, 14.5),
    ]) {
      final p = _cam.project(o.dx, o.dy, z);
      if (p == null) return;
      outer.add(p);
    }
    final hole = <Offset>[];
    for (final o in _tunnelOutline) {
      final p = _cam.project(o.dx, o.dy, z);
      if (p == null) return;
      hole.add(p);
    }
    face
      ..addPolygon(outer, true)
      ..addPolygon(hole, true);
    final fog = _fog(z, false);
    _fill.color = Color.lerp(const Color(0xFFD2694B), _haze, fog)!;
    canvas.drawPath(face, _fill);
    // Kemer çevresinde açık taş.
    _path
      ..reset()
      ..addPolygon(hole.sublist(1), false);
    _stroke
      ..color = Color.lerp(const Color(0xFFF3D9A4), _haze, fog)!
      ..strokeWidth = _px(0.9, z);
    canvas.drawPath(_path, _stroke);
    // Üst kuşak.
    _planeZ(
      canvas,
      z - 0.02,
      -14,
      14,
      12.6,
      13.6,
      Color.lerp(colorForLevel(controller.lineLevel), _haze, fog)!,
    );
  }

  /// Tünelin içine girdiği yeşil tepe: cephenin ardında yükselir.
  void _drawHill(Canvas canvas, double z) {
    final pts = <Offset>[];
    const steps = 18;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = -90 + 180 * t;
      final y = 26 * math.pow(math.sin(math.pi * t), 0.7).toDouble() - 0.6;
      final p = _cam.project(x, y, z + 6);
      if (p == null) return;
      pts.add(p);
    }
    // Tünel ağzı tepede delik kalır: içerisi zaten çizildi.
    final mouth = <Offset>[];
    for (final o in _tunnelOutline) {
      final q = _cam.project(o.dx, o.dy, z);
      if (q == null) return;
      mouth.add(q);
    }
    final fog = _fog(z + 6, false);
    final hill = Path()
      ..fillType = PathFillType.evenOdd
      ..addPolygon(pts, true)
      ..addPolygon(mouth, true);
    _fill.color = Color.lerp(const Color(0xFF5DAE3F), _haze, fog)!;
    canvas.drawPath(hill, _fill);
  }

  // ------------------------------------------------------------ nesneler

  List<_Obj> _collectObjects(double start, double end) {
    final objs = <_Obj>[];
    bool zoneIs(double z, _Zone zone) => _zoneAt(z) == zone;

    // Tünel: duvar lambaları ve afişler.
    for (var z = (start / 10).ceil() * 10.0; z < end; z += 10) {
      final zz = z;
      if (_isTunnel(zz)) {
        objs.add(_Obj(zz, (c) => _wallLamp(c, zz)));
      }
    }
    for (var z = (start / 24).ceil() * 24.0; z < end; z += 24) {
      final zz = z;
      final k = (zz / 24).round();
      if (_isTunnel(zz) && _isTunnel(zz + 5)) {
        objs.add(_Obj(zz + 5, (c) => _poster(c, zz, k)));
      } else if (zoneIs(zz, _Zone.cut) && zoneIs(zz + 6, _Zone.cut)) {
        objs.add(_Obj(zz + 6, (c) => _graffitiPanel(c, zz, k)));
      }
    }
    // Selviler (hendek ve vadi), vadide çınarlar.
    for (var z = (start / 9).ceil() * 9.0; z < end; z += 9) {
      final zz = z;
      final zone = _zoneAt(zz);
      if (zone != _Zone.cut && zone != _Zone.meadow) continue;
      final k = (zz / 9).round();
      if (_hash(k) < 0.75) {
        final side = _hash(k + 77) < 0.5 ? -1.0 : 1.0;
        final x = side * (11 + _hash(k + 3) * 16);
        final base = zone == _Zone.cut ? 3.2 : -0.6;
        objs.add(
          _Obj(zz, (c) => _cypress(c, x, zz, 6 + _hash(k + 9) * 5, base)),
        );
      }
      if (zone == _Zone.meadow && _hash(k + 41) < 0.45) {
        final side = _hash(k + 43) < 0.5 ? -1.0 : 1.0;
        final x = side * (14 + _hash(k + 47) * 30);
        objs.add(_Obj(zz + 4, (c) => _planeTree(c, x, zz + 4, k)));
      }
    }
    // Vadide lale tarhları ve ahşap evler.
    for (var z = (start / 6).ceil() * 6.0; z < end; z += 6) {
      final zz = z;
      if (!zoneIs(zz, _Zone.meadow)) continue;
      final k = (zz / 6).round();
      final side = _hash(k + 5) < 0.5 ? -1.0 : 1.0;
      final x = side * (9.5 + _hash(k + 11) * 20);
      objs.add(_Obj(zz, (c) => _tulips(c, x, zz, k)));
    }
    for (var z = (start / 34).ceil() * 34.0; z < end; z += 34) {
      final zz = z;
      if (!zoneIs(zz, _Zone.meadow) || !zoneIs(zz + 10, _Zone.meadow)) {
        continue;
      }
      final k = (zz / 34).round();
      final side = k.isEven ? -1.0 : 1.0;
      final x = side * (26 + _hash(k + 19) * 22);
      objs.add(_Obj(zz, (c) => _house(c, x, zz, k)));
    }
    // Hendekte lamba direkleri; köprüde köprü lambaları.
    for (var z = (start / 25).ceil() * 25.0; z < end; z += 25) {
      final zz = z;
      final zone = _zoneAt(zz);
      if (zone == _Zone.cut) {
        objs.add(_Obj(zz, (c) => _lampPost(c, zz, 9.2, 3.2)));
      } else if (zone == _Zone.bridge) {
        objs.add(_Obj(zz, (c) => _lampPost(c, zz, 7.0, 0)));
      }
    }
    // Sinyal köprüleri: hendek ve vadide.
    for (var z = (start / 150).ceil() * 150.0; z < end; z += 150) {
      final zz = z + 40;
      final zone = _zoneAt(zz);
      if (zone != _Zone.cut && zone != _Zone.meadow) continue;
      objs.add(_Obj(zz, (c) => _gantry(c, zz)));
    }
    // Köprü: kuleler ve askı kabloları; denizde vapurlar ve parıltılar.
    final k0 = (start / _period).floor();
    for (var k = k0; k <= (end / _period).floor(); k++) {
      for (final m in _pylons) {
        final zz = k * _period + m;
        if (zz < start - 60 || zz > end) continue;
        objs.add(_Obj(zz, (c) => _pylon(c, zz)));
      }
    }
    for (var z = (start / 70).ceil() * 70.0; z < end; z += 70) {
      final zz = z;
      if (!zoneIs(zz, _Zone.bridge)) continue;
      final k = (zz / 70).round();
      final side = k.isEven ? -1.0 : 1.0;
      final x = side * (45 + _hash(k + 23) * 90);
      objs.add(_Obj(zz, (c) => _ferry(c, x, zz, k)));
    }
    for (var z = (start / 5).ceil() * 5.0; z < end; z += 5) {
      final zz = z;
      if (!zoneIs(zz, _Zone.bridge)) continue;
      final k = (zz / 5).round();
      final side = _hash(k + 61) < 0.5 ? -1.0 : 1.0;
      final x = side * (9 + _hash(k + 67) * 70);
      objs.add(_Obj(zz, (c) => _glint(c, x, zz, k)));
    }

    // Karşıdan gelen trenler.
    final adv = _warmTravel == null ? controller.renderAdvance : 0.0;
    final obstacles = _warmTravel == null
        ? controller.obstacles
        : _warmObstacles;
    for (final o in obstacles) {
      final y = o.y + adv;
      final center = _zp + (laneRunnerTrainY - y) * unit;
      final nearZ = center - _obstacleHalf;
      if (nearZ > end || center + _obstacleHalf < start) continue;
      // Doğduğu yerde birden belirmesin: ilk metrelerde sise karışır.
      final fade = ((y + 0.12) / 0.14).clamp(0.0, 1.0);
      objs.add(
        _Obj(
          nearZ,
          (c) => _oncomingTrain(c, o, nearZ, center + _obstacleHalf, fade),
        ),
      );
    }
    return objs;
  }

  static double _hash(int k) {
    final v = math.sin(k * 127.1 + 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  void _wallLamp(Canvas c, double z) {
    final fog = _fog(z, true);
    for (final x in <double>[-7.9, 7.9]) {
      final p = _cam.project(x, 3.7, z);
      if (p == null) continue;
      final r = _px(1.6, z);
      _fill.shader = ui.Gradient.radial(p, math.max(r, 1), <Color>[
        const Color(0xFFFFE2A0).withValues(alpha: 0.5 * (1 - fog)),
        const Color(0x00FFE2A0),
      ]);
      c.drawCircle(p, math.max(r, 1), _fill);
      _fill.shader = null;
      _fill.color = Color.lerp(const Color(0xFFFFF8E1), _tunnelFog, fog * 0.6)!;
      c.drawCircle(p, math.max(_px(0.22, z), 1), _fill);
    }
  }

  void _poster(Canvas c, double z, int k) {
    final side = k.isEven ? -7.96 : 7.96;
    final fog = _fog(z, true);
    final a = _graffiti[k % _graffiti.length];
    final b = _graffiti[(k + 2) % _graffiti.length];
    final p0 = _cam.project(side, 1.0, z);
    final p1 = _cam.project(side, 1.0, z + 5);
    final p2 = _cam.project(side, 3.4, z + 5);
    final p3 = _cam.project(side, 3.4, z);
    if (p0 == null || p1 == null || p2 == null || p3 == null) return;
    _fill.color = Color.lerp(const Color(0xFF2B2420), _tunnelFog, fog)!;
    _quad(c, p0, p1, p2, p3);
    final i0 = Offset.lerp(
      Offset.lerp(p0, p1, 0.06)!,
      Offset.lerp(p3, p2, 0.06)!,
      0.08,
    )!;
    final i1 = Offset.lerp(
      Offset.lerp(p0, p1, 0.94)!,
      Offset.lerp(p3, p2, 0.94)!,
      0.08,
    )!;
    final i2 = Offset.lerp(
      Offset.lerp(p0, p1, 0.94)!,
      Offset.lerp(p3, p2, 0.94)!,
      0.92,
    )!;
    final i3 = Offset.lerp(
      Offset.lerp(p0, p1, 0.06)!,
      Offset.lerp(p3, p2, 0.06)!,
      0.92,
    )!;
    _path
      ..reset()
      ..addPolygon(<Offset>[i0, i1, i2, i3], true);
    _fill.shader = ui.Gradient.linear(i3, i1, <Color>[
      Color.lerp(a, _tunnelFog, fog)!,
      Color.lerp(b, _tunnelFog, fog)!,
    ]);
    c.drawPath(_path, _fill);
    _fill.shader = null;
    // Afişte beyaz daire ve yazı çubuğu.
    final mid = Offset.lerp(i0, i2, 0.5)!;
    final hgt = (i3 - i0).distance;
    _fill.color = Color.lerp(
      Colors.white,
      _tunnelFog,
      fog,
    )!.withValues(alpha: 0.85);
    c.drawCircle(Offset.lerp(mid, i3, 0.25)!, hgt * 0.18, _fill);
  }

  void _graffitiPanel(Canvas c, double z, int k) {
    final side = k.isEven ? -8.25 : 8.25;
    final x0 = side < 0 ? side + 0.12 : side - 0.12;
    final fog = _fog(z, false);
    final col = Color.lerp(_graffiti[k % _graffiti.length], _haze, fog)!;
    final col2 = Color.lerp(_graffiti[(k + 3) % _graffiti.length], _haze, fog)!;
    // Duvar eğik: panelin üstü biraz daha dışarıda.
    final p0 = _cam.project(x0 - (side < 0 ? 0.1 : -0.1), 0.6, z);
    final p1 = _cam.project(x0 - (side < 0 ? 0.1 : -0.1), 0.6, z + 6);
    final p2 = _cam.project(x0 - (side < 0 ? 0.45 : -0.45), 2.6, z + 6);
    final p3 = _cam.project(x0 - (side < 0 ? 0.45 : -0.45), 2.6, z);
    if (p0 == null || p1 == null || p2 == null || p3 == null) return;
    _fill.color = col;
    _quad(c, p0, p1, p2, p3);
    // Çizgi film "baloncuk" harfleri yerine kalın dalga şerit.
    _stroke
      ..color = col2
      ..strokeWidth = math.max(_px(0.35, z + 3), 1);
    _path
      ..reset()
      ..moveTo(Offset.lerp(p0, p3, 0.5)!.dx, Offset.lerp(p0, p3, 0.5)!.dy);
    for (var i = 1; i <= 6; i++) {
      final t = i / 6;
      final bottom = Offset.lerp(p0, p1, t)!;
      final top = Offset.lerp(p3, p2, t)!;
      final p = Offset.lerp(bottom, top, i.isEven ? 0.3 : 0.7)!;
      _path.lineTo(p.dx, p.dy);
    }
    c.drawPath(_path, _stroke);
  }

  /// İstanbul selvisi: koyu yeşil, sivri.
  void _cypress(Canvas c, double x, double z, double h, double base) {
    final foot = _cam.project(x, base, z);
    final top = _cam.project(x, base + h, z);
    if (foot == null || top == null) return;
    final ph = foot.dy - top.dy;
    if (ph < 2) return;
    final fog = _fog(z, false);
    final w = ph * 0.22;
    _fill.color = Color.lerp(const Color(0xFF5A3A22), _haze, fog)!;
    c.drawRect(
      Rect.fromLTRB(
        foot.dx - w * 0.08,
        foot.dy - ph * 0.12,
        foot.dx + w * 0.08,
        foot.dy,
      ),
      _fill,
    );
    final body = Path()
      ..moveTo(foot.dx, top.dy)
      ..quadraticBezierTo(
        foot.dx + w * 0.75,
        foot.dy - ph * 0.45,
        foot.dx + w * 0.35,
        foot.dy - ph * 0.1,
      )
      ..lineTo(foot.dx - w * 0.35, foot.dy - ph * 0.1)
      ..quadraticBezierTo(
        foot.dx - w * 0.75,
        foot.dy - ph * 0.45,
        foot.dx,
        top.dy,
      )
      ..close();
    _fill.color = Color.lerp(const Color(0xFF2E7D32), _haze, fog)!;
    c.drawPath(body, _fill);
    // Güneş tarafında açık ton.
    final lit = Path()
      ..moveTo(foot.dx, top.dy)
      ..quadraticBezierTo(
        foot.dx - w * 0.75,
        foot.dy - ph * 0.45,
        foot.dx - w * 0.35,
        foot.dy - ph * 0.1,
      )
      ..lineTo(foot.dx - w * 0.05, foot.dy - ph * 0.1)
      ..close();
    _fill.color = Color.lerp(const Color(0xFF4CAF50), _haze, fog)!;
    c.drawPath(lit, _fill);
  }

  void _lampPost(Canvas c, double z, double offset, double base) {
    final fog = _fog(z, false);
    for (final x in <double>[-offset, offset]) {
      final foot = _cam.project(x, base, z);
      final top = _cam.project(x, base + 5.4, z);
      final arm = _cam.project(x - x.sign * 1.6, base + 5.4, z);
      if (foot == null || top == null || arm == null) continue;
      _stroke
        ..color = Color.lerp(const Color(0xFF37474F), _haze, fog)!
        ..strokeWidth = math.max(_px(0.18, z), 1);
      c.drawLine(foot, top, _stroke);
      c.drawLine(top, arm, _stroke);
      _fill.color = Color.lerp(const Color(0xFFFFF3C4), _haze, fog * 0.5)!;
      c.drawCircle(arm, math.max(_px(0.3, z), 1.2), _fill);
    }
  }

  /// Çınar: kalın gövde, yuvarlak geniş taç.
  void _planeTree(Canvas c, double x, double z, int k) {
    final foot = _cam.project(x, -0.6, z);
    final top = _cam.project(x, 10 + _hash(k + 3) * 4, z);
    if (foot == null || top == null) return;
    final ph = foot.dy - top.dy;
    if (ph < 3) return;
    final fog = _fog(z, false);
    _fill.color = Color.lerp(const Color(0xFF6D4C35), _haze, fog)!;
    c.drawRect(
      Rect.fromLTRB(
        foot.dx - ph * 0.05,
        foot.dy - ph * 0.45,
        foot.dx + ph * 0.05,
        foot.dy,
      ),
      _fill,
    );
    final crown = Offset(foot.dx, top.dy + ph * 0.32);
    _fill.color = Color.lerp(const Color(0xFF3F9142), _haze, fog)!;
    c.drawOval(
      Rect.fromCenter(center: crown, width: ph * 0.8, height: ph * 0.62),
      _fill,
    );
    _fill.color = Color.lerp(const Color(0xFF63B455), _haze, fog)!;
    c.drawOval(
      Rect.fromCenter(
        center: crown.translate(-ph * 0.12, -ph * 0.08),
        width: ph * 0.45,
        height: ph * 0.36,
      ),
      _fill,
    );
  }

  /// Lale tarhı: kırmızı, sarı, pembe benekler; İstanbul'un lalesi.
  void _tulips(Canvas c, double x, double z, int k) {
    final fog = _fog(z, false);
    const colors = <Color>[
      Color(0xFFE53935),
      Color(0xFFFFC107),
      Color(0xFFEC407A),
      Color(0xFFFFFFFF),
    ];
    final color = Color.lerp(colors[k % colors.length], _haze, fog)!;
    _fill.color = color;
    for (var i = 0; i < 9; i++) {
      final dx = (_hash(k * 13 + i) - 0.5) * 5;
      final dz = (_hash(k * 17 + i) - 0.5) * 3;
      final p = _cam.project(x + dx, -0.3, z + dz);
      if (p == null) continue;
      final r = _px(0.28, z + dz);
      if (r < 0.6) continue;
      c.drawOval(
        Rect.fromCenter(center: p, width: r * 1.6, height: r * 2),
        _fill,
      );
    }
  }

  /// Ahşap İstanbul evi: pastel cephe, kiremit kırma çatı, pencereler.
  void _house(Canvas c, double x, double z, int k) {
    const palette = <Color>[
      Color(0xFFE7B96A),
      Color(0xFFE59A8C),
      Color(0xFF9CC3D5),
      Color(0xFFF2E3C6),
      Color(0xFFB7D39A),
    ];
    final wall = palette[k % palette.length];
    final fog = _fog(z, false);
    final w = 7.0 + _hash(k + 2) * 3;
    final d = 7.0;
    final h = 6.0 + _hash(k + 4) * 3;
    const y0 = -0.6;
    final x0 = x - w / 2;
    final x1 = x + w / 2;
    final z0 = z;
    final z1 = z + d;
    Offset? p(double px, double py, double pz) => _cam.project(px, py, pz);
    // Kameraya bakan yan yüz (evin hattın hangi yanında olduğuna göre).
    final sideX = x > _cam.x ? x0 : x1;
    final s0 = p(sideX, y0, z0);
    final s1 = p(sideX, y0, z1);
    final s2 = p(sideX, y0 + h, z1);
    final s3 = p(sideX, y0 + h, z0);
    if (s0 != null && s1 != null && s2 != null && s3 != null) {
      _fill.color = Color.lerp(_lit(wall, 0.8), _haze, fog)!;
      _quad(c, s0, s1, s2, s3);
    }
    // Ön cephe.
    final f0 = p(x0, y0, z0);
    final f1 = p(x1, y0, z0);
    final f2 = p(x1, y0 + h, z0);
    final f3 = p(x0, y0 + h, z0);
    if (f0 == null || f1 == null || f2 == null || f3 == null) return;
    _fill.color = Color.lerp(wall, _haze, fog)!;
    _quad(c, f0, f1, f2, f3);
    // Pencereler: iki kat, ikişer.
    _fill.color = Color.lerp(const Color(0xFF3A4A5A), _haze, fog)!;
    for (final fy in <double>[0.25, 0.62]) {
      for (final fx in <double>[0.22, 0.62]) {
        final a = p(x0 + w * fx, y0 + h * fy, z0 - 0.02);
        final b = p(x0 + w * (fx + 0.16), y0 + h * (fy + 0.2), z0 - 0.02);
        if (a == null || b == null) continue;
        c.drawRect(Rect.fromPoints(a, b), _fill);
      }
    }
    // Kırma çatı: tepe noktası ortada.
    final apex = p(x, y0 + h + 3, z + d / 2);
    if (apex == null) return;
    final roof = Color.lerp(const Color(0xFFC0533A), _haze, fog)!;
    _fill.color = roof;
    _path
      ..reset()
      ..addPolygon(<Offset>[f3, f2, apex], true);
    c.drawPath(_path, _fill);
    if (s2 == null || s3 == null) return;
    _fill.color = Color.lerp(_lit(const Color(0xFFC0533A), 0.75), _haze, fog)!;
    _path
      ..reset()
      ..addPolygon(<Offset>[s3, s2, apex], true);
    c.drawPath(_path, _fill);
  }

  /// Haliç Metro Köprüsü'nden esinli kule: iki bacak, tepede kiriş,
  /// tabliyeye yelpaze gibi inen askı kabloları.
  void _pylon(Canvas c, double z) {
    final fog = _fog(z, false);
    final steel = Color.lerp(const Color(0xFFF1F3F5), _haze, fog)!;
    final shade = Color.lerp(const Color(0xFFC9CFD5), _haze, fog)!;
    const top = 42.0;
    for (final x in <double>[-7.6, 7.6]) {
      final b0 = _cam.project(x - 0.9, -16, z);
      final b1 = _cam.project(x + 0.9, -16, z);
      final t1 = _cam.project(x * 0.55 + 0.6, top, z);
      final t0 = _cam.project(x * 0.55 - 0.6, top, z);
      if (b0 == null || b1 == null || t0 == null || t1 == null) continue;
      _fill.color = x < 0 ? steel : shade;
      _quad(c, b0, b1, t1, t0);
    }
    // Tepe kirişi.
    _planeZ(c, z, -4.8, 4.8, top - 2.2, top, steel);
    // Askı kabloları: iki yana, ileri ve geri.
    _stroke
      ..color = Color.lerp(const Color(0xCCFFFFFF), _haze, fog)!
      ..strokeWidth = 1;
    for (final x in <double>[-7.6, 7.6]) {
      final anchor = _cam.project(x * 0.55, top - 3, z);
      if (anchor == null) continue;
      for (var i = 1; i <= 6; i++) {
        for (final dir in <double>[-1, 1]) {
          final dz = dir * i * 11;
          final deck = _cam.project(x * 0.9, 0.3, z + dz);
          if (deck == null) continue;
          c.drawLine(anchor, deck, _stroke);
        }
      }
    }
  }

  /// Vapur: beyaz gövde, siyah bel, kırmızı bacadan duman.
  void _ferry(Canvas c, double x, double z, int k) {
    final fog = _fog(z, false);
    final bow = _cam.project(x - 9, -15.2, z);
    final stern = _cam.project(x + 9, -15.2, z);
    final deck = _cam.project(x - 7, -12, z);
    if (bow == null || stern == null || deck == null) return;
    final len = (stern.dx - bow.dx).abs();
    if (len < 3) return;
    final hH = stern.dy - deck.dy;
    final left = math.min(bow.dx, stern.dx);
    final base = bow.dy;
    _fill.color = Color.lerp(const Color(0xFF1E2328), _haze, fog)!;
    c.drawRRect(
      RRect.fromLTRBR(
        left,
        base - hH * 0.35,
        left + len,
        base,
        Radius.circular(hH * 0.3),
      ),
      _fill,
    );
    _fill.color = Color.lerp(Colors.white, _haze, fog)!;
    c.drawRect(
      Rect.fromLTRB(
        left + len * 0.08,
        base - hH,
        left + len * 0.92,
        base - hH * 0.35,
      ),
      _fill,
    );
    _fill.color = Color.lerp(const Color(0xFF3A4A5A), _haze, fog)!;
    for (var i = 0; i < 6; i++) {
      final wx = left + len * (0.14 + i * 0.12);
      c.drawRect(
        Rect.fromLTWH(wx, base - hH * 0.82, len * 0.06, hH * 0.2),
        _fill,
      );
    }
    final funnel = Rect.fromLTWH(
      left + len * 0.45,
      base - hH * 1.45,
      len * 0.08,
      hH * 0.5,
    );
    _fill.color = Color.lerp(const Color(0xFFD32F2F), _haze, fog)!;
    c.drawRect(funnel, _fill);
    _fill.color = Color.lerp(const Color(0x88FFFFFF), _haze, fog)!;
    final puff = (_t * 0.5 + k) % 1.0;
    c.drawCircle(
      Offset(
        funnel.center.dx + len * 0.06 * puff,
        funnel.top - hH * 0.3 * puff,
      ),
      hH * (0.15 + 0.2 * puff),
      _fill,
    );
  }

  /// Denizde güneş parıltısı: zamanla yanıp sönen ince beyaz çizgi.
  void _glint(Canvas c, double x, double z, int k) {
    final p = _cam.project(x, -15.9, z);
    if (p == null) return;
    final phase = (math.sin(_t * 0.9 + k * 1.7) + 1) / 2;
    if (phase < 0.45) return;
    final fog = _fog(z, false);
    final len = _px(1.6, z);
    if (len < 1) return;
    _stroke
      ..color = Colors.white.withValues(alpha: (phase - 0.45) * 1.4 * (1 - fog))
      ..strokeWidth = math.max(_px(0.12, z), 1);
    c.drawLine(p.translate(-len, 0), p.translate(len, 0), _stroke);
  }

  /// Hattın üstünden geçen sinyal köprüsü; her ray için bir yeşil lamba.
  void _gantry(Canvas c, double z) {
    final fog = _fog(z, false);
    final steel = Color.lerp(const Color(0xFF455A64), _haze, fog)!;
    final legL = _cam.project(-7.4, 0, z);
    final legLT = _cam.project(-7.4, 7.2, z);
    final legR = _cam.project(7.4, 0, z);
    final legRT = _cam.project(7.4, 7.2, z);
    if (legL == null || legLT == null || legR == null || legRT == null) return;
    _stroke
      ..color = steel
      ..strokeWidth = math.max(_px(0.35, z), 1.5);
    c.drawLine(legL, legLT, _stroke);
    c.drawLine(legR, legRT, _stroke);
    _planeZ(c, z, -7.6, 7.6, 6.6, 7.4, steel);
    for (var lane = 0; lane < laneRunnerLaneCount; lane++) {
      final lx = (lane - 1) * laneSpacing;
      _planeZ(
        c,
        z - 0.05,
        lx - 0.4,
        lx + 0.4,
        5.3,
        6.6,
        Color.lerp(const Color(0xFF1B1F23), _haze, fog)!,
      );
      final lampP = _cam.project(lx, 5.75, z - 0.1);
      if (lampP == null) continue;
      final r = math.max(_px(0.22, z), 1.2);
      _fill.shader = ui.Gradient.radial(lampP, r * 4, <Color>[
        const Color(0x8834E07A),
        const Color(0x0034E07A),
      ]);
      c.drawCircle(lampP, r * 4, _fill);
      _fill.shader = null;
      _fill.color = const Color(0xFF7CFFB0);
      c.drawCircle(lampP, r, _fill);
    }
  }

  // ------------------------------------------------------------- trenler

  static const List<Offset> _body = <Offset>[
    Offset(-1.5, 0.9),
    Offset(1.5, 0.9),
    Offset(1.5, 3.2),
    Offset(1.25, 3.65),
    Offset(-1.25, 3.65),
    Offset(-1.5, 3.2),
  ];

  static const List<Offset> _under = <Offset>[
    Offset(-1.25, 0.3),
    Offset(1.25, 0.3),
    Offset(1.25, 0.9),
    Offset(-1.25, 0.9),
  ];

  /// Karşıdan gelen tren: burnu kameraya dönük, farları yanık.
  void _oncomingTrain(
    Canvas c,
    LaneObstacle o,
    double z0,
    double z1,
    double fade,
  ) {
    final lx = (o.lane - 1) * laneSpacing;
    final tunnel = _isTunnel(z0);
    final fogColor = tunnel ? _tunnelFog : _haze;
    final fog = math.max(_fog(z0, tunnel), 1 - fade);
    final color = _oncoming[o.id % _oncoming.length];
    // Farların raya düşen ışığı.
    final b0 = _cam.project(lx - 1.3, 0.3, z0 - 14);
    final b1 = _cam.project(lx + 1.3, 0.3, z0 - 14);
    final b2 = _cam.project(lx + 1.0, 0.3, z0);
    final b3 = _cam.project(lx - 1.0, 0.3, z0);
    if (b0 != null && b1 != null && b2 != null && b3 != null) {
      _path
        ..reset()
        ..addPolygon(<Offset>[b0, b1, b2, b3], true);
      _fill.shader = ui.Gradient.linear(b3, b0, <Color>[
        Color.fromRGBO(255, 236, 170, 0.45 * (1 - fog)),
        const Color(0x00FFECAA),
      ]);
      c.drawPath(_path, _fill);
      _fill.shader = null;
    }
    _prism(
      c,
      _under,
      lx,
      z0 + 1,
      z1 - 1,
      const Color(0xFF2A2A2E),
      fog,
      fogColor,
    );
    _prism(c, _body, lx, z0, z1, color, fog, fogColor, outline: true);
    // Ön yüz: beyaz maske, cam, farlar.
    final z = z0 - 0.02;
    _trainPlaneZ(
      c,
      z,
      lx,
      -1.35,
      1.35,
      1.05,
      3.45,
      Color.lerp(const Color(0xFFF5F5F5), fogColor, fog)!,
    );
    _trainPlaneZ(
      c,
      z - 0.01,
      lx,
      -1.1,
      1.1,
      2.15,
      3.25,
      Color.lerp(const Color(0xFF1D2733), fogColor, fog)!,
    );
    _trainPlaneZ(
      c,
      z - 0.02,
      lx,
      -1.0,
      -0.1,
      2.85,
      3.15,
      Color.lerp(const Color(0x55FFFFFF), fogColor, fog)!,
    );
    _trainPlaneZ(
      c,
      z - 0.01,
      lx,
      -1.35,
      1.35,
      1.35,
      1.75,
      Color.lerp(color, fogColor, fog)!,
    );
    for (final side in <double>[-1, 1]) {
      final p = _tp(lx, side * 0.95, 1.95, z - 0.03);
      if (p == null) continue;
      final r = math.max(_px(0.2 * _k, z), 1.2);
      _fill.shader = ui.Gradient.radial(p, r * 6, <Color>[
        Color.fromRGBO(255, 244, 200, 0.75 * (1 - fog * 0.7)),
        const Color(0x00FFF4C8),
      ]);
      c.drawCircle(p, r * 6, _fill);
      _fill.shader = null;
      _fill.color = Color.lerp(const Color(0xFFFFFDE7), fogColor, fog * 0.5)!;
      c.drawCircle(p, r, _fill);
    }
  }

  /// Oyuncunun treni: arkadan görünüm, hat renginde geniş kuşak. Ray
  /// değiştirirken dönüş yönüne yatar.
  void _drawPlayer(Canvas c, double lane, double px) {
    final color = colorForLevel(controller.lineLevel);
    final lean = (controller.trainLane - lane).clamp(-1.0, 1.0) * 0.14;
    final zFront = _zp;
    double xAt(double z) => _bodyX(z, px);
    final zRear = zFront - _trainLength;
    final xRear = xAt(zRear);
    final tunnel = _isTunnel(zFront - 15);
    final light = tunnel ? 0.85 + _daylight(zFront - 15) * 0.15 : 1.0;
    // Gölge.
    final s0 = _cam.project(xRear - 1.8 * _k, 0.14, zRear - 0.5);
    final s1 = _cam.project(xRear + 1.8 * _k, 0.14, zRear - 0.5);
    final s2 = _cam.project(px + 1.8 * _k, 0.14, zFront + 0.5);
    final s3 = _cam.project(px - 1.8 * _k, 0.14, zFront + 0.5);
    if (s0 != null && s1 != null && s2 != null && s3 != null) {
      _fill.color = const Color(0x55000000);
      _quad(c, s0, s1, s2, s3);
    }
    for (var car = 0; car < 2; car++) {
      final z1 = zFront - car * (_carLength + _carGap);
      final z0 = z1 - _carLength;
      _prism(
        c,
        _under,
        px,
        z0 + 1,
        z1 - 1,
        const Color(0xFF26282C),
        0,
        _haze,
        light: light,
        xAt: xAt,
      );
      _prism(
        c,
        _body,
        px,
        z0,
        z1,
        const Color(0xFFF3F5F7),
        0,
        _haze,
        outline: true,
        lean: lean,
        light: light,
        xAt: xAt,
        stripe: color,
      );
      // Tavanda klima.
      _prism(
        c,
        const <Offset>[
          Offset(-0.8, 3.65),
          Offset(0.8, 3.65),
          Offset(0.65, 3.95),
          Offset(-0.65, 3.95),
        ],
        px,
        z0 + 3,
        z1 - 3,
        const Color(0xFFB8BEC4),
        0,
        _haze,
        outline: true,
        lean: lean,
        light: light,
        xAt: xAt,
      );
    }
    // Arka kabin: cam, stop lambaları, hat rozeti.
    final z = zFront - _trainLength - 0.02;
    _trainPlaneZ(
      c,
      z,
      xRear,
      -1.1,
      1.1,
      2.1,
      3.2,
      const Color(0xFF1D2733),
      lean: lean,
    );
    _trainPlaneZ(
      c,
      z - 0.01,
      xRear,
      -1.0,
      -0.2,
      2.85,
      3.1,
      const Color(0x44FFFFFF),
      lean: lean,
    );
    for (final side in <double>[-1, 1]) {
      final p = _tp(xRear, side * 1.05, 1.75, z - 0.02, lean: lean);
      if (p == null) continue;
      final r = math.max(_px(0.16 * _k, z), 1.5);
      _fill.shader = ui.Gradient.radial(p, r * 4, <Color>[
        const Color(0x99FF3B30),
        const Color(0x00FF3B30),
      ]);
      c.drawCircle(p, r * 4, _fill);
      _fill.shader = null;
      _fill.color = const Color(0xFFFF6B5E);
      c.drawCircle(p, r, _fill);
    }
    // Tavanın üstünde hat rozeti (ekran uzayında hap).
    final badge = _tp(xAt(zRear + 2), 0, 4.7, zRear + 2, lean: lean);
    if (badge != null) {
      final label = controller.lineLabel;
      final tp = _label(label, LineTheme.readableOn(color));
      final hgt = tp.height + 6;
      final rect = Rect.fromCenter(
        center: badge,
        width: tp.width + 18,
        height: hgt,
      );
      _fill.color = const Color(0x55000000);
      c.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(const Offset(0, 3)),
          Radius.circular(hgt / 2),
        ),
        _fill,
      );
      _fill.color = color;
      c.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(hgt / 2)),
        _fill,
      );
      _stroke
        ..color = Colors.white
        ..strokeWidth = 2;
      c.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(hgt / 2)),
        _stroke,
      );
      tp.paint(c, badge - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// Dışbükey kesiti [z0, z1] boyunca uzatır; kameraya dönük yüzleri düz
  /// gölgeyle boyar. [lean] gövdeyi yüksekliğe göre yana yatırır;
  /// [stripe] yan ve arka yüzlere hat kuşağı çizer.
  void _prism(
    Canvas c,
    List<Offset> sec,
    double x,
    double z0,
    double z1,
    Color color,
    double fog,
    Color fogColor, {
    bool outline = false,
    double lean = 0,
    double light = 1,
    Color? stripe,
    double Function(double z)? xAt,
  }) {
    Offset? p(Offset s, double z) => _cam.project(
      (xAt?.call(z) ?? x) + (s.dx + lean * s.dy) * _k,
      s.dy * _k,
      z,
    );
    for (var i = 0; i < sec.length; i++) {
      final a = sec[i];
      final b = sec[(i + 1) % sec.length];
      final q0 = p(a, z0);
      final q1 = p(a, z1);
      final q2 = p(b, z1);
      final q3 = p(b, z0);
      if (q0 == null || q1 == null || q2 == null || q3 == null) continue;
      final quad = <Offset>[q0, q1, q2, q3];
      if (!_facing(quad)) continue;
      final ny = -(b.dx - a.dx);
      final nx = b.dy - a.dy;
      final len = (b - a).distance;
      final shade = 0.74 + 0.26 * ny / len + 0.06 * nx / len;
      _fill.color = Color.lerp(_lit(color, shade * light), fogColor, fog)!;
      _quad(c, q0, q1, q2, q3);
      if (stripe != null && a.dx.abs() > 1.4 && b.dx.abs() > 1.4) {
        // Yan kuşak ve pencereler.
        final sx = a.dx;
        final s0 = p(Offset(sx, 1.3), z0);
        final s1 = p(Offset(sx, 1.3), z1);
        final s2 = p(Offset(sx, 1.95), z1);
        final s3 = p(Offset(sx, 1.95), z0);
        if (s0 != null && s1 != null && s2 != null && s3 != null) {
          _fill.color = _lit(stripe, light);
          _quad(c, s0, s1, s2, s3);
        }
        for (var k = 0; k < 5; k++) {
          final wz0 = z0 + 1.2 + k * 2.6;
          final w0 = p(Offset(sx, 2.25), wz0);
          final w1 = p(Offset(sx, 2.25), wz0 + 1.9);
          final w2 = p(Offset(sx, 3.0), wz0 + 1.9);
          final w3 = p(Offset(sx, 3.0), wz0);
          if (w0 == null || w1 == null || w2 == null || w3 == null) continue;
          _fill.color = _lit(const Color(0xFF26323F), light);
          _quad(c, w0, w1, w2, w3);
        }
      }
      if (outline) _edges(c, quad);
    }
    final cap = <Offset>[];
    for (final s in sec) {
      final q = p(s, z0);
      if (q == null) return;
      cap.add(q);
    }
    if (!_facing(cap)) return;
    _path
      ..reset()
      ..addPolygon(cap, true);
    _fill.color = Color.lerp(_lit(color, 0.92 * light), fogColor, fog)!;
    c.drawPath(_path, _fill);
    if (stripe != null) {
      final s0 = p(const Offset(-1.5, 1.3), z0 - 0.01);
      final s1 = p(const Offset(1.5, 1.3), z0 - 0.01);
      final s2 = p(const Offset(1.5, 1.95), z0 - 0.01);
      final s3 = p(const Offset(-1.5, 1.95), z0 - 0.01);
      if (s0 != null && s1 != null && s2 != null && s3 != null) {
        _fill.color = _lit(stripe, light);
        _quad(c, s0, s1, s2, s3);
      }
    }
    if (outline) _edges(c, cap);
  }

  // ---------------------------------------------------------- efektler

  /// Hız çizgileri: kenarlarda kaçış noktasından dışa akan ince şeritler.
  void _drawSpeedLines(Canvas canvas, Size size) {
    final count = 8 + (14 * _speedN).round();
    final center = Offset(size.width / 2, size.height * 0.4);
    final diag = size.longestSide;
    for (var i = 0; i < count; i++) {
      // Açı: üst ve alt orta bölge boş kalsın (ray ve gökyüzü okunur).
      final side = i.isEven ? -1.0 : 1.0;
      final angle = (side < 0 ? math.pi : 0) + (_hash(i * 7 + 1) - 0.5) * 1.5;
      final s = (_hash(i * 13 + 5) + _t * (0.5 + _speedN)) % 1.0;
      final r0 = diag * (0.28 + 0.55 * s);
      final len = diag * (0.05 + 0.12 * s) * (0.6 + _speedN);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final a = (0.06 + 0.14 * _speedN) * s;
      _stroke
        ..color = Colors.white.withValues(alpha: a)
        ..strokeWidth = 1.5 + 1.5 * s;
      canvas.drawLine(center + dir * r0, center + dir * (r0 + len), _stroke);
    }
  }

  void _drawVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    _fill.shader = ui.Gradient.radial(
      rect.center,
      size.longestSide * 0.75,
      <Color>[const Color(0x00000000), const Color(0x66000000)],
      <double>[0.6, 1],
    );
    canvas.drawRect(rect, _fill);
    _fill.shader = null;
  }

  // ------------------------------------------------------------- araçlar

  bool _facing(List<Offset> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum < 0;
  }

  void _edges(Canvas c, List<Offset> pts) {
    _path
      ..reset()
      ..addPolygon(pts, true);
    _stroke
      ..color = const Color(0x66000000)
      ..strokeWidth = 1.2;
    c.drawPath(_path, _stroke);
  }

  void _quad(Canvas c, Offset a, Offset b, Offset d, Offset e) {
    _path
      ..reset()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(d.dx, d.dy)
      ..lineTo(e.dx, e.dy)
      ..close();
    c.drawPath(_path, _fill);
  }

  /// x sabit, dikey düzlemde dörtgen (duvar şeridi, ray iç yüzü).
  void _planeX(
    Canvas c,
    double x,
    double y0,
    double y1,
    double z0,
    double z1,
    Color color,
  ) {
    final a = _cam.project(x, y0, z0);
    final b = _cam.project(x, y0, z1);
    final d = _cam.project(x, y1, z1);
    final e = _cam.project(x, y1, z0);
    if (a == null || b == null || d == null || e == null) return;
    _fill.color = color;
    _quad(c, a, b, d, e);
  }

  /// y sabit, yatay düzlemde dörtgen (balast, ray üstü, tavan ışığı).
  void _planeY(
    Canvas c,
    double y,
    double x0,
    double x1,
    double z0,
    double z1,
    Color color,
  ) {
    final a = _cam.project(x0, y, z0);
    final b = _cam.project(x1, y, z0);
    final d = _cam.project(x1, y, z1);
    final e = _cam.project(x0, y, z1);
    if (a == null || b == null || d == null || e == null) return;
    _fill.color = color;
    _quad(c, a, b, d, e);
  }

  /// Trenin yerel koordinatından ([_k] ölçekli, [lean] yatışlı) nokta.
  Offset? _tp(double cx, double x, double y, double z, {double lean = 0}) =>
      _cam.project(cx + (x + lean * y) * _k, y * _k, z);

  /// Trenin yerel koordinatında, kameraya bakan dörtgen.
  void _trainPlaneZ(
    Canvas c,
    double z,
    double cx,
    double x0,
    double x1,
    double y0,
    double y1,
    Color color, {
    double lean = 0,
  }) {
    final a = _tp(cx, x0, y0, z, lean: lean);
    final b = _tp(cx, x1, y0, z, lean: lean);
    final d = _tp(cx, x1, y1, z, lean: lean);
    final e = _tp(cx, x0, y1, z, lean: lean);
    if (a == null || b == null || d == null || e == null) return;
    _fill.color = color;
    _quad(c, a, b, d, e);
  }

  /// z sabit, kameraya bakan dörtgen.
  void _planeZ(
    Canvas c,
    double z,
    double x0,
    double x1,
    double y0,
    double y1,
    Color color,
  ) {
    final a = _cam.project(x0, y0, z);
    final b = _cam.project(x1, y0, z);
    final d = _cam.project(x1, y1, z);
    final e = _cam.project(x0, y1, z);
    if (a == null || b == null || d == null || e == null) return;
    _fill.color = color;
    _quad(c, a, b, d, e);
  }

  double _px(double meters, double z) =>
      _cam.f * meters / math.max(z - _cam.z, _near);

  static Color _lit(Color base, double light) {
    final l = light.clamp(0.0, 1.5);
    if (l <= 1) return Color.lerp(Colors.black, base, l)!;
    return Color.lerp(base, Colors.white, (l - 1) * 0.6)!;
  }

  static final Map<String, TextPainter> _labels = <String, TextPainter>{};

  TextPainter _label(String text, Color color) =>
      _labels.putIfAbsent('$text|${color.toARGB32()}', () {
        return TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: 'M PLUS Rounded 1c',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      });

  // --------------------------------------------------------- ısınma

  /// Isınma çiziminde kullanılan yol; `null` ise gerçek oyun.
  double? _warmTravel;

  static const List<LaneObstacle> _warmObstacles = <LaneObstacle>[
    LaneObstacle(id: 0, lane: 0, y: 0.2),
    LaneObstacle(id: 1, lane: 1, y: 0.45),
    LaneObstacle(id: 2, lane: 2, y: 0.62),
  ];

  /// Ekran gözükmeden her bölgeyi bir kez görünmez bir görüntüye çizer.
  ///
  /// GPU her çizim türünü (degrade, `drawVertices`, yarı saydam katman)
  /// ilk gördüğünde derliyor; tarayıcıda bu oyunun ilk saniyelerinde ve
  /// yeni bir bölgeye (vadi, köprü) ilk girişte kare kaçırtıyordu. Isınma
  /// o derlemeyi oyun başlamadan, ekran açılırken yaptırır.
  ///
  /// Dönen görüntüler bir kare sonra atılmalı: hemen atılırsa raster
  /// işi iptal edilebilir.
  List<ui.Image> warmUp(Size size) {
    final images = <ui.Image>[];
    final w = size.width.ceil().clamp(1, 4096);
    final h = size.height.ceil().clamp(1, 4096);
    // Her bölgenin ortasında, kamera o bölgenin içinde kalacak biçimde.
    for (final (m, _) in _layout) {
      final (a, b) = _zoneSpan(m);
      _warmTravel = ((a + b) / 2 + _trainLength + 12) / unit;
      final rec = ui.PictureRecorder();
      paint(Canvas(rec), size);
      final picture = rec.endRecording();
      images.add(picture.toImageSync(w, h));
      picture.dispose();
    }
    _warmTravel = null;
    _trailZ.clear();
    _trailX.clear();
    return images;
  }

  @override
  bool shouldRepaint(LaneRunnerScenePainter old) =>
      old.controller != controller;
}

enum _K { floor, wall, vault, grass, meadow, water, deck }

enum _Zone { tunnel, meadow, bridge, cut }

class _Seg {
  const _Seg(this.a, this.b, this.kind);
  final Offset a;
  final Offset b;
  final _K kind;
}

class _Obj {
  _Obj(this.z, this.draw);
  final double z;
  final void Function(Canvas) draw;
}

class _Cam {
  _Cam({
    required this.z,
    required this.x,
    required this.y,
    required this.base,
    required this.slope,
    required this.hBase,
    required this.hSlope,
    required this.cosP,
    required this.sinP,
    required this.f,
    required this.cx,
    required this.cy,
  });

  final double z;
  final double x;
  final double y;
  final double base;
  final double slope;
  final double hBase;
  final double hSlope;
  final double cosP;
  final double sinP;
  final double f;
  final double cx;
  final double cy;

  double _memoZ = double.nan;
  double _memoCurve = 0;
  double _memoHill = 0;

  Offset? project(double wx, double wy, double wz) {
    if (wz != _memoZ) {
      _memoZ = wz;
      _memoCurve = LaneRunnerScenePainter._curve(wz);
      _memoHill = LaneRunnerScenePainter._hill(wz);
    }
    final dz = wz - z;
    final lat = wx + _memoCurve - base - slope * dz - x;
    final ry = wy + _memoHill - hBase - hSlope * dz - y;
    final yc = ry * cosP + dz * sinP;
    final zc = dz * cosP - ry * sinP;
    if (zc < 0.3) return null;
    return Offset(cx + f * lat / zc, cy - f * yc / zc);
  }
}
