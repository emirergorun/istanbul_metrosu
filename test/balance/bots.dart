import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/application/lane_runner_controller.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/domain/lane_runner_state.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/domain/metro_tile.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/metro_quiz_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/quiz_pool.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/application/rail_flight_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/domain/rail_flight_state.dart';
import 'package:istanbul_metro_game/features/games/train_snake/application/train_snake_controller.dart';
import 'package:istanbul_metro_game/features/games/train_snake/domain/train_snake_state.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';
import 'package:istanbul_metro_game/features/session/journey_run.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';

import '../helpers/trivia_fixture.dart';

/// Bir **yolculuğun** sonucu: bot, süre dolana kadar oynar.
class BotRun {
  const BotRun({
    required this.score,
    required this.seconds,
    required this.lives,
    required this.arrived,
  });

  final int score;
  final double seconds;

  /// Kaç kez baştan başladı — ölmek artık yolculuğu bitirmiyor.
  final int lives;
  final bool arrived;
}

/// Bir oyuncu modeli: yolculuk boyunca aynı oyunu oynar, yanınca
/// baştan başlar.
///
/// **Neden yolculuk boyunca?** Ölmek artık yolculuğu bitirmiyor; oyuncu
/// oyunu yeniden başlatıp kalan süreyi doldurabiliyor. Tek bir canı ölçmek
/// bu yüzden yanıltıcıydı: Ray Uçuşu'nda usta da acemi de kapı başına aynı
/// puanı alıyor, fark **kaç kez baştan başladığında** ortaya çıkıyor. Rota
/// rekorunu belirleyen de bu: yolculuk başına toplam puan.
///
/// Botlar kasıtlı olarak kusurlu. [skill] 0 (acemi) ile 1 (usta) arasında
/// her botun kendi kusur düğmesini sürer: rastgele hamle oranı, kaçırılan
/// kanat, yanlış cevap… Ölçekler [midSkill] ile ayarlanır; acemi/usta
/// koşusu yalnızca "beceri hâlâ puana yansıyor mu" sorusunu cevaplar.
abstract class GameBot {
  GameBot({
    required this.journey,
    required this.seed,
    this.skill = GameBot.midSkill,
  });

  final Journey journey;
  final int seed;

  /// 0 acemi, 1 usta.
  final double skill;

  /// Ölçeklerin ayarlandığı seviye — "orta seviye oyuncu".
  static const double midSkill = 0.5;
  static const double lowSkill = 0.15;
  static const double highSkill = 0.9;

  /// Bu oyunun bırakılacağı an (yolculuk saati, saniye).
  ///
  /// Gerçek oyuncu bir oyunu yolculuğun ortasında bırakıp başkasına
  /// geçebiliyor; karışık yolculuğu ölçmek için bot da bırakabilmeli.
  double deadline = double.infinity;

  /// Oyunu bırakma vakti geldi mi?
  bool expired(JourneyGameController controller) =>
      controller.elapsedSeconds >= deadline;

  /// Yanmakla yeniden başlamak arasında geçen süre.
  ///
  /// Sonuç paneli okunur, "tekrar oyna"ya basılır; tren bu sırada
  /// beklemez. Ölmenin gerçek bedeli budur.
  static double get restartSeconds => restartSecondsOverride;

  /// Oyunu **yolculuk oturumuna bağlayarak** kurar.
  JourneyGameController create(JourneySession session, Random random);

  /// Bir canı sonuna kadar oynar: oyun bitene ya da varışa kadar.
  void live(covariant JourneyGameController controller, Random random);

  BotRun play() {
    final random = Random(seed);
    final session = JourneySession(journey: journey);
    final controller = create(session, random)..start();

    var lives = 0;
    while (lives < 400) {
      if (session.elapsedSeconds >= deadline) break;
      live(controller, random);
      lives++;
      if (controller.status == GameStatus.arrived) break;
      if (session.remainingSeconds <= 0) break;

      // Panel okunur, düğmeye basılır: tren bu sırada yol alır.
      session.addElapsed(restartSeconds);
      if (session.settle()) break;
      controller.restart();
      if (controller.status != GameStatus.playing) break;
    }

    final run = BotRun(
      score: session.score,
      seconds: session.elapsedSeconds,
      lives: lives,
      arrived: session.remainingSeconds <= 0,
    );
    controller.dispose();
    return run;
  }
}

/// Sonuç panelinde geçen süre — ölçümde değiştirilebilir.
double restartSecondsOverride = 3;

