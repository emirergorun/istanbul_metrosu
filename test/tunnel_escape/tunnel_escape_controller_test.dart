import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_hint_service.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_progress_controller.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/tunnel_escape_controller.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_level.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_session.dart';
import 'package:istanbul_metro_game/features/session/journey_status.dart';
import 'package:istanbul_metro_game/features/session/run_report.dart';

import '../helpers/metro_fixture.dart';

Journey shortJourney() => RouteService(
  MetroFixture.load(),
).estimate('m2_taksim', 'm2_levent').journey!;

/// Denetleyici testlerinin kendi küçük bölümleri: gönderilen veriden
/// bağımsız, sayıları elle bilinen tahtalar.
final List<EscapeLevel> testLevels = <EscapeLevel>[
  // 1: engel aşağı/yukarı, sonra kırmızı — en kısa 2.
  EscapeLevel.parse(
    number: 1,
    grid: const <String>[
      '......',
      '......',
      'RR..A.',
      '....A.',
      '......',
      '......',
    ],
    optimalMoves: 2,
    threeStarMoves: 2,
    twoStarMoves: 4,
  ),
  // 2: yatay B, dikey A, kırmızı — en kısa 3.
  EscapeLevel.parse(
    number: 2,
    grid: const <String>[
      '......',
      '....A.',
      'RR..A.',
      '....A.',
      '......',
      '...BB.',
    ],
    optimalMoves: 3,
    threeStarMoves: 3,
    twoStarMoves: 5,
  ),
];

class _Reports implements RunReporter {
  final List<RunReport> runs = <RunReport>[];

  @override
  void reportRun(RunReport report) => runs.add(report);

  @override
  void reportRunStarted() {}
}

TunnelEscapeController controllerFor({
  EscapeProgressController? progress,
  JourneySession? session,
}) {
  final controller = TunnelEscapeController(
    journey: shortJourney(),
    recordToBeat: 0,
    levelProgress: progress ?? EscapeProgressController(),
    levels: testLevels,
    hintSolver: solveHintImmediately,
    session: session,
  );
  addTearDown(controller.dispose);
  return controller..start();
}

/// Bölüm 1'i bitirmiş bir kayıt: bölüm 2 açık.
EscapeProgressController levelTwoOpen() =>
    EscapeProgressController()
      ..record(level: 1, moves: 2, stars: 3, perfect: false);

/// Bölüm 1'i en kısa yoldan bitirir: A aşağı, R tünele.
void solveLevelOne(TunnelEscapeController c) {
  expect(c.commitMove(1, 3), EscapeMoveOutcome.moved);
  expect(c.commitMove(0, 4), EscapeMoveOutcome.solved);
  c.finishExit();
}

