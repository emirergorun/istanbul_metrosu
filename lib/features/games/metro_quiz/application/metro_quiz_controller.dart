import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/quiz_question.dart';
import '../domain/quiz_rules.dart';
import '../domain/trivia_category.dart';
import 'quiz_pool.dart';

/// Sorunun o anki hâli.
enum QuizPhase {
  /// Oyuncu şık bekleniyor.
  answering,

  /// Cevap verildi, doğrusu gösteriliyor.
  revealing,
}

/// Metro Bilgi oyununun kuralları.
///
/// Yolculuk motoru (süre, varış, durak bonusu, rekor) üst sınıfta; burada
/// yalnızca **soru akışı, seri çarpanı ve yanlış hakkı** var.
class MetroQuizController extends JourneyGameController {
  MetroQuizController({
    required super.journey,
    required super.recordToBeat,
    required QuizPool pool,
    super.store,
    super.tick = AppConstants.playTick,
    // Alan private, parametre public kalmalı; `this._pool` dışarıdan
    // kullanılamayacak bir ad üretirdi.
    // ignore: prefer_initializing_formals
  }) : _pool = pool,
       super(gameId: id) {
    _question = _nextQuestion();
    _questionRemaining = questionDuration;
    _countAsked();
  }

  /// Rekor anahtarında kullanılır; değiştirilmemeli.
  ///
  /// Eski `station_memory` kimliğinden ayrı: oyun tamamen değişti, eski
  /// rekorlar bu oyunla karşılaştırılabilir değil.
  static const String id = 'metro_quiz';

  final QuizPool _pool;

  Timer? _revealTimer;

  late QuizQuestion _question;
  QuizPhase _phase = QuizPhase.answering;
  int _chosenIndex = -1;
  late double _questionRemaining;

  int _streak = 0;
  int _bestStreak = 0;
  int _correct = 0;
  int _mistakes = 0;
  int _lastGain = 0;
  int _jokersLeft = QuizRules.jokerCount;
  Set<int> _eliminated = const <int>{};
  final Map<TriviaCategory, int> _correctByCategory = <TriviaCategory, int>{};
  final Map<TriviaCategory, int> _askedByCategory = <TriviaCategory, int>{};
  final List<QuizQuestion> _missed = <QuizQuestion>[];
  int _lastSpeedBonus = 0;

  QuizQuestion get question => _question;
  QuizPhase get phase => _phase;

  /// Oyuncunun seçtiği şık; cevaplanmadıysa -1.
  int get chosenIndex => _chosenIndex;

  int get streak => _streak;
  int get bestStreak => _bestStreak;
  int get correctCount => _correct;
  int get mistakes => _mistakes;

  /// Kalan yanlış hakkı.
  int get livesLeft => QuizRules.mistakeAllowance - _mistakes;

  /// Şu anki puan çarpanı.
  int get multiplier => QuizRules.multiplierFor(_streak);

  /// Bir sonraki çarpana kaç doğru kaldı; tavandaysa `null`.
  int? get answersToNextMultiplier =>
      QuizRules.answersToNextMultiplier(_streak);

  /// Son doğru cevabın kazandırdığı puan — ekranda kısa bir bildirim için.
  int get lastGain => _lastGain;

  /// Son doğru cevabın hız bonusu; yoksa 0.
  int get lastSpeedBonus => _lastSpeedBonus;

  /// Bu yolculukta kaçırılan sorular — sonuç panelinde listelenir.
  List<QuizQuestion> get missedQuestions =>
      List<QuizQuestion>.unmodifiable(_missed);

  /// Doğru cevap treni hızlandırır.
  ///
  /// Üç doğru cevap yolculuktan bir saniye siler. Blok Metro'da iyi oyun
  /// yolculuğu kısaltıyordu; burada doğru cevap yalnızca puan veriyor ve
  /// oyuncunun iyi oynaması varış sahnesine yaklaştırmıyordu.
  @override
  double get journeySecondsPerGoodMove => 1 / 3;

  /// Soru sayacının kalan saniyesi.
  double get questionRemaining => _questionRemaining;

  /// Bu sorunun toplam süresi; zorluğa göre değişir.
  double get questionDuration =>
      QuizRules.answerTimeFor(_question.difficulty).inSeconds.toDouble();

  /// Sayacın 0-1 arası oranı; çubuk bunu çizer.
  double get questionProgress =>
      (_questionRemaining / questionDuration).clamp(0.0, 1.0);