/// Kusur oranını beceriye göre daraltır; 0'ın altına inmez.
double _flaw(double atZero, double atOne, double skill) {
  final value = atZero + (atOne - atZero) * skill;
  return value < 0 ? 0 : value;
}

/// Blok Metro: hattı tamamlayan hamleyi seçer, ara ara rastgele oynar.
/// Hamle aralığı 7 sn (dakikada ~8,5 parça) — mevcut denge raporuyla aynı.
class BlocksBot extends GameBot {
  BlocksBot({required super.journey, required super.seed, super.skill});

  @override
  GameController create(JourneySession session, Random random) =>
      GameController(journey: journey, random: Random(seed), session: session);

  @override
  void live(GameController controller, Random random) {
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 5000 &&
        !expired(controller)) {
      if (controller.awaitingUndo) {
        controller.acceptGameOver();
        return;
      }
      final moves = <List<int>>[];
      for (var i = 0; i < controller.tray.length; i++) {
        final piece = controller.tray[i];
        if (piece == null) continue;
        for (var r = 0; r < 8; r++) {
          for (var c = 0; c < 8; c++) {
            if (canPlace(controller.board, piece, r, c)) {
              moves.add(<int>[i, r, c]);
            }
          }
        }
      }
      if (moves.isEmpty) return;

      List<int> chosen;
      if (random.nextDouble() < _flaw(0.45, -0.05, skill)) {
        chosen = moves[random.nextInt(moves.length)];
      } else {
        chosen = moves.first;
        var best = -1;
        for (final move in moves) {
          final piece = controller.tray[move[0]]!;
          final board = placePiece(controller.board, piece, move[1], move[2]);
          final lines =
              findCompletedRows(board).length +
              findCompletedColumns(board).length;
          final score = lines * 100 + move[1] * 2 + piece.size;
          if (score > best) {
            best = score;
            chosen = move;
          }
        }
      }
      controller.place(chosen[0], chosen[1], chosen[2]);
      if (controller.status == GameStatus.playing) controller.debugAdvance(7);
    }
  }
}

/// Hat Birleştir: sola/yukarı köşe stratejisi, ara ara rastgele yön.
class MetroMergeBot extends GameBot {
  MetroMergeBot({required super.journey, required super.seed, super.skill});

  static const List<MetroMoveDirection> _order = <MetroMoveDirection>[
    MetroMoveDirection.left,
    MetroMoveDirection.up,
    MetroMoveDirection.right,
    MetroMoveDirection.down,
  ];

  @override
  MetroMergeController create(JourneySession session, Random random) =>
      MetroMergeController(
        journey: journey,
        recordToBeat: 0,
        random: Random(seed),
        session: session,
      );

  @override
  void live(MetroMergeController controller, Random random) {
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 20000 &&
        !expired(controller)) {
      final directions = random.nextDouble() < _flaw(0.35, -0.02, skill)
          ? (List<MetroMoveDirection>.of(_order)..shuffle(random))
          : _order;
      for (final direction in directions) {
        if (controller.move(direction).accepted) break;
      }
      // Hamle temposu: dakikada ~30 kaydırma.
      if (controller.status == GameStatus.playing) controller.debugAdvance(2);
    }
  }
}

/// Ray Uçuşu: boşluğun ortasını hedefler, ara ara kanat çırpmayı kaçırır.
class RailFlightBot extends GameBot {
  RailFlightBot({required super.journey, required super.seed, super.skill});

  @override
  RailFlightController create(JourneySession session, Random random) =>
      RailFlightController(
        journey: journey,
        recordToBeat: 0,
        random: Random(seed),
        session: session,
      );

  @override
  void live(RailFlightController controller, Random random) {
    const dt = 1 / 60;
    var guard = 0;
    // Dalgınlık: bir kanadı atlamak hiçbir şey değiştirmiyordu (bot bir
    // sonraki karede yeniden deniyor). Gerçek hata **süreklidir**: oyuncu
    // bir an geç kalır ve tren o sırada düşer. Kusur bu yüzden saniyelik
    // bir donma olarak modellendi.
    var lapse = 0.0;
    while (controller.status == GameStatus.playing &&
        guard++ < 200000 &&
        !expired(controller)) {
      lapse -= dt;
      if (lapse <= 0 && random.nextDouble() < _flaw(0.6, -0.05, skill) * dt) {
        lapse = 0.15 + random.nextDouble() * 0.2;
      }
      RailObstacle? next;
      for (final obstacle in controller.obstacles) {
        // Kapı, trenin **arkası** da çıkana kadar geçilmiş sayılmaz. Sınırı
        // trenin merkezine koyan ilk taslak, kapıyı yarılamışken bir
        // sonraki kapıya nişan alıp kendini duvara sürüyordu: ölümlerin
        // çoğu buradan geliyordu (dörtte üçü, ölçüldü).
        if (obstacle.x + railFlightObstacleWidth <
            railFlightTrainX - railFlightTrainRadius) {
          continue;
        }
        if (next == null || obstacle.x < next.x) next = obstacle;
      }
      final target = next?.gapCenter ?? 0.5;
      final falling = controller.velocity > 0;
      if (controller.trainY > target - 0.02 && falling && lapse <= 0) {
        controller.flap();
      }
      controller.debugAdvance(dt);
    }
  }
}

