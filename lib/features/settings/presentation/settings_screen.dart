import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/theme.dart';
import '../../../core/telemetry/analytics.dart';
import '../../../core/telemetry/usage_stats.dart';
import '../../../core/audio/audio_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/widgets/line_badge.dart';
import '../../games/catalog/mini_game.dart';
import '../../../core/widgets/pressable.dart';

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
    final analytics = scope.analytics;
    final stats = analytics is UsageStats ? analytics : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Ayarlar', style: AppText.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: <Widget>[
          // Oyuncu adı en üstte: rekor satırlarının kime ait olduğunu
          // söyleyen şey bu, altındaki "REKORLAR" bölümünün başlığı gibi
          // çalışıyor.
          const _SectionTitle('OYUNCU'),
          _SettingsCard(
            children: <Widget>[
              _PlayerNameRow(name: store.playerName, tag: store.playerTag),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
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
                  // Açan dokunuşta tek onay titreşimi: ayarın ne yaptığı
                  // anlatılmadan hissettirilir.
                  if (value) HapticFeedback.selectionClick();
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),
          _SectionTitle('REKORLAR (${_visible(records).length})'),
          if (records.isEmpty)
            _SettingsCard(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'Henüz rekor yok. Bir yolculuk tamamladığında burada '
                    'görünecek.',
                    style: AppText.body.copyWith(height: 1.35),
                  ),
                ),
              ],
            )
          else
            _SettingsCard(
              children: <Widget>[
                for (final record in _visible(records)) ...<Widget>[
                  _RecordRow(record: record),
                  if (record != _visible(records).last) const _Divider(),
                ],
              ],
            ),
          if (records.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: AppFeedback.onTap(
                context,
                () => _confirmReset(context, store.clearRecords),
              ),
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
          const _SectionTitle('İSTATİSTİKLERİN'),
          _SettingsCard(
            children: <Widget>[
              // Sayaçlar **cihazdan çıkmıyor**: hiçbir ağ isteği yok.
              // Oyuncunun kendi verisini görmesi, gönderilmediğini
              // anlatmanın en dürüst yolu.
              if (stats != null) ...<Widget>[
                _StatRow(
                  label: 'Tamamlanan yolculuk',
                  value: '${stats.valueOf(AnalyticsEvent.journeyArrived)}',
                ),
                const _Divider(),
                _StatRow(
                  label: 'Yarıda kalan',
                  value:
                      '${stats.valueOf(AnalyticsEvent.gameOver) + stats.valueOf(AnalyticsEvent.gameAbandoned)}',
                ),
                const _Divider(),
                _StatRow(
                  label: 'Varış oranı',
                  value: '%${(stats.arrivalRate * 100).round()}',
                ),
                const _Divider(),
              ],
              _SwitchRow(
                icon: Icons.insights_rounded,
                title: 'Kullanım sayaçları',
                subtitle: 'Cihazında kalır, hiçbir yere gönderilmez',
                value: store.statsEnabled,
                onChanged: (value) async {
                  await store.setStatsEnabled(value);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),

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

  /// Çizilebilecek kayıtlar, skora göre azalan.
  ///
  /// Verisi çözülemeyen kayıt (metro verisi değişmiş olabilir) baştan elenir;
  /// eskiden bu kayıtlar listeye giriyor ama boş satır olarak çiziliyordu, bu
  /// yüzden başlıktaki sayı ile ekrandaki satır sayısı tutmuyordu.
  /// Gösterilebilir rekorlar.
  ///
  /// İki eleme var:
  ///
  /// - **Durağı artık olmayan** rota (veri değişmiş olabilir).
  /// - **Kataloğda olmayan oyun.** Emekliye ayrılan bir oyunun kaydı
  ///   (ör. Durak Hafıza) cihazda duruyor; elenmezse `orElse` yüzünden
  ///   Blok Metro rekoru gibi görünür ve oyuncu hiç kurmadığı bir rekorla
  ///   karşılaşırdı. `gameId == null` olan eski kayıtlar Blok Metro'ya
  ///   aittir, onlar kalır.
  List<RouteRecord> _visible(List<RouteRecord> records) {
    final metro = AppScope.of(context).metro;
    final knownGames = <String>{for (final game in MiniGames.all) game.id};
    return records
        .where(
          (r) =>
              metro.stationById(r.originId) != null &&
              metro.stationById(r.destinationId) != null &&
              (r.gameId == null || knownGames.contains(r.gameId)),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

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

/// Oyuncu adı satırı.
///
/// Sonek (`#7F3A`) adın yanında soluk duruyor. Bugün bir işe yaramıyor;
/// ortak bir skor tablosu geldiğinde aynı adı taşıyanları ayıracak. Şimdi
/// göstermenin sebebi, o gün geldiğinde oyuncunun onu tanıyor olması.
class _PlayerNameRow extends StatelessWidget {
  const _PlayerNameRow({required this.name, required this.tag});

  final String name;
  final String tag;

  @override
  Widget build(BuildContext context) {
    // Satır **dokunulamaz**: ad ilk açılışta bir kez seçiliyor ve orada
    // kilitleniyor. Buraya bir "değiştir" düğmesi koymak, kilidin
    // olmadığı izlenimi verirdi.
    return Semantics(
      label: 'Oyuncu adın $name, değiştirilemez',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.badge_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                    Text(
                      'Rekorlarında görünen ad · #$tag',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});

  final RouteRecord record;

  /// Kaydın hangi oyuna ait olduğu. Oyun ayrımından önceki kayıtlar
  /// (`gameId == null`) Blok Metro'ya aittir.
  MiniGame get _game => MiniGames.all.firstWhere(
    (g) => g.id == (record.gameId ?? MiniGames.blocks.id),
    orElse: () => MiniGames.blocks,
  );

  @override
  Widget build(BuildContext context) {
    final metro = AppScope.of(context).metro;
    final origin = metro.stationById(record.originId);
    final destination = metro.stationById(record.destinationId);
    if (origin == null || destination == null) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${origin.name} – ${destination.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(color: AppColors.textPrimary),
                ),
                // Aynı rotanın her oyunda ayrı rekoru var; hangisi olduğu
                // yazılmazsa liste anlamsız tekrarlar gibi görünür.
                Text(
                  _game.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            Formatters.score(record.score),
            style: AppText.lead.copyWith(color: theme.accent),
          ),
        ],
      ),
    );
  }
}

/// Salt okunur sayı satırı.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: AppText.body)),
          Text(
            value,
            style: AppText.bodyStrong.copyWith(fontFeatures: kTabularFigures),
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
        style: AppText.micro.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
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
      onChanged: (bool next) {
        // Titreşim kapalıyken bu çağrı sessizdir; "titreşim" anahtarını
        // kapatan dokunuş son bir kez titrer, açan dokunuş ise aşağıdaki
        // özel onay titreşimiyle karşılık bulur.
        AppFeedback.tap(context);
        onChanged(next);
      },
      activeThumbColor: AppColors.action,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      secondary: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: AppText.body.copyWith(color: AppColors.textPrimary),
      ),
      subtitle: Text(subtitle, style: AppText.caption),
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
                  style: AppText.body.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption.copyWith(height: 1.35)),
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
        style: AppText.body.copyWith(color: AppColors.textPrimary),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
      ),
    );
  }
}
