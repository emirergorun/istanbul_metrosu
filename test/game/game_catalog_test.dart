import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/catalog/game_cover_art.dart';
import 'package:istanbul_metro_game/features/games/lane_runner/application/lane_runner_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/application/metro_quiz_controller.dart';
import 'package:istanbul_metro_game/features/games/rail_flight/application/rail_flight_controller.dart';
import 'package:istanbul_metro_game/features/games/train_snake/application/train_snake_controller.dart';
import 'package:istanbul_metro_game/features/games/catalog/mini_game.dart';

/// Katalog **tek kaynak**: galeri kartı da, tanıtım ekranı da metnini ve
/// kapağını buradan okuyor. İkisi ayrı listelerden beslenseydi bir oyunun
/// adı iki ekranda farklı olabilirdi ve kimse fark etmezdi.
void main() {
  group('Oyun kataloğu', () {
    test('kimlikler benzersiz', () {
      final ids = MiniGames.all.map((MiniGame g) => g.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('katalog kimlikleri controller kimlikleriyle birebir', () {
      // Katalog kimliği puanın hangi oyunun hanesine yazıldığını, günlük
      // görevin hangi oyunu istediğini ve kaydın hangi oyuna ait olduğunu
      // belirliyor. Controller'daki kimlikten sapsaydı oyun oynanır,
      // puan başka bir haneye yazılır ve kimse fark etmezdi.
      final controllerIds = <String>{
        GameController.id,
        MetroMergeController.id,
        RailFlightController.id,
        MergeDropController.id,
        MetroQuizController.id,
        LaneRunnerController.id,
        TrainSnakeController.id,
      };
      final playableIds = MiniGames.playable.map((MiniGame g) => g.id).toSet();
      expect(playableIds, controllerIds);
    });

    test('adlar benzersiz', () {
      final names = MiniGames.all.map((MiniGame g) => g.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('her oyunun adı, tanımı ve amacı dolu', () {
      for (final game in MiniGames.all) {
        expect(game.name, isNotEmpty, reason: game.id);
        expect(game.description, isNotEmpty, reason: game.id);
        expect(game.objective, isNotEmpty, reason: game.id);
      }
    });

    test('her oyunun bir kapak sahnesi var', () {
      for (final game in MiniGames.all) {
        // Raster kapak henüz üretilmedi; sahne çizimi her oyunda tanımlı
        // olmak zorunda, yoksa galeri boş kart çizerdi.
        expect(game.coverScene, isNotNull, reason: game.id);
      }
    });

    test('oynanabilir oyunlar kilit sahnesi kullanmaz', () {
      for (final game in MiniGames.playable) {
        expect(
          game.coverScene,
          isNot(GameCoverScene.locked),
          reason: '${game.id} açık ama kapağı kilit sahnesi',
        );
      }
    });

    test('her oynanabilir oyunun kapak sahnesi kendine ait', () {
      final arts = MiniGames.playable
          .map((MiniGame g) => g.coverScene)
          .toList();
      expect(
        arts.toSet().length,
        arts.length,
        reason: 'iki oyun aynı kapak sahnesini paylaşıyor',
      );
    });

    test('amaç metinleri oyuna özgü', () {
      // "En yüksek skoru yap" yedi oyunun hiçbirini anlatmaz; aynı cümlenin
      // iki oyunda tekrarlanması o tuzağa düşüldüğünün işareti.
      final objectives = MiniGames.playable
          .map((MiniGame g) => g.objective)
          .toList();
      expect(objectives.toSet().length, objectives.length);
    });

    test('tanımlar tek cümlelik kalıyor', () {
      for (final game in MiniGames.playable) {
        expect(
          game.description.length,
          lessThanOrEqualTo(120),
          reason: '${game.id} tanımı paragrafa dönüşmüş',
        );
      }
    });

    test('nasıl oynanır en fazla üç adım', () {
      for (final game in MiniGames.all) {
        expect(game.howToPlay.length, lessThanOrEqualTo(3), reason: game.id);
        expect(game.hasHowToPlay, game.howToPlay.isNotEmpty);
      }
    });

    test('yardım yalnız kontrolü açıklama gerektiren oyunlarda', () {
      // Sürükle-bırak ve şıkka dokunma kendini anlatıyor; dokunarak
      // yükselen tren, üç ray ve dört yön tuşu anlatmıyor.
      final withHelp = MiniGames.playable
          .where((MiniGame g) => g.hasHowToPlay)
          .map((MiniGame g) => g.id)
          .toSet();
      expect(withHelp, <String>{'rail_flight', 'lane_runner', 'train_snake'});
    });

    test('kimlikten oyuna çözüm çalışır', () {
      for (final game in MiniGames.all) {
        expect(MiniGames.byId(game.id), game, reason: game.id);
      }
      expect(MiniGames.byId('boyle_bir_oyun_yok'), isNull);
    });

    test('oynanabilir liste kilitli oyun taşımaz', () {
      expect(MiniGames.playable, isNotEmpty);
      for (final game in MiniGames.playable) {
        expect(game.isAvailable, isTrue, reason: game.id);
      }
      expect(MiniGames.playable.length, lessThan(MiniGames.all.length));
    });
  });
}
