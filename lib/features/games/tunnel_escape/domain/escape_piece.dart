/// Tünele Kaç'ın tahta parçası: tek yönde kayabilen bir metro.
///
/// Bu klasördeki alan katmanı **saf Dart**: Flutter'ı içe aktarmaz. Böylece
/// bölüm üretim aracı (`tool/tunnel_escape/`) aynı kuralları ve aynı
/// çözücüyü `dart run` ile kullanabiliyor; oyundaki kural ile bölümü
/// doğrulayan kural hiçbir zaman ayrı düşmüyor.
library;

/// Metronun ekseni. Yatay metro yalnız sağa-sola, dikey metro yalnız
/// yukarı-aşağı kayar; dönmez.
enum EscapeAxis { horizontal, vertical }

/// Bir metronun **değişmeyen** tanımı.
///
/// Konum burada yok: metronun kayabildiği tek koordinat tahtanın
/// durumuna ([EscapeBoard]) aittir. Değişmeyen koordinat [lane]'dir —
/// yatay metro için satır, dikey metro için sütun. Bu ayrım çözücünün de
/// temeli: bir tahta durumu, her metronun tek bir tamsayısından ibaret.
final class EscapePiece {
  const EscapePiece({
    required this.id,
    required this.axis,
    required this.length,
    required this.lane,
    this.isTarget = false,
  });

  /// Bölüm verisindeki harfi. Bölüm içinde benzersiz, kalıcı.
  final String id;

  final EscapeAxis axis;

  /// Kaç hücre kapladığı: 2 ya da 3.
  final int length;

  /// Sabit koordinat: yatayda satır, dikeyde sütun.
  final int lane;

  /// Kırmızı metro mu — tünele götürülecek olan.
  final bool isTarget;

  bool get isHorizontal => axis == EscapeAxis.horizontal;

  /// Metronun [position] konumunda kapladığı hücreler, `(satır, sütun)`.
  ///
  /// [position] kayan koordinattır: yatayda en soldaki sütun, dikeyde en
  /// üstteki satır.
  List<(int, int)> cellsAt(int position) => <(int, int)>[
    for (var i = 0; i < length; i++)
      isHorizontal ? (lane, position + i) : (position + i, lane),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EscapePiece &&
          other.id == id &&
          other.axis == axis &&
          other.length == length &&
          other.lane == lane &&
          other.isTarget == isTarget);

  @override
  int get hashCode => Object.hash(id, axis, length, lane, isTarget);

  @override
  String toString() =>
      'EscapePiece($id, ${isHorizontal ? 'yatay' : 'dikey'} $length, '
      'şerit $lane${isTarget ? ', hedef' : ''})';
}
