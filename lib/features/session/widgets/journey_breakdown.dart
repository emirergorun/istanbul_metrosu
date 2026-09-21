import 'package:flutter/widgets.dart';

import '../../games/catalog/mini_game.dart';
import '../../../core/utils/formatters.dart';
import '../journey_session.dart';
import 'overlay_panel.dart';

/// Varış panelindeki "hangi oyun ne kazandırdı" satırları.
///
/// Puan tek başına yanıltıcı: 800 puan altı dakika oynanmışsa normaldir,
/// bir dakika oynanmışsa bir denge hatasıdır. Bu yüzden her satır puanın
/// yanında **oynanan süreyi** de yazıyor. Satırların toplamı yolculuk
/// skoruna birebir eşittir (durak bonusu dahil).
List<Widget> journeyBreakdownRows(JourneySession session) {
  final rows = <Widget>[];
  for (final entry in session.scoreByGame.entries) {
    if (entry.value <= 0) continue;
    final isJourney = entry.key == JourneySession.journeyBucket;
    rows.add(
      StatRow(
        label: isJourney
            ? 'Durak bonusu'
            : '${MiniGames.byId(entry.key)?.name ?? entry.key}'
                  ' · ${playedLabel(session.secondsOf(entry.key))}',
        value: Formatters.score(entry.value),
      ),
    );
  }
  return rows;
}

/// "6 dk" / "40 sn" — dağılım satırındaki süre.
String playedLabel(double seconds) {
  if (seconds < 90) return '${seconds.round()} sn';
  return '${(seconds / 60).round()} dk';
}
