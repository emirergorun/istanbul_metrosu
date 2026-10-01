import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

/// Sahnenin yüzey dokuları.
///
/// Görsel dosyası yok: her doku açılışta bir kez, döşenebilir (kenarları
/// birbirine uyan) 256×256 piksel olarak üretilir. Çizici dokuyu
/// `drawVertices` ile üçgenlere sarar; ışık ve sis köşe renginden gelir
/// (`BlendMode.modulate`). Doku yalnız yüzeyin kendi rengini ve dokusunu
/// taşır.
enum SurfaceTexture {
  /// Tünel kaplaması: segmentli beton halka, ek yerleri ve cıvata yuvaları.
  lining(2.6, 1.5),

  /// Düz beton: kanal duvarı, peron ön yüzü.
  concrete(2, 2),

  /// Ray yatağı: kirli beton plak, çakıl benekleri, yağ lekeleri.
  trackbed(2, 2),

  /// Yürüme yolu: baklava desenli çelik sac.
  walkway(1, 1),

  /// İstasyon duvarı: şaşırtmalı sırlı karo.
  tiles(1.2, 1.2),

  /// Peron zemini: benekli granit plaklar.
  granite(2.4, 2.4),

  /// Peron kenarındaki sarı kabartmalı hissedilebilir şerit.
  tactile(0.6, 0.6),

  /// Tonoz: delikli metal tavan panelleri.
  vault(1.5, 3),

  /// Tren yanı: paslanmaz çelik; fırça izleri, panel ekleri, perçinler,
  /// alt etekte oluklu sac ve yol kiri. u = kesit boyunca yükseklik
  /// (0 = gövde altı), v = tren boyu.
  trainSide(2.3, 4),

  /// Tren tavanı: enine kaburgalı gri sac, is ve toz.
  trainRoof(2.44, 4);

  const SurfaceTexture(this.metersU, this.metersV);

  /// Dokunun kesit boyunca (u) ve ray boyunca (v) kapladığı metre.
  final double metersU;
  final double metersV;

  double get pxPerMeterU => MachinistTextures.size / metersU;
  double get pxPerMeterV => MachinistTextures.size / metersV;
}

class MachinistTextures {
  MachinistTextures._(this._shaders);

  static const int size = 256;

  static MachinistTextures? _ready;
  static Future<MachinistTextures>? _loading;

  /// Hazırsa dokular; değilse `null` (çizici düz renge düşer).
  static MachinistTextures? get ready => _ready;

  /// Dokuları bir kez üretir; tekrar çağrılar aynı işi bekler.
  static Future<MachinistTextures> load() =>
      _loading ??= _build().then((t) => _ready = t);

  final Map<SurfaceTexture, ImageShader> _shaders;

  ImageShader shaderFor(SurfaceTexture t) => _shaders[t]!;

