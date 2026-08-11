import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../models/station.dart';

/// Yatay hat seçici.
///
/// Her hat kendi resmi rengiyle temsil edilir; seçili hat dolu rozet,
/// diğerleri sadece renkli kenarlık olur. Renk burada **kimlik** taşır,
/// aksiyon değil.
class LineSelector extends StatelessWidget {
  const LineSelector({
    super.key,
    required this.lines,
    required this.selected,
    required this.onSelected,
  });

  final List<MetroLine> lines;
  final MetroLine? selected;
  final ValueChanged<MetroLine> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: lines.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final line = lines[index];
          return _LineChip(
            line: line,
            isSelected: line == selected,
            onTap: () => onSelected(line),
          );
        },
      ),
    );
  }
}

class _LineChip extends StatelessWidget {
  const _LineChip({
    required this.line,
    required this.isSelected,
    required this.onTap,
  });

  final MetroLine line;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = LineTheme.from(line.color);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${line.id} hattı, ${line.name}',
      child: Material(
        color: isSelected ? theme.color : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            alignment: Alignment.center,
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? theme.color
                    : theme.accent.withValues(alpha: 0.55),
                width: isSelected ? 2 : 1.4,
              ),
            ),
            child: Text(
              line.id,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: isSelected ? theme.onColor : theme.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
