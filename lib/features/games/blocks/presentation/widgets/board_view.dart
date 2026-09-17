import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../domain/block_piece.dart';
import '../../domain/board.dart';

/// Sürükleme sırasında board üzerinde gösterilen ön izleme.
@immutable
class BoardPreview {
  const BoardPreview({
    required this.piece,
    required this.row,
    required this.col,
    required this.isValid,
  });

  final BlockPiece piece;
  final int row;
  final int col;
  final bool isValid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BoardPreview &&
          other.piece == piece &&
          other.row == row &&
          other.col == col &&
          other.isValid == isValid);

  @override
  int get hashCode => Object.hash(piece, row, col, isValid);
}

/// Temizlenen satır/sütunların patlama efekti.
@immutable
class BoardFlash {
  const BoardFlash({
    required this.rows,
    required this.columns,
    this.cellValues = const <int, int>{},
    this.originRow,
    this.originCol,
    this.points = 0,
    this.combo = 0,
    this.reduceMotion = false,
  });

  final List<int> rows;
  final List<int> columns;

  /// Temizlenen hücrelerin silinmeden önceki renk değerleri
  /// (`satır * sütunSayısı + sütun` -> değer). Bloklar patlarken kendi
  /// renklerinde görünsün, parçacıklar da o renkte savrulsun diye taşınır.
  final Map<int, int> cellValues;

  /// Patlamanın başladığı nokta, hücre biriminde: yerleştirilen parçanın
  /// merkezi. Dalga buradan hattın iki ucuna yayılır.
  ///
  /// `null` ise (durakta boşalan vagon) oyuncunun hamlesi yoktur; dalga
  /// trenin gidiş yönünde soldan sağa akar.
  final double? originRow;
  final double? originCol;

  /// Hamlenin kazandırdığı puan. 0 ise puan yazısı çıkmaz.
  final int points;
  final int combo;

  /// "Hareketi azalt" açık: parçacık, ışın ve sarsıntı yok; bloklar yalnızca
  /// yerinde söner.
  final bool reduceMotion;

  bool get isEmpty => rows.isEmpty && columns.isEmpty;
  int get lineCount => rows.length + columns.length;
}

/// Geri alma geçişi: tahtanın geri almadan **önceki** hâli.
///
/// Geri alma tahtayı tek karede eski hâline döndürüyordu; konan parça bir
/// anda kayboluyor, temizlenen satırlar bir anda geri geliyordu. Önceki hâl
/// bilinirse iki tahta arasındaki fark yumuşakça çizilir.
@immutable
class BoardUndo {
  const BoardUndo({required this.before, this.reduceMotion = false});

  /// Geri almadan hemen önceki tahta (geri alınan hamle uygulanmış).
  final Board before;

  /// "Hareketi azalt" açık: ölçek ve kayma yok, yalnızca solma.
  final bool reduceMotion;
}

