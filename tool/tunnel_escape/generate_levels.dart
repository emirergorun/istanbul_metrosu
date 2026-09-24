// Tünele Kaç bölüm üretim aracı.
//
// Kullanım (proje kökünden):
//
//   dart run tool/tunnel_escape/generate_levels.dart pool <çıktı.json> [tohum] [tırmanış]
//   dart run tool/tunnel_escape/generate_levels.dart curate <havuz.json>...
//   dart run tool/tunnel_escape/generate_levels.dart report
//   dart run tool/tunnel_escape/generate_levels.dart solve <bölüm>
//
// Yöntem: **rastgele üret → çöz → ölç → seç → gönder.** Hiçbir bölüm
// "çözülebilir görünüyor" diye gönderilmez.
//
// 1. `pool`: rastgele dizilişler kurar, her birinin erişilebilen bütün durum
//    uzayını çıkarır ve o uzaydaki **en zor** başlangıcı (en uzun en kısa
//    çözüm) aday yapar. Zor bölümler için tepe tırmanma: bir metroyu
//    oynat/ekle/çıkar, en zor başlangıç uzuyorsa değişikliği tut.
// 2. `curate`: adaylardan zorluk eğrisine uyanları seçer ve
//    `lib/features/games/tunnel_escape/data/escape_levels.dart` dosyasını
//    yazar. İlk iki bölüm elle tasarlandı (öğretici), araç onları da çözücüyle
//    doğrular.
// 3. `report`: gönderilen bölümlerin zorluk tablosunu basar.
// 4. `solve`: bir bölümün tahtasını ve en kısa çözümünü adım adım basar.
//
// Alan katmanı saf Dart olduğu için araç oyunun kendi çözücüsünü kullanıyor;
// oyundaki kural ile bölümü doğrulayan kural ayrı düşemez.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:istanbul_metro_game/features/games/tunnel_escape/data/escape_levels.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_analysis.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_board.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_heuristics.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_level.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_piece.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_rules.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_solver.dart';

const int side = 6;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('pool | curate | report');
    exit(64);
  }
  switch (args.first) {
    case 'pool':
      final out = args.length > 1 ? args[1] : 'pool.json';
      final seed = args.length > 2 ? int.parse(args[2]) : 1;
      final climbs = args.length > 3 ? int.parse(args[3]) : 30;
      _pool(out, seed, climbs);
    case 'curate':
      _curate(args.skip(1).toList());
    case 'report':
      _report();
    case 'solve':
      _solve(int.parse(args[1]));
    default:
      stderr.writeln('Bilinmeyen komut: ${args.first}');
      exit(64);
  }
}

// ---------------------------------------------------------------------------
// Aday
// ---------------------------------------------------------------------------

/// Bir aday bölüm ve ölçüleri.
class Candidate {
  Candidate({
    required this.grid,
    required this.optimal,
    required this.blockers,
    required this.states,
    required this.moved,
    required this.branching,
    required this.detours,
    required this.depth,
  });

  factory Candidate.fromJson(Map<String, dynamic> json) => Candidate(
    grid: (json['grid'] as List<dynamic>).cast<String>(),
    optimal: json['optimal'] as int,
    blockers: json['blockers'] as int,
    states: json['states'] as int,
    moved: json['moved'] as int,
    branching: (json['branching'] as num).toDouble(),
    detours: json['detours'] as int,
    depth: json['depth'] as int,
  );

  final List<String> grid;
  final int optimal;

  /// Beyaz metro sayısı.
  final int blockers;

  /// Erişilebilen durum sayısı.
  final int states;

  /// En kısa çözümde en az bir kez oynayan farklı metro sayısı (hedef dahil).
  final int moved;

  /// En kısa çözüm boyunca ortalama yasal hamle sayısı.
  final double branching;

  /// Bütün en kısa çözümlerde kaçınılmaz "geri" hamle sayısı
  /// ([EscapeLevelStats.minimumDetours]).
  final int detours;

  /// Başlangıçtaki bağımlılık zinciri ([EscapeHeuristics.dependencyDepth]).
  final int depth;

  /// Açgözlü oyuncunun bitirme oranı — pahalı, yalnız seçimde hesaplanır.
  double get greedy => _greedy ??= _measureGreedy();
  double? _greedy;