  /// Sayaç son saniyelerinde mi?
  bool get isUrgent =>
      _phase == QuizPhase.answering &&
      _questionRemaining <= QuizRules.urgentSeconds;

  /// Kalan joker hakkı.
  int get jokersLeft => _jokersLeft;

  /// Jokerle elenmiş şıkların indeksleri.
  Set<int> get eliminatedOptions => _eliminated;

  /// Joker bu soruda kullanılabilir mi?
  bool get canUseJoker =>
      status == GameStatus.playing &&
      _phase == QuizPhase.answering &&
      _jokersLeft > 0 &&
      _eliminated.isEmpty;

  /// Kategori başına doğru sayısı — sonuç panelinde kırılım için.
  Map<TriviaCategory, int> get correctByCategory =>
      Map<TriviaCategory, int>.unmodifiable(_correctByCategory);

  /// Kategori başına sorulan soru sayısı.
  Map<TriviaCategory, int> get askedByCategory =>
      Map<TriviaCategory, int>.unmodifiable(_askedByCategory);

  /// En çok doğru yapılan kategori; hiç doğru yoksa `null`.
  ///
  /// Beraberlikte **oranı** yüksek olan kazanır: iki kategoriden birinde
  /// üç soruda üç doğru, diğerinde altı soruda üç doğru varsa ilki daha
  /// iyi gitmiş demektir.
  TriviaCategory? get bestCategory {
    TriviaCategory? best;
    var bestCount = 0;
    var bestRatio = 0.0;
    for (final entry in _correctByCategory.entries) {
      final asked = _askedByCategory[entry.key] ?? entry.value;
      final ratio = asked == 0 ? 0.0 : entry.value / asked;
      if (entry.value > bestCount ||
          (entry.value == bestCount && ratio > bestRatio)) {
        best = entry.key;
        bestCount = entry.value;
        bestRatio = ratio;
      }
    }
    return bestCount == 0 ? null : best;
  }

  bool get isRevealing => _phase == QuizPhase.revealing;

  /// Son cevap doğru muydu? (Yalnız [QuizPhase.revealing] sırasında anlamlı.)
  bool get lastAnswerCorrect => _chosenIndex == _question.answerIndex;

  // --- Oyuncu girdisi ---

  /// Bir şıkka dokunuldu. Kabul edildiyse `true`.
  bool answer(int index) {
    if (status != GameStatus.playing) return false;
    if (_phase != QuizPhase.answering) return false;
    if (index < 0 || index >= _question.options.length) return false;

    _chosenIndex = index;
    _resolve(correct: index == _question.answerIndex, costsLife: true);
    return true;
  }

  /// Joker: iki yanlış şıkkı eler. Kullanıldıysa `true`.
  ///
  /// Puanı değiştirmez ve süreyi durdurmaz — joker zaman değil, belirsizlik
  /// satın alır.
  bool useJoker() {
    if (!canUseJoker) return false;

    final wrong = <int>[
      for (var i = 0; i < _question.options.length; i++)
        if (i != _question.answerIndex) i,
    ];
    // Hangi ikisinin eleneceği sorunun kimliğine bağlı: aynı soru her
    // oyunda aynı şıkları eler, oyuncu jokeri tekrar tekrar deneyip
    // farklı sonuç alamaz.
    wrong.sort(
      (a, b) => ('\${_question.id}\$a').hashCode.compareTo(
        ('\${_question.id}\$b').hashCode,
      ),
    );
    _eliminated = wrong.take(QuizRules.jokerEliminates).toSet();
    _jokersLeft--;
    notifyListeners();
    return true;
  }

  // --- Yolculuk motorunun kancaları ---

  @override
  void onTick(double dt) {
    if (_phase != QuizPhase.answering) return;

    final wasUrgent = isUrgent;
    _questionRemaining -= dt;
    if (_questionRemaining > 0) {
      // Nabız eşiğini geçtiğimiz kare ekranın haberi olsun.
      if (!wasUrgent && isUrgent) notifyListeners();
      return;
    }

    // Süre dolması **yanlış cevapla aynı bedele sahip**: seri bozulur ve
    // bir hak gider.
    //
    // Önce cezasızdı, gerekçe "hareket eden vagonda gözünü kaldıran
    // oyuncu cezalandırılmasın" idi. Oynayınca iki sorun çıktı: sayaç
    // dolmasını beklemek bilmediği soruyu bedelsiz atlamanın yolu oluyor
    // ve on iki saniyelik sayaç hiçbir gerilim taşımıyordu. Doğru cevap
    // yine de gösterilir; oyuncu bedelini ödediği soruyu öğrenmeden
    // geçmemeli.
    _questionRemaining = 0;
    _chosenIndex = -1;
    _resolve(correct: false, costsLife: true);
  }

