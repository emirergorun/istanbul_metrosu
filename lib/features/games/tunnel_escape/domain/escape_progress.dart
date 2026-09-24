import 'dart:convert';

/// Bir bölümün kalıcı kaydı.
///
/// Yalnız **iyileşir**: daha kötü bir sonuç daha iyisinin üstüne yazılmaz.
/// Bitirilmiş bölüm bitmemiş olmaz, kazanılmış yıldız geri alınmaz.
///
/// Tek istisna bulmacanın kendisinin değişmesi ([fingerprint]). Bölüm
/// tasarımı yenilenirse eski bulmacadaki "7 hamle" yeni bulmacada bir şey
/// ölçmez; kayıt **taşınır** ([EscapeLevelRecord.carried]): bölüm bitmiş
/// sayılmaya devam eder (açılan bölümler kilitlenmez) ama hamle, yıldız ve
/// kusursuzluk yeni bulmacada yeniden kazanılır.
final class EscapeLevelRecord {
  const EscapeLevelRecord({
    required int this.bestMoves,
    required this.bestStars,
    this.perfect = false,
    this.wins = 1,
    this.fingerprint,
  });

  /// Bulmacası değişmiş bölüm: bitirme korunur, sonuç yok.
  const EscapeLevelRecord.carried({this.wins = 1, this.fingerprint})
    : bestMoves = null,
      bestStars = 0,
      perfect = false;

  /// En az hamleyle bitiriş. Taşınmış kayıtta `null`.
  final int? bestMoves;

  /// En yüksek yıldız (1-3); taşınmış kayıtta 0.
  final int bestStars;

  /// Bölüm en kısa çözümle, ipucusuz bitirildi mi?
  final bool perfect;

  /// Kaç kez bitirildi — tekrar oynama ölçüsü.
  final int wins;

  /// Sonucun kazanıldığı bulmacanın parmak izi
  /// ([EscapeLevel.fingerprintOf]). İlk sürümün kayıtlarında yok.
  final String? fingerprint;

  /// Bu bulmacada bir sonuç var mı? Taşınmış kayıtta yok.
  bool get hasResult => bestMoves != null;

  /// Yeni bir bitirişi kayda katar; her alan kendi en iyisini korur.
  EscapeLevelRecord merge({
    required int moves,
    required int stars,
    required bool perfect,
    String? fingerprint,
  }) {
    final best = bestMoves;
    return EscapeLevelRecord(
      bestMoves: best == null || moves < best ? moves : best,
      bestStars: stars > bestStars ? stars : bestStars,
      perfect: this.perfect || perfect,
      wins: wins + 1,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'm': ?bestMoves,
    's': bestStars,
    if (perfect) 'p': 1,
    'w': wins,
    'f': ?fingerprint,
  };

  static EscapeLevelRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final moves = json['m'];
    final stars = json['s'];
    final wins = json['w'];
    final print = json['f'];
    final fingerprint = print is String && print.isNotEmpty ? print : null;
    final safeWins = wins is int && wins > 0 ? wins : 1;
    if (moves == null) {
      // Taşınmış kayıt: sonuç yok, yıldız da olamaz.
      if (stars != 0) return null;
      return EscapeLevelRecord.carried(
        wins: safeWins,
        fingerprint: fingerprint,
      );
    }
    if (moves is! int || moves < 1) return null;
    if (stars is! int || stars < 1 || stars > 3) return null;
    return EscapeLevelRecord(
      bestMoves: moves,
      bestStars: stars,
      perfect: json['p'] == 1,
      wins: safeWins,
      fingerprint: fingerprint,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EscapeLevelRecord &&
          other.bestMoves == bestMoves &&
          other.bestStars == bestStars &&
          other.perfect == perfect &&
          other.wins == wins &&
          other.fingerprint == fingerprint);

  @override
  int get hashCode =>
      Object.hash(bestMoves, bestStars, perfect, wins, fingerprint);
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
  /// alanı yok sayar, eksik alanı varsayılanla doldurur. 2: bölüm kaydı
  /// bulmacanın parmak izini (`f`) ve taşınmış kaydı (`m` yok) taşıyor.
  static const int version = 2;

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
    String? fingerprint,
  }) {
    final previous = records[level];
    final next = previous == null
        ? EscapeLevelRecord(
            bestMoves: moves,
            bestStars: stars,
            perfect: perfect,
            fingerprint: fingerprint,
          )
        : previous.merge(
            moves: moves,
            stars: stars,
            perfect: perfect,
            fingerprint: fingerprint,
          );
    return EscapeProgress(
      Map<int, EscapeLevelRecord>.unmodifiable(<int, EscapeLevelRecord>{
        ...records,
        level: next,
      }),
    );
  }

  /// Kayıtları bugünkü bulmacalarla eşleştirir.
  ///
  /// [current]: bölüm numarasından bugünkü bulmacanın parmak izine.
  /// [legacy]: parmak izi yazılmadan önceki (ilk sürüm) bulmacaların izleri,
  /// bölüm sırasıyla — izsiz eski kayıt o bulmacada kazanılmış sayılır.
  ///
  /// Bulmacası aynı kalan kayıt olduğu gibi kalır (izsizse iz eklenir).
  /// Bulmacası değişen kayıt taşınır: bitirme korunur, sonuç silinir. Dönen
  /// ikinci değer kaydın değişip değişmediği — değiştiyse diske yazılmalı.
  (EscapeProgress, bool) reconcile({
    required Map<int, String> current,
    List<String> legacy = const <String>[],
  }) {
    var changed = false;
    final next = <int, EscapeLevelRecord>{};
    for (final entry in records.entries) {
      final record = entry.value;
      final now = current[entry.key];
      if (now == null) {
        next[entry.key] = record;
        continue;
      }
      final earned =
          record.fingerprint ??
          (entry.key <= legacy.length ? legacy[entry.key - 1] : null);
      if (earned == now) {
        if (record.fingerprint == null) {
          changed = true;
          next[entry.key] = record.hasResult
              ? EscapeLevelRecord(
                  bestMoves: record.bestMoves!,
                  bestStars: record.bestStars,
                  perfect: record.perfect,
                  wins: record.wins,
                  fingerprint: now,
                )
              : EscapeLevelRecord.carried(wins: record.wins, fingerprint: now);
        } else {
          next[entry.key] = record;
        }
        continue;
      }
      changed = true;
      next[entry.key] = EscapeLevelRecord.carried(
        wins: record.wins,
        fingerprint: now,
      );
    }
    if (!changed) return (this, false);
    return (
      EscapeProgress(Map<int, EscapeLevelRecord>.unmodifiable(next)),
      true,
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
