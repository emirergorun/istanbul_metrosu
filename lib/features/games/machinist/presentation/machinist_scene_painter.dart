import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../application/machinist_controller.dart';
import '../domain/machinist_rules.dart';
import 'machinist_textures.dart';

/// Makinist sahnesi: trenin arkasından ve biraz üstünden bakan kamera.
///
/// Motor yok; her kare elle yansıtılan bir sahte-3B. Dünya ekseni: z ray
/// boyunca ileri, x sağa, y yukarı (m). Tünel ve istasyon holü birer kesit
/// (profil) olarak tanımlı; profil z boyunca dilimlere bölünüp uzaktan
/// yakına boyanır (ressam algoritması). Her dilimin üstüne o dilime düşen
/// raylar, traversler ve nesneler biner; tren en son çizilir.
///
/// Kıvrım: ray yanal olarak [trackOffsetAt] kadar kayar. Kamera trenin
/// ortasına bakacak biçimde döndürülmüş sayılır; küçük açıda dönme, yanal
/// kaydırma ile yaklaşık olarak yapılıyor.
class MachinistScenePainter extends CustomPainter {
  MachinistScenePainter({
    required this.controller,
    required this.lineColor,
    required this.lineCode,
    required this.destination,
    Listenable? frame,
  }) : super(repaint: frame ?? controller);

  final MachinistController controller;
  final Color lineColor;
  final String lineCode;
  final String destination;

  // ------------------------------------------------------------ kamera

  static const double _camX = 3.1;
  static const double _camY = 4.85;
  static const double _pitch = 0.17;
  static const double _near = 0.8;
  static const double _far = 230;

  // ---------------------------------------------------------- kesitler

  /// Tek hatlı tünel: ortası (0.5, 1.3), yarıçapı 5.2 olan kemer; solda
  /// bakım yürüme yolu, sağda kablo kanalı. Gerçeğinden geniş: kamera
  /// trenin sağ omzunun üstünde duruyor ve duvara girmemeli.
  static const double _tunnelR = 5.2;
  static const double _tunnelCx = 0.5;
  static const double _tunnelCy = 1.3;

  static final List<_Seg> _tunnelProfile = _buildTunnelProfile();
  static final List<Offset> _tunnelOutline = _outline(_tunnelProfile);
  static final List<_Seg> _hallProfile = _buildHallProfile();
  static final List<Offset> _hallOutline = _outline(_hallProfile);

  static List<_Seg> _buildTunnelProfile() {
    final segs = <_Seg>[
      const _Seg(Offset(-2.6, 0), Offset(3.2, 0), _Kind.trackbed),
      const _Seg(Offset(3.2, 0), Offset(3.2, 0.6), _Kind.concrete),
    ];
    final a0 = math.asin((0.6 - _tunnelCy) / _tunnelR);
    final a1 = math.pi - math.asin((0.95 - _tunnelCy) / _tunnelR);
    final benchX = _tunnelCx + _tunnelR * math.cos(a0);
    segs.add(_Seg(const Offset(3.2, 0.6), Offset(benchX, 0.6), _Kind.bench));
    const steps = 16;
    Offset? prev;
    for (var i = 0; i <= steps; i++) {
      final a = a0 + (a1 - a0) * i / steps;
      final p = Offset(
        _tunnelCx + _tunnelR * math.cos(a),
        _tunnelCy + _tunnelR * math.sin(a),
      );
      if (prev != null) segs.add(_Seg(prev, p, _Kind.lining));
      prev = p;
    }
    segs
      ..add(_Seg(prev!, const Offset(-2.6, 0.95), _Kind.walkway))
      ..add(const _Seg(Offset(-2.6, 0.95), Offset(-2.6, 0), _Kind.concrete));
    return segs;
  }

  /// İstasyon holü: solda hat duvarı (istasyon adı panoları), sağda yan
  /// peron, üstte basık tonoz. Şişhane / Taksim'in tonozlu hollerinden.
  static const double _platformY = 1.05;
  static const double _platformEdge = 1.62;
  static const double _hallLeft = -4.8;
  static const double _hallRight = 9.5;
  static const double _vaultBase = 3.2;

  static List<_Seg> _buildHallProfile() {
    final segs = <_Seg>[
      const _Seg(
        Offset(_hallLeft, 0),
        Offset(_platformEdge, 0),
        _Kind.trackbed,
      ),
      const _Seg(
        Offset(_platformEdge, 0),
        Offset(_platformEdge, _platformY),
        _Kind.platformFace,
      ),
      const _Seg(
        Offset(_platformEdge, _platformY),
        Offset(2.25, _platformY),
        _Kind.tactile,
      ),
      const _Seg(
        Offset(2.25, _platformY),
        Offset(_hallRight, _platformY),
        _Kind.granite,
      ),
      const _Seg(
        Offset(_hallRight, _platformY),
        Offset(_hallRight, _vaultBase),
        _Kind.hallWall,
      ),
    ];
    const cx = (_hallLeft + _hallRight) / 2;
    const rx = (_hallRight - _hallLeft) / 2;
    const ry = 4.1;
    const steps = 14;
    Offset prev = const Offset(_hallRight, _vaultBase);
    for (var i = 1; i <= steps; i++) {
      final a = math.pi * i / steps;
      final p = Offset(cx + rx * math.cos(a), _vaultBase + ry * math.sin(a));
      segs.add(_Seg(prev, p, _Kind.vault));
      prev = p;
    }
    segs.add(
      const _Seg(
        Offset(_hallLeft, _vaultBase),
        Offset(_hallLeft, 0),
        _Kind.trackWall,
      ),
    );
    return segs;
  }

  static List<Offset> _outline(List<_Seg> segs) => <Offset>[
    for (final s in segs) s.a,
  ];

  /// Her kesit parçasının kesit boyunca başlangıç uzunluğu (m): doku u'su.
  static final List<double> _tunnelU = _uOffsets(_tunnelProfile);
  static final List<double> _hallU = _uOffsets(_hallProfile);

  static List<double> _uOffsets(List<_Seg> segs) {
    final out = <double>[];
    var u = 0.0;
    for (final s in segs) {
      out.add(u);
      u += (s.b - s.a).distance;
    }
    return out;
  }

  // ------------------------------------------------------------ durum

  late _Cam _cam;
  late List<MachinistStation> _stations;

  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Path _path = Path();

  static const Color _tunnelFog = Color(0xFF07080B);
  static const Color _hallFog = Color(0xFF3A3F46);

  /// Bu karenin tren ön ucu ve saati: fizik adımından ileri kestirilmiş.
  double _front = 0;
  double _t = 0;

  @override
  void paint(Canvas canvas, Size size) {
    _stations = controller.stations;
    _front = controller.renderPosition;
    _t = controller.renderClock;
    final front = _front;
    final speed = controller.speed;

    final camBack = 7.5 + speed * 0.12;
    final camZ = front - MachinistRules.trainLength - camBack;
    final lookZ = front - MachinistRules.trainLength * 0.35;
    final base = trackOffsetAt(_stations, camZ);
    final slope = (trackOffsetAt(_stations, lookZ) - base) / (lookZ - camZ);
    // Hızla hafif titreşim; durunca susar.
    final shake = speed <= 0.1 ? 0.0 : math.sin(_t * 23) * 0.012 * (speed / 20);

    final f = math.min(size.width * 0.92, size.height * 0.62);
    _cam = _Cam(
      z: camZ,
      x: _camX,
      y: _camY + shake,
      base: base,
      slope: slope,
      // Kamera hafif sola döner: trenin ortası ekranın ortasına gelsin.
      yaw: _camX / (lookZ - camZ),
      cosP: math.cos(_pitch),
      sinP: math.sin(_pitch),
      f: f,
      cx: size.width / 2,
      cy: size.height * 0.40,
      stations: _stations,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, _fill..color = _tunnelFog);

    final objects = _collectObjects(camZ)..sort((a, b) => b.z.compareTo(a.z));
    // Tren kendi arka ucunun hizasında çizilir: ondan uzak her şey önce,
    // yakın dilimler sonra. Peron tarafında trenin boyunca duran nesneler
    // (yolcu, DUR levhası) kamerayla tren arasında kalır; trenden sonra.
    final rear = front - MachinistRules.trainLength;
    final deferred = <_Obj>[];
    var trainDrawn = false;
    void emit(_Obj o) {
      if (!trainDrawn && o.x > 1.5 && o.z >= rear && o.z <= front + 1) {
        deferred.add(o);
      } else {
        o.draw(canvas);
      }
    }

    var next = 0;
    final cuts = _sliceCuts(camZ, rear);
    for (var i = cuts.length - 1; i > 0; i--) {
      final za = cuts[i - 1];
      final zb = cuts[i];
      if (!trainDrawn && zb <= rear + 1e-6) {
        _drawTrain(canvas);
        trainDrawn = true;
        for (final o in deferred) {
          o.draw(canvas);
        }
      }
      // Bu dilimin uzağındaki nesneler: dilimden önce.
      while (next < objects.length && objects[next].z >= zb) {
        emit(objects[next++]);
      }
      _drawBoundaryFace(canvas, zb);
      _drawSlice(canvas, za, zb);
      while (next < objects.length && objects[next].z >= za) {
        emit(objects[next++]);
      }
    }
    if (!trainDrawn) {
      _drawTrain(canvas);
      for (final o in deferred) {
        o.draw(canvas);
      }
    }
    canvas.restore();
  }

  // ----------------------------------------------------------- dilimler

