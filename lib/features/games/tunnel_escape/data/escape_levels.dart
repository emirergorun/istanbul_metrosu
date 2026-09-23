import '../domain/escape_level.dart';
import 'escape_level_grids.dart';

/// Gönderilen bölümler.
///
/// Veri `escape_level_grids.dart` içinde ızgara metni olarak duruyor; burada
/// yalnız bir kez ayrıştırılıp saklanıyor. Oyunun tamamı cihazda: bölüm
/// indirilmez, çözüm uzunlukları önceden hesaplanıp veriye yazılmıştır.
abstract final class EscapeLevels {
  static final List<EscapeLevel> all = List<EscapeLevel>.unmodifiable(
    escapeLevelData.map((EscapeLevelData data) => data.toLevel()),
  );

  static int get count => all.length;

  /// Numarası verilen bölüm; yoksa `null`.
  static EscapeLevel? byNumber(int number) {
    if (number < 1 || number > all.length) return null;
    return all[number - 1];
  }

  static EscapeLevel get last => all.last;
}
