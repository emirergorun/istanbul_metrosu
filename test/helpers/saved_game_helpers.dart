import 'package:istanbul_metro_game/features/games/blocks/application/game_controller.dart';
import 'package:istanbul_metro_game/features/games/blocks/application/game_snapshot.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/game_state.dart';

/// Testlerde kayıttan dönen oyun kurmak için.
///
/// Motor birleştikten sonra tahta durumu ([GameSession]) ile skor/süre gibi
/// motor durumu ([ResumedProgress]) ayrı taşınıyor; bu yardımcı ikisini tek
/// çağrıda birleştirir.
SavedGame savedGameOf(
  GameSession session, {
  int score = 0,
  int elapsedSeconds = 0,
  int stationsPassed = 0,
  int recordToBeat = 0,
  bool recordBeaten = false,
}) {
  return SavedGame(
    session: session,
    progress: ResumedProgress(
      score: score,
      elapsedSeconds: elapsedSeconds,
      stationsPassed: stationsPassed,
      recordToBeat: recordToBeat,
      recordBeaten: recordBeaten,
    ),
  );
}
