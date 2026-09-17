import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../domain/player_name.dart';

/// Oyuncu adı seçimi.
///
/// **Metin kutusu yok.** Oyuncu yazmaz, beğenene kadar yeniler. Böylece
/// uygunsuz ad üretmek imkânsız kalıyor ve seçim bir forma değil, bir
/// piyangoya dönüşüyor — çevirmesi eğlenceli, bırakması kolay.
///
/// Sayfa bir alt sayfa (bottom sheet) olarak açılır: ayarların içinden
/// çıkılan küçük bir karar, ayrı bir ekranı hak etmiyor.
class NamePickerSheet extends StatefulWidget {
  const NamePickerSheet({super.key, required this.current});

  final String current;

  /// Sayfayı açar; oyuncu ad seçtiyse yeni adı döndürür.
  ///
  /// Kapatılamaz (`isDismissible: false`): seçim bir kereliktir ve
  /// yarım bırakılırsa oyuncu kilitlenmiş rastgele bir adla kalırdı.
  /// Yine de "vazgeç" yok — ekrandaki her ad geçerli bir seçim, sadece
  /// birini onaylaman gerekiyor.
  static Future<String?> show(BuildContext context, String current) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => NamePickerSheet(current: current),
    );
  }

  @override
  State<NamePickerSheet> createState() => _NamePickerSheetState();
}

class _NamePickerSheetState extends State<NamePickerSheet> {
  final Random _random = Random();

  /// Ekranda duran aday. Onaylanana kadar kaydedilmez.
  late String _candidate = widget.current;

  /// Bu oturumda üretilenler — art arda aynı ad çıkmasın.
  late final Set<String> _seen = <String>{widget.current};

  void _roll() {
    var next = PlayerName.random(_random);
    // Havuz 3.600 ad taşıyor; birkaç deneme fazlasıyla yeter.
    for (var i = 0; i < 8 && _seen.contains(next); i++) {
      next = PlayerName.random(_random);
    }
    _seen.add(next);
    if (AppScope.of(context).store.hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
    setState(() => _candidate = next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'OYUNCU ADIN',
              textAlign: TextAlign.center,
              style: AppText.title,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Adı sen yazmıyorsun, beğenene kadar yeniliyorsun. '
              'Seçtiğin ad rekorlarında görünür ve bir daha değişmez.',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.xl),
            // Aday ad: ekranın en büyük ögesi, çünkü karar bu.
            Container(
              constraints: const BoxConstraints(minHeight: 84),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              ),
              child: Text(
                _candidate,
                textAlign: TextAlign.center,
                style: AppText.tileTitle.copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: _roll, child: const Text('BAŞKA BİR AD')),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_candidate),
              child: const Text('BU ADI KULLAN'),
            ),
          ],
        ),
      ),
    );
  }
}
