import 'dart:math';

import '../../../../data/metro/metro_repository.dart';
import '../../../journey/models/station.dart';
import 'quiz_question.dart';

/// Metro ağından soru **üretir**.
///
/// Soru yazmak yerine üretmenin üç sebebi var:
///
/// 1. **Tükenmiyor.** 10 hat, 161 durak, 151 komşu çift: yalnız
///    önceki/sonraki sorusundan 302 farklı soru çıkıyor, diğer tiplerle
///    birlikte binleri buluyor.
/// 2. **Kendiliğinden doğru.** Cevap oyunun kendi verisinden geliyor; yeni
///    hat eklendiğinde sorular da güncelleniyor, elle bakım gerekmiyor.
/// 3. **Zorluk ayarlanabilir.** Çeldiriciyi aynı hattaki komşu duraktan mı
///    yoksa şehrin öbür ucundan mı seçtiğimiz soruyu kolaylaştırıp
///    zorlaştırıyor.
///
/// Sınıf saf: rastgeleliği dışarıdan alır, böylece test edilebilir.
class QuizGenerator {
  QuizGenerator({required MetroRepository metro, Random? random})
    : _random = random ?? Random(),
      _lines = metro.lines(),
      _allStations = metro.stations(),
      _stationsByLine = <String, List<Station>>{
        for (final line in metro.lines())
          line.id: metro.stationsOfLine(line.id),
      },
      _uniqueNames = _namesOnSingleLine(metro.stations());

  final Random _random;
  final List<MetroLine> _lines;
  final List<Station> _allStations;
  final Map<String, List<Station>> _stationsByLine;

  /// Yalnızca tek hatta geçen durak adları.
  ///
  /// Aynı ada sahip duraklar birden fazla hatta kayıtlı (Yenikapı: M1A,
  /// M1B, M2 — 161 durağın 35'i böyle). "Bu durak hangi hatta?" sorusunun
  /// bu adlarda tek doğru cevabı olmadığı için o soru tipinden dışlanırlar.
  final Set<String> _uniqueNames;

  static Set<String> _namesOnSingleLine(List<Station> stations) {
    final counts = <String, int>{};
    for (final station in stations) {
      counts[station.name] = (counts[station.name] ?? 0) + 1;
    }
    return <String>{
      for (final entry in counts.entries)
        if (entry.value == 1) entry.key,
    };
  }

  /// Üretilebilecek bir soru döner; [usedIds] içindekiler atlanır.
  ///
  /// [hard] ise çeldiriciler aynı hattın yakın duraklarından seçilir.
  /// Havuz tükenirse `usedIds` yok sayılır — oyun soru bulamadı diye
  /// durmamalı, tekrar etmek durmaktan iyidir.
  QuizQuestion next({
    required bool hard,
    Set<String> usedIds = const <String>{},
  }) {
    for (var attempt = 0; attempt < 40; attempt++) {
      final question = _build(hard: hard);
      if (question != null && !usedIds.contains(question.id)) return question;
    }
    // Son çare: tekrar pahasına da olsa soru dön.
    return _build(hard: hard) ?? _fallback();
  }

  QuizQuestion? _build({required bool hard}) {
    // Ağırlıklar: omurga komşu durak sorusu, diğerleri çeşni.
    final roll = _random.nextInt(100);
    if (roll < 55) return _neighbourQuestion(hard: hard);
    if (roll < 75) return _lineOfStationQuestion();
    if (roll < 90) return _terminusQuestion(hard: hard);
    return _stationCountQuestion();
  }

  /// "M4 hattında Kadıköy'den **sonraki** durak hangisi?"
  QuizQuestion? _neighbourQuestion({required bool hard}) {
    final line = _lines[_random.nextInt(_lines.length)];
    final stations = _stationsByLine[line.id] ?? const <Station>[];
    if (stations.length < 5) return null;

    // Uç duraklarda tek yön sorulabilir; kafa karışmasın diye uçları
    // baştan eliyoruz.
    final index = 1 + _random.nextInt(stations.length - 2);
    final askNext = _random.nextBool();
    final subject = stations[index];
    final answer = askNext ? stations[index + 1] : stations[index - 1];

    final distractors = _distractors(
      line: line,
      stations: stations,
      around: index,
      exclude: <String>{subject.name, answer.name},
      hard: hard,
    );
    if (distractors.length < 3) return null;

    return _shuffled(
      id: 'nb_${subject.id}_${askNext ? 'next' : 'prev'}',
      prompt: askNext
          ? '${subject.name} durağından sonra hangi durak gelir?'
          : '${subject.name} durağından önce hangi durak gelir?',
      answer: answer.name,
      distractors: distractors,
      topic: QuizTopic.network,
      context: '${line.id} hattı',
    );
  }

