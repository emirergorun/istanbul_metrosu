import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tunnel_escape_controller.dart';
import '../domain/escape_board.dart';
import '../domain/escape_level.dart';
import '../domain/escape_solver.dart';
import 'escape_painter.dart';

/// Tahtanın anahtarı — testler tahtayı bununla bulur.
const Key escapeBoardKey = ValueKey<String>('tunnel-escape-board');

/// Premium eğri: hızlı başlar, yumuşak oturur.
const Cubic _kEase = Cubic(0.32, 0.72, 0, 1);

/// Tahta: çizim, sürükleme ve tahtanın kendi animasyonları.
///
/// **Sürükleme fizik değil, ray.** Metro parmağı yalnız kendi ekseninde
/// izler; dik yöndeki hareket yok sayılır, çapraz kayma yoktur. Metro
/// önündeki ilk engelde durur ve iç içe geçmez: sınır sürüklemenin
/// **başında** hesaplanıyor ([EscapeBoard.rangeOf]), sürükleme boyunca
/// değişmiyor çünkü başka hiçbir metro kıpırdamıyor.
///
/// Dokunuş ham işaretçi olaylarıyla okunuyor ([Listener]): hareket jesti
/// ~18 pikselik bir eşiği aşmadan başlamaz, metroda o gecikme "yapışkan"
/// hissettirir. Parmak değdiği anda metro kalkar, ilk pikselden izler.
class EscapeBoardView extends StatefulWidget {
  const EscapeBoardView({
    super.key,
    required this.controller,
    required this.hapticsEnabled,
    required this.onMoved,
    required this.onSolved,
    this.teachIdleHints = false,
  });

  final TunnelEscapeController controller;
  final bool hapticsEnabled;

  /// Bir hamle sayıldığında (ses için).
  final VoidCallback onMoved;

  /// Kırmızı metro tünel ağzına ulaştığında (ses ve titreşim için).
  final VoidCallback onSolved;

  /// Öğretici bölümlerde, oyuncu bir süre dokunmazsa doğru metro hafifçe
  /// kıpırdar. İpucu sayılmaz, yıldız götürmez.
  final bool teachIdleHints;

  @override
  State<EscapeBoardView> createState() => _EscapeBoardViewState();
}

