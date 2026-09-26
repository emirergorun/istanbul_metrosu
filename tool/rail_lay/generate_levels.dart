// Ray Döşe bölüm üretim aracı.
//
// Kullanım (proje kökünden):
//
//   dart run tool/rail_lay/generate_levels.dart pool <çıktı.json> [tohum] [adet]
//   dart run tool/rail_lay/generate_levels.dart curate <havuz.json>...
//   dart run tool/rail_lay/generate_levels.dart report
//   dart run tool/rail_lay/generate_levels.dart solve <bölüm>
//
// Yöntem, Tünele Kaç aracıyla aynı: **rastgele üret → çöz → ölç → seç →
// gönder.** Hiçbir bölüm "çözülebilir görünüyor" diye gönderilmez.
//
// Önceki sürüm bölümleri çalışma anında tek bir kayış zinciriyle oyuyordu.
// Çözülebilirlik garantiydi ama tahta bir koridor ağacına dönüyordu: her
// duruşta yeni kare döşeyen tek bir yön kalıyor, oyuncu o yöne gidip
// bölümü "hiçbir başarı olmadan" bitiriyordu (kullanıcı 16 bölüm oynayıp
// zorlanmadı). Şimdi her aday çözücüyle bütün durum uzayı taranarak
// ölçülüyor ve bölümler **seçim** ve **tuzak** sayısına göre seçiliyor.
//
// 1. `pool`: üç şekil ailesinden adaylar kurar (oyulmuş koridor, içine
//    duvar serpilmiş oda, birleşik odalar), en zor başlangıcı bulur ve
//    tepe tırmanmayla (bir duvar aç/kapat) zorlaştırır.
// 2. `curate`: adaylardan zorluk eğrisine uyanları seçer ve
//    `lib/features/games/rail_lay/data/rail_lay_level_grids.dart` dosyasını
//    yazar.
// 3. `report`: gönderilen bölümlerin zorluk tablosunu basar.
// 4. `solve`: bir bölümün tahtasını ve en kısa çözümünü basar.
//
// Alan katmanı saf Dart olduğu için araç oyunun kendi çözücüsünü kullanır.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:istanbul_metro_game/features/games/rail_lay/data/rail_lay_levels.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_solver.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_state.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('pool | curate | report | solve');
    exit(64);
  }
  switch (args.first) {
    case 'pool':
      final out = args.length > 1 ? args[1] : 'rail_lay_pool.json';
      final seed = args.length > 2 ? int.parse(args[2]) : 1;
      final count = args.length > 3 ? int.parse(args[3]) : 1500;
      _pool(out, seed, count);
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

/// Havuzdaki bir aday: kırpılmış ızgara ve ölçüleri.
class Candidate {
  Candidate({required this.rows, required this.analysis});

  factory Candidate.fromJson(Map<String, Object?> json) => Candidate(
    rows: (json['rows']! as List<Object?>).cast<String>(),
    analysis: RailLayAnalysis(
      optimal: json['optimal']! as int,
      solution: _decode(json['solution']! as String),
      decisions: json['decisions']! as int,
      traps: json['traps']! as int,
      states: json['states']! as int,
      deadShare: (json['dead']! as num).toDouble(),
    ),
  );

  final List<String> rows;
  final RailLayAnalysis analysis;

  int get open => rows.join().replaceAll('#', '').length;
  int get width => rows.first.length;
  int get height => rows.length;
  String get key => rows.join('/');

  Map<String, Object?> toJson() => <String, Object?>{
    'rows': rows,
    'optimal': analysis.optimal,
    'solution': _encode(analysis.solution),
    'decisions': analysis.decisions,
    'traps': analysis.traps,
    'states': analysis.states,
    'dead': analysis.deadShare,
  };
}

String _encode(List<RailLayDirection> moves) => moves
    .map(
      (RailLayDirection d) => switch (d) {
        RailLayDirection.up => 'U',
        RailLayDirection.down => 'D',
        RailLayDirection.left => 'L',
        RailLayDirection.right => 'R',
      },
    )
    .join();

List<RailLayDirection> _decode(String moves) =>
    RailLayLevels.decodeSolution(moves);

// ---------------------------------------------------------------------------
// Şekil aileleri
// ---------------------------------------------------------------------------

/// Oyma: rastgele kayışlarla koridor aç (duvar koruması yok; çözülebilirliği
/// artık çözücü söylüyor).
List<bool> _carve(Random random, int w, int h) {
  final open = List<bool>.filled(w * h, false);
  var x = random.nextInt(w);
  var y = random.nextInt(h);
  open[y * w + x] = true;
  final slides = 6 + random.nextInt(w + h);
  for (var i = 0; i < slides; i++) {
    final d = RailLayDirection.values[random.nextInt(4)].delta;
    var room = 0;
    while (true) {
      final nx = x + d.x * (room + 1);
      final ny = y + d.y * (room + 1);
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) break;
      room++;
    }
    if (room == 0) continue;
    final length = 1 + random.nextInt(room);
    for (var s = 1; s <= length; s++) {
      open[(y + d.y * s) * w + (x + d.x * s)] = true;
    }
    x += d.x * length;
    y += d.y * length;
  }
  return open;
}

