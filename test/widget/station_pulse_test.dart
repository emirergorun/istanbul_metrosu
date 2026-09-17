import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

class _SilentAudio extends AudioService {
  final List<GameSound> played = <GameSound>[];

  @override
  void play(GameSound sound) => played.add(sound);
}

/// Durak geçişi oyuncuya görünür olmalı.
///
/// Eskiden yalnızca **bonuslu** duraklar bildiriliyordu: o duraktan beri
/// satır temizlemeyen oyuncu için ilerleme çubuğu sessizce kayıyor, "bir
/// durak daha geçtim" hissi hiç oluşmuyordu.
void main() {
  final metro = MetroFixture.load();

  testWidgets('durak geçilince adı bildirilir ve üst etiket ilerler', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final audio = _SilentAudio();
    final routes = RouteService(metro);
    // Taksim -> Levent: aradaki ilk durak Osmanbey.
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: audio,
        metro: metro,
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: GameScreen(journey: journey),
        ),
      ),
    );

    // Yolculuk başında tren biniş durağından ayrılmış sayılır.
    expect(find.text('Taksim'), findsOneWidget);
    expect(find.text('Sonraki durak: Osmanbey'), findsOneWidget);

    // Hiç hamle yapılmadan ilk durağı geç: bonus kazanılmaz, bildirim yine
    // de çıkmalı.
    final perStop = journey.estimatedSeconds ~/ journey.stopCount;
    for (var i = 0; i <= perStop; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(
      find.text('Osmanbey'),
      findsWidgets,
      reason: 'varılan durağın adı bildirimde ve üst etikette',
    );
    expect(
      audio.played.where((s) => s == GameSound.station),
      isNotEmpty,
      reason: 'bonussuz durak da ses çalar',
    );
    expect(find.text('Sonraki durak: Şişli-Mecidiyeköy'), findsOneWidget);

    // Bildirim kalıcı değil: kısa süre sonra kalkar, oyun akışını kesmez.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
