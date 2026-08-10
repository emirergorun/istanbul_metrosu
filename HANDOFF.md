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

1. **`GameStatus.arrived` eklendi.** Tasarım notundaki state listesinde
   (`02 - Oyun Tasarımı`) yoktu, ama `01 - MVP` akış şeması "Trip Complete /
   Result" istiyor. `victory` = hedefe yolculuk bitmeden ulaşmak,
   `arrived` = yolculuk süresinin dolması.
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
| 1 | Tek hat (M2), yaklaşık süreler | Aktarmalı rota yok |
| 2 | Aktarma/yön/servis saati modellenmedi | Süre gerçekçi değil, prototip |
| 3 | Tek tema (koyu), yalnız portrait | Light tema ve yatay yok |
| 3b | Kurumsal renk/tipografi referansı | Ticari yayın öncesi marka incelemesi şart |
| 4 | Ses efekti yok | Haptic var, opsiyonel; ayar UI'ı yok |
| 5 | Onboarding yok | İlk kullanıcı mekanikleri deneyerek öğrenir |
| 6 | Skor yalnız local | Cloud save/leaderboard yok (MVP dışı) |
| 7 | `reduce motion` desteklenmiyor | Erişilebilirlik açığı |
| 8 | Piece rotasyonu yok | Katalog varyantlarla telafi ediliyor |
| 9 | Endless modda hedef sabit kalır | Zafer sonrası yeni hedef gelmiyor |
| 10 | Best score profil bazında | "Rota bazında rekor" yok |

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

1. **Denge testi.** Hedef skorlar oyun içi ölçümle doğrulanmadı. En az 20
   gerçek oturumda "hedefe ulaşma oranı" ölçülmeli; şu an Mini kolay,
   Maraton muhtemelen fazla zor.
2. **Çok hatlı rota motoru.** Data katmanı hazır; `RouteService` içindeki tek
   hat varsayımı graph aramasıyla değiştirilecek.
3. **Onboarding.** İlk açılışta 3 karelik bir gösterim yeterli.
4. **Ses + ayarlar ekranı.** `LocalStore` haptic tercihini zaten tutuyor,
   UI'ı yok.
5. **Erişilebilirlik.** Semantics etiketleri, reduce-motion, daha büyük
   dokunma hedefleri.

---

## 6. Kritik Kod Noktaları

| İş | Dosya |
|---|---|
| Zorluk konfigürasyonu | `features/journey/models/difficulty_profile.dart` |
| Skor kuralları | `features/game/domain/scoring.dart` (`ScoreRules`) |
| Parça kataloğu | `features/game/domain/piece_shapes.dart` |
| Adalet (fairness) garantisi | `features/game/application/piece_generator.dart` |
| Oyun döngüsü / bitiş koşulları | `features/game/application/game_controller.dart` |
| Sürükle-bırak koordinat eşlemesi | `features/game/presentation/game_screen.dart` |
| Metro ilerlemesi | `features/progress/journey_progress.dart` |
| Oyun sabitleri | `core/constants/app_constants.dart` |

### Sürükle-bırak nasıl çalışıyor?

`Draggable.dragAnchorStrategy` ile parça parmağın **üstünde** ve board
ölçeğinde gösterilir. `DragTarget.onMove` global sol-üst köşeyi verir;
`game_screen.dart` içindeki `_cellFromGlobal` bunu board'un `RenderBox`'ına
çevirip hücreye yuvarlar.

> **Dikkat:** Board konteynerinde padding/border **yoktur**. Render box'ın
> tam olarak board boyutunda olması koordinat eşlemesinin doğruluğu için
> şarttır. Border eklenecekse konteyner dışına eklenmelidir.

---

## 7. QA Durumu

97 test. `07 - QA ve Test Planı.md` içindeki P0 unit test listesi karşılandı:
board yerleştirme/temizleme, parça geometrisi, game-over, skor/combo,
rota süresi ve profil sınırları (5/6/10/11/20/21/35/36).

Widget testleri: home render, seçici güncelleme, geçersiz rotada CTA pasif,
oyun ekranı render, skor güncellemesi (gerçek sürükleme jesti), pause paneli.

**Manuel test edilmesi gerekenler** (otomatik kapsanmadı):
- Uçak modu (kodda network çağrısı yok, yine de cihazda doğrulanmalı)
- Düşük güç modu
- Küçük/büyük iPhone ekranları
- Arka plan/ön plan geçişleri
- Kesintiye uğrayan sürükleme, hızlı tap
- Tekrarlı pause/restart
