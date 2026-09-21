import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/telemetry/analytics.dart';
import '../../journey/models/journey.dart';
import '../../session/journey_run.dart';
import '../domain/share_card.dart';

/// Yolculuk sonucunu sistem paylaşım sayfasına verir.
///
/// Ortak katmanda duruyor çünkü altı oyunun da sonuç paneli aynı metni
/// üretmeli: paylaşılan şey oyunun değil **yolculuğun** sonucu.
class ShareService {
  const ShareService._();

  /// Sonucu paylaşır. Paylaşım sayfası açılıp tamamlandıysa `true`.
  static Future<bool> shareRun({
    required BuildContext context,
    required JourneyView run,
    required Journey journey,
    required int passedStops,
    required String gameName,
    required LocalStore store,
    Analytics analytics = const NoopAnalytics(),
  }) async {
    final text = ShareCard.build(
      lineId: journey.lineId,
      originName: journey.origin.name,
      destinationName: journey.destination.name,
      gameName: gameName,
      score: run.score,
      stops: journey.stopCount,
      passedStops: passedStops,
      playerName: store.playerName,
      arrived: run.status == GameStatus.arrived,
    );

    // Paylaşım sayfasının iPad'de nereden açıldığını bilmesi gerekiyor;
    // iPhone'da yok sayılır.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    final result = await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
    if (result.status == ShareResultStatus.success) {
      analytics.log(
        AnalyticsEvent.resultShared,
        params: <String, String>{'oyun': gameName},
      );
      return true;
    }
    return false;
  }
}