  @override
  void onRestart() {
    _revealTimer?.cancel();
    _pool.reset();
    _streak = 0;
    _bestStreak = 0;
    _correct = 0;
    _mistakes = 0;
    _lastGain = 0;
    _chosenIndex = -1;
    _jokersLeft = QuizRules.jokerCount;
    _eliminated = const <int>{};
    _lastSpeedBonus = 0;
    _correctByCategory.clear();
    _askedByCategory.clear();
    _missed.clear();
    _phase = QuizPhase.answering;
    _question = _nextQuestion();
    _questionRemaining = questionDuration;
    _countAsked();
  }

  @override
  void onPause() => _revealTimer?.cancel();

  @override
  void onResume() {
    // Duraklatma cevabın gösterildiği ana denk geldiyse, dönüşte sıradaki
    // soruya geçiş yeniden kurulmalı; yoksa oyun o ekranda donup kalır.
    if (_phase == QuizPhase.revealing) _scheduleAdvance();
  }

  @override
  void onAbandon() => _revealTimer?.cancel();

  @override
  void onFinish(GameStatus status) => _revealTimer?.cancel();

  @override
  void dispose() {
    _revealTimer?.cancel();
    super.dispose();
  }

  // --- İç akış ---

  void _resolve({required bool correct, required bool costsLife}) {
    _phase = QuizPhase.revealing;

    if (correct) {
      _streak++;
      _correct++;
      _correctByCategory.update(
        _question.category,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
      if (_streak > _bestStreak) _bestStreak = _streak;
      // Çarpan **cevap sayıldıktan sonraki** seriye göre: üçüncü doğru
      // cevap zaten ×2 kazanır, oyuncu çarpanı bir soru sonra değil,
      // seriyi tamamladığı anda hisseder.
      _lastSpeedBonus = QuizRules.speedBonus(questionProgress);
      _lastGain = QuizRules.pointsFor(_streak) + _lastSpeedBonus;
      addScore(_lastGain);
      markStationProgress();
      // Seri beş katına ulaştıkça joker kazanılır.
      if (_streak % QuizRules.jokerRewardStreak == 0 &&
          _jokersLeft < QuizRules.maxJokers) {
        _jokersLeft++;
      }
    } else {
      _streak = 0;
      _lastGain = 0;
      _lastSpeedBonus = 0;
      // Kaçırılan soru saklanır: yolculuk sonunda oyuncu neyi bilmediğini
      // görebilmeli. Liste sınırlı — sonuç paneli bir liste ekranı değil.
      if (_missed.length < 10 && !_missed.contains(_question)) {
        _missed.add(_question);
      }
      if (costsLife) _mistakes++;
    }

    notifyListeners();

    if (!correct && costsLife && _mistakes >= QuizRules.mistakeAllowance) {
      // Son yanlışta doğru cevap bir an görünsün, sonra oyun bitsin.
      _revealTimer?.cancel();
      _revealTimer = Timer(QuizRules.revealTime, endGame);
      return;
    }
    _scheduleAdvance();
  }

  void _scheduleAdvance() {
    _revealTimer?.cancel();
    if (status != GameStatus.playing) return;
    _revealTimer = Timer(QuizRules.revealTime, _advance);
  }

  void _advance() {
    if (status != GameStatus.playing) return;
    _question = _nextQuestion();
    _phase = QuizPhase.answering;
    _chosenIndex = -1;
    _eliminated = const <int>{};
    _questionRemaining = questionDuration;
    _countAsked();
    notifyListeners();
  }

  void _countAsked() {
    _askedByCategory.update(
      _question.category,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
  }

  /// Sıradaki soru.
  ///
  /// Zorluk ilerlemesi havuzun kendi işi: ilk sorular kolay havuzdan
  /// gelir, sonrakiler açılır. Uzun yolculuğu baştan zorlaştırmak bu
  /// projede bir kez denendi ve varış oranını sıfıra indirdi.
  QuizQuestion _nextQuestion() => _pool.next();

  @visibleForTesting
  void debugAdvanceReveal() => _advance();
}
