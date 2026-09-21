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
import '../features/daily/presentation/daily_screen.dart';
import '../features/discovery/presentation/discovery_screen.dart';
import '../features/passport/presentation/achievements_screen.dart';
import '../features/social/domain/challenge.dart';
import '../features/social/presentation/add_friend_screen.dart';
import '../features/social/presentation/challenge_preview_screen.dart';
import '../features/social/presentation/challenge_share_screen.dart';
import '../features/social/presentation/friends_screen.dart';
import '../features/social/presentation/scan_screen.dart';
import '../features/games/catalog/game_detail_screen.dart';
import '../features/games/catalog/game_select_screen.dart';
import '../features/games/catalog/mini_game.dart';
import '../features/home/presentation/title_screen.dart';
import '../features/journey/models/journey.dart';
import '../features/journey/presentation/home_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

/// Meydan okuma paylaşım ekranına geçilirken taşınan bilgi.
@immutable
class ChallengeShareArgs {
  const ChallengeShareArgs({required this.challenge, this.isRematch = false});

  final Challenge challenge;
  final bool isRematch;
}

/// Oyun tanıtım ekranına geçilirken taşınan bilgi.
@immutable
class GameDetailArgs {
  const GameDetailArgs({required this.journey, required this.gameId});

  final Journey journey;
  final String gameId;
}

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
  static const String gameDetail = '/game-detail';
  static const String game = '/game';
  static const String settings = '/settings';
  static const String discovery = '/discovery';
  static const String daily = '/daily';
  static const String achievements = '/achievements';
  static const String friends = '/friends';
  static const String addFriend = '/friends/add';
  static const String scanChallenge = '/challenge/scan';
  static const String challengePreview = '/challenge/preview';
  static const String challengeShare = '/challenge/share';

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
      case discovery:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const DiscoveryScreen(),
        );
      case daily:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const DailyScreen(),
        );
      case achievements:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AchievementsScreen(),
        );
      case friends:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const FriendsScreen(),
        );
      case addFriend:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const AddFriendScreen(),
        );
      case scanChallenge:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ScanScreen(),
        );
      case challengePreview:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              ChallengePreviewScreen(challenge: settings.arguments! as Challenge),
        );
      case challengeShare:
        final args = settings.arguments! as ChallengeShareArgs;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => ChallengeShareScreen(
            challenge: args.challenge,
            isRematch: args.isRematch,
          ),
        );
      case gameDetail:
        final args = settings.arguments! as GameDetailArgs;
        final game = MiniGames.byId(args.gameId);
        // Katalogda olmayan kimlik seçim ekranına düşürülür; kilitli oyun
        // zaten kartından açılamıyor.
        if (game == null || !game.isAvailable) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => GameSelectScreen(journey: args.journey),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => GameDetailScreen(journey: args.journey, game: game),
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

  /// Yarım kalan oyunu açar; altına o yolculuğun oyun seçim ekranını koyar.
  ///
  /// Oyundaki "Başka oyun seç" düğmesi ekranı kapatır. Oyun başlık
  /// ekranındaki kayıttan açılınca altta oyun seçimi olmadığı için düğme
  /// adının söylediği yere değil başlık ekranına dönüyordu.
  ///
  /// Dönen `Future`, oyun seçim ekranı da kapanınca tamamlanır.
  static Future<void> resumeGame(BuildContext context, SavedGame saved) {
    final navigator = Navigator.of(context);
    final gameSelectClosed = navigator.pushNamed<void>(
      gameSelect,
      arguments: saved.session.journey,
    );
    navigator.pushNamed<void>(
      game,
      arguments: GameLaunch(journey: saved.session.journey, resumeFrom: saved),
    );
    return gameSelectClosed;
  }

  /// Rota planlayıcıyı açar.
  static Future<void> openPlanner(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(planner);

  /// Rota seçildikten sonra oyun seçim ekranını açar.
  static Future<void> openGameSelect(BuildContext context, Journey journey) =>
      Navigator.of(context).pushNamed<void>(gameSelect, arguments: journey);

  /// Oyunun tanıtım ekranını açar.
  ///
  /// Oyunu **başlatmaz**: yolculuk sayacı ve İstanbul Keşfi yalnızca
  /// [openGame] ile başlar.
  static Future<void> openGameDetail(
    BuildContext context,
    Journey journey, {
    required String gameId,
  }) => Navigator.of(context).pushNamed<void>(
    gameDetail,
    arguments: GameDetailArgs(journey: journey, gameId: gameId),
  );

  /// Oyundaki "Başka oyun seç" eyleminin hedefi: **oyun galerisi**.
  ///
  /// Tek bir `pop` V2'de oyunun tanıtım ekranına düşüyordu — oyuncu "başka
  /// oyun seç" deyip aynı oyunun sayfasına varıyordu. Yığında galeri yoksa
  /// (başlık ekranından açılan yarım kalan oyun) ilk rotaya kadar dönülür;
  /// davranış eskisiyle aynı kalır.
  static void exitToGallery(BuildContext context) {
    Navigator.of(context).popUntil(
      (Route<dynamic> route) =>
          route.settings.name == gameSelect || route.isFirst,
    );
  }

  /// Arkadaşlar katmanını açar.
  static Future<void> openFriends(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(friends);

  /// Okunmuş bir meydan okumanın onay ekranını açar.
  ///
  /// Açmak kabul etmek değil: oyun ancak oyuncu onaylayınca başlıyor.
  static Future<void> openChallengePreview(
    BuildContext context,
    Challenge challenge,
  ) => Navigator.of(
    context,
  ).pushNamed<void>(challengePreview, arguments: challenge);

  /// Üretilmiş bir meydan okumanın karesini gösterir.
  static Future<void> openChallengeShare(
    BuildContext context,
    Challenge challenge, {
    bool isRematch = false,
  }) => Navigator.of(context).pushNamed<void>(
    challengeShare,
    arguments: ChallengeShareArgs(challenge: challenge, isRematch: isRematch),
  );

  /// Ayarları açar.
  static Future<void> openSettings(BuildContext context) =>
      Navigator.of(context).pushNamed<void>(AppRoutes.settings);
}
