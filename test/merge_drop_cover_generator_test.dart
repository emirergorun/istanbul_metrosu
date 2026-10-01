@Tags(<String>['tools'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/application/merge_drop_controller.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/domain/merge_drop_state.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/presentation/merge_drop_effects.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/presentation/merge_drop_painter.dart';
import 'package:istanbul_metro_game/features/games/merge_drop/presentation/metro_token.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import 'helpers/metro_fixture.dart';

/// Hat Düşür'ün galeri kapağını üretir — ürün kodu değil, araç.
///
/// Kapak **oyunun kendi çizicisinden** çıkıyor ([MergeDropPainter],
/// [paintMetroToken]): jetonlar oyundaki fizikle yerleştirilip oturtuluyor,
/// sonra bir M8 birleşmesinin ilk karesi çiziliyor. Görüntü üretici yok;
/// kartta ne görünüyorsa oyunda da o var.
///
///   flutter test test/merge_drop_cover_generator_test.dart
///   cp build/merge_drop_cover.png assets/images/games/hat_dusur_cover.png
///
/// Başlık kapakta yok; galeri onu Bungee ile sol üste yazıyor. Üst bölge
/// sakin bırakıldı, depo kartın altından taşar.
void main() {
  const width = 660.0;
  const height = 1200.0;

  Future<void> loadFonts() async {
    Future<ByteData> read(String path) async =>
        ByteData.sublistView(await File(path).readAsBytes());
    final body = FontLoader(AppFonts.body)
      ..addFont(read('assets/fonts/MPLUSRounded1c-ExtraBold.ttf'))
      ..addFont(read('assets/fonts/MPLUSRounded1c-Bold.ttf'));
    await body.load();
  }

  test('Hat Düşür kapağı', () async {
    await loadFonts();
    final metro = MetroFixture.load();
    final palette = MetroTokenPalette.from(metro);
    final journey = RouteService(
      metro,
    ).estimate('m1a_yenikapi', 'm1a_ataturk_havalimani').journey!;
    final controller = MergeDropController(
      journey: journey,
      recordToBeat: 0,
      random: Random(11),
      tick: const Duration(hours: 1),
    )..start();
    addTearDown(controller.dispose);
    controller.setPoolAspect(mergeDropPoolAspect);
    final h = controller.worldHeight;

    // Seçilmiş bir yığın: altta büyük hatlar, üstte küçükler. Komşu eş
    // seviye yok ki oturturken birleşmesinler.
    var id = 1;
    DropBall ball(int level, double x, double y) =>
        DropBall(id: id++, level: level, x: x, y: h - y);
    controller.debugSetBalls(<DropBall>[
      ball(9, 0.20, 0.18),
      ball(7, 0.52, 0.13),
      ball(8, 0.82, 0.15),
      ball(6, 0.40, 0.40),
      ball(5, 0.70, 0.38),
      ball(4, 0.10, 0.48),
      ball(3, 0.90, 0.42),
      ball(2, 0.55, 0.60),
      ball(1, 0.28, 0.62),
      ball(3, 0.78, 0.62),
      ball(4, 0.20, 0.72),
      ball(5, 0.45, 0.80),
      ball(2, 0.66, 0.78),
      ball(1, 0.88, 0.80),
    ]);
    for (var i = 0; i < 240; i++) {
      controller.debugStep(1 / 60);
    }
    controller.takeEvents();
    controller.moveAim(0.6);

    // Birleşmenin ilk karesi: yığının ortasındaki M7, az önce iki M6'dan
    // doğmuş gibi — darbe halkası ve puan yazısı.
    final hero = controller.balls.reduce(
      (a, b) => (a.level == 7) ? a : b,
    );
    final effects = MergeDropEffects()
      ..addMerge(
        MergeDropEvent(
          level: hero.level,
          x: hero.x,
          y: hero.y,
          parentA: (hero.x, hero.y),
          parentB: (hero.x, hero.y),
          points: (mergeDropMergePoints(hero.level) * 0.027).round(),
          chain: 1,
          newRunMax: false,
        ),
      );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      // Kurumsal lacivert: galerinin koyu zemininden ayrılsın, kartın sınırı
      // kaybolmasın.
      Paint()..color = AppColors.brandNavyDeep,
    );

    // Depo kartın iki yanından ve altından hafifçe taşar; tepesi kartın
    // üçte birinde — başlığa yer kalır.
    const depotWidth = 740.0;
    final depotHeight = depotWidth * mergeDropPoolAspect;
    canvas.save();
    canvas.translate((width - depotWidth) / 2, height - depotHeight - 10);
    MergeDropPainter(
      controller: controller,
      palette: palette,
      effects: effects,
      showGuide: true,
    ).paint(canvas, Size(depotWidth, depotHeight));
    canvas.restore();

    final image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build').createSync(recursive: true);
    File(
      'build/merge_drop_cover.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);
    expect(File('build/merge_drop_cover.png').lengthSync(), greaterThan(1000));
  });
}
