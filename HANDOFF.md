# HANDOFF — İstanbul Metrosu Oyunu (MVP)

Bu belge, MVP vertical slice'ı devralacak yazılımcı için yazılmıştır.
Ürün bağlamı için Obsidian vault'taki `00 - İstanbul Metrosu Oyunu.md` ve
`01 - MVP.md` notlarına bakın.

---

## 1. Kurulum ve Komutlar

| Amaç | Komut |
|---|---|
| Bağımlılıklar | `flutter pub get` |
| iOS simulator | `flutter run -d <simulator-udid>` |
| Testler | `flutter test` |
| Statik analiz | `flutter analyze` |
| Format | `dart format lib test` |
| Release (iOS) | `flutter build ios --release` |

Doğrulanan sürümler: **Flutter 3.44.9 / Dart 3.12.2**, Xcode 26.6,
iPhone 17 simulator (iOS 26.5).

iOS ilk derlemede CocoaPods gerekir (`shared_preferences` native tarafı için):

```bash
brew install cocoapods
```

---

## 2. Mimari Kararlar

### Katmanlar

```text
presentation  →  application  →  domain
       ↘  data (metro) ↗
```

- **domain**: Flutter'a bağımlı olmayan saf kurallar. Widget import etmez.
  Tüm oyun mantığı burada ve unit test ile doğrulanmıştır.
- **application**: `GameController` (ChangeNotifier) + `PieceGenerator`.
  Oturum durumunu yönetir, timer'ı tutar, domain fonksiyonlarını çağırır.
- **presentation**: Yalnızca çizim ve input. Kural bilmez.
- **data/metro**: `MetroRepository` arayüzü + gömülü implementasyon.
  Production verisi geldiğinde **sadece bu katman** değişir.

### State management

Ek paket yok. `ChangeNotifier` + `InheritedWidget` (`AppScope`).
Ekran sayısı ve state karmaşıklığı Riverpod'u haklı çıkarmıyor; ölçek
büyürse `GameController` olduğu gibi bir Riverpod provider'ına sarılabilir.

### Immutability

`Board` ve `GameSession` immutable'dır. Bunun iki faydası var:
undo tek satırda snapshot almakla çalışıyor ve testler yan etkisiz.
Performans sorunu yok — 8x8 grid kopyası önemsiz.

### Tipografi ve marka dili

Yazı tipleri `assets/fonts/` içinde gömülüdür ve `AppFonts` üzerinden
kullanılır: tek satıra sığan büyük başlıklarda (≥ 20 pt) `Bungee`,
diğer her yerde `Plus Jakarta Sans` (400 / 500 / 700 / 800). İki satıra
taşabilen başlıklar (onay pencereleri, hata ekranı) `AppText.heading` ile
Plus Jakarta Sans ExtraBold'dadır.

- **Bungee** (SIL OFL 1.1) tek ağırlıklıdır; stillerde `w400` kalmalı,
  daha kalını Flutter'ın sahte kalınlaştırmasıyla harfleri bozar. Özgün dosya
  küçük `i`'yi noktasız çizip Türkçe `locl` kuralı taşımadığı için `cmap`
  içinde `i` → `Idotaccent` eşlendi:

  ```python
  from fontTools.ttLib import TTFont
  t = TTFont("Bungee-Regular.ttf")
  for table in t["cmap"].tables:
      if table.isUnicode() and 0x69 in table.cmap:
          table.cmap[0x69] = "Idotaccent"
  t.save("Bungee-Regular.ttf")
  ```

  Font google/fonts'tan yeniden indirilirse bu adım tekrarlanmalı.
- **Plus Jakarta Sans** (SIL OFL 1.1) google/fonts'ta yalnızca değişken
  dosya olarak var; sabit ağırlıklar şöyle üretildi:

  ```python
  from fontTools.ttLib import TTFont
  from fontTools.varLib.instancer import instantiateVariableFont
  for w, n in {400: "Regular", 500: "Medium", 700: "Bold", 800: "ExtraBold"}.items():
      f = instantiateVariableFont(TTFont("PlusJakartaSans[wght].ttf"), {"wght": w})
      f["OS/2"].usWeightClass = w
      f.save(f"PlusJakartaSans-{n}.ttf")
  ```

Lisans metinleri asset olarak paketlenir ve `main.dart` içinde
`LicenseRegistry`'ye kaydedilir — silinmemeli.

Ana ekran düzeni metro.istanbul'daki yolculuk planlayıcısını referans alır
(A/B alanları, lacivert başlık şeridi, kırmızı alt şerit). Resmi logo veya
amblem kullanılmaz.

### Board temsili

`List<List<int>>`: `0` boş, `1..6` blok rengi, `9` engel.
Engel hücreleri normal dolu hücre gibi davranır ve **temizlenebilir**;
kalıcı ölü hücre bırakmamak için bilinçli bir karardır.