  /// Dilim sınırları: yakında 1,5 m (tünel halkası), uzakta seyrek.
  /// Hol sınırları dilim sınırına eklenir ki kesit tam orada değişsin.
  List<double> _sliceCuts(double camZ, double trainRear) {
    final start = camZ + _near;
    final end = camZ + _far;
    final cuts = <double>[start, trainRear];
    var z = start;
    while (z < end) {
      final dz = z - camZ;
      if (dz < 18.75) {
        // Kameraya yakın dilimler derinlikle orantılı kısa: doku üçgene
        // afin sarılıyor; dilimin iki ucu arasındaki derinlik oranı büyürse
        // doku köşegende kırılıp zikzak çiziyordu.
        z += math.max(0.3, dz * 0.08);
        cuts.add(math.min(z, end));
        continue;
      }
      final step = dz < 45
          ? 1.5
          : dz < 110
          ? 3.0
          : 6.0;
      z = ((z / step).floor() + 1) * step;
      cuts.add(math.min(z, end));
    }
    for (final s in _stations) {
      for (final b in <double>[s.hallStart, s.hallEnd]) {
        if (b > start && b < end) cuts.add(b);
      }
    }
    cuts.sort();
    return cuts;
  }

  MachinistStation? _hallAt(double z) {
    for (final s in _stations) {
      if (z >= s.hallStart && z < s.hallEnd) return s;
    }
    return null;
  }

  /// İstasyon holünden tünele taşan ışık.
  double _hallSpill(double z) {
    var best = 0.0;
    for (final s in _stations) {
      final d = z < s.hallStart
          ? s.hallStart - z
          : z > s.hallEnd
          ? z - s.hallEnd
          : 0.0;
      best = math.max(best, math.exp(-d / 9));
    }
    return best;
  }

  /// Tünel lambası (12 m'de bir) etrafındaki aydınlık.
  double _lampLight(double z) {
    final m = ((z % 12) + 12) % 12;
    final d = m - 6;
    return math.exp(-d * d / 10);
  }

  /// Farların yola düşen ışığı.
  double _headlight(double z) {
    final d = z - _front;
    if (d < -1 || d > 60) return 0;
    return math.exp(-d / 22) * (d < 2 ? (d + 1) / 3 : 1);
  }

  void _drawSlice(Canvas canvas, double za, double zb) {
    final zm = (za + zb) / 2;
    final dz = zm - _cam.z;
    final hall = _hallAt(zm);
    final inHall = hall != null;
    final textures = MachinistTextures.ready;
    if (textures != null) {
      _drawShellTextured(canvas, textures, za, zb, inHall);
      final fog = 1 - math.exp(-dz / (inHall ? 140 : 55));
      final fogColor = inHall ? _hallFog : _tunnelFog;
      if (inHall) {
        _drawHallDecor(canvas, za, zb, fog);
      } else {
        _drawTunnelDecor(canvas, za, zb, fog, _lampLight(zm));
      }
      _drawTrack(canvas, za, zb, fog, fogColor, inHall, _headlight(zm));
      return;
    }
    final profile = inHall ? _hallProfile : _tunnelProfile;
    final fog = 1 - math.exp(-dz / (inHall ? 140 : 55));
    final fogColor = inHall ? _hallFog : _tunnelFog;
    final ring = (zm / 1.5).floor().isEven;
    final lamp = inHall ? 0.0 : _lampLight(zm);
    final spill = inHall ? 0.0 : _hallSpill(zm);
    final head = _headlight(zm);

    for (final seg in profile) {
      final a0 = _cam.project(seg.a.dx, seg.a.dy, za);
      final b0 = _cam.project(seg.b.dx, seg.b.dy, za);
      final b1 = _cam.project(seg.b.dx, seg.b.dy, zb);
      final a1 = _cam.project(seg.a.dx, seg.a.dy, zb);
      if (a0 == null || b0 == null || b1 == null || a1 == null) continue;

      var light = inHall ? _hallLight(seg) : 0.22;
      if (!inHall) {
        // Lamba sol üst duvarda: yakın yüzeyler daha çok aydınlanır.
        final side = seg.a.dx < 0 ? 1.0 : 0.55;
        light += lamp * 0.42 * side + spill * 0.75;
        if (seg.kind == _Kind.lining && ring) light *= 0.93;
      }
      if (seg.kind == _Kind.trackbed || seg.kind == _Kind.bench) {
        light += head * (inHall ? 0.25 : 0.9);
      }
      final base = _segColor(seg.kind);
      _fill.color = Color.lerp(_lit(base, light), fogColor, fog)!;
      _quad(canvas, a0, b0, b1, a1);
    }

    if (dz < 60) _drawRingJoints(canvas, za, inHall, fog, fogColor);
    if (inHall) {
      _drawHallDecor(canvas, za, zb, fog);
    } else {
      _drawTunnelDecor(canvas, za, zb, fog, lamp);
    }
    _drawTrack(canvas, za, zb, fog, fogColor, inHall, head);
  }

  /// Kesiti dokulu üçgenlerle çizer. Işık ve sis dilimin iki ucunda ayrı
  /// hesaplanıp köşe rengine yazılır: lamba havuzları ve far ışığı bant
  /// bant değil, yumuşak geçişle yayılır.
  void _drawShellTextured(
    Canvas canvas,
    MachinistTextures textures,
    double za,
    double zb,
    bool inHall,
  ) {
    final profile = inHall ? _hallProfile : _tunnelProfile;
    final us = inHall ? _hallU : _tunnelU;
    final envA = _env(za, inHall);
    final envB = _env(zb, inHall);
    // v ray boyunca; 60 metrede bir sarılır ki sayılar büyümesin (60 her
    // dokunun boyunun katı).
    final vz0 = ((za % 60) + 60) % 60;
    final vz1 = vz0 + (zb - za);
    _batches.clear();
    for (var i = 0; i < profile.length; i++) {
      final seg = profile[i];
      final a0 = _cam.project(seg.a.dx, seg.a.dy, za);
      final b0 = _cam.project(seg.b.dx, seg.b.dy, za);
      final b1 = _cam.project(seg.b.dx, seg.b.dy, zb);
      final a1 = _cam.project(seg.a.dx, seg.a.dy, zb);
      if (a0 == null || b0 == null || b1 == null || a1 == null) continue;
      final (tex, tint) = _material(seg.kind);
      final len = (seg.b - seg.a).distance;
      final u0 = us[i] * tex.pxPerMeterU;
      final u1 = (us[i] + len) * tex.pxPerMeterU;
      final v0 = vz0 * tex.pxPerMeterV;
      final v1 = vz1 * tex.pxPerMeterV;
      final ca = _vertexColor(seg, envA, inHall, tint);
      final cb = _vertexColor(seg, envB, inHall, tint);
      // Ekleme sırası korunur: kesitte önce gelen yüz önce çizilir.
      _batches
          .putIfAbsent(tex, _Batch.new)
          .add(a0, b0, b1, a1, u0, u1, v0, v1, ca, cb);
    }
    for (final entry in _batches.entries) {
      final b = entry.value;
      canvas.drawVertices(
        ui.Vertices(
          ui.VertexMode.triangles,
          b.positions,
          textureCoordinates: b.uvs,
          colors: b.colors,
        ),
        BlendMode.modulate,
        _texPaint..shader = textures.shaderFor(entry.key),
      );
    }
  }

  final Map<SurfaceTexture, _Batch> _batches = <SurfaceTexture, _Batch>{};
  final Paint _texPaint = Paint();

  (SurfaceTexture, double) _material(_Kind kind) => switch (kind) {
    _Kind.trackbed => (SurfaceTexture.trackbed, 1.0),
    _Kind.concrete => (SurfaceTexture.concrete, 1.0),
    _Kind.bench => (SurfaceTexture.concrete, 0.92),
    _Kind.lining => (SurfaceTexture.lining, 1.0),
    _Kind.walkway => (SurfaceTexture.walkway, 1.0),
    _Kind.platformFace => (SurfaceTexture.concrete, 0.6),
    _Kind.tactile => (SurfaceTexture.tactile, 1.0),
    _Kind.granite => (SurfaceTexture.granite, 1.0),
    _Kind.hallWall => (SurfaceTexture.tiles, 1.0),
    _Kind.vault => (SurfaceTexture.vault, 1.0),
    _Kind.trackWall => (SurfaceTexture.tiles, 0.97),
  };

  _Env _env(double z, bool inHall) => _Env(
    fog: 1 - math.exp(-(z - _cam.z) / (inHall ? 140 : 55)),
    lamp: inHall ? 0 : _lampLight(z),
    spill: inHall ? 0 : _hallSpill(z),
    head: _headlight(z),
  );

  Color _vertexColor(_Seg seg, _Env e, bool inHall, double tint) {
    var light = inHall ? _hallLight(seg) : 0.26;
    if (!inHall) {
      final side = seg.a.dx < 0 ? 1.0 : 0.55;
      light += e.lamp * 0.5 * side + e.spill * 0.75;
    }
    if (seg.kind == _Kind.trackbed || seg.kind == _Kind.bench) {
      light += e.head * (inHall ? 0.25 : 0.9);
    }
    // Holde sis griye çeker; çarpımla (modulate) ancak karartılabildiği
    // için etkisi yarıya indirildi.
    final k = light.clamp(0.0, 1.0) * tint * (1 - e.fog * (inHall ? 0.45 : 1));
    final v = (k * 255).round().clamp(0, 255);
    return Color.fromARGB(255, v, v, v);
  }

  double _hallLight(_Seg seg) => switch (seg.kind) {
    _Kind.vault => 1.05,
    _Kind.granite || _Kind.tactile => 1.0,
    _Kind.trackbed => 0.55,
    _Kind.platformFace => 0.45,
    _ => 0.92,
  };

