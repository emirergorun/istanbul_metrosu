import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

/// Oyuncu simgesi — **kullanıcı yüklemesi değil, koddan türeyen çizim.**
///
/// Fotoğraf yükleme V5a'ya girmedi ve girmemeli: moderasyon, depolama ve
/// bildirim akışı gerektirir, üçü de bu sürümde yok. Platform avatarı da
/// kullanılmıyor — Game Center ve Play Games avatarları ayrı izin ve ağ
/// isteği demek, oyun ise tünelde açılıyor.
///
/// Bunun yerine simge arkadaş kodundan türüyor: aynı kod her cihazda aynı
/// deseni veriyor, yani arkadaşının simgesi senin ekranında da onun
/// ekranındaki gibi görünüyor. Desen bir peron tabelası: hat renginde bir
/// şerit ve adın baş harfi.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.code,
    required this.displayName,
    this.size = 44,
  });

  final String code;
  final String displayName;
  final double size;

  /// Metro hatlarının renk ailesinden türetilmiş simge paleti.
  ///
  /// Oyun renkleri değil hat renkleri: simge bir oyuna değil, bir yolcuya
  /// ait. Sekiz ton, koyu zeminde hepsi 4.5:1 üstünde.
  static const List<Color> _palette = <Color>[
    Color(0xFFE2504C),
    Color(0xFF2FB37A),
    Color(0xFF4CC9F0),
    Color(0xFFFF6B9D),
    Color(0xFFC77DFF),
    Color(0xFFFFB020),
    Color(0xFFA8E05F),
    Color(0xFF8C97FF),
  ];

  /// Koddan sabit bir renk seçer.
  static Color colorFor(String code) {
    if (code.isEmpty) return _palette.first;
    var hash = 0;
    for (final unit in code.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return _palette[hash % _palette.length];
  }

  /// Adın ekranda görünen baş harfi.
  ///
  /// Türkçe'de `toUpperCase` güvenli değil: `i` harfi `I` oluyor. Ad
  /// zaten büyük harfle başladığı için ilk karakter olduğu gibi alınıyor.
  static String initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first);
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(code);

    return Semantics(
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _AvatarPainter(color: color),
          child: Center(
            child: Text(
              initialOf(displayName),
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: size * 0.38,
                color: AppColors.brandNavyDeep,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  const _AvatarPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, radius, Paint()..color = color);

    // Tabelanın üst şeridi: dairenin üst üçte birini kaplayan koyu bant.
    // Peron tabelalarındaki hat renkli şeritle aynı işaret.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.22),
      Paint()..color = AppColors.brandNavyDeep.withValues(alpha: 0.35),
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      radius - 0.75,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_AvatarPainter old) => old.color != color;
}
