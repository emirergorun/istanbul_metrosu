import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/telemetry/analytics.dart';
import '../../daily/domain/day_stamp.dart';
import '../../discovery/application/discovery_controller.dart';
import '../../journey/models/journey.dart';
import '../domain/challenge.dart';
import '../domain/challenge_record.dart';
import '../domain/challenge_validator.dart';
import '../domain/friend.dart';
import '../domain/friend_code.dart';
import '../domain/social_player.dart';
import 'platform_gaming_service.dart';

/// Sosyal katmanın tek durumu: kimlik, arkadaşlar, meydan okuma geçmişi.
///
/// Üçü bir arada duruyor çünkü üçü de aynı soruya hizmet ediyor: *kiminle,
/// hangi yolculukta yarışıyorum?* Ayrı denetleyicilere bölmek, her ekranın
/// üçünü birden dinlemesi demek olurdu.
///
/// **Ağ yok.** Bu sınıfın hiçbir yöntemi bir sunucuya gitmez, hiçbiri
/// beklemez, hiçbiri bağlantı hatası üretmez. Metroda tünele girmek bu
/// katmanın hiçbir parçasını bozmaz.
class SocialController extends ChangeNotifier {
  SocialController({
    required this.store,
    this.discovery,
    this.analytics = const NoopAnalytics(),
    this.platform = const UnavailableGamingService(),
    Random? random,
  }) : _random = random ?? Random.secure() {
    _restore();
  }

  final LocalStore store;

  /// Kimlik kartındaki keşif sayısı buradan okunur.
  ///
  /// Kopyalanmaz: pasaportta olduğu gibi tek kaynak keşif kaydı.
  final DiscoveryController? discovery;

  final Analytics analytics;
  final PlatformGamingService platform;

  final Random _random;

  String _code = '';
  String? _platformName;
  final List<Friend> _friends = <Friend>[];
  final List<ChallengeRecord> _history = <ChallengeRecord>[];

  void _restore() {
    _platformName = store.platformDisplayName;
    _code = store.friendCode ?? _createCode();
    _friends.addAll(Friend.decodeList(store.friendsRaw));
    _history.addAll(ChallengeRecord.decodeList(store.challengeHistoryRaw));
  }

  String _createCode() {
    final code = FriendCode.generate(random: _random);
    unawaited(store.saveFriendCode(code));
    return code;
  }

  // --- Kimlik ---

  /// Bu cihazın oyuncusu.
  ///
  /// Ad önceliği: platform kimliği → sözlükten üretilmiş yerel ad. Platform
  /// kimliği yoksa hiçbir şey eksik değil; bkz. [PlatformGamingService].
  SocialPlayer get me => SocialPlayer(
    code: _code,
    displayName: _platformName ?? store.playerName,
    source: _platformName == null
        ? PlayerIdentitySource.local
        : PlayerIdentitySource.gameCenter,
    stationsDiscovered: discovery?.discoveredCount ?? 0,
    linesCompleted: discovery == null
        ? 0
        : discovery!.completedLineCount(discovery!.catalog.lineIds),
  );

  /// Bu cihazda platform kimliği bağlanabilir mi?
  bool get canLinkPlatform => platform.isAvailable;

  /// Kimlik platformdan mı geliyor?
  bool get isPlatformLinked => _platformName != null;

  /// Bağlanma denemesi sürüyor mu? Arayüz düğmeyi bir kez kilitliyor.
  bool _linking = false;
  bool get isLinkingPlatform => _linking;