---

## 2b. Meta Katmanlar — Keşif, Günlük, Pasaport

Oyunların üstünde üç katman var ve üçü de **tek bir kaynağa** dayanıyor.
Birinin kendi sayacını tutması, o sayacın er geç kaynaktan ayrı düşmesi
demek; mimarinin tamamı bunu engellemek üzerine kurulu.

```text
OYUN
 ↓  JourneyGameController._finish
RunReport  (rota, oyun, sonuç, geçilen durak)
 ↓  CompositeRunReporter
DailyController  +  AchievementController
```

### V1a — İstanbul Keşfi (`lib/features/discovery/`)

Kalıcı olarak saklanan **tek** şey keşfedilen fiziksel durak kimlikleri
(`discovered_stations`). Yüzde, hat tamamlanması, aktarma sayısı: hepsi
türetilir. Kaydedilselerdi `metro.json`'a bir hat eklendiği gün yalan
söylerlerdi.

- `DiscoveryCatalog` — hat kapsamlı `Station` kayıtlarını **fiziksel**
  duraklara (`canonicalId`) indirger. Yenikapı üç kayıt, bir durak.
- `JourneyDiscovery` — tek koşunun defteri. Motor "kaç durak geçildi" der,
  keşif kuralı burada kalır. Yedi oyunun hiçbiri durak kimliği görmez.
- `DiscoveryController` — kalıcı durum. Hat sayaçları ve aktarma sayısı
  yazma anında güncellenen **önbellek**; diske yazılmaz, her açılışta
  kümeden yeniden kurulur.

Bildirimler `scheduleMicrotask` ile kare başına bire indiriliyor. Biniş
durağı `didChangeDependencies` içindeki `start()` çağrısıyla keşfediliyor,
yani build sırasında; doğrudan `notifyListeners` "setState() called during
build" hatası veriyordu.

### V3 — Günlük Yolculuk (`lib/features/daily/`)

İki kavram ayrı:

| | Nerede | Saklanır mı? |
|---|---|---|
| **Plan** (rota, oyun, görevler) | `DailyGenerator` | Hayır — takvim gününden türer |
| **İlerleme** (sayaçlar) | `DailyCounters` | Evet — `daily_counters` |
| **Seri** | `StreakState` | Evet — `daily_streak` |

- **Determinizm.** Tohum FNV-1a + xorshift32. `dart:math`'ın `Random`'ı
  kullanılmadı: tohumdan üretilen dizinin Dart sürümleri arasında aynı
  kalacağı garanti değil ve bir güncelleme günün rotasını gün ortasında
  değiştirebilirdi.
- **Oyun rotasyonu.** `(epochDay × adım) % oyunSayısı`, adım oyun sayısıyla
  aralarında asal. Bütün oyunlar sırayla gelir, iki gün üst üste aynı oyun
  düşmez.
- **Görevler sayaçlardan türer.** Görev başına ilerleme saklanmaz; bkz.
  `DailyMission.progressFrom`.
- **Keşif görevi keşif durumuna duyarlı.** Kalan durak hedeften azsa hedef
  kırpılır, hiç kalmadıysa görev üretilmez. İkisi de tek yönlü: keşif geri
  gitmediği için gün içinde görev zorlaşamaz.
- **Anlamlı koşu.** Sayaçlar yalnız `RunReport.isMeaningful` olan koşuyu
  görür: varış, ya da en az bir durak geçilmiş bir oyun sonu. Oyunu açıp
  iki saniyede kaybetmek "oyun bitirmek" değil.
- **Seri.** Takvim günü üzerinden, `DayStamp` ile. Gün farkı sivil takvim
  formülüyle (Hinnant `days_from_civil`) hesaplanır — süre hesabı yaz saati
  gecesinde 23 saat çıkarıp seriyi sessizce kırardı. Her serinin **bir**
  af hakkı var: bir gün kaçırmak seriyi bitirmez, iki gün bitirir. Hak seri
  kırıldığında tazelenir.

### V4 — İstanbul Pasaportu (`lib/features/passport/`)

Pasaport **ikinci bir ilerleme veritabanı değil**. Keşif ekranı pasaporta
dönüştü (`DiscoveryScreen`, başlık `PASAPORTUM`); bölümler: İSTANBUL KEŞFİ →
GÜNLÜK → BAŞARIMLAR → HATLAR.

`AchievementController` ölçüyü kaynağından okur:

| Ölçü | Kaynak |
|---|---|
| Keşfedilen durak, aktarma, tamamlanan hat | `DiscoveryController` |
| En uzun seri, toplam gün | `DailyController` |
| Metro Bilgi rekoru | `LocalStore.bestScoreForGame` |
| Tamamlanan yolculuk, oynanan oyunlar | `PlayerStats` (`player_stats`) |