  double _measureGreedy() {
    final (layout, start) = EscapeLevel.parseGrid(grid);
    final runs = EscapeHeuristics(layout).greedyRuns(start);
    final limit = max(12, optimal * 3);
    return runs.where((int? r) => r != null && r <= limit).length / runs.length;
  }

  /// Hamle başına düşünme yükü: zorunlu geri hamlenin çözüme oranı.
  double get detourDensity => optimal == 0 ? 0 : detours / optimal;

  /// Tahtadaki metroların (hedef dahil) çözüme katılan payı.
  double get involvement => moved / (blockers + 1);

  /// Aynı metro takımı (şerit, eksen, uzunluk) — aynı bulmacanın ailesi.
  ///
  /// Hangi arabanın kırmızı olduğu aileyi değiştirmez: aynı düzende
  /// başka bir yatay ikiliyi hedef yapmak durum uzayını aynen korur,
  /// oyuncuya aynı tahta gibi görünür.
  ///
  /// Aynalar da aynı aile sayılır. Dikey ayna aynı bulmacanın baş aşağı
  /// hâli; yatay ayna ise durum uzayı birebir aynı, yalnız tünel öbür
  /// yanda kalan bir bulmaca — oyuncuya "bunun aynasını oynadım" dedirtir.
  String get family {
    final (layout, _) = EscapeLevel.parseGrid(grid);
    String key(bool flipRows, bool flipCols) {
      final parts = <String>[
        for (final p in layout.pieces)
          '${p.isHorizontal ? 'h' : 'v'}${p.length}@'
              '${p.isHorizontal ? (flipRows ? layout.height - 1 - p.lane : p.lane) : (flipCols ? layout.width - 1 - p.lane : p.lane)}',
      ]..sort();
      return parts.join(',');
    }

    final keys = <String>[
      key(false, false),
      key(true, false),
      key(false, true),
      key(true, true),
    ]..sort();
    return keys.first;
  }

  /// Durum uzayının parmak izi: aynı büyüklükte uzay ve aynı en kısa
  /// çözüm, farklı harflerle yazılmış aynı bulmacanın işareti.
  ///
  /// Büyük uzaylarda durum sayısı tek başına yeter: binlerce durumluk iki
  /// uzayın aynı büyüklükte olması, aynı düzenin başka bir hâli demek.
  String get fingerprint => states >= 2000 ? '$states' : '$states/$optimal';

  /// Metroların tahtadaki yerleri (eksen, uzunluk, şerit, konum).
  ///
  /// Tepe tırmanma art arda gelen adımlarda tek metroyu değiştiriyor;
  /// iki aday aynı ailede olmasa da metroların çoğu aynı yerde durabilir.
  /// Oyuncu bunu "bunu az önce oynadım" diye okur.
  List<String> placements({bool flipRows = false, bool flipCols = false}) {
    final (layout, start) = EscapeLevel.parseGrid(grid);
    final out = <String>[];
    for (var i = 0; i < layout.pieceCount; i++) {
      final p = layout.pieces[i];
      var lane = p.lane;
      var pos = start[i];
      if (p.isHorizontal) {
        if (flipRows) lane = layout.height - 1 - lane;
        if (flipCols) pos = layout.width - p.length - pos;
      } else {
        if (flipCols) lane = layout.width - 1 - lane;
        if (flipRows) pos = layout.height - p.length - pos;
      }
      out.add('${p.isHorizontal ? 'h' : 'v'}${p.length}@$lane:$pos');
    }
    return out;
  }

  /// İki adayın görsel benzerliği: aynı yerde duran metroların payı
  /// (dört ayna hâlinin en yükseği).
  double similarityTo(Candidate other) {
    final mine = placements();
    var best = 0.0;
    for (final flipRows in <bool>[false, true]) {
      for (final flipCols in <bool>[false, true]) {
        final theirs = other
            .placements(flipRows: flipRows, flipCols: flipCols)
            .toSet();
        final shared = mine.where(theirs.contains).length;
        final total = mine.length > theirs.length ? mine.length : theirs.length;
        final ratio = shared / total;
        if (ratio > best) best = ratio;
      }
    }
    return best;
  }

  Map<String, Object> toJson() => <String, Object>{
    'grid': grid,
    'optimal': optimal,
    'blockers': blockers,
    'states': states,
    'moved': moved,
    'branching': double.parse(branching.toStringAsFixed(2)),
    'detours': detours,
    'depth': depth,
  };
}

