import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../core/audio/audio_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';

/// Ayarlar: ses, titreşim, rekorlar ve uygulama bilgisi.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final records = store.allRecords();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Ayarlar',
          style: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          const _SectionTitle('OYUN'),
          _SettingsCard(
            children: <Widget>[
              _SwitchRow(
                icon: Icons.volume_up_rounded,
                title: 'Ses efektleri',
                subtitle: 'Müziğini kesmez, sessiz moda saygı gösterir',
                value: store.soundEnabled,
                onChanged: (value) async {
                  await store.setSoundEnabled(value);
                  scope.audio.enabled = value;
                  if (value) scope.audio.play(GameSound.clear);
                  if (mounted) setState(() {});
                },
              ),
              const _Divider(),
              _SwitchRow(
                icon: Icons.music_note_rounded,
                title: 'Müzik',
                subtitle: 'Yolculuk boyunca çalan sakin piyano',
                value: store.musicEnabled,
                onChanged: (value) async {
                  await store.setMusicEnabled(value);
                  scope.audio.musicEnabled = value;
                  if (mounted) setState(() {});
                },
              ),
              const _Divider(),
              _SwitchRow(
                icon: Icons.vibration_rounded,
                title: 'Titreşim',
                subtitle: 'Yerleştirme ve temizleme geri bildirimi',
                value: store.hapticsEnabled,
                onChanged: (value) async {
                  await store.setHapticsEnabled(value);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
          _SectionTitle('REKORLAR (${records.length})'),
          if (records.isEmpty)
            const _SettingsCard(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Henüz rekor yok. Bir yolculuk tamamladığında burada '
                    'görünecek.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            )
          else
            _SettingsCard(
              children: <Widget>[
                for (final entry in _sorted(records)) ...<Widget>[
                  _RecordRow(routeKey: entry.key, score: entry.value),
                  if (entry.key != _sorted(records).last.key) const _Divider(),
                ],
              ],
            ),
          if (records.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () => _confirmReset(context, store.clearRecords),
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              label: const Text(
                'Tüm rekorları sıfırla',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
          const _SectionTitle('UYGULAMA'),
          _SettingsCard(
            children: <Widget>[
              const _InfoRow(
                icon: Icons.wifi_off_rounded,
                title: 'Çevrimdışı çalışır',
                subtitle:
                    'Ağ isteği, hesap, reklam ve analitik yoktur. '
                    'Rekorlar yalnızca bu cihazda tutulur.',
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.route_rounded,
                title: 'Metro verisi',
                subtitle:
                    '${scope.metro.lines().length} hat, '
                    '${scope.metro.stations().length} istasyon. İstasyon sırası '
                    've sefer süreleri metro.istanbul kaynaklıdır; durak arası '
                    'süreler bundan türetilmiştir.',
              ),
              const _Divider(),
              _ActionRow(
                icon: Icons.description_outlined,
                title: 'Lisanslar',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appTitle,
                  applicationVersion: '0.1.0',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, int>> _sorted(Map<String, int> records) =>
      records.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  Future<void> _confirmReset(
    BuildContext context,
    Future<int> Function() reset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Rekorlar sıfırlansın mı?'),
        content: const Text(
          'Tüm rotalardaki rekorların silinecek. Bu geri alınamaz.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Sıfırla',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await reset();
    if (mounted) setState(() {});
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.routeKey, required this.score});

  final String routeKey;
  final int score;

  @override
  Widget build(BuildContext context) {
    final metro = AppScope.of(context).metro;
    final ids = routeKey.split('__');
    final origin = ids.isNotEmpty ? metro.stationById(ids.first) : null;
    final destination = ids.length > 1 ? metro.stationById(ids[1]) : null;

    if (origin == null || destination == null) {
      // Veri değişmiş olabilir; anahtarı ham göstermek yerine atla.
      return const SizedBox.shrink();
    }

    final line = metro.lineById(origin.lineId);
    final theme = LineTheme.from(line?.color ?? AppColors.brandNavy);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          LineBadge(label: origin.lineId, color: theme.accent, compact: true),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '${origin.name} – ${destination.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            Formatters.score(score),
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: theme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.outline);
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.action,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      secondary: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15.5, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
      ),
    );
  }
}