Yalnız son satır saklanıyor, çünkü türetilemiyor. Açılma kaydı
`achievements_unlocked` içinde `kimlik@yyyy-MM-dd` biçiminde; tarihsiz eski
biçim de okunur. Geriye dönük göçte tarih **yazılmaz** — rozet ne zaman hak
edildi bilinmiyor, uydurulmuyor.

İlk kurulum sessiz (`_evaluate(announce: false)`): V4'ten önce 40 durak
keşfetmiş oyuncuya açılışta beş rozet birden patlamaz.

### Yeni oyun eklerken

Meta katmanlara **dokunmak gerekmiyor**. `MiniGames` kataloğuna kayıt,
ekranda iki satır:

```dart
final controller = YeniOyunController(
  journey: widget.journey,
  discovery: scope.discoveryFor(widget.journey, YeniOyunController.id),
  ...
);
controller.reporter = scope.runReporter;
```

Gerisi — keşif, günlük görev, seri, başarım, sonuç paneli — kendiliğinden
gelir.

---

## 3. Tasarım Notlarından Sapmalar

Hepsi bilinçlidir ve ürün gereksinimini değiştirmez:

0. **Hedef skor kaldırıldı.** Amaç, o rotadaki kendi rekorunu geçmek.
   `DifficultyProfile.targetScore` silindi; rekor `LocalStore` içinde
   **rota bazında** (sıralı durak çifti) tutulur. Sabit hedef, yolculuğun
   ortasında ulaşılınca geriye amaç bırakmıyordu ve uzun hatlarda hiç
   ölçülmemişti.

1. **`GameStatus.arrived` eklendi, `victory` kaldırıldı.** Varış oyunun tek
   finalidir. Hedef skora yolculuk bitmeden ulaşmak oyunu **durdurmaz**;
   yalnızca `GameSession.targetReached` işaretlenir ve
   `PlaceOutcome.reachedTarget` ile bir kez bildirim gösterilir. Böylece
   akışta tek doruk nokta kalır. Bitişler: `arrived` (tören + kutlama) ve
   `gameOver` (sade, törensiz).
2. **Dikey parça varyantları eklendi.** MVP parça listesinde `1x4` var ama
   `4x1` yoktu; L-3/L-5/T-4/T-5'in dönmüş varyantları da katalogda ayrı
   şekil olarak duruyor. MVP'de runtime rotasyon yok, bu yüzden varyantlar
   hazır şekil olmalı — yoksa parça havuzu tek yönlü ve yapay olurdu.
3. **Engel hücreleri en üst satıra konmuyor.** Oyun açılışında tepedeki
   satırın kilitli hissettirmesini engellemek için.
4. **Combo çarpanı yalnızca hat puanına uygulanır**, yerleştirme puanına
   değil. Notta "base x comboMultiplier" yazıyordu; "base"i hat puanı
   olarak yorumladık, aksi halde combo skoru çok hızlı şişiriyor.

---

## 4. Bilinen Sınırlar

| # | Sınır | Etki |
|---|---|---|
| 1 | Aktarma yok | İki durak aynı hatta olmalı |
| 2 | Durak arası süreler türetilmiş | Kenar bazında resmi veri yayınlanmıyor |
| 2b | M11 eklenmedi | TCDD işletiyor, metro.istanbul'da yayınlanmıyor |
| 3 | Tek tema (koyu), yalnız portrait | Light tema ve yatay yok |
| 3b | Kurumsal renk/tipografi referansı | Ticari yayın öncesi marka incelemesi şart |
| 4 | Ses efekti yok | Haptic var, opsiyonel; ayar UI'ı yok |
| 5 | Uzun yolculuklarda varış hâlâ zor | Durak rahatlamasından sonra 7 sn/hamle temposunda Uzun %48, Maraton %35; 4 sn/hamle gibi hızlı bir tempoda %1-2 |
| 6 | Skor yalnız local | Cloud save/leaderboard yok (MVP dışı) |
| 6b | Yazılı sorular doğrulanmadı | 62 soru yazıldı, kaynak alanları dolu ama içerik incelemesi yapılmadı |
| 7 | Yazı ölçeği 1.6'da sınırlı | Tahta/HUD düzeni ölçekten bağımsız değil |
| 8 | Piece rotasyonu yok | Katalog varyantlarla telafi ediliyor |
| 9 | Endless modda hedef sabit kalır | Zafer sonrası yeni hedef gelmiyor |
| 10 | Rekor hat bazında | "Rota bazında rekor" yok |
| 11 | Durak bonusu ve sprint dengelenmedi | +25 ve ×2 tahmin; ölçülmedi |
| 12 | Rekor sıfırlama yok | Yanlışlıkla yüksek rekor kurulursa rota oynanamaz hâle gelebilir |

---

## 4b. Backlog — Ertelenmiş Sürümler

Bunlar **bilinçli olarak yapılmadı**. Her birinin neden ertelendiği yazılı;
gerekçe okunmadan başlanmamalı.

