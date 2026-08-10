import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../models/station.dart';

/// İstasyon seçim sayfası (modal bottom sheet).
///
/// Seçilen istasyonu döner; kullanıcı kapatırsa `null`.
Future<Station?> showStationPicker(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<Station> stations,
  required Color accent,
  Station? selected,
  Station? disabled,
}) {
  return showModalBottomSheet<Station>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _StationPickerSheet(
      title: title,
      subtitle: subtitle,
      stations: stations,
      accent: accent,
      selected: selected,
      disabled: disabled,
    ),
  );
}

class _StationPickerSheet extends StatelessWidget {
  const _StationPickerSheet({
    required this.title,
    required this.subtitle,
    required this.stations,
    required this.accent,
    this.selected,
    this.disabled,
  });

  final String title;
  final String subtitle;
  final List<Station> stations;
  final Color accent;
  final Station? selected;
  final Station? disabled;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    Formatters.upperTr(title),
                    style: const TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: AppColors.brandRed,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: stations.length,
                itemBuilder: (context, index) {
                  final station = stations[index];
                  final isSelected = station == selected;
                  final isDisabled = station == disabled;

                  return _StationTile(
                    station: station,
                    accent: accent,
                    isSelected: isSelected,
                    isDisabled: isDisabled,
                    isFirst: index == 0,
                    isLast: index == stations.length - 1,
                    onTap: isDisabled
                        ? null
                        : () => Navigator.of(context).pop(station),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationTile extends StatelessWidget {
  const _StationTile({
    required this.station,
    required this.accent,
    required this.isSelected,
    required this.isDisabled,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final Station station;
  final Color accent;
  final bool isSelected;
  final bool isDisabled;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isDisabled ? AppColors.textMuted : AppColors.textPrimary;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: SizedBox(
          height: 52,
          child: Row(
            children: <Widget>[
              // Hat çizgisi + durak noktası: metro haritası hissi.
              SizedBox(
                width: 24,
                height: 52,
                child: CustomPaint(
                  painter: _LineDotPainter(
                    color: isDisabled ? accent.withValues(alpha: 0.3) : accent,
                    isFirst: isFirst,
                    isLast: isLast,
                    isSelected: isSelected,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (isDisabled)
                const Text(
                  'seçili',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                )
              else if (isSelected)
                Icon(Icons.check_rounded, size: 20, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Listede hat çizgisi ve durak noktası çizer.
class _LineDotPainter extends CustomPainter {
  const _LineDotPainter({
    required this.color,
    required this.isFirst,
    required this.isLast,
    required this.isSelected,
  });

  final Color color;
  final bool isFirst;
  final bool isLast;
  final bool isSelected;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    if (!isFirst) {
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, centerY), linePaint);
    }
    if (!isLast) {
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX, size.height),
        linePaint,
      );
    }

    canvas.drawCircle(
      Offset(centerX, centerY),
      isSelected ? 7 : 5,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(centerX, centerY),
      isSelected ? 3.5 : 2.5,
      Paint()..color = AppColors.surface,
    );
  }

  @override
  bool shouldRepaint(_LineDotPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.isFirst != isFirst ||
      oldDelegate.isLast != isLast ||
      oldDelegate.isSelected != isSelected;
}
