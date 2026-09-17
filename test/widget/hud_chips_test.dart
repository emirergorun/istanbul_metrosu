import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_hud.dart';

/// Combo ve serinin HUD okuması.
///
/// Önce iki ayrı hap rozetti — ikon, büyük harf etiket, sayı ve nokta
/// göstergesi taşıyan, biri sarı biri yeşil, eşit ağırlıkta iki kutu.
/// Hiyerarşi yoktu, hat renginden kopuktu ve combo zaten tahtada
/// gösterildiği için tekrardı. Tek okumaya indirildi.
void main() {
  const line = Color(0xFFE30613);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  group('görünürlük', () {
    testWidgets('combo ve seri yokken hiç çizilmez', (tester) async {
      await pump(tester, const ComboReadout(combo: 0, streak: 0, accent: line));

      expect(find.byType(Text), findsNothing);
    });

    testWidgets('tek combo yetmez, ikiden başlar', (tester) async {
      await pump(tester, const ComboReadout(combo: 1, streak: 0, accent: line));

      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('combo çarpan olarak yazılır', (tester) async {
      await pump(tester, const ComboReadout(combo: 4, streak: 0, accent: line));

      expect(find.text('×4'), findsOneWidget);
      expect(find.textContaining('seri'), findsNothing);
    });

    testWidgets('seri combo olmadan da görünür', (tester) async {
      await pump(tester, const ComboReadout(combo: 0, streak: 6, accent: line));

      expect(find.text('seri 6'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('ikisi birlikte alt alta', (tester) async {
      await pump(tester, const ComboReadout(combo: 4, streak: 6, accent: line));

      final combo = tester.getCenter(find.text('×4'));
      final streak = tester.getCenter(find.text('seri 6'));

      expect(streak.dy, greaterThan(combo.dy), reason: 'seri altta');
    });
  });

  group('renk', () {
    testWidgets('çarpan hattın renginde yanar', (tester) async {
      await pump(tester, const ComboReadout(combo: 3, streak: 0, accent: line));

      // Hazırlık payı verilmediğinde tam opak.
      expect(colorOf(tester, '×3'), line);
    });

    testWidgets('seri sessiz kalır, hattın rengini çalmaz', (tester) async {
      await pump(tester, const ComboReadout(combo: 0, streak: 6, accent: line));

      expect(colorOf(tester, 'seri 6'), AppColors.textSecondary);
    });

    testWidgets('risk altındaki seri uyarı rengine döner', (tester) async {
      await pump(
        tester,
        const ComboReadout(
          combo: 0,
          streak: 6,
          accent: line,
          streakAtRisk: true,
        ),
      );

      expect(colorOf(tester, 'seri 6'), AppColors.danger);
    });
  });

  group('hazırlık payı', () {
    testWidgets('hak azaldıkça çarpan solar', (tester) async {
      await pump(
        tester,
        ComboReadout(
          combo: 3,
          streak: 0,
          accent: line,
          graceLeft: ScoreRules.comboGraceMoves,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      );
      final full = colorOf(tester, '×3').a;

      await pump(
        tester,
        ComboReadout(
          combo: 3,
          streak: 0,
          accent: line,
          graceLeft: 0,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      );
      final empty = colorOf(tester, '×3').a;

      expect(
        empty,
        lessThan(full),
        reason:
            'sönmeye yakın combo solar — nokta dizisi açıklama '
            'gerektiriyordu, solma gerektirmiyor',
      );
    });

    testWidgets('sönse bile okunur kalır', (tester) async {
      await pump(
        tester,
        ComboReadout(
          combo: 3,
          streak: 0,
          accent: line,
          graceLeft: 0,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      );

      expect(colorOf(tester, '×3').a, greaterThanOrEqualTo(0.5));
    });
  });

  testWidgets('combo değişince çarpan sıçrar', (tester) async {
    await pump(tester, const ComboReadout(combo: 2, streak: 0, accent: line));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(child: ComboReadout(combo: 3, streak: 0, accent: line)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));

    final scale = tester.widget<Transform>(
      find
          .ancestor(of: find.text('×3'), matching: find.byType(Transform))
          .first,
    );
    expect(scale.transform.getMaxScaleOnAxis(), greaterThan(1.0));

    await tester.pumpAndSettle();
  });

  testWidgets('basınca kuralı anlatan açıklama çıkar', (tester) async {
    await pump(
      tester,
      ComboReadout(
        combo: 4,
        streak: 6,
        accent: line,
        graceLeft: 2,
        graceTotal: ScoreRules.comboGraceMoves,
      ),
    );

    await tester.tap(find.byType(ComboReadout));
    await tester.pumpAndSettle();

    expect(find.textContaining('art arda sıra temizledikçe'), findsOneWidget);
    expect(find.textContaining('her üç parçada'), findsOneWidget);
  });

  testWidgets('stok ikon kullanılmaz', (tester) async {
    // Material ikonları Flutter uygulamalarının en belirgin "üretilmiş"
    // izi; biçimi tipografi ve renk taşımalı.
    await pump(tester, const ComboReadout(combo: 4, streak: 6, accent: line));

    expect(find.byType(Icon), findsNothing);
  });
}
