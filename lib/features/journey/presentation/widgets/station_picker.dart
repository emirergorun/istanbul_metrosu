import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/line_badge.dart';
import '../../models/station.dart';

/// İstasyon seçim sayfası (modal bottom sheet).
///
/// Seçilen istasyonu döner; kullanıcı kapatırsa `null`.
Future<Station?> showStationPicker(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String lineId,
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
      lineId: lineId,
      stations: stations,
      accent: accent,
      selected: selected,
      disabled: disabled,
    ),
  );
}

class _StationPickerSheet extends StatefulWidget {
  const _StationPickerSheet({
    required this.title,
    required this.subtitle,
    required this.lineId,
    required this.stations,
    required this.accent,
    this.selected,
    this.disabled,
  });

  final String title;
  final String subtitle;
  final String lineId;
  final List<Station> stations;
  final Color accent;
  final Station? selected;
  final Station? disabled;

  /// Bu sayının altında arama alanı gösterilmez — M6'da dört durak için
  /// arama kutusu gereksiz gürültü olur.
  static const int searchThreshold = 12;

  @override
  State<_StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<_StationPickerSheet> {
  String _query = '';

  bool get _showSearch =>
      widget.stations.length >= _StationPickerSheet.searchThreshold;

  /// Türkçe karakterleri normalleştirerek arar: "sisli" → "Şişli".
  List<Station> get _visible {
    final query = _normalize(_query);
    if (query.isEmpty) return widget.stations;
    return widget.stations
        .where((s) => _normalize(s.name).contains(query))
        .toList();
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .trim();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    final stations = _visible;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
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
                    Row(
                      children: <Widget>[
                        LineBadge(
                          label: widget.lineId,
                          color: widget.accent,
                          compact: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          Formatters.upperTr(widget.title),
                          style: const TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (_showSearch) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      _SearchField(
                        accent: widget.accent,
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ],
                  ],
                ),
              ),
              if (stations.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.xxl,
                  ),
                  child: Text(
                    'Bu hatta eşleşen durak yok.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    itemCount: stations.length,
                    itemBuilder: (context, index) {
                      final station = stations[index];
                      // Arama sonucunda hat çizgisi yanıltmasın: yalnız tam
                      // listede uçlar özel çizilir.
                      final isFullList =
                          stations.length == widget.stations.length;

                      return _StationTile(
                        station: station,
                        accent: widget.accent,
                        isSelected: station == widget.selected,
                        isDisabled: station == widget.disabled,
                        isFirst: isFullList && index == 0,
                        isLast: isFullList && index == stations.length - 1,
                        onTap: station == widget.disabled
                            ? null
                            : () => Navigator.of(context).pop(station),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.accent, required this.onChanged});

  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      cursorColor: accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Durak ara',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: AppColors.textMuted,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
          borderSide: BorderSide(color: accent, width: 1.6),
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

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: !isDisabled,
      label: station.name,
      child: InkWell(
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
                      color: isDisabled
                          ? accent.withValues(alpha: 0.3)
                          : accent,
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
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
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
