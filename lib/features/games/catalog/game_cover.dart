import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/pressable.dart';
import 'game_cover_art.dart';
import 'mini_game.dart';

/// Bir oyunun kapağı — galeri kartında ve tanıtım ekranında **aynı**.
///
/// Zemin, sahne ve başlık tek parça: kapak kendi içinde bitmiş bir görsel.
/// Başlık kapağın altına ayrı bir şerit olarak konsaydı kart bir etiketli
/// kutuya dönerdi; oyun kapaklarının dili başlığı görselin içine alır.
class GameCover extends StatelessWidget {
  const GameCover({super.key, required this.game, this.showTitle = true});

  final MiniGame game;

  /// Başlık kapağın içine çizilsin mi? Bkz. [GameCoverArt.showTitle].
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final locked = !game.isAvailable;
    return GameCoverArt(
      scene: locked ? GameCoverScene.locked : game.coverScene,
      identity: locked ? AppColors.gameGlyphLocked : game.color,
      title: game.name,
      asset: locked ? null : game.coverAsset,
      onLightCover: !locked && game.coverIsLight,
      dimmed: locked,
      // Kilitli kapakta ad yazılmıyor: üç yer tutucu ad ("Aktarma",
      // "Sinyal", "Vagon") oyuncuya verilmemiş bir söz veriyordu. Sahne
      // zaten kapalı istasyonu ve YAKINDA tabelasını çiziyor.
      showTitle: showTitle && !locked,
    );
  }
}

/// Galerideki oyun kartı.
///
/// **Kap sabit, sanat değişir.** Yedi oyunun kartı aynı orana, aynı köşe
/// yarıçapına ve aynı dokunma davranışına sahip; ayrışma kapak sahnesinden
/// ve oyunun renginden geliyor. Her kart kendi düzenini uydursaydı ekran bir
/// oyun koleksiyonu değil yedi ayrı deneme gibi görünürdü.
///
/// Kartın **tamamı** dokunmatik: içine küçük bir "oyna" düğmesi konmuyor.
/// Dokunuş oyunu başlatmaz, oyunun tanıtımını açar.
class GameCoverCard extends StatelessWidget {
  const GameCoverCard({super.key, required this.game, required this.onTap});

  final MiniGame game;

  /// Kart açılınca çağrılır. Kilitli oyunda `null` gelir.
  final VoidCallback? onTap;

  /// Kartın en/boy oranı (genişlik / yükseklik).
  ///
  /// Kapak görsellerinin kendi oranı: referans tabakasındaki yedi kart tek
  /// orana getirildi. Kart başka bir orana zorlanırsa `BoxFit.cover` ya
  /// başlık bandını ya da kompozisyonun altını kırpar.
  static const double aspectRatio = 0.55;

  /// Köşe yarıçapı — kart, içindeki her ögeden daha yuvarlak.
  static const double radius = 18;

  @override
  Widget build(BuildContext context) {
    final locked = !game.isAvailable;

    return Semantics(
      button: !locked,
      enabled: !locked,
      label: locked
          ? '${game.name}, yakında eklenecek, henüz oynanamaz'
          : '${game.name} oyununu görüntüle',
      child: ExcludeSemantics(
        child: Opacity(
          opacity: locked ? 0.5 : 1,
          child: Pressable(
            onTap: locked ? null : onTap,
            borderRadius: BorderRadius.circular(radius),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
                child: GameCover(game: game),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
