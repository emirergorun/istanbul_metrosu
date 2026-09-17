import 'dart:math';

import '../../../../core/constants/app_constants.dart';
import '../../../journey/models/difficulty_profile.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/piece_shapes.dart';

/// Tepsiye gelen parçaları üretir.
///
/// Tam random kullanılmaz:
/// - zorluk profiline göre kolay/orta/zor havuzları ağırlıklandırılır,
/// - her havuz bir **torbadır**: çekilen şekil torbadan çıkar, torba bitince
///   karıştırılıp yenilenir,
/// - aynı tepside aynı şekil tekrar etmemeye çalışılır,
/// - üretilen tepside **en az bir** legal hamle olması garanti edilmeye
///   çalışılır (fairness kuralı).
///
/// Torba olmadan ölçüm şuydu: kısa yolculuklarda beş küçük şekil tüm
/// parçaların %41'ini kaplıyor, tepsilerin %17'sinde aynı şekil tekrar
/// ediyordu. Torba, havuzdaki her şeklin görünmesini garanti eder.
class PieceGenerator {
  PieceGenerator({
    Random? random,
    this.colorCount = AppConstants.blockColorCount,
  }) : _random = random ?? Random();

  final Random _random;

  /// Blok renk paletindeki renk sayısı.
  final int colorCount;

  /// Zorluk havuzu başına karıştırılmış torba.
  final Map<PieceDifficulty, List<BlockPiece>> _bags =
      <PieceDifficulty, List<BlockPiece>>{};

  /// Torbadan bir şekil çeker; torba boşsa karıştırıp yeniler.
  BlockPiece _drawShape(PieceDifficulty tier) {
    final bag = _bags[tier] ??= _refill(tier);
    if (bag.isEmpty) bag.addAll(_refill(tier));
    return bag.removeLast();
  }

  List<BlockPiece> _refill(PieceDifficulty tier) =>
      List<BlockPiece>.of(PieceShapes.pool(tier))..shuffle(_random);

  /// Tahta boşken zor (büyük) havuzun olasılığı bu katsayıyla çarpılır.
  ///
  /// 3x3 kare, 2x3 dikdörtgen ve 5'li çubuk eldeki en eğlenceli parçalar:
  /// tek hamlede iki hattı birden temizleyebiliyorlar. Ama sabit bir
  /// olasılıkla dağıtıldıklarında iki sorun birden çıkıyordu — tahta
  /// doluyken geldiklerinde oyunu bitiriyorlar, boşken ise neredeyse hiç
  /// görünmüyorlardı (ölçüm: tüm parçaların %0.4 - %0.9'u).
  ///
  /// Kural tek cümle: **tahta boşken büyük parça gelir, doldukça küçülür.**
  /// Böylece büyük parça tam da keyifli olduğu anda geliyor, öldürücü
  /// olduğu anda gelmiyor. Oyuncuya kıyak değil, parçayı doğru zamana
  /// koymak.
  static const double openBoardHardBoost = 2.2;

  /// Tahta doluyken aynı olasılığın çarpanı.
  static const double fullBoardHardBoost = 0.35;

  /// Zorluk havuzu seçimi.
  ///
  /// `hardPieceWeight` zor havuzunun temel olasılığıdır; tahtanın doluluğuna
  /// göre [openBoardHardBoost] ile [fullBoardHardBoost] arasında ölçeklenir.
  /// Kalan olasılık kolay/orta arasında 55/45 bölünür.
  PieceDifficulty _rollDifficulty(DifficultyProfile profile, double fill) {
    final openness = (1 - fill).clamp(0.0, 1.0);
    final boost =
        fullBoardHardBoost +
        (openBoardHardBoost - fullBoardHardBoost) * openness;
    final hard = (profile.hardPieceWeight * boost).clamp(0.0, 1.0);

    final rest = 1.0 - hard;
    final easyChance = rest * 0.55;

    final roll = _random.nextDouble();
    if (roll < easyChance) return PieceDifficulty.easy;
    if (roll < easyChance + rest * 0.45) return PieceDifficulty.medium;
    return PieceDifficulty.hard;
  }

  /// Tek parça üretir (renk atanmış olarak).
  ///
  /// [fill] tahtanın doluluk oranıdır (0..1); büyük parçaların sıklığını
  /// belirler. Verilmezse tahta boş sayılır.
  BlockPiece nextPiece(DifficultyProfile profile, {double fill = 0}) =>
      _drawShape(_rollDifficulty(profile, fill)).withColor(_randomColor());

  int _randomColor() => 1 + _random.nextInt(colorCount);

  /// Tepsi için parça çeker; mümkünse tepsideki şekilleri tekrarlamaz.
  BlockPiece _nextDistinct(
    DifficultyProfile profile,
    Set<String> used,
    double fill,
  ) {
    for (var attempt = 0; attempt < 6; attempt++) {
      final piece = nextPiece(profile, fill: fill);
      if (used.add(piece.id)) return piece;
    }
    return nextPiece(profile, fill: fill);
  }

