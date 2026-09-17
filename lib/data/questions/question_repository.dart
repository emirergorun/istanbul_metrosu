import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../features/games/metro_quiz/domain/trivia_category.dart';

/// Küratörlü bilgi sorusu.
///
/// [answerIndex] **dosyadaki** sıraya göre doğru şıkkı gösterir. Şıklar
/// veri hazırlanırken karıştırılmıştır; oyun içinde yeniden karıştırmak
/// gerekmez ve karıştırılmaz — aynı soru her oyunda aynı görünür, oyuncu
/// "az önce B'ydi şimdi D" diye şaşırmaz.
@immutable
class TriviaQuestion {
  const TriviaQuestion({
    required this.id,
    required this.category,
    required this.difficulty,
    required this.prompt,
    required this.options,
    required this.answerIndex,
    required this.source,
    required this.verification,
    this.explanation,
  });

  final String id;
  final TriviaCategory category;
  final TriviaDifficulty difficulty;
  final String prompt;
  final List<String> options;
  final int answerIndex;

  /// Bilginin başvuru kaynağı.
  ///
  /// **Doğrulama iddiası taşımaz** — hangi kurumun bu konuyu belgelediğini
  /// söyler. Kaydın nasıl doğrulandığı [verification] alanındadır.
  final String source;

  final TriviaVerification verification;

  /// Cevap gösterilirken ekranda çıkan tek cümlelik not.
  ///
  /// **Zorunlu değil.** Yalnızca doğrulanabilir bir gerekçesi olan
  /// kayıtlarda dolu; boşsa ekran satırı hiç çizmez. Uydurma açıklama
  /// yazmaktansa hiç yazmamak doğru: yanlış bir açıklama, yanlış bir
  /// sorudan daha çok zarar verir.
  final String? explanation;

  String get answer => options[answerIndex];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TriviaQuestion && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// Bilgi sorularına tek erişim noktası.
///
/// Oyun kodu dosyayı bilmez, yalnızca bu arayüzü bilir — kaynak ileride
/// sunucuya taşınırsa **sadece implementasyon** değişir. Sunum katmanı
/// JSON'un tek dosya mı altı dosya mı olduğunu hiç görmez.
abstract class QuestionRepository {
  List<TriviaQuestion> questions();

  /// Yalnızca verilen kategorinin soruları.
  List<TriviaQuestion> byCategory(TriviaCategory category);
}

/// Boş havuz — soru dosyası okunamadığında oyun çökmesin diye.
class EmptyQuestionRepository implements QuestionRepository {
  const EmptyQuestionRepository();

  @override
  List<TriviaQuestion> questions() => const <TriviaQuestion>[];

  @override
  List<TriviaQuestion> byCategory(TriviaCategory category) =>
      const <TriviaQuestion>[];
}

/// `assets/data/trivia.json` dosyasından okunan, bellekte tutulan havuz.
///
/// **Tek dosya** seçildi, kategori başına ayrı dosya değil. Sebep: veri
/// 1.200 kayıt ve ~600 KB; altı dosya altı ayrı asset kaydı, altı ayrı
/// okuma ve altı ayrı hata yolu demekti. Kategori zaten her kaydın kendi
/// alanında; bölmenin kazandıracağı bir şey yok. Uygulama çevrimdışı
/// çalışıyor, veritabanı ya da ağ yok.
class QuestionDataset implements QuestionRepository {
  QuestionDataset._(this._questions) : _byCategory = _group(_questions);

  final List<TriviaQuestion> _questions;
  final Map<TriviaCategory, List<TriviaQuestion>> _byCategory;

  static Map<TriviaCategory, List<TriviaQuestion>> _group(
    List<TriviaQuestion> all,
  ) {
    final map = <TriviaCategory, List<TriviaQuestion>>{};
    for (final q in all) {
      (map[q.category] ??= <TriviaQuestion>[]).add(q);
    }
    return map;
  }

  /// Varsayılan veri dosyasını yükler.
  static Future<QuestionDataset> load({
    AssetBundle? bundle,
    String assetPath = 'assets/data/trivia.json',
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    return parse(raw);
  }

  /// JSON metnini ayrıştırır. Test'te dosyaya gitmeden çağrılabilir.
  ///
  /// Tek bir bozuk kayıt tüm dosyayı düşürmez: kategorisi tanınmayan ya da
  /// şık sayısı dörtten farklı olan kayıt **atlanır**. Oyun eksik bir
  /// soruyla devam edebilir, ama hiç soruyla devam edemez.
  static QuestionDataset parse(String rawJson) {
    final root = jsonDecode(rawJson) as Map<String, dynamic>;
    final items = root['questions'] as List<dynamic>;

    final out = <TriviaQuestion>[];
    for (final entry in items) {
      final map = entry as Map<String, dynamic>;
      final category = TriviaCategory.byId(map['category'] as String);
      if (category == null) continue;

      final options = <String>[
        for (final o in map['options'] as List<dynamic>) o as String,
      ];
      final answerIndex = map['correctAnswerIndex'] as int;
      if (options.length != 4) continue;
      if (answerIndex < 0 || answerIndex >= options.length) continue;

      out.add(
        TriviaQuestion(
          id: map['id'] as String,
          category: category,
          difficulty: TriviaDifficulty.byId(map['difficulty'] as String),
          prompt: map['question'] as String,
          options: List<String>.unmodifiable(options),
          answerIndex: answerIndex,
          source: map['source'] as String? ?? '',
          verification: TriviaVerification.byId(
            map['verification'] as String? ?? '',
          ),
          explanation: (map['explanation'] as String?)?.trim().isEmpty ?? true
              ? null
              : (map['explanation'] as String).trim(),
        ),
      );
    }
    return QuestionDataset._(List<TriviaQuestion>.unmodifiable(out));
  }

  @override
  List<TriviaQuestion> questions() => _questions;

  @override
  List<TriviaQuestion> byCategory(TriviaCategory category) =>
      _byCategory[category] ?? const <TriviaQuestion>[];
}