/// Dizilişin durum uzayını açar, en zor başlangıcı aday yapar.
///
/// Çözülemeyen ya da [minOptimal]'dan kısa olan diziliş `null` döner.
Candidate? evaluate(
  EscapeLayout layout,
  List<int> positions, {
  int minOptimal = 2,
}) {
  final solver = EscapeSolver(layout, maxStates: 400000);
  final EscapeComponent component;
  try {
    component = solver.explore(positions);
  } on StateError {
    return null;
  }
  if (!component.isSolvable) return null;
  final hardest = component.maxDistance;
  if (hardest < minOptimal) return null;

  // Eşit zorluktaki başlangıçlardan hedefi tünele en uzak olanı; o da eşitse
  // en küçük anahtar. Sonuç tohuma değil yalnız dizilişe bağlı.
  int? pick;
  var pickTarget = 99;
  for (final key in component.states) {
    if (component.distance[key] != hardest) continue;
    final target = layout.positionIn(key, layout.targetIndex);
    if (pick == null ||
        target < pickTarget ||
        (target == pickTarget && key < pick)) {
      pick = key;
      pickTarget = target;
    }
  }
  final start = layout.positionsOf(pick!);
  return _measure(layout, start, solver, component);
}

/// Başlangıcı belli bir tahtanın ölçüleri. [component] aynı bileşenin
/// haritası: en zor başlangıç da elle yazılmış başlangıç da oradadır.
Candidate _measure(
  EscapeLayout layout,
  List<int> start,
  EscapeSolver solver,
  EscapeComponent component,
) {
  final solution = solver.solve(start)!;
  final movedPieces = <int>{for (final m in solution.path) m.piece};

  var branchingSum = 0;
  var key = layout.keyOf(start);
  for (final move in solution.path) {
    branchingSum += solver.branching(key);
    key = layout.keyWith(key, move.piece, move.to);
  }

  final heuristics = EscapeHeuristics(layout);
  return Candidate(
    grid: EscapeLevel.render(layout, start),
    optimal: solution.moves,
    blockers: layout.pieceCount - 1,
    states: component.size,
    moved: movedPieces.length,
    branching: branchingSum / solution.moves,
    detours: EscapeLevelStats.minimumDetours(
      layout,
      start,
      solver,
      component,
      heuristics,
    ),
    depth: heuristics.dependencyDepth(start),
  );
}

// ---------------------------------------------------------------------------
// Rastgele diziliş ve mutasyon
// ---------------------------------------------------------------------------

/// Düzenlenebilir diziliş: metrolar ve konumları.
class Arrangement {
  Arrangement(this.pieces, this.positions);

  final List<EscapePiece> pieces;
  final List<int> positions;

  Arrangement copy() =>
      Arrangement(List<EscapePiece>.of(pieces), List<int>.of(positions));

  int occupancyWithout(int skip) {
    var mask = 0;
    for (var i = 0; i < pieces.length; i++) {
      if (i == skip) continue;
      mask |= maskOf(pieces[i], positions[i]);
    }
    return mask;
  }

  static int maskOf(EscapePiece piece, int position) {
    var mask = 0;
    for (final (row, col) in piece.cellsAt(position)) {
      mask |= 1 << (row * side + col);
    }
    return mask;
  }

  EscapeLayout? toLayout() {
    try {
      return EscapeLayout(width: side, height: side, pieces: pieces);
    } on ArgumentError {
      return null;
    }
  }
}

const String _letters = 'ABCDEFGHIJKLMNOPQSTUVWXYZ';

/// Hedefi [exitRow]'a koyup [blockers] beyaz metroyu rastgele yerleştirir.
Arrangement? randomArrangement(Random random, int blockers, {int exitRow = 2}) {
  final pieces = <EscapePiece>[
    EscapePiece(
      id: EscapeLevel.targetId,
      axis: EscapeAxis.horizontal,
      length: 2,
      lane: exitRow,
      isTarget: true,
    ),
  ];
  final positions = <int>[random.nextInt(side - 2)];
  var occupied = Arrangement.maskOf(pieces.first, positions.first);

  for (var n = 0; n < blockers; n++) {
    var placed = false;
    for (var attempt = 0; attempt < 60 && !placed; attempt++) {
      final piece = _randomPiece(random, _letters[n], exitRow);
      final position = random.nextInt(side - piece.length + 1);
      final mask = Arrangement.maskOf(piece, position);
      if (mask & occupied != 0) continue;
      pieces.add(piece);
      positions.add(position);
      occupied |= mask;
      placed = true;
    }
    if (!placed) return null;
  }
  return Arrangement(pieces, positions);
}