  // --- Kurtarıcı parça ---
  //
  // Tahtada az kalmış bir hat varken (ör. alt satırın yalnızca üç hücresi
  // boş) tepsinin oyuncuya **tam o boşluğa oturan** parçayı vermesi.
  // Oyuncu patlatır, "yakaladım" der ve devam etme isteği artar.
  //
  // Bu bilinçli bir kayırma. Gerekçesi: tek başına rastgelelik, oyuncunun
  // kurduğu planı çoğu zaman ödüllendirmiyor — satırı üç hücreye kadar
  // getirip sonra işe yaramaz üç parça alan oyuncu, kendi hatasından değil
  // şanssızlıktan kaybediyor. Kurtarıcı parça bu emeği karşılıyor.
  //
  // Her seferinde verilmez: [rescueChance] altında kalınırsa tepsi normal
  // yoldan üretilir. Sürekli verilseydi oyuncu kalıbı birkaç turda çözer,
  // patlatma sıradanlaşır ve gerilim biterdi.

  /// Bir hattın "kapanmaya yakın" sayılması için en çok kaç hücresi boş
  /// olabilir.
  ///
  /// Üçten fazlası artık "az kalmış" değil: tek parçayla kapatmak da zor,
  /// oyuncunun kurduğu bir plan olduğu da şüpheli.
  static const int nearCompleteGap = 3;

  /// Az kalmış hat varken kurtarıcı parçanın gelme olasılığı.
  static const double rescueChance = 0.70;

  /// Kurtarıcı parça aranırken denenecek aday tepsi sayısı.
  static const int rescueCandidates = 8;

  /// Tahta bu doluluğun üstündeyken tepsi seçimi titizleşir.
  ///
  /// Altında tahta zaten rahat: her parça bir yere sığar, seçim yapmanın
  /// anlamı yok ve rastgelelik korunmalı.
  static const double crowdedFillRatio = 0.40;

  /// 3'lü tepsi üretir.
  ///
  /// İki kural var:
  ///
  /// **Fairness:** tepside en az bir parça board'a konabilmeli. En fazla
  /// [AppConstants.maxTrayGenerationAttempts] deneme yapılır; hiçbiri
  /// tutmazsa son deneme yine de döner (board gerçekten doluysa oyun
  /// zaten game-over olacaktır).
  ///
  /// **Sıkışık tahtada aday seçimi:** tahta [crowdedFillRatio] üstündeyse
  /// [DifficultyProfile.trayCandidates] kadar aday tepsi üretilir ve en çok
  /// hamle imkânı sunan seçilir. Bu oyuncuya kıyak değil, haksız diziyi
  /// elemektir: dolu tahtada rastgele üç parçanın hiçbirinin işe yaramaması
  /// sık oluyor ve oyun oyuncunun hatasından değil şanssızlıktan bitiyordu.
  /// Tahta rahatken bu adım hiç çalışmaz, rastgelelik bozulmaz.
  List<BlockPiece> generateTray(Board board, DifficultyProfile profile) {
    final crowded = board.filledCount / board.cellCount >= crowdedFillRatio;

    // Kurtarıcı parça yalnızca kapanmaya yakın bir hat varken devreye
    // girer; boş tahtada aranacak bir şey yok.
    final rescue =
        hasNearCompleteLine(board, maxGap: nearCompleteGap) &&
        _random.nextDouble() < rescueChance;

    var candidates = crowded ? profile.trayCandidates : 1;
    if (rescue && candidates < rescueCandidates) candidates = rescueCandidates;
    if (candidates < 1) candidates = 1;

    if (candidates == 1) return _generateOne(board, profile);

    List<BlockPiece>? best;
    var bestScore = -1;

    for (var pick = 0; pick < candidates; pick++) {
      final tray = _generateOne(board, profile);
      final freedom = _trayFreedom(board, tray);

      // Kurtarma turunda hattı kapatabilen tepsi her zaman önce gelir;
      // eşitlik bozulursa yine en çok hamle imkânı sunan seçilir.
      final score = rescue && _canCompleteLine(board, tray)
          ? freedom + _rescueBonus
          : freedom;

      if (score > bestScore) {
        bestScore = score;
        best = tray;
      }
    }
    return best ?? _generateOne(board, profile);
  }

  /// Kurtarıcı tepsinin puanına eklenen, özgürlükle yarışmayacak kadar
  /// büyük sabit. Tahtadaki toplam konum sayısından fazla olmalı.
  static const int _rescueBonus = 1 << 20;