void main() {
  group('Harita', () {
    test('oyun haritada başlar, bölüm 1 açılır, 2 kilitli', () {
      final c = controllerFor();
      expect(c.phase, EscapePhase.map);
      expect(c.nextLevelNumber, 1);
      expect(c.openLevel(2), isFalse);
      expect(c.openLevel(1), isTrue);
      expect(c.phase, EscapePhase.playing);
      expect(c.level!.number, 1);
      expect(c.moves, 0);
    });

    test('haritaya dönmek koşuyu bitirmez', () {
      final c = controllerFor()..openLevel(1);
      c.commitMove(1, 3);
      c.showMap();
      expect(c.phase, EscapePhase.map);
      expect(c.status, GameStatus.playing);
    });
  });

  group('Hamle sayımı', () {
    test('tek sürükleyiş tek hamle: metro kaç hücre giderse gitsin', () {
      final c = controllerFor()..openLevel(1);
      // R iki hücre sağa: tek hamle.
      expect(c.commitMove(0, 2), EscapeMoveOutcome.moved);
      expect(c.moves, 1);
      // A üç hücre yukarı değil, iki hücre aşağı: yine tek hamle.
      expect(c.commitMove(1, 4), EscapeMoveOutcome.moved);
      expect(c.moves, 2);
    });

    test('bırakıldığı yere dönen metro hamle sayılmaz', () {
      final c = controllerFor()..openLevel(1);
      expect(c.commitMove(1, 2), EscapeMoveOutcome.unchanged);
      expect(c.moves, 0);
      expect(c.canUndo, isFalse);
    });

    test('yasadışı hamle yok sayılır, tahta değişmez', () {
      final c = controllerFor()..openLevel(1);
      final before = c.board;
      // R, A'nın içinden tünele giremez.
      expect(c.commitMove(0, 4), EscapeMoveOutcome.ignored);
      expect(c.board, before);
      expect(c.moves, 0);
    });

    test('hamle durak bonusu hakkı verir', () {
      final c = controllerFor()..openLevel(1);
      expect(c.journeySession.hasStationProgress, isFalse);
      c.commitMove(1, 3);
      expect(c.journeySession.hasStationProgress, isTrue);
    });
  });

  group('Geri al ve baştan', () {
    test('geri almak tahtayı ve sayacı tam olarak geri getirir', () {
      final c = controllerFor(progress: levelTwoOpen())..openLevel(2);
      final start = c.board;
      c.commitMove(2, 1); // B sola
      final afterFirst = c.board;
      c.commitMove(1, 3); // A aşağı
      expect(c.moves, 2);

      expect(c.undo(), isTrue);
      expect(c.board, afterFirst);
      expect(c.moves, 1);
      expect(c.usedUndo, isTrue);

      expect(c.undo(), isTrue);
      expect(c.board, start);
      expect(c.moves, 0);
      expect(c.undo(), isFalse);
    });

    test('baştan başlatmak sayacı, geçmişi ve ipucunu sıfırlar', () async {
      final c = controllerFor(progress: levelTwoOpen())..openLevel(2);
      c.commitMove(2, 1);
      await c.requestHint();
      expect(c.hint, isNotNull);
      c.restartLevel();
      expect(c.board, testLevels[1].initialBoard);
      expect(c.moves, 0);
      expect(c.canUndo, isFalse);
      expect(c.hint, isNull);
      expect(c.usedHint, isFalse);
    });

    test('bitmiş bölümde geri alınamaz', () {
      final c = controllerFor()..openLevel(1);
      solveLevelOne(c);
      expect(c.canUndo, isFalse);
      expect(c.undo(), isFalse);
    });
  });

  group('İpucu', () {
    test('sıradaki faydalı hamleyi gösterir, bölümü çözmez', () async {
      final c = controllerFor(progress: levelTwoOpen())..openLevel(2);
      await c.requestHint();
      final hint = c.hint!;
      // Bölüm 2'de ilk faydalı hamle B'nin kayması.
      expect(c.level!.pieces[hint.piece].id, 'B');
      expect(c.moves, 0, reason: 'ipucu hamle yapmaz');
      expect(c.usedHint, isTrue);
    });

    test('hamle yapılınca ipucu kalkar', () async {
      final c = controllerFor(progress: levelTwoOpen())..openLevel(2);
      await c.requestHint();
      final hint = c.hint!;
      c.commitMove(hint.piece, hint.to);
      expect(c.hint, isNull);
    });

    test('ipucuyla bitirilen bölüm en fazla iki yıldız', () async {
      final c = controllerFor()..openLevel(1);
      await c.requestHint();
      final hint = c.hint!;
      c.commitMove(hint.piece, hint.to);
      await c.requestHint();
      final last = c.hint!;
      c.commitMove(last.piece, last.to);
      expect(c.completion!.moves, 2);
      expect(c.completion!.stars, 2);
      expect(c.completion!.usedHint, isTrue);
    });
  });

  group('Tamamlanma', () {
    test('kırmızı tünele girince bölüm biter, kayıt yazılır', () {
      final progress = EscapeProgressController();
      final c = controllerFor(progress: progress)..openLevel(1);
      c.commitMove(1, 3);
      expect(c.commitMove(0, 4), EscapeMoveOutcome.solved);
      expect(c.phase, EscapePhase.exiting);
      expect(c.acceptsInput, isFalse, reason: 'tünelde girdi kilitli');

      c.finishExit();
      expect(c.phase, EscapePhase.solved);
      final done = c.completion!;
      expect(done.moves, 2);
      expect(done.stars, 3);
      expect(done.isNewBest, isTrue);
      expect(done.hasNext, isTrue);
      expect(progress.isCompleted(1), isTrue);
      expect(progress.isUnlocked(2), isTrue);
      expect(c.levelsSolvedThisRun, 1);
      expect(c.starsThisRun, 3);
    });

    test('bölüm yolculuğa puan yazar', () {
      final c = controllerFor()..openLevel(1);
      solveLevelOne(c);
      expect(c.completion!.pointsAwarded, greaterThan(0));
      expect(c.score, c.completion!.pointsAwarded);
      expect(c.scoreThisGame, c.score);
    });

    test('sonraki durak bir sonraki bölümü hemen açar', () {
      final c = controllerFor()..openLevel(1);
      solveLevelOne(c);
      expect(c.openNext(), isTrue);
      expect(c.level!.number, 2);
      expect(c.phase, EscapePhase.playing);
      expect(c.moves, 0);
    });

    test('son bölümde sonraki durak yok', () {
      final progress = EscapeProgressController()
        ..record(level: 1, moves: 2, stars: 3, perfect: false);
      final c = controllerFor(progress: progress)..openLevel(2);
      c.commitMove(2, 1);
      c.commitMove(1, 3);
      expect(c.commitMove(0, 4), EscapeMoveOutcome.solved);
      c.finishExit();
      expect(c.completion!.hasNext, isFalse);
      expect(c.completion!.isFinale, isTrue);
      expect(c.openNext(), isFalse);
    });

    test('aynı yolculukta tekrar oynamak puan kasmaz', () {
      final c = controllerFor()..openLevel(1);
      solveLevelOne(c);
      final first = c.completion!.pointsAwarded;

      c.replay();
      solveLevelOne(c);
      final second = c.completion!.pointsAwarded;
      c.replay();
      solveLevelOne(c);
      final third = c.completion!.pointsAwarded;

      expect(first, greaterThan(0));
      expect(second, 0, reason: 'ilk bitiriş bu yolculukta zaten sayıldı');
      expect(third, 0);
    });

    test('oyundan çıkıp dönmek tekrar payını yenilemez', () {
      final session = JourneySession(journey: shortJourney());
      final progress = EscapeProgressController()
        ..record(level: 1, moves: 2, stars: 3, perfect: false);

      final first = controllerFor(progress: progress, session: session)
        ..openLevel(1);
      solveLevelOne(first);
      expect(first.completion!.pointsAwarded, greaterThan(0));
      first.leave();

      final second = controllerFor(progress: progress, session: session)
        ..openLevel(1);
      solveLevelOne(second);
      expect(second.completion!.pointsAwarded, 0);
    });

    test('yıldız artışı aynı yolculukta da farkı kazandırır', () {
      final progress = EscapeProgressController()
        ..record(level: 1, moves: 6, stars: 1, perfect: false);
      final c = controllerFor(progress: progress)..openLevel(1);
      solveLevelOne(c);
      expect(c.completion!.stars, 3);
      expect(c.completion!.pointsAwarded, greaterThan(0));
      expect(progress.recordOf(1)!.bestStars, 3);
    });
  });

  group('Koşu', () {
    test('bölüm bitirmeden çıkmak koşuyu yarıda bırakır', () {
      final reports = _Reports();
      final c = controllerFor()..reporter = reports;
      c.leave();
      expect(c.status, GameStatus.abandoned);
      expect(reports.runs, isEmpty);
    });

    test('en az bir bölüm bitince çıkış koşuyu bitmiş sayar', () {
      final reports = _Reports();
      final c = controllerFor()..reporter = reports;
      c.openLevel(1);
      solveLevelOne(c);
      c.leave();
      expect(c.status, GameStatus.gameOver);
      expect(reports.runs, hasLength(1));
      expect(reports.runs.single.gameId, TunnelEscapeController.id);
    });

    test('ortak yolculukta çıkış yolculuğu bitirmez', () {
      final session = JourneySession(journey: shortJourney())
        ..setStatus(GameStatus.playing);
      final c = controllerFor(session: session)..openLevel(1);
      solveLevelOne(c);
      c.leave();
      expect(session.status, isNot(GameStatus.gameOver));
      expect(session.score, greaterThan(0));
    });
  });
}
