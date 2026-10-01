import '../domain/merge_drop_state.dart';

/// Birleşme efektlerinin süreleri (milisaniye).
///
/// Toplam his ~250 ms: önce iki eski jeton birleşme noktasına çekilip
/// söner ([pullMs]), aynı anda ince bir halka açılır ([ringMs]); yeni jeton
/// fiziğin kendi şişmesiyle gelir (`DropBall.drawRadius`). Puan yazısı
/// daha uzun kalır ([scoreMs]) ama hızla solar, tahtayı kapatmaz.
abstract final class MergeDropTiming {
  static const int pullMs = 90;
  static const int ringMs = 260;
  static const int scoreMs = 700;
}

/// Ekrandaki tek bir birleşme efekti.
final class MergeEffect {
  MergeEffect(this.event, this.startedAt);

  final MergeDropEvent event;

  /// Efektin başladığı an (efekt saatine göre, milisaniye).
  final int startedAt;
}

/// Birleşme efektlerinin listesi ve saati.
///
/// Efektler fizikten bağımsız bir saatle yürür: oyun her karede yeniden
/// çiziliyor, efekt ilerlemesi bu saatten okunuyor. Süresi dolan efekt
/// kendiliğinden düşer; aynı anda en fazla [_cap] efekt tutulur ki uzun
/// bir zincir bile çizim yükünü büyütmesin.
final class MergeDropEffects {
  final Stopwatch _clock = Stopwatch()..start();
  final List<MergeEffect> _items = <MergeEffect>[];

  static const int _cap = 12;

  int get now => _clock.elapsedMilliseconds;

  void addMerge(MergeDropEvent event) {
    _items.add(MergeEffect(event, now));
    if (_items.length > _cap) _items.removeAt(0);
  }

  /// Süren efektler; bitenler listeden düşer.
  List<MergeEffect> get active {
    final t = now;
    _items.removeWhere((e) => t - e.startedAt > MergeDropTiming.scoreMs);
    return _items;
  }

  void clear() => _items.clear();
}