  Color _segColor(_Kind kind) => switch (kind) {
    _Kind.trackbed => const Color(0xFF55585C),
    _Kind.concrete => const Color(0xFF6E7074),
    _Kind.bench => const Color(0xFF6A6C70),
    _Kind.lining => const Color(0xFF7D8083),
    _Kind.walkway => const Color(0xFF85878A),
    _Kind.platformFace => const Color(0xFF4A4D52),
    _Kind.tactile => const Color(0xFFF2C230),
    _Kind.granite => const Color(0xFFB9B7B2),
    _Kind.hallWall => const Color(0xFFE4E2DC),
    _Kind.vault => const Color(0xFFD9DADB),
    _Kind.trackWall => const Color(0xFFDCDAD4),
  };

  /// Tünel halkalarının ek yerleri: kemerin üstünde ince koyu çizgi.
  void _drawRingJoints(
    Canvas canvas,
    double za,
    bool inHall,
    double fog,
    Color fogColor,
  ) {
    if (inHall) return;
    final m = za / 1.5;
    if ((m - m.round()).abs() > 0.01) return;
    _path.reset();
    var first = true;
    for (final seg in _tunnelProfile) {
      if (seg.kind != _Kind.lining) continue;
      final p = _cam.project(seg.a.dx, seg.a.dy, za);
      if (p == null) return;
      if (first) {
        _path.moveTo(p.dx, p.dy);
        first = false;
      } else {
        _path.lineTo(p.dx, p.dy);
      }
    }
    _stroke
      ..color = Color.lerp(const Color(0x66000000), fogColor, fog)!
      ..strokeWidth = _px(0.05, za);
    canvas.drawPath(_path, _stroke);
  }

  void _drawTunnelDecor(
    Canvas canvas,
    double za,
    double zb,
    double fog,
    double lamp,
  ) {
    // Sağ duvarda kablo tavası: üç kalın kablo.
    for (final (i, deg) in <double>[4, 9, 14].indexed) {
      final a = deg * math.pi / 180;
      final x = _tunnelCx + (_tunnelR - 0.12) * math.cos(a);
      final y = _tunnelCy + (_tunnelR - 0.12) * math.sin(a);
      final c = <Color>[
        const Color(0xFF1B1C1E),
        const Color(0xFF3B2A1C),
        const Color(0xFF1E2A33),
      ][i];
      _line(
        canvas,
        x,
        y,
        za,
        x,
        y,
        zb,
        0.09,
        _fogged(c, 0.4 + lamp * 0.4, fog),
      );
    }
    // Tava rafı.
    final ta = 18 * math.pi / 180;
    final tx = _tunnelCx + (_tunnelR - 0.35) * math.cos(ta);
    final ty = _tunnelCy + (_tunnelR - 0.35) * math.sin(ta);
    _line(
      canvas,
      tx,
      ty,
      za,
      tx,
      ty,
      zb,
      0.05,
      _fogged(const Color(0xFF8E9296), 0.5 + lamp * 0.5, fog),
    );
    // Yürüme yolu korkuluğu.
    const hy = 1.95;
    final hx =
        _tunnelCx -
        math.sqrt(_tunnelR * _tunnelR - (hy - _tunnelCy) * (hy - _tunnelCy)) +
        0.18;
    _line(
      canvas,
      hx,
      hy,
      za,
      hx,
      hy,
      zb,
      0.05,
      _fogged(const Color(0xFFC9A227), 0.35 + lamp * 0.6, fog),
    );
    // Tepede yangın suyu borusu.
    _line(
      canvas,
      -1.4,
      5.85,
      za,
      -1.4,
      5.85,
      zb,
      0.1,
      _fogged(const Color(0xFF9A2A22), 0.3 + lamp * 0.5, fog),
    );
  }

  void _drawHallDecor(Canvas canvas, double za, double zb, double fog) {
    // Hat duvarında hat renginde şerit, perona bakan duvarda da.
    final band = _fogged(lineColor, 0.95, fog, fogColor: _hallFog);
    _wallQuadX(canvas, _hallLeft + 0.01, 2.05, 2.35, za, zb, band);
    _wallQuadX(canvas, _hallRight - 0.01, 2.35, 2.6, za, zb, band);
    // Süpürgelik.
    _wallQuadX(
      canvas,
      _hallLeft + 0.01,
      0,
      0.35,
      za,
      zb,
      _fogged(const Color(0xFF3C3F44), 1, fog, fogColor: _hallFog),
    );
    // Tavanda iki ışık bandı.
    for (final x in <double>[-1.2, 5.0]) {
      final y = _vaultYAt(x) - 0.05;
      final p0 = _cam.project(x - 0.35, y, za);
      final p1 = _cam.project(x + 0.35, y, za);
      final p2 = _cam.project(x + 0.35, y, zb);
      final p3 = _cam.project(x - 0.35, y, zb);
      if (p0 == null || p1 == null || p2 == null || p3 == null) continue;
      _fill.color = Color.lerp(const Color(0xFFFFFBEF), _hallFog, fog * 0.6)!;
      _quad(canvas, p0, p1, p2, p3);
    }
    // Peron kenarında beyaz güvenlik çizgisi.
    final e0 = _cam.project(_platformEdge, _platformY + 0.002, za);
    final e1 = _cam.project(_platformEdge + 0.08, _platformY + 0.002, za);
    final e2 = _cam.project(_platformEdge + 0.08, _platformY + 0.002, zb);
    final e3 = _cam.project(_platformEdge, _platformY + 0.002, zb);
    if (e0 != null && e1 != null && e2 != null && e3 != null) {
      _fill.color = _fogged(Colors.white, 1, fog, fogColor: _hallFog);
      _quad(canvas, e0, e1, e2, e3);
    }
  }

  double _vaultYAt(double x) {
    const cx = (_hallLeft + _hallRight) / 2;
    const rx = (_hallRight - _hallLeft) / 2;
    final t = ((x - cx) / rx).clamp(-1.0, 1.0);
    return _vaultBase + 4.1 * math.sqrt(1 - t * t);
  }

  /// Raylar, traversler ve üçüncü ray.
  void _drawTrack(
    Canvas canvas,
    double za,
    double zb,
    double fog,
    Color fogColor,
    bool inHall,
    double head,
  ) {
    final dz = za - _cam.z;
    final light =
        (inHall ? 0.8 : 0.3) + head * 0.8 + (inHall ? 0 : _hallSpill(za) * 0.6);

    // Beton traversler, 0,65 m arayla; uzakta taban rengine karışır.
    if (dz < 75) {
      final first = (za / 0.65).ceil();
      final last = (zb / 0.65).floor();
      // Hızda traversler göz için bulanıklaşır: rengi yatağa yaklaşır;
      // yoksa kare başına yarım travers kayıp titreşim gibi görünüyordu.
      final blur = (controller.speed / MachinistRules.maxSpeed).clamp(0.0, 1.0);
      _fill.color = _fogged(
        Color.lerp(
          const Color(0xFF8F8C86),
          const Color(0xFF626468),
          blur * 0.6,
        )!,
        light,
        fog,
        fogColor: fogColor,
      );
      for (var k = first; k <= last; k++) {
        final z = k * 0.65;
        final p0 = _cam.project(-1.25, 0.14, z);
        final p1 = _cam.project(1.25, 0.14, z);
        final p2 = _cam.project(1.25, 0.14, z + 0.24);
        final p3 = _cam.project(-1.25, 0.14, z + 0.24);
        if (p0 == null || p1 == null || p2 == null || p3 == null) continue;
        _quad(canvas, p0, p1, p2, p3);
      }
    }

    // Raylar: iç yüz koyu, üst yüz parlak çelik.
    for (final side in <double>[-1, 1]) {
      final x = side * 0.7175;
      final inner = x - side * 0.036;
      final s0 = _cam.project(inner, 0.14, za);
      final s1 = _cam.project(inner, 0.3, za);
      final s2 = _cam.project(inner, 0.3, zb);
      final s3 = _cam.project(inner, 0.14, zb);
      if (s0 != null && s1 != null && s2 != null && s3 != null) {
        _fill.color = _fogged(
          const Color(0xFF4A3B30),
          light,
          fog,
          fogColor: fogColor,
        );
        _quad(canvas, s0, s1, s2, s3);
      }
      final t0 = _cam.project(x - 0.036, 0.3, za);
      final t1 = _cam.project(x + 0.036, 0.3, za);
      final t2 = _cam.project(x + 0.036, 0.3, zb);
      final t3 = _cam.project(x - 0.036, 0.3, zb);
      if (t0 != null && t1 != null && t2 != null && t3 != null) {
        final shine = 0.75 + head * 0.9 + (inHall ? 0.4 : 0);
        _fill.color = _fogged(
          const Color(0xFFD7DCE0),
          shine,
          fog * 0.85,
          fogColor: fogColor,
        );
        _quad(canvas, t0, t1, t2, t3);
      }
    }

    // Üçüncü ray (750 V DC) solda, sarı koruyucu kapakla.
    final c0 = _cam.project(-1.68, 0.42, za);
    final c1 = _cam.project(-1.5, 0.42, za);
    final c2 = _cam.project(-1.5, 0.42, zb);
    final c3 = _cam.project(-1.68, 0.42, zb);
    if (c0 != null && c1 != null && c2 != null && c3 != null) {
      _fill.color = _fogged(
        const Color(0xFFD9B43A),
        light * 0.9,
        fog,
        fogColor: fogColor,
      );
      _quad(canvas, c0, c1, c2, c3);
    }
    // Yalıtkan destekler, 5 m'de bir.
    if (dz < 60) {
      final first = (za / 5).ceil();
      final last = (zb / 5).floor();
      for (var k = first; k <= last; k++) {
        final z = k * 5.0;
        final b = _cam.project(-1.6, 0.14, z);
        final t = _cam.project(-1.6, 0.42, z);
        if (b == null || t == null) continue;
        _stroke
          ..color = _fogged(
            const Color(0xFF2E3A48),
            light,
            fog,
            fogColor: fogColor,
          )
          ..strokeWidth = _px(0.08, z);
        canvas.drawLine(b, t, _stroke);
      }
    }
  }

