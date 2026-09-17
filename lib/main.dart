import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'core/audio/audio_service.dart';
import 'core/storage/local_store.dart';
import 'data/metro/metro_repository.dart';
import 'data/questions/question_repository.dart';

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

  // Bilgi soruları oyunun omurgası değil çeşnisi: dosya yoksa ya da
  // bozuksa havuz boş gelir, Metro Bilgi üretilen sorularla oynanır.
  // Bu yüzden metro verisinin aksine hata ekranı göstermez.
  final questions = await QuestionDataset.load();

  final audio = AudioService()
    ..enabled = store.soundEnabled
    ..musicEnabled = store.musicEnabled;
  // `runApp`'ı bunun bitmesini BEKLEMEDEN çağır. Web'de her ses dosyası
  // tarayıcının otomatik oynatma kısıtlaması yüzünden ayrı ayrı 30 saniye
  // zaman aşımına düşebiliyor (bkz. AudioService.init dokümantasyonu);
  // altı sesin hepsi sırayla timeout olursa açılış ~3 dakika bomboş
  // ekranda kalıyordu. `AudioService.play`/`resumeMusic` zaten `_ready`
  // olmadan sessizce hiçbir şey yapmıyor, o yüzden arka planda yüklenmesi
  // güvenli — kullanıcı arayüzü görmek için sesin yüklenmesini beklemesin.
  unawaited(audio.init());

  runApp(
    MetroGameApp(
      store: store,
      audio: audio,
      metro: metro,
      questions: questions,
    ),
  );
}

/// Gömülü fontların lisans metinlerini kaydeder.
///
/// OFL, yazı tipiyle birlikte lisansının da dağıtılmasını şart koşar; bu
/// sayede metinler uygulamanın "Lisanslar" ekranında görünür.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const <String>[
      'Bungee',
    ], await rootBundle.loadString('assets/fonts/OFL-Bungee.txt'));
    yield LicenseEntryWithLineBreaks(const <String>[
      'Plus Jakarta Sans',
    ], await rootBundle.loadString('assets/fonts/OFL-PlusJakartaSans.txt'));
  });
}
