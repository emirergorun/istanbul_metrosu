import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Yakalanan bir hata.
@immutable
class ReportedError {
  const ReportedError({
    required this.message,
    required this.when,
    this.context,
  });

  factory ReportedError.fromJson(Map<String, dynamic> json) => ReportedError(
    message: json['message'] as String? ?? '',
    when: DateTime.tryParse(json['when'] as String? ?? '') ?? DateTime(2026),
    context: json['context'] as String?,
  );

  final String message;
  final DateTime when;

  /// Hatanın hangi katmandan geldiği (`widget`, `platform`).
  final String? context;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'message': message,
    'when': when.toIso8601String(),
    if (context != null) 'context': context,
  };
}

/// Çökme ve yakalanmamış hata kaydı.
///
/// Kullanıcının telefonunda çöken uygulama geliştiricinin makinesinde
/// çökmez: farklı iOS sürümü, farklı ekran, düşük bellek, beklenmedik
/// veri. Çökme raporu olmadan tek haber kaynağı mağaza yorumudur — ve o
/// yorum zaten verilmiş bir yıldızdır.
///
/// Bu gerçekleme **hiçbir yere bağlanmıyor**: son [maxEntries] hatayı
/// cihazda tutuyor, oyuncu ayarlardan görüp paylaşabiliyor. Sentry ya da
/// Crashlytics eklendiğinde [onError] aynı yere bir satır daha ekler;
/// uygulamanın geri kalanı değişmez.
class ErrorReporter {
  ErrorReporter({required this.load, required this.save});

  /// Kayıttan okunan ham JSON; yoksa `null`.
  final String? Function() load;

  /// Kaydı yazar.
  final Future<void> Function(String raw) save;

  /// Cihazda tutulan en fazla hata sayısı.
  ///
  /// Sınır bilinçli: bu bir günlük dosyası değil, "son ne oldu"
  /// penceresi. Sınırsız büyüyen bir liste tercih dosyasını şişirir.
  static const int maxEntries = 20;

  final List<ReportedError> _entries = <ReportedError>[];
  bool _loaded = false;

  /// En yeniden eskiye doğru kayıtlar.
  List<ReportedError> get entries {
    _ensureLoaded();
    return List<ReportedError>.unmodifiable(_entries);
  }

  /// Flutter'ın hata kancalarını bağlar.
  ///
  /// `runApp` öncesinde bir kez çağrılır. İki ayrı kaynak var: widget
  /// ağacındaki hatalar (`FlutterError.onError`) ve zone dışındaki
  /// asenkron hatalar (`PlatformDispatcher.onError`).
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exceptionAsString(), context: 'widget');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error.toString(), context: 'platform');
      // `false` dönmek hatayı yutmaz; varsayılan işlemeye bırakır.
      return false;
    };
  }

  /// Bir hatayı kaydeder.
  void record(String message, {String? context}) {
    _ensureLoaded();
    _entries.insert(
      0,
      ReportedError(
        // Uzun yığın izleri tercih dosyasını şişirir; ilk satır hatayı
        // tanımaya yetiyor.
        message: message.length > 400 ? message.substring(0, 400) : message,
        when: DateTime.now(),
        context: context,
      ),
    );
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    _persist();
  }

  /// Kayıtları siler.
  Future<void> clear() async {
    _entries.clear();
    _loaded = true;
    await save(jsonEncode(<Map<String, dynamic>>[]));
  }

  /// Paylaşılabilir özet — destek istendiğinde oyuncu bunu gönderir.
  String asShareText() {
    _ensureLoaded();
    if (_entries.isEmpty) return 'Kayıtlı hata yok.';
    return _entries
        .take(5)
        .map((e) => '${e.when.toIso8601String()} · ${e.context} · ${e.message}')
        .join('\n\n');
  }

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = load();
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      for (final item in decoded) {
        _entries.add(ReportedError.fromJson(item as Map<String, dynamic>));
      }
    } catch (error) {
      debugPrint('ErrorReporter okunamadı: $error');
      _entries.clear();
    }
  }

  void _persist() {
    unawaited(save(jsonEncode(_entries.map((e) => e.toJson()).toList())));
  }
}