/// Oda: tamamen açık dikdörtgen, içine tek ya da ikili duvar blokları.
List<bool> _room(Random random, int w, int h) {
  final open = List<bool>.filled(w * h, true);
  final blocks = 1 + random.nextInt(max(1, (w * h) ~/ 7));
  for (var i = 0; i < blocks; i++) {
    final x = random.nextInt(w);
    final y = random.nextInt(h);
    open[y * w + x] = false;
    if (random.nextBool()) {
      final horizontal = random.nextBool();
      final nx = x + (horizontal ? 1 : 0);
      final ny = y + (horizontal ? 0 : 1);
      if (nx < w && ny < h) open[ny * w + nx] = false;
    }
  }
  return open;
}

/// Birleşik odalar: iki-dört dikdörtgen, üstüne birkaç duvar bloğu.
List<bool> _rooms(Random random, int w, int h) {
  final open = List<bool>.filled(w * h, false);
  final count = 2 + random.nextInt(3);
  for (var i = 0; i < count; i++) {
    final rw = 2 + random.nextInt(max(1, w - 1));
    final rh = 2 + random.nextInt(max(1, h - 1));
    final rx = random.nextInt(max(1, w - rw + 1));
    final ry = random.nextInt(max(1, h - rh + 1));
    for (var y = ry; y < min(h, ry + rh); y++) {
      for (var x = rx; x < min(w, rx + rw); x++) {
        open[y * w + x] = true;
      }
    }
  }
  final blocks = random.nextInt(max(1, (w * h) ~/ 9) + 1);
  for (var i = 0; i < blocks; i++) {
    open[random.nextInt(w * h)] = false;
  }
  return open;
}

/// En büyük bitişik parçayı bırakır, çevresine kırpar. Sığmıyorsa `null`.
List<String>? _normalize(List<bool> open, int w, int h) {
  final component = List<int>.filled(w * h, -1);
  var bestSize = 0;
  var bestId = -1;
  var id = 0;
  for (var i = 0; i < open.length; i++) {
    if (!open[i] || component[i] >= 0) continue;
    var size = 0;
    final stack = <int>[i];
    component[i] = id;
    while (stack.isNotEmpty) {
      final cell = stack.removeLast();
      size++;
      final cx = cell % w;
      final cy = cell ~/ w;
      for (final d in RailLayDirection.values) {
        final nx = cx + d.delta.x;
        final ny = cy + d.delta.y;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final n = ny * w + nx;
        if (!open[n] || component[n] >= 0) continue;
        component[n] = id;
        stack.add(n);
      }
    }
    if (size > bestSize) {
      bestSize = size;
      bestId = id;
    }
    id++;
  }
  if (bestSize < 6 || bestSize > RailLaySolver.maxOpenCells) return null;

  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var i = 0; i < open.length; i++) {
    if (component[i] != bestId) continue;
    minX = min(minX, i % w);
    maxX = max(maxX, i % w);
    minY = min(minY, i ~/ w);
    maxY = max(maxY, i ~/ w);
  }
  if (maxX - minX + 1 > railLayMaxWidth) return null;
  if (maxY - minY + 1 > railLayMaxHeight) return null;
  return <String>[
    for (var y = minY; y <= maxY; y++)
      <String>[
        for (var x = minX; x <= maxX; x++)
          component[y * w + x] == bestId ? '.' : '#',
      ].join(),
  ];
}

