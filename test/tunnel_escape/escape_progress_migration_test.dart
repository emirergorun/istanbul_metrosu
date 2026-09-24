import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_progress_controller.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/data/escape_level_history.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/data/escape_levels.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/domain/escape_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bölümler yeniden tasarlandığında oyuncunun kaydı ne olur?
///
/// Kural: bitirilen bölüm bitmiş kalır (açılan bölümler kilitlenmez); eski
/// bulmacanın hamle ve yıldızı yeni bulmacayla karşılaştırılmaz.
void main() {
  // Sahte üç bölümlük sürüm: 1 aynı kaldı, 2 ve 3 yenilendi.
  const legacy = <String>['aaaa0001', 'aaaa0002', 'aaaa0003'];
  const current = <int, String>{1: 'aaaa0001', 2: 'bbbb0002', 3: 'bbbb0003'};

  EscapeProgress legacyProgress() => EscapeProgress.decode(
    jsonEncode(<String, Object>{
      'v': 1,
      'levels': <String, Object>{
        '1': <String, Object>{'m': 2, 's': 3, 'w': 1},
        '2': <String, Object>{'m': 4, 's': 3, 'p': 1, 'w': 2},
        '3': <String, Object>{'m': 9, 's': 1, 'w': 1},
      },
    }),
  );

  group('Eşleştirme', () {
    test('aynı kalan bulmacanın sonucu korunur, izi eklenir', () {
      final (progress, changed) = legacyProgress().reconcile(
        current: current,
        legacy: legacy,
      );
      expect(changed, isTrue);
      final one = progress.recordOf(1)!;
      expect(one.bestMoves, 2);
      expect(one.bestStars, 3);
      expect(one.fingerprint, 'aaaa0001');
    });

    test('yenilenen bulmaca taşınır: bitmiş kalır, sonucu silinir', () {
      final (progress, _) = legacyProgress().reconcile(
        current: current,
        legacy: legacy,
      );
      final two = progress.recordOf(2)!;
      expect(progress.isCompleted(2), isTrue);
      expect(progress.isUnlocked(3), isTrue);
      expect(progress.isUnlocked(4), isTrue, reason: 'açılan kilitlenmez');
      expect(two.hasResult, isFalse);
      expect(two.bestMoves, isNull);
      expect(two.bestStars, 0);
      expect(two.perfect, isFalse, reason: 'eski kusursuzluk taşınmaz');
      expect(two.wins, 2, reason: 'oynama geçmişi korunur');
      expect(two.fingerprint, 'bbbb0002');
      // Yıldız toplamı yalnız bugünkü bulmacalardan.
      expect(progress.totalStars, 3);
      expect(progress.completedCount, 3);
    });

    test('eşleşmiş kayıt ikinci kez değişmez', () {
      final (once, _) = legacyProgress().reconcile(
        current: current,
        legacy: legacy,
      );
      final (twice, changed) = once.reconcile(current: current, legacy: legacy);
      expect(changed, isFalse);
      expect(twice, once);
    });

    test('izli kayıt kendi izine göre eşleşir, eski listeye bakmaz', () {
      final progress = const EscapeProgress().withCompletion(
        level: 1,
        moves: 3,
        stars: 3,
        perfect: false,
        fingerprint: 'eski-iz',
      );
      final (next, changed) = progress.reconcile(
        current: current,
        legacy: legacy,
      );
      expect(changed, isTrue);
      expect(next.recordOf(1)!.hasResult, isFalse);
    });
  });

  group('Taşınmış kayıt', () {
    test('kodlanır ve geri çözülür', () {
      final (progress, _) = legacyProgress().reconcile(
        current: current,
        legacy: legacy,
      );
      final restored = EscapeProgress.decode(progress.encode());
      expect(restored, progress);
      expect(restored.recordOf(2)!.hasResult, isFalse);
    });

    test('yıldızlı ama hamlesiz kayıt bozuk sayılır ve atlanır', () {
      final progress = EscapeProgress.decode(
        jsonEncode(<String, Object>{
          'v': 2,
          'levels': <String, Object>{
            '1': <String, Object>{'s': 2, 'w': 1},
            '2': <String, Object>{'m': 3, 's': 3, 'w': 1},
          },
        }),
      );
      expect(progress.isCompleted(1), isFalse);
      expect(progress.isCompleted(2), isTrue);
    });

    test('yeni bulmacadaki ilk bitiriş ilk sonuçtur', () {
      final (migrated, _) = legacyProgress().reconcile(
        current: current,
        legacy: legacy,
      );
      final next = migrated.withCompletion(
        level: 2,
        moves: 12,
        stars: 2,
        perfect: false,
        fingerprint: 'bbbb0002',
      );
      final record = next.recordOf(2)!;
      expect(record.bestMoves, 12, reason: 'eski 4 hamle karşılaştırılmaz');
      expect(record.bestStars, 2);
      expect(record.wins, 3);
    });
  });

  group('Denetleyici', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('açılışta eşleştirir ve yeni biçimi diske yazar', () async {
      final store = LocalStore();
      await store.init();
      await store.saveEscapeProgress(legacyProgress().encode());

      final controller = EscapeProgressController(
        store: store,
        fingerprints: current,
        legacyFingerprints: legacy,
      );
      expect(controller.isCompleted(3), isTrue);
      expect(controller.isUnlocked(4), isTrue);
      expect(controller.recordOf(3)!.hasResult, isFalse);
      await controller.flush();

      final saved = jsonDecode(store.escapeProgressRaw!) as Map;
      expect(saved['v'], EscapeProgress.version);
      final levels = saved['levels'] as Map;
      expect((levels['1'] as Map)['f'], 'aaaa0001');
      expect((levels['3'] as Map).containsKey('m'), isFalse);
    });

    test('taşınmış bölümün ilk bitirişi en iyi ve tam puan sayılır', () {
      final controller =
          EscapeProgressController(
            fingerprints: current,
            legacyFingerprints: legacy,
          )..debugSetProgress(
            legacyProgress().reconcile(current: current, legacy: legacy).$1,
          );
      final result = controller.record(
        level: 2,
        moves: 15,
        stars: 1,
        perfect: false,
      );
      expect(result.isFirstCompletion, isFalse);
      expect(result.isFirstResult, isTrue);
      expect(result.isNewBestFor(15), isTrue);
      expect(result.previousBestStars, 0);
      expect(result.current.fingerprint, 'bbbb0002');
    });

    test('gerçek veri: ilk sürümün öğretici bölümleri korunuyor', () {
      expect(escapeLegacyFingerprints, hasLength(EscapeLevels.count));
      // 1 ve 2 elle tasarlandı ve değişmedi; kayıtları aynen kalmalı.
      expect(escapeLegacyFingerprints[0], EscapeLevels.fingerprints[1]);
      expect(escapeLegacyFingerprints[1], EscapeLevels.fingerprints[2]);
    });
  });
}