  /// Platform kimliğini bağlamayı dener.
  ///
  /// Başarılıysa görünen ad Game Center takma adına dönüyor ve **kalıcı**
  /// oluyor: bir daha ağ beklenmiyor, çevrimdışı oturumlarda da aynı ad
  /// görünüyor ve karekoda aynı ad giriyor.
  ///
  /// Başarısızsa hiçbir şey değişmiyor ve hata gösterilmiyor. Platform
  /// kimliği bir zenginleştirme; oyuncu oturum açmadıysa oyun yerel
  /// kimliğiyle sorunsuz çalışmaya devam ediyor.
  Future<bool> linkPlatformIdentity() async {
    if (!platform.isAvailable || _linking) return false;
    _linking = true;
    notifyListeners();
    try {
      final player = await platform.signIn();
      if (player == null) return false;
      _platformName = player.displayName;
      await store.savePlatformDisplayName(_platformName);
      return true;
    } finally {
      _linking = false;
      notifyListeners();
    }
  }

  /// Platform kimliğini bırakır; ad sözlükten üretilen yerel ada döner.
  ///
  /// Arkadaş kodu **değişmiyor**: kod paylaşıldıktan sonra değişirse karşı
  /// tarafın listesindeki kayıt sahipsiz kalırdı.
  Future<void> unlinkPlatformIdentity() async {
    if (_platformName == null) return;
    _platformName = null;
    await store.savePlatformDisplayName(null);
    notifyListeners();
  }

  // --- Arkadaşlar ---

  List<Friend> get friends => List<Friend>.unmodifiable(_friends);

  bool get hasFriends => _friends.isNotEmpty;

  Friend? friendByCode(String? code) {
    final normalized = FriendCode.normalize(code);
    if (normalized == null) return null;
    for (final friend in _friends) {
      if (friend.code == normalized) return friend;
    }
    return null;
  }