// ---------------------------------------------------------------------------
// Ölçme
// ---------------------------------------------------------------------------

/// Durum sayısı bu sınırı aşan tahta ölçülemez sayılır.
///
/// Oyundaki anında çıkmaz kontrolünün kendi, çok daha küçük sınırı var;
/// onu aşan durumda kontrol "bilinmiyor" deyip sezgisel yoklamaya düşer.
const int _cap = 250000;

/// Tahtanın en zor başlangıcını bulur. Hiçbir başlangıçtan çözülemiyorsa
/// ya da ölçülemiyorsa `null`.
Candidate? _evaluate(List<String> rows, Random random, {int starts = 10}) {
  final cells = <Point<int>>[];
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y][x] != '#') cells.add(Point<int>(x, y));
    }
  }
  cells.shuffle(random);
  Candidate? best;
  for (final start in cells.take(starts)) {
    final grid = <String>[
      for (var y = 0; y < rows.length; y++)
        <String>[
          for (var x = 0; x < rows[y].length; x++)
            start.x == x && start.y == y ? 'S' : rows[y][x],
        ].join(),
    ];
    final analysis = RailLaySolver(RailLayLevel.parse(grid)).explore(cap: _cap);
    if (analysis == null) continue;
    if (best == null || analysis.score > best.analysis.score) {
      best = Candidate(rows: grid, analysis: analysis);
    }
  }
  return best;
}

/// Bir duvarı açıp kapatarak zorlaştırır; bölüm çözülebilir kalmalı.
Candidate _climb(Candidate seed, Random random, int steps) {
  var current = seed;
  for (var i = 0; i < steps; i++) {
    final rows = current.rows.map((String r) => r.split('')).toList();
    final y = random.nextInt(rows.length);
    final x = random.nextInt(rows[y].length);
    if (rows[y][x] == 'S') continue;
    rows[y][x] = rows[y][x] == '#' ? '.' : '#';
    final flat = <bool>[
      for (final row in rows)
        for (final c in row) c != '#',
    ];
    final normalized = _normalize(flat, rows.first.length, rows.length);
    if (normalized == null) continue;
    final plain = normalized.map((String r) => r.replaceAll('S', '.')).toList();
    // Başlangıç kaybolmasın: kırpma kaydırdıysa yeniden aranır.
    final candidate = _evaluate(plain, random, starts: 6);
    if (candidate == null) continue;
    // Kırpma ızgarayı kaydırabildiği için başlangıç her adımda yeniden
    // seçiliyor; yalnız daha zor sonuç tutulur.
    if (candidate.analysis.score > current.analysis.score) {
      current = candidate;
    }
  }
  return current;
}

// ---------------------------------------------------------------------------
// pool
// ---------------------------------------------------------------------------

void _pool(String out, int seed, int count) {
  final random = Random(seed);
  final pool = <String, Candidate>{};
  final watch = Stopwatch()..start();
  var tries = 0;
  while (pool.length < count && tries++ < count * 30) {
    // Boy katmanı: küçük, orta, büyük tahtalar dengeli dağılsın.
    // Büyük tahtalar daha sık denenir: çoğu ölçüm sınırını aşıp eleniyor.
    final tier = min(2, tries % 5);
    final w = switch (tier) {
      0 => 3 + random.nextInt(3),
      1 => 5 + random.nextInt(3),
      _ => 7 + random.nextInt(3),
    };
    final h = switch (tier) {
      0 => 3 + random.nextInt(4),
      1 => 5 + random.nextInt(4),
      _ => 8 + random.nextInt(4),
    };
    final family = random.nextInt(3);
    final open = switch (family) {
      0 => _carve(random, w, h),
      1 => _room(random, w, h),
      _ => _rooms(random, w, h),
    };
    final rows = _normalize(open, w, h);
    if (rows == null) continue;
    var candidate = _evaluate(rows, random);
    if (candidate == null) continue;
    candidate = _climb(candidate, random, tier == 0 ? 8 : 20);
    pool[candidate.key] = candidate;
    if (pool.length % 100 == 0) {
      stdout.writeln(
        '${pool.length} aday · ${watch.elapsed.inSeconds} sn · deneme $tries',
      );
    }
  }
  File(out).writeAsStringSync(
    const JsonEncoder.withIndent(
      ' ',
    ).convert(<Object?>[for (final c in pool.values) c.toJson()]),
  );
  stdout.writeln('${pool.length} aday → $out');
}

