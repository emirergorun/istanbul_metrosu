# Oyunlar

Her oyun kendi klasöründe yaşar ve **başka bir oyunun dosyasına dokunmaz.**

```
features/
  session/          ← her oyunun paylaştığı yolculuk katmanı
    journey_status.dart   GameStatus (ready/playing/arrived/gameOver…)
    journey_run.dart      JourneyRun sözleşmesi
    widgets/              varış sahnesi, duraklatma, sonuç paneli,
                          ilerleme çubuğu — hepsi oyundan bağımsız
  games/
    catalog/        oyun listesi + seçim ekranı
    blocks/         1. oyun: Blok Metro
    game2/          2. oyun buraya
```

## Yeni oyun eklemek

**1. Klasörünü aç.** `features/games/game2/`. Blok oyununun içindeki hiçbir
dosyayı açman gerekmez.

**2. Kataloğa kaydet.** `catalog/mini_game.dart` içine bir `MiniGame` ekle ve
`isAvailable: true` yap. Seçim ekranı listeyi olduğu gibi çizer; ekrana
dokunmana gerek yok.

```dart
static const MiniGame transfer = MiniGame(
  id: 'transfer',          // kalıcı kimlik, sonradan değiştirme
  name: 'Aktarma',
  tagline: 'Yolcuları doğru hatta yönlendir.',
  icon: Icons.alt_route_rounded,
  isAvailable: true,
);
```

**3. Controller'ında `JourneyRun`'ı uygula.** Sözleşme
`session/journey_run.dart` içinde: skor, durum, ilerleme, rekor ve
başlat/duraklat/devam/yeniden-başlat.

**4. Ortak parçaları kullan.** `session/widgets/` altındakiler oyundan
bağımsızdır ve doğrudan kullanılabilir:

| Widget | Ne verir |
|---|---|
| `JourneyProgressBar` | alttaki metro ilerleme şeridi |
| `ArrivalSequence` | tren gelir, kapılar açılır |
| `ResultOverlay` | sonuç paneli (`extraStats` ile kendi satırlarını ekle) |
| `PauseOverlay` | duraklatma paneli |

## Sesler her oyunda ortak

`core/audio/audio_service.dart` tek yerdir; her oyun aynı `GameSound`
değerlerini kullanır:

- `GameSound.arrival` — **metro kapı sesi**, durağa varınca bir kez
- `GameSound.station` — ara durak geçilince
- `place` · `clear` · `combo` · `invalid` — oyunun kendi geri bildirimi
- Arka plan müziği `resumeMusic()` / `pauseMusic()` / `stopMusic()` ile

Kullanıcı ayarlarında ses efektleri ve müzik **ayrı** açılıp kapanır; oyunun
bunu kontrol etmesi gerekmez, `AudioService` zaten uyar.

## Bilinen sınır

`blocks/` bugün yolculuk motorunu (sayaç, varış tespiti, durak bonusu, rekor
kaydı) kendi `GameController`'ı içinde taşıyor. İkinci oyun yazılırken bu
motor `session/` altına çıkarılmalı ki iki oyun aynı kodu paylaşsın —
soyutlamayı ikinci somut örnek ortaya çıkmadan sabitlemek erken olurdu.
