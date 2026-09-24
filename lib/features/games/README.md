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
    blocks/         Blok Metro (artık o da motoru kullanıyor)
    metro_merge/    Hat Birleştir
    rail_flight/    Ray Uçuşu
    merge_drop/     Hat Düşür
    metro_quiz/     Metro Bilgi
    lane_runner/    Ray Değiştir
    tunnel_escape/  Tünele Kaç (bölümlü bulmaca, aşağıda)
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

- `GameSound.arrival` — **metro kapı sesi**, durağa varınca bir kez. Çalarken
  kısa efektler susar; varış karesinde başka ses çalmanın sakıncası yok.
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

## Bölümlü oyun: Tünele Kaç

Diğer oyunlar sonsuz; Tünele Kaç **60 sabit bölümlü** bir kaydırmalı
bulmaca. Yolculuk motorunu aynen kullanıyor, üstüne üç şey ekliyor:

- **Saf Dart alan katmanı** (`tunnel_escape/domain/`): hareket, çarpışma,
  BFS çözücü. Flutter içe aktarmıyor; bölüm üretim aracı
  (`tool/tunnel_escape/generate_levels.dart`) aynı kodu `dart run` ile
  kullanıyor.
- **Veri olarak bölümler** (`tunnel_escape/data/escape_level_grids.dart`):
  ızgara metni + çözücünün en kısa çözümü + yıldız sınırları.
  `test/tunnel_escape/escape_levels_test.dart` her bölümü çözücüyle yeniden
  doğruluyor; veri elle düzenlenirse test yakalar.
- **Kalıcı bölüm kaydı** (`EscapeProgressController`, `LocalStore`
  `tunnel_escape_progress_v1`): bitirilen bölüm, en iyi hamle, yıldız.
  Yolculuktan bağımsız; açık bölümler bu kayıttan **türetiliyor**. Her
  sonuç kazanıldığı bulmacanın parmak iziyle yazılıyor: bölümler yeniden
  tasarlanırsa bitirme korunur, eski hamle ve yıldız yeni bulmacaya
  taşınmaz (`EscapeProgress.reconcile`).
- **Zorluk yalnız hamle sayısı değil** (`domain/escape_heuristics.dart`):
  bölüm seçimi zorunlu "önce uzaklaş" hamlelerine ve göze iyi gelen hamleyi
  yapan bir oyuncunun bölümü bitirip bitiremediğine de bakıyor. Eğri ve
  kuşak kuralları üretim aracında, `report` hepsini tablo olarak basar.

Yolculuk puanı bitirilen bölümden gelir ve tekrar oynayarak kasılamaz
(`EscapeRules.journeyPoints`). Bölüm bitirmeden çıkılan koşu diğer
oyunlardaki gibi sayılmaz; en az bir bölüm bitmişse çıkış koşuyu bitirir.