// ---------------------------------------------------------------------------
// curate
// ---------------------------------------------------------------------------

/// Bir bölüm aralığı ve oraya girebilecek adayın koşulu.
class _Tier {
  const _Tier(this.first, this.last, this.accepts);
  final int first;
  final int last;
  final bool Function(Candidate c) accepts;
  int get size => last - first + 1;
}

final List<_Tier> _tiers = <_Tier>[
  // Öğretici: küçük, bir seçim var ama tuzak yok.
  _Tier(
    1,
    2,
    (c) =>
        c.open >= 7 &&
        c.open <= 12 &&
        c.analysis.traps == 0 &&
        c.analysis.decisions >= 1 &&
        c.analysis.optimal >= 3,
  ),
  // İlk tuzaklar.
  _Tier(
    3,
    10,
    (c) =>
        c.open >= 9 &&
        c.open <= 22 &&
        c.analysis.traps >= 1 &&
        c.analysis.optimal >= 4,
  ),
  // Büyüyen tahta, birden fazla tuzak.
  _Tier(
    11,
    40,
    (c) =>
        c.open >= 16 &&
        c.open <= 42 &&
        c.analysis.traps >= 2 &&
        c.analysis.decisions >= 1,
  ),
  // Açık odalar, çok tuzak.
  _Tier(
    41,
    RailLayLevels.target,
    (c) => c.open >= 26 && c.analysis.traps >= 3 && c.analysis.decisions >= 2,
  ),
];

double _lerp(double a, double b, double t) => a + (b - a) * t.clamp(0, 1);

/// Bölümün hedef zorluk puanı ([RailLayAnalysis.score]).
///
/// Havuzun puan dağılımından okundu (öğretici adaylar 5-23, ilk tuzaklar
/// 12-48, büyüyen tahtalar 12-68, açık odalar 23-71). Eğri aralık
/// sınırlarında **düşmüyor**: önceki sürüm her aralığı kendi en kolayından
/// başlatıyordu ve 11. bölüm 10.'dan kolay çıkıyordu.
double _targetScore(int n) {
  if (n == 1) return 6;
  if (n == 2) return 9;
  if (n <= 10) return _lerp(13, 24, (n - 3) / 7);
  if (n <= 40) return _lerp(24, 38, (n - 11) / 29);
  return _lerp(38, 64, (n - 41) / (RailLayLevels.target - 41));
}

/// Bölümün hedef açık kare sayısı.
double _targetOpen(int n) {
  if (n <= 2) return 8;
  if (n <= 10) return _lerp(11, 20, (n - 3) / 7);
  if (n <= 40) return _lerp(18, 36, (n - 11) / 29);
  return _lerp(30, 56, (n - 41) / (RailLayLevels.target - 41));
}

