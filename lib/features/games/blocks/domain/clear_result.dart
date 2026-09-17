import 'package:flutter/foundation.dart';

/// Bir hamlede temizlenen line sayısının kademesi.
///
/// Kademe **yalnızca sınıflandırmadır**: puanı, sesi, titreşimi ya da
/// efekti bilmez. Sunum katmanı kademeye bakıp kendi kararını verir; oyun
/// motoru hangi rengin parladığını bilmek zorunda kalmaz.
enum ClearTier {
  /// Hiç line temizlenmedi.
  none,
  single,
  double,
  triple,

  /// Aynı hamlede 4 veya daha fazla line.
  mega;

  /// Temizlenen line sayısından kademe.
  static ClearTier of(int lines) {
    if (lines <= 0) return ClearTier.none;
    if (lines == 1) return ClearTier.single;
    if (lines == 2) return ClearTier.double;
    if (lines == 3) return ClearTier.triple;
    return ClearTier.mega;
  }

  bool get isClear => this != ClearTier.none;

  /// Kademe gücü 0..4 — efekt, ses ve titreşim şiddeti buradan ölçeklenir.
  int get intensity => index;
}

/// Kademenin oyuncuya gösterilen adı.
///
/// Metinler tek yerde: tema değişirse ("İKİ VAGON", "ÇİFT HAT") yalnızca bu
/// tablo değişir, oyun kodunda arama yapmak gerekmez.
const Map<ClearTier, String> kClearTierLabels = <ClearTier, String>{
  ClearTier.none: '',
  ClearTier.single: '',
  ClearTier.double: '2 SIRA BİRDEN',
  ClearTier.triple: '3 SIRA BİRDEN',
  ClearTier.mega: '4 SIRA BİRDEN',
};

/// Combo kızıştıkça çıkan etiketler: eşik -> metin.
///
/// Combo sayısı zaten ekranda; bu etiket sayının söylemediğini söyler —
/// "iyi gidiyorsun, sürdür". Eşikler seyrek tutuldu: her combo'da bir şey
/// bağırmak, bağırmanın kendisini değersizleştirir.
///
/// Metinler **trenin hızından bahsetmez.** İyi oyun yolculuğa saniye
/// katıyor, yani tren gerçekten hızlanıyor; "HIZLANIYOR" gibi bir etiket
/// oyuncunun combo etiketiyle tren hızını karıştırmasına yol açıyordu.
/// Bunlar yalnızca combo'yu över.
///
/// Metinler tek yerde: metro temasına göre değiştirmek için yalnızca bu
/// tablo yeter.
const Map<int, String> kComboHeatLabels = <int, String>{
  5: 'İYİ GİDİYOR',
  8: 'MÜTHİŞ',
  12: 'DURDURULAMAZ',
};

/// Combo bu değere ulaşınca geri bildirim ekranın tamamına taşar:
/// nabız ve güçlü titreşim. Altındaki combo'lar yalnızca tahtada kutlanır.
const int kComboPulseThreshold = 5;

/// Combo sesi bu eşikten itibaren çalar.
///
/// İki ardışık temizlik sık olur; her seferinde farklı bir ses çalmak
/// combo sesini sıradanlaştırıyordu.
const int kComboSoundThreshold = 3;

/// [combo] için geçerli kızışma etiketi — eşiğin altındaysa `null`.
String? comboHeatLabel(int combo) {
  String? label;
  for (final entry in kComboHeatLabels.entries) {
    if (combo >= entry.key) label = entry.value;
  }
  return label;
}

/// Tek bir hamlenin **tam sonucu**.
///
/// Motor bu nesneyi üretir; skor, efekt, ses, titreşim ve HUD hepsi bunu
/// okur. Amaç prompt'un istediği ayrışma: oyun mantığı *ne olduğunu*
/// hesaplar, sunum *nasıl görüneceğine* karar verir.
@immutable
class ClearResult {
  const ClearResult({
    required this.clearedRows,
    required this.clearedColumns,
    required this.clearedCellValues,
    required this.comboIndex,
    required this.streakIndex,
    required this.scoreAwarded,
    required this.journeySecondsAwarded,
  });

  /// Hiçbir line temizlenmeyen hamle.
  const ClearResult.none({
    required this.comboIndex,
    required this.streakIndex,
    required this.scoreAwarded,
  }) : clearedRows = const <int>[],
       clearedColumns = const <int>[],
       clearedCellValues = const <int, int>{},
       journeySecondsAwarded = 0;

  final List<int> clearedRows;
  final List<int> clearedColumns;

  /// Temizlenen hücrelerin **silinmeden önceki** renk değerleri.
  ///
  /// Anahtar `satır * sütunSayısı + sütun`. Patlama efekti blokları kendi
  /// renklerinde savurabilsin diye taşınır; tahta temizlendikten sonra bu
  /// bilgi başka yerden okunamaz.
  final Map<int, int> clearedCellValues;

  /// Hamle sonrası combo değeri.
  final int comboIndex;

  /// Hamle sonrası streak değeri.
  final int streakIndex;

  /// Bu hamlede kazanılan puan (yerleştirme dahil).
  final int scoreAwarded;

  /// Bu hamlenin yolculuğa kattığı saniye — tren bu kadar hızlanır.
  final int journeySecondsAwarded;

  int get totalLines => clearedRows.length + clearedColumns.length;

  /// Aynı hamlede hem satır hem sütun temizlendi mi?
  bool get simultaneousClear =>
      clearedRows.isNotEmpty && clearedColumns.isNotEmpty;

  ClearTier get tier => ClearTier.of(totalLines);

  bool get didClear => totalLines > 0;

  /// Temizlenen hücre sayısı; kesişim iki kez sayılmaz.
  int get clearedCellCount => clearedCellValues.length;

  @override
  String toString() =>
      'ClearResult(${tier.name}, $totalLines line, combo $comboIndex, '
      'streak $streakIndex, +$scoreAwarded puan, '
      '+$journeySecondsAwarded sn)';
}