/// Hat Düşür: aynı seviyeden topu hedefler, ara ara rastgele bırakır;
/// iki bırakış arasında insan temposu kadar (~1 sn) bekler.
class MergeDropBot extends GameBot {
  MergeDropBot({required super.journey, required super.seed, super.skill});

  @override
  MergeDropController create(JourneySession session, Random random) =>
      MergeDropController(
        journey: journey,
        recordToBeat: 0,
        random: Random(seed),
        session: session,
      );

  @override
  void live(MergeDropController controller, Random random) {
    const dt = 1 / 60;
    var wait = 0.0;
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 200000 &&
        !expired(controller)) {
      wait -= dt;
      // Oyunun kendi bekleme süresi 0,32 sn; insan nişan alıp bırakırken
      // saniyede üç top düşüremiyor.
      if (wait <= 0 && controller.canDrop) {
        wait = 0.7 + random.nextDouble() * 0.5;
        final same = controller.balls
            .where((b) => b.level == controller.currentLevel && b.settled)
            .toList();
        final aim =
            same.isEmpty || random.nextDouble() < _flaw(0.55, 0.11, skill)
            ? random.nextDouble()
            : same[random.nextInt(same.length)].x;
        controller
          ..moveAim(aim)
          ..drop();
      }
      controller.debugAdvance(dt);
    }
  }
}

/// Ray Değiştir: en ferah raya kaçar, ara ara yanlış rayı seçer.
///
/// İlk taslak yalnızca "kendi rayındaki engelden" kaçıyordu ve dokuz
/// saniyede ölüyordu; oyunun puanı hayatta kaldıkça hızlandığı için o ölçüm
/// oyunu olduğundan ucuz gösteriyordu. Bu sürüm insanın yaptığını yapar:
/// ileriye bakıp en uzun süre boş kalacak rayı seçer.
class LaneRunnerBot extends GameBot {
  LaneRunnerBot({required super.journey, required super.seed, super.skill});

  @override
  LaneRunnerController create(JourneySession session, Random random) =>
      LaneRunnerController(
        journey: journey,
        recordToBeat: 0,
        random: Random(seed),
        session: session,
      );

  @override
  void live(LaneRunnerController controller, Random random) {
    const dt = 1 / 60;
    var reaction = 0.0;
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 200000 &&
        !expired(controller)) {
      reaction -= dt;
      if (reaction <= 0) {
        // Orta seviye oyuncu ekranı sürekli izler ama her kareye yetişmez.
        // Gecikme 0,10 sn'yi geçtiğinde oyun bir uçurumdan düşüyor
        // (ölçüldü: 0,06 sn'de 150 sn yaşıyor, 0,10 sn'de 19 sn); bu yüzden
        // kusurun ağırlığı gecikmeye değil, seçime kondu.
        reaction = _flaw(0.085, 0.04, skill) + random.nextDouble() * 0.02;
        final best = _safestLane(controller, random);
        if (best < controller.trainLane) {
          controller.moveLeft();
        } else if (best > controller.trainLane) {
          controller.moveRight();
        }
      }
      controller.debugAdvance(dt);
    }
  }

  /// Önünde en uzun boşluk olan ray; eşitlikte bulunduğu ray kazanır.
  int _safestLane(LaneRunnerController controller, Random random) {
    // Saniyede ~12 karar veriyor; kusur oranı buna göre seyrek olmalı.
    if (random.nextDouble() < _flaw(0.009, -0.001, skill)) {
      return random.nextInt(laneRunnerLaneCount);
    }

    const horizon = 0.75;
    var best = controller.trainLane;
    var bestClearance = -10.0;
    for (var lane = 0; lane < laneRunnerLaneCount; lane++) {
      var clearance = horizon;
      for (final obstacle in controller.obstacles) {
        if (obstacle.lane != lane) continue;
        // Treni çoktan geçmiş engel tehdit değil.
        if (obstacle.y > laneRunnerTrainY + 0.08) continue;
        final gap = laneRunnerTrainY - obstacle.y;
        if (gap < clearance) clearance = gap;
      }
      // Uzağa geçmek zaman alır; yakın ray küçük bir avantaj alır.
      clearance -= (lane - controller.trainLane).abs() * 0.04;
      if (lane == controller.trainLane) clearance += 0.02;
      if (clearance > bestClearance) {
        bestClearance = clearance;
        best = lane;
      }
    }
    return best;
  }
}

