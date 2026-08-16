import 'package:flutter/material.dart';

/// Yolculuk sırasında oynanabilecek bir oyun.
///
/// Uygulama tek oyunla başladı; artık yolculuk ve oyun ayrı seçimler.
/// Rota "ne kadar oynayacağını", oyun ise "ne oynayacağını" belirler.
@immutable
class MiniGame {
  const MiniGame({
    required this.id,
    required this.name,
    required this.tagline,
    required this.icon,
    this.isAvailable = false,
  });

  /// Kalıcı kimlik — kayıtlarda ve rekorlarda kullanılabilir, değiştirilmemeli.
  final String id;

  final String name;

  /// Kartta adın altında görünen tek cümlelik tanım.
  final String tagline;

  final IconData icon;

  /// `false` ise kart kilitli görünür ve seçilemez.
  final bool isAvailable;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MiniGame && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MiniGame($id, ${isAvailable ? "açık" : "kilitli"})';
}

/// Oyun kataloğu.
///
/// Yeni bir oyun eklemek için buraya kayıt eklemek ve `isAvailable`'ı `true`
/// yapmak yeterli; seçim ekranı listeyi olduğu gibi çizer.
///
/// TODO(PROD): Kilitli üç oyunun adları **yer tutucudur**; ürün kararı
/// verildiğinde değiştirilecek. `id` alanları değişmemeli.
class MiniGames {
  const MiniGames._();

  static const MiniGame blocks = MiniGame(
    id: 'blocks',
    name: 'Blok Metro',
    tagline: 'Parçaları yerleştir, dolan satır ve sütunları temizle.',
    icon: Icons.grid_view_rounded,
    isAvailable: true,
  );

  static const MiniGame transfer = MiniGame(
    id: 'transfer',
    name: 'Aktarma',
    tagline: 'Yolcuları doğru hatta yönlendir.',
    icon: Icons.alt_route_rounded,
  );

  static const MiniGame signal = MiniGame(
    id: 'signal',
    name: 'Sinyal',
    tagline: 'Işıkları zamanında çevir, trenleri çarpıştırma.',
    icon: Icons.traffic_rounded,
  );

  static const MiniGame wagon = MiniGame(
    id: 'wagon',
    name: 'Vagon',
    tagline: 'Vagonları en verimli şekilde doldur.',
    icon: Icons.view_week_rounded,
  );

  static const List<MiniGame> all = <MiniGame>[blocks, transfer, signal, wagon];
}
