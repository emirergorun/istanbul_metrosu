import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/discovery/presentation/widgets/discovery_progress_track.dart';

/// İlerleme çubuğunun **genişliği**.
///
/// Çubuğun içinde kendi genişliğini belirleyen hiçbir şey yok; dolayısıyla
/// gevşek kısıt veren bir düzende (ör. `CrossAxisAlignment.start` kullanan
/// bir `Column`) sıfıra çöküyordu. Ana ekran şeridi, keşif ekranı, sonuç
/// paneli ve günlük görev kartları aynı çubuğu kullanıyor — bu yüzden
/// kuralı bir kez burada sabitliyoruz.
void main() {
  Future<void> pumpIn(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: child),
        ),
      ),
    );
  }

  testWidgets('gevşek kısıtta bile tam genişlikte çizilir', (tester) async {
    await pumpIn(
      tester,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[DiscoveryProgressTrack(value: 0)],
      ),
    );

    final size = tester.getSize(find.byType(DiscoveryProgressTrack));
    expect(size.width, 300);
    expect(size.height, 6);
  });

  testWidgets('ilerleme sıfırken de zemin görünür', (tester) async {
    await pumpIn(
      tester,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DiscoveryProgressTrack(value: 0, background: AppColors.outline),
        ],
      ),
    );

    // Zemin kutusu çiziliyor: boş çubuk da bir bilgi, hedef orada duruyor.
    expect(
      tester.getSize(find.byType(DiscoveryProgressTrack)).width,
      greaterThan(0),
    );
  });

  testWidgets('kalınlık verildiği gibi kalır', (tester) async {
    await pumpIn(
      tester,
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[DiscoveryProgressTrack(value: 0.5, thickness: 5)],
      ),
    );

    expect(tester.getSize(find.byType(DiscoveryProgressTrack)).height, 5);
  });
}