### V1b — Metro Bilgi: 1 doğru = 1 durak

Negatif binom hesabı yapıldı: mevcut can ve süre dengesiyle uçtan uca bir
hatta varış oranı %0,9 ile %10 arasına düşüyor. Önce can/süre formülünün
simülasyonu gerekiyor. Soru veritabanına ve cana **dokunulmadı**.

### Game Center — bugün ne yapıyor, ne yapmıyor

**Yapıyor:** oyuncu isterse görünen adı Game Center takma adına çeviriyor.
`ios/Runner/AppDelegate.swift` içindeki `GameCenterBridge` yalnız `alias`
döndürüyor.

**Neden `displayName` değil:** Apple'ın belgelediği davranışa göre
`GKPlayer.displayName`, bakan kişi oyuncunun arkadaşıysa **gerçek adı**
döndürüyor. Bu üründe ad bir karekoda giriyor ve o kareyi tanımadığı biri
okuyabiliyor. Gerçek ad oraya asla girmemeli.

**Yapmıyor:** arkadaş listesi çekmiyor, skor tablosu yazmıyor, başarım
göndermiyor. `GKLocalPlayer.loadFriends` onay kapılı ve salt okunur;
GameKit oyuna arkadaş ekleme, oyuncu arama ya da istek gönderme yetkisi
vermiyor. Uygulamanın arkadaş katmanı bu yüzden kendine ait.

**Android:** `UnavailableGamingService`. Play Games v2 bir Play Console
uygulama kimliği ve manifest girdisi istiyor; kimlik olmadan SDK açılışta
çöküyor. Kimlik hazır olduğunda yapılacak tek şey `GameCenterService`
yanına bir `PlayGamesService` koyup `app.dart`'ta platforma göre seçmek.

**Sınırlar:**

- Takma ad **kalıcı** yazılıyor (`platform_display_name`). Oyuncu Game
  Center'dan çıkarsa ad bayat kalır; "KALDIR" ile yerel ada dönülüyor.
- Oturum açma 12 saniyede zaman aşımına uğruyor: GameKit çevrimdışıyken
  askıda kalabiliyor.
- **Gerçek cihazda doğrulanmadı.** Simülatörde köprünün çağrıldığı ve
  başarısızlığın nazikçe yutulduğu görüldü; başarılı bir oturum açma
  App Store Connect kaydı gerektiriyor.

### V5b — Yakındaki oyuncu / canlı yarış

V5a arkadaş ve meydan okuma katmanını kurdu; V5b aynı vagondaki iki
telefonu **canlı** yarıştıracak.

Kapsam:

- İki cihazın eşleşmesi (tek karekod ya da yerel keşif).
- Koşu sırasında skorun karşılıklı akması; "önde/geride" canlı.
- Bitişte iki tarafın da doğruladığı ortak sonuç.
- Gerçek karşılaşma tablosu — V5a'da **kasten yok**, çünkü iki cihazın
  geçmişi birbirini doğrulayamıyor.

Bilinen kısıtlar, araştırıldı:

- **Play Games** gerçek zamanlı ve sıra tabanlı çok oyuncu API'lerini
  31 Mart 2020'de kapattı; yeni oyunlara açılmıyor.
- **Game Center** eşleştirme sunuyor ama arkadaş listesi salt okunur ve
  onay kapılı; oyun içinde arkadaş eklemeye izin vermiyor.
- Yani taşıma katmanı **kendi işimiz**: yerel ağ, Bluetooth ya da hafif
  bir sunucu. Üçü de yeni bir izin yüzeyi ve yeni bir hata durumu demek.

Hazır olan: `PlatformGamingService`, `ChallengeCodec`, `ChallengeSession`
ve tohumlu adalet modeli. V5b'nin yeniden yazması gereken şey yalnızca
taşıma ve eşleşme.

### Diğer backlog

- **Aktarmalı rota.** Bugün iki durak aynı hatta olmalı; Dijkstra + aktarma
  kenarları gerekiyor (`RouteService`).
- **Meydan okuma kalıcılığı.** Kabul edilmiş ama oynanmamış meydan okuma
  uygulama kapanınca kayboluyor.
- **Metro Bilgi başarımı eşiği** (`quiz_400`) hesapla konuldu, oyuncu
  verisiyle doğrulanmadı.
- **Gerçek cihazda kamera okuması** — simülatörde doğrulanamadı.

---

## 5. Production TODO'ları

Kod içinde `// TODO(PROD):` ile işaretlidir:

- `lib/data/metro/stations.dart` — resmi/izinli istasyon datası, çok hatlı ağ.
- `lib/features/journey/models/station.dart` — hat renkleri için marka/kullanım
  hakkı incelemesi.
