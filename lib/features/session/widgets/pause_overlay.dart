import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/utils/formatters.dart';
import 'overlay_panel.dart';
import '../../../core/widgets/pressable.dart';

/// Duraklatma paneli.
///
/// Uygulama arka plana alındığında oyun otomatik duraklar ve dönüşte
/// kullanıcıdan açık bir "devam et" hamlesi istenir.
class PauseOverlay extends StatelessWidget {
  const PauseOverlay({
    super.key,
    required this.accent,
    required this.score,
    required this.remainingSeconds,
    required this.onResume,
    required this.onRestart,
    required this.onSettings,
    required this.onExit,
  });

  final Color accent;
  final int score;
  final int remainingSeconds;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onSettings;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return OverlayPanel(
      icon: Icons.pause_rounded,
      accent: accent,
      title: 'Duraklatıldı',
      subtitle: 'Yolculuk sayacı da durdu. Hazır olduğunda devam et.',
      children: <Widget>[
        StatRow(label: 'Skor', value: Formatters.score(score), highlight: true),
        StatRow(
          label: 'Kalan yolculuk',
          value: Formatters.remaining(remainingSeconds),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Buton rengi bilinçli olarak hattan bağımsız: `theme.dart`'taki
        // hiyerarşi kuralı gereği birincil eylem her hatta aynı görünür.
        // Hat rengi verilseydi M1A'da (kırmızı) "Devam et" butonu `danger`
        // ile aynı tona düşüp yıkıcı bir eylem gibi okunurdu.
        FilledButton(
          onPressed: AppFeedback.onTap(context, onResume),
          child: const Text('DEVAM ET'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: AppFeedback.onTap(context, onRestart),
          child: const Text('Yeniden başlat'),
        ),
        TextButton(
          onPressed: AppFeedback.onTap(context, onSettings),
          child: const Text('Ayarlar'),
        ),
        TextButton(
          onPressed: AppFeedback.onTap(context, onExit),
          child: const Text('Başka oyun seç'),
        ),
      ],
    );
  }
}
