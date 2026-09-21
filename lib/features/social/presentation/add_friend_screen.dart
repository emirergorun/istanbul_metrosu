import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_scope.dart';
import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/widgets/pressable.dart';
import '../domain/friend.dart';
import '../domain/friend_code.dart';
import 'widgets/challenge_qr_view.dart';
import 'widgets/player_avatar.dart';

/// Arkadaş ekleme: kodumu göster ya da kodunu yaz.
///
/// İki yön ayrı ayrı çalışıyor ve **ikisi de kamerasız**. Kamera yalnızca
/// meydan okuma karesi için gerekli; arkadaş eklemek için kodu okumak ya da
/// yazmak yetiyor. Erişilebilirlik açısından da gerekli: kamera
/// kullanamayan bir oyuncu sekiz karakteri yazabilir.
///
/// Arka uç olmadığı için burada **istek gönderilmiyor**. Kodu ekleyen taraf
/// karşıyı kendi listesine alıyor, karşı taraf da aynısını yapıyor.
/// Arayüzün hiçbir yerinde "istek gönderildi" yazmıyor; söyleyemediğimiz
/// şeyi söylemiyoruz.
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _name = TextEditingController();
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final social = AppScope.of(context).social;
    if (social == null) return;

    final name = _name.text.trim();
    final result = social.addFriend(
      rawCode: _code.text,
      // Ad boşsa koddan okunabilir bir yer tutucu: arkadaşın adını
      // bilmiyor olabilirsin ama kodunu okudun.
      displayName: name.isEmpty
          ? 'Yolcu ${FriendCode.normalize(_code.text)?.substring(0, 4) ?? ''}'
          : name,
    );

    setState(() {
      _message = result.message;
      _failed = !result.isSuccess;
    });
    if (result.isSuccess) {
      _code.clear();
      _name.clear();
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = AppScope.of(context).social;
    if (social == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final me = social.me;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('ARKADAŞ EKLE', style: AppText.title),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            Text('METRO KODUN', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.stack),
            _MyCodeCard(
              code: me.code,
              displayName: me.displayName,
              // Karede yalnızca ad ve kod var: e-posta, cihaz kimliği,
              // platform kimliği ya da konum yok.
              payload: 'IMGF|1|${me.code}|${me.displayName}',
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            Text('ARKADAŞININ KODU', style: AppText.sectionTitle),
            const SizedBox(height: AppSpacing.stack),
            _CodeField(controller: _code, onSubmitted: _submit),
            const SizedBox(height: AppSpacing.stack),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 24,
              style: AppText.body,
              decoration: const InputDecoration(
                labelText: 'Adı (isteğe bağlı)',
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.stack),
            FilledButton(
              onPressed: AppFeedback.onTap(context, _submit),
              child: const Text('EKLE'),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.stack),
              _ResultNotice(message: _message!, failed: _failed),
            ],
            const SizedBox(height: AppSpacing.sectionGap),
            Text(
              'Arkadaşının karesini okutmak için QR TARA\'yı kullan. '
              'Meydan okuma kareleri de oradan okunur.',
              style: AppText.caption,
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
        ),
      ),
    );
  }
}

/// Oyuncunun kendi kodu ve karesi.
class _MyCodeCard extends StatelessWidget {
  const _MyCodeCard({
    required this.code,
    required this.displayName,
    required this.payload,
  });

  final String code;
  final String displayName;
  final String payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              PlayerAvatar(code: code, displayName: displayName),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong,
                    ),
                    Text(
                      FriendCode.format(code),
                      style: AppText.statSmall.copyWith(
                        fontFamily: AppFonts.display,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Metro kodunu kopyala',
                child: ExcludeSemantics(
                  child: IconButton(
                    onPressed: AppFeedback.onTap(context, () {
                      Clipboard.setData(
                        ClipboardData(text: FriendCode.format(code)),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kod kopyalandı')),
                      );
                    }),
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    color: AppColors.textMuted,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.stack),
          Center(
            child: ChallengeQrView(
              data: payload,
              size: 200,
              semanticLabel:
                  'Metro kodunun karesi. Kodun ${FriendCode.format(code)}. '
                  'Arkadaşın kamerayı kullanamıyorsa bu kodu elle yazabilir.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Kod girişi.
///
/// Klavye büyük harfe zorlanmıyor ve tire serbest: oyuncu kodu gördüğü
/// gibi yazıyor, biçimi [FriendCode.normalize] düzeltiyor.
class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.characters,
      autocorrect: false,
      maxLength: 12,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => onSubmitted(),
      style: AppText.bodyStrong.copyWith(
        fontFamily: AppFonts.display,
        letterSpacing: 2,
      ),
      decoration: const InputDecoration(
        labelText: 'Metro kodu',
        hintText: 'ABCD-1234',
        counterText: '',
      ),
    );
  }
}

class _ResultNotice extends StatelessWidget {
  const _ResultNotice({required this.message, required this.failed});

  final String message;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = failed ? AppColors.warning : AppColors.success;
    return Semantics(
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                failed
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
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

/// Arkadaş karesinin yükünü çözer.
///
/// Meydan okuma yükünden **ayrı bir imza** (`IMGF`) kullanıyor: tarayıcı
/// okuduğu karenin arkadaş kartı mı yoksa meydan okuma mı olduğunu ilk
/// alandan anlıyor ve yanlış ekrana götürmüyor.
class FriendInvite {
  const FriendInvite({required this.code, required this.displayName});

  static const String magic = 'IMGF';

  final String code;
  final String displayName;

  /// Karekod metnini çözer; arkadaş kartı değilse `null`.
  static FriendInvite? decode(String? raw) {
    if (raw == null || !raw.startsWith('$magic|')) return null;
    final parts = raw.split('|');
    if (parts.length < 4) return null;
    if (parts[1] != '1') return null;
    final code = FriendCode.normalize(parts[2]);
    // Ad `|` içerebilir; kalan parçalar geri birleştiriliyor.
    final name = parts.sublist(3).join('|').trim();
    if (code == null || name.isEmpty || name.length > 40) return null;
    return FriendInvite(code: code, displayName: name);
  }
}

/// Okunmuş bir arkadaş kartının onay sayfası.
///
/// Kare okunur okunmaz eklemek yok: oyuncu kimi eklediğini görmeden
/// listesine kimse girmiyor.
class FriendPreviewSheet extends StatelessWidget {
  const FriendPreviewSheet({super.key, required this.invite});

  final FriendInvite invite;

  /// Onay sayfasını açar; eklendiyse `true` döner.
  static Future<bool> show(BuildContext context, FriendInvite invite) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext context) => FriendPreviewSheet(invite: invite),
    );
    return added ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final social = AppScope.of(context).social;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                PlayerAvatar(
                  code: invite.code,
                  displayName: invite.displayName,
                  size: 52,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        invite.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.tileTitle,
                      ),
                      Text(
                        FriendCode.format(invite.code),
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            FilledButton(
              onPressed: AppFeedback.onTap(context, () {
                final result =
                    social?.addFriend(
                      rawCode: invite.code,
                      displayName: invite.displayName,
                    ) ??
                    FriendAddResult.invalid;
                Navigator.of(context).pop(result.isSuccess);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.message)));
              }),
              child: const Text('ARKADAŞ EKLE'),
            ),
            TextButton(
              onPressed: AppFeedback.onTap(
                context,
                () => Navigator.of(context).pop(false),
              ),
              child: const Text('Vazgeç'),
            ),
          ],
        ),
      ),
    );
  }
}
