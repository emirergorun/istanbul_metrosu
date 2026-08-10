import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  // Tek elle, dikey kullanım hedefleniyor.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  // Tek local bağımlılık: en iyi skor ve haptic tercihi.
  final store = LocalStore();
  await store.init();

  runApp(MetroGameApp(store: store));
}

/// Gömülü fontların SIL Open Font License metinlerini kaydeder.
///
/// OFL, yazı tipleriyle birlikte lisansın da dağıtılmasını şart koşar;
/// bu sayede metinler uygulamanın "Lisanslar" ekranında görünür.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Raleway',
    ], await rootBundle.loadString('assets/fonts/OFL-Raleway.txt'));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Open Sans',
    ], await rootBundle.loadString('assets/fonts/OFL-OpenSans.txt'));
  });
}
