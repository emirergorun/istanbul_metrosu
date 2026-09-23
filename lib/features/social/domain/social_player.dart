import 'package:flutter/foundation.dart';

import 'friend_code.dart';

/// Kimliğin nereden geldiği.
///
/// Sıra **yetki sırası değil, köken bilgisi**: oyunun sosyal katmanı her
/// durumda çalışır, platform kimliği yalnızca görünen adı zenginleştirir.
enum PlayerIdentitySource {
  /// Cihazda üretilmiş ad ve kod. Varsayılan ve her zaman kullanılabilir.
  local,

  /// Game Center'dan gelen görünen ad.
  gameCenter,

  /// Play Games'ten gelen görünen ad.
  playGames,
}

/// Paylaşılabilir oyuncu kimliği.
///
/// **Yalnızca gösterime güvenli alanlar.** E-posta, gerçek ad, telefon,
/// cihaz kimliği, ham Game Center / Play Games kimlikleri ve arka uç
/// belirteçleri burada yer almaz ve QR'a da girmez.
///
/// [code] kimliğin makine tarafı, [displayName] insan tarafı. İkisi ayrı:
/// ad sözlükten üretiliyor ve bir kez seçiliyor, kod ise sabit.
@immutable
class SocialPlayer {
  const SocialPlayer({
    required this.code,
    required this.displayName,
    this.source = PlayerIdentitySource.local,
    this.stationsDiscovered = 0,
    this.linesCompleted = 0,
  });

  /// Kanonik (tiresiz) arkadaş kodu.
  final String code;

  /// Ekranda görünen ad.
  final String displayName;

  final PlayerIdentitySource source;

  /// Keşfedilen durak sayısı — kartta gösterilen tek istatistik.
  ///
  /// QR ile taşınır ve karşı tarafta **anlık değil o andaki** değerdir;
  /// arayüz bunu "şu an" diye sunmaz.
  final int stationsDiscovered;

  /// Tamamlanan hat sayısı.
  final int linesCompleted;

  /// Keşfe göre verilen unvan.
  ///
  /// Uydurma bir rütbe sistemi değil: tek girdisi keşfedilen durak sayısı,
  /// yani oyuncunun gerçekten yaptığı iş. Eşikler Yolculuk Kartı'ndaki İstanbul
  /// Kâşifi başarımlarıyla aynı basamaklarda.
  String get title => switch (stationsDiscovered) {
    >= 50 => 'İstanbul Kâşifi',
    >= 25 => 'Hat Gezgini',
    >= 10 => 'Sık Yolcu',
    >= 1 => 'Yeni Yolcu',
    _ => 'Peronda',
  };

  String get formattedCode => FriendCode.format(code);

  SocialPlayer copyWith({
    String? displayName,
    PlayerIdentitySource? source,
    int? stationsDiscovered,
    int? linesCompleted,
  }) => SocialPlayer(
    code: code,
    displayName: displayName ?? this.displayName,
    source: source ?? this.source,
    stationsDiscovered: stationsDiscovered ?? this.stationsDiscovered,
    linesCompleted: linesCompleted ?? this.linesCompleted,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SocialPlayer && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'SocialPlayer($formattedCode, $displayName)';
}
