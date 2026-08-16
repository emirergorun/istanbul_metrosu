import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Oyunun ses efektleri.
enum GameSound {
  place('place'),
  clear('clear'),
  combo('combo'),
  station('station'),

  /// Varış (metro kapısı) — 4 saniyelik tören sesi, kısa bir tık değil.
  arrival('arrival', longForm: true),

  invalid('invalid');

  const GameSound(this.file, {this.longForm = false});

  final String file;

  /// Uzun ses mi?
  ///
  /// `lowLatency` modu ardışık kısa tıklar için tasarlanmıştır ve uzun
  /// dosyalarda güvenilir çalmaz — varış sesi (4 sn, 48 kHz, stereo) bu
  /// yüzden hiç duyulmuyordu. Uzun sesler normal medya çalar kullanır;
  /// birkaç milisaniyelik gecikmenin tören sesinde bir önemi yok.
  final bool longForm;

  String get asset => 'audio/$file.wav';
}

/// Ses çalma servisi.
///
/// İki ürün kararı burada gömülü:
///
/// 1. **Kullanıcının müziğini kesmez.** Metroda çoğu kişi kulaklıkla müzik
///    dinler; iOS ses oturumu `ambient` olarak ayarlanır: diğer seslerle
///    karışır ve sessiz moda saygı gösterir. Aksi hâlde ilk blok sesinde
///    Spotify durur.
/// 2. **Ses varsayılan olarak kapalıdır.** Kulaklıksız bir vagonda telefonun
///    ötmesi kimsenin istediği bir şey değil; açmak kullanıcının tercihi.
///
/// Efektler ve müzik **ayrı** açılıp kapanır. Kısa bir blok sesiyle sürekli
/// çalan bir piyano aynı şey değil: vagonda efektleri açık tutup müziği
/// kapatmak isteyen biri için tek anahtar yetmez.
class AudioService {
  AudioService();

  /// Arka plan müziği (döngü). Efektlerden ayrı bir player: efektler
  /// `lowLatency`, müzik `mediaPlayer` modunda ve durdurulup sürdürülüyor.
  static const String musicAsset = 'audio/music_ambient.wav';

  final Map<GameSound, AudioPlayer> _players = <GameSound, AudioPlayer>{};
  AudioPlayer? _music;
  bool _ready = false;
  bool enabled = false;

  /// Müzik tercihi. Kapatılınca çalan müzik anında durur.
  bool get musicEnabled => _musicEnabled;
  bool _musicEnabled = false;
  set musicEnabled(bool value) {
    if (_musicEnabled == value) return;
    _musicEnabled = value;
    if (value) {
      if (_musicShouldPlay) unawaited(_startMusic());
    } else {
      unawaited(_music?.stop() ?? Future<void>.value());
    }
  }

  /// Oyun ekranı müziği istiyor mu? (Duraklatma ve arka plan bunu düşürür.)
  bool _musicShouldPlay = false;

  /// Ses oturumunu kurar ve **kısa efektleri** yükler.
  ///
  /// Müzik burada yüklenmez: 4 MB'lık bir dosyayı açılışta beklemek
  /// audioplayers'ın 30 sn'lik zaman aşımına takılıyordu ve tek bir arıza
  /// tüm sesi susturuyordu. Müzik ilk çalma isteğinde yüklenir.
  ///
  /// Her kaynak **ayrı** try/catch içinde: biri patlarsa diğerleri sağ kalır.
  Future<void> init() async {
    if (_ready) return;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          // `ambient` iOS'ta zaten tanımı gereği diğer seslerle karışır ve
          // sessiz moda saygı gösterir; `mixWithOthers` seçeneğini ayrıca
          // vermek gerekmez. Üstelik audioplayers bunu yasaklıyor: seçenek
          // yalnızca playback/playAndRecord/multiRoute ile açıkça verilebilir,
          // aksi hâlde AudioContextIOS kurucusu assert atar. Bu assert debug
          // modunda tüm ses sistemini sessizce devre dışı bırakıyordu
          // (init throw eder -> _ready false kalır -> play() hiç çalmaz).
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.game,
            audioFocus: AndroidAudioFocus.none,
          ),
        ),
      );
    } catch (error, stack) {
      // Ses oturumu kurulamazsa bile efektleri denemeye değer.
      debugPrint('Ses oturumu kurulamadı: $error\n$stack');
    }

    for (final sound in GameSound.values) {
      try {
        final player = AudioPlayer(playerId: sound.name)
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(
            sound.longForm ? PlayerMode.mediaPlayer : PlayerMode.lowLatency,
          );
        await player.setSource(AssetSource(sound.asset));
        _players[sound] = player;
      } catch (error) {
        // Tek bir ses yüklenemezse yalnızca o ses susar.
        debugPrint('Ses yüklenemedi (${sound.name}): $error');
      }
    }

    _ready = true;
  }

  void play(GameSound sound) {
    if (!enabled || !_ready) return;
    final player = _players[sound];
    if (player == null) return;
    // Aynı ses üst üste gelirse baştan başlat.
    player.stop().then((_) => player.resume()).catchError((Object error) {
      debugPrint('Ses çalınamadı (${sound.name}): $error');
    });
  }

  // --- Arka plan müziği ---

  /// Oyun başladı/sürüyor: müzik çalsın (tercih açıksa).
  void resumeMusic() {
    _musicShouldPlay = true;
    if (!_musicEnabled || !_ready) return;
    unawaited(_startMusic());
  }

  /// Oyun duraklatıldı ya da uygulama arka plana alındı.
  ///
  /// `stop` değil `pause`: kullanıcı geri döndüğünde parça kaldığı yerden
  /// devam etsin, her duraklatmada baştan başlamasın.
  void pauseMusic() {
    _musicShouldPlay = false;
    if (!_ready) return;
    unawaited(
      _music?.pause().catchError((Object error) {
            debugPrint('Müzik duraklatılamadı: $error');
          }) ??
          Future<void>.value(),
    );
  }

  /// Oyun ekranından çıkıldı: müzik biter ve başa sarar.
  void stopMusic() {
    _musicShouldPlay = false;
    if (!_ready) return;
    unawaited(
      _music?.stop().catchError((Object error) {
            debugPrint('Müzik durdurulamadı: $error');
          }) ??
          Future<void>.value(),
    );
  }

  /// Müzik player'ını ilk ihtiyaçta kurar.
  ///
  /// Dosya büyük (~4 MB); açılışta yüklemek uygulamayı geciktiriyor ve
  /// zaman aşımına takılabiliyordu. Burada yüklenirse yalnızca müzik
  /// gecikir, efektler ve oyun etkilenmez.
  Future<AudioPlayer?> _ensureMusic() async {
    if (_music != null) return _music;
    if (_musicLoading) return null;
    _musicLoading = true;
    try {
      final player = AudioPlayer(playerId: 'music')
        ..setReleaseMode(ReleaseMode.loop)
        ..setPlayerMode(PlayerMode.mediaPlayer);
      await player.setSource(AssetSource(musicAsset));
      _music = player;
    } catch (error) {
      debugPrint('Müzik yüklenemedi: $error');
    } finally {
      _musicLoading = false;
    }
    return _music;
  }

  bool _musicLoading = false;

  Future<void> _startMusic() async {
    final player = await _ensureMusic();
    if (player == null) return;
    // Yükleme sırasında oyun duraklamış olabilir.
    if (!_musicShouldPlay || !_musicEnabled) return;
    try {
      await player.resume();
    } catch (error) {
      debugPrint('Müzik çalınamadı: $error');
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    await _music?.dispose();
    _music = null;
    _ready = false;
  }
}