/// Yolcu Topla: yolcuya gider ama duvara ve kendi gövdesine bakar.
class TrainSnakeBot extends GameBot {
  TrainSnakeBot({required super.journey, required super.seed, super.skill});

  @override
  TrainSnakeController create(JourneySession session, Random random) =>
      TrainSnakeController(
        journey: journey,
        recordToBeat: 0,
        random: Random(seed),
        session: session,
      );

  @override
  void live(TrainSnakeController controller, Random random) {
    const dt = 1 / 60;
    var guard = 0;
    Point<int>? lastHead;
    while (controller.status == GameStatus.playing &&
        guard++ < 200000 &&
        !expired(controller)) {
      final head = controller.body.first;
      // Karar adım başına bir kez: her karede zar atmak yönü titretirdi.
      if (head != lastHead) {
        lastHead = head;
        final choice = _chooseDirection(controller, random);
        if (choice != null) controller.turn(choice);
      }
      controller.debugAdvance(dt);
    }
  }

  SnakeDirection? _chooseDirection(
    TrainSnakeController controller,
    Random random,
  ) {
    final head = controller.body.first;
    final body = controller.body;
    final passenger = controller.passenger;

    bool safe(SnakeDirection direction) {
      final delta = direction.delta;
      final next = Point<int>(head.x + delta.x, head.y + delta.y);
      if (next.x < 0 || next.x >= trainSnakeColumns) return false;
      if (next.y < 0 || next.y >= trainSnakeRows) return false;
      // Kuyruğun son vagonu bu adımda boşalacak (yolcuya girmiyorsak).
      final blocking = next == passenger
          ? body
          : body.sublist(0, body.length - 1);
      return !blocking.contains(next);
    }

    final wanted = <SnakeDirection>[
      if (passenger.x > head.x) SnakeDirection.right,
      if (passenger.x < head.x) SnakeDirection.left,
      if (passenger.y > head.y) SnakeDirection.down,
      if (passenger.y < head.y) SnakeDirection.up,
    ];
    // Aceleci an: yolcuya değil boş tarafa döner.
    if (random.nextDouble() < _flaw(0.22, -0.02, skill)) wanted.clear();

    for (final direction in wanted) {
      if (safe(direction)) return direction;
    }
    final fallback = <SnakeDirection>[...SnakeDirection.values]
      ..shuffle(random);
    for (final direction in fallback) {
      if (safe(direction)) return direction;
    }
    return null;
  }
}

/// Metro Bilgi: becerisi kadar doğru bilir ve o kadar erken cevaplar.
class MetroQuizBot extends GameBot {
  MetroQuizBot({required super.journey, required super.seed, super.skill});

  @override
  MetroQuizController create(JourneySession session, Random random) =>
      MetroQuizController(
        journey: journey,
        recordToBeat: 0,
        pool: QuizPool(
          repository: TriviaFixture.repository(),
          random: Random(seed),
        ),
        session: session,
      );

  @override
  void live(MetroQuizController controller, Random random) {
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 20000 &&
        !expired(controller)) {
      if (controller.phase == QuizPhase.answering) {
        // Düşünme süresi: usta erken, acemi son saniyede cevaplar.
        controller.debugAdvance(
          controller.questionDuration * _flaw(0.8, 0.3, skill),
        );
        if (controller.status != GameStatus.playing) break;
        final correct = controller.question.answerIndex;
        final answer = random.nextDouble() < _flaw(0.45, 0.95, skill)
            ? correct
            : (correct + 1 + random.nextInt(3)) % 4;
        controller.answer(answer);
      }
      // Doğru şık ekranda kalırken tren yol alıyor; ölçüm bunu atlarsa
      // oyunu olduğundan hızlı gösterir.
      final reveal = controller.revealSeconds;
      controller.debugAdvance(reveal);
      if (controller.status != GameStatus.playing) break;
      controller.debugAdvanceReveal();
    }
  }
}

