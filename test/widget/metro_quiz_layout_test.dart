import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:istanbul_metro_game/app/app_scope.dart';
import 'package:istanbul_metro_game/app/theme.dart';
import 'package:istanbul_metro_game/core/audio/audio_service.dart';
import 'package:istanbul_metro_game/core/storage/local_store.dart';
import 'package:istanbul_metro_game/data/questions/question_repository.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/domain/trivia_category.dart';
import 'package:istanbul_metro_game/features/games/metro_quiz/presentation/metro_quiz_screen.dart';
import 'package:istanbul_metro_game/features/journey/services/route_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/metro_fixture.dart';
import '../helpers/trivia_fixture.dart';

class _SilentAudio extends AudioService {
  @override
  void play(GameSound sound) {}
}

/// Tek bir soruyu tekrar tekrar veren havuz — düzen testleri için.
class _FixedQuestion implements QuestionRepository {
  _FixedQuestion(this.question);

  final TriviaQuestion question;

  @override
  List<TriviaQuestion> questions() => <TriviaQuestion>[question];

  @override
  List<TriviaQuestion> byCategory(TriviaCategory category) =>
      question.category == category
      ? <TriviaQuestion>[question]
      : const <TriviaQuestion>[];
}

TriviaQuestion _question({
  required String prompt,
  List<String>? options,
  TriviaCategory category = TriviaCategory.geographyCity,
}) {
  return TriviaQuestion(
    id: 'test_1',
    category: category,
    difficulty: TriviaDifficulty.easy,
    prompt: prompt,
    options: options ?? const <String>['Bir', 'İki', 'Üç', 'Dört'],
    answerIndex: 0,
    source: 'https://ornek.test/',
    verification: TriviaVerification.modelKnowledge,
  );
}

