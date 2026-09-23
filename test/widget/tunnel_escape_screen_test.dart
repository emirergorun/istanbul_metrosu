import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/application/escape_progress_controller.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/presentation/escape_board_view.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/presentation/escape_painter.dart';
import 'package:istanbul_metro_game/features/games/tunnel_escape/presentation/tunnel_escape_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/journey_harness.dart';
import '../helpers/metro_fixture.dart';

/// Tünele Kaç'ın oyuncuya görünen akışı: harita → bölüm → sürükle →
/// tünel → panel → sonraki durak.
///
/// Bölüm 1 elle tasarlandı ve düzeni sabit: kırmızı metro 3. satırın
/// solunda, tek beyaz metro 5. sütunda (satır 3-4). Testler hücre
/// koordinatlarını buradan alıyor.
void main() {
  late LocalStore store;
  late EscapeProgressController progress;
  final metro = MetroFixture.load();
  final journey = RouteService(
    metro,
  ).estimate('m2_taksim', 'm2_levent').journey!;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = LocalStore();
    await store.init();
    progress = EscapeProgressController(store: store);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1179, 2556),
    double pixelRatio = 3,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: AudioService(),
        metro: metro,
        routeService: RouteService(metro),
        escapeProgress: progress,
        child: withJourney(
          store: store,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: TunnelEscapeScreen(journey: journey),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Tahtadaki hücrenin ekran merkezi.
  Offset cellCenter(WidgetTester tester, int row, int col) {
    final rect = tester.getRect(find.byKey(escapeBoardKey));
    final geometry = EscapeGeometry.fit(rect.size, 6, 6);
    return rect.topLeft +
        geometry.origin +
        Offset((col + 0.5) * geometry.cell, (row + 0.5) * geometry.cell);
  }

  double cellSize(WidgetTester tester) {
    final rect = tester.getRect(find.byKey(escapeBoardKey));
    return EscapeGeometry.fit(rect.size, 6, 6).cell;
  }

  Future<void> openFirstLevel(WidgetTester tester) async {
    await tester.tap(find.text('BÖLÜM 1 · BAŞLA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> drag(WidgetTester tester, Offset from, Offset by) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    // Parmak yavaş yavaş kayar: metro her karede izlesin.
    const steps = 6;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(by / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  testWidgets('harita açılır, sıradaki durak bölüm 1', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester);

    expect(find.text('TÜNELE KAÇ'), findsOneWidget);
    expect(find.text('0/60 bölüm · 0 yıldız'), findsOneWidget);
    expect(find.text('BÖLÜM 1 · BAŞLA'), findsOneWidget);
    // Bölüm 1 gerçek istasyon: M2'nin ilk durağı.
    expect(find.text('Yenikapı'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp(r'Bölüm 2, .*kilitli')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('bölüm sürükleyerek çözülür, panel çıkar, sonraki durak açılır', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openFirstLevel(tester);

    expect(find.byKey(escapeBoardKey), findsOneWidget);
    expect(find.text('BÖLÜM 1'), findsOneWidget);

    final cell = cellSize(tester);
    // Beyaz metroyu bir hücre aşağı: kırmızının yolu açılır.
    await drag(tester, cellCenter(tester, 2, 4), Offset(0, cell));
    // Kırmızıyı tünele: dört hücre sağa, tek sürükleyiş.
    await drag(tester, cellCenter(tester, 2, 0), Offset(cell * 4.2, 0));

    // Tünel animasyonu, sonra panel.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('HAT AÇILDI'), findsOneWidget);
    expect(find.text('2 HAMLE'), findsOneWidget);
    expect(progress.isCompleted(1), isTrue);
    expect(progress.recordOf(1)!.bestStars, 3);

    await tester.tap(find.text('SONRAKİ DURAK'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('BÖLÜM 2'), findsOneWidget);
    expect(find.text('HAT AÇILDI'), findsNothing);
  });

  testWidgets('dik yöndeki sürükleme metroyu oynatmaz', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester);
    await openFirstLevel(tester);

    final cell = cellSize(tester);
    // Kırmızı yatay: yukarı sürüklemek hiçbir şey yapmaz.
    await drag(tester, cellCenter(tester, 2, 0), Offset(0, -cell * 1.5));
    expect(find.bySemanticsLabel('0 hamle'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('geri al ve baştan düğmeleri çalışır', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester);
    await openFirstLevel(tester);

    final cell = cellSize(tester);
    await drag(tester, cellCenter(tester, 2, 0), Offset(cell * 2, 0));
    expect(find.bySemanticsLabel('1 hamle'), findsOneWidget);

    await tester.tap(find.text('GERİ AL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.bySemanticsLabel('0 hamle'), findsOneWidget);

    await drag(tester, cellCenter(tester, 2, 4), Offset(0, cell));
    await drag(tester, cellCenter(tester, 2, 0), Offset(cell, 0));
    expect(find.bySemanticsLabel('2 hamle'), findsOneWidget);

    await tester.tap(find.text('BAŞTAN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.bySemanticsLabel('0 hamle'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('haritaya dönüş düğmesi bölümü kapatır, koşu sürer', (
    tester,
  ) async {
    await pumpScreen(tester);
    await openFirstLevel(tester);
    await tester.tap(find.bySemanticsLabel('Hat haritasına dön'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('BÖLÜM 1 · BAŞLA'), findsOneWidget);
  });

  for (final device in <(String, Size, double)>[
    ('iPhone SE', const Size(750, 1334), 2),
    ('iPhone 15', const Size(1179, 2556), 3),
    ('iPhone 15 Pro Max', const Size(1290, 2796), 3),
    ('Android 20:9', const Size(1080, 2400), 2.625),
  ]) {
    testWidgets('${device.$1}: harita ve tahta taşmıyor', (tester) async {
      await pumpScreen(tester, size: device.$2, pixelRatio: device.$3);
      expect(tester.takeException(), isNull);

      await openFirstLevel(tester);
      expect(tester.takeException(), isNull);

      // Tahta kare ve yeterince büyük: parmak için hücre en az 44 pt.
      final cell = cellSize(tester);
      expect(cell, greaterThanOrEqualTo(44), reason: device.$1);
    });
  }
}
