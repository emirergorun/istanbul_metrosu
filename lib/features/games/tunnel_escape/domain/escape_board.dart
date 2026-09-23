import 'escape_piece.dart';

/// Bir bölümün değişmeyen geometrisi: tahta boyu, metrolar ve çıkış.
///
/// Çarpışma denetimi bit maskeleriyle yapılıyor: her metronun her olası
/// konumu için kapladığı hücrelerin maskesi **bir kez** hesaplanıyor. Bir
/// hamlenin yasal olup olmadığı iki tamsayının `&` işlemine iniyor. Çözücü
/// saniyede yüz binlerce durum açarken bu fark belirleyici.
///
/// Çıkış her zaman **sağ kenarda**, hedef metronun satırında: tünel oradan
/// açılıyor. Kural tek yönlü tutuldu ki oyuncu tüneli bir kez öğrensin.
final class EscapeLayout {
  EscapeLayout({
    required this.width,
    required this.height,
    required List<EscapePiece> pieces,
  }) : pieces = List<EscapePiece>.unmodifiable(pieces),
       targetIndex = pieces.indexWhere((EscapePiece p) => p.isTarget) {
    if (width < 3 || height < 3 || width > maxSide || height > maxSide) {
      throw ArgumentError('Tahta 3 ile $maxSide arasında olmalı');
    }
    if (pieces.length > maxPieces) {
      throw ArgumentError('En fazla $maxPieces metro olabilir');
    }
    if (targetIndex < 0) throw ArgumentError('Hedef metro yok');
    if (pieces.where((EscapePiece p) => p.isTarget).length != 1) {
      throw ArgumentError('Tek bir hedef metro olmalı');
    }
    if (!pieces[targetIndex].isHorizontal) {
      throw ArgumentError('Hedef metro yatay olmalı: tünel sağ kenarda');
    }
    for (final piece in pieces) {
      final span = piece.isHorizontal ? width : height;
      final laneLimit = piece.isHorizontal ? height : width;
      if (piece.length < 2 || piece.length > span) {
        throw ArgumentError('${piece.id}: geçersiz uzunluk ${piece.length}');
      }
      if (piece.lane < 0 || piece.lane >= laneLimit) {
        throw ArgumentError('${piece.id}: şerit tahtanın dışında');
      }
      final max = span - piece.length;
      _maxPositions.add(max);
      _masks.add(<int>[for (var p = 0; p <= max; p++) _maskOf(piece, p)]);
    }
  }

  /// Kenar sınırı. 8'i geçen tahta telefonda parmak ucuna küçük gelir;
  /// üstelik anahtar biçimi konum başına 3 bit ayırıyor.
  static const int maxSide = 8;

  /// Anahtar 64 bitlik tamsayıya sığmalı: 20 metro × 3 bit = 60 bit.
  static const int maxPieces = 20;

  static const int _bitsPerPiece = 3;
  static const int _slotMask = (1 << _bitsPerPiece) - 1;

  final int width;
  final int height;
  final List<EscapePiece> pieces;
  final int targetIndex;

  final List<List<int>> _masks = <List<int>>[];
  final List<int> _maxPositions = <int>[];

  EscapePiece get target => pieces[targetIndex];

  /// Tünelin açıldığı satır.
  int get exitRow => target.lane;

  /// Hedef metronun tünel ağzına dayandığı konum — bölümün bittiği an.
  int get exitPosition => width - target.length;

  int get pieceCount => pieces.length;

  /// Metronun alabileceği en büyük konum.
  int maxPosition(int piece) => _maxPositions[piece];

  /// Metronun [position] konumundaki hücre maskesi.
  int maskOf(int piece, int position) => _masks[piece][position];

  /// Bütün metroların kapladığı hücreler.
  int occupancy(List<int> positions) {
    var occupied = 0;
    for (var i = 0; i < positions.length; i++) {
      occupied |= _masks[i][positions[i]];
    }
    return occupied;
  }

  /// Hücrenin tek bitlik maskesi.
  int cellBit(int row, int col) => 1 << (row * width + col);

  /// Konum listesinin **kanonik** anahtarı.
  ///
  /// Her metronun konumu 3 bitte, metro sırasıyla. Aynı dizilişin tek bir
  /// anahtarı var ve iki farklı dizilişin anahtarı hiçbir zaman aynı
  /// olmuyor — çözücünün "bu durumu gördüm mü" sorusu buna dayanıyor.
  int keyOf(List<int> positions) {
    var key = 0;
    for (var i = 0; i < positions.length; i++) {
      key |= positions[i] << (_bitsPerPiece * i);
    }
    return key;
  }

  /// Anahtardaki bir metronun konumu.
  int positionIn(int key, int piece) =>
      (key >> (_bitsPerPiece * piece)) & _slotMask;

  /// Anahtarı konum listesine açar.
  List<int> positionsOf(int key) => <int>[
    for (var i = 0; i < pieces.length; i++) positionIn(key, i),
  ];