void _curate(List<String> files) {
  final pool = <String, Candidate>{};
  for (final file in files) {
    final json = jsonDecode(File(file).readAsStringSync()) as List<Object?>;
    for (final entry in json) {
      final c = Candidate.fromJson((entry! as Map).cast<String, Object?>());
      pool[c.key] = c;
    }
  }
  stdout.writeln('${pool.length} aday okundu');

  final used = <String>{};
  final chosen = <Candidate>[];
  for (var number = 1; number <= RailLayLevels.target; number++) {
    final tier = _tiers.firstWhere(
      (t) => number >= t.first && number <= t.last,
    );
    final score = _targetScore(number);
    final open = _targetOpen(number);
    Candidate? best;
    var bestDistance = double.infinity;
    for (final c in pool.values) {
      if (used.contains(c.key) || !tier.accepts(c)) continue;
      // Zorluk öncelikli; tahta boyu ikinci planda, ki bölümler hem
      // zorlaşsın hem büyüsün ama boy tek başına zorluk sayılmasın.
      final distance =
          (c.analysis.score - score).abs() + 0.3 * (c.open - open).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = c;
      }
    }
    if (best == null) {
      stderr.writeln('$number. bölüme uygun aday kalmadı. Havuzu büyüt.');
      exit(1);
    }
    used.add(best.key);
    chosen.add(best);
  }
  _write(chosen);
  stdout.writeln('${chosen.length} bölüm yazıldı');
}

void _write(List<Candidate> levels) {
  final buffer = StringBuffer()
    ..writeln('// ÜRETİLMİŞ DOSYA — elle düzenleme.')
    ..writeln('//')
    ..writeln('// tool/rail_lay/generate_levels.dart curate ile yazıldı. Her')
    ..writeln('// bölüm çözücüyle ölçüldü: en kısa çözüm, gerçek seçim sayısı')
    ..writeln(
      '// ve tuzak (yeni kare döşeyip bölümü bitirilemez bırakan hamle)',
    )
    ..writeln('// sayısı. Izgara: `S` başlangıç, `#` duvar, `.` açık kare.')
    ..writeln()
    ..writeln("import 'rail_lay_levels.dart';")
    ..writeln()
    ..writeln('const List<RailLayLevelData> railLayLevelGrids =')
    ..writeln('    <RailLayLevelData>[');
  for (var i = 0; i < levels.length; i++) {
    final c = levels[i];
    buffer
      ..writeln('      RailLayLevelData(')
      ..writeln('        number: ${i + 1},')
      ..writeln('        optimal: ${c.analysis.optimal},')
      ..writeln('        decisions: ${c.analysis.decisions},')
      ..writeln('        traps: ${c.analysis.traps},')
      ..writeln("        solution: '${_encode(c.analysis.solution)}',")
      ..writeln('        grid: <String>[')
      ..writeAll(<String>[for (final r in c.rows) "          '$r',\n"])
      ..writeln('        ],')
      ..writeln('      ),');
  }
  buffer.writeln('    ];');
  File(
    'lib/features/games/rail_lay/data/rail_lay_level_grids.dart',
  ).writeAsStringSync(buffer.toString());
}

// ---------------------------------------------------------------------------
// report / solve
// ---------------------------------------------------------------------------

void _report() {
  stdout.writeln(
    '${'#'.padLeft(4)}${'boy'.padLeft(7)}${'kare'.padLeft(6)}'
    '${'hamle'.padLeft(7)}${'seçim'.padLeft(7)}${'tuzak'.padLeft(7)}'
    '${'puan'.padLeft(6)}',
  );
  for (final data in railLayLevelGrids) {
    final level = RailLayLevels.byNumber(data.number);
    stdout.writeln(
      '${data.number.toString().padLeft(4)}'
      '${'${level.width}x${level.height}'.padLeft(7)}'
      '${level.openCount.toString().padLeft(6)}'
      '${data.optimal.toString().padLeft(7)}'
      '${data.decisions.toString().padLeft(7)}'
      '${data.traps.toString().padLeft(7)}'
      '${level.points.toString().padLeft(6)}',
    );
  }
}

void _solve(int number) {
  final level = RailLayLevels.byNumber(number);
  final data = railLayLevelGrids[number - 1];
  data.grid.forEach(stdout.writeln);
  final analysis = RailLaySolver(level).explore(cap: 1000000)!;
  stdout.writeln(
    'en kısa ${analysis.optimal} hamle: ${_encode(analysis.solution)} · '
    'seçim ${analysis.decisions} · tuzak ${analysis.traps} · '
    'durum ${analysis.states}',
  );
}