/// 8x8 oyun tahtası.
///
/// Performans: tek [CustomPaint]. Sürükleme ön izlemesi ve temizleme
/// animasyonu widget rebuild etmeden `repaint` listenable üzerinden çizilir.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.board,
    required this.cellSize,
    required this.preview,
    required this.flash,
    required this.flashAnimation,
    this.undo,
    this.undoAnimation,
  });

  final Board board;
  final double cellSize;
  final ValueListenable<BoardPreview?> preview;
  final ValueListenable<BoardFlash?> flash;
  final Animation<double> flashAnimation;

  /// Geri alma geçişi ve süresi. İkisi birlikte verilmeli.
  final ValueListenable<BoardUndo?>? undo;
  final Animation<double>? undoAnimation;

  double get width => board.cols * cellSize;
  double get height => board.rows * cellSize;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(width, height),
        painter: _BoardPainter(
          board: board,
          cellSize: cellSize,
          preview: preview,
          flash: flash,
          flashAnimation: flashAnimation,
          undo: undo,
          undoAnimation: undoAnimation,
          repaint: Listenable.merge(<Listenable>[
            preview,
            flash,
            flashAnimation,
            ?undo,
            ?undoAnimation,
          ]),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.cellSize,
    required this.preview,
    required this.flash,
    required this.flashAnimation,
    required this.undo,
    required this.undoAnimation,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Board board;
  final double cellSize;
  final ValueListenable<BoardPreview?> preview;
  final ValueListenable<BoardFlash?> flash;
  final Animation<double> flashAnimation;
  final ValueListenable<BoardUndo?>? undo;
  final Animation<double>? undoAnimation;

  /// Geri alma geçişi sürüyorsa önceki tahta ve ilerleme (0..1).
  ({BoardUndo fx, double t})? get _activeUndo {
    final fx = undo?.value;
    final t = undoAnimation?.value ?? 1;
    if (fx == null || t >= 1) return null;
    return (fx: fx, t: t.clamp(0.0, 1.0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final activeUndo = _activeUndo;
    _paintCells(canvas, activeUndo?.fx.before);
    if (activeUndo != null) _paintUndo(canvas, activeUndo.fx, activeUndo.t);
    _paintPreview(canvas);
    _paintFlash(canvas);
  }

  Rect _cellRect(int row, int col) {
    final gap = cellSize * 0.06;
    return Rect.fromLTWH(
      col * cellSize + gap,
      row * cellSize + gap,
      cellSize - gap * 2,
      cellSize - gap * 2,
    );
  }

  RRect _cellRRect(int row, int col) => RRect.fromRectAndRadius(
    _cellRect(row, col),
    Radius.circular(cellSize * 0.20),
  );

  /// [undoBefore] verilirse geri almayla **geri gelen** hücreler boş çizilir;
  /// onları [_paintUndo] belirerek çizer.
  void _paintCells(Canvas canvas, [Board? undoBefore]) {
    final emptyPaint = Paint()..color = AppColors.emptyCell;
    // Izgara boş hücrenin dolgusuyla değil bu ince çizgiyle çiziliyor;
    // gerekçesi `AppColors.cellGrid` üzerinde. Çizgi hücre sınırının tam
    // üstüne oturmasın diye yarım kalınlık içeri alınır.
    final gridPaint = Paint()
      ..color = AppColors.cellGrid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final value = board.valueAt(r, c);
        final rrect = _cellRRect(r, c);
        final returning =
            undoBefore != null && undoBefore.isEmptyAt(r, c) && value != 0;

        if (value == kEmptyCell || returning) {
          canvas.drawRRect(rrect, emptyPaint);
          canvas.drawRRect(rrect.deflate(0.5), gridPaint);
          continue;
        }

        _paintBlock(canvas, rrect, value);
      }
    }
  }

  /// Dolu hücre: renk, üst parlama ya da engel deseni.
  ///
  /// [whiten] 0..1 bloğu beyaza çeker (patlamanın parlama anı), [opacity]
  /// bloğu soldurur.
  void _paintBlock(
    Canvas canvas,
    RRect rrect,
    int value, {
    double whiten = 0,
    double opacity = 1,
  }) {
    final base = AppColors.forCellValue(value);
    final color = Color.lerp(base, Colors.white, whiten)!;
    canvas.drawRRect(
      rrect,
      Paint()..color = color.withValues(alpha: color.a * opacity),
    );

    // Engel hücresi: yalnız renkle değil, desenle de ayrışsın.
    if (value == kBlockerCell) {
      _paintBlockerHatch(canvas, rrect);
      return;
    }
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(rrect.left, rrect.top, rrect.width, rrect.height * 0.42),
        topLeft: rrect.tlRadius,
        topRight: rrect.trRadius,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.10 * opacity),
    );
  }

  void _paintBlockerHatch(Canvas canvas, RRect rrect) {
    canvas.save();
    canvas.clipRRect(rrect);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.6;
    for (var x = -rrect.height; x < rrect.width; x += 6) {
      canvas.drawLine(
        Offset(rrect.left + x, rrect.bottom),
        Offset(rrect.left + x + rrect.height, rrect.top),
        paint,
      );
    }
    canvas.restore();
  }

  void _paintPreview(Canvas canvas) {
    final value = preview.value;
    if (value == null) return;

    final piece = value.piece;
    final color = value.isValid
        ? AppColors.forCellValue(piece.colorIndex)
        : AppColors.danger;

    // Geçerli yerleştirmede tamamlanacak satır/sütunları da vurgula.
    if (value.isValid) {
      _paintCompletionHint(canvas, value);
    }

    for (final cell in piece.cells) {
      final r = value.row + cell.row;
      final c = value.col + cell.col;
      if (!board.contains(r, c)) continue;

      final rrect = _cellRRect(r, c);
      canvas.drawRRect(
        rrect,
        Paint()..color = color.withValues(alpha: value.isValid ? 0.45 : 0.28),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }
  }

  /// Bu hamle bir satır/sütun tamamlıyorsa o hattı hafifçe aydınlat.
  void _paintCompletionHint(Canvas canvas, BoardPreview value) {
    final grid = board.toGrid();
    for (final cell in value.piece.cells) {
      final r = value.row + cell.row;
      final c = value.col + cell.col;
      // Taşan hücre atlanır — `return` olsaydı tek bir taşma yüzünden
      // ipucunun tamamı çizilmezdi.
      if (r < 0 || r >= board.rows || c < 0 || c >= board.cols) continue;
      grid[r][c] = 1;
    }
    final hypothetical = Board.fromGrid(grid);
    final paint = Paint()..color = AppColors.success.withValues(alpha: 0.16);

    for (final r in findCompletedRows(hypothetical)) {
      canvas.drawRect(
        Rect.fromLTWH(0, r * cellSize, board.cols * cellSize, cellSize),
        paint,
      );
    }
    for (final c in findCompletedColumns(hypothetical)) {
      canvas.drawRect(
        Rect.fromLTWH(c * cellSize, 0, cellSize, board.rows * cellSize),
        paint,
      );
    }
  }

  // --- Geri alma ---
  //
  // Geri alınan parça hücrelerinden kalkar: hafif küçülüp tepsiye doğru
  // (aşağı) kayarak söner. Hamlenin temizlediği satırlar aynı anda yerlerine
  // döner: küçük başlayıp hafif taşarak oturur, soldan sağa kısa bir sırayla.
  // İki hareket birlikte ~300 ms; tahta hiçbir karede sıçramaz.

  void _paintUndo(Canvas canvas, BoardUndo fx, double t) {
    final before = fx.before;
    for (var r = 0; r < board.rows; r++) {
      for (var c = 0; c < board.cols; c++) {
        final was = before.valueAt(r, c);
        final now = board.valueAt(r, c);
        if (was != kEmptyCell && now == kEmptyCell) {
          _paintLeavingBlock(canvas, r, c, was, t, fx.reduceMotion);
        } else if (was == kEmptyCell && now != kEmptyCell) {
          _paintReturningBlock(canvas, r, c, now, t, fx.reduceMotion);
        }
      }
    }
  }

  void _paintLeavingBlock(
    Canvas canvas,
    int row,
    int col,
    int value,
    double t,
    bool reduceMotion,
  ) {
    final k = Curves.easeInCubic.transform((t / 0.75).clamp(0.0, 1.0));
    if (k >= 1) return;
    final scale = reduceMotion ? 1.0 : 1 - 0.35 * k;
    final drop = reduceMotion ? 0.0 : cellSize * 0.6 * k;
    final rect = _cellRect(row, col);
    final scaled = Rect.fromCenter(
      center: rect.center.translate(0, drop),
      width: rect.width * scale,
      height: rect.height * scale,
    );
    _paintBlock(
      canvas,
      RRect.fromRectAndRadius(scaled, Radius.circular(cellSize * 0.20 * scale)),
      value,
      opacity: 1 - k,
    );
  }

  void _paintReturningBlock(
    Canvas canvas,
    int row,
    int col,
    int value,
    double t,
    bool reduceMotion,
  ) {
    // Soldan sağa kısa sıra: geri gelen satır "dolarak" oturur.
    final delay = reduceMotion ? 0.0 : col / board.cols * 0.25;
    final u = ((t - delay) / 0.75).clamp(0.0, 1.0);
    if (u <= 0) return;
    final scale = reduceMotion
        ? 1.0
        : 0.55 + 0.45 * Curves.easeOutBack.transform(u);
    final rect = _cellRect(row, col);
    final scaled = Rect.fromCenter(
      center: rect.center,
      width: rect.width * scale,
      height: rect.height * scale,
    );
    _paintBlock(
      canvas,
      RRect.fromRectAndRadius(scaled, Radius.circular(cellSize * 0.20 * scale)),
      value,
      whiten: 0.35 * (1 - u),
      opacity: Curves.easeOut.transform(u),
    );
  }

  // --- Patlama ---
  //
  // Zaman çizelgesi, [BoardFlash] süresine göre 0..1:
  //
  //   dalga   Patlama parçanın konduğu yerden hattın iki ucuna yürür. Dalga
  //           ulaşmayan blok yerinde durur; tahta "bir anda boşaldı" değil
  //           "zincirleme patladı" gibi okunur.
  //   blok    Önce şişip beyaza döner (vuruş), sonra küçülüp kaybolur.
  //   ışın    Dalganın arkasında hat boyunca yumuşak bir parıltı.
  //   enkaz   Blok kaybolurken kendi renginde dönen parçalar savrulur;
  //           yavaşlayarak açılır, yerçekimiyle düşer.
  //   puan    Parçanın üstünden "+N" yükselir.
  //
  // Eskisinde bloklar ilk karede siliniyor, yerlerinde beyaz kareler ve
  // tahtanın tamamına taşan bir halka beliriyordu; parçacıklar da aynı anda
  // ve sabit hızla dağıldığı için efekt "patlama" yerine "yanıp sönme"
  // gibi duruyordu.

  /// Dalganın bir hücre ilerlemesi için geçen süre.
  static const double _waveStep = 0.034;

  /// Tek bir bloğun vuruş + küçülme süresi.
  static const double _popSpan = 0.40;

  /// Bloğun şişmeyi bitirip küçülmeye başladığı an ([_popSpan] içinde).
  static const double _popPeak = 0.30;

  /// Enkazın uçuş süresi.
  static const double _debrisSpan = 0.58;

  void _paintFlash(Canvas canvas) {
    final value = flash.value;
    if (value == null || value.isEmpty) return;

    final t = flashAnimation.value.clamp(0.0, 1.0);
    if (t >= 1) return;

    final cells = _flashCells(value);

    if (value.reduceMotion) {
      for (final cell in cells) {
        _paintBlock(
          canvas,
          _cellRRect(cell.row, cell.col),
          cell.value,
          opacity: 1 - t,
        );
      }
      return;
    }

    _paintBeams(canvas, value, t);
    for (final cell in cells) {
      _paintPoppingBlock(canvas, cell, t);
    }
    _paintDebris(canvas, value, cells, t);
    _paintPoints(canvas, value, t);
  }

  /// Patlayan hücreler ve dalganın her birine ulaşma anı. Kesişim hücresi
  /// bir kez, iki hattan hangisi erken ulaşıyorsa o anda patlar.
  List<({int row, int col, int value, double delay})> _flashCells(
    BoardFlash flash,
  ) {
    final delays = <int, double>{};
    void add(int row, int col, double distance) {
      final key = row * board.cols + col;
      // Durakta boşalan satır yalnızca kısmen dolu: boş hücre patlamaz.
      // Atlanmazsa boşluklar gri blok gibi patlayıp koyu enkaz saçıyordu.
      final value = flash.cellValues[key];
      if (value == null || value == kEmptyCell) return;
      final delay = distance * _waveStep;
      final current = delays[key];
      if (current == null || delay < current) delays[key] = delay;
    }

    for (final r in flash.rows) {
      for (var c = 0; c < board.cols; c++) {
        final origin = flash.originCol;
        add(r, c, origin == null ? c.toDouble() : (c - origin).abs());
      }
    }
    for (final c in flash.columns) {
      for (var r = 0; r < board.rows; r++) {
        final origin = flash.originRow;
        add(r, c, origin == null ? r.toDouble() : (r - origin).abs());
      }
    }

    return <({int row, int col, int value, double delay})>[
      for (final entry in delays.entries)
        (
          row: entry.key ~/ board.cols,
          col: entry.key % board.cols,
          value: flash.cellValues[entry.key]!,
          delay: entry.value,
        ),
    ];
  }

  /// Dalga ulaşana kadar yerinde duran, sonra şişip beyazlaşan ve küçülerek
  /// kaybolan blok.
  void _paintPoppingBlock(
    Canvas canvas,
    ({int row, int col, int value, double delay}) cell,
    double t,
  ) {
    final u = ((t - cell.delay) / _popSpan).clamp(0.0, 1.0);
    if (u >= 1) return;

    final double scale;
    final double whiten;
    final double opacity;
    if (u < _popPeak) {
      final k = Curves.easeOutCubic.transform(u / _popPeak);
      scale = 1 + 0.16 * k;
      whiten = 0.75 * k;
      opacity = 1;
    } else {
      final k = Curves.easeInCubic.transform((u - _popPeak) / (1 - _popPeak));
      scale = 1.16 * (1 - k);
      whiten = 0.75 + 0.25 * k;
      opacity = 1 - k * 0.5;
    }
    if (scale <= 0.02) return;

    final rect = _cellRect(cell.row, cell.col);
    final scaled = Rect.fromCenter(
      center: rect.center,
      width: rect.width * scale,
      height: rect.height * scale,
    );
    _paintBlock(
      canvas,
      RRect.fromRectAndRadius(scaled, Radius.circular(cellSize * 0.20 * scale)),
      cell.value,
      whiten: whiten,
      opacity: opacity,
    );
  }

  /// Dalganın arkasında hat boyunca yumuşak parıltı. Aynı anda birden çok
  /// hat temizlenirse daha parlak yanar.
  void _paintBeams(Canvas canvas, BoardFlash flash, double t) {
    const span = 0.55;
    final k = (t / span).clamp(0.0, 1.0);
    if (k >= 1) return;

    // Hızlı yanar, yavaş söner.
    final envelope = k < 0.12 ? k / 0.12 : 1 - (k - 0.12) / 0.88;
    final strength = 0.30 + 0.12 * math.min(flash.lineCount, 3);
    final front = t / _waveStep; // dalganın ulaştığı mesafe, hücre biriminde
    final thickness = cellSize * (0.30 + 0.70 * (1 - k));

    final glow = Paint()
      ..color = Colors.white.withValues(alpha: strength * envelope)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.35);
    final core = Paint()
      ..color = Colors.white.withValues(
        alpha: (strength * 1.8 * envelope).clamp(0.0, 1.0),
      );

    void beam(Rect rect) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(thickness / 2)),
        glow,
      );
      final coreRect = Rect.fromCenter(
        center: rect.center,
        width: rect.width > rect.height ? rect.width : rect.width * 0.18,
        height: rect.width > rect.height ? rect.height * 0.18 : rect.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(coreRect, Radius.circular(cellSize * 0.1)),
        core,
      );
    }

    final boardWidth = board.cols * cellSize;
    final boardHeight = board.rows * cellSize;

    for (final r in flash.rows) {
      final origin = flash.originCol;
      final from = origin == null ? 0.0 : (origin + 0.5 - front) * cellSize;
      final to = origin == null
          ? (front + 1) * cellSize
          : (origin + 0.5 + front) * cellSize;
      final left = from.clamp(0.0, boardWidth);
      final right = to.clamp(0.0, boardWidth);
      if (right <= left) continue;
      beam(
        Rect.fromLTRB(
          left,
          (r + 0.5) * cellSize - thickness / 2,
          right,
          (r + 0.5) * cellSize + thickness / 2,
        ),
      );
    }
    for (final c in flash.columns) {
      final origin = flash.originRow;
      final from = origin == null ? 0.0 : (origin + 0.5 - front) * cellSize;
      final to = origin == null
          ? (front + 1) * cellSize
          : (origin + 0.5 + front) * cellSize;
      final top = from.clamp(0.0, boardHeight);
      final bottom = to.clamp(0.0, boardHeight);
      if (bottom <= top) continue;
      beam(
        Rect.fromLTRB(
          (c + 0.5) * cellSize - thickness / 2,
          top,
          (c + 0.5) * cellSize + thickness / 2,
          bottom,
        ),
      );
    }
  }

  /// Blok küçülmeye başladığı anda kendi renginde savrulan, dönen enkaz.
  ///
  /// Hareket yavaşlayarak açılır (easeOut) ve yerçekimiyle düşer; sabit
  /// hızla dağılan parçacık yapay duruyordu. Her dört parçadan biri küçük
  /// beyaz kıvılcım. Yönler hücre konumundan türetilen deterministik bir
  /// sözde-rastgeleden gelir, böylece karelerde titremez.
  void _paintDebris(
    Canvas canvas,
    BoardFlash flash,
    List<({int row, int col, int value, double delay})> cells,
    double t,
  ) {
    final perCell = 3 + math.min(flash.lineCount, 3);
    final power = 1 + 0.18 * (math.min(flash.lineCount, 4) - 1);
    final paint = Paint();

    for (final cell in cells) {
      final spawn = cell.delay + _popSpan * _popPeak;
      final q = (t - spawn) / _debrisSpan;
      if (q <= 0 || q >= 1) continue;

      final origin = _cellRect(cell.row, cell.col).center;
      final key = cell.row * board.cols + cell.col;
      final color = AppColors.forCellValue(cell.value);
      final travel = 1 - math.pow(1 - q, 3).toDouble();
      final alpha = math.pow(1 - q, 1.6).toDouble();

      for (var i = 0; i < perCell; i++) {
        final seed = key * 97 + i * 13;
        final spark = i % 4 == 3;
        final angle = _pseudoRandom(seed) * 2 * math.pi;
        final speed =
            cellSize *
            (0.7 + _pseudoRandom(seed + 1) * 1.5) *
            power *
            (spark ? 1.35 : 1);
        final position =
            origin +
            Offset(
              math.cos(angle) * speed * travel,
              math.sin(angle) * speed * travel + cellSize * 1.7 * q * q,
            );

        if (spark) {
          paint.color = Colors.white.withValues(alpha: alpha);
          canvas.drawCircle(position, cellSize * 0.06 * (1 - q * 0.5), paint);
          continue;
        }

        final size =
            cellSize * (0.13 + _pseudoRandom(seed + 2) * 0.13) * (1 - q * 0.55);
        final rotation = (_pseudoRandom(seed + 3) - 0.5) * 7 * travel;
        paint.color = color.withValues(alpha: alpha);

        canvas.save();
        canvas.translate(position.dx, position.dy);
        canvas.rotate(rotation);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: size, height: size),
            Radius.circular(size * 0.28),
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  /// Parçanın konduğu yerden yükselen "+N" ve varsa combo etiketi.
  void _paintPoints(Canvas canvas, BoardFlash flash, double t) {
    if (flash.points <= 0) return;

    final boardWidth = board.cols * cellSize;
    final boardHeight = board.rows * cellSize;
    final anchor = Offset(
      ((flash.originCol ?? (board.cols - 1) / 2) + 0.5) * cellSize,
      ((flash.originRow ?? (board.rows - 1) / 2) + 0.5) * cellSize,
    );

    final pop = t < 0.16 ? Curves.easeOutBack.transform(t / 0.16) : 1.0;
    final alpha = t < 0.72 ? 1.0 : 1 - (t - 0.72) / 0.28;
    final rise = cellSize * 1.1 * Curves.easeOutCubic.transform(t);

    final extra = math.min(flash.lineCount, 4) - 1;
    final label = TextPainter(
      text: TextSpan(
        text: '+${flash.points}',
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w800,
          fontSize: cellSize * (0.62 + 0.10 * extra),
          height: 1,
          color: Colors.white.withValues(alpha: alpha),
          shadows: <Shadow>[
            Shadow(
              color: Colors.black.withValues(alpha: 0.55 * alpha),
              blurRadius: cellSize * 0.18,
              offset: Offset(0, cellSize * 0.04),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    TextPainter? comboLabel;
    if (flash.combo >= 2) {
      comboLabel = TextPainter(
        text: TextSpan(
          text: 'COMBO x${flash.combo}',
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontWeight: FontWeight.w800,
            fontSize: cellSize * 0.30,
            letterSpacing: cellSize * 0.02,
            height: 1,
            color: AppColors.warning.withValues(alpha: alpha),
            shadows: <Shadow>[
              Shadow(
                color: Colors.black.withValues(alpha: 0.55 * alpha),
                blurRadius: cellSize * 0.14,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    final totalHeight =
        label.height + (comboLabel == null ? 0.0 : comboLabel.height + 4);
    final maxWidth = math.max(label.width, comboLabel?.width ?? 0.0);

    // Yazı tahtanın kenarından taşmasın.
    final centerX = anchor.dx
        .clamp(
          maxWidth / 2 + 4,
          math.max(maxWidth / 2 + 4, boardWidth - maxWidth / 2 - 4),
        )
        .toDouble();
    final top = (anchor.dy - totalHeight / 2 - rise)
        .clamp(4.0, math.max(4.0, boardHeight - totalHeight - 4))
        .toDouble();

    canvas.save();
    canvas.translate(centerX, top + totalHeight / 2);
    canvas.scale(pop);
    label.paint(canvas, Offset(-label.width / 2, -totalHeight / 2));
    comboLabel?.paint(
      canvas,
      Offset(-comboLabel.width / 2, -totalHeight / 2 + label.height + 4),
    );
    canvas.restore();
  }

  /// Deterministik sözde-rastgele, 0..1. Aynı tohum her karede aynı değeri
  /// verir; yoksa parçacıklar her frame'de yer değiştirir.
  double _pseudoRandom(int seed) {
    var x = (seed * 1103515245 + 12345) & 0x7fffffff;
    x = (x >> 16) ^ x;
    return ((x * 2654435761) & 0xffff) / 0xffff;
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.board != board || oldDelegate.cellSize != cellSize;
}