EscapePiece _randomPiece(Random random, String id, int exitRow) {
  final length = random.nextDouble() < 0.72 ? 2 : 3;
  // Hedefin satırına yatay metro konmaz: sağında dursa bölüm çözülemez,
  // solunda dursa hiçbir şey yapmaz.
  final horizontal = random.nextBool();
  var lane = random.nextInt(side);
  if (horizontal) {
    while (lane == exitRow) {
      lane = random.nextInt(side);
    }
  }
  return EscapePiece(
    id: id,
    axis: horizontal ? EscapeAxis.horizontal : EscapeAxis.vertical,
    length: length,
    lane: lane,
  );
}

/// Dizilişte küçük bir değişiklik: metro taşı, ekle ya da çıkar.
Arrangement? mutate(Arrangement base, Random random, {required int exitRow}) {
  final next = base.copy();
  final roll = random.nextDouble();
  final blockers = next.pieces.length - 1;

  if (roll < 0.12 && blockers < 14) {
    // Ekle.
    final occupied = next.occupancyWithout(-1);
    for (var attempt = 0; attempt < 40; attempt++) {
      final piece = _randomPiece(random, _letters[blockers], exitRow);
      final position = random.nextInt(side - piece.length + 1);
      if (Arrangement.maskOf(piece, position) & occupied != 0) continue;
      next.pieces.add(piece);
      next.positions.add(position);
      return _relabel(next);
    }
    return null;
  }
  if (roll < 0.20 && blockers > 3) {
    // Çıkar.
    final victim = 1 + random.nextInt(blockers);
    next.pieces.removeAt(victim);
    next.positions.removeAt(victim);
    return _relabel(next);
  }
  // Taşı: bir beyaz metroyu yeni bir yere, yeni bir eksenle.
  if (blockers == 0) return null;
  final index = 1 + random.nextInt(blockers);
  final occupied = next.occupancyWithout(index);
  for (var attempt = 0; attempt < 40; attempt++) {
    final piece = _randomPiece(random, next.pieces[index].id, exitRow);
    final position = random.nextInt(side - piece.length + 1);
    if (Arrangement.maskOf(piece, position) & occupied != 0) continue;
    next.pieces[index] = piece;
    next.positions[index] = position;
    return next;
  }
  return null;
}

/// Harfleri sırayla yeniden verir: ekle/çıkar sonrası boşluk kalmasın.
Arrangement _relabel(Arrangement arrangement) {
  final pieces = <EscapePiece>[arrangement.pieces.first];
  for (var i = 1; i < arrangement.pieces.length; i++) {
    final p = arrangement.pieces[i];
    pieces.add(
      EscapePiece(
        id: _letters[i - 1],
        axis: p.axis,
        length: p.length,
        lane: p.lane,
      ),
    );
  }
  return Arrangement(pieces, arrangement.positions);
}

// ---------------------------------------------------------------------------
// pool
// ---------------------------------------------------------------------------

