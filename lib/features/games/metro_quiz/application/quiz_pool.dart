import 'dart:math';

import '../../../../data/questions/question_repository.dart';
import '../domain/quiz_question.dart';
import '../domain/trivia_category.dart';

/// Bir yolculuğun soru akışı.
///
/// Omurga artık **küratörlü soru veritabanı**. Metro ağından üretilen
/// sorular (`QuizGenerator`) yolculuk boyunca tükenmiyor diye omurgaydı;
/// 1.200 soruluk havuz geldikten sonra buna gerek kalmadı — 12 dakikalık
/// bir yolculuk ~60 soru demek, havuz bunun yirmi katını karşılıyor.
///
/// Seçim üç kurala uyar:
///
/// 1. **Aynı soru bir yolculukta iki kez sorulmaz.**
/// 2. **Kategori çeşitliliği:** üst üste aynı kategoriden en fazla
///    [maxSameCategoryStreak] soru gelir. Rastgele seçim, altı kategoriyle
///    bile art arda dört Tarih sorusu üretebiliyor ve oyun "bu bir tarih
///    sınavı" gibi okunuyordu.
/// 3. **Zorluk ilerlemesi:** ilk sorular kolay havuzdan, sonrakiler
///    zorlaşır. Oyuncu ısınmadan zor soruyla karşılaşıp canını kaybetmez.
class QuizPool {
  QuizPool({
    required QuestionRepository repository,
    Random? random,
    // Alan private, parametre public kalmalı; `this._repository` dışarıdan
    // kullanılamayacak bir ad üretirdi.
    // ignore: prefer_initializing_formals
  }) : _repository = repository,
       _random = random ?? Random();

  /// Üst üste aynı kategoriden gelebilecek en fazla soru.
  static const int maxSameCategoryStreak = 2;

  /// Kolay havuzun ağırlıklı olduğu ilk soru sayısı.
  static const int warmupQuestions = 5;

  /// Zor havuzun devreye girdiği soru sayısı.
  static const int hardUnlockAt = 12;

  final QuestionRepository _repository;
  final Random _random;

  final Set<String> _used = <String>{};
  final List<TriviaCategory> _recentCategories = <TriviaCategory>[];

  /// Yolculukta şimdiye kadar sorulan soru sayısı.
  int get askedCount => _used.length;

  /// Yeniden başlatmada havuzu tazeler.
  void reset() {
    _used.clear();
    _recentCategories.clear();
  }

  /// Sıradaki soru. Havuz tamamen tükenirse sorulmuşlar unutulur.
  ///
  /// Havuzun **kendisi** boşsa hata verir. Sessizce boş bir soru üretmek
  /// ya da sonsuz döngüye girmek, veri dosyası okunamadığında hatayı
  /// oyunun içine gömerdi; bu durumda oyun açılmamalı.
  QuizQuestion next() {
    if (_repository.questions().isEmpty) {
      throw StateError('Soru havuzu boş: assets/data/trivia.json okunamadı.');
    }

    final candidates = _candidates();
    if (candidates.isEmpty) {
      // 1.200 soruluk havuzda pratikte olmaz; yine de oyun durmamalı.
      _used.clear();
      _recentCategories.clear();
      return next();
    }

    final picked = candidates[_random.nextInt(candidates.length)];
    _used.add(picked.id);
    _recentCategories.add(picked.category);
    if (_recentCategories.length > maxSameCategoryStreak) {
      _recentCategories.removeAt(0);
    }
    return QuizQuestion.fromTrivia(picked);
  }

  /// Kurallardan geçen sorular.
  ///
  /// Kurallar **kademeli gevşer**: önce hepsi uygulanır, sonuç boşsa
  /// zorluk kuralı düşer, hâlâ boşsa kategori kuralı düşer. Böylece dar
  /// bir havuzda bile oyun soru bulamadığı için durmaz.
  List<TriviaQuestion> _candidates() {
    final all = _repository.questions();
    if (all.isEmpty) return const <TriviaQuestion>[];

    final unused = all.where((q) => !_used.contains(q.id)).toList();
    if (unused.isEmpty) return const <TriviaQuestion>[];

    final blocked = _blockedCategory();
    final byCategory = blocked == null
        ? unused
        : unused.where((q) => q.category != blocked).toList();
    final pool = byCategory.isEmpty ? unused : byCategory;

    final wanted = _wantedDifficulties();
    final byDifficulty = pool
        .where((q) => wanted.contains(q.difficulty))
        .toList();
    return byDifficulty.isEmpty ? pool : byDifficulty;
  }

  /// Üst üste çıktığı için bu tur elenen kategori.
  TriviaCategory? _blockedCategory() {
    if (_recentCategories.length < maxSameCategoryStreak) return null;
    final first = _recentCategories.first;
    return _recentCategories.every((c) => c == first) ? first : null;
  }

  /// Soru sırasına göre hangi zorluklar açık.
  Set<TriviaDifficulty> _wantedDifficulties() {
    final asked = _used.length;
    if (asked < warmupQuestions) {
      return const <TriviaDifficulty>{TriviaDifficulty.easy};
    }
    if (asked < hardUnlockAt) {
      return const <TriviaDifficulty>{
        TriviaDifficulty.easy,
        TriviaDifficulty.medium,
      };
    }
    return const <TriviaDifficulty>{
      TriviaDifficulty.easy,
      TriviaDifficulty.medium,
      TriviaDifficulty.hard,
    };
  }
}
