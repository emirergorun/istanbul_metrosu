import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/data/metro/metro_repository.dart';
import 'package:istanbul_metro_game/features/journey/models/station.dart';

import '../helpers/metro_fixture.dart';

/// `canonicalId` keşif sisteminin temeli.
///
/// Fiziksel durak kimliği yanlışsa hata sessizdir: sayaç tutar, ekran
/// çizilir, yalnızca **yanlış** sayar. Aktarma durağı iki kez sayılır ya da
/// iki ayrı durak tek keşif olur. Bu testler o sessiz hatayı veri
/// dosyasının kendisinde yakalar.
void main() {
  final repository = MetroFixture.load();
  final stations = repository.stations();

  group('metro.json — fiziksel durak kimliği', () {
    test('her durağın canonicalId alanı dolu', () {
      for (final station in stations) {
        expect(
          station.canonicalId,
          isNotEmpty,
          reason: '${station.id} durağında canonicalId boş',
        );
      }
    });

    test('farklı adlar aynı canonicalId’yi paylaşamaz', () {
      // Slug üretimi Türkçe karakterleri sadeleştiriyor; iki farklı durak
      // adının aynı slug’a düşmesi mümkün. O gün iki ayrı durak tek keşif
      // olur ve toplam sessizce küçülür.
      final namesById = <String, Set<String>>{};
      for (final station in stations) {
        (namesById[station.canonicalId] ??= <String>{}).add(station.name);
      }

      final collisions = <String, Set<String>>{
        for (final entry in namesById.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      };

      expect(
        collisions,
        isEmpty,
        reason:
            'Aynı canonicalId farklı adlara verilmiş: $collisions. '
            'Veri dosyasında ilgili duraklara ayırt edici bir canonicalId '
            'yazılmalı.',
      );
    });

    test('aynı ad her hatta aynı canonicalId’yi taşır', () {
      // Tersi de doğru olmalı: Yenikapı M1A’da başka, M2’de başka bir
      // kimlik taşırsa aktarma çalışmaz, durak iki kez keşfedilir.
      final idsByName = <String, Set<String>>{};
      for (final station in stations) {
        (idsByName[station.name] ??= <String>{}).add(station.canonicalId);
      }

      final split = <String, Set<String>>{
        for (final entry in idsByName.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      };

      expect(
        split,
        isEmpty,
        reason: 'Aynı durak adı farklı canonicalId taşıyor: $split',
      );
    });

    test('kayıt sayısı ile fiziksel durak sayısı beklenen ilişkide', () {
      final unique = stations.map((Station s) => s.canonicalId).toSet();
      // Aktarma durakları birden çok hatta geçtiği için kayıt sayısı her
      // zaman fiziksel durak sayısından büyüktür.
      expect(
        unique.length,
        lessThan(stations.length),
        reason: 'Hiç aktarma durağı yok gibi görünüyor; veri şüpheli.',
      );
      expect(
        stations.length - unique.length,
        18,
        reason:
            'Aktarma kaydı sayısı değişti. Veri bilerek güncellendiyse bu '
            'sayı da güncellenmeli; değilse bir durak kimliği kaymış '
            'olabilir.',
      );
    });
  });

  group('metro.json — ayrıştırma', () {
    test('canonicalId eksikse hangi durak olduğu söylenir', () {
      final raw =
          jsonDecode(File('assets/data/metro.json').readAsStringSync())
              as Map<String, dynamic>;
      final lines = raw['lines'] as List<dynamic>;
      final firstLine = lines.first as Map<String, dynamic>;
      final firstStation =
          (firstLine['stations'] as List<dynamic>).first
              as Map<String, dynamic>;
      final brokenId = firstStation['id'] as String;
      firstStation.remove('canonicalId');

      expect(
        () => MetroDataset.parse(jsonEncode(raw)),
        throwsA(
          isA<FormatException>().having(
            (FormatException e) => e.message,
            'mesaj',
            allOf(contains(brokenId), contains('canonicalId')),
          ),
        ),
      );
    });

    test('boş canonicalId de reddedilir', () {
      final raw =
          jsonDecode(File('assets/data/metro.json').readAsStringSync())
              as Map<String, dynamic>;
      final lines = raw['lines'] as List<dynamic>;
      final firstLine = lines.first as Map<String, dynamic>;
      final firstStation =
          (firstLine['stations'] as List<dynamic>).first
              as Map<String, dynamic>;
      firstStation['canonicalId'] = '';

      expect(
        () => MetroDataset.parse(jsonEncode(raw)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
