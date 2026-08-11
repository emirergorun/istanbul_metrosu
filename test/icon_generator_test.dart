@Tags(<String>['tools'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/widgets/metro_train.dart';

/// Uygulama ikonunu üretir — ürün kodu değil, araç.
///
/// İkon, oyunun içindeki `MetroTrainPainter` ile çizilir; böylece ikon, alt
/// çubuktaki tren ve varış sahnesindeki tren aynı şekildir.
///
///   flutter test test/icon_generator_test.dart
void main() {
  test('1024x1024 ikon üret', () async {
    const size = 1024.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

    // Zemin: kurumsal lacivert, hafif dikey degrade.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF1B5488), AppColors.brandNavyDeep],
        ).createShader(const Rect.fromLTWH(0, 0, size, size)),
    );

    // Ray: trenin altından geçen çizgi ve durak noktaları.
    const trackY = size * 0.66;
    canvas.drawLine(
      const Offset(size * 0.10, trackY),
      const Offset(size * 0.90, trackY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..strokeWidth = size * 0.018
        ..strokeCap = StrokeCap.round,
    );
    for (var i = 0; i <= 3; i++) {
      canvas.drawCircle(
        Offset(size * (0.10 + 0.80 * i / 3), trackY),
        size * 0.022,
        Paint()..color = Colors.white.withValues(alpha: 0.32),
      );
    }

    // Tren: hattın yeşili, ekrandakiyle aynı çizim.
    const trainHeight = size * 0.30;
    final trainWidth = MetroTrain.widthFor(height: trainHeight);
    canvas.save();
    canvas.translate(
      (size - trainWidth) / 2,
      trackY - trainHeight - size * 0.03,
    );
    const MetroTrainPainter(
      color: AppColors.success,
    ).paint(canvas, Size(trainWidth, trainHeight));
    canvas.restore();

    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      'build/app_icon.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List(), flush: true);

    expect(File('build/app_icon.png').lengthSync(), greaterThan(1000));
  });
}