  /// Tek bir metronun konumu değişmiş anahtar.
  int keyWith(int key, int piece, int position) {
    final shift = _bitsPerPiece * piece;
    return (key & ~(_slotMask << shift)) | (position << shift);
  }

  int _maskOf(EscapePiece piece, int position) {
    var mask = 0;
    for (final (row, col) in piece.cellsAt(position)) {
      mask |= cellBit(row, col);
    }
    return mask;
  }
}

/// Tek bir hamle: bir metro, bir yönde, istediği kadar hücre.
///
/// Oyuncunun tek sürükleyişi tek hamledir — metro 1 hücre de gitse 3 hücre
/// de gitse. Çözücü de hamleyi aynı ölçüyle sayar; yıldız eşikleri bu iki
/// sayının aynı dili konuşmasına dayanıyor.
final class EscapeMove {
  const EscapeMove({required this.piece, required this.from, required this.to});

  /// Metronun bölümdeki sırası.
  final int piece;
  final int from;
  final int to;

  /// İşaretli uzaklık: artı sağa/aşağı, eksi sola/yukarı.
  int get delta => to - from;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EscapeMove &&
          other.piece == piece &&
          other.from == from &&
          other.to == to);

  @override
  int get hashCode => Object.hash(piece, from, to);

  @override
  String toString() => 'EscapeMove($piece: $from → $to)';
}

/// Tahtanın bir anı: her metronun konumu.
///
/// Değişmez: hamle yeni bir tahta üretir. Geri alma bu yüzden bir yığından
/// eski tahtayı çekmekten ibaret ve hiçbir ara durum (yarım sürükleme)
/// yığına giremiyor.
final class EscapeBoard {
  EscapeBoard(this.layout, List<int> positions)
    : positions = List<int>.unmodifiable(positions) {
    if (positions.length != layout.pieceCount) {
      throw ArgumentError('Konum sayısı metro sayısıyla aynı olmalı');
    }
    for (var i = 0; i < positions.length; i++) {
      if (positions[i] < 0 || positions[i] > layout.maxPosition(i)) {
        throw ArgumentError('${layout.pieces[i].id}: tahtanın dışında');
      }
    }
  }

  final EscapeLayout layout;
  final List<int> positions;

  int get key => layout.keyOf(positions);

  /// Hedef metro tünel ağzında mı?
  bool get isSolved => positions[layout.targetIndex] == layout.exitPosition;

  /// Metroların birbirinin içine girmediği geçerli bir diziliş mi?
  bool get isValid {
    var occupied = 0;
    for (var i = 0; i < positions.length; i++) {
      final mask = layout.maskOf(i, positions[i]);
      if (occupied & mask != 0) return false;
      occupied |= mask;
    }
    return true;
  }

  /// Hedefin önü tünele kadar boş mu? "Yol açıldı" anı.
  bool get isTargetPathClear =>
      rangeOf(layout.targetIndex).$2 == layout.exitPosition;

  /// Metronun **bu tahtada** gidebileceği en küçük ve en büyük konum.
  ///
  /// Arada kalan her konum da erişilebilir: metro önündeki ilk engele
  /// kadar kayar, üstünden atlayamaz.
  (int, int) rangeOf(int piece) {
    final others =
        layout.occupancy(positions) & ~layout.maskOf(piece, positions[piece]);
    var low = positions[piece];
    while (low > 0 && layout.maskOf(piece, low - 1) & others == 0) {
      low--;
    }
    var high = positions[piece];
    final max = layout.maxPosition(piece);
    while (high < max && layout.maskOf(piece, high + 1) & others == 0) {
      high++;
    }
    return (low, high);
  }

  bool canMove(int piece, int to) {
    final (low, high) = rangeOf(piece);
    return to >= low && to <= high;
  }

  /// Metroyu [to] konumuna kaydırılmış yeni tahta.
  ///
  /// Yasadışı hamle hata fırlatır: arayüz metroyu zaten [rangeOf] içinde
  /// tutuyor, buraya kadar gelen yasadışı hamle bir programlama hatasıdır.
  EscapeBoard moved(int piece, int to) {
    if (!canMove(piece, to)) {
      throw StateError('${layout.pieces[piece].id} $to konumuna gidemez');
    }
    return EscapeBoard(layout, <int>[
      for (var i = 0; i < positions.length; i++) i == piece ? to : positions[i],
    ]);
  }

  /// Hücredeki metronun sırası; boşsa `null`.
  int? pieceAt(int row, int col) {
    if (row < 0 || col < 0 || row >= layout.height || col >= layout.width) {
      return null;
    }
    final bit = layout.cellBit(row, col);
    for (var i = 0; i < positions.length; i++) {
      if (layout.maskOf(i, positions[i]) & bit != 0) return i;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EscapeBoard &&
          identical(other.layout, layout) &&
          other.key == key);

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'EscapeBoard($positions)';
}