/// Bir oyunun bot fabrikası.
typedef BotFactory =
    GameBot Function({
      required Journey journey,
      required int seed,
      required double skill,
    });

/// Rapor ve parite testinin ortak oyun listesi.
///
/// [id] `GameScoreProfiles` anahtarıyla aynı olmalı; parite testi ölçekleri
/// bu eşleşmeden buluyor.
final Map<String, ({String id, BotFactory make})> botFactories =
    <String, ({String id, BotFactory make})>{
      'Blok Metro': (
        id: 'blocks',
        make: ({required journey, required seed, required skill}) =>
            BlocksBot(journey: journey, seed: seed, skill: skill),
      ),
      'Hat Birleştir': (
        id: 'metro_merge',
        make: ({required journey, required seed, required skill}) =>
            MetroMergeBot(journey: journey, seed: seed, skill: skill),
      ),
      'Ray Uçuşu': (
        id: 'rail_flight',
        make: ({required journey, required seed, required skill}) =>
            RailFlightBot(journey: journey, seed: seed, skill: skill),
      ),
      'Hat Düşür': (
        id: 'merge_drop',
        make: ({required journey, required seed, required skill}) =>
            MergeDropBot(journey: journey, seed: seed, skill: skill),
      ),
      'Ray Değiştir': (
        id: 'lane_runner',
        make: ({required journey, required seed, required skill}) =>
            LaneRunnerBot(journey: journey, seed: seed, skill: skill),
      ),
      'Yolcu Topla': (
        id: 'train_snake',
        make: ({required journey, required seed, required skill}) =>
            TrainSnakeBot(journey: journey, seed: seed, skill: skill),
      ),
      'Metro Bilgi': (
        id: 'metro_quiz',
        make: ({required journey, required seed, required skill}) =>
            MetroQuizBot(journey: journey, seed: seed, skill: skill),
      ),
    };

/// Bir seviyedeki koşuların özeti.
@immutable
class BotSample {
  const BotSample({
    required this.median,
    required this.p10,
    required this.p90,
    required this.medianLives,
  });

  /// Medyan puan/dk (yolculuk süresine göre).
  final double median;
  final double p10;
  final double p90;

  /// Yolculuk başına medyan can sayısı.
  final double medianLives;
}

/// Bir oyunu [runs] tohumla bir yolculuk boyu oynatır.
BotSample measure(
  ({String id, BotFactory make}) bot, {
  required Journey journey,
  required double skill,
  int runs = 25,
}) {
  final rates = <double>[];
  final lives = <double>[];
  for (var seed = 0; seed < runs; seed++) {
    final run = bot.make(journey: journey, seed: seed, skill: skill).play();
    if (run.seconds < 5) continue;
    rates.add(run.score / (run.seconds / 60));
    lives.add(run.lives.toDouble());
  }
  if (rates.isEmpty) {
    return const BotSample(median: 0, p10: 0, p90: 0, medianLives: 0);
  }
  rates.sort();
  lives.sort();
  double at(List<double> xs, double q) =>
      xs[(xs.length * q).clamp(0, xs.length - 1).floor()];
  return BotSample(
    median: at(rates, 0.5),
    p10: at(rates, 0.1),
    p90: at(rates, 0.9),
    medianLives: at(lives, 0.5),
  );
}

/// Var olan bir yolculuğa, [untilElapsed] saniyesine kadar bir oyunu oynatır.
///
/// Gerçek oynanışın karşılığı: oyuncu bir oyunu bir süre oynar, yanarsa
/// baştan başlar, sonra başka oyuna geçer. Yolculuk ikisinin de üstünde.
void playInto(
  JourneySession session,
  ({String id, BotFactory make}) bot, {
  required Journey journey,
  required int seed,
  required double untilElapsed,
}) {
  final random = Random(seed);
  final model = bot.make(journey: journey, seed: seed, skill: GameBot.midSkill)
    ..deadline = untilElapsed;
  var guard = 0;
  while (session.elapsedSeconds < untilElapsed && guard++ < 400) {
    final controller = model.create(session, random)..start();
    model.live(controller, random);
    controller.dispose();
    if (session.remainingSeconds <= 0) break;
    session.addElapsed(GameBot.restartSeconds);
    if (session.settle()) break;
  }
}