  static Future<MachinistTextures> _build() async {
    final shaders = <SurfaceTexture, ImageShader>{};
    for (final t in SurfaceTexture.values) {
      final pixels = await _generate(t);
      final image = await _decode(pixels);
      shaders[t] = ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList(<double>[
          1, 0, 0, 0, //
          0, 1, 0, 0, //
          0, 0, 1, 0, //
          0, 0, 0, 1,
        ]),
        // Mipmap: uzaktaki doku kaynaşır, karıncalanmaz.
        filterQuality: FilterQuality.medium,
      );
    }
    return MachinistTextures._(shaders);
  }

  static Future<ui.Image> _decode(Uint8List pixels) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  // ------------------------------------------------------------- üretim

  /// Bir karede dokuya ayrılan en uzun süre.
  ///
  /// Üretim ana iş parçacığında; tek seferde yapılınca açılışta birkaç
  /// yüz milisaniye ekranı donduruyordu. Satırlar küçük dilimlerle
  /// üretilir, aralarda sıradaki kare beklenir: oyun kare kaçırmaz.
  static const Duration _frameBudget = Duration(milliseconds: 5);

  static Future<Uint8List> _generate(SurfaceTexture t) async {
    final noise = _Noise(t.index * 97 + 11);
    final out = Uint8List(size * size * 4);
    final budget = Stopwatch()..start();
    for (var y = 0; y < size; y++) {
      if (budget.elapsed > _frameBudget) {
        await SchedulerBinding.instance.endOfFrame;
        budget.reset();
      }
      for (var x = 0; x < size; x++) {
        final (r, g, b) = switch (t) {
          SurfaceTexture.lining => _lining(noise, x, y),
          SurfaceTexture.concrete => _concrete(noise, x, y),
          SurfaceTexture.trackbed => _trackbed(noise, x, y),
          SurfaceTexture.walkway => _walkway(noise, x, y),
          SurfaceTexture.tiles => _tiles(noise, x, y),
          SurfaceTexture.granite => _granite(noise, x, y),
          SurfaceTexture.tactile => _tactile(noise, x, y),
          SurfaceTexture.vault => _vault(noise, x, y),
          SurfaceTexture.trainSide => _trainSide(noise, x, y),
          SurfaceTexture.trainRoof => _trainRoof(noise, x, y),
        };
        final i = (y * size + x) * 4;
        out[i] = _byte(r);
        out[i + 1] = _byte(g);
        out[i + 2] = _byte(b);
        out[i + 3] = 255;
      }
    }
    return out;
  }

  static int _byte(double v) => v.round().clamp(0, 255);

  static (double, double, double) _shade(
    (double, double, double) c,
    double k,
  ) => (c.$1 * k, c.$2 * k, c.$3 * k);

  static (double, double, double) _mix(
    (double, double, double) a,
    (double, double, double) b,
    double t,
  ) => (
    a.$1 + (b.$1 - a.$1) * t,
    a.$2 + (b.$2 - a.$2) * t,
    a.$3 + (b.$3 - a.$3) * t,
  );

  static (double, double, double) _lining(_Noise n, int x, int y) {
    var k = 0.84 + 0.3 * n.fbm(x, y, 8, 4);
    // Nem ve is lekeleri: geniş, yumuşak kararmalar.
    final grime = n.fbm(x, y, 2, 3, seed: 3);
    if (grime > 0.55) k *= 1 - (grime - 0.55) * 0.9;
    // Kesit boyunca akan su izleri (u yönünde uzun, v yönünde dar).
    final streak = n.value(x / size * 3, y / size * 24, 3, 24, seed: 5);
    if (streak > 0.72) k *= 1 - (streak - 0.72) * 0.9;
    // Gözenekler.
    if (n.hash(x, y, 7) > 0.985) k *= 0.72;
    // Halka ek yeri (v = 0) ve segment ek yeri (u = 0).
    if (y < 3) k *= y == 1 ? 0.3 : 0.5;
    if (x < 3) k *= x == 1 ? 0.4 : 0.6;
    if (y == 3 || x == 3) k *= 1.12;
    // Cıvata yuvaları: halka ek yerinin iki yanında.
    for (final bx in const <int>[64, 192]) {
      for (final by in const <int>[14, 242]) {
        final dx = (x - bx).abs();
        final dy = (y - by).abs();
        if (dx < 7 && dy < 5) k *= (dx < 3 && dy < 2) ? 0.35 : 0.62;
      }
    }
    return _shade((125, 128, 131), k);
  }

  static (double, double, double) _concrete(_Noise n, int x, int y) {
    var k = 0.86 + 0.26 * n.fbm(x, y, 8, 4);
    if (n.hash(x, y, 2) > 0.98) k *= 0.75;
    // Kalıp izleri.
    if (x % 128 < 2) k *= 0.82;
    return _shade((116, 118, 121), k);
  }

  static (double, double, double) _trackbed(_Noise n, int x, int y) {
    var k = 0.8 + 0.35 * n.fbm(x, y, 16, 3);
    // Çakıl ve kum benekleri.
    final h = n.hash(x, y, 4);
    if (h > 0.9) k *= 1.25;
    if (h < 0.08) k *= 0.7;
    var c = _shade((88, 90, 93), k);
    // Yağ ve pas lekeleri.
    final oil = n.fbm(x, y, 3, 3, seed: 9);
    if (oil > 0.58) {
      c = _mix(c, (38, 34, 30), ((oil - 0.58) * 2.8).clamp(0, 0.8));
    }
    final rust = n.fbm(x, y, 4, 2, seed: 13);
    if (rust > 0.66) c = _mix(c, (110, 72, 44), (rust - 0.66) * 1.6);
    return c;
  }

  static (double, double, double) _walkway(_Noise n, int x, int y) {
    const cell = 16;
    final cx = x ~/ cell;
    final cy = y ~/ cell;
    final lx = x % cell - cell / 2 + 0.5;
    final ly = y % cell - cell / 2 + 0.5;
    // Baklava: hücreden hücreye yönü dönen kısa çıkıntı.
    final diag = (cx + cy).isEven ? lx - ly : lx + ly;
    final along = (cx + cy).isEven ? lx + ly : lx - ly;
    var k = 0.9 + 0.14 * n.fbm(x, y, 8, 3);
    if (diag.abs() < 1.8 && along.abs() < 9) {
      k *= diag > 0 ? 1.28 : 0.78;
    }
    var c = _shade((126, 129, 132), k);
    final dirt = n.fbm(x, y, 4, 3, seed: 21);
    if (dirt > 0.6) c = _mix(c, (70, 60, 50), (dirt - 0.6) * 1.5);
    return c;
  }

  static (double, double, double) _tiles(_Noise n, int x, int y) {
    // Karo: kesit boyunca 32 px (15 cm), ray boyunca 64 px (30 cm);
    // her sıra yarım karo kaydırılmış.
    const tu = 32;
    const tv = 64;
    final row = x ~/ tu;
    final yy = (y + (row.isOdd ? tv ~/ 2 : 0)) % size;
    final col = yy ~/ tv;
    final gx = x % tu;
    final gy = yy % tv;
    if (gx < 2 || gy < 2) return (168, 165, 158);
    final tint = 0.95 + 0.07 * n.hash(row, col, 31);
    // Sırın hafif parlaması: karonun üst kenarına doğru açılır.
    final glaze = 1 + 0.05 * (1 - gx / tu);
    final k = tint * glaze * (0.97 + 0.05 * n.fbm(x, y, 16, 2));
    return _shade((232, 230, 224), k);
  }

  static (double, double, double) _granite(_Noise n, int x, int y) {
    const slab = 128;
    if (x % slab < 2 || y % slab < 2) return (118, 116, 112);
    final tint = 0.94 + 0.08 * n.hash(x ~/ slab, y ~/ slab, 41);
    final k = tint * (0.9 + 0.18 * n.fbm(x, y, 8, 3));
    final h = n.hash(x, y, 43);
    if (h < 0.07) return _shade((86, 84, 82), k);
    if (h > 0.965) return _shade((240, 240, 238), k);
    if (h > 0.9) return _shade((150, 146, 140), k);
    return _shade((188, 186, 181), k);
  }

  static (double, double, double) _tactile(_Noise n, int x, int y) {
    const cell = 32;
    final lx = x % cell - cell / 2 + 0.5;
    final ly = y % cell - cell / 2 + 0.5;
    final d = math.sqrt(lx * lx + ly * ly);
    var k = 0.94 + 0.1 * n.fbm(x, y, 8, 2);
    if (d < 9) {
      // Kabartma: sol üstü aydınlık, sağ altı gölgeli.
      k *= 1 + (-lx - ly) / 9 * 0.18 + 0.06;
    } else if (d < 11) {
      k *= 0.8;
    }
    return _shade((242, 194, 48), k);
  }

  static (double, double, double) _trainSide(_Noise n, int x, int y) {
    // x: yükseklik (256 px = 2,3 m), y: tren boyu (256 px = 4 m).
    final h = x / MachinistTextures.size * 2.3;
    // Fırça izi: tren boyunca uzun, yükseklikte ince çizgiler.
    final brush = n.value(x / 2, y / 64, 128, 4, seed: 51);
    var k = 0.93 + 0.1 * brush + 0.03 * n.fbm(x, y, 8, 2);
    // Alt etek (ilk 35 cm): oluklu sac, olukları tren boyunca.
    if (h < 0.35) {
      final rib = (x % 9) / 9;
      k *= rib < 0.35 ? 0.8 : (rib < 0.5 ? 1.08 : 0.95);
    }
    // Panel ekleri (her 2 m) ve yanlarında perçin sırası.
    final seam = y % 128;
    if (seam < 2) k *= 0.62;
    if ((seam == 6 || seam == 122) && x % 10 == 5) k *= 0.7;
    // Pencere altı yatay ek.
    if (x >= 88 && x < 90) k *= 0.8;
    var c = _shade((226, 230, 234), k);
    // Yol kiri: alt kenara doğru koyulaşan, lekeli.
    final grime =
        (1 - h / 0.9).clamp(0.0, 1.0) *
        (0.55 + 0.45 * n.fbm(x, y, 4, 3, seed: 53));
    if (grime > 0) c = _mix(c, (92, 84, 74), grime * 0.55);
    return c;
  }

  static (double, double, double) _trainRoof(_Noise n, int x, int y) {
    // Enine kaburgalar: her 25 cm'de bir (16 px).
    final rib = y % 16;
    var k = 0.9 + 0.12 * n.fbm(x, y, 8, 3);
    if (rib < 2) k *= 1.15;
    if (rib == 2 || rib == 3) k *= 0.78;
    var c = _shade((158, 163, 168), k);
    // Fren tozu ve is: kenarlara yakın koyu.
    final edge = (x / MachinistTextures.size - 0.5).abs() * 2;
    final soot = n.fbm(x, y, 3, 3, seed: 61) * (0.3 + 0.7 * edge);
    if (soot > 0.35) c = _mix(c, (60, 56, 52), (soot - 0.35) * 0.9);
    return c;
  }

  static (double, double, double) _vault(_Noise n, int x, int y) {
    // Panel ek yerleri ve delik ızgarası.
    if (x % 128 < 2 || y < 2) return (188, 190, 193);
    var k = 0.96 + 0.06 * n.fbm(x, y, 4, 2);
    if (x % 8 == 4 && y % 8 == 4) k *= 0.8;
    return _shade((220, 221, 222), k);
  }
}

