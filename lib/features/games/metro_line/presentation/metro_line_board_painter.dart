import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../application/metro_line_controller.dart';
import '../domain/metro_line_state.dart';

/// İstanbul hat renkleri — trenler bunlarla çizilir.
const List<Color> metroLineColors = <Color>[
  Color(0xFFE30613), // M1 kırmızı
  Color(0xFF009A44), // M2 yeşil
  Color(0xFF00AEEF), // M3 mavi
  Color(0xFFE6007E), // M4 pembe
  Color(0xFF6A2C91), // M5 mor
  Color(0xFFF7A800), // M6 turuncu
];

/// Basit 3B vektör.
@immutable
class _V {
  const _V(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;

  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double k) => _V(x * k, y * k, z * k);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(dot(this));
  _V get unit => this * (1 / length);
}

/// Tahtaya eğik bakan kamera: satranç tahtasına oyuncunun koltuğundan
/// bakar gibi. Dünya: x sağa, y yukarı, z uzağa; bir hücre 1 birim.
/// Tahtanın ortası orijinde, 0. satır en uzakta.
///
/// Hem çizim hem dokunma bu sınıfı kullanır: ekrandaki nokta ters
/// yansıtılarak hangi hücreye düştüğü bulunur.
class MetroLineBoardProjection {
  MetroLineBoardProjection(this.n, Size size) {
    // Uzak kamera: perspektif yumuşak, uzak sıralar fazla küçülmez.
    final r = n * 2.2;
    _cam = _V(0, r * math.sin(_pitch), -r * math.cos(_pitch));
    _fwd = const _V(0, 0, 0) - _cam;
    _fwd = _fwd.unit;
    _up = _V(0, math.cos(_pitch), math.sin(_pitch));
    // Tahtanın köşeleri (ve trenin yüksekliği) ekrana sığsın.
    final h = n / 2 + _rim;
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in <_V>[
      _V(-h, 0, -h),
      _V(h, 0, -h),
      _V(-h, 0, h),
      _V(h, 0, h),
      _V(-h, -_slab, -h),
      _V(h, -_slab, -h),
      _V(-h, _trainTop, h),
      _V(h, _trainTop, h),
    ]) {
      final q = _raw(p);
      minX = math.min(minX, q.dx);
      maxX = math.max(maxX, q.dx);
      minY = math.min(minY, q.dy);
      maxY = math.max(maxY, q.dy);
    }
    // Ağaçlar sığma hesabına girmez; kenardan biraz taşabilirler.
    final pad = 0.02;
    final sx = size.width * (1 - pad * 2) / (maxX - minX);
    final sy = size.height * (1 - pad * 2) / (maxY - minY);
    _scale = math.min(sx, sy);
    _offset = Offset(
      size.width / 2 - (minX + maxX) / 2 * _scale,
      size.height / 2 - (minY + maxY) / 2 * _scale,
    );
  }

  /// Bakış açısı: yataydan ~53° aşağı.
  static const double _pitch = 0.93;

  /// Ada: hücrelerin çevresinde çimenli kenar, altında toprak katmanları
  /// (hücre biriminde). Tren tepesi ekrana sığma hesabına girer.
  static const double _rim = 0.5;
  static const double _slab = 0.75;
  static const double _trainTop = 0.62;

  final int n;
  late _V _cam;
  late _V _fwd;
  late _V _up;
  late double _scale;
  late Offset _offset;

  _V get _camera => _cam;

  Offset _raw(_V p) {
    final d = p - _cam;
    final zc = d.dot(_fwd);
    return Offset(d.x / zc, -d.dot(_up) / zc);
  }

  /// Dünya noktasının ekrandaki yeri.
  Offset _project(_V p) => _offset + _raw(p) * _scale;

  /// Hücre (sütun, satır) kesirli koordinatından dünyaya.
  _V _world(double col, double row, [double y = 0]) =>
      _V(col - (n - 1) / 2, y, (n - 1) / 2 - row);

  /// Ekran noktasının [y] yüksekliğindeki yatay düzlemde denk geldiği
  /// hücre; tahtanın dışındaysa `null`.
  math.Point<int>? cellAt(Offset screen, {double y = 0}) {
    final u = (screen.dx - _offset.dx) / _scale;
    final v = -(screen.dy - _offset.dy) / _scale;
    final dir = _fwd + const _V(1, 0, 0) * u + _up * v;
    if (dir.y.abs() < 1e-9) return null;
    final t = (y - _cam.y) / dir.y;
    if (t <= 0) return null;
    final p = _cam + dir * t;
    final col = (p.x + n / 2).floor();
    final row = (n / 2 - p.z).floor();
    if (col < 0 || col >= n || row < 0 || row >= n) return null;
    return math.Point<int>(col, row);
  }

  /// Dokunulan tren: önce tren tepesi yüksekliğinde (yan yüze dokunuş da
  /// sayılsın), sonra zeminde arar.
  MetroLineTrain? trainAt(MetroLineController controller, Offset screen) {
    for (final y in <double>[_trainTop, _trainTop * 0.5, 0]) {
      final cell = cellAt(screen, y: y);
      if (cell == null) continue;
      final train = controller.trainAt(cell);
      if (train != null) return train;
    }
    return null;
  }
}

