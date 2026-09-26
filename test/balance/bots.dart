import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/crossing/application/crossing_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_line/application/metro_line_controller.dart';
import 'package:istanbul_metro_game/features/games/crossing/domain/crossing_state.dart';
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
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_hint_service.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_progress_controller.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/tunnel_escape_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/application/rail_lay_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_lay/domain/rail_lay_state.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/data/escape_levels.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_solver.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';
import 'package:istanbul_metro_game/features/session/journey_run.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';

import '../helpers/metro_fixture.dart';
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
      // Kenar bir tünel: tren karşı kenardan girer.
      final next = Point<int>(
        (head.x + delta.x) % trainSnakeColumns,
        (head.y + delta.y) % trainSnakeRows,
      );
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

/// Karşıdan Karşıya: boşluğu bekler, güvenliyse ileri adım atar.
///
/// Oyunun kendisi zaman baskısı içermiyor (kovalayan yok), yani beceri
/// tamamen **ne kadar hızlı karar verdiğinde**: acemi geniş bir güvenlik
/// payı ister ve çok bekler, usta dar boşluklardan geçer.
class CrossingBot extends GameBot {
  CrossingBot({required super.journey, required super.seed, super.skill});

  @override
  CrossingController create(JourneySession session, Random random) =>
      CrossingController(
        journey: journey,
        recordToBeat: 0,
        lines: MetroFixture.load().lines(),
        random: Random(seed),
        session: session,
      );

  @override
  void live(CrossingController controller, Random random) {
    const dt = 1 / 60;
    var reaction = 0.0;
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 200000 &&
        !expired(controller)) {
      reaction -= dt;
      if (reaction <= 0 && !controller.isHopping) {
        reaction = _reactionSeconds + random.nextDouble() * 0.05;
        final move = _decide(controller, random);
        if (move != null) controller.move(move);
      }
      controller.debugAdvance(dt);
    }
  }

  /// Kararlar arası süre: oyuncu ekrana bakıp sonra basıyor.
  ///
  /// Zıplama 0,14 saniye sürdüğüne göre bu aralık aynı zamanda oyunun
  /// pratikteki temposu.
  double get _reactionSeconds => _flaw(0.30, 0.09, skill) + 0.025;

  /// Bir hücrede güvenle durabilmek için gereken boşluk.
  ///
  /// Oyuncu hücreye varır (bir zıplama), sıradaki kararını verir (bir
  /// tepki süresi) ve oradan çıkar (bir zıplama daha). Bu üçü hesaba
  /// katılmazsa bot her ray satırında "vardım ve kaldım" diye eziliyordu
  /// (ölçüldü: yolculuk başına 32 can). Üstüne beceriye göre daralan bir
  /// pay: usta dar boşluklardan geçer, acemi en geniş boşluğu bekler.
  double get _dwellSeconds =>
      crossingHopSeconds * 2 + _reactionSeconds + _flaw(0.25, 0.03, skill);

  CrossingDirection? _decide(CrossingController controller, Random random) {
    // Ara sıra bakmadan atlar. Karar saniyede birkaç kez verildiği için
    // oran düşük tutuldu.
    if (random.nextDouble() < _flaw(0.006, 0.0002, skill)) {
      return CrossingDirection.forward;
    }

    final column = controller.column;
    final row = controller.row;
    final dwell = _dwellSeconds;

    // 1. İleri gidebiliyorsa git: oyunun tamamı bu.
    if (_clearSeconds(controller, row + 1, column, dwell) >= dwell) {
      return CrossingDirection.forward;
    }

    // 2. Boşluk hizada değilse ona doğru kay — ama kaydığı hücre de
    //    güvenli olmalı, yoksa trenin önüne kaçmış olur.
    final sideways = _towardsGap(controller, row + 1, column, dwell);
    if (sideways != null) {
      final candidate = column + sideways.delta.x;
      if (_clearSeconds(controller, row, candidate, dwell) >= dwell) {
        return sideways;
      }
    }

    // 3. Durduğu yer bir sonraki kararı verip çıkmaya yetiyorsa bekle.
    final stay = crossingHopSeconds * 2 + _reactionSeconds;
    if (_clearSeconds(controller, row, column, stay) >= stay) return null;

    // 4. Tren geliyor ve beklenecek yer yok: en uzun yaşatan yöne kaç.
    CrossingDirection? best;
    var bestClear = _clearSeconds(controller, row, column, dwell);
    for (final direction in CrossingDirection.values) {
      final delta = direction.delta;
      final clear = _clearSeconds(
        controller,
        row + delta.y,
        column + delta.x,
        dwell,
      );
      if (clear > bestClear) {
        bestClear = clear;
        best = direction;
      }
    }
    return best;
  }

  /// [row] satırının [column] sütunu kaç saniye boş kalıyor.
  ///
  /// [cap] tavanında durur: botun ufku dar, ondan ötesini hesaplamak hem
  /// gereksiz hem de gerçek oyuncunun yapmadığı bir şey.
  double _clearSeconds(
    CrossingController controller,
    int row,
    int column,
    double cap,
  ) {
    if (column < 0 || column >= crossingColumns) return -1;
    if (row < controller.backLimit) return -1;
    final target = controller.rowAt(row);
    if (target == null) return -1;
    if (!target.isTrack) return cap;

    final direction = target.toRight ? 1 : -1;
    for (var t = 0.0; t <= cap; t += 0.03) {
      final shift = target.speed * t * direction;
      for (final train in target.trains) {
        if (train.copyWith(x: train.x + shift).hits(column)) return t;
      }
    }
    return cap;
  }

  /// İleride açık bir sütun varsa o yöne bir adım.
  CrossingDirection? _towardsGap(
    CrossingController controller,
    int row,
    int column,
    double window,
  ) {
    for (var distance = 1; distance <= 3; distance++) {
      for (final direction in <CrossingDirection>[
        CrossingDirection.left,
        CrossingDirection.right,
      ]) {
        final candidate = column + direction.delta.x * distance;
        if (_clearSeconds(controller, row, candidate, window) >= window) {
          return direction;
        }
      }
    }
    return null;
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
      'Karşıdan Karşıya': (
        id: 'crossing',
        make: ({required journey, required seed, required skill}) =>
            CrossingBot(journey: journey, seed: seed, skill: skill),
      ),
      'Metro Hattı': (
        id: 'metro_line',
        make: ({required journey, required seed, required skill}) =>
            MetroLineBot(journey: journey, seed: seed, skill: skill),
      ),
      'Tünele Kaç': (
        id: 'tunnel_escape',
        make: ({required journey, required seed, required skill}) =>
            TunnelEscapeBot(journey: journey, seed: seed, skill: skill),
      ),
      'Ray Döşe': (
        id: 'rail_lay',
        make: ({required journey, required seed, required skill}) =>
            RailLayBot(journey: journey, seed: seed, skill: skill),
      ),
      'Metro Bilgi': (
        id: 'metro_quiz',
        make: ({required journey, required seed, required skill}) =>
            MetroQuizBot(journey: journey, seed: seed, skill: skill),
      ),
    };

