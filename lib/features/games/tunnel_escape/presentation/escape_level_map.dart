import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/theme.dart';
import '../../../../core/widgets/line_badge.dart';
import '../../../../core/widgets/pressable.dart';
import '../../../../data/metro/metro_repository.dart';
import '../../../journey/models/station.dart';
import '../application/escape_progress_controller.dart';
import '../domain/escape_progress.dart';
import 'escape_widgets.dart';

/// Haritada bir hat: on beş bölüm, gerçek bir metro hattının ilk on beş
/// istasyonu.
///
/// Bölüm seçimi numaralı bir ızgara değil, **hat boyunca ilerlemek**:
/// Bölüm 1 Yenikapı, Bölüm 15 Hacıosman. Oyuncu bir hattı bitirince bir
/// sonrakine aktarma yapar. Tam bir İstanbul haritası çizilmiyor — yalnız
/// istasyon adları ve hat rengi, bağlamı kurmaya yetiyor.
@immutable
class EscapeRouteSegment {
  const EscapeRouteSegment({
    required this.lineId,
    required this.first,
    required this.last,
  });

  final String lineId;
  final int first;
  final int last;

  bool contains(int level) => level >= first && level <= last;

  /// Hatlar zorluk kuşaklarıyla kabaca örtüşüyor: M2 öğrenme, M3 planlama,
  /// M4 ustalık, M5 uzmanlık ve son durak. Kırmızı hatlar (M1) bilerek
  /// yok — tahtada kırmızı yalnız oyuncunun metrosu.
  static const List<EscapeRouteSegment> all = <EscapeRouteSegment>[
    EscapeRouteSegment(lineId: 'M2', first: 1, last: 15),
    EscapeRouteSegment(lineId: 'M3', first: 16, last: 30),
    EscapeRouteSegment(lineId: 'M4', first: 31, last: 45),
    EscapeRouteSegment(lineId: 'M5', first: 46, last: 60),
  ];

  static EscapeRouteSegment of(int level) => all.firstWhere(
    (EscapeRouteSegment s) => s.contains(level),
    orElse: () => all.last,
  );
}

/// Bölümün istasyon adı ve hat rengi.
@immutable
class EscapeStation {
  const EscapeStation({
    required this.level,
    required this.name,
    required this.segment,
    required this.color,
  });

  final int level;
  final String name;
  final EscapeRouteSegment segment;

  /// Koyu zeminde okunur hâle getirilmiş hat rengi.
  final Color color;

  /// Metro verisinden bölümün istasyonunu bulur. Veri eksikse ad yerine
  /// bölüm numarası yazılır, harita yine çalışır.
  static EscapeStation of(int level, MetroRepository? metro) {
    final segment = EscapeRouteSegment.of(level);
    final line = metro?.lineById(segment.lineId);
    final stations = metro?.stationsOfLine(segment.lineId) ?? const <Station>[];
    final index = level - segment.first;
    final name = index >= 0 && index < stations.length
        ? stations[index].name
        : 'Durak $level';
    final color = LineTheme.from(line?.color ?? AppColors.brandNavy).accent;
    return EscapeStation(
      level: level,
      name: name,
      segment: segment,
      color: color,
    );
  }
}

/// Hat haritası: bölüm seçimi.
class EscapeLevelMap extends StatefulWidget {
  const EscapeLevelMap({
    super.key,
    required this.progress,
    required this.levelCount,
    required this.onOpen,
  });

  final EscapeProgressController progress;
  final int levelCount;
  final ValueChanged<int> onOpen;

  @override
  State<EscapeLevelMap> createState() => _EscapeLevelMapState();
}

/// Harita satırlarının sabit yükseklikleri — kaydırma konumu hesaplanabilsin.
const double _rowHeight = 62;
const double _headerHeight = 58;

class _EscapeLevelMapState extends State<EscapeLevelMap> {
  late final ScrollController _scroll = ScrollController();
  bool _scrolledOnce = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<_MapEntry> _entries() {
    final entries = <_MapEntry>[];
    for (final segment in EscapeRouteSegment.all) {
      if (segment.first > widget.levelCount) break;
      entries.add(_MapEntry.header(segment));
      final last = math.min(segment.last, widget.levelCount);
      for (var level = segment.first; level <= last; level++) {
        entries.add(_MapEntry.station(level));
      }
    }
    return entries;
  }

