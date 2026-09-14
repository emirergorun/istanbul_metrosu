import 'package:flutter/foundation.dart';

/// Sorunun nereden geldiği.
///
/// Ayrım rastgele değil, karışımı dengelemek için gerekli: ağ soruları
/// `metro.json`'dan **üretilir** (tükenmez), bilgi soruları elle **yazılır**
/// (sınırlı). Oyun, yazılı havuz bitince üretilene düşer.
enum QuizTopic {
  /// Metro ağından üretilen soru: önceki/sonraki durak, hat, son durak.
  network,

  /// Elle yazılmış İstanbul / metro bilgisi sorusu.
  trivia,
}

/// Dört şıklı tek soru.
///
/// [options] zaten karıştırılmış gelir ve [answerIndex] karıştırılmış liste
/// üzerindeki doğru şıkkı gösterir. Karıştırmayı üreten taraf yapar; ekran
/// listeyi olduğu gibi çizer, böylece her yeniden çizimde şıklar yer
/// değiştirmez.
@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.prompt,
    required this.options,
    required this.answerIndex,
    required this.topic,
    this.context,
  });

  /// Aynı soruyu bir yolculukta iki kez sormamak için kullanılır.
  final String id;

  final String prompt;
  final List<String> options;
  final int answerIndex;
  final QuizTopic topic;

  /// Sorunun üstünde duran küçük bağlam etiketi: `M4 hattı` gibi.
  final String? context;

  String get answer => options[answerIndex];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is QuizQuestion && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'QuizQuestion($id, $prompt)';
}