/// Metro Hattı: önü açık bir tren arar, ara sıra yanlış trene dokunur.
///
/// Oyunun zorluğu tıkanmak değil (tahta kilitlenemez, bkz.
/// `metro_line_controller_test`), **görsel arama**: karışık tahtada önü
/// gerçekten açık olanı ayırt etmek. Bot bunu iki sayıyla modelliyor:
/// dokunuş başına düşünme süresi ve yanlış dokunma olasılığı.
class MetroLineBot extends GameBot {
  MetroLineBot({required super.journey, required super.seed, super.skill});

  @override
  MetroLineController create(JourneySession session, Random random) =>
      MetroLineController(
        journey: journey,
        recordToBeat: 0,
        random: Random(seed),
        session: session,
      );

  @override
  void live(MetroLineController controller, Random random) {
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 20000 &&
        !expired(controller)) {
      final trains = controller.trains;
      if (trains.isEmpty) break;

      // Yanlış dokunuş: acemi daha sık kapalı raya tren sokar.
      final mistake = random.nextDouble() < _flaw(0.16, 0.03, skill);
      final open = trains.where(controller.canExit).toList();
      final shut = trains.where((t) => !controller.canExit(t)).toList();

      final target = mistake && shut.isNotEmpty
          ? shut[random.nextInt(shut.length)]
          : (open.isNotEmpty
                ? open[random.nextInt(open.length)]
                : trains[random.nextInt(trains.length)]);
      controller.tap(target.id);

      // Arama süresi: tahta büyüdükçe uzuyor, usta daha çabuk buluyor.
      final think = _flaw(2.2, 1.1, skill) + controller.size * 0.06;
      if (controller.status == GameStatus.playing) {
        controller.debugAdvance(think);
      }
    }
  }
}

