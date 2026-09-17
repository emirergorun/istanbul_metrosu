/// Metro Bilgi'nin altı soru kategorisi.
///
/// Kimlikler veri dosyasındaki `category` alanıyla birebir aynıdır ve
/// **değiştirilmemelidir**: kayıtlı rekorlar ve soru dosyası bu adlara
/// bağlı.
///
/// Etiket, kısa ad ve simge tek yerde durur. Eşlemeyi widget'lara
/// dağıtmak, yeni bir kategori eklendiğinde altı ayrı dosyayı düzeltmeyi
/// gerektirirdi.
enum TriviaCategory {
  history('history', 'Tarih', 'TAR'),
  cultureArt('culture_art', 'Kültür & Sanat', 'SAN'),
  sports('sports', 'Spor', 'SPO'),
  geographyCity('geography_city', 'Coğrafya & Şehir', 'COĞ'),
  transportation('transportation', 'Ulaşım', 'ULA'),
  generalKnowledge('general_knowledge', 'Genel Kültür', 'GNL');

  const TriviaCategory(this.id, this.label, this.badge);

  /// Veri dosyasındaki kimlik.
  final String id;

  /// Oyuncuya gösterilen ad.
  final String label;

  /// Hat rozetiyle aynı biçimde çizilen üç harfli kısaltma.
  ///
  /// Metro kimliğine bağlanmanın en ucuz yolu: oyunun her yerinde hat
  /// rozetleri (`M1A`, `M4`) var, kategori de aynı dilde konuşuyor.
  final String badge;

  static TriviaCategory? byId(String id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Sorunun bilgi zorluğu.
enum TriviaDifficulty {
  easy('easy'),
  medium('medium'),
  hard('hard');

  const TriviaDifficulty(this.id);

  final String id;

  static TriviaDifficulty byId(String id) {
    for (final d in values) {
      if (d.id == id) return d;
    }
    return TriviaDifficulty.medium;
  }
}

/// Bir kaydın nasıl doğrulandığı.
///
/// Veri dosyasında her sorunun yanında durur ve **iddia edilenden fazlasını
/// söylemez**: [modelKnowledge] olan bir kayıt bağımsız bir kaynakla
/// karşılaştırılmadı. Bu ayrım kodda da taşınıyor ki ileride "hangi
/// soruları doğrulamamız gerekiyor" sorusu veriden cevaplanabilsin.
enum TriviaVerification {
  /// Depodaki `assets/data/metro.json` verisine karşı programatik olarak
  /// doğrulandı.
  metroJson('metro_json'),

  /// Bağımsız bir kaynakla doğrulanmadı.
  modelKnowledge('model_knowledge');

  const TriviaVerification(this.id);

  final String id;

  static TriviaVerification byId(String id) {
    for (final v in values) {
      if (v.id == id) return v;
    }
    return TriviaVerification.modelKnowledge;
  }
}
