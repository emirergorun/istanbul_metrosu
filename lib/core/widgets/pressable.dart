import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';

/// Menü ekranlarının dokunma geri bildirimi.
///
/// Ayar ekranındaki "titreşim" tercihi tek kaynaktır: kapalıysa hiçbir
/// menü dokunuşu titreşmez. Oyun ekranları kendi haptik kurallarını
/// kullanmaya devam eder (blok oturma, satır temizleme gibi olaylar
/// farklı şiddetlerde titreşir).
class AppFeedback {
  const AppFeedback._();

  /// Dokunma anı titreşimi.
  ///
  /// [BuildContext] üzerinden `AppScope` **dinlemeden** okunur: bu çağrı
  /// bir jest sırasında yapılıyor, build sırasında değil; bağımlılık
  /// kurmak gereksiz yeniden çizime yol açardı. Scope yoksa (izole widget
  /// testi) sessizce hiçbir şey yapmaz.
  static void tap(BuildContext context) {
    final AppScope? scope = context.getInheritedWidgetOfExactType<AppScope>();
    if (scope != null && scope.store.hapticsEnabled) {
      HapticFeedback.selectionClick();
    }
  }

  /// Material butonlarını (`FilledButton`, `TextButton`) haptikle sarar.
  ///
  /// Butonların basılı görünümü zaten temadan geliyor; eksik olan tek şey
  /// dokunma hissiydi. `null` geri çağrı `null` kalır — devre dışı buton
  /// devre dışı kalmalı.
  static VoidCallback? onTap(BuildContext context, VoidCallback? action) {
    if (action == null) return null;
    return () {
      tap(context);
      action();
    };
  }
}

/// Basıldığında **anında** tepki veren dokunma alanı.
///
/// `InkWell` yerine bunun kullanılmasının iki sebebi var:
///
/// 1. **Zamanlama.** Mürekkep dalgası parmağın altından dışarı doğru
///    büyür; tepkinin tamamlanması ~200 ms sürer. Hareket eden bir
///    vagonda göz ucuyla bakan oyuncu o dalgayı kaçırır. Ölçek + ton
///    değişimi ise ilk karede görünür.
/// 2. **Kimlik.** Genişleyen dalga Material'ın imzasıdır ve her şablon
///    uygulamada aynıdır. Kartın hafifçe içeri basılması fiziksel bir
///    tuş hissi verir, oyunun kendi dili olur.
///
/// Haptik bilinçli olarak **parmak kalkınca** (`onTap`) çalışır, basınca
/// değil: liste içindeki satırlarda parmağın değmesi çoğu zaman kaydırma
/// başlangıcıdır, her kaydırmada titreşen bir liste rahatsız eder.
/// Görsel basılı durum ise dokunma anında başlar ve kaydırma jesti
/// kazandığında (`onTapCancel`) geri alınır — `InkWell` de böyle davranır.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.onLightSurface = false,
    this.scale = 0.97,
    this.semanticLabel,
  });

  final Widget child;

  /// `null` ise widget tamamen pasiftir: ne titreşir ne de basılı görünür.
  final VoidCallback? onTap;

  final BorderRadius? borderRadius;

  /// Açık zeminli yüzeyler (birincil buton rengi) koyulaşarak, koyu
  /// yüzeyler aydınlanarak tepki verir. Tersi yapılırsa basılı durum
  /// kendi zemininde kaybolur.
  final bool onLightSurface;

  /// 1.0 = ölçek değişimi yok. Büyük kartlarda küçük bir değer bile
  /// belirgindir; 0.97'nin altı "kart kaçıyor" hissi veriyor.
  final double scale;

  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;

    // "Hareketi azalt" açıkken ölçek animasyonu yapılmaz; basılı durum
    // yalnızca ton değişimiyle anlatılır. Geri bildirim kaybolmaz,
    // yalnızca hareketi kalkar.
    final bool animate = !MediaQuery.disableAnimationsOf(context);
    final bool showPressed = enabled && _pressed;

    // Kaplama katmanı basılı olmasa da ağaçta kalır: basışta eklenip
    // kalkışta çıkarılsaydı alttaki alt ağaç her dokunuşta yeniden
    // kurulur, içindeki animasyonlu widget'lar durumunu kaybederdi.
    Widget content = Container(
      foregroundDecoration: showPressed
          ? BoxDecoration(
              color: widget.onLightSurface
                  ? Colors.black.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: widget.borderRadius,
            )
          : null,
      child: widget.child,
    );

    if (animate) {
      content = AnimatedScale(
        scale: showPressed ? widget.scale : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: content,
      );
    }

    return Semantics(
      button: enabled,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: enabled
            ? () {
                AppFeedback.tap(context);
                widget.onTap!();
              }
            : null,
        child: content,
      ),
    );
  }
}
