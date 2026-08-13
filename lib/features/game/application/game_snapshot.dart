import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../journey/services/route_service.dart';
import '../domain/block_piece.dart';
import '../domain/board.dart';
import '../domain/game_state.dart';
import '../domain/piece_shapes.dart';

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
  static const int version = 1;

  static String encode(GameSession session) {
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
      'score': session.score,
      'combo': session.combo,
      'bestCombo': session.bestCombo,
      'clearedRows': session.clearedRows,
      'clearedColumns': session.clearedColumns,
      'elapsed': session.elapsedSeconds,
      'undoLeft': session.undoLeft,
      'record': session.recordToBeat,
      'recordBeaten': session.recordBeaten,
      'stationsPassed': session.stationsPassed,
      'placedPieces': session.placedPieces,
    });
  }

  /// Kayıt bozuk, eski sürüm ya da rotası artık geçersizse `null` döner.
  static GameSession? decode(String raw, RouteService routeService) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['v'] != version) return null;

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

      return GameSession(
        journey: journey,
        board: Board.fromGrid(grid),
        tray: List<BlockPiece?>.unmodifiable(tray),
        score: json['score'] as int,
        combo: json['combo'] as int,
        bestCombo: json['bestCombo'] as int,
        clearedRows: json['clearedRows'] as int,
        clearedColumns: json['clearedColumns'] as int,
        elapsedSeconds: json['elapsed'] as int,
        // Kayıttan dönen oyun daima duraklatılmış başlar: kullanıcı hazır
        // olduğunda açıkça "devam et" der.
        status: GameStatus.paused,
        undoLeft: json['undoLeft'] as int,
        recordToBeat: json['record'] as int,
        recordBeaten: json['recordBeaten'] as bool,
        stationsPassed: json['stationsPassed'] as int,
        placedPieces: json['placedPieces'] as int,
      );
    } catch (error, stack) {
      debugPrint('Kayıtlı oyun okunamadı: $error\n$stack');
      return null;
    }
  }
}
