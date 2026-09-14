# Oyunlar

Her oyun kendi klasöründe yaşar ve **başka bir oyunun dosyasına dokunmaz.**

```
features/
  session/          ← her oyunun paylaştığı yolculuk katmanı
    journey_status.dart          GameStatus (ready/playing/arrived/gameOver…)
    journey_run.dart             JourneyRun sözleşmesi
    journey_game_controller.dart YOLCULUK MOTORU: sayaç, varış, durak
                                 bonusu, rekor takibi ve kaydı
    widgets/                     varış sahnesi, duraklatma, sonuç paneli,
                                 ilerleme çubuğu — hepsi oyundan bağımsız
  games/
    catalog/        oyun listesi + seçim ekranı
    blocks/         Blok Metro
    metro_merge/    Hat Birleştir
    rail_flight/    Ray Uçuşu
    merge_drop/     Hat Düşür
    metro_quiz/     Metro Bilgi
    lane_runner/    Ray Değiştir
    game2/          yeni oyun buraya
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

**3. Controller'ını `JourneyGameController`'dan türet.** Sayaç, varış
tespiti, durak bonusu, rekor takibi ve kaydı hazır gelir. Sen yalnızca
kancaları doldurursun:

| Kanca | Ne zaman |
|---|---|
| `onTick(dt)` | her karede kendi güncellemen (gerçek zamanlı oyunlar) |
| `onRestart()` | "tekrar oyna"da kendi durumunu sıfırla |
| `onPause` / `onResume` / `onAbandon` / `onFinish` | kendi sayaçların varsa |

Ve şu araçları kullanırsın:

| Araç | Ne yapar |
|---|---|
| `addScore(puan)` | puan ekler, rekor geçildiyse işaretler |
| `markStationProgress()` | "bu duraktan beri kayda değer bir şey yaptım" |
| `endGame()` | oyun kendi kuralıyla bitti (çarpıştı, hamle kalmadı…) |

`static const String id` tanımla — rekor anahtarında kullanılır, sonradan
değiştirme. (`gameId` adı motorun alanı olduğu için kullanılamaz.)

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

**`blocks/` hâlâ kendi yolculuk motorunu taşıyor.** Diğer beş oyun
`JourneyGameController`'a taşındı; Blok Metro taşınmadı çünkü skoru, süresi
ve durumu immutable bir `GameSession` içinde tutuyor ve bu yapı iki şeye daha
hizmet ediyor: **geri alma** (tek satırda anlık görüntü) ve **yarım kalan
oyun kaydı** (`GameSnapshot`). Motora taşımak kayıt biçimini de değiştirmek
demek; ayrı bir iş olarak ele alınmalı.

Pratik sonucu: Blok Metro rekorunu eski (oyundan bağımsız) anahtarla yazıyor,
diğerleri oyun bazlı anahtarla. Ayarlar ekranı ikisini de doğru gösterir.
