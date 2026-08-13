import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../models/journey.dart';
import '../models/station.dart';
import '../services/route_service.dart';
import 'widgets/line_selector.dart';
import 'widgets/station_picker.dart';

/// Yolculuk kurulum ekranı.
///
/// Düzen metro.istanbul'daki "nasıl giderim" planlayıcısını izler: başlık
/// şeridi, A/B işaretli çıkış–varış alanları, tam genişlik aksiyon butonu ve
/// altta kırmızı vurgu şeridi. Üstüne hat seçici eklenmiştir — MVP'de
/// aktarma yok, yolculuk tek hat üzerinde kurulur.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MetroLine? _line;
  Station? _origin;
  Station? _destination;
  MetroLine get _activeLine =>
      _line ?? AppScope.of(context).metro.lines().first;

  LineTheme get _lineTheme => LineTheme.from(_activeLine.color);

  RouteResult? get _route {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return null;
    return AppScope.of(
      context,
    ).routeService.estimate(origin.id, destination.id);
  }

  void _selectLine(MetroLine line) {
    if (line == _activeLine) return;
    setState(() {
      _line = line;
      // Hat değişince eski duraklar geçersiz.
      _origin = null;
      _destination = null;
    });
  }

  Future<void> _pick({required bool isOrigin}) async {
    final scope = AppScope.of(context);
    final line = _activeLine;
    final picked = await showStationPicker(
      context,
      title: isOrigin ? 'Çıkış Noktası' : 'Gidilecek Yer',
      subtitle: isOrigin ? 'Nereden bindin?' : 'Nerede ineceksin?',
      lineId: line.id,
      stations: scope.metro.stationsOfLine(line.id),
      accent: _lineTheme.accent,
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
    _startJourney(journey);
  }

  /// Oyunu açar ve döndüğünde ekranı tazeler.
  ///
  /// `Navigator.pop` alttaki rotayı yeniden çizmez; beklemeden bırakılırsa
  /// dönüşte ne "son rotan" kartı ne de yeni rekor görünür.
  Future<void> _startJourney(Journey journey) async {
    final store = AppScope.of(context).store;
    await store.rememberRoute(journey.origin.id, journey.destination.id);
    if (!mounted) return;

    await AppRoutes.openGame(context, journey);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);

    // Hat yoksa planlanacak yolculuk da yok. `_activeLine` boş listede
    // `.first` çağırıp StateError atardı; kullanıcıya boş ekran yerine
    // ne olduğunu söylüyoruz.
    if (scope.metro.lines().isEmpty) return const _NoLinesScreen();

    final route = _route;
    final journey = route?.journey;
    final line = _activeLine;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.xs,
                          AppSpacing.sm,
                          0,
                        ),
                        child: Row(
                          children: <Widget>[
                            const Spacer(),
                            IconButton(
                              onPressed: () => AppRoutes.openSettings(context),
                              tooltip: 'Ayarlar',
                              icon: const Icon(Icons.settings_rounded),
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          0,
                          AppSpacing.xl,
                          AppSpacing.lg,
                        ),
                        child: _Hero(),
                      ),
                      LineSelector(
                        lines: scope.metro.lines(),
                        selected: line,
                        onSelected: _selectLine,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.lg,
                          AppSpacing.xl,
                          AppSpacing.lg,
                        ),
                        child: _PlannerCard(
                          line: line,
                          lineTheme: _lineTheme,
                          origin: _origin,
                          destination: _destination,
                          route: route,
                          bestScore: journey == null
                              ? 0
                              : scope.store.bestScoreForRoute(
                                  journey.origin.id,
                                  journey.destination.id,
                                ),
                          onPickOrigin: () => _pick(isOrigin: true),
                          onPickDestination: () => _pick(isOrigin: false),
                          onSwap: _origin == null && _destination == null
                              ? null
                              : _swap,
                          onStart: journey == null ? null : _start,
                        ),
                      ),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.lg),
                        child: _OfflineNote(),
                      ),
                    ],
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

/// Metro verisinde hiç hat yoksa gösterilen boş durum.
class _NoLinesScreen extends StatelessWidget {
  const _NoLinesScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.wrong_location_rounded,
                size: 44,
                color: AppColors.danger,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Hat bulunamadı',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Metro verisi boş görünüyor, yolculuk planlanamıyor.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
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
          '${AppConstants.appTitle} · hattını ve iki durağını seç, '
          'oyunun uzunluğu yolculuğuna göre ayarlansın.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _PlannerCard extends StatelessWidget {
  const _PlannerCard({
    required this.line,
    required this.lineTheme,
    required this.origin,
    required this.destination,
    required this.route,
    required this.bestScore,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.onSwap,
    required this.onStart,
  });

  final MetroLine line;
  final LineTheme lineTheme;
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
          _CardHeader(line: line, lineTheme: lineTheme),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _OriginDestinationFields(
                  lineTheme: lineTheme,
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
                  child: const Text('YOLCULUĞU BAŞLAT'),
                ),
              ],
            ),
          ),
          // Kurumsal arayüzdeki alt vurgu şeridi — seçili hattın renginde.
          Container(height: 4, color: lineTheme.accent),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.line, required this.lineTheme});

  final MetroLine line;
  final LineTheme lineTheme;

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: lineTheme.color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              line.id,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: lineTheme.onColor,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              line.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A/B işaretli çıkış–varış alanları ve yön değiştirme butonu.
class _OriginDestinationFields extends StatelessWidget {
  const _OriginDestinationFields({
    required this.lineTheme,
    required this.origin,
    required this.destination,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.onSwap,
  });

  final LineTheme lineTheme;
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
              lineTheme: lineTheme,
              onTap: onPickOrigin,
            ),
            const SizedBox(height: AppSpacing.sm),
            _StationField(
              marker: 'B',
              label: 'GİDİLECEK YER',
              hint: 'İneceğin durağı seç',
              station: destination,
              lineTheme: lineTheme,
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
    required this.lineTheme,
    required this.onTap,
  });

  final String marker;
  final String label;
  final String hint;
  final Station? station;
  final LineTheme lineTheme;
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
              _AbMarker(letter: marker, lineTheme: lineTheme),
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

/// Planlayıcıdaki A / B işareti.
///
/// Seçili hattın rengini taşır — bu işaretler o hat üzerindeki iki noktayı
/// gösterdiği için renk burada kimlik bilgisidir. Koyu zeminde kaybolmaması
/// için resmi renk değil, düzeltilmiş [LineTheme.accent] kullanılır.
class _AbMarker extends StatelessWidget {
  const _AbMarker({required this.letter, required this.lineTheme});

  final String letter;
  final LineTheme lineTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lineTheme.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: lineTheme.onAccent,
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
        color: AppColors.danger,
      );
    }

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
              child: _Metric(
                label: bestScore > 0 ? 'ROTA REKORUN' : 'BU ROTADA',
                value: bestScore > 0
                    ? Formatters.score(bestScore)
                    : 'İlk yolculuk',
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