/// Tünele Kaç: bölümleri sırayla çözer, ara ara yanlış metroyu kaydırır.
///
/// **Oyuncu nereden başlıyor?** Bölümler sonlu; ilk yolculukta oyuncu
/// bölüm 1'den, otuzuncu yolculukta belki bölüm 30'dan başlıyor. Tohum
/// başlangıç bölümünü seçiyor (1-40): ölçüm, ilerlemenin farklı
/// noktalarındaki oyuncuların ortalaması.
///
/// Kusur modeli: her adımda [_flaw] olasılıkla en kısa çözüme götürmeyen
/// yasal bir hamle (yanlış metro, yanlış yön). Düşünme süresi bölüm başına
/// bir okuma payı ve hamle başına bir karar süresi; zor bölümde karar
/// süresi uzar.
/// Ray Döşe: açgözlü bir insan modeli.
///
/// Her hamlede en çok yeni kare döşeyen kayışı seçer; hiçbiri yeni kare
/// döşemiyorsa döşeyebileceği en yakın duruşa yürür. Bu strateji bazen
/// tek yönlü bir cebe girip sıkışıyor — gerçek oyuncu da öyle; o zaman
/// bölümü baştan alır ve süre kaybeder.
class RailLayBot extends GameBot {
  RailLayBot({required super.journey, required super.seed, super.skill});

  /// İlerleme kalıcı: gerçek oyuncu her yolculuğa farklı bir bölümden
  /// başlar. Tünele Kaç botuyla aynı dağıtım.
  late final int _startLevel = 1 + (seed * 7) % 40;

  @override
  RailLayController create(JourneySession session, Random random) =>
      RailLayController(
        journey: journey,
        recordToBeat: 0,
        startLevel: _startLevel,
        session: session,
      );

  @override
  void live(RailLayController controller, Random random) {
    const dt = 1 / 60;
    var readLevel = -1;
    var idleMoves = 0;
    var guard = 0;
    // Baştan alınan bölümde oyuncu artık yolu biliyor: ikinci denemede
    // bölümün bilinen çözümünü izler. Yoksa az hata yapan usta bot aynı
    // çıkmaza tekrar tekrar giriyor ve acemiden az puan alıyordu
    // (ölçüldü: usta 63, orta 77).
    List<RailLayDirection>? route;
    while (controller.status == GameStatus.playing &&
        guard++ < 400000 &&
        !expired(controller)) {
      if (controller.isSliding || controller.isCelebrating) {
        controller.debugAdvance(dt);
        continue;
      }
      // Yeni bölüm: tahtayı okuma süresi, bölüm büyüdükçe uzar.
      if (controller.levelNumber != readLevel) {
        readLevel = controller.levelNumber;
        idleMoves = 0;
        route = null;
        controller.debugAdvance(
          _flaw(3.0, 1.2, skill) +
              controller.openCount * _flaw(0.04, 0.015, skill),
        );
        continue;
      }
      // Sıkıştı (ya da uzun süredir hiçbir şey döşeyemiyor): baştan al.
      if (controller.isStuck || idleMoves >= 12) {
        controller.debugAdvance(_flaw(2.5, 0.8, skill));
        if (controller.status != GameStatus.playing) break;
        controller.restartLevel();
        idleMoves = 0;
        route = List<RailLayDirection>.of(controller.level.solution);
        continue;
      }

      controller.debugAdvance(
        _flaw(1.1, 0.45, skill) * (0.6 + random.nextDouble() * 0.8),
      );
      if (controller.status != GameStatus.playing) break;
      final before = controller.paintedCount;
      var planned = route;
      // Yolu bilen oyuncu da ara sıra şaşar: kusursuz ikinci deneme botu
      // gerçek oyuncudan hızlı gösterirdi. Şaşan oyuncu yolu kaybeder,
      // açgözlü oynamaya döner ve belki yine tuzağa düşer.
      if (planned != null &&
          planned.isNotEmpty &&
          random.nextDouble() < _flaw(0.12, 0.02, skill)) {
        route = planned = null;
      }
      controller.swipe(
        planned != null && planned.isNotEmpty
            ? planned.removeAt(0)
            : _choose(controller, random),
      );
      // Kayış bitene kadar zamanı akıt, sonra ilerleme var mı bak.
      var frames = 0;
      while (controller.isSliding && frames++ < 120) {
        controller.debugAdvance(dt);
      }
      idleMoves = controller.paintedCount > before ? 0 : idleMoves + 1;
    }
  }