- `lib/features/journey/models/edge.dart` — yön, servis takvimi, aktarma ağırlıkları.
- `lib/features/journey/services/route_service.dart` — Dijkstra/A* + aktarma maliyeti.
- `lib/features/journey/services/difficulty_mapper.dart` — bucket yerine sürekli
  ölçekleme (bucket sınırlarında zorluk sıçraması hissediliyor).
- `lib/app/theme.dart` — light tema ve reduce-motion.

### Sıradaki iş için öneri (öncelik sırasıyla)

1. **Denge testi.** Hedef skor kalktığı için zorluk artık yalnızca engel
   oranı, parça havuzu ve undo ile ayarlanıyor — bunlar hiç ölçülmedi.
   Durak bonusu (+25) ve sprint (×2) de tahmin.
2. **Aktarma desteği.** Data katmanı hazır; §8'deki adımlar.
3. **Ses + ayarlar ekranı.** `LocalStore` haptic tercihini zaten tutuyor,
   UI'ı yok. Rekor sıfırlama da buraya girmeli.
4. **Erişilebilirlik — kalanlar.** Yazı ölçeği sınırını tamamen kaldırmak
   için tahta/HUD düzeninin ölçekten bağımsız olması gerekiyor. Tahta ve
   parçalar için semantik etiket de yok (sürükle-bırak VoiceOver ile
   oynanamıyor).
5. **Light tema.**

---

## 6. Kritik Kod Noktaları

| İş | Dosya |
|---|---|
| Zorluk konfigürasyonu | `features/journey/models/difficulty_profile.dart` |
| Skor kuralları | `features/game/domain/scoring.dart` (`ScoreRules`) |
| Parça kataloğu | `features/game/domain/piece_shapes.dart` |
| Adalet (fairness) garantisi | `features/game/application/piece_generator.dart` |
| Oyun döngüsü / bitiş koşulları | `features/game/application/game_controller.dart` |
| Rekor ve son rota kaydı | `core/storage/local_store.dart` |
| Açılış ekranı / hareketli ağ | `features/home/presentation/title_screen.dart` |
| Ayarlar | `features/settings/presentation/settings_screen.dart` |
| Soru üretimi (Metro Bilgi) | `features/games/metro_quiz/domain/quiz_generator.dart` |
| Quiz puan/seri kuralları | `features/games/metro_quiz/domain/quiz_rules.dart` |
| Yazılı soru havuzu | `assets/data/questions.json` + `data/questions/question_repository.dart` |
| Ses | `core/audio/audio_service.dart` |
| Ortak yolculuk (saat, puan, durak) | `features/session/journey_session.dart` |
| Yolculuğu ekranlardan uzun yaşatan tutamak | `features/session/journey_host.dart` |
| Yarım kalan yolculuğun kaydı | `features/session/journey_save.dart` |
| Oyunlar arası ortak puan ölçeği | `features/session/scoring/game_score_profile.dart` |
| Oyunlar arası tempo ölçümü (araç) | `test/balance/points_per_minute_test.dart` |
| Ortak puanlamanın bekçisi | `test/balance/parity_test.dart` |
| Blok Metro denge ölçümü (araç) | `test/balance/blocks_report_test.dart` |
| İkon üretimi (araç) | `test/icon_generator_test.dart` |
| Parça torbası | `features/game/application/piece_generator.dart` |
| Sürükle-bırak koordinat eşlemesi | `features/game/presentation/game_screen.dart` |
| Metro ilerlemesi | `features/progress/journey_progress.dart` |
| Varış sahnesi | `features/game/presentation/widgets/arrival_sequence.dart` |
| Tren çizimi (her ölçek) | `core/widgets/metro_train.dart` |
| Oyun sabitleri | `core/constants/app_constants.dart` |

### Varış sahnesi

`ArrivalSequence` tek bir `AnimationController` üzerinde `Interval`'lerle
kurgulanmıştır (toplam 1600 ms):

| Dilim | Ne olur |
|---|---|
| 0.00 – 0.14 | Ekran kararır, oyun kilitlenir |
| 0.00 – 0.56 | Tren sağdan girer, `easeOutCubic` ile frenleyip durur |
| 0.56 – 0.72 | Peron tabelası belirir |
| 0.68 – 0.94 | Kapılar yanlara açılır, karanlık iç görünür |
| 0.76 – 1.00 | Sonuç kartı kapı aralığından büyüyerek çıkar |

Ekranın herhangi bir yerine dokunmak sahneyi 200 ms'de sonuna sarar.

> **Dikkat:** Vagon yüksekliği bilinçli olarak küçüktür (`ekran * 0.15`).
> Vagon ekranın yarısından genişse şekil tren gibi değil, renkli blok gibi
> okunuyor. Kapı genişliği de ortadaki vagonun içinde kalmalıdır
> (`wagonWidth * 0.6`) — 3 vagon olduğu için ortadaki vagon ekranın
> merkezine denk gelir.

