import 'dart:io';

import 'package:istanbul_metro_game/data/metro/metro_repository.dart';

/// Gerçek `assets/data/metro.json` dosyasını testlerde tek sefer yükler.
///
/// Asset bundle yerine doğrudan dosyadan okunur; böylece hem widget hem de
/// saf unit testlerde binding kurulumu gerekmez.
class MetroFixture {
  const MetroFixture._();

  static MetroDataset? _cached;

  static MetroDataset load() {
    return _cached ??= MetroDataset.parse(
      File('assets/data/metro.json').readAsStringSync(),
    );
  }
}