/// Metro Hattı tahtası: eğik kameradan 3B depo platformu ve kutu vagonlar.
class MetroLineBoardPainter extends CustomPainter {
  MetroLineBoardPainter({
    required this.controller,
    required this.accent,
    required this.departingTrain,
    required this.departingSize,
    required this.departureProgress,
    required this.blockedTrainId,
    required this.blockedGlow,
    required this.boardSize,
    required this.trains,
    this.hintTrainId,
    this.drop,
    this.bumpTrainId,
    this.bumpOffset = 0,
    this.hitTrainId,
    this.hitShift = Offset.zero,
  });

  /// Önü kapalı trene dokunulunca: tren yolu boyunca [bumpOffset] hücre
  /// ilerler, çarptığı tren ([hitTrainId]) [hitShift] kadar sarsılır.
  final int? bumpTrainId;
  final double bumpOffset;
  final int? hitTrainId;
  final Offset hitShift;

  final MetroLineController controller;

  /// Çizilen tahtanın boyu ve üstündeki trenler. Bölüm geçişinde eski
  /// ada (boş, yalnız son çıkan tren) çizilebilsin diye controller'dan
  /// bağımsız.
  final int boardSize;
  final List<MetroLineTrain> trains;
  final int? hintTrainId;

  /// Bölüm girişinde trenin havadan inişi: sıradaki trenin yüksekliği
  /// (hücre) ve görünürlüğü. `null` ise hepsi yerinde.
  final (double, double) Function(int index)? drop;
  final Color accent;
  final MetroLineTrain? departingTrain;
  final int departingSize;
  final double departureProgress;
  final int? blockedTrainId;

  /// Kırmızı uyarı parıltısının gücü (0–1).
  final double blockedGlow;

  late MetroLineBoardProjection _pj;
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Path _path = Path();

  /// Işık sol üstten, biraz önden.
  static final _V _light = const _V(-0.45, 0.85, -0.3).unit;

  // Vagon ölçüleri (hücre biriminde): alt gövde ve üstte daha dar çatı
  // katı. Hücre boyundan kısa: vagonlar arasında körük boşluğu kalır.
  static const double _carLen = 0.8;
  static const double _carW = 0.54;
  static const double _carBottom = 0.07;
  static const double _bodyTop = 0.44;
  static const double _roofW = 0.42;
  static const double _roofTop = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final n = boardSize;
    _pj = MetroLineBoardProjection(n, size);
    _paintSlab(canvas, n);

    // Bütün vagonları topla, kameradan uzaktan yakına çiz.
    final cars = <_Car>[];
    for (var i = 0; i < trains.length; i++) {
      final (lift, alpha) = drop?.call(i) ?? (0.0, 1.0);
      if (alpha <= 0) continue;
      final train = trains[i];
      _collectCars(
        cars,
        train,
        n,
        train.id == bumpTrainId ? bumpOffset : 0,
        alpha,
        extraLift: lift,
        shift: train.id == hitTrainId ? hitShift : Offset.zero,
      );
    }
    final leaving = departingTrain;
    if (leaving != null) {
      final route = _route(leaving, departingSize);
      final body = (leaving.carCount - 1).toDouble();
      final travel = _length(route) - body;
      _collectCars(
        cars,
        leaving,
        departingSize,
        Curves.easeInCubic.transform(departureProgress) * travel,
        1,
      );
    }