### Metro Bilgi soruları nereden geliyor?

İki kaynak var ve ikisi çok farklı:

1. **Üretilen sorular** (`QuizGenerator`). `assets/data/metro.json`'dan
   türetilir: önceki/sonraki durak, durağın hattı, hattın uç durağı, hattaki
   durak sayısı. 10 hat ve 161 durakla komşu durak sorusundan tek başına
   **302 farklı soru** çıkıyor. Yeni hat eklenince sorular kendiliğinden
   güncellenir; elle bakım yok.
2. **Yazılı sorular** (`assets/data/questions.json`). İstanbul ve metro
   bilgisi; üretilemez, yazılır. Her kaydın `source` alanı **zorunlu**:
   oyun bir bilgiyi doğruymuş gibi söylüyorsa nereden aldığı da yazılı
   olmalı. `test/game/question_bank_test.dart` dosyayı her koşuda denetler
   (4 farklı şık, geçerli cevap indeksi, tekrarsız id, kaynak).

Karışım ~%40 yazılı / %60 üretilen; yazılı havuz bitince akış üretilene
düşer. 12 dakikalık bir yolculuk ~60 soru demek, yani omurga her zaman
üretilen sorulardır.

**Veritabanı yok ve gerekmiyor.** Uygulama çevrimdışı, soru sayısı birkaç
yüz ve sürüm başına sabit. Kaynak ileride sunucuya taşınırsa yalnızca
`QuestionRepository` implementasyonu değişir.

> TODO(PROD): Yazılı soruların doğruluğu yayından önce kaynaklarıyla
> birlikte gözden geçirilmeli.

### Parça torbası

Ağırlıklı random tek başına çeşitlilik hissi vermiyordu. Ölçüm: kısa
yolculuklarda beş küçük şekil tüm parçaların **%41'ini** kaplıyor,
tepsilerin **%17'sinde** aynı şekil tekrar ediyordu.

Şimdi her zorluk havuzu bir torba: çekilen şekil torbadan çıkar, torba
bitince karıştırılıp yenilenir. Ayrıca aynı tepside şekil tekrarı elenir.
Ölçüm sonrası: tekrar eden tepsi **%0**, havuzdaki 24 şeklin hepsi eşit
sıklıkta.

> Zorluk hâlâ havuz ağırlığıyla ayarlanır (`hardPieceWeight`); torba
> yalnızca havuz **içindeki** dağılımı düzeltir.

### Ana ekran neden `await` ile tazeleniyor?

`Navigator.pop` alttaki rotayı yeniden çizmez. `HomeScreen._startJourney`
oyun rotasını `await` edip dönüşte `setState` çağırmazsa "son rotan" kartı
ve yeni rekor ekranda görünmez. Regresyon testi:
`test/widget/home_screen_test.dart` → "oyundan dönünce son rota kartı görünür".

### Yarım kalan yolculuk

