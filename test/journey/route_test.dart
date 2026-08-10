import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/utils/formatters.dart';
import 'package:istanbul_metro_game/data/metro/metro_repository.dart';
import 'package:istanbul_metro_game/features/journey/models/difficulty_profile.dart';
import 'package:istanbul_metro_game/features/journey/services/difficulty_mapper.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';

void main() {
  const repository = BundledMetroRepository();
  const service = RouteService(repository);

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
      // Taksim(4) -> Levent(8): 2+2+2+2 = 8 dk
      final result = service.estimate('m2_taksim', 'm2_levent');

      expect(result.isValid, isTrue);
      expect(result.journey!.estimatedMinutes, 8);
      expect(result.journey!.stopCount, 4);
    });

    test('ters yön aynı süreyi verir', () {
      final forward = service.estimate('m2_taksim', 'm2_levent').journey!;
      final reverse = service.estimate('m2_levent', 'm2_taksim').journey!;

      expect(reverse.estimatedMinutes, forward.estimatedMinutes);
      expect(reverse.origin.id, 'm2_levent');
      expect(reverse.destination.id, 'm2_taksim');
    });

    test('3 dakikalık kenar hesaba katılır', () {
      // Sanayi Mahallesi(10) -> İTÜ-Ayazağa(11) = 3 dk (tek uzun kenar)
      final result = service.estimate('m2_sanayi_mahallesi', 'm2_itu_ayazaga');
      expect(result.journey!.estimatedMinutes, 3);
    });

    test('uçtan uca rota', () {
      // Yenikapı -> Hacıosman: 13 x 2 dk + 1 x 3 dk = 29 dk
      final result = service.estimate('m2_yenikapi', 'm2_haciosman');

      expect(result.journey!.estimatedMinutes, 29);
      expect(result.journey!.stopCount, 14);
      expect(result.journey!.difficulty, DifficultyProfiles.long);
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
    test('istasyon sırası boşluksuz', () {
      final stations = repository.stations();
      for (var i = 0; i < stations.length; i++) {
        expect(stations[i].order, i);
      }
    });

    test('her komşu çift için kenar var', () {
      final stations = repository.stations();
      expect(repository.edges().length, stations.length - 1);
    });

    test('istasyon id’leri benzersiz', () {
      final ids = repository.stations().map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
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