  double _offsetOf(List<_MapEntry> entries, int level) {
    var offset = 0.0;
    for (final entry in entries) {
      if (entry.level == level) return offset;
      offset += entry.isHeader ? _headerHeight : _rowHeight;
    }
    return offset;
  }

  @override
  Widget build(BuildContext context) {
    final metro = AppScope.of(context).metro;
    final entries = _entries();

    return ListenableBuilder(
      listenable: widget.progress,
      builder: (BuildContext context, _) {
        final progress = widget.progress.progress;
        final next = progress.nextLevel(widget.levelCount);

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (!_scrolledOnce) {
              _scrolledOnce = true;
              // Sıradaki bölüm ekranın üst üçte birine gelsin: geçilmiş
              // birkaç durak üstünde görünür, ilerleme hissi kaybolmaz.
              final target =
                  _offsetOf(entries, next) - constraints.maxHeight * 0.3;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_scroll.hasClients) return;
                _scroll.jumpTo(
                  target.clamp(0.0, _scroll.position.maxScrollExtent),
                );
              });
            }
            return ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              itemCount: entries.length,
              itemBuilder: (BuildContext context, int index) {
                final entry = entries[index];
                if (entry.isHeader) {
                  return _SegmentHeader(
                    segment: entry.segment!,
                    metro: metro,
                    progress: progress,
                  );
                }
                final level = entry.level!;
                final station = EscapeStation.of(level, metro);
                final segment = station.segment;
                return _StationRow(
                  station: station,
                  record: progress.recordOf(level),
                  unlocked: progress.isUnlocked(level),
                  isNext: level == next && !progress.isCompleted(level),
                  isFirstOfLine: level == segment.first,
                  isLastOfLine:
                      level == math.min(segment.last, widget.levelCount),
                  previousTraveled:
                      progress.isCompleted(level - 1) || level == 1,
                  onTap: () => widget.onOpen(level),
                );
              },
            );
          },
        );
      },
    );
  }
}

@immutable
class _MapEntry {
  const _MapEntry.header(EscapeRouteSegment this.segment) : level = null;
  const _MapEntry.station(int this.level) : segment = null;

  final EscapeRouteSegment? segment;
  final int? level;

  bool get isHeader => segment != null;
}

class _SegmentHeader extends StatelessWidget {
  const _SegmentHeader({
    required this.segment,
    required this.metro,
    required this.progress,
  });

  final EscapeRouteSegment segment;
  final MetroRepository metro;
  final EscapeProgress progress;

