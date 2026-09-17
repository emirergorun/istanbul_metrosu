import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/constants/app_constants.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/board.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/clear_result.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/game_screen.dart';
import 'package:istanbul_metro_game/features/games/blocks/presentation/widgets/board_view.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:istanbul_metro_game/features/session/widgets/result_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';

class _RecordingAudio extends AudioService {
  final List<GameSound> played = <GameSound>[];

  @override
  void play(GameSound sound) => played.add(sound);
}

void main() {
  final metro = MetroFixture.load();

  /// Patlamanın her karesini çizer; çizim sırasında hata çıkarsa test düşer.
  Future<void> paintWholeFlash(WidgetTester tester, BoardFlash flash) async {
    final controller = AnimationController(
      vsync: tester,
      duration: AppConstants.lineClearDuration,
    );
    final notifier = ValueNotifier<BoardFlash?>(flash);
    addTearDown(notifier.dispose);
    final preview = ValueNotifier<BoardPreview?>(null);
    addTearDown(preview.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: BoardView(
            board: Board.empty(),
            cellSize: 40,
            preview: preview,
            flash: notifier,
            flashAnimation: controller,
          ),
        ),
      ),
    );

    controller.forward(from: 0);
    for (var i = 0; i <= 50; i++) {
      await tester.pump(AppConstants.lineClearDuration ~/ 50);
    }
    expect(tester.takeException(), isNull);

    // Ticker kontrolü teardown'dan önce çalışıyor; burada kapatılmalı.
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }

  final cellValues = <int, int>{
    for (var c = 0; c < 8; c++) 3 * 8 + c: c % 5 + 1,
    for (var r = 0; r < 8; r++) r * 8 + 5: kBlockerCell,
    // Durakta boşalan satırlar kısmen dolu: boş hücreler de haritada.
    for (var c = 0; c < 8; c++) 0 * 8 + c: c.isEven ? 2 : kEmptyCell,
    for (var c = 0; c < 8; c++) 7 * 8 + c: c < 4 ? 4 : kEmptyCell,
  };

  testWidgets('satır + sütun patlaması, puan ve combo ile çizilir', (
    tester,
  ) async {
    await paintWholeFlash(
      tester,
      BoardFlash(
        rows: const <int>[3],
        columns: const <int>[5],
        cellValues: cellValues,
        originRow: 3,
        originCol: 5.5,
        points: 120,
        combo: 3,
      ),
    );
  });

  testWidgets('kızışmış combo etiketiyle çizilir', (tester) async {
    await paintWholeFlash(
      tester,
      BoardFlash(
        rows: const <int>[3],
        columns: const <int>[5],
        cellValues: cellValues,
        originRow: 3,
        originCol: 5.5,
        points: 940,
        // En üst kızışma eşiğini aşar: "DURDURULAMAZ" çizilir.
        combo: kComboHeatLabels.keys.last + 2,
      ),
    );
  });

  testWidgets('mega temizlik kademe etiketiyle çizilir', (tester) async {
    await paintWholeFlash(
      tester,
      BoardFlash(
        rows: const <int>[0, 3, 7],
        columns: const <int>[5],
        cellValues: cellValues,
        originRow: 3,
        originCol: 5.5,
        points: 520,
        combo: 1,
      ),
    );
  });

  testWidgets('durakta boşalan satır (başlangıç noktası yok) çizilir', (
    tester,
  ) async {
    await paintWholeFlash(
      tester,
      BoardFlash(
        rows: const <int>[0, 7],
        columns: const <int>[],
        cellValues: cellValues,
      ),
    );
  });

  testWidgets('hareketi azalt açıkken sade sönme çizilir', (tester) async {
    await paintWholeFlash(
      tester,
      BoardFlash(
        rows: const <int>[3],
        columns: const <int>[],
        cellValues: cellValues,
        originCol: 0,
        points: 40,
        reduceMotion: true,
      ),
    );
  });

  group('kızışma etiketi', () {
    test('eşiğin altında etiket yok', () {
      expect(comboHeatLabel(kComboHeatLabels.keys.first - 1), isNull);
    });

    test('eşikte ve üstünde o kademenin etiketi', () {
      final first = kComboHeatLabels.entries.first;
      expect(comboHeatLabel(first.key), first.value);
      expect(comboHeatLabel(first.key + 1), first.value);
    });

    test('yüksek combo en üst kademeyi alır', () {
      final last = kComboHeatLabels.entries.last;
      expect(comboHeatLabel(last.key + 50), last.value);
    });

    test('eşikler artan sırada', () {
      final keys = kComboHeatLabels.keys.toList();
      for (var i = 1; i < keys.length; i++) {
        expect(keys[i], greaterThan(keys[i - 1]));
      }
    });
  });

  testWidgets('tekrar oynanan yolculukta varış sesi yine çalar', (
    tester,
  ) async {
    // Regresyon: "tekrar oyna" aynı ekranı kullanıyor ve "varış sesi çalındı"
    // bayrağı sıfırlanmıyordu; ikinci varışta kapı sesi gelmiyordu.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final audio = _RecordingAudio();
    final routes = RouteService(metro);
    final journey = routes.estimate('m2_taksim', 'm2_osmanbey').journey!;

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

    Future<void> rideToArrival() async {
      for (var i = 0; i < journey.estimatedSeconds + 2; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump(const Duration(seconds: 5));
    }

    int arrivals() => audio.played.where((s) => s == GameSound.arrival).length;

    await rideToArrival();
    expect(arrivals(), 1);

    tester.widget<ResultOverlay>(find.byType(ResultOverlay)).onRestart();
    await tester.pump();
    await rideToArrival();
    expect(arrivals(), 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
}
