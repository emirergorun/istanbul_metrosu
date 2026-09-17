import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/features/games/blocks/domain/scoring.dart';
import 'package:istanbul_metro_game/features/session/widgets/journey_hud.dart';

/// HUD rozetleri combo ve seriyi **okunur** kılmalı.
///
/// İkisi de aynı renkte, adsız birer sayıydı; oyuncu hangisinin ne olduğunu
/// ayırt edemiyordu. Artık her birinin kendi adı, kendi rengi ve basınca
/// çıkan kendi açıklaması var.
void main() {
  Future<void> pumpChip(WidgetTester tester, Widget chip) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: chip)),
      ),
    );
  }

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  group('ComboChip', () {
    testWidgets('adını ve değerini gösterir', (tester) async {
      await pumpChip(tester, const ComboChip(combo: 4));
      await tester.pumpAndSettle();

      expect(find.text('COMBO'), findsOneWidget);
      expect(find.text('x4'), findsOneWidget);
    });

    testWidgets('combo rengi sarıdır', (tester) async {
      await pumpChip(tester, const ComboChip(combo: 4));
      await tester.pumpAndSettle();

      expect(colorOf(tester, 'x4'), AppColors.warning);
    });

    testWidgets('hazırlık payı verilmezse nokta çizilmez', (tester) async {
      await pumpChip(tester, const ComboChip(combo: 3));
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsOneWidget);
    });

    testWidgets('kalan hazırlık hakkı nokta olarak gösterilir', (tester) async {
      await pumpChip(
        tester,
        ComboChip(
          combo: 3,
          graceLeft: 1,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      );
      await tester.pumpAndSettle();

      // Rozetin kendisi + her hazırlık hakkı için bir nokta.
      expect(
        find.byType(Container),
        findsNWidgets(1 + ScoreRules.comboGraceMoves),
      );
    });

    testWidgets('basınca kuralı anlatan açıklama çıkar', (tester) async {
      await pumpChip(
        tester,
        ComboChip(
          combo: 3,
          graceLeft: 2,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ComboChip));
      await tester.pumpAndSettle();

      expect(find.textContaining('art arda sıra temizledikçe'), findsOneWidget);
      expect(find.textContaining('2 hamle hakkın kaldı'), findsOneWidget);
    });

    testWidgets('son hak kalmayınca açıklama uyarır', (tester) async {
      await pumpChip(
        tester,
        ComboChip(
          combo: 3,
          graceLeft: 0,
          graceTotal: ScoreRules.comboGraceMoves,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ComboChip));
      await tester.pumpAndSettle();

      expect(find.textContaining('combo’yu bitirir'), findsOneWidget);
    });

    testWidgets('combo değişince rozet yeniden animasyona girer', (
      tester,
    ) async {
      await pumpChip(tester, const ComboChip(combo: 2));
      await tester.pumpAndSettle();

      await pumpChip(tester, const ComboChip(combo: 3));
      // Animasyonun ilk karesi: ölçek henüz 1 değil.
      await tester.pump(const Duration(milliseconds: 1));

      final scale = tester.widget<Transform>(
        find
            .ancestor(of: find.text('x3'), matching: find.byType(Transform))
            .first,
      );
      expect(scale.transform.getMaxScaleOnAxis(), greaterThan(1.0));

      await tester.pumpAndSettle();
    });
  });

  group('StreakChip', () {
    testWidgets('adını ve değerini gösterir', (tester) async {
      await pumpChip(tester, const StreakChip(streak: 7));
      await tester.pumpAndSettle();

      expect(find.text('SERİ'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('güvendeyken yeşil, combo renginden farklı', (tester) async {
      await pumpChip(tester, const StreakChip(streak: 7));
      await tester.pumpAndSettle();

      expect(colorOf(tester, '7'), AppColors.success);
      expect(colorOf(tester, '7'), isNot(AppColors.warning));
    });

    testWidgets('risk altındayken kırmızıya döner', (tester) async {
      await pumpChip(tester, const StreakChip(streak: 7, atRisk: true));
      await tester.pumpAndSettle();

      expect(colorOf(tester, '7'), AppColors.danger);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('basınca kuralı anlatan açıklama çıkar', (tester) async {
      await pumpChip(tester, const StreakChip(streak: 7));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(StreakChip));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('her üç parçada en az bir sıra'),
        findsOneWidget,
      );
    });

    testWidgets('risk altında açıklama kalan parçayı söyler', (tester) async {
      await pumpChip(
        tester,
        const StreakChip(streak: 7, atRisk: true, piecesLeft: 1),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(StreakChip));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 parça kaldı'), findsOneWidget);
    });
  });
}
