import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/merge_drop_state.dart';

class MergeDropController extends JourneyGameController {
  MergeDropController({
    required super.journey,
    required super.recordToBeat,
    super.store,
    Random? random,
    super.tick = const Duration(milliseconds: 16),
  }) : _random = random ?? Random(),
       super(gameId: id) {
    _currentLevel = _randomLevel();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  static const String id = 'merge_drop';

  /// Dünya **izotropiktir**: 1 birim = havuzun genişliği, her iki eksende de.
  ///
  /// Bu şart: fizik mesafeyi `sqrt(dx²+dy²)` ile ölçüyor, yani x ve y aynı
  /// birimde olmak zorunda. Eskiden çizim katmanı x'i genişlikle, y'yi
  /// yükseklikle, yarıçapı da kısa kenarla çarpıyordu; havuz dikey olduğu
  /// için fizikte tam temas eden iki top ekranda **hep boşluklu**
  /// görünüyordu (342×500'lük bir havuzda boşluk ~yarım top çapı).
  static const double worldWidth = 1;

  /// Havuzun dünya birimi cinsinden yüksekliği = ekrandaki en/boy oranı.
  /// Düzen ölçülene kadar kare varsayılır.
  double _worldHeight = 1;
  double get worldHeight => _worldHeight;

  /// Tehlike çizgisinin dünya birimi cinsinden y'si.
  double get dangerY => mergeDropDangerLine * _worldHeight;

  /// Çizim katmanı havuzun en/boy oranını (yükseklik / genişlik) bildirir.
  ///
  /// Topların konumu oranla birlikte ölçeklenir, yoksa ekran döndüğünde ya
  /// da yeniden boyutlandığında yığın havuzun dışında kalırdı.
  void setPoolAspect(double aspect) {
    final next = aspect.clamp(0.6, 3.0);
    if ((next - _worldHeight).abs() < 1e-6) return;
    final scale = next / _worldHeight;
    _worldHeight = next;
    _balls = <DropBall>[
      for (final ball in _balls)
        ball.copyWith(
          y: (ball.y * scale).clamp(ball.radius, next - ball.radius),
        ),
    ];
    notifyListeners();
  }

  /// Serbest düşüş ivmesi. Kütleden bağımsızdır (Galileo) — büyük top küçük
  /// topla aynı hızda düşer; "ağırlık" hissi kütleye göre çarpışma
  /// tepkisinden gelir, yerçekiminden değil.
  static const double _gravity = 2.2;

  /// Serbest düşüşte hız burada kesilir. Sınır olmasa hızlı bir top, tek bir
  /// karede altındaki topun içinden geçip altına düşebilir (tünelleme);
  /// bu sınır tek bir alt-adımda kat edilecek mesafeyi en küçük top çapının
  /// altında tutar (2.7 × 0.016/4 ≈ 0.011, en küçük top çapı 0.09'un çok
  /// altında — güvenli pay var).
  static const double _maxFallSpeed = 2.7;

  /// Fizik her tikte bu kadar alt-adıma bölünür. Adım küçüldükçe hem
  /// tünelleme riski azalır hem de çarpışma çözümü daha kararlı yığınlar
  /// üretir.
  static const int _substeps = 4;

  /// Bir alt-adımda çakışmaları gidermek için kaç kez tekrar denenir.
  /// Tek geçiş, üst üste birkaç top varken çakışmaları tam gideremez ve
  /// yığın titrer/dağılır; birden çok geçiş (Gauss–Seidel gevşemesi) yığının
  /// oturmasını sağlar.
  static const int _solverIterations = 4;

  /// Duvara çarpan topun ne kadar geri sektiğini belirler.
  static const double _wallRestitution = 0.28;

  /// Zeminde ve top-top temaslarında yanal hız her alt-adımda bu oranda
  /// azalır — sürtünme olmadan yığınlar yavaşça yanlara doğru "sürünür".
  static const double _friction = 0.82;

  /// Top-top çarpışmalarında sekme payı. Sıfırsa toplar birbirine değince
  /// tüm yaklaşma hızını anında yutar ve "yapışmış" gibi durur; gerçek
  /// toplar gibi hafifçe sekip ayrılsınlar diye küçük bir pay bırakılır.
  /// Zemin sekmez (ayrı fizik, aşağıda) — yalnızca top-top teması için.
  /// Yalnızca `_restitutionThreshold` üzerindeki gerçek çarpmalarda
  /// uygulanır (aşağıya bakın).
  static const double _ballRestitution = 0.38;

  /// Bu hızın altındaki yaklaşmalarda sekme uygulanmaz, çarpışma tam
  /// sönümlenir. Eşik olmadan, yerçekiminin her alt-adımda oturmuş bir
  /// yığını yeniden hafifçe bastırması → sekme → tekrar bastırma... diye
  /// sonsuz bir mikro-titreşim döngüsü oluşuyordu; bu da tam olarak
  /// "yapışma/titreme" hissinin köküydü. Yalnızca gerçek, sert çarpmalar
  /// (bu eşiğin üzerindeki yaklaşma hızları) sekiyor.
  static const double _restitutionThreshold = 0.06;

  /// Bu kadarın altındaki iç içe geçmeler düzeltilmez (kayan nokta
  /// gürültüsü payı) — aksi hâlde toplar hiçbir zaman tam durmayıp
  /// mikroskobik ölçekte sürekli düzeltilip yeniden çakışabilir.
  static const double _positionSlop = 0.0015;

  /// Tehlike çizgisinde **oturmuş** bir top kaybettirmeden önce ne kadar
  /// orada kalmalı. Yalnızca gerçekten oturmuş toplar sayıldığı için kısa
  /// tutulabilir; amaç anlık bir sekmeyi haksız kayıp saymamak.
  static const double _overflowGraceSeconds = 0.35;

  /// Bir topun "oturdu" sayılması için hızının altında kalması gereken
  /// değer. Düşmekte olan bir top bunun çok üstündedir.
  static const double _settleSpeed = 0.06;

  /// Temas toleransı: iki top bu mesafeye kadar yakınsa "değiyor" sayılır
  /// (çözücü zaten `_positionSlop` kadar boşluk bırakıyor).
  static const double _contactEpsilon = 0.004;

  /// Birleşme şişme animasyonunun süresi (saniye).
  static const double _mergePopSeconds = 0.18;

  /// Doğum bölgesi boşalmadan yeni top bırakılamaz.
  ///
  /// Bu olmadan arka arkaya bırakılan toplar doğum noktasında üst üste
  /// biniyor, havada zincirleme birleşiyor ve oyun bir saniyede
  /// seviye 4'e fırlıyordu. Gerçek "meyve düşürme" oyunlarında da boyun
  /// bölgesi boşalmadan yeni parça gelmez.
  static const double _spawnClearance = 0.02;

  final Random _random;

  double _aimX = 0.5;
  double _dropCooldown = 0;
  double _overflowSeconds = 0;
  int _nextId = 1;
  int _currentLevel = mergeDropMinLevel;
  int _merges = 0;
  int _maxLevel = mergeDropMinLevel;
  List<DropBall> _balls = const <DropBall>[];

  double get aimX => _aimX;
  int get currentLevel => _currentLevel;
  String get currentLabel => mergeDropLabelForLevel(_currentLevel);
  int get merges => _merges;
  int get maxLevel => _maxLevel;
  String get maxLabel => mergeDropLabelForLevel(_maxLevel);
  bool get canDrop =>
      status == GameStatus.playing && _dropCooldown <= 0 && _isSpawnClear();

  /// Doğum noktası boş mu? Önceki top hâlâ boyundaysa yeni top bırakılmaz.
  bool _isSpawnClear() {
    final radius = mergeDropRadiusForLevel(_currentLevel);
    final spawnY = radius + 0.015;
    for (final ball in _balls) {
      final dx = ball.x - _aimX;
      final dy = ball.y - spawnY;
      final minDistance = ball.radius + radius + _spawnClearance;
      if (dx * dx + dy * dy < minDistance * minDistance) return false;
    }
    return true;
  }
  List<DropBall> get balls => List<DropBall>.unmodifiable(_balls);

  @visibleForTesting
  void debugSetBalls(List<DropBall> balls) {
    _balls = List<DropBall>.of(balls);
    notifyListeners();
  }

  @visibleForTesting
  void debugStep(double seconds) {
    advance(seconds);
    notifyListeners();
  }

  @override
  void onRestart() {
    _aimX = 0.5;
    _dropCooldown = 0;
    _overflowSeconds = 0;
    _nextId = 1;
    _merges = 0;
    _maxLevel = mergeDropMinLevel;
    _balls = const <DropBall>[];
    _currentLevel = _randomLevel();
  }

  void moveAim(double x) {
    final radius = mergeDropRadiusForLevel(_currentLevel);
    _aimX = x.clamp(radius, worldWidth - radius);
    notifyListeners();
  }

  bool drop() {
    if (!canDrop) return false;
    final radius = mergeDropRadiusForLevel(_currentLevel);
    _balls = <DropBall>[
      ..._balls,
      DropBall(
        id: _nextId++,
        level: _currentLevel,
        x: _aimX.clamp(radius, worldWidth - radius),
        y: radius + 0.015,
      ),
    ];
    _currentLevel = _randomLevel();
    _dropCooldown = 0.32;
    notifyListeners();
    return true;
  }

  int _randomLevel() => _random.nextInt(3) + mergeDropMinLevel;

  @override
  void onTick(double dt) {
    _dropCooldown = max(0, _dropCooldown - dt);

    // Tek büyük adım yerine küçük alt-adımlar: hızlı düşen bir top, altındaki
    // topu tek bir karede "atlayıp" altına geçemesin diye (tünelleme).
    final subDt = dt / _substeps;
    for (var s = 0; s < _substeps; s++) {
      _integrate(subDt);
      for (var i = 0; i < _solverIterations; i++) {
        if (_mergeFirstOverlap()) continue;
        _resolveCollisions();
      }
    }

    _advancePop(dt);
    _updateSettled();

    if (_isOverflowing()) {
      _overflowSeconds += dt;
      if (_overflowSeconds > _overflowGraceSeconds) endGame();
    } else {
      _overflowSeconds = 0;
    }
  }

  void _integrate(double dt) {
    final updated = <DropBall>[];
    for (final ball in _balls) {
      final radius = ball.radius;
      final onFloor = ball.y + radius >= worldHeight - 1e-6;
      // Zeminde dururken sürtünme, havadayken yalnızca hafif hava direnci.
      var vx = ball.vx * (onFloor ? _friction : 0.995);
      var vy = (ball.vy + _gravity * dt).clamp(-_maxFallSpeed, _maxFallSpeed);
      var x = ball.x + vx * dt;
      var y = ball.y + vy * dt;

      if (x - radius < 0) {
        x = radius;
        vx = vx.abs() * _wallRestitution;
      } else if (x + radius > worldWidth) {
        x = worldWidth - radius;
        vx = -vx.abs() * _wallRestitution;
      }

      if (y + radius > worldHeight) {
        y = worldHeight - radius;
        if (vy > 0) vy = 0;
        if (vx.abs() < 1e-4) vx = 0;
      }

      updated.add(ball.copyWith(x: x, y: y, vx: vx, vy: vy));
    }
    _balls = updated;
  }

  bool _mergeFirstOverlap() {
    for (var i = 0; i < _balls.length; i++) {
      for (var j = i + 1; j < _balls.length; j++) {
        final a = _balls[i];
        final b = _balls[j];
        if (a.level != b.level || a.level >= mergeDropMaxLevel) continue;
        final distance = _distance(a, b);
        if (distance > a.radius + b.radius) continue;

        // Kütle merkezinde doğ ve momentumu koru.
        //
        // Eskiden konum düz ortalama, `vx` sıfır, `vy` keyfî bir kesirdi:
        // farklı boyda iki top birleşince yeni top yanlış yere düşüyor ve
        // yatay hızını tamamen yitiriyordu — yığın her birleşmede
        // "zıplıyormuş" gibi görünüyordu. Kütle ağırlıklı ortalama hem
        // konum hem hız için doğru olanı verir.
        final totalMass = a.mass + b.mass;
        final mergedRadius = mergeDropRadiusForLevel(a.level + 1);
        final merged = DropBall(
          id: _nextId++,
          level: a.level + 1,
          x: ((a.x * a.mass + b.x * b.mass) / totalMass).clamp(
            mergedRadius,
            worldWidth - mergedRadius,
          ),
          y: ((a.y * a.mass + b.y * b.mass) / totalMass).clamp(
            mergedRadius,
            worldHeight - mergedRadius,
          ),
          vx: (a.vx * a.mass + b.vx * b.mass) / totalMass,
          vy: (a.vy * a.mass + b.vy * b.mass) / totalMass,
          // agar.io hissi: yeni top küçük doğup gözle görülür şekilde şişer.
          // Yalnızca çizim; fizik ilk kareden itibaren tam yarıçapla çalışır.
          pop: 0,
        );
        _balls = <DropBall>[
          for (var k = 0; k < _balls.length; k++)
            if (k != i && k != j) _balls[k],
          merged,
        ];
        _merges++;
        _maxLevel = max(_maxLevel, merged.level);
        addScore(merged.level * 10);
        markStationProgress();
        return true;
      }
    }
    return false;
  }

  /// Çakışan her top çiftini aynı anda hem konum hem hız düzeyinde çözer.
  ///
  /// 1. **Konum düzeltmesi (penetrasyon ayrıştırma)**: toplar, kütleleriyle
  ///    ters orantılı ölçüde ayrılır — büyük/ağır top az, küçük/hafif top
  ///    çok hareket eder. Eşit bölüşüm (eski davranış) büyük bir topun
  ///    küçük bir topla aynı miktarda itilmesine, yani "ağırlıksız" bir
  ///    hisse yol açıyordu.
  /// 2. **Hız düzeltmesi (impuls)**: yalnızca gerçekten yaklaşan çiftlerde
  ///    (`vn < 0`) uygulanır; kütleye göre dağıtılan bir impuls hem normal
  ///    yöndeki hızı çözer hem de gerçek, sert çarpmalarda hafif bir sekme
  ///    bırakır (`_ballRestitution`, yalnızca `_restitutionThreshold`
  ///    üzerindeki yaklaşma hızlarında). Eşik olmadan yerçekiminin her
  ///    alt-adımda oturmuş toplara verdiği minik yaklaşma hızı bile
  ///    sekmeye dönüşüp sonsuz bir titreşim/yapışma hissi yaratıyordu.
  ///    Teğet yöndeki hız sürtünmeyle söner.
  ///
  /// Alt-adım başına birden çok kez çağrılır (Gauss–Seidel gevşemesi):
  /// çok sayıda top üst üsteyken tek geçiş çakışmayı tam gideremez.
  void _resolveCollisions() {
    final balls = List<DropBall>.of(_balls);
    for (var i = 0; i < balls.length; i++) {
      for (var j = i + 1; j < balls.length; j++) {
        final a = balls[i];
        final b = balls[j];
        final minDistance = a.radius + b.radius;
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance >= minDistance) continue;

        final safeDistance = distance <= 1e-6 ? 1e-6 : distance;
        final nx = dx / safeDistance;
        final ny = dy / safeDistance;
        final overlap = minDistance - safeDistance;

        final invMassA = 1 / a.mass;
        final invMassB = 1 / b.mass;
        final invMassSum = invMassA + invMassB;

        // Kayan nokta gürültüsü kadar çakışmayı düzeltmeye çalışma —
        // aksi hâlde toplar hiç tam durmayıp mikroskobik ölçekte titreşir.
        final penetration = max(overlap - _positionSlop, 0.0);
        final correctionA = penetration * (invMassA / invMassSum);
        final correctionB = penetration * (invMassB / invMassSum);

        var newA = a.copyWith(
          x: (a.x - nx * correctionA).clamp(a.radius, worldWidth - a.radius),
          y: (a.y - ny * correctionA).clamp(a.radius, worldHeight - a.radius),
        );
        var newB = b.copyWith(
          x: (b.x + nx * correctionB).clamp(b.radius, worldWidth - b.radius),
          y: (b.y + ny * correctionB).clamp(b.radius, worldHeight - b.radius),
        );

        final relVx = newB.vx - newA.vx;
        final relVy = newB.vy - newA.vy;
        final closingSpeed = relVx * nx + relVy * ny;
        if (closingSpeed < 0) {
          // Yalnızca gerçek, sert çarpmalarda sek; oturmuş bir yığını
          // yerçekiminin verdiği minik yaklaşma hızı sekmeye dönüşmesin.
          final restitution = closingSpeed < -_restitutionThreshold
              ? _ballRestitution
              : 0.0;
          final impulse = -(1 + restitution) * closingSpeed / invMassSum;
          newA = newA.copyWith(
            vx: newA.vx - impulse * nx * invMassA,
            vy: newA.vy - impulse * ny * invMassA,
          );
          newB = newB.copyWith(
            vx: newB.vx + impulse * nx * invMassB,
            vy: newB.vy + impulse * ny * invMassB,
          );
        }

        final tx = -ny;
        final ty = nx;
        final normalA = newA.vx * nx + newA.vy * ny;
        final tangentA = (newA.vx * tx + newA.vy * ty) * _friction;
        final normalB = newB.vx * nx + newB.vy * ny;
        final tangentB = (newB.vx * tx + newB.vy * ty) * _friction;

        balls[i] = newA.copyWith(
          vx: normalA * nx + tangentA * tx,
          vy: normalA * ny + tangentA * ty,
        );
        balls[j] = newB.copyWith(
          vx: normalB * nx + tangentB * tx,
          vy: normalB * ny + tangentB * ty,
        );
      }
    }
    _balls = balls;
  }

