import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/telemetry/analytics.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/line_badge.dart';
import '../../../core/widgets/pressable.dart';
import '../../games/catalog/mini_game.dart';
import '../application/social_controller.dart';
import '../domain/challenge_record.dart';
import '../domain/friend.dart';
import 'widgets/player_avatar.dart';

/// Oyunun sosyal katmanı.
///
/// Bir sosyal ağ değil, bir **birlikte oynama** katmanı: akış yok, yorum
/// yok, beğeni yok, takipçi yok. Ekranın cevapladığı tek soru şu: *kiminle
/// yarışacağım?*
///
/// Hiyerarşi bu soruya göre: önce sen kimsin, sonra ne yapabilirsin, sonra
/// kimlerle, en sonda ne oldu.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logged) return;
    _logged = true;
    AppScope.of(context).analytics.log(AnalyticsEvent.friendsOpened);
  }

  @override
  Widget build(BuildContext context) {
    final social = AppScope.of(context).social;
    if (social == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('ARKADAŞLAR', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: social,
          builder: (BuildContext context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: <Widget>[
                _IdentityCard(social: social),
                if (social.canLinkPlatform) ...<Widget>[
                  const SizedBox(height: AppSpacing.stack),
                  _PlatformIdentityRow(social: social),
                ],
                const SizedBox(height: AppSpacing.stack),
                const _ActionRow(),
                const SizedBox(height: AppSpacing.sectionGap),
                if (social.hasFriends) ...<Widget>[
                  Text('ARKADAŞLARIM', style: AppText.sectionTitle),
                  const SizedBox(height: AppSpacing.stack),
                  for (final friend in social.friends) ...<Widget>[
                    _FriendCard(friend: friend, social: social),
                    const SizedBox(height: AppSpacing.stack),
                  ],
                  const SizedBox(height: AppSpacing.stack),
                ] else
                  const _EmptyFriends(),
                if (social.history.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.stack),
                  Text('SON MEYDAN OKUMALAR', style: AppText.sectionTitle),
                  const SizedBox(height: AppSpacing.stack),
                  // Tek taraflı liste: "senin oynadığın meydan okumalar".
                  // Karşılaşma tablosu (5-3 gibi) gösterilmiyor — iki
                  // cihazın geçmişi birbirini doğrulayamıyor, o yüzden
                  // öyle bir iddiada bulunmuyoruz.
                  for (final record in social.history.take(8)) ...<Widget>[
                    _HistoryCard(record: record, social: social),
                    const SizedBox(height: AppSpacing.stack),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Oyuncunun kendi kartı.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.social});

  final SocialController social;

  @override
  Widget build(BuildContext context) {
    final me = social.me;

    return Semantics(
      container: true,
      label:
          '${me.displayName}, ${me.title}, ${me.stationsDiscovered} istasyon. '
          'Metro kodun ${me.formattedCode}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Row(
            children: <Widget>[
              PlayerAvatar(
                code: me.code,
                displayName: me.displayName,
                size: 52,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      me.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.tileTitle,
                    ),
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            '${me.title} · ${me.stationsDiscovered} istasyon',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ),
                        if (social.isPlatformLinked) ...<Widget>[
                          const SizedBox(width: AppSpacing.sm),
                          const _GameCenterMark(),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      me.formattedCode,
                      style: AppText.captionStrong.copyWith(
                        fontFamily: AppFonts.display,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.2,
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

/// Game Center bağlantısı.
///
/// Açılışta **kendiliğinden** oturum açma penceresi çıkmıyor: oyun tünelde
/// açılıyor ve kimliği ağa bağlamak, oynamak için gereken bir adım değil.
/// Bağlanmak oyuncunun kararı ve tek satır yer kaplıyor.
///
/// Bağlandığında değişen tek şey **görünen ad**: sözlükten üretilen ad
/// yerine Game Center takma adı. Arkadaş kodu değişmiyor — kod paylaşıldıktan
/// sonra değişirse karşı tarafın listesindeki kayıt sahipsiz kalırdı.
class _PlatformIdentityRow extends StatelessWidget {
  const _PlatformIdentityRow({required this.social});

  final SocialController social;

  Future<void> _link(BuildContext context) async {
    final linked = await social.linkPlatformIdentity();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          linked
              ? 'Game Center adın kullanılıyor'
              // Hata değil: oyuncu vazgeçmiş, oturum açmamış ya da cihaz
              // çevrimdışı olabilir. Üçünde de oyun aynen çalışıyor.
              : 'Game Center\'a bağlanılamadı. Adın olduğu gibi kalıyor.',
        ),
      ),
    );
  }

  Future<void> _unlink(BuildContext context) async {
    await social.unlinkPlatformIdentity();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Oyun içi adına dönüldü')));
  }

  @override
  Widget build(BuildContext context) {
    final linked = social.isPlatformLinked;
    final busy = social.isLinkingPlatform;

    return Semantics(
      button: true,
      label: linked
          ? 'Game Center bağlı. Oyun içi adına dön'
          : 'Game Center hesabını bağla',
      child: ExcludeSemantics(
        child: Pressable(
          onTap: busy
              ? null
              : () => linked ? _unlink(context) : _link(context),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  linked
                      ? Icons.link_rounded
                      : Icons.sports_esports_outlined,
                  size: 18,
                  color: linked ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    linked
                        ? 'Game Center adın kullanılıyor'
                        : 'Game Center hesabını bağla',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    linked ? 'KALDIR' : 'BAĞLA',
                    style: AppText.micro.copyWith(
                      fontFamily: AppFonts.display,
                      color: linked
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adın Game Center'dan geldiğini söyleyen küçük işaret.
class _GameCenterMark extends StatelessWidget {
  const _GameCenterMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'GAME CENTER',
        style: AppText.micro.copyWith(
          fontFamily: AppFonts.display,
          color: AppColors.success,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// İki birincil eylem: kod göster, kare oku.
class _ActionRow extends StatelessWidget {
  const _ActionRow();

  @override
  Widget build(BuildContext context) {
    // Yan yana **değil, alt alta**.
    //
    // İki gerekçe. Tabela fontu geniş: yan yana iki düğmede "ARKADAŞ EKLE"
    // iki satıra kırılıyor ve düğme komşusundan uzun oluyordu. Dahası iki
    // eylem eşit değil — arkadaş eklemek birincil, kare okumak ikincil.
    // Alt alta düzen bunu hem genişlikle hem de dolgu rengiyle söylüyor.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton(
          onPressed: AppFeedback.onTap(
            context,
            () => Navigator.of(context).pushNamed(AppRoutes.addFriend),
          ),
          child: const Text('ARKADAŞ EKLE'),
        ),
        const SizedBox(height: AppSpacing.stack),
        OutlinedButton(
          onPressed: AppFeedback.onTap(
            context,
            () => Navigator.of(context).pushNamed(AppRoutes.scanChallenge),
          ),
          child: const Text('QR TARA'),
        ),
      ],
    );
  }
}

/// Arkadaşı olmayan oyuncunun gördüğü ekran.
///
/// Boş liste değil, bir davet. Oyuncuya ne kazanacağını söylüyor ve tek
/// bir sonraki adım gösteriyor.
class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('AYNI YOLCULUK. KİM DAHA İYİ?', style: AppText.sectionTitle),
          const SizedBox(height: AppSpacing.stack),
          Text(
            'Yanındaki arkadaşının kodunu okut, aynı rotada aynı oyunu '
            'oynayın ve skorlarınızı karşılaştırın. İnternet gerekmiyor.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSpacing.stack),
          Text(
            'Metro kodun kimliğin: onu gösterirsin, arkadaşın okutur.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// Tek bir arkadaş.
///
/// Kart iki şey söylüyor: **kim** ve **meydan okuyabilir miyim**. Yirmi
/// istatistik yok; oynatmayan bilgi kartta yer kaplamıyor.
class _FriendCard extends StatelessWidget {
  const _FriendCard({required this.friend, required this.social});

  final Friend friend;
  final SocialController social;

  Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Listeden çıkarılsın mı?'),
        // Sunucu yok: karşı tarafın listesine erişemiyoruz ve bunu
        // gizlemiyoruz. "Engelle" demiyoruz çünkü engelleyemiyoruz.
        content: Text(
          '${friend.displayName} senin listenden çıkacak. Meydan okuma '
          'geçmişin silinmez.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: AppFeedback.onTap(
              context,
              () => Navigator.of(context).pop(false),
            ),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: AppFeedback.onTap(
              context,
              () => Navigator.of(context).pop(true),
            ),
            child: const Text(
              'Çıkar',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) social.removeFriend(friend.code);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '${friend.displayName}, ${friend.asPlayer.title}, '
          '${friend.stationsDiscovered} istasyon',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Row(
            children: <Widget>[
              PlayerAvatar(code: friend.code, displayName: friend.displayName),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      friend.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                    Text(
                      '${friend.asPlayer.title} · '
                      '${friend.stationsDiscovered} istasyon',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                button: true,
                label: '${friend.displayName} listenden çıkarılsın mı',
                child: ExcludeSemantics(
                  child: IconButton(
                    onPressed: AppFeedback.onTap(
                      context,
                      () => _remove(context),
                    ),
                    icon: const Icon(Icons.person_remove_rounded, size: 20),
                    color: AppColors.textMuted,
                    // Dokunma alanı 44 pikselin altına inmiyor.
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Geçmişteki bir maç ve rövanş düğmesi.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record, required this.social});

  final ChallengeRecord record;
  final SocialController social;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final line = scope.metro.lineById(record.lineId);
    final game = MiniGames.byId(record.gameId);
    final outcome = record.outcome;
    final color = switch (outcome) {
      ChallengeOutcome.won => AppColors.success,
      ChallengeOutcome.lost => AppColors.textSecondary,
      ChallengeOutcome.tied => AppColors.warning,
    };

    return Semantics(
      container: true,
      label:
          '${record.opponentName} ile ${game?.name ?? record.gameId}. '
          '${record.lineId} hattı, ${record.originName} '
          '${record.destinationName}. Senin skorun '
          '${record.myScore}, hedef ${record.targetScore}. ${outcome.label}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: outcome == ChallengeOutcome.won
                  ? AppColors.success.withValues(alpha: 0.4)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  LineBadge(
                    label: record.lineId,
                    color: line?.color ?? AppColors.brandNavy,
                    compact: true,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      record.opponentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                  ),
                  Text(
                    outcome.label,
                    style: AppText.micro.copyWith(
                      fontFamily: AppFonts.display,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${game?.name ?? record.gameId} · '
                '${record.originName} → ${record.destinationName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${Formatters.score(record.myScore)}'
                      '  —  '
                      '${Formatters.score(record.targetScore)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.statSmall.copyWith(
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: AppFeedback.onTap(context, () {
                      AppRoutes.openChallengeShare(
                        context,
                        social.rematchFrom(record),
                        isRematch: true,
                      );
                    }),
                    child: const Text('RÖVANŞ'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
