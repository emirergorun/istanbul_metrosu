import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// İlk açılışta bir kez gösterilen üç kartlık tanıtım.
///
/// Ayrı bir karşılama ekranı **değildir**: ürün prensibi "metroda tek elle,
/// mümkün olduğunca az dokunuş". Bu yüzden yalnızca ilk kullanımda çıkar,
/// sonraki açılışlarda araya girmez.
class OnboardingSheet extends StatefulWidget {
  const OnboardingSheet({super.key});

  static const List<({IconData icon, String title, String body})> steps =
      <({IconData icon, String title, String body})>[
        (
          icon: Icons.alt_route_rounded,
          title: 'Yolculuğunu seç',
          body:
              'Hattını, bindiğin ve ineceğin durağı seç. Oyunun uzunluğu '
              'yolculuğunun süresine göre ayarlanır.',
        ),
        (
          icon: Icons.grid_view_rounded,
          title: 'Blokları yerleştir',
          body:
              'Gelen üç parçayı tahtaya sürükle. Dolan satır ve sütunlar '
              'temizlenir, arka arkaya temizlik combo yapar.',
        ),
        (
          icon: Icons.emoji_events_rounded,
          title: 'Rekorunu geç',
          body:
              'Hedef skor yok. Amaç, durağına varmadan o rotadaki kendi '
              'rekorunu geçmek. Her durak geçişi bonus getirir.',
        ),
      ];

  @override
  State<OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<OnboardingSheet> {
  final PageController _pages = PageController();
  int _index = 0;

  bool get _isLast => _index == OnboardingSheet.steps.length - 1;

  void _next() {
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: 210,
              child: PageView.builder(
                controller: _pages,
                onPageChanged: (value) => setState(() => _index = value),
                itemCount: OnboardingSheet.steps.length,
                itemBuilder: (context, index) =>
                    _Step(step: OnboardingSheet.steps[index]),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < OnboardingSheet.steps.length; i++)
                  Container(
                    width: i == _index ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.action : AppColors.outline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _next,
              child: Text(_isLast ? 'HADİ BAŞLAYALIM' : 'DEVAM'),
            ),
            if (!_isLast)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Atla'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.step});

  final ({IconData icon, String title, String body}) step;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.surfaceHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(step.icon, size: 26, color: AppColors.action),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          step.body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
