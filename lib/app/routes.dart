import 'package:flutter/material.dart';

import '../features/game/presentation/game_screen.dart';
import '../features/journey/models/journey.dart';
import '../features/journey/presentation/home_screen.dart';

/// Uygulama rotaları.
///
/// MVP'de iki ekran var; router paketine gerek yok.
class AppRoutes {
  const AppRoutes._();

  static const String home = '/';
  static const String game = '/game';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case game:
        final journey = settings.arguments as Journey;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => GameScreen(journey: journey),
        );
      case home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
    }
  }

  /// Oyun ekranını açar.
  static Future<void> openGame(BuildContext context, Journey journey) {
    return Navigator.of(context).pushNamed<void>(game, arguments: journey);
  }
}