  /// Hol ile tünel arasındaki duvar yüzü: kameraya dönük olan kısmı.
  void _drawBoundaryFace(Canvas canvas, double z) {
    for (final s in _stations) {
      final isStart = (z - s.hallStart).abs() < 1e-6;
      final isEnd = (z - s.hallEnd).abs() < 1e-6;
      if (!isStart && !isEnd) continue;
      final dz = z - _cam.z;
      // Kameranın dibindeki yüz ekrana binlerce piksel taşar ve zaten
      // görünmez (kamera onu geçmek üzere): çizilmez.
      if (dz < 3) return;
      // Yol çıkarma (`Path.combine`) yerine çift-tek dolgu: iki kesitin
      // simetrik farkı. Fazladan boyanan parça her iki uçta da yakın
      // dilimlerin arkasında kalıyor. Kombinasyon her karede yeniden
      // hesaplanıyordu ve tren holden çıkarken kare düşürüyordu.
      final face = Path()..fillType = PathFillType.evenOdd;
      if (!_addPoly(face, _tunnelOutline, z) ||
          !_addPoly(face, _hallOutline, z)) {
        return;
      }
      if (isStart) {
        // Tünelden bakınca: peron ucunun ön yüzü.
        _fill.color = _fogged(
          const Color(0xFF5B5E63),
          0.55 + _hallSpill(z) * 0.3,
          1 - math.exp(-dz / 55),
        );
        canvas.drawPath(face, _fill);
      } else {
        // Holden bakınca: tünel ağzı açılmış uç duvar.
        _fill.color = _fogged(
          const Color(0xFFD8D6D0),
          0.9,
          1 - math.exp(-dz / 140),
          fogColor: _hallFog,
        );
        canvas.drawPath(face, _fill);
      }
      return;
    }
  }

  /// Kesiti [z]'de yansıtıp yola ekler; bir köşe kameranın arkasındaysa
  /// `false`.
  bool _addPoly(Path path, List<Offset> outline, double z) {
    final pts = <Offset>[];
    for (final o in outline) {
      final p = _cam.project(o.dx, o.dy, z);
      if (p == null) return false;
      pts.add(p);
    }
    path.addPolygon(pts, true);
    return true;
  }

  // ------------------------------------------------------------ nesneler

  List<_Obj> _collectObjects(double camZ) {
    final objs = <_Obj>[];
    final start = camZ + _near;
    final end = camZ + _far;
    final t = _t;

    // Tünel lambaları.
    for (var z = (start / 12).ceil() * 12.0 + 6; z < end; z += 12) {
      if (_hallAt(z) != null) continue;
      objs.add(_Obj(z, (c) => _drawLamp(c, z)));
    }
    // Acil çıkış levhaları.
    for (var z = (start / 96).ceil() * 96.0 + 30; z < end; z += 96) {
      if (_hallAt(z) != null) continue;
      objs.add(_Obj(z, (c) => _drawExitSign(c, z)));
    }

    for (final s in _stations) {
      final pending = s.state == StationState.pending;
      // Yaklaşma sinyali: istasyon beklenirken sarı yanıp söner.
      final sig = s.stopPos - MachinistRules.approachWarning;
      if (sig > start && sig < end) {
        objs.add(
          _Obj(sig, (c) {
            final blink = (t * 2.2).floor().isEven;
            _drawSignal(
              c,
              sig,
              pending ? (blink ? _Aspect.yellow : _Aspect.dark) : _Aspect.green,
            );
          }),
        );
      }
      // 3 · 2 · 1 mesafe levhaları.
      for (final (n, d) in <(int, double)>[
        (3, MachinistRules.countdown3),
        (2, MachinistRules.countdown2),
        (1, MachinistRules.countdown1),
      ]) {
        final z = s.stopPos - d;
        if (z > start && z < end) {
          objs.add(_Obj(z, (c) => _drawCountBoard(c, z, n, pending)));
        }
      }
      if (s.hallEnd < start || s.hallStart > end) continue;

      // Çıkış sinyali: tren peronda iken kırmızı.
      final exitZ = s.platformEnd + 2.5;
      final dwelling = controller.dwellStation == s;
      objs.add(
        _Obj(exitZ, (c) {
          final aspect = pending || (dwelling && controller.doorOpen > 0.02)
              ? _Aspect.red
              : _Aspect.green;
          _drawSignal(c, exitZ, aspect, x: -2.3);
        }),
      );
      // Durak işareti.
      if (s.stopPos > start) {
        objs
          ..add(_Obj(s.stopPos, (c) => _drawStopZone(c, s)))
          ..add(_Obj(s.stopPos, (c) => _drawStopSign(c, s), x: 2.05));
      }
      // Tavandan sarkan yön levhaları.
      for (final z in <double>[s.platformStart + 14, s.platformEnd - 22]) {
        if (z < start || z > end) continue;
        objs.add(_Obj(z, (c) => _drawHangingSign(c, s, z), x: 5.7));
      }
      // Banklar.
      for (var z = s.platformStart + 8; z < s.platformEnd - 4; z += 16) {
        if (z < start || z > end) continue;
        final zz = z;
        objs.add(_Obj(zz, (c) => _drawBench(c, zz), x: 9));
      }
      // Yolcular.
      _addPassengers(objs, s, start, end);
    }
    return objs;
  }

  void _addPassengers(
    List<_Obj> objs,
    MachinistStation s,
    double start,
    double end,
  ) {
    final boarding = controller.dwellStation == s;
    if (s.state != StationState.pending && !boarding) {
      // Kaçırılan istasyonda yolcular kalır; bitenlerde peron boşalır.
      if (s.state == StationState.served) return;
    }
    final rng = math.Random(s.index * 7919 + 13);
    final count = math.min(s.passengers, 26);
    final trainRear = _front - MachinistRules.trainLength;
    final progress = boarding ? controller.boardingProgress : 0.0;
    for (var i = 0; i < count; i++) {
      final z0 =
          s.platformStart +
          6 +
          rng.nextDouble() * (MachinistRules.platformLength - 12);
      final x0 = 2.6 + rng.nextDouble() * 4.8;
      final look = rng.nextInt(_outfits.length);
      final h = 1.6 + rng.nextDouble() * 0.25;
      final delay = i / math.max(count, 1) * 0.55;
      var p = boarding ? ((progress - delay) / 0.45).clamp(0.0, 1.0) : 0.0;
      if (z0 < trainRear + 1 || z0 > _front - 1) {
        // Trenin boyunun dışında bekleyen yolcu sonraki treni bekler.
        p = 0;
      }
      if (p >= 1) continue;
      // En yakın kapıya doğru yürür.
      final doorZ = _nearestDoorZ(z0.clamp(trainRear + 2, _front - 2));
      final x = x0 + (_platformEdge + 0.2 - x0) * p;
      final z = z0 + (doorZ - z0) * p;
      if (z < start || z > end) continue;
      objs.add(_Obj(z, (c) => _drawPerson(c, x, z, h, look, 1 - p * p), x: x));
    }
  }

  double _nearestDoorZ(double z) {
    var best = z;
    var bestD = double.infinity;
    for (var car = 0; car < MachinistRules.carCount; car++) {
      final z1 =
          _front - car * (MachinistRules.carLength + MachinistRules.carGap);
      final z0 = z1 - MachinistRules.carLength;
      for (final off in _doorOffsets) {
        final dz = z0 + off;
        final d = (dz - z).abs();
        if (d < bestD) {
          bestD = d;
          best = dz;
        }
      }
    }
    return best;
  }

  static const List<(Color, Color)> _outfits = <(Color, Color)>[
    (Color(0xFF2B3A55), Color(0xFF1F2328)),
    (Color(0xFFB23A48), Color(0xFF26282C)),
    (Color(0xFF3F7D58), Color(0xFF3A3024)),
    (Color(0xFFE0B040), Color(0xFF2A2E38)),
    (Color(0xFF6B4E9B), Color(0xFF1E2024)),
    (Color(0xFFDADADA), Color(0xFF34495E)),
    (Color(0xFF8C5A3C), Color(0xFF222222)),
    (Color(0xFF2F8FB0), Color(0xFF2C2C2C)),
  ];

