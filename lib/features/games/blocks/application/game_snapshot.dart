import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../journey/services/route_service.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/combo.dart';
import '../domain/game_state.dart';
import '../domain/piece_shapes.dart';
import '../domain/streak.dart';
import 'game_controller.dart';

/// Kayıttan çözülmüş oyun: tahta durumu (+ eski kayıtlarda motor durumu).
///
/// [progress] yalnızca ortak yolculuktan **önceki** kayıtlarda dolu: puan,
/// süre ve geçilen durak artık oyunun değil yolculuğun (bkz.
/// `JourneySave`), kayıtta da orada duruyor.
@immutable
class SavedGame {
  const SavedGame({required this.session, this.progress});

  final GameSession session;
  final ResumedProgress? progress;
}

/// Yarım kalan oyunun diske yazılabilir hâli.
///
/// Metroda uygulama sürekli arka plana atılır: telefon cebe girer, ekran
/// kilitlenir, araya bir bildirim girer. Oyunun bu yüzden kaybolmaması
/// gerekir — kullanıcı geri döndüğünde kaldığı yerden devam eder.
///
/// Yolculuk iki durak id'siyle saklanır ve açılışta yeniden hesaplanır;
/// böylece metro verisi güncellenirse eski kayıt sessizce geçersiz olur.
class GameSnapshot {
  const GameSnapshot._();

  /// Kayıt biçimi değişirse eski kayıtlar atılır.
  ///
  /// v4 **yalnızca tahtayı** taşır: puan, süre ve geçilen durak yolculuğun
  /// zarfına (`JourneySave`) taşındı. v3 hâlâ okunuyor — oyuncunun yarım
  /// kalan oyunu sürüm yükseltmesinde kaybolmasın.
  static const int version = 4;

  /// Okunabilen sürümler.
  static const Set<int> readableVersions = <int>{3, 4};

  /// [GameController.session] tahtanın kendisi; zarf onu metin olarak
  /// taşır.
  static String encode(GameController controller) {
    final session = controller.session;
    return jsonEncode(<String, dynamic>{
      'v': version,
      'origin': session.journey.origin.id,
      'destination': session.journey.destination.id,
      'board': session.board.toGrid(),
      'tray': <Map<String, dynamic>?>[
        for (final piece in session.tray)
          if (piece == null)
            null
          else
            <String, dynamic>{'id': piece.id, 'color': piece.colorIndex},
      ],
      'combo': session.combo,
      'bestCombo': session.bestCombo,
      'comboGrace': session.comboState.movesSinceLastClear,
      'streak': session.streakState.value,
      'bestStreak': session.streakState.best,
      'streakPieces': session.streakState.piecesInSet,
      'streakCleared': session.streakState.clearedInSet,
      'clearedRows': session.clearedRows,
      'clearedColumns': session.clearedColumns,
      'undoLeft': session.undoLeft,
      'placedPieces': session.placedPieces,
    });
  }

  /// Kayıt bozuk, eski sürüm ya da rotası artık geçersizse `null` döner.
  static SavedGame? decode(String raw, RouteService routeService) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (!readableVersions.contains(json['v'])) return null;

      final journey = routeService
          .estimate(json['origin'] as String, json['destination'] as String)
          .journey;
      if (journey == null) return null;

      final grid = <List<int>>[
        for (final row in json['board'] as List<dynamic>)
          <int>[for (final cell in row as List<dynamic>) cell as int],
      ];

      // Parça kataloğu değişmişse (şekil silinmiş ya da adı değişmiş)
      // `byId` null döner. Bunu sessizce tepsiye koymak tehlikeli: oyuncu
      // eksik tepsiyle devam eder, tepsi tamamen boşalırsa oyun kilitlenir
      // (yeni tepsi yalnızca hamle yapılınca geliyor, yapacak parça ise yok).
      // Bu yüzden tek bir şekil bile çözülemezse kaydın tamamı atılır.
      final tray = <BlockPiece?>[];
      for (final entry in json['tray'] as List<dynamic>) {
        if (entry == null) {
          tray.add(null);
          continue;
        }
        final map = entry as Map<String, dynamic>;
        final shape = PieceShapes.byId(map['id'] as String);
        if (shape == null) return null;
        tray.add(shape.withColor(map['color'] as int));
      }

      return SavedGame(
        session: GameSession(
          journey: journey,
          board: Board.fromGrid(grid),
          tray: List<BlockPiece?>.unmodifiable(tray),
          comboState: ComboState(
            value: json['combo'] as int,
            movesSinceLastClear: json['comboGrace'] as int,
            best: json['bestCombo'] as int,
          ),
          streakState: StreakState(
            value: json['streak'] as int,
            best: json['bestStreak'] as int,
            piecesInSet: json['streakPieces'] as int,
            clearedInSet: json['streakCleared'] as bool,
          ),
          clearedRows: json['clearedRows'] as int,
          clearedColumns: json['clearedColumns'] as int,
          undoLeft: json['undoLeft'] as int,
          placedPieces: json['placedPieces'] as int,
        ),
        // Eski kayıtta yolculuk alanları da vardı; yenisinde zarfta.
        progress: json['v'] == 3
            ? ResumedProgress(
                score: json['score'] as int,
                elapsedSeconds: json['elapsed'] as int,
                stationsPassed: json['stationsPassed'] as int,
                recordToBeat: json['record'] as int,
                recordBeaten: json['recordBeaten'] as bool,
              )
            : null,
      );
    } catch (error, stack) {
      debugPrint('Kayıtlı oyun okunamadı: $error\n$stack');
      return null;
    }
  }
}