Kayıt artık **yolculuğun**, tek bir oyunun değil: `JourneySave` (zarf)
rotayı, geçen süreyi, puanı, puanın oyunlara dağılımını ve geçilen durağı
tutar. Oyunun kendi durumu (Blok Metro'nun tahtası) zarfın içinde
`gamePayload` alanında, zarfın okumadığı bir metin olarak taşınır;
`GameSnapshot` (v4) onu yalnız tahta olarak yazar.

Yazma anları: yolculuk başlarken, her beş saniyede bir, arka plana
alınırken ve oyun kendi durumunu yazdığında (Blok Metro'da her
yerleştirme). Silme anları: varış ve yolculuğun kapatılması — ikisinde de
puan rotanın rekoruna yazılır.

`savedAt` **yalnızca gösterim içindir; asla süreye eklenmez.** Uygulama
kapalıyken tren yol almaz; oyuncunun bir gün sonra dönüp yolculuğu bitmiş
bulması kaydın anlamını yok ederdi. Arka plandaki süre ise sayılır
(`JourneyController.onForeground`): uygulama açıkken telefon cebe girse de
tren yol alır.

Yolculuk iki durak id'siyle saklanır ve açılışta yeniden hesaplanır; metro
verisi değişirse eski kayıt sessizce geçersiz olur (`decode` `null` döner).
Ortak yolculuktan önceki Blok Metro kaydı (`saved_game`, v3) açılışta
zarfa çevrilir — sürüm yükseltmesinde yarım kalan oyun kaybolmaz.

Başlık ekranındaki kart **canlı**: yolculuk orada da sürüyor, kalan süre
akıyor. Karta dokunmak oyun seçimini açar (yolculuk ortak, oyuncu kalan
süreyi istediği oyunda geçirebilir); "Yolculuğu bitir" kaydı silmez, puanı
rotanın rekoruna yazar.

### Denge ölçümü — kritik bulgu ve çözümü

`flutter test test/balance/blocks_report_test.dart` gerçek kurallarla (yalnız zaman
döngüsü ve oyuncu davranışı modellenir) 150 oyun simüle eder.

**Bulgu:** 9 dakikadan uzun yolculuklarda oyuncu durağına varamıyordu. Tahta
doluyor, oyun "Hamle kalmadı" ile bitiyordu; varış sahnesi gerçek bir işe
gidiş yolculuğunda hiç oynamıyordu — ürünün ana vaadi karşılanmıyordu.

**Çözüm: durakta kalabalık vagonlar boşalır.** Tren bir durağı geçtiğinde
tahtada **en az yarısı dolu olan satırlar** temizlenir
(`crowdedRows`, `kStationReliefMinFilled`). Eşik doluluğa bağlı olduğu için
rahatlama kendiliğinden ölçekleniyor: tahta rahatken hiçbir şey olmuyor,
oyuncu sıkıştıkça boşalma büyüyor. Boşalan satır **puan getirmez**; skoru
hâlâ yalnızca oyuncunun kendi temizlediği satırlar kazandırır. Durak
geçildikten sonra geri alma kapanır (yoksa boşalan satırlar geri yüklenirdi).

Varış oranı, 7 sn/hamle temposunda:

| Profil | Süre | Önce | **Sonra** | Medyan (sonra) |
|---|---|---:|---:|---:|
| Mini | 2 dk | %100 | %100 | 169 |
| Kısa | 9 dk | %46 | **%86** | 722 |
| Standart | 14 dk | %19 | **%62** | 1096 |
| Uzun | 32 dk | %3 | **%48** | 2202 |
| Maraton | 52 dk | %0 | **%35** | 2635 |

4 sn/hamle (dakikada 15 parça) temposunda uzun yolculuklarda varış hâlâ
%1-2: o tempoda oyuncu tahtayı rahatlamadan hızlı dolduruyor. Bilinçli
bırakıldı — hız skor getiriyor, hayatta kalma değil.

İki yan bulgu:

- **Zorluk ters yönde çalışıyor.** Uzun yolculuğa daha çok engel + daha zor
  parça veriliyor; oysa uzun yolculukta zaten hayatta kalmak zor. Hâlâ açık.
- **Sprint artık ölü değil.** Son %15'e ulaşılabildiği için payı %0-4'ten
  %17-18'e çıktı.

### Sürükle-bırak nasıl çalışıyor?

`Draggable.dragAnchorStrategy` ile parça parmağın **üstünde** ve board
ölçeğinde gösterilir. `DragTarget.onMove` global sol-üst köşeyi verir;
`game_screen.dart` içindeki `_cellFromGlobal` bunu board'un `RenderBox`'ına
çevirip hücreye yuvarlar.

> **Dikkat 1:** Bırakma hedefi (`DragTarget`) board'dan büyüktür; tepsiyi de
> kapsar. Parça parmağın üstünde durduğu için en alt satıra yerleştirmek
> parmağın board'un altına inmesini gerektirir — hedef daraltılırsa alt satır
> yeniden oynanamaz hale gelir. Regresyon testi:
> `test/widget/game_screen_test.dart` → "en alt satıra parça bırakılabilir".
>
> **Dikkat 2:** Board konteynerinde padding/border **yoktur**. Render box'ın
> tam olarak board boyutunda olması koordinat eşlemesinin doğruluğu için
> şarttır. Border eklenecekse konteyner dışına eklenmelidir.

---

## 7. QA Durumu

121 test. `07 - QA ve Test Planı.md` içindeki P0 unit test listesi karşılandı:
board yerleştirme/temizleme, parça geometrisi, game-over, skor/combo,
rota süresi ve profil sınırları (5/6/10/11/20/21/35/36).

Widget testleri: home render, seçici güncelleme, geçersiz rotada CTA pasif,
oyun ekranı render, skor güncellemesi ve **en alt satıra bırakma**
(gerçek sürükleme jestiyle, regresyon testi), pause paneli.

**Manuel test edilmesi gerekenler** (otomatik kapsanmadı):
- Uçak modu (kodda network çağrısı yok, yine de cihazda doğrulanmalı)
- Düşük güç modu
- Küçük/büyük iPhone ekranları
- Arka plan/ön plan geçişleri
- Kesintiye uğrayan sürükleme, hızlı tap
- Tekrarlı pause/restart

---

## 8. Veri Modeli (yeni hat eklemek için)

Metro verisi **`assets/data/metro.json`** dosyasındadır; açılışta bir kez
okunur. Veritabanı ya da network yoktur. Üç tip + bir arayüz:

### Tipler

| Tip | Dosya | Alanlar |
|---|---|---|
| `MetroLine` | `features/journey/models/station.dart` | `id` (`"M2"`), `name`, `colorValue` (ARGB accent) |
| `Station` | `features/journey/models/station.dart` | `id`, `name`, `lineId`, `order` (hat üzerindeki sıra) |
| `Edge` | `features/journey/models/edge.dart` | `from` (station id), `to`, `seconds` |

> Kenar süresi **saniye**dir. Dakika olsaydı yuvarlama hatası birikirdi:
> M4'ün 22 kenarı 2'şer dakikaya yuvarlansa hat uçtan uca 52 yerine 44 dakika
> çıkardı.

### Yeni hat eklemek

`assets/data/metro.json` içine bir kayıt eklemek yeterlidir; **kod
değişmez**:

```json
{
  "id": "M10",
  "name": "Pendik – Sabiha Gökçen",
  "color": "#0090D0",
  "oneWayMinutes": 12,
  "segmentSeconds": 120,
  "stations": [
    {"id": "m10_pendik", "name": "Pendik"}
  ]
}
```

- `segmentSeconds` = `oneWayMinutes * 60 / (istasyon sayısı - 1)`.
  Kenarlar sırayla bu değerle üretilir.
- İstasyon id'leri şehir genelinde benzersiz olmalı; kural
  `<hat kodu küçük harf>_<türkçesizleştirilmiş ad>`.
- Renk resmi ağ haritasından alınır; arayüz varyantlarını `LineTheme`
  otomatik türetir, elle ayar gerekmez.
- `test/journey/route_test.dart` içindeki veri testleri yeni hattı otomatik
  kapsar (sıra bütünlüğü, kenar sayısı, uçtan uca sürenin resmi süreye
  yakınlığı).

`data/metro/metro_repository.dart` → `MetroRepository` arayüzü. UI ve oyun
kodu yalnızca bu arayüzü bilir; kaynak değişince (uzak sunucu, SQLite)
**sadece implementasyon** değişir.

### Dallı ve şube hatlar

- **M1A / M1B** Yenikapı–Otogar arasını paylaşır. "Her hat bağımsız"
  kararıyla ikisi ayrı hattır ve ortak duraklar iki kez kayıtlıdır.
- **M2'nin Seyrantepe şubesi** veriye alınmadı: Sanayi Mahallesi'nden
  aktarmalı mekik işletmesi olduğu için doğrusal sıraya sokulamıyor.
  M2 bu yüzden resmi 16 yerine 15 istasyonla modellendi; 32 dakikalık
  resmi süre Yenikapı–Hacıosman ana hattına aittir.

### Dakikalar oyunu nasıl etkiliyor?

```text
RouteService.estimate()      → toplam saniye (kenarların toplamı)
        ↓
difficultyFor(minutes)       → DifficultyProfile
        ↓                       (hedef skor, başlangıç engeli,
        ↓                        zor parça oranı, undo hakkı)
Journey.estimatedSeconds     → metro ilerleme çubuğunun hızı
```

Yani **tek girdi toplam dakikadır**. Yeni hat eklemek oyun motoruna hiç
dokunmaz; sadece süre üretim şekli değişir. Zorluk profilleri de artık
oyuncuya gösterilmediği için serbestçe ayarlanabilir.

### Aktarma desteği — sonraki aşama

MVP'de iki durak aynı hatta olmalı; farklı hat seçilirse
`RouteError.differentLines` döner. Aktarma için:

1. **Aktarma modeli ekle.** Fiziksel olarak aynı olan duraklar (Yenikapı:
   M1/M2/Marmaray) ayrı `Station` kayıtlarıdır. Aralarına yürüme + bekleme
   süresini taşıyan bir aktarma kenarı gerekir:
   `Transfer(fromStationId, toStationId, walkMinutes, headwayMinutes)`.
   Alternatif olarak GTFS'teki `parent_station` gibi bir `stationGroupId`
   alanı eklenip aynı gruptaki duraklar otomatik bağlanabilir.
2. **`RouteService`'i graph aramasına çevir.** Bugünkü `_secondsBetween`
   "aynı hat + `order` farkı" varsayımına dayanır. Yerine kenar listesi
   üzerinde Dijkstra: düğüm = station id, ağırlık = `seconds`.
   161 durak için de 400 durak için de yeterince hızlıdır.
3. **İstasyon seçiciye arama ekle.** Hat seçimi listeyi 24 durağa indiriyor,
   bu yüzden şimdilik düz liste yetiyor. Aktarma gelince gerekecek.
4. **`order` alanının anlamını koru.** Yalnızca "bu hat üzerindeki sıra"dır;
   çok hatta global sıra olarak kullanılmamalıdır. `_nextStopName`
   (oyun ekranındaki "sonraki durak") bu varsayıma dayanıyor, rota
   üzerinden yürüyecek şekilde güncellenmeli.

Veri büyüdüğünde (birkaç yüz durak) Dart sabitleri yerine
`assets/metro.json` + tek seferlik parse önerilir; `MetroRepository`
arayüzü zaten bunu karşılıyor, çağıran kod değişmez.
