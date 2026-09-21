import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/telemetry/analytics.dart';
import '../../../core/widgets/pressable.dart';
import '../domain/challenge.dart';
import '../domain/challenge_codec.dart';
import 'add_friend_screen.dart';

/// Karekod okuyucu.
///
/// İki tür kare okunuyor ve **ayrımı ilk alan yapıyor**: `IMGF` arkadaş
/// kartı, `IMG1` meydan okuma. Başka her şey — Wi-Fi şifresi, bağlantı
/// adresi, market barkodu — tek karşılaştırmayla eleniyor ve oyuncuya
/// suçlayıcı olmayan bir cümleyle söyleniyor.
///
/// Kamera **tek** izin noktası. Kameranın olmadığı ya da reddedildiği
/// durumda ekran kırmızı bir hata duvarına dönmüyor; elle kod girme yoluna
/// yönlendiriyor. Meydan okumanın kamerasız yolu her zaman açık.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Yalnız karekod: barkod biçimlerinin tamamını açmak hem yavaş hem de
    // yanlış eşleşme kaynağı.
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Aynı kare art arda onlarca kez okunuyor; ilk geçerli okumadan sonra
  /// kapı kapanıyor ve ekran değişene kadar açılmıyor.
  bool _handled = false;

  ChallengeError? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((Barcode barcode) => barcode.rawValue)
        .firstWhere((String? value) => value != null && value.isNotEmpty,
            orElse: () => null);
    if (raw == null) return;

    // 1) Arkadaş kartı mı?
    final invite = FriendInvite.decode(raw);
    if (invite != null) {
      _handled = true;
      await _controller.stop();
      if (!mounted) return;
      await FriendPreviewSheet.show(context, invite);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // 2) Meydan okuma mı?
    final decoded = ChallengeCodec.decode(raw);
    if (!decoded.isValid) {
      // Kare bozuk ya da bize ait değil: tarama durmuyor, oyuncu kareyi
      // düzeltip yeniden deneyebilsin.
      setState(() => _error = decoded.error);
      return;
    }

    _handled = true;
    await _controller.stop();
    if (!mounted) return;
    AppScope.of(context).analytics.log(AnalyticsEvent.challengeScanned);
    await AppRoutes.openChallengePreview(context, decoded.challenge!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('QR TARA', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder:
                            (
                              BuildContext context,
                              MobileScannerException error,
                            ) => const _CameraUnavailable(),
                      ),
                      const IgnorePointer(child: _ScanFrame()),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_error != null) ...<Widget>[
                    _ScanError(error: _error!),
                    const SizedBox(height: AppSpacing.stack),
                  ] else ...<Widget>[
                    Text(
                      'Arkadaşının meydan okuma ya da metro kodu karesini '
                      'çerçeveye al. İnternet gerekmiyor.',
                      textAlign: TextAlign.center,
                      style: AppText.caption,
                    ),
                    const SizedBox(height: AppSpacing.stack),
                  ],
                  OutlinedButton(
                    onPressed: AppFeedback.onTap(
                      context,
                      () => Navigator.of(
                        context,
                      ).pushReplacementNamed(AppRoutes.addFriend),
                    ),
                    child: const Text('KODU ELLE YAZ'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Çerçeve — nereye tutulacağını söyleyen tek çizim.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ScanFramePainter());
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.68;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side,
    );

    // Çerçevenin dışı karartılıyor: göz otomatik olarak açık alana gidiyor.
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16))),
      ),
      Paint()..color = AppColors.background.withValues(alpha: 0.6),
    );

    // Dört köşe işareti — tam çerçeve çizmek kareyle karışıyor.
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const arm = 26.0;
    for (final (Offset corner, double dx, double dy) in <(Offset, double, double)>[
      (rect.topLeft, 1, 1),
      (rect.topRight, -1, 1),
      (rect.bottomLeft, 1, -1),
      (rect.bottomRight, -1, -1),
    ]) {
      canvas.drawLine(corner, corner.translate(arm * dx, 0), paint);
      canvas.drawLine(corner, corner.translate(0, arm * dy), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanFramePainter oldDelegate) => false;
}

/// Kamera açılamadı.
///
/// "NETWORK ERROR / RETRY" tonu yok: kamera izni verilmemiş ya da cihazda
/// kamera yok olabilir; ikisi de oyuncunun hatası değil ve ikisinde de
/// kamerasız yol duruyor.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        // Metin çerçevenin **içinde** kalıyor.
        //
        // Çerçeve köşe işaretleri bu katmanın üstüne çiziliyor; tam
        // genişlikte bir metin onların altından geçip okunmayı zorlaştırdı.
        // Oran çerçeve karesinin oranına yakın tutuldu.
        child: FractionallySizedBox(
          widthFactor: 0.62,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.photo_camera_outlined,
                size: 40,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.stack),
              Text(
                'Kamera kullanılamıyor',
                style: AppText.sectionTitle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Meydan okumayı kamerasız da kabul edebilirsin: '
                'arkadaşının kodunu elle yaz.',
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  const _ScanError({required this.error});

  final ChallengeError error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: '${error.title}. ${error.detail}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                error.title,
                style: AppText.bodyStrong.copyWith(color: AppColors.warning),
              ),
              const SizedBox(height: 2),
              Text(error.detail, style: AppText.caption),
            ],
          ),
        ),
      ),
    );
  }
}
