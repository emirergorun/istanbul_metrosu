import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../session/journey_game_controller.dart';
import '../../../session/journey_status.dart';
import '../domain/quiz_question.dart';
import '../domain/quiz_rules.dart';
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
  double _questionRemaining = QuizRules.answerTime.inSeconds.toDouble();

  int _streak = 0;
  int _bestStreak = 0;
  int _correct = 0;
  int _mistakes = 0;
  int _lastGain = 0;

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

  /// Soru sayacının kalan saniyesi.
  double get questionRemaining => _questionRemaining;

  /// Sayacın 0-1 arası oranı; çubuk bunu çizer.
  double get questionProgress =>
      (_questionRemaining / QuizRules.answerTime.inSeconds).clamp(0.0, 1.0);

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

  // --- Yolculuk motorunun kancaları ---

  @override
  void onTick(double dt) {
    if (_phase != QuizPhase.answering) return;

    _questionRemaining -= dt;
    if (_questionRemaining > 0) return;

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
    _phase = QuizPhase.answering;
    _questionRemaining = QuizRules.answerTime.inSeconds.toDouble();
    _question = _nextQuestion();
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
      if (_streak > _bestStreak) _bestStreak = _streak;
      // Çarpan **cevap sayıldıktan sonraki** seriye göre: üçüncü doğru
      // cevap zaten ×2 kazanır, oyuncu çarpanı bir soru sonra değil,
      // seriyi tamamladığı anda hisseder.
      _lastGain = QuizRules.pointsFor(_streak);
      addScore(_lastGain);
      markStationProgress();
    } else {
      _streak = 0;
      _lastGain = 0;
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
    _questionRemaining = QuizRules.answerTime.inSeconds.toDouble();
    notifyListeners();
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