    // İpucu ve uyarı: trenin altında, zeminde parlayan hücreler.
    for (final train in trains) {
      final hinted = train.id == hintTrainId;
      final blocked = train.id == blockedTrainId ? blockedGlow : 0.0;
      if (!hinted && blocked <= 0) continue;
      final color = hinted
          ? AppColors.warning.withValues(alpha: 0.55)
          : AppColors.danger.withValues(alpha: 0.75 * blocked);
      for (final c in train.cells) {
        _groundQuad(canvas, c.x.toDouble(), c.y.toDouble(), 0.02, 0.98, color);
      }
    }

    // Gölgeler önce, hepsi zeminde.
    for (final car in cars) {
      _shadow(canvas, car);
    }
    final cam = _pj._camera;
    cars.sort((a, b) {
      final da = (_pj._world(a.col, a.row) - cam).length;
      final db = (_pj._world(b.col, b.row) - cam).length;
      return db.compareTo(da);
    });
    for (final car in cars) {
      _paintCar(canvas, car);
    }
    _decor(canvas, n, front: true);
  }

  // ------------------------------------------------------------ zemin

  /// Platform: denizde yüzen sevimli bir ada. Pastel kareli zemin,
  /// çevresinde çimenli kenar, yanlarda çimen–toprak–taş katmanları;
  /// suda gölgesi ve dalga halkaları.
  void _paintSlab(Canvas canvas, int n) {
    final h = n / 2;
    final o = h + MetroLineBoardProjection._rim;
    const s = MetroLineBoardProjection._slab;

    // Suya düşen gölge ve dalga halkaları.
    _poly(canvas, <_V>[
      _V(-o - 0.3, -s, -o - 0.45),
      _V(o + 0.45, -s, -o - 0.45),
      _V(o + 0.45, -s, o + 0.2),
      _V(-o - 0.3, -s, o + 0.2),
    ], const Color(0x33102030));
    for (var k = 1; k <= 3; k++) {
      final m = o + 0.25 * k;
      _path
        ..reset()
        ..addPolygon(<Offset>[
          _pj._project(_V(-m, -s, -m)),
          _pj._project(_V(m, -s, -m)),
          _pj._project(_V(m, -s, m)),
          _pj._project(_V(-m, -s, m)),
        ], true);
      _stroke
        ..color = Colors.white.withValues(alpha: 0.28 / k)
        ..strokeWidth = 1.5;
      canvas.drawPath(_path, _stroke);
    }

    // Yan yüzler katman katman: kameradan görünen ön ve iki yan.
    void side(_V a, _V b, double shade) {
      // a → b üst kenar boyunca; katmanlar yukarıdan aşağı.
      const layers = <(double, double, Color)>[
        (0, 0.14, Color(0xFF7CC35A)),
        (0.14, 0.5, Color(0xFFB9825A)),
        (0.5, s, Color(0xFF8E7A6E)),
      ];
      for (final (top, bottom, color) in layers) {
        _poly(canvas, <_V>[
          a + _V(0, -bottom, 0),
          b + _V(0, -bottom, 0),
          b + _V(0, -top, 0),
          a + _V(0, -top, 0),
        ], _lit(color, shade));
      }
      // Toprakta çakıllar.
      _fill.color = _lit(const Color(0xFFD7B08A), shade);
      for (var k = 0; k < 7; k++) {
        final t = (k + 0.5) / 7;
        final p = a + (b - a) * t + _V(0, -0.24 - (k % 3) * 0.08, 0);
        canvas.drawCircle(_pj._project(p), 1.6, _fill);
      }
      // Çimen sarkıntısı: üst kenarda yuvarlak tutamlar.
      _fill.color = _lit(const Color(0xFF8ED46A), shade);
      for (var k = 0; k <= 10; k++) {
        final p = a + (b - a) * (k / 10) + _V(0, -0.12, 0);
        canvas.drawCircle(_pj._project(p), 2.6, _fill);
      }
    }

    side(_V(-o, 0, -o), _V(o, 0, -o), 1.0);
    side(_V(-o, 0, o), _V(-o, 0, -o), 0.85);
    side(_V(o, 0, -o), _V(o, 0, o), 0.7);

    // Çimenli üst yüz (kenar) ve hücrelerin altındaki koyu çerçeve.
    _poly(canvas, <_V>[
      _V(-o, 0, -o),
      _V(o, 0, -o),
      _V(o, 0, o),
      _V(-o, 0, o),
    ], const Color(0xFF8ED46A));
    final b = h + 0.06;
    _poly(canvas, <_V>[
      _V(-b, 0.001, -b),
      _V(b, 0.001, -b),
      _V(b, 0.001, b),
      _V(-b, 0.001, b),
    ], const Color(0xFFCDBB97));

    // Zemin plakaları: krem ve nane kareli; uzaktakiler hafif koyu.
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final light = (row + col).isEven;
        final base = light ? const Color(0xFFF7EEDA) : const Color(0xFFDDEFD9);
        _groundQuad(
          canvas,
          col.toDouble(),
          row.toDouble(),
          0.03,
          0.97,
          Color.lerp(base, const Color(0xFFB8A98E), row / n * 0.25)!,
        );
      }
    }

    // Raylar ve traversler: ahşap traversler, koyu çelik raylar.
    const gauge = 0.19;
    final tie = Paint()
      ..color = const Color(0x66A57C55)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    _stroke
      ..color = const Color(0x997B6B5C)
      ..strokeWidth = 1.5;
    for (var i = 0; i < n; i++) {
      for (var t = 0; t < n * 2; t++) {
        final along = t * 0.5 - 0.25;
        canvas.drawLine(
          _pj._project(_pj._world(along, i - gauge)),
          _pj._project(_pj._world(along, i + gauge)),
          tie,
        );
        canvas.drawLine(
          _pj._project(_pj._world(i - gauge, along)),
          _pj._project(_pj._world(i + gauge, along)),
          tie,
        );
      }
      for (final g in <double>[-gauge, gauge]) {
        canvas.drawLine(
          _pj._project(_pj._world(-0.5, i + g)),
          _pj._project(_pj._world(n - 0.5, i + g)),
          _stroke,
        );
        canvas.drawLine(
          _pj._project(_pj._world(i + g, -0.5)),
          _pj._project(_pj._world(i + g, n - 0.5)),
          _stroke,
        );
      }
    }

    // Arka kenar süsleri (trenlerin arkasında kalır).
    _decor(canvas, n, front: false);
  }

  /// Kenar süsleri: köşelerde ağaçlar, kenar ortalarında fenerler,
  /// ön ve yan kenarlarda laleler. Arkadakiler trenlerden önce, öndekiler
  /// sonra çizilir.
  void _decor(Canvas canvas, int n, {required bool front}) {
    final h = n / 2;
    final m = h + MetroLineBoardProjection._rim / 2;
    bool isFront(double z) => z < 0;

    // Laleler.
    const tulips = <Color>[
      Color(0xFFE53935),
      Color(0xFFFFC107),
      Color(0xFFEC407A),
      Color(0xFFFFFFFF),
      Color(0xFFAB47BC),
    ];
    var k = 0;
    for (var t = -h + 0.5; t < h; t += 0.7) {
      for (final p in <_V>[
        _V(t, 0, -m),
        _V(-m, 0, t),
        _V(m, 0, t),
        _V(t, 0, m),
      ]) {
        if (isFront(p.z) != front) continue;
        k++;
        final stem = _pj._project(p);
        final bloom = _pj._project(p + const _V(0, 0.14, 0));
        _stroke
          ..color = const Color(0xFF4E8B3A)
          ..strokeWidth = 1.2;
        canvas.drawLine(stem, bloom, _stroke);
        _fill.color = tulips[k % tulips.length];
        canvas.drawOval(
          Rect.fromCenter(center: bloom, width: 5, height: 6.5),
          _fill,
        );
      }
    }

    // Fenerler: kenar ortalarında.
    for (final p in <_V>[
      _V(0, 0, -m),
      _V(-m, 0, 0),
      _V(m, 0, 0),
      _V(0, 0, m),
    ]) {
      if (isFront(p.z) != front) continue;
      final foot = _pj._project(p);
      final top = _pj._project(p + const _V(0, 0.7, 0));
      _stroke
        ..color = const Color(0xFF3B4650)
        ..strokeWidth = 2;
      canvas.drawLine(foot, top, _stroke);
      _fill.shader = RadialGradient(
        colors: <Color>[const Color(0x99FFE2A0), const Color(0x00FFE2A0)],
      ).createShader(Rect.fromCircle(center: top, radius: 16));
      canvas.drawCircle(top, 16, _fill);
      _fill.shader = null;
      _fill.color = const Color(0xFFFFF1C4);
      canvas.drawCircle(top, 3.5, _fill);
    }

    // Ağaçlar: köşelerde, yuvarlak taç.
    for (final p in <_V>[
      _V(-m, 0, -m),
      _V(m, 0, -m),
      _V(-m, 0, m),
      _V(m, 0, m),
    ]) {
      if (isFront(p.z) != front) continue;
      final foot = _pj._project(p);
      final crown = _pj._project(p + const _V(0, 0.95, 0));
      final r = (foot - crown).distance * 0.42;
      _stroke
        ..color = const Color(0xFF7A5034)
        ..strokeWidth = math.max(2.5, r * 0.22);
      canvas.drawLine(foot, Offset.lerp(foot, crown, 0.8)!, _stroke);
      _fill.color = const Color(0xFF4CAF50);
      canvas.drawCircle(crown, r, _fill);
      _fill.color = const Color(0xFF81C784);
      canvas.drawCircle(crown.translate(-r * 0.3, -r * 0.3), r * 0.55, _fill);
      _fill.color = const Color(0xFFE57373);
      for (final d in <Offset>[
        Offset(r * 0.35, -r * 0.1),
        Offset(-r * 0.1, r * 0.4),
      ]) {
        canvas.drawCircle(crown + d, math.max(1.5, r * 0.1), _fill);
      }
    }
  }

  void _groundQuad(
    Canvas canvas,
    double col,
    double row,
    double inset,
    double size,
    Color color,
  ) {
    final a = col - 0.5 + inset;
    final b = col - 0.5 + size;
    final c = row - 0.5 + inset;
    final d = row - 0.5 + size;
    _poly(canvas, <_V>[
      _pj._world(a, c, 0.002),
      _pj._world(b, c, 0.002),
      _pj._world(b, d, 0.002),
      _pj._world(a, d, 0.002),
    ], color);
  }

  void _poly(Canvas canvas, List<_V> pts, Color color) {
    _path
      ..reset()
      ..addPolygon(<Offset>[for (final p in pts) _pj._project(p)], true);
    _fill.color = color;
    canvas.drawPath(_path, _fill);
  }

  // ------------------------------------------------------------- trenler

  /// Trenin izleyeceği yol (hücre koordinatında): kuyruktan başa, oradan
  /// tahtanın dışına. Vagonlar bu yolda yay uzunluğuyla yürür; çıkarken
  /// başın döndüğü köşelerden geçerler.
  List<Offset> _route(MetroLineTrain train, int boardSize) {
    final points = <Offset>[
      for (final c in train.cells.reversed)
        Offset(c.x.toDouble(), c.y.toDouble()),
    ];
    final step = train.direction.delta;
    final head = train.head;
    final corridor = train.corridor(boardSize).length;
    for (var i = 1; i <= corridor + train.carCount + 2; i++) {
      points.add(
        Offset(
          (head.x + step.x * i).toDouble(),
          (head.y + step.y * i).toDouble(),
        ),
      );
    }
    return points;
  }

  double _length(List<Offset> pts) {
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
    }
    return total;
  }

  (Offset, Offset) _poseAt(List<Offset> pts, double distance) {
    var walked = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final len = (b - a).distance;
      if (len <= 0) continue;
      if (distance <= walked + len) {
        final t = ((distance - walked) / len).clamp(0.0, 1.0);
        return (Offset.lerp(a, b, t)!, (b - a) / len);
      }
      walked += len;
    }
    final a = pts[pts.length - 2];
    final b = pts.last;
    final len = (b - a).distance;
    return (b, len > 0 ? (b - a) / len : const Offset(1, 0));
  }

  void _collectCars(
    List<_Car> out,
    MetroLineTrain train,
    int boardSize,
    double offset,
    double alpha, {
    double extraLift = 0,
    Offset shift = Offset.zero,
  }) {
    final route = _route(train, boardSize);
    final body = (train.carCount - 1).toDouble();
    final color = metroLineColors[train.lineIndex % metroLineColors.length];
    final n = this.boardSize;
    for (var i = train.carCount - 1; i >= 0; i--) {
      final at = offset + body - i;
      if (at < 0) continue;
      final (rawPos, fwd) = _poseAt(route, at);
      final pos = rawPos + shift;
      // Önündeki vagona bağlayan körük: iki vagonun arasında, yol üstünde.
      if (i > 0) {
        final (rawCp, cf) = _poseAt(route, at + 0.5);
        final cp = rawCp + shift;
        out.add(
          _Car(
            col: cp.dx,
            row: cp.dy,
            dirCol: cf.dx,
            dirRow: cf.dy,
            color: color,
            isHead: false,
            isTail: false,
            alpha: _fadeAt(cp, n) * alpha,
            lift: extraLift,
            connector: true,
          ),
        );
      }
      final outside = _outside(pos, n);
      final fade = _fadeAt(pos, n) * alpha;
      if (fade <= 0.01) continue;
      out.add(
        _Car(
          col: pos.dx,
          row: pos.dy,
          dirCol: fwd.dx,
          dirRow: fwd.dy,
          color: color,
          isHead: i == 0,
          isTail: i == train.carCount - 1,
          alpha: fade,
          lift: (outside > 0 ? -outside * 0.25 : 0) + extraLift,
        ),
      );
    }
  }

  /// Tahtanın kenarından ne kadar dışarıda (hücre).
  static double _outside(Offset pos, int n) => math.max(
    math.max(-0.5 - pos.dx, pos.dx - (n - 0.5)),
    math.max(-0.5 - pos.dy, pos.dy - (n - 0.5)),
  );

  /// Tahtanın kenarını geçen vagon karanlığa karışarak kaybolur.
  static double _fadeAt(Offset pos, int n) =>
      (1 - _outside(pos, n) / 1.6).clamp(0.0, 1.0);

  /// Kutunun dünya köşeleri: alt dört, üst dört (arka-sol, arka-sağ,
  /// ön-sağ, ön-sol). [noseBack] üst ön kenarı geri çeker: eğimli burun.
  List<_V> _box(
    _Car car,
    double len,
    double width,
    double y0,
    double y1, {
    double noseBack = 0,
    double tailBack = 0,
    double shift = 0,
  }) {
    final center = _pj._world(car.col, car.row, car.lift);
    // Satır aşağı doğru artar, dünya z'si yukarı: yön z'de ters.
    final f = _V(car.dirCol, 0, -car.dirRow).unit;
    final s = _V(f.z, 0, -f.x); // sağ
    final halfL = len / 2;
    final halfW = width / 2;
    _V p(double along, double side, double y) =>
        center + f * (along + shift) + s * side + _V(0, y, 0);
    return <_V>[
      p(-halfL, -halfW, y0),
      p(-halfL, halfW, y0),
      p(halfL, halfW, y0),
      p(halfL, -halfW, y0),
      p(-halfL + tailBack, -halfW, y1),
      p(-halfL + tailBack, halfW, y1),
      p(halfL - noseBack, halfW, y1),
      p(halfL - noseBack, -halfW, y1),
    ];
  }

  List<_V> _corners(_Car car) =>
      _box(car, _carLen, _carW, _carBottom, _bodyTop);

  void _shadow(Canvas canvas, _Car car) {
    if (car.lift < -0.05 || car.connector) return;
    final c = _corners(car);
    const off = _V(0.07, 0, -0.06);
    _path
      ..reset()
      ..addPolygon(<Offset>[
        for (final i in <int>[0, 1, 2, 3])
          _pj._project(_V(c[i].x, 0.003, c[i].z) + off),
      ], true);
    final air = (car.lift / 4).clamp(0.0, 0.75);
    _fill.color = Colors.black.withValues(alpha: 0.38 * car.alpha * (1 - air));
    canvas.drawPath(_path, _fill);
  }

  void _paintCar(Canvas canvas, _Car car) {
    if (car.connector) {
      _paintBox(
        canvas,
        car,
        _box(car, 0.34, 0.32, 0.12, 0.4),
        const Color(0xFF1A2028),
        const Color(0xFF232A33),
        details: false,
      );
      return;
    }
    final body = car.color;
    // Alt gövde: hat renginde, lokomotifte eğimli ön.
    _paintBox(
      canvas,
      car,
      _box(
        car,
        _carLen,
        _carW,
        _carBottom,
        _bodyTop,
        noseBack: car.isHead ? 0.1 : 0,
      ),
      body,
      body,
    );
    // Çatı katı: daha dar, açık gümüş; lokomotifte camlı burun geride.
    _paintBox(
      canvas,
      car,
      _box(
        car,
        car.isHead ? _carLen - 0.22 : _carLen - 0.06,
        _roofW,
        _bodyTop,
        _roofTop,
        noseBack: car.isHead ? 0.08 : 0,
        shift: car.isHead ? -0.1 : 0,
      ),
      Color.lerp(body, Colors.white, 0.55)!,
      Color.lerp(body, Colors.white, 0.7)!,
      roof: true,
    );
  }

  void _paintBox(
    Canvas canvas,
    _Car car,
    List<_V> c,
    Color sideColor,
    Color topColor, {
    bool details = true,
    bool roof = false,
  }) {
    final center = (c[0] + c[6]) * 0.5;
    final cam = _pj._camera;
    // Yüzler: (köşe indeksleri alt-sol, alt-sağ, üst-sağ, üst-sol), tür.
    final faces = <(List<int>, _Face)>[
      (<int>[3, 0, 4, 7], _Face.left),
      (<int>[1, 2, 6, 5], _Face.right),
      (<int>[2, 3, 7, 6], _Face.front),
      (<int>[0, 1, 5, 4], _Face.back),
      (<int>[4, 5, 6, 7], _Face.top),
    ];
    for (final (idx, kind) in faces) {
      final pts = <_V>[for (final i in idx) c[i]];
      final fc = (pts[0] + pts[1] + pts[2] + pts[3]) * 0.25;
      final normal = _normal(pts, fc - center);
      if (normal.dot(cam - fc) <= 0) continue;
      final shade = 0.62 + 0.45 * math.max(0.0, normal.dot(_light));
      final base = kind == _Face.top ? topColor : sideColor;
      final q = <Offset>[for (final p in pts) _pj._project(p)];
      _fill.color = _a(_lit(base, shade), car.alpha);
      _path
        ..reset()
        ..addPolygon(q, true);
      canvas.drawPath(_path, _fill);
      if (details) {
        if (roof) {
          _roofDetails(canvas, car, kind, q);
        } else {
          _faceDetails(canvas, car, kind, q, shade);
        }
      }
      _stroke
        ..color = _a(const Color(0xFF0B1118), 0.5 * car.alpha)
        ..strokeWidth = 1;
      canvas.drawPath(_path, _stroke);
    }
  }

  /// Çatı katı: yanlarda pencere bandı, üstte klima ve (lokomotifte) ok,
  /// önde camlı burun.
  void _roofDetails(Canvas canvas, _Car car, _Face kind, List<Offset> q) {
    final a = car.alpha;
    switch (kind) {
      case _Face.left:
      case _Face.right:
        // Üst pencere bandı: içeriden ışık.
        _faceRect(
          canvas,
          q,
          0.06,
          0.94,
          0.1,
          0.9,
          _a(const Color(0xFF16202B), a),
        );
        _faceRect(
          canvas,
          q,
          0.1,
          0.9,
          0.25,
          0.75,
          _a(const Color(0xCCFFE6B4), a),
        );
        for (final u in <double>[0.36, 0.64]) {
          _stroke
            ..color = _a(const Color(0xFF16202B), a)
            ..strokeWidth = 1.2;
          canvas.drawLine(_uv(q, u, 0.1), _uv(q, u, 0.9), _stroke);
        }
      case _Face.front:
        if (car.isHead) {
          _faceRect(
            canvas,
            q,
            0.06,
            0.94,
            0.08,
            0.95,
            _a(const Color(0xFF16202B), a),
          );
          _faceRect(
            canvas,
            q,
            0.15,
            0.45,
            0.55,
            0.85,
            _a(const Color(0x55FFFFFF), a),
          );
        }
      case _Face.back:
        if (car.isTail) {
          _faceRect(
            canvas,
            q,
            0.12,
            0.88,
            0.15,
            0.9,
            _a(const Color(0xFF16202B), a),
          );
        }
      case _Face.top:
        // Üst yüz köşeleri: arka-sol, arka-sağ, ön-sağ, ön-sol.
        _faceRect(
          canvas,
          q,
          0.25,
          0.75,
          0.15,
          0.42,
          _a(const Color(0xCC2B3440), a),
        );
        if (car.isHead) {
          _path
            ..reset()
            ..addPolygon(<Offset>[
              _uv(q, 0.22, 0.5),
              _uv(q, 0.5, 0.95),
              _uv(q, 0.78, 0.5),
            ], true);
          _fill.color = _a(Colors.white, a);
          canvas.drawPath(_path, _fill);
          _stroke
            ..color = _a(const Color(0xE60B1118), a)
            ..strokeWidth = 1.4;
          canvas.drawPath(_path, _stroke);
        }
    }
  }

  /// Yüz normali: dörtgenin iki köşegeninin çarpımı, dışa çevrilmiş.
  _V _normal(List<_V> p, _V outward) {
    final a = p[2] - p[0];
    final b = p[3] - p[1];
    var n = _V(
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x,
    ).unit;
    if (n.dot(outward) < 0) n = n * -1;
    return n;
  }

  /// Dörtgen yüzde (u: alttan sağa, v: alttan yukarı) noktası.
  static Offset _uv(List<Offset> q, double u, double v) {
    final bottom = Offset.lerp(q[0], q[1], u)!;
    final top = Offset.lerp(q[3], q[2], u)!;
    return Offset.lerp(bottom, top, v)!;
  }

  void _faceRect(
    Canvas canvas,
    List<Offset> q,
    double u0,
    double u1,
    double v0,
    double v1,
    Color color,
  ) {
    _path
      ..reset()
      ..addPolygon(<Offset>[
        _uv(q, u0, v0),
        _uv(q, u1, v0),
        _uv(q, u1, v1),
        _uv(q, u0, v1),
      ], true);
    _fill.color = color;
    canvas.drawPath(_path, _fill);
  }

  void _faceDetails(
    Canvas canvas,
    _Car car,
    _Face kind,
    List<Offset> q,
    double shade,
  ) {
    final a = car.alpha;
    final dark = _a(_lit(const Color(0xFF1B232D), shade), a);
    switch (kind) {
      case _Face.left:
      case _Face.right:
        // Alt gövde: koyu etek, üstünde beyaz ince şerit, kapılar.
        _faceRect(canvas, q, 0.0, 1.0, 0.0, 0.22, dark);
        _faceRect(
          canvas,
          q,
          0.0,
          1.0,
          0.62,
          0.72,
          _a(const Color(0xE6FFFFFF), a),
        );
        for (final u in <double>[0.3, 0.7]) {
          _faceRect(
            canvas,
            q,
            u - 0.07,
            u + 0.07,
            0.22,
            0.98,
            _a(_lit(car.color, shade * 0.8), a),
          );
          _stroke
            ..color = _a(const Color(0x880B1118), a)
            ..strokeWidth = 1;
          canvas.drawLine(_uv(q, u, 0.22), _uv(q, u, 0.98), _stroke);
        }
      case _Face.front:
        if (car.isHead) {
          // Burun: farlar ve beyaz şerit.
          _faceRect(
            canvas,
            q,
            0.0,
            1.0,
            0.62,
            0.72,
            _a(const Color(0xE6FFFFFF), a),
          );
          _fill.color = _a(const Color(0xFFFFF2CC), a);
          final r = math.max(1.5, (q[1] - q[0]).distance * 0.08);
          for (final u in <double>[0.2, 0.8]) {
            canvas.drawCircle(_uv(q, u, 0.4), r, _fill);
          }
          _faceRect(canvas, q, 0.0, 1.0, 0.0, 0.2, dark);
        } else {
          _faceRect(canvas, q, 0.0, 1.0, 0.0, 0.22, dark);
        }
      case _Face.back:
        _faceRect(canvas, q, 0.0, 1.0, 0.0, 0.22, dark);
        if (car.isTail) {
          _fill.color = _a(const Color(0xFFFF5A4A), a);
          final r = math.max(1.2, (q[1] - q[0]).distance * 0.07);
          for (final u in <double>[0.2, 0.8]) {
            canvas.drawCircle(_uv(q, u, 0.45), r, _fill);
          }
        }
      case _Face.top:
        break;
    }
  }

  static Color _a(Color c, double alpha) =>
      c.withValues(alpha: c.a * alpha.clamp(0.0, 1.0));

  static Color _lit(Color base, double light) {
    final l = light.clamp(0.0, 1.4);
    if (l <= 1) return Color.lerp(Colors.black, base, l)!;
    return Color.lerp(base, Colors.white, (l - 1) * 0.6)!;
  }

  @override
  bool shouldRepaint(MetroLineBoardPainter oldDelegate) => true;
}

enum _Face { left, right, front, back, top }

class _Car {
  const _Car({
    required this.col,
    required this.row,
    required this.dirCol,
    required this.dirRow,
    required this.color,
    required this.isHead,
    required this.isTail,
    required this.alpha,
    required this.lift,
    this.connector = false,
  });

  /// Vagonlar arasındaki körük mü?
  final bool connector;

  final double col;
  final double row;
  final double dirCol;
  final double dirRow;
  final Color color;
  final bool isHead;
  final bool isTail;
  final double alpha;

  /// Tahtadan çıkınca hafifçe aşağı iner (platformdan iniyor gibi).
  final double lift;
}