/// Döşenebilir değer gürültüsü. Tablo tohumlu `Random` ile kurulur;
/// büyük tamsayı çarpımı yok, web'de de aynı çalışır.
class _Noise {
  _Noise(int seed) : _table = _makeTable(seed);

  final List<double> _table;

  static List<double> _makeTable(int seed) {
    final r = math.Random(seed);
    return List<double>.generate(1024, (_) => r.nextDouble());
  }

  double hash(int x, int y, int seed) =>
      _table[(x * 7 + y * 131 + seed * 977 + (x ~/ 3) * (y % 17)) & 1023] *
          0.5 +
      _table[(x * 113 + y * 29 + seed * 31 + (y ~/ 5) * (x % 13)) & 1023] * 0.5;

  double _lattice(int x, int y, int seed) =>
      _table[(x * 59 + y * 173 + seed * 389) & 1023];

  /// [period] hücrelik ızgarada, kenarları döşenebilir yumuşak gürültü.
  double value(double u, double v, int periodU, int periodV, {int seed = 0}) {
    final x0 = u.floor();
    final y0 = v.floor();
    final fx = u - x0;
    final fy = v - y0;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    final xa = x0 % periodU;
    final xb = (x0 + 1) % periodU;
    final ya = y0 % periodV;
    final yb = (y0 + 1) % periodV;
    final a = _lattice(xa, ya, seed);
    final b = _lattice(xb, ya, seed);
    final c = _lattice(xa, yb, seed);
    final d = _lattice(xb, yb, seed);
    return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
  }

  /// Katmanlı gürültü, 0–1 aralığında.
  double fbm(int x, int y, int basePeriod, int octaves, {int seed = 0}) {
    var sum = 0.0;
    var amp = 0.5;
    var norm = 0.0;
    var period = basePeriod;
    for (var o = 0; o < octaves; o++) {
      sum +=
          amp *
          value(
            x / MachinistTextures.size * period,
            y / MachinistTextures.size * period,
            period,
            period,
            seed: seed + o * 17,
          );
      norm += amp;
      amp *= 0.5;
      period *= 2;
    }
    return sum / norm;
  }
}
