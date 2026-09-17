import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/telemetry/analytics.dart';
import 'package:istanbul_metro_game/core/telemetry/error_reporter.dart';
import 'package:istanbul_metro_game/core/telemetry/usage_stats.dart';

/// Ölçüm ve hata kaydı.
///
/// İkisi de **cihazda kalıyor**: ağ isteği yok, kişisel veri yok. Bu
/// testler o sözün kodda karşılığı olduğunu ve sayaçların doğru
/// sayıldığını doğruluyor.
void main() {
  group('kullanım sayaçları', () {
    late String? stored;
    UsageStats build() =>
        UsageStats(load: () => stored, save: (raw) async => stored = raw);

    setUp(() => stored = null);

    test('olay sayılır ve kayda yazılır', () {
      final stats = build()..log(AnalyticsEvent.gameStarted);

      expect(stats.valueOf(AnalyticsEvent.gameStarted), 1);
      expect(stored, isNotNull);
    });

    test('kategorik kırılım ayrı sayaç tutar', () {
      final stats = build()
        ..log(
          AnalyticsEvent.gameStarted,
          params: <String, String>{'game': 'blocks'},
        )
        ..log(
          AnalyticsEvent.gameStarted,
          params: <String, String>{'game': 'metro_quiz'},
        )
        ..log(
          AnalyticsEvent.gameStarted,
          params: <String, String>{'game': 'blocks'},
        );

      expect(stats.valueOf(AnalyticsEvent.gameStarted), 3);
      expect(
        stats.valueOf(AnalyticsEvent.gameStarted, suffix: 'game.blocks'),
        2,
      );
      expect(
        stats.valueOf(AnalyticsEvent.gameStarted, suffix: 'game.metro_quiz'),
        1,
      );
    });

    test('sayaçlar yeni oturumda geri yüklenir', () {
      build().log(AnalyticsEvent.journeyArrived);
      final next = build();

      expect(next.valueOf(AnalyticsEvent.journeyArrived), 1);
    });

    test('varış oranı tamamlanan ve yarım kalanlardan hesaplanır', () {
      final stats = build()
        ..log(AnalyticsEvent.journeyArrived)
        ..log(AnalyticsEvent.journeyArrived)
        ..log(AnalyticsEvent.gameOver)
        ..log(AnalyticsEvent.gameAbandoned);

      expect(stats.arrivalRate, 0.5);
    });

    test('hiç oyun yoksa oran sıfır, bölme hatası olmaz', () {
      expect(build().arrivalRate, 0);
    });

    test('bozuk kayıt oyunu durdurmaz', () {
      stored = 'bu json değil';
      final stats = build();

      expect(stats.valueOf(AnalyticsEvent.appOpened), 0);
      stats.log(AnalyticsEvent.appOpened);
      expect(stats.valueOf(AnalyticsEvent.appOpened), 1);
    });

    test('sıfırlama sayaçları siler', () async {
      final stats = build()..log(AnalyticsEvent.gameOver);
      await stats.reset();

      expect(stats.counts, isEmpty);
    });

    test('kapalıyken hiçbir şey sayılmaz', () {
      const analytics = NoopAnalytics();
      // Çökmeden çalışmalı; ölçümün kapalı hâli de aynı yoldan geçiyor.
      analytics.log(AnalyticsEvent.gameStarted);
    });
  });

  group('hata kaydı', () {
    late String? stored;
    ErrorReporter build() =>
        ErrorReporter(load: () => stored, save: (raw) async => stored = raw);

    setUp(() => stored = null);

    test('hata kaydedilir ve en yeni başta durur', () {
      final reporter = build()
        ..record('ilk hata', context: 'widget')
        ..record('ikinci hata', context: 'platform');

      expect(reporter.entries.first.message, 'ikinci hata');
      expect(reporter.entries, hasLength(2));
    });

    test('kayıt sayısı sınırlıdır', () {
      final reporter = build();
      for (var i = 0; i < ErrorReporter.maxEntries + 10; i++) {
        reporter.record('hata $i');
      }

      expect(reporter.entries, hasLength(ErrorReporter.maxEntries));
    });

    test('uzun yığın izi kırpılır', () {
      final reporter = build()..record('x' * 2000);

      expect(reporter.entries.first.message.length, lessThanOrEqualTo(400));
    });

    test('kayıtlar yeni oturumda geri yüklenir', () {
      build().record('kalıcı hata');

      expect(build().entries.first.message, 'kalıcı hata');
    });

    test('temizleme kayıtları siler', () async {
      final reporter = build()..record('hata');
      await reporter.clear();

      expect(reporter.entries, isEmpty);
    });

    test('paylaşım metni boş kayıtta da çalışır', () {
      expect(build().asShareText(), 'Kayıtlı hata yok.');
    });
  });
}
