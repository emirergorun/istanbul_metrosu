import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/audio/audio_service.dart';
import 'core/storage/local_store.dart';
import 'data/metro/metro_repository.dart';

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

  // Metro verisi uygulama paketinden okunur; network yok.
  //
  // Veri olmadan uygulamanın yapabileceği hiçbir şey yok: hat seçici de,
  // rota hesabı da buna dayanıyor. Korumasız bırakılırsa dosya bozulduğunda
  // uygulama boş ekranla ölüyor ve kullanıcı nedenini göremiyor.
  final MetroDataset metro;
  try {
    metro = await MetroDataset.load();
  } catch (error, stack) {
    debugPrint('Metro verisi yüklenemedi: $error\n$stack');
    runApp(const MetroDataErrorApp());
    return;
  }

  final audio = AudioService()
    ..enabled = store.soundEnabled
    ..musicEnabled = store.musicEnabled;
  await audio.init();

  runApp(MetroGameApp(store: store, audio: audio, metro: metro));
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