  void _drawPerson(
    Canvas c,
    double x,
    double z,
    double h,
    int look,
    double alpha,
  ) {
    final feet = _cam.project(x, _platformY, z);
    final head = _cam.project(x, _platformY + h, z);
    if (feet == null || head == null) return;
    final ph = feet.dy - head.dy;
    if (ph < 2) return;
    final w = ph * 0.26;
    final (coat, legs) = _outfits[look];
    final fog = 1 - math.exp(-(z - _cam.z) / 140);
    final a = alpha.clamp(0.0, 1.0);
    Color fc(Color col) => Color.lerp(col, _hallFog, fog)!.withValues(alpha: a);
    // Bacaklar.
    _fill.color = fc(legs);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          feet.dx - w * 0.36,
          feet.dy - ph * 0.46,
          feet.dx + w * 0.36,
          feet.dy,
        ),
        Radius.circular(w * 0.12),
      ),
      _fill,
    );
    // Gövde.
    _fill.color = fc(coat);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          feet.dx - w * 0.5,
          feet.dy - ph * 0.84,
          feet.dx + w * 0.5,
          feet.dy - ph * 0.42,
        ),
        Radius.circular(w * 0.3),
      ),
      _fill,
    );
    // Baş.
    _fill.color = fc(const Color(0xFFE2B48C));
    c.drawCircle(Offset(feet.dx, feet.dy - ph * 0.92), ph * 0.085, _fill);
    _fill.color = fc(const Color(0xFF2A1E18));
    c.drawArc(
      Rect.fromCircle(
        center: Offset(feet.dx, feet.dy - ph * 0.925),
        radius: ph * 0.088,
      ),
      math.pi,
      math.pi,
      true,
      _fill,
    );
  }

  void _drawLamp(Canvas c, double z) {
    const a = 148 * math.pi / 180;
    final x = _tunnelCx + (_tunnelR - 0.1) * math.cos(a);
    final y = _tunnelCy + (_tunnelR - 0.1) * math.sin(a);
    final p = _cam.project(x, y, z);
    final q = _cam.project(x, y, z + 1.2);
    if (p == null || q == null) return;
    final dz = z - _cam.z;
    final fog = 1 - math.exp(-dz / 90);
    final r = _px(0.9, z);
    _fill.shader = ui.Gradient.radial(p, math.max(r, 1), <Color>[
      const Color(0xFFFFE3A8).withValues(alpha: 0.45 * (1 - fog)),
      const Color(0x00FFE3A8),
    ]);
    c.drawCircle(p, math.max(r, 1), _fill);
    _fill.shader = null;
    _stroke
      ..color = Color.lerp(const Color(0xFFFFF4D6), _tunnelFog, fog * 0.7)!
      ..strokeWidth = math.max(_px(0.16, z), 1);
    c.drawLine(p, q, _stroke);
  }

  void _drawExitSign(Canvas c, double z) {
    const x = -4.1;
    final tl = _cam.project(x, 2.75, z);
    final br = _cam.project(x + 0.8, 2.35, z);
    if (tl == null || br == null) return;
    final fog = 1 - math.exp(-(z - _cam.z) / 90);
    final rect = Rect.fromPoints(tl, br);
    _fill.color = Color.lerp(const Color(0xFF12A150), _tunnelFog, fog * 0.8)!;
    c.drawRect(rect, _fill);
    _fill.color = Color.lerp(Colors.white, _tunnelFog, fog * 0.8)!;
    // Kapı ve ok.
    c.drawRect(
      Rect.fromLTWH(
        rect.left + rect.width * 0.12,
        rect.top + rect.height * 0.2,
        rect.width * 0.18,
        rect.height * 0.6,
      ),
      _fill,
    );
    _path
      ..reset()
      ..moveTo(
        rect.left + rect.width * 0.45,
        rect.center.dy - rect.height * 0.1,
      )
      ..lineTo(
        rect.left + rect.width * 0.72,
        rect.center.dy - rect.height * 0.1,
      )
      ..lineTo(
        rect.left + rect.width * 0.72,
        rect.center.dy - rect.height * 0.3,
      )
      ..lineTo(rect.left + rect.width * 0.9, rect.center.dy)
      ..lineTo(
        rect.left + rect.width * 0.72,
        rect.center.dy + rect.height * 0.3,
      )
      ..lineTo(
        rect.left + rect.width * 0.72,
        rect.center.dy + rect.height * 0.1,
      )
      ..lineTo(
        rect.left + rect.width * 0.45,
        rect.center.dy + rect.height * 0.1,
      )
      ..close();
    c.drawPath(_path, _fill);
  }

  void _drawSignal(Canvas c, double z, _Aspect aspect, {double x = -3.3}) {
    final foot = _cam.project(x, x < -2.6 ? 0.95 : 0, z);
    final top = _cam.project(x, 3.1, z);
    if (foot == null || top == null) return;
    final dz = z - _cam.z;
    final w = _px(0.12, z);
    _stroke
      ..color = const Color(0xFF2B2E33)
      ..strokeWidth = math.max(w, 1);
    c.drawLine(foot, top, _stroke);
    // Başlık: iki lambalı siyah kutu.
    final hw = _px(0.36, z);
    final head = Rect.fromLTRB(
      top.dx - hw / 2,
      top.dy - hw * 2.1,
      top.dx + hw / 2,
      top.dy,
    );
    _fill.color = const Color(0xFF111214);
    c.drawRRect(
      RRect.fromRectAndRadius(head, Radius.circular(hw * 0.2)),
      _fill,
    );
    final upper = Offset(head.center.dx, head.top + hw * 0.55);
    final lower = Offset(head.center.dx, head.bottom - hw * 0.55);
    final lampR = hw * 0.3;
    Color? upperC;
    Color? lowerC;
    switch (aspect) {
      case _Aspect.red:
        upperC = const Color(0xFFFF2D2D);
      case _Aspect.yellow:
        lowerC = const Color(0xFFFFC21A);
      case _Aspect.green:
        lowerC = const Color(0xFF2DFF7A);
      case _Aspect.dark:
        break;
    }
    _fill.color = const Color(0xFF2A2B2E);
    c.drawCircle(upper, lampR, _fill);
    c.drawCircle(lower, lampR, _fill);
    for (final (pos, col) in <(Offset, Color?)>[
      (upper, upperC),
      (lower, lowerC),
    ]) {
      if (col == null) continue;
      final glow = math.max(lampR * 5, 6.0) * (dz > 150 ? 1.3 : 1);
      _fill.shader = ui.Gradient.radial(pos, glow, <Color>[
        col.withValues(alpha: 0.55),
        col.withValues(alpha: 0),
      ]);
      c.drawCircle(pos, glow, _fill);
      _fill.shader = null;
      _fill.color = Color.lerp(col, Colors.white, 0.35)!;
      c.drawCircle(pos, math.max(lampR, 1.2), _fill);
    }
  }

  /// Sarı zeminli mesafe levhası: 3, 2, 1.
  void _drawCountBoard(Canvas c, double z, int n, bool active) {
    const x = -3.9;
    final tl = _cam.project(x, 3.3, z);
    final br = _cam.project(x + 0.9, 2.3, z);
    final foot = _cam.project(x + 0.45, 0.95, z);
    if (tl == null || br == null || foot == null) return;
    final rect = Rect.fromPoints(tl, br);
    final fog = 1 - math.exp(-(z - _cam.z) / 110);
    _stroke
      ..color = Color.lerp(const Color(0xFF3A3D42), _tunnelFog, fog)!
      ..strokeWidth = math.max(_px(0.07, z), 1);
    c.drawLine(Offset(rect.center.dx, rect.bottom), foot, _stroke);
    final boardLight = active ? 1.0 : 0.55;
    _fill.color = Color.lerp(
      _lit(const Color(0xFFFFC21A), boardLight),
      _tunnelFog,
      fog * 0.75,
    )!;
    c.drawRect(rect, _fill);
    _fill.color = Color.lerp(const Color(0xFF111111), _tunnelFog, fog * 0.6)!;
    c.drawRect(
      rect.deflate(rect.width * 0.06),
      _fill..style = PaintingStyle.fill,
    );
    _fill.color = Color.lerp(
      _lit(const Color(0xFFFFC21A), boardLight),
      _tunnelFog,
      fog * 0.75,
    )!;
    c.drawRect(rect.deflate(rect.width * 0.12), _fill);
    if (rect.height > 6) {
      _paintText(
        c,
        '$n',
        rect.center,
        rect.height * 0.72,
        const Color(0xFF111111),
      );
    }
  }

  /// Durak işareti: peron kenarında direk, tepesinde "DUR" levhası; rayın
  /// üstünde de beklenirken yanan ince çizgi.
  void _drawStopZone(Canvas c, MachinistStation s) {
    final z = s.stopPos;
    final pending = s.state == StationState.pending;
    if (pending) {
      // Hedef bölge: ±1,5 m yeşil, işaret çizgisi sarı.
      final g0 = _cam.project(-1.4, 0.16, z - 1.5);
      final g1 = _cam.project(1.4, 0.16, z - 1.5);
      final g2 = _cam.project(1.4, 0.16, z + 1.5);
      final g3 = _cam.project(-1.4, 0.16, z + 1.5);
      if (g0 != null && g1 != null && g2 != null && g3 != null) {
        _fill.color = const Color(0x5534E07A);
        _quad(c, g0, g1, g2, g3);
      }
      final l0 = _cam.project(-1.6, 0.17, z - 0.12);
      final l1 = _cam.project(1.6, 0.17, z - 0.12);
      final l2 = _cam.project(1.6, 0.17, z + 0.12);
      final l3 = _cam.project(-1.6, 0.17, z + 0.12);
      if (l0 != null && l1 != null && l2 != null && l3 != null) {
        _fill.color = const Color(0xFFFFD84A);
        _quad(c, l0, l1, l2, l3);
      }
    }
  }

  void _drawStopSign(Canvas c, MachinistStation s) {
    final z = s.stopPos;
    const x = 2.05;
    final foot = _cam.project(x, _platformY, z);
    final top = _cam.project(x, _platformY + 2.2, z);
    if (foot == null || top == null) return;
    _stroke
      ..color = const Color(0xFF2B2E33)
      ..strokeWidth = math.max(_px(0.08, z), 1);
    c.drawLine(foot, top, _stroke);
    final bw = _px(1.3, z);
    final rect = Rect.fromCenter(
      center: Offset(top.dx, top.dy - bw * 0.35),
      width: bw,
      height: bw * 0.7,
    );
    _fill.color = const Color(0xFFFFC21A);
    c.drawRect(rect, _fill);
    // Siyah-sarı çapraz şerit kenar.
    _fill.color = const Color(0xFF111111);
    c.drawRect(
      Rect.fromLTWH(
        rect.left,
        rect.bottom - rect.height * 0.18,
        rect.width,
        rect.height * 0.18,
      ),
      _fill,
    );
    if (rect.height > 5) {
      _paintText(
        c,
        'DUR',
        Offset(rect.center.dx, rect.top + rect.height * 0.42),
        rect.height * 0.5,
        const Color(0xFF111111),
      );
    }
  }

  /// Perona tavandan sarkan lacivert levha: istasyon adı + yön.
  void _drawHangingSign(Canvas c, MachinistStation s, double z) {
    final tl = _cam.project(3.2, 4.55, z);
    final br = _cam.project(8.2, 3.85, z);
    final hook = _cam.project(5.7, _vaultYAt(5.7), z);
    if (tl == null || br == null || hook == null) return;
    final rect = Rect.fromPoints(tl, br);
    final fog = 1 - math.exp(-(z - _cam.z) / 140);
    _stroke
      ..color = const Color(0xFF55595F)
      ..strokeWidth = math.max(_px(0.03, z), 1);
    c.drawLine(
      Offset(rect.left + rect.width * 0.2, rect.top),
      Offset(rect.left + rect.width * 0.2, hook.dy),
      _stroke,
    );
    c.drawLine(
      Offset(rect.right - rect.width * 0.2, rect.top),
      Offset(rect.right - rect.width * 0.2, hook.dy),
      _stroke,
    );
    _fill.color = Color.lerp(const Color(0xFF14264A), _hallFog, fog)!;
    c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height * 0.08)),
      _fill,
    );
    if (rect.height < 6) return;
    final bs = rect.height * 0.62;
    _fill.color = lineColor;
    final badge = Rect.fromLTWH(
      rect.left + rect.height * 0.2,
      rect.center.dy - bs / 2,
      bs,
      bs,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(bs * 0.2)),
      _fill,
    );
    _paintText(
      c,
      lineCode,
      badge.center,
      bs * 0.46,
      LineTheme.readableOn(lineColor),
    );
    _paintText(
      c,
      s.name,
      Offset(
        badge.right + (rect.right - badge.right) / 2,
        rect.center.dy - rect.height * 0.12,
      ),
      rect.height * 0.4,
      Colors.white,
      maxWidth: rect.right - badge.right - rect.height * 0.3,
    );
    _paintText(
      c,
      '→ $destination',
      Offset(
        badge.right + (rect.right - badge.right) / 2,
        rect.center.dy + rect.height * 0.26,
      ),
      rect.height * 0.2,
      const Color(0xFFB9C4D8),
      maxWidth: rect.right - badge.right - rect.height * 0.3,
    );
  }

  void _drawBench(Canvas c, double z) {
    const x0 = 8.7;
    const x1 = 9.35;
    final fog = 1 - math.exp(-(z - _cam.z) / 140);
    final col = Color.lerp(const Color(0xFF8A9199), _hallFog, fog)!;
    // Oturak (üst yüz) ve arkalık.
    final s0 = _cam.project(x0, _platformY + 0.45, z);
    final s1 = _cam.project(x1, _platformY + 0.45, z);
    final s2 = _cam.project(x1, _platformY + 0.45, z + 2.2);
    final s3 = _cam.project(x0, _platformY + 0.45, z + 2.2);
    final b0 = _cam.project(x1, _platformY + 0.45, z);
    final b1 = _cam.project(x1, _platformY + 0.95, z);
    final b2 = _cam.project(x1, _platformY + 0.95, z + 2.2);
    final b3 = _cam.project(x1, _platformY + 0.45, z + 2.2);
    final l0 = _cam.project(x0, _platformY, z);
    if (s0 == null || s1 == null || s2 == null || s3 == null) return;
    if (b0 == null || b1 == null || b2 == null || b3 == null || l0 == null) {
      return;
    }
    _fill.color = _lit(col, 0.7);
    _quad(c, b0, b1, b2, b3);
    _fill.color = col;
    _quad(c, s0, s1, s2, s3);
    _stroke
      ..color = const Color(0xFF3C4046)
      ..strokeWidth = math.max(_px(0.05, z), 1);
    c.drawLine(s0, l0, _stroke);
  }

  // --------------------------------------------------------------- tren

  static const List<double> _doorOffsets = <double>[3.4, 9.25, 15.1];

  /// Tren kesiti; arkadan bakınca saat yönünün tersine.
  static const List<Offset> _body = <Offset>[
    Offset(-1.45, 1.0),
    Offset(1.45, 1.0),
    Offset(1.45, 3.3),
    Offset(1.22, 3.72),
    Offset(-1.22, 3.72),
    Offset(-1.45, 3.3),
  ];

  static const List<Offset> _under = <Offset>[
    Offset(-1.25, 0.32),
    Offset(1.25, 0.32),
    Offset(1.25, 1.0),
    Offset(-1.25, 1.0),
  ];

  void _drawTrain(Canvas canvas) {
    final front = _front;
    final inHall = _hallAt(front - MachinistRules.trainLength / 2) != null;
    final light = inHall ? 1.0 : 0.62 + _hallSpill(front - 20) * 0.35;
    final textures = MachinistTextures.ready;
    // Trenin ray yatağına düşen yumuşak gölgesi: gövdeyi yere oturtur.
    _floorShadow(canvas, front - MachinistRules.trainLength - 0.6, front + 0.6);
    for (var car = 0; car < MachinistRules.carCount; car++) {
      final z1 =
          front - car * (MachinistRules.carLength + MachinistRules.carGap);
      final z0 = z1 - MachinistRules.carLength;
      // Önündeki vagona bağlayan körük (arka vagonda görünür).
      if (car > 0) {
        _drawPrism(
          canvas,
          _bellows,
          z1,
          z1 + MachinistRules.carGap,
          const Color(0xFF1E2024),
          light,
        );
      }
      _drawPrism(
        canvas,
        _under,
        z0 + 1.2,
        z1 - 1.2,
        const Color(0xFF26282C),
        light,
      );
      _drawBogies(canvas, z0, z1, light);
      _drawCarBody(
        canvas,
        textures,
        z0,
        z1,
        light,
        isRear: car == MachinistRules.carCount - 1,
      );
      // Tavan klima üniteleri.
      for (final (a, b) in <(double, double)>[
        (z0 + 3, z0 + 7.5),
        (z1 - 7.5, z1 - 3),
      ]) {
        _drawPrism(
          canvas,
          const <Offset>[
            Offset(-0.85, 3.72),
            Offset(0.85, 3.72),
            Offset(0.7, 4.02),
            Offset(-0.7, 4.02),
          ],
          a,
          b,
          const Color(0xFFBFC4C9),
          light,
          outline: true,
        );
      }
    }
  }

  static const List<Offset> _bellows = <Offset>[
    Offset(-1.15, 1.1),
    Offset(1.15, 1.1),
    Offset(1.15, 3.45),
    Offset(-1.15, 3.45),
  ];

  void _floorShadow(Canvas c, double z0, double z1) {
    final a = _cam.project(-1.75, 0.16, z0);
    final b = _cam.project(1.75, 0.16, z0);
    final d = _cam.project(1.75, 0.16, z1);
    final e = _cam.project(-1.75, 0.16, z1);
    if (a == null || b == null || d == null || e == null) return;
    _fill.color = const Color(0x66000000);
    _quad(c, a, b, d, e);
  }

  /// Bojiler: yandan görünen tekerlekler ve şasi. Tekerlekler dairesel
  /// değil, kameraya göre sıkışmış elips (yan yüzün açısı).
  void _drawBogies(Canvas c, double z0, double z1, double light) {
    for (final center in <double>[z0 + 2.6, z1 - 2.6]) {
      // Boji şasisi.
      _planeQuadX(
        c,
        1.28,
        0.28,
        0.78,
        center - 1.55,
        center + 1.55,
        _lit(const Color(0xFF2F3236), light),
      );
      for (final off in <double>[-1.1, 1.1]) {
        final z = center + off;
        final top = _cam.project(1.3, 0.86, z);
        final bottom = _cam.project(1.3, 0.0, z);
        final near = _cam.project(1.3, 0.43, z - 0.43);
        final far = _cam.project(1.3, 0.43, z + 0.43);
        if (top == null || bottom == null || near == null || far == null) {
          continue;
        }
        final rect = Rect.fromLTRB(
          math.min(near.dx, far.dx),
          top.dy,
          math.max(near.dx, far.dx),
          bottom.dy,
        );
        if (rect.height < 2) continue;
        _fill.color = _lit(const Color(0xFF1A1B1E), light);
        c.drawOval(rect, _fill);
        // Jant ve göbek: çelik parıltısı.
        _fill.color = _lit(const Color(0xFF7D838A), light);
        c.drawOval(rect.deflate(rect.height * 0.12), _fill);
        _fill.color = _lit(const Color(0xFF34373C), light);
        c.drawOval(
          Rect.fromCenter(
            center: rect.center,
            width: rect.width * 0.35,
            height: rect.height * 0.35,
          ),
          _fill,
        );
      }
    }
  }

  void _drawCarBody(
    Canvas c,
    MachinistTextures? textures,
    double z0,
    double z1,
    double light, {
    required bool isRear,
  }) {
    const bodyColor = Color(0xFFE9ECEF);
    // Önce yan ve tavan yüzleri.
    for (var i = 0; i < _body.length; i++) {
      final p = _body[i];
      final q = _body[(i + 1) % _body.length];
      final pts = <Offset?>[
        _cam.project(p.dx, p.dy, z0),
        _cam.project(p.dx, p.dy, z1),
        _cam.project(q.dx, q.dy, z1),
        _cam.project(q.dx, q.dy, z0),
      ];
      if (pts.contains(null)) continue;
      final quad = pts.cast<Offset>();
      if (!_facing(quad)) continue;
      final nx = q.dy - p.dy;
      final ny = -(q.dx - p.dx);
      final len = math.sqrt(nx * nx + ny * ny);
      final shade = 0.72 + 0.28 * (ny / len) + 0.08 * (nx / len);
      if (textures != null) {
        _texturedBodyFace(c, textures, p, q, z0, z1, light * shade, ny / len);
      } else {
        _fill.color = _lit(bodyColor, light * shade);
        _quad(c, quad[0], quad[1], quad[2], quad[3]);
      }
      // Sağ yan yüz görünüyorsa pencereler, kapılar, hat şeridi.
      if (p.dx > 1.4 && q.dx > 1.4) _drawSideDetails(c, z0, z1, light);
      _strokeEdges(c, quad);
    }
    // Arka kapak.
    final rear = <Offset>[];
    for (final p in _body) {
      final s = _cam.project(p.dx, p.dy, z0);
      if (s == null) return;
      rear.add(s);
    }
    if (!_facing(rear)) return;
    _path.reset();
    _path.addPolygon(rear, true);
    _fill.color = _lit(bodyColor, light * 0.9);
    c.drawPath(_path, _fill);
    if (isRear) _drawCab(c, z0, light);
    _strokeEdges(c, rear);
  }

  /// Gövde yüzünü dokuyla sarar. Uzun yüz tek dörtgen olsaydı afin doku
  /// boyunca kayardı; yakında sık, uzakta seyrek parçalara bölünür.
  void _texturedBodyFace(
    Canvas c,
    MachinistTextures textures,
    Offset p,
    Offset q,
    double z0,
    double z1,
    double light,
    double upness,
  ) {
    final tex = upness > 0.9
        ? SurfaceTexture.trainRoof
        : SurfaceTexture.trainSide;
    final batch = _trainBatch
      ..positions.clear()
      ..uvs.clear()
      ..colors.clear();
    // u: yan yüzde gövde altından yükseklik; tavanda enine konum.
    final double ua;
    final double ub;
    if (tex == SurfaceTexture.trainRoof) {
      ua = (p.dx + 1.22) * tex.pxPerMeterU;
      ub = (q.dx + 1.22) * tex.pxPerMeterU;
    } else {
      ua = (p.dy - 1.0) * tex.pxPerMeterU;
      ub = (q.dy - 1.0) * tex.pxPerMeterU;
    }
    // Alt kenarda ortam gölgesi: gövde altı hafif kararır.
    Color col(double y) {
      final ao = y < 1.05 ? 0.78 : 1.0;
      final v = (light.clamp(0.0, 1.0) * ao * 255).round().clamp(0, 255);
      return Color.fromARGB(255, v, v, v);
    }

    final ca = col(p.dy);
    final cb = col(q.dy);
    final camZ = _cam.z;
    var za = z0;
    while (za < z1 - 1e-6) {
      final zb = math.min(z1, za + math.max(0.8, (za - camZ) * 0.12));
      final a0 = _cam.project(p.dx, p.dy, za);
      final b0 = _cam.project(q.dx, q.dy, za);
      final b1 = _cam.project(q.dx, q.dy, zb);
      final a1 = _cam.project(p.dx, p.dy, zb);
      if (a0 != null && b0 != null && b1 != null && a1 != null) {
        final v0 = (za - z0) * tex.pxPerMeterV;
        final v1 = (zb - z0) * tex.pxPerMeterV;
        batch.positions.addAll(<Offset>[a0, b0, b1, a0, b1, a1]);
        batch.uvs.addAll(<Offset>[
          Offset(ua, v0),
          Offset(ub, v0),
          Offset(ub, v1),
          Offset(ua, v0),
          Offset(ub, v1),
          Offset(ua, v1),
        ]);
        batch.colors.addAll(<Color>[ca, cb, cb, ca, cb, ca]);
      }
      za = zb;
    }
    if (batch.positions.isEmpty) return;
    c.drawVertices(
      ui.Vertices(
        ui.VertexMode.triangles,
        batch.positions,
        textureCoordinates: batch.uvs,
        colors: batch.colors,
      ),
      BlendMode.modulate,
      _texPaint..shader = textures.shaderFor(tex),
    );
  }

  final _Batch _trainBatch = _Batch();

  /// Yüzün kenarına ince koyu çizgi: gövde hatları uzakta da seçilsin.
  void _strokeEdges(Canvas c, List<Offset> pts) {
    _path
      ..reset()
      ..addPolygon(pts, true);
    _stroke
      ..color = const Color(0x59000000)
      ..strokeWidth = 1;
    c.drawPath(_path, _stroke);
  }

  void _drawSideDetails(Canvas c, double z0, double z1, double light) {
    const x = 1.452;
    // Hat rengi şerit.
    _planeQuadX(c, x, 1.35, 1.6, z0 + 0.3, z1 - 0.3, _lit(lineColor, light));
    // Pencereler: koyu çerçeve, cam, üstte gökyüzü yansıması.
    final open = controller.doorOpen;
    final doorZs = _doorOffsets.map((o) => z0 + o).toList();
    final glass = _lit(const Color(0xFF1C2733), light);
    final frame = _lit(const Color(0xFF3A3F46), light);
    final sheen = _lit(const Color(0xFF55667A), light);
    void window(double za, double zb) {
      _planeQuadX(c, x, 1.98, 3.12, za - 0.07, zb + 0.07, frame);
      _planeQuadX(c, x + 0.005, 2.05, 3.05, za, zb, glass);
      _planeQuadX(c, x + 0.01, 2.72, 3.0, za + 0.05, zb - 0.05, sheen);
    }

    var zc = z0 + 0.6;
    for (final dz in doorZs) {
      if (dz - 0.75 - zc > 0.8) window(zc + 0.3, dz - 1.05);
      zc = dz + 0.75;
    }
    if (z1 - 0.6 - zc > 0.8) window(zc + 0.3, z1 - 0.9);
    // Kapılar: kapalıyken gri çerçeve, açılınca içerisi (sıcak ışık).
    for (final dz in doorZs) {
      // Kapı boşluğunun koyu contası.
      _planeQuadX(
        c,
        x,
        0.98,
        3.24,
        dz - 0.78,
        dz + 0.78,
        _lit(const Color(0xFF2A2D31), light),
      );
      _planeQuadX(
        c,
        x,
        1.02,
        3.2,
        dz - 0.72,
        dz + 0.72,
        _lit(const Color(0xFF9EA5AD), light),
      );
      if (open > 0) {
        final half = 0.65 * open;
        _planeQuadX(
          c,
          x,
          1.05,
          3.1,
          dz - half,
          dz + half,
          const Color(0xFFFFE9B5),
        );
      }
      final leafW = 0.65;
      final shift = 0.62 * open;
      _planeQuadX(
        c,
        x + 0.01,
        1.08,
        3.12,
        dz - leafW - shift,
        dz - shift - 0.02,
        _lit(const Color(0xFFD5DADF), light),
      );
      _planeQuadX(
        c,
        x + 0.01,
        1.08,
        3.12,
        dz + shift + 0.02,
        dz + leafW + shift,
        _lit(const Color(0xFFD5DADF), light),
      );
      _planeQuadX(
        c,
        x + 0.02,
        2.2,
        2.95,
        dz - leafW + 0.12 - shift,
        dz - 0.14 - shift,
        glass,
      );
      _planeQuadX(
        c,
        x + 0.02,
        2.2,
        2.95,
        dz + 0.14 + shift,
        dz + leafW - 0.12 + shift,
        glass,
      );
    }
  }

  /// Arka kabin: ön cam, hedef göstergesi, stop lambaları, kuplör.
  void _drawCab(Canvas c, double z0, double light) {
    final z = z0 - 0.01;
    final braking = controller.brakeLevel;
    // Hat rengi şerit.
    _planeQuadZ(c, z, -1.45, 1.45, 1.35, 1.6, _lit(lineColor, light));
    // Kabin maskesi: ön camı ve lambaları çevreleyen siyah bant.
    _planeQuadZ(c, z, -1.3, 1.3, 1.95, 3.42, const Color(0xFF15171A));
    // Lamba yuvaları.
    for (final side in <double>[-1, 1]) {
      _planeQuadZ(
        c,
        z,
        side > 0 ? 0.62 : -1.3,
        side > 0 ? 1.3 : -0.62,
        1.68,
        2.02,
        const Color(0xFF15171A),
      );
    }
    // Tampon plakası (anti-climber).
    _planeQuadZ(
      c,
      z,
      -1.2,
      1.2,
      1.0,
      1.22,
      _lit(const Color(0xFF4A4F56), light),
    );
    // Ön cam.
    final w0 = _cam.project(-1.12, 2.05, z);
    final w1 = _cam.project(1.12, 2.05, z);
    final w2 = _cam.project(1.02, 3.28, z);
    final w3 = _cam.project(-1.02, 3.28, z);
    if (w0 != null && w1 != null && w2 != null && w3 != null) {
      _path
        ..reset()
        ..addPolygon(<Offset>[w0, w1, w2, w3], true);
      _fill.shader = ui.Gradient.linear(w3, w0, <Color>[
        const Color(0xFF3A4A5C),
        const Color(0xFF0E141B),
      ]);
      c.drawPath(_path, _fill);
      _fill.shader = null;
      // Yansıma çizgisi.
      _stroke
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = math.max(_px(0.12, z), 1);
      c.drawLine(_lerp(w0, w3, 0.2), _lerp(w1, w2, 0.75), _stroke);
    }
    // Hedef göstergesi (turuncu LED).
    final d0 = _cam.project(-0.8, 2.95, z - 0.01);
    final d1 = _cam.project(0.8, 2.95, z - 0.01);
    final d2 = _cam.project(0.8, 3.2, z - 0.01);
    final d3 = _cam.project(-0.8, 3.2, z - 0.01);
    if (d0 != null && d1 != null && d2 != null && d3 != null) {
      _fill.color = const Color(0xFF080808);
      _quad(c, d0, d1, d2, d3);
      final h = d0.dy - d3.dy;
      if (h > 4) {
        _paintText(
          c,
          destination.toUpperCase(),
          Offset((d0.dx + d1.dx) / 2, (d0.dy + d3.dy) / 2),
          h * 0.7,
          const Color(0xFFFFA726),
          maxWidth: (d1.dx - d0.dx) * 0.92,
        );
      }
    }
    // Stop lambaları: frende parlar.
    for (final side in <double>[-1, 1]) {
      final p = _cam.project(side * 1.08, 1.85, z - 0.01);
      if (p == null) continue;
      final r = _px(0.13, z);
      final glow = 0.25 + braking * 0.75;
      _fill.shader = ui.Gradient.radial(p, r * (3 + braking * 4), <Color>[
        const Color(0xFFFF2020).withValues(alpha: 0.6 * glow),
        const Color(0x00FF2020),
      ]);
      c.drawCircle(p, r * (3 + braking * 4), _fill);
      _fill.shader = null;
      _fill.color = Color.lerp(
        const Color(0xFF7A0E0E),
        const Color(0xFFFF5A4A),
        glow,
      )!;
      c.drawCircle(p, r, _fill);
      final w = _cam.project(side * 0.78, 1.85, z - 0.01);
      if (w != null) {
        _fill.color = const Color(0xFFF4F1E4);
        c.drawCircle(w, r * 0.75, _fill);
      }
    }
    // Kuplör.
    _planeQuadZ(c, z, -0.25, 0.25, 0.75, 1.05, const Color(0xFF2A2C30));
  }

  /// Dışbükey kesiti [z0, z1] boyunca uzatır; yalnız kameraya dönük
  /// yüzleri boyar.
  void _drawPrism(
    Canvas c,
    List<Offset> sec,
    double z0,
    double z1,
    Color color,
    double light, {
    bool outline = false,
  }) {
    for (var i = 0; i < sec.length; i++) {
      final p = sec[i];
      final q = sec[(i + 1) % sec.length];
      final a = _cam.project(p.dx, p.dy, z0);
      final b = _cam.project(p.dx, p.dy, z1);
      final d = _cam.project(q.dx, q.dy, z1);
      final e = _cam.project(q.dx, q.dy, z0);
      if (a == null || b == null || d == null || e == null) continue;
      final quad = <Offset>[a, b, d, e];
      if (!_facing(quad)) continue;
      final ny = -(q.dx - p.dx);
      final len = (q - p).distance;
      _fill.color = _lit(color, light * (0.7 + 0.3 * ny / len));
      _quad(c, a, b, d, e);
      if (outline) _strokeEdges(c, quad);
    }
    final cap = <Offset>[];
    for (final p in sec) {
      final s = _cam.project(p.dx, p.dy, z0);
      if (s == null) return;
      cap.add(s);
    }
    if (!_facing(cap)) return;
    _path
      ..reset()
      ..addPolygon(cap, true);
    _fill.color = _lit(color, light * 0.85);
    c.drawPath(_path, _fill);
  }

  // ------------------------------------------------------------ araçlar

  /// Arkadan bakınca saat yönünün tersine sıralı yüz kameraya dönük mü?
  /// Ekranda y aşağı baktığı için işaret ters döner.
  bool _facing(List<Offset> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % pts.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum < 0;
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

  void _planeQuadX(
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

  void _planeQuadZ(
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

  void _wallQuadX(
    Canvas c,
    double x,
    double y0,
    double y1,
    double za,
    double zb,
    Color color,
  ) => _planeQuadX(c, x, y0, y1, za, zb, color);

  void _line(
    Canvas c,
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    double width,
    Color color,
  ) {
    final a = _cam.project(x0, y0, z0);
    final b = _cam.project(x1, y1, z1);
    if (a == null || b == null) return;
    _stroke
      ..color = color
      ..strokeWidth = math.max(_px(width, (z0 + z1) / 2), 0.6);
    c.drawLine(a, b, _stroke);
  }

  /// [meters] uzunluğun [z] derinliğindeki piksel karşılığı.
  double _px(double meters, double z) =>
      _cam.f * meters / math.max(z - _cam.z, _near);

  Color _lit(Color base, double light) {
    final l = light.clamp(0.0, 1.6);
    if (l <= 1) return Color.lerp(Colors.black, base, l)!;
    return Color.lerp(base, Colors.white, (l - 1) * 0.6)!;
  }

  Color _fogged(
    Color base,
    double light,
    double fog, {
    Color fogColor = _tunnelFog,
  }) => Color.lerp(_lit(base, light), fogColor, fog)!;

  static Offset _lerp(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;

  static final Map<String, TextPainter> _textCache = <String, TextPainter>{};

  TextPainter _layout(String text, Color color) {
    final key = '$text|${color.toARGB32()}';
    return _textCache.putIfAbsent(key, () {
      if (_textCache.length > 200) _textCache.clear();
      return TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'M PLUS Rounded 1c',
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
    });
  }

  /// Metni [center]'a, [height] piksel yüksekliğinde (ve [maxWidth]'e
  /// sığacak biçimde) çizer.
  void _paintText(
    Canvas c,
    String text,
    Offset center,
    double height,
    Color color, {
    double? maxWidth,
  }) {
    final tp = _layout(text, color);
    var scale = height / tp.height;
    if (maxWidth != null && tp.width * scale > maxWidth) {
      scale = maxWidth / tp.width;
    }
    c.save();
    c.translate(center.dx, center.dy);
    c.scale(scale);
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    c.restore();
  }

  @override
  bool shouldRepaint(MachinistScenePainter old) =>
      old.controller != controller ||
      old.lineColor != lineColor ||
      old.destination != destination;
}

enum _Aspect { red, yellow, green, dark }

enum _Kind {
  trackbed,
  concrete,
  bench,
  lining,
  walkway,
  platformFace,
  tactile,
  granite,
  hallWall,
  vault,
  trackWall,
}

class _Seg {
  const _Seg(this.a, this.b, this.kind);
  final Offset a;
  final Offset b;
  final _Kind kind;
}

class _Env {
  const _Env({
    required this.fog,
    required this.lamp,
    required this.spill,
    required this.head,
  });
  final double fog;
  final double lamp;
  final double spill;
  final double head;
}

/// Bir dokunun bu dilimdeki üçgenleri.
class _Batch {
  final List<Offset> positions = <Offset>[];
  final List<Offset> uvs = <Offset>[];
  final List<Color> colors = <Color>[];

  /// a0-b0 dilimin yakın ucu, a1-b1 uzak ucu.
  void add(
    Offset a0,
    Offset b0,
    Offset b1,
    Offset a1,
    double u0,
    double u1,
    double v0,
    double v1,
    Color c0,
    Color c1,
  ) {
    positions.addAll(<Offset>[a0, b0, b1, a0, b1, a1]);
    uvs.addAll(<Offset>[
      Offset(u0, v0),
      Offset(u1, v0),
      Offset(u1, v1),
      Offset(u0, v0),
      Offset(u1, v1),
      Offset(u0, v1),
    ]);
    colors.addAll(<Color>[c0, c0, c1, c0, c1, c1]);
  }
}

class _Obj {
  _Obj(this.z, this.draw, {this.x = 0});
  final double z;

  /// Yanal konum; yalnız trenle sıralama için (peron tarafı > 1,5).
  final double x;
  final void Function(Canvas) draw;
}

class _Cam {
  _Cam({
    required this.z,
    required this.x,
    required this.y,
    required this.base,
    required this.slope,
    required this.yaw,
    required this.cosP,
    required this.sinP,
    required this.f,
    required this.cx,
    required this.cy,
    required this.stations,
  });

  final double z;
  final double x;
  final double y;
  final double base;
  final double slope;
  final double yaw;
  final double cosP;
  final double sinP;
  final double f;
  final double cx;
  final double cy;
  final List<MachinistStation> stations;

  double _shiftZ = double.nan;
  double _shift = 0;

  Offset? project(double wx, double wy, double wz) {
    final dz = wz - z;
    if (wz != _shiftZ) {
      _shiftZ = wz;
      _shift = trackOffsetAt(stations, wz);
    }
    final lat = wx + _shift - base - slope * dz - x + yaw * dz;
    final ry = wy - y;
    final yc = ry * cosP + dz * sinP;
    final zc = dz * cosP - ry * sinP;
    if (zc < 0.3) return null;
    return Offset(cx + f * lat / zc, cy - f * yc / zc);
  }
}
