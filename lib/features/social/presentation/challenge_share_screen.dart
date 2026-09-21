import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../games/catalog/mini_game.dart';
import '../domain/challenge.dart';
import '../domain/challenge_codec.dart';
import 'widgets/challenge_qr_view.dart';

/// Üretilmiş meydan okumanın paylaşım ekranı.
///
/// Ekranın tamamı **çevrimdışı** çalışıyor: karekod cihazda üretiliyor,
/// metin cihazda kuruluyor, hiçbir şey beklenmiyor. Sistem paylaşım
/// sayfası açılırsa açılıyor; açılmasa da kare ekranda duruyor ve karşı
/// taraf onu doğrudan okuyabiliyor. Metroda tünelde olan iki kişi için
/// asıl yol zaten bu.
class ChallengeShareScreen extends StatelessWidget {
  const ChallengeShareScreen({
    super.key,
    required this.challenge,
    this.isRematch = false,
  });

  final Challenge challenge;

  /// Rövanş mı? Yalnızca başlık ve metin değişiyor.
  final bool isRematch;

  Future<void> _share(BuildContext context, String gameName) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    // Paylaşılan **metin**, görsel değil: görsel üretmek dosya yazmayı ve
    // her cihazda farklı ölçeklenen bir tuvali gerektirirdi. Metin her
    // uygulamada aynı görünüyor ve karekodun kendisi ekranda duruyor.
    //
    // Gizli hiçbir şey taşınmıyor: ne cihaz kimliği, ne platform kimliği,
    // ne konum. Yalnızca oyuncunun görünen adı, rota ve hedef.
    final text = <String>[
      isRematch
          ? 'RÖVANŞ · Aynı yolculukta beni geç'
          : 'Aynı yolculukta beni geç',
      '${challenge.lineId} · $gameName',
      'Hedef: ${Formatters.score(challenge.targetScore)}',
      '',
      'Kareyi İstanbul Metrosu Oyunu ile okut:',
      ChallengeCodec.encode(challenge),
    ].join('\n');

    await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: origin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final game = MiniGames.byId(challenge.gameId);
    final line = scope.metro.lineById(challenge.lineId);
    final payload = ChallengeCodec.encode(challenge);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          isRematch ? 'RÖVANŞ' : 'MEYDAN OKUMA',
          style: AppText.title,
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            Text(
              isRematch ? 'RÖVANŞ HAZIR' : 'MEYDAN OKUMA HAZIR',
              style: AppText.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.stack),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      LineBadge(
                        label: challenge.lineId,
                        color: line?.color ?? AppColors.brandNavy,
                        compact: true,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          game?.name ?? challenge.gameId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.bodyStrong,
                        ),
                      ),
                      Text(
                        Formatters.score(challenge.targetScore),
                        style: AppText.statSmall.copyWith(
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.stack),
                  Center(
                    child: ChallengeQrView(
                      data: payload,
                      size: 240,
                      semanticLabel:
                          'Meydan okuma karesi. ${challenge.lineId} hattı, '
                          '${game?.name ?? challenge.gameId}, hedef '
                          '${challenge.targetScore} puan. Arkadaşın bu kareyi '
                          'QR TARA ile okutur.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.stack),
            Text(
              'Arkadaşın bu kareyi Arkadaşlar · QR TARA ile okutsun. '
              'İnternet gerekmiyor.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            OutlinedButton(
              onPressed: AppFeedback.onTap(
                context,
                () => _share(context, game?.name ?? challenge.gameId),
              ),
              child: const Text('PAYLAŞ'),
            ),
          ],
        ),
      ),
    );
  }
}
