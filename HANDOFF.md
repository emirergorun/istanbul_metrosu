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
kullanılır (`Raleway` başlık, `Open Sans` gövde). Statik ağırlıklar şu
şekilde üretildi:

```bash
python3 -m fontTools.varLib.instancer "Raleway[wght].ttf" wght=700 -o out.ttf
python3 -m fontTools.subset out.ttf --unicodes="U+0000-024F,U+2000-206F,U+20A0-20BF" --layout-features='*' --output-file=Raleway-700.ttf
```

Yeni ağırlık gerekirse aynı adımlar tekrarlanıp `pubspec.yaml` içindeki
`fonts:` bloğuna eklenir. OFL metinleri asset olarak paketlenir ve
`main.dart` içinde `LicenseRegistry`'ye kaydedilir — silinmemeli.

Ana ekran düzeni metro.istanbul'daki yolculuk planlayıcısını referans alır
(A/B alanları, lacivert başlık şeridi, kırmızı alt şerit). Resmi logo veya
amblem kullanılmaz.

### Board temsili

`List<List<int>>`: `0` boş, `1..6` blok rengi, `9` engel.
Engel hücreleri normal dolu hücre gibi davranır ve **temizlenebilir**;
kalıcı ölü hücre bırakmamak için bilinçli bir karardır.

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
| Denge ölçümü (araç) | `test/balance_report_test.dart` |
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

### Yarım kalan oyun

`GameSnapshot` oturumu JSON'a çevirir; `LocalStore` tek anahtarda tutar.
Yazma anları: **her yerleştirme**, duraklatma ve ekrandan çıkış. Silme
anları: oyun bitişi (varış/hamle bitişi) ve yeniden başlatma.

Yolculuk iki durak id'siyle saklanır ve açılışta yeniden hesaplanır; metro
verisi değişirse eski kayıt sessizce geçersiz olur (`decode` `null` döner).
Kayıt sürümü `GameSnapshot.version` ile korunur — biçim değişirse eski
kayıtlar atılır.

Geri yüklenen oturum daima `GameStatus.paused` başlar; mevcut duraklatma
paneli olduğu gibi kullanılır, yeni bir ekran gerekmez.

### Denge ölçümü — kritik bulgu ve çözümü

`flutter test test/balance_report_test.dart` gerçek kurallarla (yalnız zaman
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
