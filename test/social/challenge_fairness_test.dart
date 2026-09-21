import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/domain/metro_tile.dart';
import 'package:istanbul_metro_game/features/games/train_snake/application/train_snake_controller.dart';
import 'package:istanbul_metro_game/features/journey/models/journey.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/social/application/challenge_session.dart';
import 'package:istanbul_metro_game/features/social/domain/challenge.dart';

import '../helpers/metro_fixture.dart';

/// Adalet: **aynı tohum, aynı başlangıç**.
///
/// Meydan okumanın sözü "aynı yolculuk, aynı oyun, aynı koşullar". Rota ve
/// süre karekodta taşınıyor; rastgeleliği eşitleyen şey tohum. Burada
/// tohumun gerçekten eşitlediği gösteriliyor.
///
/// Fizik tabanlı iki oyun (Ray Uçuşu, Ray Değiştir) bilinçli olarak dışarıda:
/// ikisi de gerçek zamanlı kare süresine bağlı ve iki cihazın kare
/// zamanlaması birebir aynı olmuyor. Tohumları yine de veriliyor — engel
/// dizisi aynı geliyor — ama "birebir aynı fizik" iddiası test edilebilir
/// değil, o yüzden edilmiyor.
void main() {
  final metro = MetroFixture.load();
  final routes = RouteService(metro);
  Journey journey() => routes.estimate('m2_taksim', 'm2_levent').journey!;

  Challenge challenge({int seed = 4242}) => Challenge(
    id: 'abc123',
    gameId: 'metro_merge',
    lineId: 'M2',
    originId: 'taksim',
    destinationId: 'levent',
    estimatedSeconds: 600,
    targetScore: 1000,
    seed: seed,
    creatorCode: 'ABCD1234',
    creatorName: 'Berke',
    createdOnEpochDay: 20719,
  );

  group('oturum tohumu', () {
    test('rota ve oyun tutarsa tohum veriliyor', () {
      final session = ChallengeSession()
        ..begin(challenge(), journey());
      addTearDown(session.dispose);

      expect(session.randomFor('metro_merge', journey()), isNotNull);
      expect(session.targetFor('metro_merge', journey()), 1000);
    });

    test('başka oyun tohum almıyor', () {
      final session = ChallengeSession()..begin(challenge(), journey());
      addTearDown(session.dispose);

      // Meydan okuma Hat Birleştir'e ait; oyuncu Blok Metro açarsa o koşu
      // Serbest Oyun'dur ve tohumsuz başlar.
      expect(session.randomFor('blocks', journey()), isNull);
      expect(session.targetFor('blocks', journey()), isNull);
    });

    test('başka rota tohum almıyor', () {
      final session = ChallengeSession()..begin(challenge(), journey());
      addTearDown(session.dispose);

      final other = routes.estimate('m2_taksim', 'm2_sishane').journey!;
      expect(session.randomFor('metro_merge', other), isNull);
    });

    test('oturum bitince tohum kesiliyor', () {
      final session = ChallengeSession()..begin(challenge(), journey());
      addTearDown(session.dispose);

      session.end();
      // **Sızıntı yok**: sonraki Serbest Oyun koşusu tohumsuz başlar.
      expect(session.isActive, isFalse);
      expect(session.randomFor('metro_merge', journey()), isNull);
    });

    test('hiç başlamamış oturum tohum vermez', () {
      final session = ChallengeSession();
      addTearDown(session.dispose);
      expect(session.randomFor('metro_merge', journey()), isNull);
    });
  });

  group('aynı tohum aynı başlangıç', () {
    test('Hat Birleştir: tahta birebir aynı', () {
      List<List<int?>> gridOf(int seed) {
        final session = ChallengeSession()
          ..begin(challenge(seed: seed), journey());
        final controller = MetroMergeController(
          journey: journey(),
          recordToBeat: 0,
          random: session.randomFor('metro_merge', journey()),
        )..start();
        final grid = <List<int?>>[
          for (final row in controller.grid)
            <int?>[for (final MetroTile? tile in row) tile?.rank],
        ];
        controller.dispose();
        session.dispose();
        return grid;
      }

      expect(gridOf(4242), gridOf(4242));
      // Farklı tohum farklı tahta vermeli, yoksa tohumun bir anlamı yok.
      expect(gridOf(4242), isNot(gridOf(777)));
    });

    test('Yolcu Topla: ilk yolcu aynı yerde', () {
      ({int x, int y}) passengerOf(int seed) {
        final session = ChallengeSession()
          ..begin(challenge(seed: seed), journey());
        final controller = TrainSnakeController(
          journey: journey(),
          recordToBeat: 0,
          random: session.randomFor('metro_merge', journey()),
        )..start();
        final point = (x: controller.passenger.x, y: controller.passenger.y);
        controller.dispose();
        session.dispose();
        return point;
      }

      expect(passengerOf(4242), passengerOf(4242));
    });

    test('Hat Düşür: ilk rozet aynı', () {
      int levelOf(int seed) {
        final session = ChallengeSession()
          ..begin(challenge(seed: seed), journey());
        final controller = MergeDropController(
          journey: journey(),
          recordToBeat: 0,
          random: session.randomFor('metro_merge', journey()),
        )..start();
        final level = controller.currentLevel;
        controller.dispose();
        session.dispose();
        return level;
      }

      expect(levelOf(4242), levelOf(4242));
    });
  });

  test('Serbest Oyun rastgeleliği değişmedi', () {
    // Tohum verilmeyen iki koşu **farklı** tahta vermeli. Meydan okuma
    // tohumu normal oyuna sızsaydı burada eşitlik çıkardı.
    List<List<int?>> freePlayGrid() {
      final controller = MetroMergeController(
        journey: journey(),
        recordToBeat: 0,
      )..start();
      final grid = <List<int?>>[
        for (final row in controller.grid)
          <int?>[for (final MetroTile? tile in row) tile?.rank],
      ];
      controller.dispose();
      return grid;
    }

    // İki karo rastgele yerleşiyor; ard arda yüz koşuda hepsinin aynı
    // çıkması pratikte imkânsız.
    final grids = <String>{
      for (var i = 0; i < 20; i++) freePlayGrid().toString(),
    };
    expect(grids.length, greaterThan(1));
  });
}