  @override
  Widget build(BuildContext context) {
    final line = metro.lineById(segment.lineId);
    final color = line?.color ?? AppColors.brandNavy;
    final stations = metro.stationsOfLine(segment.lineId);
    final span = stations.length >= segment.last - segment.first + 1
        ? '${stations.first.name} – ${stations[segment.last - segment.first].name}'
        : '${segment.first}–${segment.last}';
    var done = 0;
    for (var level = segment.first; level <= segment.last; level++) {
      if (progress.isCompleted(level)) done++;
    }
    final total = segment.last - segment.first + 1;

    return SizedBox(
      height: _headerHeight,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 64,
              child: Center(
                child: LineBadge(label: segment.lineId, color: color),
              ),
            ),
            Expanded(
              child: Text(
                span,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.captionStrong.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$done/$total',
              style: AppText.captionStrong.copyWith(
                color: done == total
                    ? LineTheme.from(color).accent
                    : AppColors.textMuted,
                fontFeatures: kTabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.station,
    required this.record,
    required this.unlocked,
    required this.isNext,
    required this.isFirstOfLine,
    required this.isLastOfLine,
    required this.previousTraveled,
    required this.onTap,
  });

  final EscapeStation station;
  final EscapeLevelRecord? record;
  final bool unlocked;
  final bool isNext;
  final bool isFirstOfLine;
  final bool isLastOfLine;
  final bool previousTraveled;
  final VoidCallback onTap;

  String get _semantics {
    final base = 'Bölüm ${station.level}, ${station.name}';
    if (!unlocked) return '$base, kilitli';
    final r = record;
    if (r == null) return '$base, sıradaki bölüm';
    return '$base, ${r.bestStars} yıldız, en iyi ${r.bestMoves} hamle';
  }

  @override
  Widget build(BuildContext context) {
    final completed = record != null;
    final nameColor = unlocked ? AppColors.textPrimary : AppColors.textMuted;

    final row = SizedBox(
      height: _rowHeight,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 64,
            height: _rowHeight,
            child: CustomPaint(
              painter: _NodePainter(
                color: station.color,
                completed: completed,
                mastered: (record?.bestStars ?? 0) >= 3,
                unlocked: unlocked,
                isNext: isNext,
                drawTop: !isFirstOfLine,
                drawBottom: !isLastOfLine,
                topTraveled: previousTraveled && unlocked,
                bottomTraveled: completed,
              ),
              child: Center(
                child: Text(
                  '${station.level}',
                  style: AppText.label.copyWith(
                    fontSize: 12,
                    color: completed
                        ? LineTheme.readableOn(station.color)
                        : unlocked
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  station.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong.copyWith(
                    fontSize: 16,
                    fontWeight: isNext ? FontWeight.w800 : FontWeight.w600,
                    color: nameColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  !unlocked
                      ? 'BÖLÜM ${station.level}'
                      : completed
                      ? 'BÖLÜM ${station.level} · EN İYİ ${record!.bestMoves} HAMLE'
                      : 'BÖLÜM ${station.level} · SIRADAKİ DURAK',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.micro.copyWith(
                    color: isNext ? station.color : AppColors.textMuted,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ],
            ),
          ),
          if (completed)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: EscapeStarRow(count: record!.bestStars, size: 15),
            )
          else if (isNext)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Icon(
                Icons.chevron_right_rounded,
                color: station.color,
                size: 24,
              ),
            ),
        ],
      ),
    );

    return Semantics(
      label: _semantics,
      button: unlocked,
      child: ExcludeSemantics(
        child: unlocked
            ? Pressable(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                child: row,
              )
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final scope = context
                      .getInheritedWidgetOfExactType<AppScope>();
                  if (scope?.store.hapticsEnabled ?? false) {
                    HapticFeedback.lightImpact();
                  }
                },
                child: row,
              ),
      ),
    );
  }
}

/// İstasyon düğümü ve hattın o satırdaki parçası.
class _NodePainter extends CustomPainter {
  const _NodePainter({
    required this.color,
    required this.completed,
    required this.mastered,
    required this.unlocked,
    required this.isNext,
    required this.drawTop,
    required this.drawBottom,
    required this.topTraveled,
    required this.bottomTraveled,
  });

  final Color color;
  final bool completed;
  final bool mastered;
  final bool unlocked;
  final bool isNext;
  final bool drawTop;
  final bool drawBottom;
  final bool topTraveled;
  final bool bottomTraveled;

  static const double _radius = 15;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final line = Paint()
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.butt;
    final idle = AppColors.surfaceHigh;

    if (drawTop) {
      line.color = topTraveled ? color : idle;
      canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, c.dy - _radius), line);
    }
    if (drawBottom) {
      line.color = bottomTraveled ? color : idle;
      canvas.drawLine(
        Offset(c.dx, c.dy + _radius),
        Offset(c.dx, size.height),
        line,
      );
    }

    if (isNext) {
      // Sıradaki durak: hat renginde yumuşak hale.
      canvas.drawCircle(
        c,
        _radius + 6,
        Paint()..color = color.withValues(alpha: 0.18),
      );
    }

    if (completed) {
      canvas.drawCircle(c, _radius, Paint()..color = color);
      if (mastered) {
        canvas.drawCircle(
          c,
          _radius + 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = escapeStarColor,
        );
      }
    } else {
      canvas.drawCircle(c, _radius, Paint()..color = AppColors.background);
      canvas.drawCircle(
        c,
        _radius - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNext ? 3.5 : 2.5
          ..color = unlocked ? color : idle,
      );
    }
  }

  @override
  bool shouldRepaint(_NodePainter old) =>
      old.color != color ||
      old.completed != completed ||
      old.mastered != mastered ||
      old.unlocked != unlocked ||
      old.isNext != isNext ||
      old.drawTop != drawTop ||
      old.drawBottom != drawBottom ||
      old.topTraveled != topTraveled ||
      old.bottomTraveled != bottomTraveled;
}
