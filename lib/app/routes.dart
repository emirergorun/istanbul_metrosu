import 'package:flutter/material.dart';

import '../features/games/blocks/domain/game_state.dart';
import '../features/games/blocks/presentation/game_screen.dart';
import '../features/games/catalog/game_select_screen.dart';
import '../features/home/presentation/title_screen.dart';
import '../features/journey/models/journey.dart';
import '../features/journey/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// Oyun ekranına geçilirken taşınan bilgi.
@immutable
class GameLaunch {
  const GameLaunch({required this.journey, this.resumeFrom});

  final Journey journey;
  final GameSession? resumeFrom;
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
            builder: (_) =>
                GameScreen(journey: args.journey, resumeFrom: args.resumeFrom),
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
    GameSession? resumeFrom,
  }) {
    return Navigator.of(context).pushNamed<void>(
      game,
      arguments: GameLaunch(journey: journey, resumeFrom: resumeFrom),
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
