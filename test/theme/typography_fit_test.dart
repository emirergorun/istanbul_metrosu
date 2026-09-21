import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';

/// Tipografi fizibilitesi: **hangi yazı hangi kutuya sığıyor?**
///
/// Bungee bir tabela fontu — yalnız büyük harf, geniş, ağır. Gövde metnine
/// ya da uzun durak adlarına konulup konulamayacağı fikir meselesi değil,
/// ölçü meselesi. Bu test gerçek font dosyalarını yükleyip gerçek metinleri
/// ölçüyor ve uygulamanın desteklediği en dar ekranda (320 piksel) en büyük
/// yazı ölçeğinde (1.6×) taşma olup olmadığını söylüyor.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final entry in <String, List<String>>{
      'Bungee': <String>['assets/fonts/Bungee-Regular.ttf'],
      'M PLUS Rounded 1c': <String>[
        'assets/fonts/MPLUSRounded1c-Regular.ttf',
        'assets/fonts/MPLUSRounded1c-Medium.ttf',
        'assets/fonts/MPLUSRounded1c-Bold.ttf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        loader.addFont(
          Future<ByteData>.value(
            File(path).readAsBytesSync().buffer.asByteData(),
          ),
        );
      }
      await loader.load();
    }
  });

  double widthOf(String text, TextStyle style, {double scale = 1}) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
    )..layout();
    return painter.width;
  }

  test('Bungee uzun durak adı için ne kadar geniş', () {
    const samples = <String>[
      'Sancaktepe Şehir Hastanesi',
      'Sabiha Gökçen Havalimanı',
      'Vezneciler-İstanbul Ü.',
      'Şişli-Mecidiyeköy',
      'Yenikapı',
    ];
    const body = TextStyle(fontFamily: AppFonts.body, fontSize: 15);
    const display = TextStyle(fontFamily: AppFonts.display, fontSize: 15);

    // ignore: avoid_print
    print('\n--- 15 punto, aynı metin, iki font ---');
    for (final s in samples) {
      final b = widthOf(s, body);
      final d = widthOf(s, display);
      // ignore: avoid_print
      print(
        '${s.padRight(28)} gövde ${b.toStringAsFixed(0).padLeft(4)} px  '
        'Bungee ${d.toStringAsFixed(0).padLeft(4)} px  '
        '×${(d / b).toStringAsFixed(2)}',
      );
    }
  });

  test('yolculuk şeridi: iki durak adı tek satıra sığıyor mu', () {
    // Galeri şeridi: 320 px ekran − 2×16 kenar − 3 şerit − 2×12 iç dolgu
    // − rozet 34 − boşluk 8 − süre 46 − boşluk 8.
    const available = 320 - 32 - 3 - 24 - 34 - 8 - 46 - 8;
    const route = 'Sancaktepe Şehir Hastanesi → Sabiha Gökçen Havalimanı';

    // ignore: avoid_print
    print('\n--- yolculuk şeridi, kullanılabilir genişlik $available px ---');
    for (final size in <double>[13, 14, 15, 16]) {
      for (final scale in <double>[1.0, 1.6]) {
        final body = widthOf(
          route,
          TextStyle(
            fontFamily: AppFonts.body,
            fontSize: size,
            fontWeight: FontWeight.w700,
          ),
          scale: scale,
        );
        final bungee = widthOf(
          route,
          TextStyle(fontFamily: AppFonts.display, fontSize: size),
          scale: scale,
        );
        // ignore: avoid_print
        print(
          '$size punto ×$scale  gövde ${body.toStringAsFixed(0).padLeft(4)} '
          '(${(body / available).toStringAsFixed(1)}× taşma)  '
          'Bungee ${bungee.toStringAsFixed(0).padLeft(4)} '
          '(${(bungee / available).toStringAsFixed(1)}× taşma)',
        );
      }
    }
  });

  test('OYNA düğmesi Bungee ile sığıyor mu', () {
    // 320 px ekran − 2×16 kenar − 2×24 düğme iç dolgu.
    const available = 320 - 32 - 48;
    // ignore: avoid_print
    print('\n--- OYNA, kullanılabilir genişlik $available px ---');
    for (final size in <double>[16, 18, 20, 22, 24]) {
      final w = widthOf(
        'OYNA',
        TextStyle(fontFamily: AppFonts.display, fontSize: size),
        scale: 1.6,
      );
      // ignore: avoid_print
      print(
        '$size punto ×1.6  ${w.toStringAsFixed(0)} px  '
        '${w <= available ? "sığıyor" : "TAŞIYOR"}',
      );
    }
  });

  test('birincil düğme metinleri Bungee ile sığıyor mu', () {
    // FilledButton: 320 px ekran − 2×16 sayfa kenarı − 2×24 düğme dolgusu.
    const available = 320 - 32 - 48;
    const labels = <String>[
      'OYNA',
      'TEKRAR OYNA',
      'OYUNA BAŞLA',
      'SONUCU PAYLAŞ',
      'YOLCULUĞU BAŞLAT',
      'BAŞLA',
      'BAŞKA OYUN SEÇ',
    ];
    // ignore: avoid_print
    print('\n--- birincil düğme, kullanılabilir $available px ---');
    for (final size in <double>[14, 15, 16, 17, 18]) {
      final widths = <String, double>{
        for (final l in labels)
          l: widthOf(
            l,
            TextStyle(fontFamily: AppFonts.display, fontSize: size),
            scale: 1.6,
          ),
      };
      if (size != 16) continue;
      // ignore: avoid_print
      print('$size punto ×1.6, tek tek:');
      for (final e in widths.entries) {
        // ignore: avoid_print
        print(
          '   ${e.key.padRight(18)} ${e.value.toStringAsFixed(0).padLeft(4)} px  '
          '${e.value <= available ? "sığıyor" : "TAŞIYOR"}',
        );
      }
    }
  });

  test('bölüm etiketleri Bungee ile sığıyor mu', () {
    const available = 320 - 32;
    const labels = <String>[
      'AMAÇ',
      'YOLCULUĞUN',
      'İSTANBUL KEŞFİ',
      'HATLAR',
      'NASIL OYNANIR?',
      'YENİ KEŞİFLER',
      'İSTANBUL KEŞFİ',
    ];
    // ignore: avoid_print
    print('\n--- bölüm etiketi, kullanılabilir $available px ---');
    for (final size in <double>[13, 15, 16, 17]) {
      final worst = labels
          .map(
            (String l) => widthOf(
              l,
              TextStyle(fontFamily: AppFonts.display, fontSize: size),
              scale: 1.6,
            ),
          )
          .reduce((double a, double b) => a > b ? a : b);
      // ignore: avoid_print
      print(
        '$size punto ×1.6  en geniş ${worst.toStringAsFixed(0)} px  '
        '${worst <= available ? "sığıyor" : "TAŞIYOR"}',
      );
    }
  });

  test('detay ekranı gövde metni: kaç satıra çıkıyor', () {
    const available = 320.0 - 32;
    const text =
        'Toplanan her beş yolcu bir üst hatta taşır; elli yolcuda M11’e '
        'ulaşıp yolculuğu kazanırsın. Duvara ya da kendi vagonlarına '
        'çarptığında oyun biter.';
    // ignore: avoid_print
    print('\n--- detay gövde metni, genişlik $available px ---');
    for (final size in <double>[14, 15, 16, 17]) {
      for (final scale in <double>[1.0, 1.6]) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: AppFonts.body,
              fontSize: size,
              height: 1.4,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout(maxWidth: available);
        // ignore: avoid_print
        print(
          '$size punto ×$scale  ${painter.computeLineMetrics().length} satır  '
          '${painter.height.toStringAsFixed(0)} px yükseklik',
        );
      }
    }
  });
}
