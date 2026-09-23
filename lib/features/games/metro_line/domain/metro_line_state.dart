import 'dart:math';

import 'package:flutter/foundation.dart';

/// Tahtanın en küçük ve en büyük kenarı.
///
/// 5'ten 6'ya çıkarıldı: 5x5'te trenler ekranda kocaman duruyor ve tahta
/// birkaç dokunuşta bitiyordu. Üst sınır 8'den 10'a çıktı; 10x10 telefonda
/// hücre başına ~34 px demek, parmak ucu için hâlâ rahat.
const int metroLineMinSize = 6;
const int metroLineMaxSize = 10;

/// Bir trenin en az ve en çok kaç vagonu olur.
///
/// Üst sınır 5'ten 4'e indirildi: beş vagonluk tren küçük tahtanın yarısını
/// kaplıyor, hem görsel olarak hantal hem de bulmacayı basitleştiriyordu
/// (az sayıda kocaman parça = az karar).
const int metroLineMinCars = 2;
const int metroLineMaxCars = 4;

/// Her seviyede oyuncunun hakkı. Yanlış dokunuş birini götürür.
const int metroLineHearts = 3;

/// Trenin tahtadan çıkacağı yön — baştaki okun gösterdiği yön.
enum MetroLineDirection { up, down, left, right }

extension MetroLineDirectionX on MetroLineDirection {
  /// Bu yönde bir hücrelik adım. x sütun, y satırdır.
  Point<int> get delta => switch (this) {
    MetroLineDirection.up => const Point<int>(0, -1),
    MetroLineDirection.down => const Point<int>(0, 1),
    MetroLineDirection.left => const Point<int>(-1, 0),
    MetroLineDirection.right => const Point<int>(1, 0),
  };
}

/// Tahtadaki bir metro treni: uç uca eklenmiş vagonlardan oluşan bir yol.
///
/// [cells] **baştan kuyruğa** sıralıdır: ilk eleman lokomotif. Tren
/// çıkarken baş [direction] yönünde ilerler, vagonlar da başın geçtiği
/// yoldan onu takip eder — yılan gibi. Bu yüzden çıkış için yalnızca
/// **başın önündeki koridorun** boş olması yeter; vagonların arkadaki
/// hücreleri zaten trenin kendisine ait.
@immutable
class MetroLineTrain {
  const MetroLineTrain({
    required this.id,
    required this.cells,
    required this.direction,
    required this.lineIndex,
  });

  final int id;

  /// Baş önce, kuyruk sonra. Her ardışık çift komşu hücredir.
  final List<Point<int>> cells;

  final MetroLineDirection direction;

  /// Hangi hat rengiyle çizileceği.
  final int lineIndex;

  Point<int> get head => cells.first;
  int get carCount => cells.length;

  /// Başın önünde, tahta kenarına kadar uzanan hücreler.
  ///
  /// Çıkış koşulu bu listenin tamamen boş olmasıdır.
  List<Point<int>> corridor(int size) {
    final step = direction.delta;
    final cells = <Point<int>>[];
    var p = Point<int>(head.x + step.x, head.y + step.y);
    while (p.x >= 0 && p.x < size && p.y >= 0 && p.y < size) {
      cells.add(p);
      p = Point<int>(p.x + step.x, p.y + step.y);
    }
    return cells;
  }
}

/// Üretilmiş bir bulmaca.
@immutable
class MetroLinePuzzle {
  const MetroLinePuzzle({
    required this.size,
    required this.trains,
    required this.solution,
  });

  final int size;
  final List<MetroLineTrain> trains;

  /// Üreticinin garanti ettiği **bir** çözüm sırası (tren kimlikleri).
  ///
  /// Tek çözüm değil, var olan bir çözüm: oyuncu başka sırayla da
  /// bitirebilir. İpucu ve "çözülebilir mi" denetimi bunu kullanır.
  final List<int> solution;
}

