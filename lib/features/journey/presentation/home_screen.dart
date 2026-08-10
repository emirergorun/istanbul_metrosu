import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../models/difficulty_profile.dart';
import '../models/station.dart';
import '../services/route_service.dart';
import 'widgets/station_picker.dart';

/// Yolculuk kurulum ekranı.
///
/// Düzen, metro.istanbul'daki "nasıl giderim" planlayıcısını izler:
/// başlık şeridi, A/B işaretli çıkış–varış alanları, tam genişlik aksiyon
/// butonu ve altta kırmızı vurgu şeridi.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Station? _origin;
  Station? _destination;

  RouteResult? get _route {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return null;
    return AppScope.of(
      context,
    ).routeService.estimate(origin.id, destination.id);
  }

  Color get _accent {
    final scope = AppScope.of(context);
    final lineId = _origin?.lineId ?? scope.metro.stations().first.lineId;
    final line = scope.metro.lineById(lineId);
    return line == null ? AppColors.brandNavy : Color(line.colorValue);
  }

  Future<void> _pick({required bool isOrigin}) async {
    final scope = AppScope.of(context);
    final picked = await showStationPicker(
      context,
      title: isOrigin ? 'Çıkış Noktası' : 'Gidilecek Yer',
      subtitle: isOrigin ? 'Nereden bindin?' : 'Nerede ineceksin?',
      stations: scope.metro.stations(),
      accent: _accent,
      selected: isOrigin ? _origin : _destination,
    );
    if (picked == null) return;
    setState(() {
      if (isOrigin) {
        _origin = picked;
      } else {
        _destination = picked;
      }
    });
  }

  void _swap() {
    setState(() {
      final origin = _origin;
      _origin = _destination;
      _destination = origin;
    });
  }

  void _start() {
    final journey = _route?.journey;
    if (journey == null) return;
    AppRoutes.openGame(context, journey);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final route = _route;
    final journey = route?.journey;
    final line = scope.metro.lineById(_origin?.lineId ?? 'M2');

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                // IntrinsicHeight: scroll içinde Spacer'ın çalışması için
                // Column'un yüksekliği sınırlı olmalı.
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _TopBar(lineId: line?.id ?? 'M2', accent: _accent),
                        const SizedBox(height: AppSpacing.xl),
                        const _Hero(),
                        const SizedBox(height: AppSpacing.xl),
                        _PlannerCard(
                          origin: _origin,
                          destination: _destination,
                          route: route,
                          bestScore: journey == null
                              ? 0
                              : scope.store.bestScoreFor(journey.difficulty.id),
                          onPickOrigin: () => _pick(isOrigin: true),
                          onPickDestination: () => _pick(isOrigin: false),
                          onSwap: _origin == null && _destination == null
                              ? null
                              : _swap,
                          onStart: journey == null ? null : _start,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _DifficultyScale(active: journey?.difficulty),
                        const Spacer(),
                        const SizedBox(height: AppSpacing.lg),
                        const _OfflineNote(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.lineId, required this.accent});

  final String lineId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        LineBadge(label: lineId, color: accent),
        const SizedBox(width: AppSpacing.md),
        const Expanded(
          child: Text(
            'Yenikapı – Hacıosman',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'ÇEVRİMDIŞI',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'YOLCULUĞUN\nKADAR OYNA',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${AppConstants.appTitle} · bindiğin ve ineceğin durağı seç, '
          'oyunun uzunluğu yolculuğuna göre ayarlansın.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _PlannerCard extends StatelessWidget {
  const _PlannerCard({
    required this.origin,
    required this.destination,
    required this.route,
    required this.bestScore,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.onSwap,
    required this.onStart,
  });

  final Station? origin;
  final Station? destination;
  final RouteResult? route;
  final int bestScore;
  final VoidCallback onPickOrigin;
  final VoidCallback onPickDestination;
  final VoidCallback? onSwap;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _CardHeader(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _OriginDestinationFields(
                  origin: origin,
                  destination: destination,
                  onPickOrigin: onPickOrigin,
                  onPickDestination: onPickDestination,
                  onSwap: onSwap,
                ),
                const SizedBox(height: AppSpacing.lg),
                _JourneySummary(
                  route: route,
                  hasSelection: origin != null && destination != null,
                  bestScore: bestScore,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandRed,
                    disabledBackgroundColor: AppColors.surfaceHigh,
                    disabledForegroundColor: AppColors.textMuted,
                  ),
                  child: const Text('YOLCULUĞU BAŞLAT'),
                ),
              ],
            ),
          ),
          // Kurumsal arayüzdeki alt kırmızı şerit.
          Container(height: 4, color: AppColors.brandRed),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brandNavy,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              'YOLCULUĞUNU PLANLA',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: Colors.white,
              ),
            ),
          ),
          Icon(
            Icons.alt_route_rounded,
            size: 18,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ],
      ),
    );
  }
}

