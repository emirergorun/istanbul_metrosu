import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import 'overlay_panel.dart';

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
        StatRow(
          label: 'Skor',
          value: Formatters.score(score),
          highlight: true,
          accent: accent,
        ),
        StatRow(
          label: 'Kalan yolculuk',
          value: Formatters.remaining(remainingSeconds),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: onResume,
          style: FilledButton.styleFrom(backgroundColor: accent),
          child: const Text('Devam et'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRestart, child: const Text('Yeniden başlat')),
        TextButton(onPressed: onSettings, child: const Text('Ayarlar')),
        TextButton(onPressed: onExit, child: const Text('Yeni rota seç')),
      ],
    );
  }
}