void _pool(String out, int seed, int climbs) {
  final random = Random(seed);
  final byGrid = <String, Candidate>{};

  void keep(Candidate c) => byGrid.putIfAbsent(c.grid.join('/'), () => c);

  final watch = Stopwatch()..start();

  // 1. Rastgele örnekler: her yoğunluktan.
  for (var blockers = 2; blockers <= 13; blockers++) {
    var found = 0;
    for (var sample = 0; sample < 500; sample++) {
      final exitRow = random.nextInt(10) < 7 ? 2 : 1 + random.nextInt(4);
      final arrangement = randomArrangement(random, blockers, exitRow: exitRow);
      if (arrangement == null) continue;
      final layout = arrangement.toLayout();
      if (layout == null) continue;
      final candidate = evaluate(layout, arrangement.positions, minOptimal: 3);
      if (candidate == null) continue;
      keep(candidate);
      found++;
    }
    stderr.writeln(
      'rastgele $blockers engel: $found aday, toplam ${byGrid.length} '
      '(${watch.elapsed.inSeconds} sn)',
    );
  }

  // 2. Tepe tırmanma, iki amaçla sırayla:
  //
  // * uzun: en kısa çözüm ve zorunlu geri hamle birlikte uzasın (geç
  //   bölümler);
  // * sıkı: az metroyla çok geri hamle — zorluğu kalabalıktan değil akıl
  //   yürütmeden alan orta bölümler. Metro sayısı [_compactMax]'ı geçemez.
  for (var climb = 0; climb < climbs; climb++) {
    final compact = climb.isOdd;
    final exitRow = climb % 3 == 0 ? 1 + random.nextInt(4) : 2;
    double scoreOf(Candidate c) => compact
        ? c.detours * 3.0 + c.optimal - c.blockers * 0.8
        : c.optimal + c.detours * 2.0;

    Arrangement? current;
    Candidate? currentScore;
    for (var attempt = 0; attempt < 50 && currentScore == null; attempt++) {
      current = randomArrangement(
        random,
        compact ? 5 + random.nextInt(3) : 9 + random.nextInt(4),
        exitRow: exitRow,
      );
      final layout = current?.toLayout();
      if (layout == null) continue;
      currentScore = evaluate(layout, current!.positions, minOptimal: 2);
    }
    if (current == null || currentScore == null) continue;

    for (var step = 0; step < 1000; step++) {
      final next = mutate(current!, random, exitRow: exitRow);
      final layout = next?.toLayout();
      if (next == null || layout == null) continue;
      if (compact && next.pieces.length - 1 > _compactMax) continue;
      final score = evaluate(layout, next.positions, minOptimal: 2);
      if (score == null) continue;
      // Eşit zorluğu da kabul et: platoda yürümek yerel tepeden çıkarır.
      if (scoreOf(score) >= scoreOf(currentScore!)) {
        current = next;
        currentScore = score;
        if (score.optimal >= 5) keep(score);
      }
    }
    stderr.writeln(
      'tırmanış $climb (${compact ? 'sıkı' : 'uzun'}): '
      '${currentScore!.optimal} hamle, ${currentScore.detours} geri, '
      '${currentScore.blockers} engel (${watch.elapsed.inSeconds} sn)',
    );
  }

  final list = byGrid.values.toList()
    ..sort((a, b) => a.optimal.compareTo(b.optimal));
  File(out).writeAsStringSync(
    const JsonEncoder.withIndent(
      ' ',
    ).convert(<Object>[for (final c in list) c.toJson()]),
  );
  final histogram = <int, int>{};
  for (final c in list) {
    histogram[c.optimal] = (histogram[c.optimal] ?? 0) + 1;
  }
  stderr.writeln('Havuz: ${list.length} aday → $out');
  stderr.writeln(
    'Dağılım: ${(histogram.keys.toList()..sort()).map((k) => '$k:${histogram[k]}').join(' ')}',
  );
}

// ---------------------------------------------------------------------------
// curate
// ---------------------------------------------------------------------------

/// Sıkı tırmanışta en fazla beyaz metro.
const int _compactMax = 9;

/// İlk iki bölüm elle: mekaniği metinsiz öğretmeleri gerekiyor.
///
/// 1. Tek beyaz metro kırmızının önünde; aşağı ya da yukarı kaydırmak
///    yolu açıyor. Başka anlamlı hamle yok.
/// 2. Dikey metro yalnız aşağı inebilir, altında da yatay bir metro var:
///    önce yatayı kaydır (ikinci eksen), sonra dikeyi, sonra kırmızıyı.
const List<List<String>> _handmade = <List<String>>[
  <String>['......', '......', 'RR..A.', '....A.', '......', '......'],
  <String>['......', '....A.', 'RR..A.', '....A.', '......', '...BB.'],
];

/// Zorluk eğrisi: bölüm başına hedeflenen en kısa çözüm uzunluğu.
///
/// Kuşaklar: 1-5 öğret, 6-15 düşün, 16-30 planla, 31-45 çöz, 46-59
/// ustalaş, 60 son durak. Kuşak içinde düz artmıyor: iki zor bölümden sonra
/// bir **nefes** bölümü geliyor (zor → zor → orta → daha zor). Oyuncu iki
/// zor bölüm arasında kendini akıllı hissetmeli.
///
/// Hamle sayısı zorluğun yalnız bir yüzü. Asıl ayar [_detourBand] ve
/// [_maxGreedy]: kuşak ilerledikçe çözüm daha çok "önce uzaklaş" anı
/// istiyor ve göze iyi gelen hamleyle bitirilemiyor.
const List<int> _curve = <int>[
  // 1-5 öğret
  2, 3, 4, 5, 6,
  // 6-15 düşün
  6, 7, 8, 7, 9, 10, 8, 10, 11, 12,
  // 16-30 planla
  11, 12, 13, 12, 14, 15, 13, 15, 16, 17, 15, 17, 18, 19, 19,
  // 31-45 çöz
  17, 19, 20, 18, 21, 22, 20, 23, 24, 22, 25, 25, 23, 26, 27,
  // 46-59 ustalaş
  24, 26, 28, 25, 29, 30, 27, 31, 32, 29, 33, 34, 35, 36,
  // 60 son durak — [_finaleRange] içindeki en iyi aday
  99,
];