/// A/B işaretli çıkış–varış alanları ve yön değiştirme butonu.
class _OriginDestinationFields extends StatelessWidget {
  const _OriginDestinationFields({
    required this.origin,
    required this.destination,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.onSwap,
  });

  final Station? origin;
  final Station? destination;
  final VoidCallback onPickOrigin;
  final VoidCallback onPickDestination;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Column(
          children: <Widget>[
            _StationField(
              marker: 'A',
              label: 'ÇIKIŞ NOKTASI',
              hint: 'Bindiğin durağı seç',
              station: origin,
              onTap: onPickOrigin,
            ),
            const SizedBox(height: AppSpacing.sm),
            _StationField(
              marker: 'B',
              label: 'GİDİLECEK YER',
              hint: 'İneceğin durağı seç',
              station: destination,
              onTap: onPickDestination,
            ),
          ],
        ),
        Positioned(
          right: AppSpacing.sm,
          top: 0,
          bottom: 0,
          child: Center(
            child: Material(
              color: AppColors.brandNavy,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                onPressed: onSwap,
                tooltip: 'Yönü değiştir',
                iconSize: 18,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.swap_vert_rounded),
                color: Colors.white,
                disabledColor: Colors.white24,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StationField extends StatelessWidget {
  const _StationField({
    required this.marker,
    required this.label,
    required this.hint,
    required this.station,
    required this.onTap,
  });

  final String marker;
  final String label;
  final String hint;
  final Station? station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
        child: Container(
          height: 58,
          padding: const EdgeInsets.only(left: 12, right: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
            border: Border.all(color: AppColors.outline),
          ),
          child: Row(
            children: <Widget>[
              _AbMarker(letter: marker),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      station?.name ?? hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: station == null
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Planlayıcıdaki kırmızı A / B işareti.
class _AbMarker extends StatelessWidget {
  const _AbMarker({required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.brandRed,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

class _JourneySummary extends StatelessWidget {
  const _JourneySummary({
    required this.route,
    required this.hasSelection,
    required this.bestScore,
  });

  final RouteResult? route;
  final bool hasSelection;
  final int bestScore;

  @override
  Widget build(BuildContext context) {
    if (!hasSelection) {
      return const _InfoBanner(
        icon: Icons.info_outline_rounded,
        text: 'İki durak seç, oyun süreni yolculuğuna göre ayarlayalım.',
      );
    }

    final journey = route?.journey;
    if (journey == null) {
      return _InfoBanner(
        icon: Icons.error_outline_rounded,
        text: route?.message ?? 'Rota hesaplanamadı.',
        color: AppColors.brandRed,
      );
    }

    final difficulty = journey.difficulty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _Metric(
                label: 'TAHMİNİ YOLCULUK',
                value: Formatters.approxMinutes(journey.estimatedMinutes),
              ),
            ),
            Container(width: 1, height: 32, color: AppColors.outline),
            Expanded(
              child: _Metric(label: 'ZORLUK', value: difficulty.label),
            ),
            Container(width: 1, height: 32, color: AppColors.outline),
            Expanded(
              child: _Metric(
                label: 'HEDEF',
                value: Formatters.score(difficulty.targetScore),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            const Icon(
              Icons.linear_scale_rounded,
              size: 15,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${journey.stopCount} durak'
                '${bestScore > 0 ? '  ·  En iyi ${Formatters.score(bestScore)}' : ''}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    this.color = AppColors.textMuted,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.fieldRadius),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13.5, color: color, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Süre → zorluk skalası.
///
/// Oyunun ana fikrini ("yolculuk ne kadarsa oyun da o kadar") tek bakışta
/// anlatır ve seçili rotanın hangi banda düştüğünü gösterir.
class _DifficultyScale extends StatelessWidget {
  const _DifficultyScale({required this.active});

  final DifficultyProfile? active;

  String _range(DifficultyProfile profile) => profile.maxMinutes == null
      ? '${profile.minMinutes}+'
      : '${profile.minMinutes}–${profile.maxMinutes}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'YOLCULUK SÜRESİ  →  ZORLUK',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            for (final profile in DifficultyProfiles.all)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _ScaleSegment(
                    label: profile.label,
                    range: _range(profile),
                    isActive: profile == active,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ScaleSegment extends StatelessWidget {
  const _ScaleSegment({
    required this.label,
    required this.range,
    required this.isActive,
  });

  final String label;
  final String range;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      decoration: BoxDecoration(
        color: isActive ? AppColors.brandNavy : AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isActive ? AppColors.brandRed : AppColors.outline,
        ),
      ),
      child: Column(
        children: <Widget>[
          FittedBox(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isActive
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 1),
          FittedBox(
            child: Text(
              '$range dk',
              style: const TextStyle(fontSize: 9.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.textMuted),
        SizedBox(width: AppSpacing.sm),
        Text(
          AppConstants.offlineNote,
          style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}