  /// "Osmanbey hangi hatta?"
  QuizQuestion? _lineOfStationQuestion() {
    if (_lines.length < 4) return null;
    final line = _lines[_random.nextInt(_lines.length)];
    final stations = (_stationsByLine[line.id] ?? const <Station>[])
        .where((s) => _uniqueNames.contains(s.name))
        .toList();
    if (stations.isEmpty) return null;

    final subject = stations[_random.nextInt(stations.length)];
    final others = _lines.where((l) => l.id != line.id).toList()
      ..shuffle(_random);

    return _shuffled(
      id: 'line_${subject.id}',
      prompt: '${subject.name} durağı hangi hatta?',
      answer: line.id,
      distractors: others.take(3).map((l) => l.id).toList(),
      topic: QuizTopic.network,
    );
  }

  /// "M7 hattının son durağı hangisi?"
  QuizQuestion? _terminusQuestion({required bool hard}) {
    final line = _lines[_random.nextInt(_lines.length)];
    final stations = _stationsByLine[line.id] ?? const <Station>[];
    if (stations.length < 5) return null;

    final fromStart = _random.nextBool();
    final answer = fromStart ? stations.first : stations.last;
    final distractors = _distractors(
      line: line,
      stations: stations,
      around: fromStart ? 0 : stations.length - 1,
      exclude: <String>{answer.name},
      hard: hard,
    );
    if (distractors.length < 3) return null;

    return _shuffled(
      id: 'term_${line.id}_${fromStart ? 'start' : 'end'}',
      prompt: '${line.id} hattının uç duraklarından biri hangisidir?',
      answer: answer.name,
      distractors: distractors,
      topic: QuizTopic.network,
    );
  }

  /// "M5 hattında kaç durak var?"
  QuizQuestion? _stationCountQuestion() {
    final line = _lines[_random.nextInt(_lines.length)];
    final count = (_stationsByLine[line.id] ?? const <Station>[]).length;
    if (count < 5) return null;

    // Çeldirici sayılar gerçek sayıya yakın ama başka bir hattın sayısıyla
    // çakışmayacak kadar ayrı.
    final offsets = <int>[-3, -2, -1, 1, 2, 3]..shuffle(_random);
    final distractors = <String>{};
    for (final offset in offsets) {
      if (count + offset < 2) continue;
      distractors.add('${count + offset}');
      if (distractors.length == 3) break;
    }
    if (distractors.length < 3) return null;

    return _shuffled(
      id: 'count_${line.id}',
      prompt: '${line.id} hattında kaç durak var?',
      answer: '$count',
      distractors: distractors.toList(),
      topic: QuizTopic.network,
    );
  }

  /// Üç çeldirici seçer.
  ///
  /// [hard] ise doğru cevabın **çevresindeki** duraklardan: aynı hat, yakın
  /// sıra. Kolay modda şehrin herhangi bir yerinden — ikisi arasındaki fark
  /// oyuncunun hattı gerçekten bilip bilmediğini ayırır.
  List<String> _distractors({
    required MetroLine line,
    required List<Station> stations,
    required int around,
    required Set<String> exclude,
    required bool hard,
  }) {
    final picked = <String>{};

    if (hard) {
      final nearby = <Station>[];
      for (var d = 1; d <= 4; d++) {
        if (around - d >= 0) nearby.add(stations[around - d]);
        if (around + d < stations.length) nearby.add(stations[around + d]);
      }
      nearby.shuffle(_random);
      for (final station in nearby) {
        if (exclude.contains(station.name)) continue;
        picked.add(station.name);
        if (picked.length == 3) return picked.toList();
      }
    }

    final pool = List<Station>.of(_allStations)..shuffle(_random);
    for (final station in pool) {
      if (exclude.contains(station.name)) continue;
      picked.add(station.name);
      if (picked.length == 3) break;
    }
    return picked.toList();
  }

  QuizQuestion _shuffled({
    required String id,
    required String prompt,
    required String answer,
    required List<String> distractors,
    required QuizTopic topic,
    String? context,
  }) {
    final options = <String>[answer, ...distractors.take(3)]..shuffle(_random);
    return QuizQuestion(
      id: id,
      prompt: prompt,
      options: List<String>.unmodifiable(options),
      answerIndex: options.indexOf(answer),
      topic: topic,
      context: context,
    );
  }

  /// Veri beklenmedik biçimde yetersizse oyunun çökmemesi için.
  QuizQuestion _fallback() {
    final line = _lines.isEmpty ? null : _lines.first;
    return QuizQuestion(
      id: 'fallback',
      prompt: 'İstanbul metrosunda hangisi bir hat kodudur?',
      options: List<String>.unmodifiable(<String>[
        line?.id ?? 'M2',
        'B14',
        'T9',
        'K3',
      ]),
      answerIndex: 0,
      topic: QuizTopic.network,
    );
  }
}