/// Son durağın hamle aralığı.
///
/// Havuzda 50 hamleyi aşan bulmacalar da var, ama onlar "adil" değil: iyi
/// oyuncu bile ipucusuz bitiremez. Son durak öncekilerden **belirgin
/// biçimde** zor (ustalık kuşağı 36'da bitiyor) ama çözülebilir kalmalı.
const (int, int) _finaleRange = (40, 46);

/// Bölümün zorunlu geri hamle bandı (bütün en kısa çözümlerde).
///
/// Alt sınır bölümün "gözle çözülmemesini", üst sınır adil kalmasını
/// sağlıyor: 11 hamlelik bir bölümde beş "önce uzaklaş" anı, düşün
/// kuşağında zorluk değil yorgunluktur. Band kuşak içinde de ilerliyor.
(int, int) _detourBand(int number) {
  if (number <= 5) return (0, 1);
  if (number <= 9) return (1, 2);
  if (number <= 15) return (2, 3);
  if (number <= 22) return (3, 4);
  if (number <= 30) return (4, 5);
  if (number <= 37) return (4, 6);
  if (number <= 45) return (5, 7);
  if (number <= 59) return (6, 9);
  return (7, 12);
}

/// Açgözlü oyuncunun en fazla bitirme oranı: bu oranın üstündeki bölüm
/// "gözle çözülüyor" sayılır. Öğreticide sınır yok — orası gözle çözülsün.
double _maxGreedy(int number) => switch (EscapeTier.of(number)) {
  EscapeTier.onboarding => 1,
  EscapeTier.understanding => number < 10 ? 0.8 : 0.5,
  EscapeTier.planning => 0.25,
  EscapeTier.mastery => 0.1,
  EscapeTier.expert => 0.05,
  EscapeTier.finale => 0.05,
};

/// Seçilmiş bir bölüme bundan fazla benzeyen aday elenir.
const double _maxSimilarity = 0.6;

void _curate(List<String> pools) {
  final byGrid = <String, Candidate>{};
  for (final path in pools) {
    final raw = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
    for (final e in raw) {
      final c = Candidate.fromJson(e as Map<String, dynamic>);
      byGrid.putIfAbsent(c.grid.join('/'), () => c);
    }
  }
  final candidates = byGrid.values.toList();
  stderr.writeln('${candidates.length} aday okundu');

  final usedFamilies = <String>{};
  final usedGrids = <String>{};
  final usedPrints = <String>{};
  final picked = <int, Candidate>{};

  void take(int number, Candidate c) {
    picked[number] = c;
    usedFamilies.add(c.family);
    usedGrids.add(c.grid.join('/'));
    usedPrints.add(c.fingerprint);
  }

  bool fresh(Candidate c) {
    if (usedGrids.contains(c.grid.join('/'))) return false;
    if (usedPrints.contains(c.fingerprint)) return false;
    if (usedFamilies.contains(c.family)) return false;
    // Küçük tahtada (öğretici bölümler) tek ortak metro bile oranı
    // yükseltir; benzerlik yalnız kalabalık tahtalarda anlamlı.
    return c.blockers < 5 ||
        !picked.values.any(
          (Candidate o) =>
              o.blockers >= 5 && o.similarityTo(c) > _maxSimilarity,
        );
  }

  // Son durak önce seçilir: en iyi finali geç bölümlerin benzerlik ve aile
  // kuralları elemeden alsın.
  final order = <int>[
    _curve.length - 1,
    for (var i = 0; i < _curve.length - 1; i++) i,
  ];
  for (final i in order) {
    final number = i + 1;
    if (number <= _handmade.length) {
      final (layout, start) = EscapeLevel.parseGrid(_handmade[i]);
      take(number, evaluateExact(layout, start));
      continue;
    }

    final tier = EscapeTier.of(number);
    final want = _curve[i];
    bool inRange(Candidate c, int slack) => want == 99
        ? c.optimal >= _finaleRange.$1 && c.optimal <= _finaleRange.$2
        : (c.optimal - want).abs() <= slack;

    // Önce tam kurallarla; bulunamazsa önce geri hamle şartı bir gevşer,
    // sonra hamle sayısı bir oynar. Her gevşeme raporlanır.
    Candidate? best;
    for (final (slack, detourRelief) in const <(int, int)>[
      (0, 0),
      (0, 1),
      (1, 0),
      (1, 1),
    ]) {
      final (fewest, most) = _detourBand(number);
      final matches =
          candidates
              .where(
                (Candidate c) =>
                    inRange(c, slack) &&
                    c.detours >= fewest - detourRelief &&
                    c.detours <= most + detourRelief &&
                    _fits(tier, number, c),
              )
              .toList()
            ..sort(
              (Candidate a, Candidate b) =>
                  _quality(tier, b).compareTo(_quality(tier, a)),
            );
      var checked = 0;
      for (final c in matches) {
        if (!fresh(c)) continue;
        if (c.greedy > _maxGreedy(number)) continue;
        best = c;
        break;
      }
      checked = matches.length;
      if (best != null) {
        if (slack > 0 || detourRelief > 0) {
          stderr.writeln(
            'Bölüm $number: gevşetildi (hamle ±$slack, geri -$detourRelief), '
            '$checked aday',
          );
        }
        break;
      }
    }
    if (best == null) {
      stderr.writeln('Bölüm $number için $want hamlelik aday yok!');
      exit(1);
    }
    take(number, best);
  }

  _write(<Candidate>[for (var n = 1; n <= _curve.length; n++) picked[n]!]);
}

