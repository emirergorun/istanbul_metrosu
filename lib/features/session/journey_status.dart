/// Bir yolculuk oturumunun durumu.
///
/// Oyundan bağımsızdır: hangi oyun oynanırsa oynansın yolculuk aynı
/// aşamalardan geçer.
///
/// - [arrived]: yolculuk süresi doldu. **Oyunun tek finali budur** ve varış
///   sahnesi (tren gelir, kapılar açılır, kapı sesi çalar) burada oynar.
/// - [gameOver]: oyuncu oyunun kendi kurallarına takıldı (blok oyununda
///   hamle kalmaması). Tören yok, sade panel.
enum GameStatus { setup, ready, playing, paused, arrived, gameOver, abandoned }

extension GameStatusX on GameStatus {
  bool get isFinished =>
      this == GameStatus.arrived || this == GameStatus.gameOver;

  bool get isActive => this == GameStatus.playing;
}