  RailLayDirection _choose(RailLayController controller, Random random) {
    const directions = RailLayDirection.values;
    if (random.nextDouble() < _flaw(0.18, 0.03, skill)) {
      return directions[random.nextInt(directions.length)];
    }
    final level = controller.level;

    int gainOf(Point<int> from, RailLayDirection direction) {
      var gain = 0;
      for (final cell in level.slide(from, direction)) {
        if (controller.paintAt(cell) == 0) gain++;
      }
      return gain;
    }

    // 1. Buradan yeni kare döşeyen en iyi kayış.
    var best = <RailLayDirection>[];
    var bestGain = 0;
    for (final direction in directions) {
      final gain = gainOf(controller.position, direction);
      if (gain > bestGain) {
        bestGain = gain;
        best = <RailLayDirection>[direction];
      } else if (gain == bestGain && gain > 0) {
        best.add(direction);
      }
    }
    if (best.isNotEmpty) return best[random.nextInt(best.length)];

    // 2. Döşeyebileceği en yakın duruşa giden ilk adım (BFS).
    final firstStep = <Point<int>, RailLayDirection>{};
    final queue = <Point<int>>[controller.position];
    final seen = <Point<int>>{controller.position};
    while (queue.isNotEmpty) {
      final stop = queue.removeAt(0);
      for (final direction in directions) {
        final path = level.slide(stop, direction);
        if (path.isEmpty) continue;
        final next = path.last;
        if (!seen.add(next)) continue;
        firstStep[next] = firstStep[stop] ?? direction;
        for (final d in directions) {
          if (gainOf(next, d) > 0) return firstStep[next]!;
        }
        queue.add(next);
      }
    }
    return directions[random.nextInt(directions.length)];
  }
}

class TunnelEscapeBot extends GameBot {
  TunnelEscapeBot({required super.journey, required super.seed, super.skill});

  /// Bölüm başına durum uzayı — bütün bot koşuları paylaşır.
  static final Map<int, EscapeComponent> _components = <int, EscapeComponent>{};

  static EscapeComponent _componentOf(int number) =>
      _components.putIfAbsent(number, () {
        final level = EscapeLevels.byNumber(number)!;
        return EscapeSolver(level.layout).explore(level.start);
      });

  late final int _startLevel = 1 + (seed * 7) % 40;

  @override
  TunnelEscapeController create(JourneySession session, Random random) {
    final progress = EscapeProgressController();
    for (var level = 1; level < _startLevel; level++) {
      progress.record(level: level, moves: 99, stars: 2, perfect: false);
    }
    return TunnelEscapeController(
      journey: journey,
      recordToBeat: 0,
      levelProgress: progress,
      hintSolver: solveHintImmediately,
      session: session,
    );
  }

  @override
  void live(TunnelEscapeController controller, Random random) {
    var guard = 0;
    while (controller.status == GameStatus.playing &&
        guard++ < 400 &&
        !expired(controller)) {
      final number = controller.nextLevelNumber;
      if (!controller.openLevel(number)) break;
      final level = controller.level!;
      final component = _componentOf(number);
      final solver = EscapeSolver(level.layout);

      // Tahtayı okuma: engel sayısıyla uzar.
      controller.debugAdvance(
        _flaw(6, 3, skill) + level.pieces.length * _flaw(0.5, 0.25, skill),
      );

      var steps = 0;
      while (controller.status == GameStatus.playing &&
          controller.phase == EscapePhase.playing &&
          steps++ < 400) {
        final board = controller.board!;
        final key = board.key;
        final distance = component.distance[key]!;
        final options = <(int, int, int)>[];
        solver.expand(key, (int child) {
          for (var i = 0; i < board.positions.length; i++) {
            final to = level.layout.positionIn(child, i);
            if (to != board.positions[i]) {
              options.add((i, to, component.distance[child]!));
              break;
            }
          }
        });
        final good = options.where((o) => o.$3 < distance).toList();
        // Kusur zor bölümde artar: seçenek çok, bağımlılık uzun.
        final hardness = (level.optimalMoves / 25).clamp(0.2, 1.4);
        final mistake =
            random.nextDouble() < _flaw(0.32, 0.05, skill) * hardness;
        final pick = mistake || good.isEmpty
            ? options[random.nextInt(options.length)]
            : good[random.nextInt(good.length)];
        controller.commitMove(pick.$1, pick.$2);
        if (controller.status != GameStatus.playing) break;
        // Karar süresi: hamle başına, zorlukla uzar.
        controller.debugAdvance(
          _flaw(4.2, 2.2, skill) * (0.7 + hardness * 0.6),
        );
      }
      if (controller.phase == EscapePhase.exiting) {
        controller.finishExit();
        // Tünel animasyonu ve panel: "sonraki durak"a basana kadar.
        controller.debugAdvance(2.5);
      }
    }
  }
}

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
