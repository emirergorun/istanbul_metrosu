import 'dart:convert';

/// Bir bölümün kalıcı kaydı.
///
/// Yalnız **iyileşir**: daha kötü bir sonuç daha iyisinin üstüne yazılmaz.
/// Bitirilmiş bölüm bitmemiş olmaz, kazanılmış yıldız geri alınmaz.
final class EscapeLevelRecord {
  const EscapeLevelRecord({
    required this.bestMoves,
    required this.bestStars,
    this.perfect = false,
    this.wins = 1,
  });

  /// En az hamleyle bitiriş.
  final int bestMoves;

  /// En yüksek yıldız (1-3).
  final int bestStars;

  /// Bölüm en kısa çözümle, ipucusuz bitirildi mi?
  final bool perfect;

  /// Kaç kez bitirildi — tekrar oynama ölçüsü.
  final int wins;

  /// Yeni bir bitirişi kayda katar; her alan kendi en iyisini korur.
  EscapeLevelRecord merge({
    required int moves,
    required int stars,
    required bool perfect,
  }) => EscapeLevelRecord(
    bestMoves: moves < bestMoves ? moves : bestMoves,
    bestStars: stars > bestStars ? stars : bestStars,
    perfect: this.perfect || perfect,
    wins: wins + 1,
  );

  Map<String, Object> toJson() => <String, Object>{
    'm': bestMoves,
    's': bestStars,
    if (perfect) 'p': 1,
    'w': wins,
  };

  static EscapeLevelRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final moves = json['m'];
    final stars = json['s'];
    final wins = json['w'];
    if (moves is! int || moves < 1) return null;
    if (stars is! int || stars < 1 || stars > 3) return null;
    return EscapeLevelRecord(
      bestMoves: moves,
      bestStars: stars,
      perfect: json['p'] == 1,
      wins: wins is int && wins > 0 ? wins : 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EscapeLevelRecord &&
          other.bestMoves == bestMoves &&
          other.bestStars == bestStars &&
          other.perfect == perfect &&
          other.wins == wins);

  @override
  int get hashCode => Object.hash(bestMoves, bestStars, perfect, wins);
}

/// Bütün bölümlerin kaydı — bulmaca ilerlemesi.
///
/// Yolculuktan **bağımsız**: bir bölüm hangi rotada, hangi yolculukta
/// bitirilirse bitirilsin buraya aynı şekilde yazılır. Yolculuk puanı ayrı
/// bir kovada ([JourneySession]) tutuluyor; ikisi aynı olaydan beslenir
/// ama birbirinin yerine geçmez.
///
/// **Açılma türetilir, saklanmaz.** Bölüm 1 her zaman açık; N bitince N+1
/// açılır. Açık bölüm listesi ayrıca tutulsaydı bitirme kaydıyla er geç
/// ayrı düşerdi (bitmiş ama kilitli bölüm gibi).
final class EscapeProgress {
  const EscapeProgress([this.records = const <int, EscapeLevelRecord>{}]);

  static const EscapeProgress empty = EscapeProgress();

  /// Kayıt biçiminin sürümü. Alan eklemek sürüm artırmaz: çözücü tanımadığı
  /// alanı yok sayar, eksik alanı varsayılanla doldurur.
  static const int version = 1;

  final Map<int, EscapeLevelRecord> records;

  EscapeLevelRecord? recordOf(int level) => records[level];

  bool isCompleted(int level) => records.containsKey(level);

  bool isUnlocked(int level) => level == 1 || isCompleted(level - 1);

  int get completedCount => records.length;

  int get totalStars {
    var sum = 0;
    for (final record in records.values) {
      sum += record.bestStars;
    }
    return sum;
  }

  /// Üç yıldızlı bölüm sayısı.
  int get masteredCount =>
      records.values.where((EscapeLevelRecord r) => r.bestStars >= 3).length;

  int get perfectCount =>
      records.values.where((EscapeLevelRecord r) => r.perfect).length;

  /// Sıradaki bölüm: açık olup bitmemiş ilk bölüm. Hepsi bittiyse son bölüm.
  int nextLevel(int levelCount) {
    for (var level = 1; level <= levelCount; level++) {
      if (!isCompleted(level)) return level;
    }
    return levelCount;
  }

  /// Bitirişi katar. Eski kayıttan kötüyse eski değerler korunur.
  EscapeProgress withCompletion({
    required int level,
    required int moves,
    required int stars,
    required bool perfect,
  }) {
    final previous = records[level];
    final next = previous == null
        ? EscapeLevelRecord(
            bestMoves: moves,
            bestStars: stars,
            perfect: perfect,
          )
        : previous.merge(moves: moves, stars: stars, perfect: perfect);
    return EscapeProgress(
      Map<int, EscapeLevelRecord>.unmodifiable(<int, EscapeLevelRecord>{
        ...records,
        level: next,
      }),
    );
  }

  String encode() => jsonEncode(<String, Object>{
    'v': version,
    'levels': <String, Object>{
      for (final entry in records.entries) '${entry.key}': entry.value.toJson(),
    },
  });

  /// Kaydı çözer. Bozuk kayıt **boş ilerleme** döner: bulmaca baştan açılır
  /// ama uygulama açılır ve başka hiçbir kayda dokunulmaz. Tek tek bozuk
  /// bölüm kayıtları atlanır, sağlamlar korunur.
  static EscapeProgress decode(String? raw) {
    if (raw == null || raw.isEmpty) return empty;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return empty;
      final levels = json['levels'];
      if (levels is! Map) return empty;
      final records = <int, EscapeLevelRecord>{};
      for (final entry in levels.entries) {
        final number = int.tryParse('${entry.key}');
        final record = EscapeLevelRecord.fromJson(entry.value);
        if (number == null || number < 1 || record == null) continue;
        records[number] = record;
      }
      return EscapeProgress(Map<int, EscapeLevelRecord>.unmodifiable(records));
    } on FormatException {
      return empty;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EscapeProgress || other.records.length != records.length) {
      return false;
    }
    for (final entry in records.entries) {
      if (other.records[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    records.entries.map(
      (MapEntry<int, EscapeLevelRecord> e) => Object.hash(e.key, e.value),
    ),
  );
}
