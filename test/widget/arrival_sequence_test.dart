import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/session/widgets/arrival_sequence.dart';

/// Varış sahnesinin sırası: **önce metro gelir, sonra kapı açılır.**
///
/// Regresyon: kapı ekranın ortasında sabit duruyor, yalnızca saydamlığı
/// trenle birlikte artıyordu. Tren daha yolun yarısındayken kapı havada
/// belirmiş oluyor ve sahne "kapı erken geldi" gibi okunuyordu.
void main() {
  const duration = ArrivalSequence.defaultDuration;

  var skipped = 0;

  Future<void> pumpScene(WidgetTester tester) async {
    skipped = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ArrivalSequence(
            accent: Colors.red,
            lineId: 'M2',
            stationName: 'Levent',
            onSkipped: () => skipped++,
            child: const Center(child: Text('SONUÇ')),
          ),
        ),
      ),
    );
    // initState'teki postFrameCallback animasyonu başlatır.
    await tester.pump();
  }

  double centerX(WidgetTester tester, Key key) =>
      tester.getCenter(find.byKey(key)).dx;

  /// İki kapı kanadı arasındaki açıklık.
  double doorGap(WidgetTester tester) {
    final left = tester.getRect(find.byKey(ArrivalSequence.leftDoorKey));
    final right = tester.getRect(find.byKey(ArrivalSequence.rightDoorKey));
    return right.left - left.right;
  }

  Duration at(double fraction) => duration * fraction;

  testWidgets('kapı trenle birlikte gelir, ayrı hareket etmez', (tester) async {
    await pumpScene(tester);

    // Sahnenin başında ikisi de ekranın dışında, aynı hizada.
    final trainStart = centerX(tester, ArrivalSequence.trainKey);
    final doorStart = centerX(tester, ArrivalSequence.doorsKey);

    await tester.pump(at(0.25));
    final trainMid = centerX(tester, ArrivalSequence.trainKey);
    final doorMid = centerX(tester, ArrivalSequence.doorsKey);

    expect(
      trainStart - trainMid,
      closeTo(doorStart - doorMid, 0.5),
      reason: 'kapı ile tren aynı mesafeyi kat etmeli',
    );
    expect(trainMid, lessThan(trainStart), reason: 'tren sağdan geliyor');
  });

  testWidgets('tren yoldayken kapı ekranın ortasında değil', (tester) async {
    await pumpScene(tester);
    await tester.pump(at(0.2));

    final screenCenter = tester.getSize(find.byType(ArrivalSequence)).width / 2;
    expect(
      centerX(tester, ArrivalSequence.doorsKey),
      greaterThan(screenCenter + 40),
      reason: 'kapı hâlâ trenle birlikte sağda olmalı',
    );
  });

  testWidgets('tren durmadan kapı açılmaz', (tester) async {
    await pumpScene(tester);

    // Tren dilimi 0.50'de biter, kapı 0.56'da açılmaya başlar.
    var elapsed = 0.0;
    for (final fraction in <double>[0.1, 0.25, 0.4, 0.52]) {
      await tester.pump(at(fraction - elapsed));
      elapsed = fraction;
      expect(
        doorGap(tester),
        lessThan(1),
        reason: 'kapı $fraction anında kapalı olmalı',
      );
    }
  });

  testWidgets('tren durduktan sonra kapı açılır', (tester) async {
    await pumpScene(tester);
    await tester.pump(at(0.95));

    expect(doorGap(tester), greaterThan(10), reason: 'kapı açılmış olmalı');
  });

  testWidgets('sahne bitince sonuç kartı görünür', (tester) async {
    await pumpScene(tester);
    await tester.pump(duration);
    await tester.pumpAndSettle();

    expect(find.text('SONUÇ'), findsOneWidget);
  });

  testWidgets('dokununca sahne atlanır', (tester) async {
    await pumpScene(tester);
    await tester.pump(at(0.2));

    await tester.tapAt(const Offset(200, 700));
    await tester.pumpAndSettle();

    expect(find.text('SONUÇ'), findsOneWidget);
    expect(doorGap(tester), greaterThan(10));
    expect(skipped, 1, reason: 'tören sesi kesilsin diye atlama bildirilmeli');
  });

  testWidgets('sahne kendi biterse atlama bildirilmez', (tester) async {
    await pumpScene(tester);
    await tester.pump(duration);
    await tester.pumpAndSettle();

    expect(find.text('SONUÇ'), findsOneWidget);
    expect(skipped, 0);
  });

  testWidgets('ikinci dokunuş tekrar bildirmez', (tester) async {
    await pumpScene(tester);
    await tester.pump(at(0.2));

    await tester.tapAt(const Offset(200, 700));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 700));
    await tester.pumpAndSettle();

    expect(skipped, 1);
  });

  testWidgets('hareketi azalt açıkken sahne beklemeden sonuca geçer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: ArrivalSequence(
              accent: Colors.red,
              lineId: 'M2',
              stationName: 'Levent',
              child: Center(child: Text('SONUÇ')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SONUÇ'), findsOneWidget);
    expect(doorGap(tester), greaterThan(10));
  });
}
