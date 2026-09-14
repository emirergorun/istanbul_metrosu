import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Elle yazılmış bilgi sorusu.
///
/// [answerIndex] **dosyadaki** sıraya göre doğru şıkkı gösterir; şıklar
/// oyuna verilirken karıştırılır, yani doğru cevap her oyunda farklı
/// konumda çıkar.
class TriviaQuestion {
  const TriviaQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    required this.answerIndex,
    this.context,
    this.source,
  });

  final String id;
  final String prompt;
  final List<String> options;
  final int answerIndex;

  /// Sorunun üstündeki küçük etiket: `Marmaray`, `Tarih` gibi.
  final String? context;

  /// Bilginin kaynağı. Kaynaksız soru eklenmemeli: oyun bir bilgiyi
  /// doğruymuş gibi söylüyorsa, nereden aldığı da yazılı olmalı.
  final String? source;

  String get answer => options[answerIndex];
}

/// Bilgi sorularına tek erişim noktası.
///
/// Oyun kodu dosyayı bilmez, yalnızca bu arayüzü bilir — kaynak ileride
/// sunucuya taşınırsa **sadece implementasyon** değişir.
abstract class QuestionRepository {
  List<TriviaQuestion> questions();
}

/// Boş havuz: bilgi sorusu yok, oyun yalnızca üretilen sorularla oynanır.
///
/// Varsayılan olarak kullanılır — bilgi soruları oyunun omurgası değil
/// çeşnisi olduğu için, havuzu vermeyen bir çağıran da geçerli olmalı.
class EmptyQuestionRepository implements QuestionRepository {
  const EmptyQuestionRepository();

  @override
  List<TriviaQuestion> questions() => const <TriviaQuestion>[];
}

/// `assets/data/questions.json` dosyasından okunan, bellekte tutulan havuz.
///
/// Veritabanı yok: uygulama çevrimdışı çalışıyor, soru sayısı birkaç yüzü
/// geçmiyor ve sorular sürüm başına sabit. SQLite ya da uzak servis bugün
/// yalnızca paket ve karmaşıklık eklerdi.
class QuestionDataset implements QuestionRepository {
  QuestionDataset._(this._questions);

  final List<TriviaQuestion> _questions;

  static const String assetPath = 'assets/data/questions.json';

  /// Dosya okunamazsa **boş havuz** döner, hata fırlatmaz.
  ///
  /// Bilgi soruları oyunun omurgası değil, çeşnisi: dosya bozuksa oyun
  /// üretilen ağ sorularıyla oynanmaya devam etmeli.
  static Future<QuestionDataset> load({AssetBundle? bundle}) async {
    try {
      final raw = await (bundle ?? rootBundle).loadString(assetPath);
      return QuestionDataset.parse(raw);
    } catch (_) {
      return QuestionDataset._(const <TriviaQuestion>[]);
    }
  }

  /// Test ve araçlar için: ham JSON'dan havuz üretir.
  factory QuestionDataset.parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['questions'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();

    final questions = <TriviaQuestion>[];
    for (final item in list) {
      final options = (item['options'] as List<dynamic>? ?? <dynamic>[])
          .map((o) => o as String)
          .toList();
      final answer = item['answer'] as int? ?? -1;
      // Bozuk kayıt sessizce atlanır: tek hatalı soru yüzünden havuzun
      // tamamı kaybolmamalı.
      if (options.length < 4) continue;
      if (answer < 0 || answer >= options.length) continue;

      questions.add(
        TriviaQuestion(
          id: item['id'] as String,
          prompt: item['text'] as String,
          options: List<String>.unmodifiable(options),
          answerIndex: answer,
          context: item['context'] as String?,
          source: item['source'] as String?,
        ),
      );
    }
    return QuestionDataset._(List<TriviaQuestion>.unmodifiable(questions));
  }

  @override
  List<TriviaQuestion> questions() => _questions;
}