class _EscapeBoardViewState extends State<EscapeBoardView>
    with TickerProviderStateMixin {
  // Ekranda görünen konumlar ve geçiş animasyonu (oturma, geri alma,
  // baştan başlatma aynı yoldan geçer).
  List<double> _from = const <double>[];
  List<double> _to = const <double>[];
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
  );

  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  EscapeLevel? _shownLevel;
  EscapeBoard? _shownBoard;
  EscapePhase? _shownPhase;

  // Sürükleme durumu.
  int? _pointer;
  int? _dragPiece;
  Offset _dragOrigin = Offset.zero;
  int _dragStart = 0;
  (int, int) _dragRange = (0, 0);
  double _dragShown = 0;
  int _lastCell = 0;
  bool _hitWall = false;

  // Öğretici kıpırtı.
  Timer? _idleTimer;
  int? _wigglePiece;
  int _wiggleDirection = 1;

  EscapeGeometry? _geometry;

  TunnelEscapeController get _c => widget.controller;

  /// iOS "Hareketi Azalt": geçişler anında olur, tünel animasyonu atlanır.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onController);
    _exit.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) _c.finishExit();
    });
    _syncFromController(animate: false, rebuild: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  void didUpdateWidget(EscapeBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _syncFromController(animate: false);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onController);
    _idleTimer?.cancel();
    _motion.dispose();
    _exit.dispose();
    _pulse.dispose();
    _wiggle.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _syncFromController(animate: true);
  }

  /// Denetleyicinin tahtasını ekrana yansıtır.
  ///
  /// Bölüm değiştiyse konumlar doğrudan yerine oturur; aynı bölümde tahta
  /// değiştiyse (hamle, geri alma, baştan) metrolar kısa bir geçişle yeni
  /// yerlerine kayar.
  void _syncFromController({required bool animate, bool rebuild = true}) {
    final level = _c.level;
    final board = _c.board;
    final phase = _c.phase;

    if (board == null || level == null) {
      _shownLevel = level;
      _shownBoard = board;
      _shownPhase = phase;
      return;
    }

    final target = <double>[for (final p in board.positions) p.toDouble()];
    final sameLevel = identical(level, _shownLevel);

    if (!sameLevel || _shownBoard == null) {
      _from = target;
      _to = target;
      _motion.value = 1;
      _exit.value = 0;
      _cancelDrag();
    } else if (!identical(board, _shownBoard)) {
      final current = _displayed();
      _from = current;
      _to = target;
      if (animate && !_reduceMotion) {
        _motion.forward(from: 0);
      } else {
        _motion.value = 1;
      }
    }

    // Tünel: bölüm bittiği anda kırmızı metro hızlanarak içeri girer.
    if (phase == EscapePhase.exiting && _shownPhase != EscapePhase.exiting) {
      if (_reduceMotion) {
        _exit.value = 1;
        // Animasyonsuz kullanıcı da paneli görmeli.
        scheduleMicrotask(_c.finishExit);
      } else {
        _exit.forward(from: 0);
      }
    }
    if (phase == EscapePhase.playing && _shownPhase != EscapePhase.playing) {
      _exit.value = 0;
    }

    if (_c.hint != null) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }

    _shownLevel = level;
    _shownBoard = board;
    _shownPhase = phase;
    _restartIdleTimer();
    if (rebuild) setState(() {});
  }

  List<double> _displayed() {
    final t = _kEase.transform(_motion.value);
    return <double>[
      for (var i = 0; i < _to.length; i++)
        i < _from.length ? _from[i] + (_to[i] - _from[i]) * t : _to[i],
    ];
  }

  // --- Öğretici kıpırtı ---

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (!widget.teachIdleHints || !_c.acceptsInput) return;
    _idleTimer = Timer(const Duration(milliseconds: 2600), _teach);
  }

  void _teach() {
    final board = _c.board;
    if (!mounted || board == null || !_c.acceptsInput || _dragPiece != null) {
      return;
    }
    // Öğretici bölümler küçük: aynı iş parçacığında çözmek anlık.
    final move = EscapeSolver(board.layout).nextMove(board.positions);
    if (move == null) return;
    setState(() {
      _wigglePiece = move.piece;
      _wiggleDirection = move.delta.sign;
    });
    if (_reduceMotion) return;
    _wiggle.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _wigglePiece = null);
      _idleTimer = Timer(const Duration(milliseconds: 3400), _teach);
    });
  }

  // --- Dokunuş ---

  int? _pieceUnder(Offset local) {
    final g = _geometry;
    final board = _c.board;
    if (g == null || board == null) return null;
    final (row, col) = g.cellAt(local);
    final direct = board.pieceAt(row, col);
    if (direct != null) return direct;

    // Affedici dokunuş: parmak metronun hemen kenarına düştüyse en yakın
    // metroyu seç. Kenar payı hücrenin dörtte biri.
    int? best;
    var bestDistance = double.infinity;
    for (var i = 0; i < board.positions.length; i++) {
      final rect = g
          .pieceRect(board.layout.pieces[i], board.positions[i].toDouble())
          .inflate(g.cell * 0.25);
      if (!rect.contains(local)) continue;
      final d = (rect.center - local).distanceSquared;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_pointer != null || !_c.acceptsInput) return;
    if (_motion.isAnimating) _motion.value = 1;
    final piece = _pieceUnder(event.localPosition);
    if (piece == null) {
      _c.clearHint();
      return;
    }
    _idleTimer?.cancel();
    _wiggle.stop();
    setState(() {
      _pointer = event.pointer;
      _dragPiece = piece;
      _dragOrigin = event.localPosition;
      _dragStart = _c.board!.positions[piece];
      _dragRange = _c.rangeOf(piece);
      _dragShown = _dragStart.toDouble();
      _lastCell = _dragStart;
      _hitWall = false;
      _wigglePiece = null;
    });
    _haptic(HapticFeedback.selectionClick);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _dragPiece == null) return;
    final g = _geometry!;
    final piece = _c.board!.layout.pieces[_dragPiece!];
    final delta = event.localPosition - _dragOrigin;
    final along = piece.isHorizontal ? delta.dx : delta.dy;
    final desired = _dragStart + along / g.cell;
    final (low, high) = _dragRange;

    // Sınırda hafif direnç: metro duvara yaslanır, biraz esner, geçmez.
    double shown;
    if (desired > high) {
      final over = desired - high;
      shown = high + _resist(over);
      if (over > 0.18) _bump();
    } else if (desired < low) {
      final over = low - desired;
      shown = low - _resist(over);
      if (over > 0.18) _bump();
    } else {
      shown = desired;
    }

    final cell = shown.round().clamp(low, high);
    if (cell != _lastCell) {
      _lastCell = cell;
      _haptic(HapticFeedback.selectionClick);
    }
    setState(() => _dragShown = shown);
  }

  double _resist(double over) => 0.12 * (1 - 1 / (1 + over * 2.4));

  void _bump() {
    if (_hitWall) return;
    _hitWall = true;
    _haptic(HapticFeedback.lightImpact);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.pointer != _pointer) return;
    final piece = _dragPiece;
    _pointer = null;
    if (piece == null) return;
    final (low, high) = _dragRange;
    final release = _dragShown;
    final to = release.round().clamp(low, high);
    final before = _displayed()..[piece] = release;
    _dragPiece = null;

    final outcome = _c.commitMove(piece, to);
    switch (outcome) {
      case EscapeMoveOutcome.moved:
        widget.onMoved();
      case EscapeMoveOutcome.solved:
        widget.onSolved();
      case EscapeMoveOutcome.unchanged:
      case EscapeMoveOutcome.ignored:
        break;
    }

    // Bırakılan yerden oturduğu hücreye kısa bir geçiş. Hamle sayılmadıysa
    // metro başladığı hücreye döner.
    final board = _c.board;
    if (board != null) {
      _from = before;
      _to = <double>[for (final p in board.positions) p.toDouble()];
      if (_reduceMotion) {
        _motion.value = 1;
      } else {
        _motion.forward(from: 0);
      }
    }
    _restartIdleTimer();
    setState(() {});
  }

  void _cancelDrag() {
    _pointer = null;
    _dragPiece = null;
  }

  void _haptic(void Function() effect) {
    if (widget.hapticsEnabled) effect();
  }

  // --- Çizim ---

  List<double> _positionsForPaint() {
    final positions = _displayed();
    final dragged = _dragPiece;
    if (dragged != null) positions[dragged] = _dragShown;
    final wiggling = _wigglePiece;
    if (wiggling != null && _wiggle.isAnimating) {
      final t = _wiggle.value;
      // Yalnız gideceği yöne doğru dürtülür: öbür yöne kıpırdasa komşu
      // metronun içine girmiş gibi görünürdü.
      positions[wiggling] +=
          _wiggleDirection * 0.16 * math.sin(t * math.pi * 3).abs() * (1 - t);
    }
    return positions;
  }

  /// Metronun bulunduğu yerden hangi yöne daha gidebildiği.
  (bool, bool) _cues() {
    final (low, high) = _dragRange;
    return (_dragShown > low + 0.05, _dragShown < high - 0.05);
  }

  String _semanticsLabel(EscapeBoard board) {
    final target = board.layout.target;
    final position = board.positions[board.layout.targetIndex];
    final free =
        board.layout.exitPosition - board.rangeOf(board.layout.targetIndex).$2;
    return 'Tahta ${board.layout.width} sütun, ${board.layout.height} satır. '
        'Kırmızı metro ${target.lane + 1}. satırda, ${position + 1}. sütunda. '
        '${free == 0 ? 'Tünele giden yol açık.' : 'Tünele giden yol kapalı.'}';
  }

  @override
  Widget build(BuildContext context) {
    final board = _c.board;
    if (board == null) return const SizedBox.shrink();

    return Semantics(
      label: _semanticsLabel(board),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final size = constraints.biggest;
            final geometry = EscapeGeometry.fit(
              size,
              board.layout.width,
              board.layout.height,
            );
            _geometry = geometry;
            return Listener(
              key: escapeBoardKey,
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerUp,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[
                    _motion,
                    _exit,
                    _pulse,
                    _wiggle,
                  ]),
                  builder: (BuildContext context, _) {
                    final hint = _c.hint;
                    final dragged = _dragPiece;
                    return CustomPaint(
                      size: size,
                      painter: EscapeBoardPainter(
                        layout: board.layout,
                        positions: _positionsForPaint(),
                        geometry: geometry,
                        lifted: dragged,
                        hintPiece: dragged == null ? hint?.piece : null,
                        hintTo: dragged == null ? hint?.to : null,
                        hintPulse: _pulse.value,
                        exitProgress: _exit.value,
                        axisCuePiece: dragged,
                        axisCues: dragged == null ? (false, false) : _cues(),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