  /// Tek bir aday tepsi üretir; fairness kuralı burada uygulanır.
  List<BlockPiece> _generateOne(Board board, DifficultyProfile profile) {
    final fill = board.filledCount / board.cellCount;
    List<BlockPiece> tray = const <BlockPiece>[];

    for (
      var attempt = 0;
      attempt < AppConstants.maxTrayGenerationAttempts;
      attempt++
    ) {
      final used = <String>{};
      tray = <BlockPiece>[
        for (var i = 0; i < AppConstants.traySize; i++)
          _nextDistinct(profile, used, fill),
      ];
      if (hasAnyLegalMove(board, tray)) return tray;
    }

    // Son çare: sadece kolay havuzdan dene — dar board'larda kurtarır.
    for (
      var attempt = 0;
      attempt < AppConstants.maxTrayGenerationAttempts;
      attempt++
    ) {
      tray = <BlockPiece>[
        for (var i = 0; i < AppConstants.traySize; i++)
          _drawShape(PieceDifficulty.easy).withColor(_randomColor()),
      ];
      if (hasAnyLegalMove(board, tray)) return tray;
    }

    return tray;
  }

  /// Tepsideki parçalardan biri tek hamlede bir hat kapatabiliyor mu?
  bool _canCompleteLine(Board board, List<BlockPiece> tray) {
    for (final piece in tray) {
      for (var r = 0; r <= board.rows - piece.height; r++) {
        for (var c = 0; c <= board.cols - piece.width; c++) {
          if (!canPlace(board, piece, r, c)) continue;
          if (_completesLine(board, piece, r, c)) return true;
        }
      }
    }
    return false;
  }

  /// Parça ([row],[col]) köşesine konunca bir satır ya da sütun dolar mı?
  ///
  /// Tahtayı kopyalamadan bakar: her satır ve sütunun boş hücre sayısı
  /// biliniyorsa, parçanın o hat üzerinde kaç boş hücre doldurduğunu saymak
  /// yeter. Tepsi üretimi aday başına yüzlerce konum deniyor; her denemede
  /// tahta kopyalamak ölçülebilir şekilde yavaşlatıyordu.
  bool _completesLine(Board board, BlockPiece piece, int row, int col) {
    final rowFill = <int, int>{};
    final colFill = <int, int>{};
    for (final cell in piece.cells) {
      final r = row + cell.row;
      final c = col + cell.col;
      rowFill[r] = (rowFill[r] ?? 0) + 1;
      colFill[c] = (colFill[c] ?? 0) + 1;
    }

    for (final entry in rowFill.entries) {
      if (_emptyInRow(board, entry.key) == entry.value) return true;
    }
    for (final entry in colFill.entries) {
      if (_emptyInColumn(board, entry.key) == entry.value) return true;
    }
    return false;
  }

  int _emptyInRow(Board board, int row) {
    var empty = 0;
    for (var c = 0; c < board.cols; c++) {
      if (board.isEmptyAt(row, c)) empty++;
    }
    return empty;
  }

  int _emptyInColumn(Board board, int col) {
    var empty = 0;
    for (var r = 0; r < board.rows; r++) {
      if (board.isEmptyAt(r, col)) empty++;
    }
    return empty;
  }

  /// Tepsinin tahtada kaç ayrı yere konabildiği.
  ///
  /// "Özgürlük" ölçüsü: sayı ne kadar büyükse oyuncunun o tepsiyle o kadar
  /// çok seçeneği var, yani tahtayı kilitlemeden oynayabilme ihtimali o
  /// kadar yüksek. Tek tek parçaların toplamı alınır; hiç sığmayan parça
  /// sıfır katkı verir.
  int _trayFreedom(Board board, List<BlockPiece> tray) {
    var total = 0;
    for (final piece in tray) {
      for (var r = 0; r <= board.rows - piece.height; r++) {
        for (var c = 0; c <= board.cols - piece.width; c++) {
          if (canPlace(board, piece, r, c)) total++;
        }
      }
    }
    return total;
  }

  /// Oyun başında zorluk profiline göre engel hücreleri serpiştirir.
  ///
  /// Engeller normal dolu hücre gibi davranır; satır/sütun temizliğinde
  /// silinebilirler (kalıcı ölü hücre bırakmamak için).
  Board applyInitialBlockers(Board board, DifficultyProfile profile) {
    final ratio = profile.initialBlockerRatio.clamp(0.0, 0.5);
    if (ratio <= 0) return board;

    final target = (board.cellCount * ratio).round();
    if (target <= 0) return board;

    final grid = board.toGrid();
    var placed = 0;
    var guard = 0;
    while (placed < target && guard < board.cellCount * 10) {
      guard++;
      final r = _random.nextInt(board.rows);
      final c = _random.nextInt(board.cols);
      if (grid[r][c] != kEmptyCell) continue;
      // En üst satır boş bırakılır: oyun açılışında tahtanın tepesi kilitli
      // görünmesin, uzun parçalar için her zaman temiz bir sıra kalsın.
      if (r == 0) continue;
      grid[r][c] = kBlockerCell;
      placed++;
    }
    return Board.fromGrid(grid);
  }
}