/// Kuşağın kaba sınırları: öğretici bölümde kalabalık, ileri bölümlerde boş
/// tahta istemiyoruz. Zorluk metro sayısından gelmesin diye üst sınır
/// ustalık kuşağında bile tahtayı doldurmuyor.
bool _fits(EscapeTier tier, int number, Candidate c) {
  final (minBlockers, maxBlockers) = switch (tier) {
    EscapeTier.onboarding => (1, 4),
    EscapeTier.understanding => (3, 8),
    EscapeTier.planning => (4, 10),
    EscapeTier.mastery => (5, 12),
    EscapeTier.expert => (6, 13),
    EscapeTier.finale => (6, 14),
  };
  if (c.blockers < minBlockers || c.blockers > maxBlockers) return false;
  if (tier == EscapeTier.onboarding) {
    // Öğreticide her metro çözüme katılmalı: süs metro yeni oyuncuyu
    // yanıltır. En çok bir geri hamle; beşinci bölüm ilk küçük zinciri
    // (C → B → A) tanıtır.
    if (c.moved != c.blockers + 1) return false;
    if (number == 5 && c.depth < 3) return false;
  }
  return c.involvement >= 0.5;
}

/// Aynı hamle sayısındaki uygun adaylardan hangisi daha iyi bir bölüm?
///
/// Düşünme yükü (zorunlu geri hamle, zincir) yüksek olsun; çözüme katılan
/// metro payı yüksek olsun (süs metro az); kuşağın rahat yoğunluğunu aşan
/// her metro cezalı — zorluk kalabalıktan gelmesin.
double _quality(EscapeTier tier, Candidate c) {
  final comfortable = switch (tier) {
    EscapeTier.onboarding => 3,
    EscapeTier.understanding => 6,
    EscapeTier.planning => 8,
    EscapeTier.mastery => 9,
    EscapeTier.expert => 10,
    EscapeTier.finale => 11,
  };
  var score = c.detours * 2.0 + c.involvement * 4 + min(c.depth, 7) * 0.4;
  score -= max(0, c.blockers - comfortable) * 0.8;
  if (tier == EscapeTier.onboarding) score -= c.blockers * 0.5;
  if (tier.index >= EscapeTier.mastery.index) score += log(c.states) * 0.2;
  return score;
}

/// Elle yazılmış bölüm: en zor başlangıç değil, **olduğu gibi** çözülür.
Candidate evaluateExact(EscapeLayout layout, List<int> start) {
  final solver = EscapeSolver(layout);
  if (solver.solve(start) == null) {
    throw StateError('Elle yazılmış bölüm çözülemiyor');
  }
  return _measure(layout, start, solver, solver.explore(start));
}

