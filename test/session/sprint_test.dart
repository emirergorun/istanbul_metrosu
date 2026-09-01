import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/features/games/metro_merge/application/metro_merge_controller.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/journey_game_controller.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final routeService = RouteService(MetroFixture.load());

  MetroMergeController controllerFor(String origin, String destination) {
    return MetroMergeController(
      journey: routeService.estimate(origin, destination).journey!,
      recordToBeat: 0,
    );
  }

  /// Yolculuğu bitmesine bir saniye kalana kadar ilerletir.
  void runToLastSecond(MetroMergeController controller) {
    final total = controller.journey.estimatedSeconds;
    for (var i = 0; i < total - 1; i++) {
      controller.debugAdvance(1);
    }
  }

  group('son durak sprinti', () {
    test('kısa yolculukta hiç açılmaz', () {
      // Taksim -> Osmanbey: 1 durak. "Son durak sprinti" anlamsız olurdu.
      final controller = controllerFor('m2_taksim', 'm2_osmanbey')..start();
      addTearDown(controller.dispose);

      expect(
        controller.journey.stopCount,
        lessThan(JourneyGameController.sprintMinStops),
      );

      runToLastSecond(controller);

      expect(controller.isSprint, isFalse);
      expect(controller.sprintPulse, 0);
    });

    test('uzun yolculukta son dilimde açılır ve bir kez haber verir', () {
      // Yenikapı -> Hacıosman: 14 durak.
      final controller = controllerFor('m2_yenikapi', 'm2_haciosman')..start();
      addTearDown(controller.dispose);

      expect(
        controller.journey.stopCount,
        greaterThanOrEqualTo(JourneyGameController.sprintMinStops),
      );
      expect(controller.isSprint, isFalse);

      runToLastSecond(controller);

      expect(controller.isSprint, isTrue);
      expect(
        controller.sprintPulse,
        1,
        reason: 'şerit yalnızca bir kez gösterilmeli',
      );
    });
  });
}