  /// Arkadaş ekler.
  ///
  /// Üç kapı: geçersiz kod, kendi kodun, zaten ekli. Üçü de sessizce
  /// geçilmez — arayüz her durumu oyuncuya söyler.
  FriendAddResult addFriend({
    required String? rawCode,
    required String displayName,
    int stationsDiscovered = 0,
  }) {
    final code = FriendCode.normalize(rawCode);
    if (code == null || displayName.trim().isEmpty) {
      return FriendAddResult.invalid;
    }
    if (code == _code) return FriendAddResult.self;
    if (friendByCode(code) != null) return FriendAddResult.alreadyAdded;

    _friends.add(
      Friend(
        code: code,
        displayName: displayName.trim(),
        stationsDiscovered: stationsDiscovered,
        addedOn: DayStamp.today(),
      ),
    );
    // Ada göre sıralı: liste ekleme sırasına göre dursaydı oyuncu kendi
    // arkadaşını aramak zorunda kalırdı.
    _friends.sort(
      (Friend a, Friend b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    analytics.log(AnalyticsEvent.friendAdded);
    unawaited(_persistFriends());
    notifyListeners();
    return FriendAddResult.added;
  }

  /// Arkadaşı listeden çıkarır.
  ///
  /// Sunucu yok, yani "engelleme" diye bir şey de yok: karşı tarafın
  /// listesinde kalmaya devam edebilirsin ve bunu değiştiremeyiz. Arayüz
  /// bu yüzden yalnızca "listemden çıkar" diyor; engelleme sözü vermiyor.
  void removeFriend(String code) {
    final normalized = FriendCode.normalize(code);
    if (normalized == null) return;
    _friends.removeWhere((Friend friend) => friend.code == normalized);
    unawaited(_persistFriends());
    notifyListeners();
  }

  // --- Meydan okuma ---

  /// Oynanmış bir koşudan meydan okuma üretir.
  Challenge createChallenge({
    required Journey journey,
    required String gameId,
    required int score,
  }) {
    final pair = ChallengeValidator.canonicalPair(journey);
    final challenge = Challenge(
      id: _newId(),
      gameId: gameId,
      lineId: journey.lineId,
      originId: pair.origin,
      destinationId: pair.destination,
      estimatedSeconds: journey.estimatedSeconds,
      targetScore: score,
      seed: newSeed(),
      creatorCode: _code,
      creatorName: me.displayName,
      createdOnEpochDay: DayStamp.today().epochDay,
    );
    analytics.log(
      AnalyticsEvent.challengeCreated,
      params: <String, String>{'game_id': gameId},
    );
    return challenge;
  }

  /// Yeni bir rastgelelik tohumu.
  int newSeed() => _random.nextInt(Challenge.maxSeed);

  String _newId() {
    // Kısa, çakışması pratikte imkânsız ve karekodda yer kaplamayan bir
    // kimlik: 48 bit, onaltılık.
    final high = _random.nextInt(1 << 24);
    final low = _random.nextInt(1 << 24);
    return (high.toRadixString(16).padLeft(6, '0') +
        low.toRadixString(16).padLeft(6, '0'));
  }

  // --- Geçmiş ---

  /// En yeniden eskiye meydan okuma geçmişi.
  List<ChallengeRecord> get history =>
      List<ChallengeRecord>.unmodifiable(_history);

  /// Geçmişte tutulan en fazla kayıt.
  ///
  /// Sınırsız bir liste tercih dosyasını büyütür ve kimse üç yüz maç
  /// öncesine bakmaz.
  static const int maxHistory = 50;

  /// Tamamlanmış bir meydan okumayı kaydeder.
  ///
  /// Aynı meydan okuma iki kez kaydedilmez: oyuncu sonuç panelini kapatıp
  /// tekrar açsa da geçmişte tek satır kalır.
  ChallengeRecord? recordResult({
    required Challenge challenge,
    required Journey journey,
    required int myScore,
  }) {
    if (_history.any(
      (ChallengeRecord record) => record.challengeId == challenge.id,
    )) {
      return null;
    }

    final record = ChallengeRecord(
      challengeId: challenge.id,
      opponentName: challenge.creatorName,
      opponentCode: challenge.creatorCode,
      gameId: challenge.gameId,
      lineId: challenge.lineId,
      originName: journey.origin.name,
      destinationName: journey.destination.name,
      originId: challenge.originId,
      destinationId: challenge.destinationId,
      myScore: myScore,
      targetScore: challenge.targetScore,
      seed: challenge.seed,
      estimatedSeconds: challenge.estimatedSeconds,
      playedOn: DayStamp.today(),
    );

    _history.insert(0, record);
    if (_history.length > maxHistory) _history.removeLast();

    analytics.log(
      AnalyticsEvent.challengeCompleted,
      params: <String, String>{
        'game_id': challenge.gameId,
        'outcome': record.outcome.name,
      },
    );
    unawaited(_persistHistory());
    notifyListeners();
    return record;
  }

  /// Geçmişteki bir maçtan rövanş meydan okuması kurar.
  ///
  /// Rota, oyun ve süre aynı; tohum yeni ve hedef **senin skorun** — sıra
  /// artık karşı tarafta.
  Challenge rematchFrom(ChallengeRecord record) {
    final challenge = record.rematch(
      id: _newId(),
      seed: newSeed(),
      myCode: _code,
      myName: me.displayName,
      today: DayStamp.today().epochDay,
    );
    analytics.log(
      AnalyticsEvent.rematchCreated,
      params: <String, String>{'game_id': record.gameId},
    );
    return challenge;
  }

  // --- Kalıcılık ---

  Future<void> _persistFriends() async {
    try {
      await store.saveFriends(Friend.encodeList(_friends));
    } catch (error, stack) {
      debugPrint('Arkadaş listesi yazılamadı: $error\n$stack');
    }
  }

  Future<void> _persistHistory() async {
    try {
      await store.saveChallengeHistory(ChallengeRecord.encodeList(_history));
    } catch (error, stack) {
      debugPrint('Meydan okuma geçmişi yazılamadı: $error\n$stack');
    }
  }

  /// Bekleyen yazımları tamamlar — uygulama arka plana düşerken.
  Future<void> flush() async {
    await _persistFriends();
    await _persistHistory();
  }
}