void _write(List<Candidate> chosen) {
  final buffer = StringBuffer()
    ..writeln(
      '// Bu dosya `tool/tunnel_escape/generate_levels.dart curate` ile üretildi.',
    )
    ..writeln('// Elle düzenlenebilir; her değişiklikten sonra bölüm testi')
    ..writeln(
      '// (`test/tunnel_escape/escape_levels_test.dart`) çözücüyle yeniden doğrular.',
    )
    ..writeln()
    ..writeln("import '../domain/escape_level.dart';")
    ..writeln()
    ..writeln('/// Gönderilen 60 bölüm, ızgara metni olarak.')
    ..writeln('///')
    ..writeln(
      '/// Sütunlar: en kısa çözüm (çözücü), üç yıldız ve iki yıldız sınırı.',
    )
    ..writeln(
      '/// Sınırların nasıl hesaplandığı [EscapeRules.parFor] üzerinde.',
    )
    ..writeln(
      'const List<EscapeLevelData> escapeLevelData = <EscapeLevelData>[',
    );
  for (var i = 0; i < chosen.length; i++) {
    final c = chosen[i];
    final (three, two) = EscapeRules.parFor(
      optimal: c.optimal,
      branching: c.branching,
    );
    buffer
      ..writeln('  EscapeLevelData(')
      ..writeln('    number: ${i + 1},')
      ..writeln('    optimalMoves: ${c.optimal},')
      ..writeln('    threeStarMoves: $three,')
      ..writeln('    twoStarMoves: $two,')
      ..writeln('    grid: <String>[');
    for (final row in c.grid) {
      buffer.writeln("      '$row',");
    }
    buffer
      ..writeln('    ],')
      ..writeln('  ),');
  }
  buffer.writeln('];');
  final path = 'lib/features/games/tunnel_escape/data/escape_level_grids.dart';
  File(path).writeAsStringSync(buffer.toString());
  stderr.writeln('${chosen.length} bölüm → $path');
  for (var i = 0; i < chosen.length; i++) {
    final c = chosen[i];
    stderr.writeln(
      '${(i + 1).toString().padLeft(2)}  en iyi ${c.optimal.toString().padLeft(2)}  '
      'engel ${c.blockers.toString().padLeft(2)}  katılım ${(c.involvement * 100).round()}%  '
      'durum ${c.states}',
    );
  }
}

// ---------------------------------------------------------------------------
// report
// ---------------------------------------------------------------------------

void _report() {
  stdout.writeln(
    'BÖLÜM | EN İYİ | ENGEL | ZİNCİR | GERİ | AÇGÖZLÜ | DURUM | DALLANMA | ZORLUK',
  );
  for (final level in EscapeLevels.all) {
    final stats = EscapeLevelStats.of(level);
    stdout.writeln(
      '${level.number.toString().padLeft(5)} | '
      '${stats.optimal.toString().padLeft(6)} | '
      '${stats.blockers.toString().padLeft(5)} | '
      '${stats.dependencyDepth.toString().padLeft(6)} | '
      '${stats.detours.toString().padLeft(4)} | '
      '${'${(stats.greedySolveRate * 100).round()}%'.padLeft(7)} | '
      '${stats.states.toString().padLeft(6)} | '
      '${stats.branching.toStringAsFixed(1).padLeft(8)} | '
      '${stats.difficulty.toStringAsFixed(1).padLeft(6)}',
    );
  }
}

// ---------------------------------------------------------------------------
// solve
// ---------------------------------------------------------------------------

void _solve(int number) {
  final level = EscapeLevels.byNumber(number);
  if (level == null) {
    stderr.writeln('Bölüm $number yok');
    exit(64);
  }
  final solution = EscapeSolver(level.layout).solve(level.start)!;
  stdout.writeln('Bölüm $number — ${solution.moves} hamle');
  EscapeLevel.render(level.layout, level.start).forEach(stdout.writeln);
  for (final move in solution.path) {
    final piece = level.pieces[move.piece];
    final direction = piece.isHorizontal
        ? (move.to > move.from ? 'sağa' : 'sola')
        : (move.to > move.from ? 'aşağı' : 'yukarı');
    stdout.writeln(
      '${piece.id} ${(move.to - move.from).abs()} $direction '
      '(${move.from} → ${move.to})',
    );
  }
}
