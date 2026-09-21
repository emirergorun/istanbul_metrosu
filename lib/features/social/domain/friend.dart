import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../daily/domain/day_stamp.dart';
import 'friend_code.dart';
import 'social_player.dart';

/// Cihazdaki arkadaş kaydı.
///
/// **Bu bir sunucu ilişkisi değil, bir rehber kaydı.** Arka uç yok; birinin
/// kodunu okumak onu *senin* listene ekler, karşı tarafa hiçbir şey
/// göndermez. Arayüz bu yüzden hiçbir yerde "istek gönderildi" demez —
/// söylemediğimiz şey, yapamadığımız şey.
///
/// Karşılıklılık oyuncular arasında kurulur: ikisi de birbirinin kodunu
/// okur. Metroda yan yana oturan iki kişi için bu, sunucudan hızlı ve
/// tamamen çevrimdışı bir yol.
@immutable
class Friend {
  const Friend({
    required this.code,
    required this.displayName,
    required this.addedOn,
    this.stationsDiscovered = 0,
  });

  /// Kanonik arkadaş kodu — kaydın kimliği.
  final String code;

  /// Eklendiği andaki görünen adı.
  final String displayName;

  /// Eklendiği andaki keşif sayısı.
  ///
  /// **Anlık değil, fotoğraf.** Arka uç olmadan karşı tarafın bugünkü
  /// ilerlemesini bilmenin yolu yok; arayüz de bunu güncel diye sunmuyor.
  final int stationsDiscovered;

  final DayStamp addedOn;

  String get formattedCode => FriendCode.format(code);

  SocialPlayer get asPlayer => SocialPlayer(
    code: code,
    displayName: displayName,
    stationsDiscovered: stationsDiscovered,
  );

  Friend copyWith({String? displayName, int? stationsDiscovered}) => Friend(
    code: code,
    displayName: displayName ?? this.displayName,
    stationsDiscovered: stationsDiscovered ?? this.stationsDiscovered,
    addedOn: addedOn,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'name': displayName,
    'stations': stationsDiscovered,
    'added': addedOn.toString(),
  };

  /// Kaydı çözer. Bozuksa `null` — o satır atılır, liste açılmaya devam eder.
  static Friend? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final code = FriendCode.normalize(raw['code'] as String?);
    final name = raw['name'];
    final added = DayStamp.tryParse(raw['added'] as String?);
    if (code == null || name is! String || name.isEmpty || added == null) {
      return null;
    }
    final stations = raw['stations'];
    return Friend(
      code: code,
      displayName: name,
      stationsDiscovered: stations is int && stations > 0 ? stations : 0,
      addedOn: added,
    );
  }

  static String encodeList(List<Friend> friends) =>
      jsonEncode(<Object?>[for (final friend in friends) friend.toJson()]);

  static List<Friend> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <Friend>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <Friend>[];
      return <Friend>[
        for (final entry in decoded)
          if (Friend.fromJson(entry) case final Friend friend) friend,
      ];
    } catch (error) {
      debugPrint('Arkadaş listesi okunamadı: $error');
      return const <Friend>[];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Friend && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Friend($formattedCode, $displayName)';
}

/// Arkadaş ekleme denemesinin sonucu.
///
/// Sessizce başarısız olmak yok: arayüz her durumda oyuncuya ne olduğunu
/// söyleyebilmeli.
enum FriendAddResult {
  added('Arkadaş eklendi'),
  alreadyAdded('Bu oyuncu zaten listende'),
  self('Bu senin kendi kodun'),
  invalid('Kod okunamadı');

  const FriendAddResult(this.message);

  final String message;

  bool get isSuccess => this == FriendAddResult.added;
}
