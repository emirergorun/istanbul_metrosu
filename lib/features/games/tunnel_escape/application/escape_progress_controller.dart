import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/storage/local_store.dart';
import '../domain/escape_progress.dart';

/// Bir bitirişin kayda etkisi — tamamlanma paneli bunu anlatır.
@immutable
class EscapeRecordResult {
  const EscapeRecordResult({
    required this.previous,
    required this.current,
    required this.unlockedNext,
  });

  /// Bu bitirişten önceki kayıt; ilk bitirişte `null`.
  final EscapeLevelRecord? previous;

  final EscapeLevelRecord current;

  /// Bu bitiriş bir sonraki bölümü **ilk kez** mi açtı?
  final bool unlockedNext;

  bool get isFirstCompletion => previous == null;

  /// En iyi hamle bu bitirişte mi kırıldı? İlk bitiriş de rekordur.
  bool isNewBestFor(int moves) =>
      previous == null || moves < previous!.bestMoves;

  int get previousBestStars => previous?.bestStars ?? 0;
}

/// Tünele Kaç'ın bölüm ilerlemesi — uygulama ömrü boyunca tek.
///
/// Yolculuk Kartı'nın rozetleri bunu **okur**: bitirilen bölüm, toplam
/// yıldız, kusursuz sefer. Rozetler kendi sayacını tutmuyor, tek kaynak
/// burası.
///
/// Kayıt bitirişte hemen yazılır ve beklenmez: diske yazmak bir kareyi
/// bekletmemeli. Arka plana düşerken [flush] beklenerek çağrılır.
class EscapeProgressController extends ChangeNotifier {
  EscapeProgressController({this.store})
    : _progress = EscapeProgress.decode(store?.escapeProgressRaw);

  final LocalStore? store;

  EscapeProgress _progress;

  EscapeProgress get progress => _progress;

  EscapeLevelRecord? recordOf(int level) => _progress.recordOf(level);

  bool isUnlocked(int level) => _progress.isUnlocked(level);

  bool isCompleted(int level) => _progress.isCompleted(level);

  int get completedCount => _progress.completedCount;

  int get totalStars => _progress.totalStars;

  int get perfectCount => _progress.perfectCount;

  int nextLevel(int levelCount) => _progress.nextLevel(levelCount);

  /// Bitirişi kaydeder ve etkisini döner.
  ///
  /// Kilitli bir bölüm bitirilemez; arayüz buna izin vermiyor ama kayıt
  /// katmanı da kendi kuralını korur.
  EscapeRecordResult record({
    required int level,
    required int moves,
    required int stars,
    required bool perfect,
  }) {
    if (!_progress.isUnlocked(level)) {
      throw StateError('Bölüm $level kilitli');
    }
    final previous = _progress.recordOf(level);
    final nextWasLocked = !_progress.isUnlocked(level + 1);
    _progress = _progress.withCompletion(
      level: level,
      moves: moves,
      stars: stars,
      perfect: perfect,
    );
    unawaited(_persist());
    notifyListeners();
    return EscapeRecordResult(
      previous: previous,
      current: _progress.recordOf(level)!,
      unlockedNext: nextWasLocked,
    );
  }

  Future<void> _persist() async {
    try {
      await store?.saveEscapeProgress(_progress.encode());
    } catch (error, stack) {
      debugPrint('Tünele Kaç kaydı yazılamadı: $error\n$stack');
    }
  }

  /// Bekleyen yazımı tamamlar — uygulama arka plana düşerken.
  Future<void> flush() => _persist();

  @visibleForTesting
  void debugSetProgress(EscapeProgress progress) {
    _progress = progress;
    notifyListeners();
  }
}
