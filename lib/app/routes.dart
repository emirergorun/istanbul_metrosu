import 'package:flutter/material.dart';

import '../features/games/blocks/application/game_snapshot.dart';
import '../features/games/blocks/presentation/game_screen.dart';
import '../features/games/lane_runner/application/lane_runner_controller.dart';
import '../features/games/lane_runner/presentation/lane_runner_screen.dart';
import '../features/games/merge_drop/application/merge_drop_controller.dart';
import '../features/games/merge_drop/presentation/merge_drop_screen.dart';
import '../features/games/metro_merge/application/metro_merge_controller.dart';
import '../features/games/metro_merge/presentation/metro_merge_screen.dart';
import '../features/games/rail_flight/application/rail_flight_controller.dart';
import '../features/games/rail_flight/presentation/rail_flight_screen.dart';
import '../features/games/metro_quiz/application/metro_quiz_controller.dart';
import '../features/games/metro_quiz/presentation/metro_quiz_screen.dart';
import '../features/games/train_snake/application/train_snake_controller.dart';
import '../features/games/train_snake/presentation/train_snake_screen.dart';
import '../features/games/catalog/game_select_screen.dart';
import '../features/home/presentation/title_screen.dart';
import '../features/journey/models/journey.dart';
import '../features/journey/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// Oyun ekranına geçilirken taşınan bilgi.
@immutable
class GameLaunch {
  const GameLaunch({
    required this.journey,
    this.gameId = 'blocks',
    this.resumeFrom,
  });

  final Journey journey;
  final String gameId;
  final SavedGame? resumeFrom;
}

/// Uygulama rotaları.
///
/// MVP'de iki ekran var; router paketine gerek yok.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String planner = '/planner';
  static const String gameSelect = '/game-select';
  static const String game = '/game';
  static const String settings = '/settings';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case planner:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
      case AppRoutes.settings:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SettingsScreen(),
        );
      case gameSelect:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              GameSelectScreen(journey: settings.arguments! as Journey),
        );
      case game:
        final args = settings.arguments;
        if (args is GameLaunch) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) {
              if (args.gameId == MetroMergeController.id) {
                return MetroMergeScreen(journey: args.journey);
              }
              if (args.gameId == RailFlightController.id) {
                return RailFlightScreen(journey: args.journey);
              }
              if (args.gameId == MergeDropController.id) {
                return MergeDropScreen(journey: args.journey);
              }
              if (args.gameId == MetroQuizController.id) {
                return MetroQuizScreen(journey: args.journey);
              }
              if (args.gameId == LaneRunnerController.id) {
                return LaneRunnerScreen(journey: args.journey);
              }
              if (args.gameId == TrainSnakeController.id) {
                return TrainSnakeScreen(journey: args.journey);
              }
              return GameScreen(
                journey: args.journey,
                resumeFrom: args.resumeFrom,
              );
            },
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => GameScreen(journey: args! as Journey),
        );
      case home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const TitleScreen(),
        );
    }
  }

  /// Oyun ekranını açar. [resumeFrom] verilirse yarım kalan oyun sürer.
  static Future<void> openGame(
    BuildContext context,
    Journey journey, {
    String gameId = 'blocks',
    SavedGame? resumeFrom,
  }) {
    return Navigator.of(context).pushNamed<void>(
      game,
      arguments: GameLaunch(
        journey: journey,
        gameId: gameId,
        resumeFrom: resumeFrom,
      ),
    );
  }

  /// Rota planlayıcıyı açar.
  static Future<void> openPlanner(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(planner);

  /// Rota seçildikten sonra oyun seçim ekranını açar.
  static Future<void> openGameSelect(BuildContext context, Journey journey) =>
      Navigator.of(context).pushNamed<void>(gameSelect, arguments: journey);

  /// Ayarları açar.
  static Future<void> openSettings(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(AppRoutes.settings);
}