  double _distance(DropBall a, DropBall b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Birleşme şişme animasyonunu ilerletir (yalnızca çizim etkilenir).
  void _advancePop(double dt) {
    if (!_balls.any((ball) => ball.pop < 1)) return;
    _balls = <DropBall>[
      for (final ball in _balls)
        ball.pop >= 1
            ? ball
            : ball.copyWith(
                pop: (ball.pop + dt / _mergePopSeconds).clamp(0.0, 1.0),
              ),
    ];
  }

  /// Her topun "oturdu mu" durumunu baştan hesaplar.
  ///
  /// Oturmuş = neredeyse duruyor **ve** altında bir dayanak var (zemin ya da
  /// merkezi daha aşağıda, temas hâlinde bir top). Havada düşmekte olan ya
  /// da bir başka topa sürtüp geçen top oturmuş sayılmaz — kaybetme koşulu
  /// buna baktığı için bu ayrım oyunun oynanabilirliğini belirliyor.
  void _updateSettled() {
    final updated = <DropBall>[];
    for (final ball in _balls) {
      final slow = ball.speed < _settleSpeed;
      if (!slow) {
        updated.add(ball.copyWith(settled: false));
        continue;
      }

      final onFloor = ball.y + ball.radius >= worldHeight - 1e-3;
      var supported = onFloor;
      if (!supported) {
        for (final other in _balls) {
          if (identical(other, ball) || other.id == ball.id) continue;
          // Dayanak yalnızca merkezi bu topun merkezinden aşağıda olan ve
          // temas hâlindeki toplar olabilir.
          if (other.y <= ball.y) continue;
          final dx = other.x - ball.x;
          final dy = other.y - ball.y;
          final contact = ball.radius + other.radius + _contactEpsilon;
          if (dx * dx + dy * dy <= contact * contact) {
            supported = true;
            break;
          }
        }
      }
      updated.add(ball.copyWith(settled: supported));
    }
    _balls = updated;
  }

  /// Yalnızca gerçekten oturmuş toplar sayılır.
  bool _isOverflowing() {
    return _balls.any(
      (ball) => ball.settled && ball.y - ball.radius < dangerY,
    );
  }
}
