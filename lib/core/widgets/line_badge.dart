import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Hat rozeti — metro haritalarındaki kare hat etiketinin sade karşılığı.
///
/// Resmi hat amblemi değildir; yalnızca hat kodunu taşıyan renkli bir etikettir.
///
/// Metin rengi **sabit değildir**: hat renginden [LineTheme.readableOn] ile
/// türetilir. Sabit beyazken sarı M9'da kontrast 1.44:1'e, pembe M7'de
/// 2.01:1'e düşüyordu — on hattın yedisinde rozet yazısı okunmuyordu.
class LineBadge extends StatelessWidget {
  const LineBadge({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.onColor,
  });

  final String label;
  final Color color;
  final bool compact;

  /// Metin rengini elle vermek için. Boş bırakılırsa [color]'dan türetilir.
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 13,
          fontWeight: FontWeight.w800,
          color: onColor ?? LineTheme.readableOn(color),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
