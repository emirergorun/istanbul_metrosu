import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Oyunun kısa arayüz sesleri.
enum GameSound {
  place('place'),
  clear('clear'),
  combo('combo'),
  station('station'),
  arrival('arrival'),
  invalid('invalid');

  const GameSound(this.file);

  final String file;

  String get asset => 'audio/$file.wav';
}

/// Ses çalma servisi.
///
/// İki ürün kararı burada gömülü:
///
/// 1. **Kullanıcının müziğini kesmez.** Metroda çoğu kişi kulaklıkla müzik
///    dinler; iOS ses oturumu `ambient` + `mixWithOthers` olarak ayarlanır ve
///    sessiz moda saygı gösterilir. Aksi hâlde ilk blok sesinde Spotify durur.
/// 2. **Ses varsayılan olarak kapalıdır.** Kulaklıksız bir vagonda telefonun
///    ötmesi kimsenin istediği bir şey değil; açmak kullanıcının tercihi.
class AudioService {
  AudioService();

  final Map<GameSound, AudioPlayer> _players = <GameSound, AudioPlayer>{};
  bool _ready = false;
  bool enabled = false;

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

      for (final sound in GameSound.values) {
        final player = AudioPlayer(playerId: sound.name)
          ..setReleaseMode(ReleaseMode.stop)
          ..setPlayerMode(PlayerMode.lowLatency);
        await player.setSource(AssetSource(sound.asset));
        _players[sound] = player;
      }
      _ready = true;
    } catch (error, stack) {
      // Ses kurulamazsa oyun sessiz çalışmaya devam eder.
      debugPrint('AudioService init başarısız: $error\n$stack');
      _ready = false;
    }
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

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();
    _ready = false;
  }
}