/// Rastgele ama **her zaman çözülebilir** bir bulmaca üretir.
///
/// Anahtar fikir: bulmacayı çözerek değil, **çözümü tersten oynayarak**
/// kurmak. Trenler tahtaya, oyunda çıkacakları sıranın tersinden eklenir.
///
/// Neden işe yarıyor: oyunda T treni çıkarken tahtada yalnızca ondan
/// **sonra** çıkacak trenler durur. Tersten eklerken T'yi koyduğumuz anda
/// tahtada duranlar da tam olarak onlardır. Dolayısıyla "T'nin koridoru şu
/// an boş" koşulunu ekleme sırasında sağlamak, oyunda o sıranın
/// yürüyeceğini garanti eder.
///
/// Rastgele yerleştirip sonra "acaba çözülüyor mu" diye aramak yerine bu
/// yol seçildi: arama hem pahalı hem de çoğu denemede çözümsüz bulmaca
/// üretip atıyor.
MetroLinePuzzle generateMetroLinePuzzle({
  required int size,
  required int desiredTrains,
  required Random random,
  int lineColorCount = 6,
}) {
  assert(size >= metroLineMinSize && size <= metroLineMaxSize);

  final occupied = <Point<int>>{};
  final placed = <MetroLineTrain>[];
  var nextId = 1;

  bool inside(Point<int> p) =>
      p.x >= 0 && p.x < size && p.y >= 0 && p.y < size;

  for (var i = 0; i < desiredTrains; i++) {
    MetroLineTrain? train;

    // Her tren için sınırlı deneme: tahta doldukça uygun yer kalmayabilir,
    // o zaman bulmaca olduğu kadarıyla kalır (sonsuz döngü yok).
    for (var attempt = 0; attempt < 90 && train == null; attempt++) {
      final direction =
          MetroLineDirection.values[random.nextInt(
            MetroLineDirection.values.length,
          )];
      final head = Point<int>(random.nextInt(size), random.nextInt(size));
      if (occupied.contains(head)) continue;

      // Lokomotifin arkasındaki ilk vagon, çıkış yönünün tam tersinde
      // olmak zorunda: tren gittiği yöne baksın.
      //
      // Bu olmadan üretici başı rastgele bir yöne çeviriyordu ve trenlerin
      // **%62'sinin** başı çıkış yönünden başka yana bakıyordu. Ok gövdenin
      // son parçasına göre çizildiği için de çoğu zaman yanlış yönü
      // gösteriyor, gövdeye dik düştüğünde ise "ok yok" gibi okunuyordu.
      final step = direction.delta;
      final neck = Point<int>(head.x - step.x, head.y - step.y);
      if (!inside(neck) || occupied.contains(neck)) continue;

      // Koridor: başın önünden kenara kadar. Şu an tahtada duran trenler
      // (yani oyunda bu trenden sonra çıkacaklar) burayı kapatmamalı.
      final corridor = <Point<int>>{};
      var p = Point<int>(head.x + step.x, head.y + step.y);
      var corridorClear = true;
      while (inside(p)) {
        if (occupied.contains(p)) {
          corridorClear = false;
          break;
        }
        corridor.add(p);
        p = Point<int>(p.x + step.x, p.y + step.y);
      }
      if (!corridorClear) continue;

      // Gövdeyi baştan geriye doğru rastgele büyüt. Gövde kendi
      // koridoruna giremez: girseydi tren çıkarken kendi vagonunun
      // üstünden geçmek zorunda kalırdı.
      final body = <Point<int>>[head, neck];
      final taken = <Point<int>>{head, neck, ...corridor};
      final targetCars =
          metroLineMinCars +
          random.nextInt(metroLineMaxCars - metroLineMinCars + 1);

      while (body.length < targetCars) {
        final tail = body.last;
        final options = <Point<int>>[
          for (final d in MetroLineDirection.values)
            Point<int>(tail.x + d.delta.x, tail.y + d.delta.y),
        ]..removeWhere(
          (c) => !inside(c) || occupied.contains(c) || taken.contains(c),
        );
        if (options.isEmpty) break;
        final next = options[random.nextInt(options.length)];
        body.add(next);
        taken.add(next);
      }

      if (body.length < metroLineMinCars) continue;

      train = MetroLineTrain(
        id: nextId++,
        cells: List<Point<int>>.unmodifiable(body),
        direction: direction,
        lineIndex: random.nextInt(lineColorCount),
      );
    }

    if (train == null) break;
    placed.add(train);
    occupied.addAll(train.cells);
  }

  // Eklenen ilk tren en son çıkar: çözüm sırası, ekleme sırasının tersi.
  final solution = <int>[for (final t in placed.reversed) t.id];

  return MetroLinePuzzle(
    size: size,
    trains: List<MetroLineTrain>.unmodifiable(placed),
    solution: List<int>.unmodifiable(solution),
  );
}

/// Seviyeye göre tahta boyu ve tren sayısı.
///
/// **İki** seviyede bir tahta bir kenar büyür (önce üç seviyedeydi) ve
/// hücrelerin kabaca %55'i dolar (önce %50). Amaç istenen zorluk artışı:
/// daha çok kare, daha çok ve daha kısa tren — yani daha çok karar.
///
/// Üretici yer bulamazsa daha az trenle döner, yani bu sayılar bir üst
/// sınır.
@immutable
class MetroLineLevelPlan {
  const MetroLineLevelPlan({required this.size, required this.trains});

  factory MetroLineLevelPlan.forLevel(int level) {
    final size = (metroLineMinSize + (level - 1) ~/ 2).clamp(
      metroLineMinSize,
      metroLineMaxSize,
    );
    // Hücrelerin kabaca %55'i dolsun; ortalama tren 3 vagon.
    final capacity = (size * size * 0.55 / 3).round();
    final trains = (4 + level * 2).clamp(4, capacity);
    return MetroLineLevelPlan(size: size, trains: trains);
  }

  final int size;
  final int trains;
}
