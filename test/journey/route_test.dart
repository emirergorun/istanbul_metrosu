import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/utils/formatters.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';
import 'package:istanbul_metro_game/features/journey/services/difficulty_mapper.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

import '../helpers/metro_fixture.dart';

void main() {
  final repository = MetroFixture.load();
  final service = RouteService(repository);

  group('RouteService', () {
    test('aynı istasyon reddedilir', () {
      final result = service.estimate('m2_taksim', 'm2_taksim');

      expect(result.isValid, isFalse);
      expect(result.error, RouteError.sameStation);
      expect(result.message, isNotNull);
    });

    test('bilinmeyen istasyon reddedilir', () {
      final result = service.estimate('m2_taksim', 'yok_boyle_durak');
      expect(result.error, RouteError.unknownStation);
    });

    test('ileri yön süresi doğru toplanır', () {
      // Taksim(4) -> Levent(8): M2'de kenar 137 sn, 4 kenar = 548 sn ≈ 9 dk
      final result = service.estimate('m2_taksim', 'm2_levent');

      expect(result.isValid, isTrue);
      expect(result.journey!.estimatedSeconds, 4 * 137);
      expect(result.journey!.estimatedMinutes, 9);
      expect(result.journey!.stopCount, 4);
    });

    test('farklı hatlardaki duraklar reddedilir (MVP: aktarma yok)', () {
      final result = service.estimate('m2_taksim', 'm4_kadikoy');
      expect(result.error, RouteError.differentLines);
      expect(result.message, contains('aynı hatta'));
    });

    test('ters yön aynı süreyi verir', () {
      final forward = service.estimate('m2_taksim', 'm2_levent').journey!;
      final reverse = service.estimate('m2_levent', 'm2_taksim').journey!;

      expect(reverse.estimatedMinutes, forward.estimatedMinutes);
      expect(reverse.origin.id, 'm2_levent');
      expect(reverse.destination.id, 'm2_taksim');
    });

    test('kenar süresi hatta göre değişir', () {
      // Süreler resmi sefer süresinden türetiliyor; her hat farklı.
      final m2 = service.estimate('m2_taksim', 'm2_osmanbey').journey!;
      final m9 = service.estimate('m9_atakoy', 'm9_yenibosna').journey!;

      expect(m2.estimatedSeconds, 137);
      expect(m9.estimatedSeconds, 120);
      expect(
        m2.estimatedSeconds,
        isNot(m9.estimatedSeconds),
        reason: 'tek tip 2 dk varsayımına geri dönülmemeli',
      );
    });

    test('uçtan uca rota resmi sefer süresini verir', () {
      // M2 resmi tek yön sefer süresi: 32 dakika.
      final result = service.estimate('m2_yenikapi', 'm2_haciosman');

      expect(result.journey!.estimatedMinutes, 32);
      expect(result.journey!.stopCount, 14);
      expect(result.journey!.difficulty, DifficultyProfiles.long);
    });

    test('en uzun hat maraton profiline düşer', () {
      // M4 Kadıköy -> Sabiha Gökçen: resmi 52 dakika.
      final result = service.estimate(
        'm4_kadikoy',
        'm4_sabiha_gokcen_havalimani',
      );

      expect(result.journey!.estimatedMinutes, 52);
      expect(result.journey!.difficulty, DifficultyProfiles.marathon);
    });

    test('komşu duraklar en kısa rotayı verir', () {
      final result = service.estimate('m2_taksim', 'm2_osmanbey');
      expect(result.journey!.estimatedMinutes, 2);
      expect(result.journey!.difficulty, DifficultyProfiles.mini);
    });
  });

  group('difficultyFor sınırları', () {
    test(
      '5 dk -> Mini',
      () => expect(difficultyFor(5), DifficultyProfiles.mini),
    );
    test(
      '6 dk -> Kısa',
      () => expect(difficultyFor(6), DifficultyProfiles.short),
    );
    test(
      '10 dk -> Kısa',
      () => expect(difficultyFor(10), DifficultyProfiles.short),
    );
    test(
      '11 dk -> Standart',
      () => expect(difficultyFor(11), DifficultyProfiles.standard),
    );
    test(
      '20 dk -> Standart',
      () => expect(difficultyFor(20), DifficultyProfiles.standard),
    );
    test(
      '21 dk -> Uzun',
      () => expect(difficultyFor(21), DifficultyProfiles.long),
    );
    test(
      '35 dk -> Uzun',
      () => expect(difficultyFor(35), DifficultyProfiles.long),
    );
    test(
      '36 dk -> Maraton',
      () => expect(difficultyFor(36), DifficultyProfiles.marathon),
    );
    test(
      'çok uzun rota maraton ile sınırlanır',
      () => expect(difficultyFor(500), DifficultyProfiles.marathon),
    );
  });

  group('metro datası', () {
    test('on metro hattı yüklendi', () {
      final ids = repository.lines().map((l) => l.id).toList();
      expect(ids, <String>[
        'M1A',
        'M1B',
        'M2',
        'M3',
        'M4',
        'M5',
        'M6',
        'M7',
        'M8',
        'M9',
      ]);
    });

    test('her hattın istasyon sırası boşluksuz', () {
      for (final line in repository.lines()) {
        final stations = repository.stationsOfLine(line.id);
        expect(stations, isNotEmpty, reason: '${line.id} boş');
        for (var i = 0; i < stations.length; i++) {
          expect(stations[i].order, i, reason: '${line.id} sırası bozuk');
        }
      }
    });

    test('her hat için komşu çift sayısı kadar kenar var', () {
      final expected = repository
          .lines()
          .map((l) => repository.stationsOfLine(l.id).length - 1)
          .reduce((a, b) => a + b);
      expect(repository.edges().length, expected);
    });

    test('istasyon id’leri şehir genelinde benzersiz', () {
      final ids = repository.stations().map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('her hattın resmi rengi ve sefer süresi var', () {
      for (final line in repository.lines()) {
        expect(line.oneWayMinutes, greaterThan(0), reason: line.id);
        expect(line.color.a, 1.0, reason: '${line.id} rengi opak olmalı');
        expect(line.name, isNotEmpty, reason: line.id);
      }
    });

    test('uçtan uca süre resmi sefer süresine yakın', () {
      // Kenarlar yuvarlandığı için birkaç saniye sapma kabul edilebilir.
      for (final line in repository.lines()) {
        final stations = repository.stationsOfLine(line.id);
        final journey = service
            .estimate(stations.first.id, stations.last.id)
            .journey!;
        expect(
          journey.estimatedMinutes,
          closeTo(line.oneWayMinutes, 1),
          reason: line.id,
        );
      }
    });
  });

  group('Türkçe biçimlendirme', () {
    test('büyük harf i -> İ, ı -> I', () {
      expect(Formatters.upperTr('Gidilecek Yer'), 'GİDİLECEK YER');
      expect(Formatters.upperTr('Çıkış Noktası'), 'ÇIKIŞ NOKTASI');
      expect(Formatters.upperTr('İTÜ-Ayazağa'), 'İTÜ-AYAZAĞA');
    });

    test('skor binlik ayracı', () {
      expect(Formatters.score(1400), '1.400');
      expect(Formatters.score(520), '520');
    });
  });
}
