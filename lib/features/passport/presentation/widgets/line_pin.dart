import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import 'achievement_badge.dart';

/// Bir metro hattının koleksiyon pini.
///
/// Başarım rozetleriyle **aynı gövdeyi** kullanıyor ([paintPinBody]); tek
/// farkı ortasındaki işaretin bir simge değil hattın kendi adı olması. On
/// hat yan yana dizildiğinde amaç tek bir şey: İstanbul metrosunun pin
/// koleksiyonu gibi okunmak.
///
/// Hat tamamlanınca pin hattın kendi rengine kavuşuyor; tamamlanmadan önce
/// silueti ve yazısı duruyor ama soluk. Toplanacak şey görünmeden hedef de
/// olmaz.
class LinePin extends StatelessWidget {
  const LinePin({
    super.key,
    required this.lineId,
    required this.color,
    required this.completed,
    this.size = 44,
  });

  final String lineId;
  final Color color;
  final bool completed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _LinePinPainter(
            label: lineId.toUpperCase(),
            color: color,
            completed: completed,
            // Yazı `CustomPainter` içinde çiziliyor: pin tek bir katman
            // olmalı, üstüne binen bir `Text` jetonun içinde kaymaya
            // başlıyordu.
            textScale: MediaQuery.textScalerOf(context).scale(1),
          ),
        ),
      ),
    );
  }
}

class _LinePinPainter extends CustomPainter {
  _LinePinPainter({
    required this.label,
    required this.color,
    required this.completed,
    required this.textScale,
  });

  final String label;
  final Color color;
  final bool completed;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1.5;
    // Kilitli pin gri değil **soluk hat rengi**: on hat gri çizilince
    // koleksiyon tek bir gri lekeye dönüşüyor ve hangi hattın ne olduğu
    // kayboluyor. Hat kimliği her yerde renkten okunuyor, burada da öyle.
    final tone = completed ? color : Color.lerp(color, AppColors.blocker, 0.6)!;

    paintPinBody(
      canvas: canvas,
      center: center,
      radius: radius,
      color: color,
      tone: tone,
      unlocked: completed,
      // Bütün hatlar aynı ağırlıkta: biri diğerinden değerli değil.
      master: false,
    );

    // Hat adı jetonun içine sığmalı: M1A üç karakter, M2 iki. Yazı
    // ölçeğini de hesaba katıp kutuya göre küçültülüyor, taşma yok.
    final available = radius * 1.35;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: AppText.micro.copyWith(
          fontFamily: AppFonts.display,
          color: completed ? color : AppColors.textSecondary,
          fontSize: size.shortestSide * 0.26,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1),
    )..layout();

    final scale = painter.width > available ? available / painter.width : 1.0;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-painter.width / 2, -painter.height / 2);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinePinPainter old) =>
      old.completed != completed ||
      old.color != color ||
      old.label != label ||
      old.textScale != textScale;
}