/// Metro Bilgi ekranının düzeni.
///
/// Ölçülen şey estetik değil, **okuma sırası ve dokunma hedefi**: kategori
/// sorunun üstünde mi, soru ile şıklar tek grup mu, dar ekranda taşma var
/// mı, kalan hak göstergesi doğru sayıyı mı söylüyor.
void main() {
  final metro = MetroFixture.load();

  Future<void> pumpScreen(
    WidgetTester tester, {
    QuestionRepository? repository,
    Size size = const Size(375, 667),
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final routes = RouteService(metro);
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: _SilentAudio(),
        metro: metro,
        questions: repository ?? TriviaFixture.repository(),
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MetroQuizScreen(journey: journey),
        ),
      ),
    );
    await tester.pump();
  }

  /// Ekranı söker: oyun sayacı widget ağacından sonra da tik atmasın.
  Future<void> tearDownScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('kategori sorunun üstünde görünür', (tester) async {
    await pumpScreen(
      tester,
      repository: _FixedQuestion(
        _question(
          prompt: 'Boğaziçi Köprüsü hangi yıl açıldı?',
          category: TriviaCategory.history,
        ),
      ),
    );

    expect(find.text('Tarih'), findsOneWidget);
    expect(find.text('TAR'), findsOneWidget);
    expect(find.text('Boğaziçi Köprüsü hangi yıl açıldı?'), findsOneWidget);

    final categoryY = tester.getTopLeft(find.text('Tarih')).dy;
    final promptY = tester
        .getTopLeft(find.text('Boğaziçi Köprüsü hangi yıl açıldı?'))
        .dy;
    expect(categoryY, lessThan(promptY));

    await tearDownScreen(tester);
  });

  testWidgets('dört şık da çizilir', (tester) async {
    await pumpScreen(
      tester,
      repository: _FixedQuestion(_question(prompt: 'Kaç durak var?')),
    );

    for (final option in <String>['Bir', 'İki', 'Üç', 'Dört']) {
      expect(find.text(option), findsOneWidget);
    }

    await tearDownScreen(tester);
  });

  testWidgets('soru ile şıklar arasındaki boşluk sabit', (tester) async {
    // Kısa soru + uzun ekran: eski düzende buradaki boşluk ekranın üçte
    // biri kadardı.
    await pumpScreen(
      tester,
      size: const Size(430, 932),
      repository: _FixedQuestion(_question(prompt: 'Kaç?')),
    );

    final card = tester.getRect(find.byKey(MetroQuizScreen.questionCardKey));
    final options = tester.getRect(find.byKey(MetroQuizScreen.optionsKey));
    final gap = options.top - card.bottom;

    expect(
      gap,
      inInclusiveRange(14, 20),
      reason: 'kart ile şıklar tek grup olmalı, ölçülen boşluk: $gap',
    );

    // Kısa soruda da kart kendisine ayrılan alanı kaplar: ekranda gövdesiz
    // bir boşluk kalmamalı.
    final screen = tester.getRect(find.byType(Scaffold));
    expect(
      card.height / screen.height,
      greaterThan(0.25),
      reason:
          'kart ekranın gövdesi olmalı, ölçülen oran: '
          '${card.height / screen.height}',
    );

    await tearDownScreen(tester);
  });

  testWidgets('uzun soruda da boşluk aynı, taşma yok', (tester) async {
    await pumpScreen(
      tester,
      size: const Size(375, 667),
      repository: _FixedQuestion(
        _question(
          prompt:
              'İstanbul metrosunun ilk hattı olan M1 hattının açıldığı '
              'tarihte hangi iki istasyon arasında sefer yapıldığı ve o '
              'dönemdeki toplam istasyon sayısı kaçtı?',
          options: const <String>[
            'Aksaray ile Kocatepe arasında, dokuz istasyon',
            'Yenikapı ile Atatürk Havalimanı arasında, on sekiz istasyon',
            'Aksaray ile Esenler arasında, on bir istasyon',
            'Otogar ile Bağcılar arasında, yedi istasyon',
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // Kart ekrana sığmadığında içeriği kendi içinde kayar; kartın kendi
    // kutusu düzende aynı yerde durur, şıklar kımıldamaz.
    final card = tester.getRect(find.byKey(MetroQuizScreen.questionCardKey));
    final options = tester.getRect(find.byKey(MetroQuizScreen.optionsKey));
    expect(options.top - card.bottom, inInclusiveRange(14, 20));

    await tearDownScreen(tester);
  });

  testWidgets('dar ekranda taşma yok', (tester) async {
    await pumpScreen(
      tester,
      // Desteklenen en dar ekran.
      size: const Size(320, 568),
      repository: _FixedQuestion(
        _question(
          prompt: 'Marmaray hangi iki kıtayı birbirine bağlar?',
          options: const <String>[
            'Avrupa ile Asya',
            'Avrupa ile Afrika',
            'Asya ile Afrika',
            'Avrupa ile Okyanusya',
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    await tearDownScreen(tester);
  });

  testWidgets('yazı ölçeği iki katına çıkınca taşma yok', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_seen': true,
    });
    final store = LocalStore();
    await store.init();
    final routes = RouteService(metro);
    final journey = routes.estimate('m2_taksim', 'm2_levent').journey!;

    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      AppScope(
        store: store,
        audio: _SilentAudio(),
        metro: metro,
        questions: _FixedQuestion(
          _question(prompt: 'Taksim hangi hatta bulunur?'),
        ),
        routeService: routes,
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 2,
            maxScaleFactor: 2,
            child: child!,
          ),
          home: MetroQuizScreen(journey: journey),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tearDownScreen(tester);
  });

  group('kalan hak göstergesi', () {
    testWidgets('üç trenle başlar', (tester) async {
      await pumpScreen(
        tester,
        repository: _FixedQuestion(_question(prompt: 'Kaç durak var?')),
      );

      expect(find.bySemanticsLabel('Kalan yanlış hakkı 3 / 3'), findsOneWidget);
      // Üç ikon: üçü de dolu.
      expect(find.byType(MetroQuizLifeIcon), findsNWidgets(3));
      expect(
        tester
            .widgetList<MetroQuizLifeIcon>(find.byType(MetroQuizLifeIcon))
            .where((w) => w.spent)
            .length,
        0,
      );

      await tearDownScreen(tester);
    });

    testWidgets('yanlış cevaptan sonra bir tren söner', (tester) async {
      await pumpScreen(
        tester,
        repository: _FixedQuestion(_question(prompt: 'Kaç durak var?')),
      );

      // Doğru cevap 0. şık; yanlış bir şıkka dokun.
      await tester.tap(find.text('İki'));
      await tester.pump();

      expect(find.bySemanticsLabel('Kalan yanlış hakkı 2 / 3'), findsOneWidget);
      expect(
        tester
            .widgetList<MetroQuizLifeIcon>(find.byType(MetroQuizLifeIcon))
            .where((w) => w.spent)
            .length,
        1,
      );

      await tearDownScreen(tester);
    });

    testWidgets('çift dokunuş ikinci canı götürmez', (tester) async {
      await pumpScreen(
        tester,
        repository: _FixedQuestion(_question(prompt: 'Kaç durak var?')),
      );

      // Aynı karede iki dokunuş: ekran daha yeniden çizilmeden ikincisi
      // gelirse de ikinci can gitmemeli.
      await tester.tap(find.text('İki'), warnIfMissed: false);
      await tester.tap(find.text('Üç'), warnIfMissed: false);
      await tester.pump();

      expect(find.bySemanticsLabel('Kalan yanlış hakkı 2 / 3'), findsOneWidget);

      await tearDownScreen(tester);
    });
  });
}
