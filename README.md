# İstanbul Metrosu Oyunu

> **Yolculuğun kadar oyna.**

İstanbul metrosunda internet zayıf ya da yokken oynanmak üzere tasarlanmış,
**tamamen offline** çalışan bir blok yerleştirme oyunu. Oyuncu bindiği ve
ineceği durağı seçer; uygulama tahmini yolculuk süresini hesaplar ve oyunun
hedefini/zorluğunu bu süreye göre ayarlar.

Bu depo, tasarım notlarındaki **MVP vertical slice**'ıdır (`01 - MVP.md`).

| Yolculuk kurulumu | Oyun |
|---|---|
| <img src="docs/screenshots/01-home.png" width="260"> | <img src="docs/screenshots/02-game.png" width="260"> |

---

## Hızlı Başlangıç

```bash
flutter pub get
```

```bash
flutter run -d iphone
```

Testler:

```bash
flutter test
```

Analiz ve format:

```bash
flutter analyze && dart format lib test
```

**Gereksinimler:** Flutter 3.44+ (Dart 3.12+), iOS için Xcode ve CocoaPods.

---

## Tasarım Dili

Arayüz, İstanbul metrosunun kendi dijital arayüzüne yaslanır:

- **Tipografi:** başlıklarda **Raleway**, gövde ve butonlarda **Open Sans** —
  metro.istanbul ile aynı aile. İkisi de SIL Open Font License 1.1 altındadır;
  statik ağırlıklar `google/fonts` değişken fontlarından üretilip latin +
  latin-ext karakter kümesine daraltıldı (`assets/fonts/`). Lisans metinleri
  uygulamanın "Lisanslar" ekranına kaydedilir.
- **Yolculuk planlayıcı:** ana ekran, resmi sitedeki "nasıl giderim"
  kutusunun düzenini izler — lacivert başlık şeridi, **A/B** işaretli
  *Çıkış Noktası* / *Gidilecek Yer* alanları, tam genişlik aksiyon butonu ve
  altta kırmızı vurgu şeridi.
- **Renk:** kurumsal lacivert (`#164874`) + kırmızı (`#E1251B`) düzeni,
  hat rengi ise seçili hattan gelir.
- **Türkçe:** büyük harf dönüşümü locale-duyarlıdır
  (`Formatters.upperTr`: `i → İ`, `ı → I`).

> Resmi logo, amblem veya marka görseli kullanılmaz; yalnızca açık lisanslı
> yazı tipleri ve arayüz düzeni referans alınır.
> TODO(PROD): Kurumsal renk/tipografi kullanımı için marka incelemesi.

---

## Oyun Kuralları

- 8x8 tahta.
- Oyuncuya aynı anda 3 parça verilir.
- Parça tahtaya sürükle-bırak ile konur; tüm hücreleri tahta içinde ve boş
  hücrelere denk gelmelidir.
- Yerleştirme sonrası **tamamen dolu satır ve sütunlar** aynı anda temizlenir.
- Skorlama:
  - yerleştirilen her hücre **+1**
  - temizlenen her satır **+10**, her sütun **+10**
  - aynı hamlede 2 hat **+30**, 3+ hat **+60** bonus
  - hat temizleyen ardışık hamleler combo yapar; **hat puanı** combo ile çarpılır
- Üç parça da kullanılınca yeni tepsi gelir.
- Tepsideki hiçbir parça konamıyorsa oyun biter.
- Sayı birleştirme **yoktur** (2048 mekaniği değildir).

### Bitiş koşulları

| Durum | Ne zaman | Sonuç ekranı |
|---|---|---|
| `victory` | Yolculuk bitmeden hedef skora ulaşılır | "Challenge tamamlandı" (endless devam edilebilir) |
| `arrived` | Tahmini yolculuk süresi dolar | "Durağına yaklaştın!" |
| `gameOver` | Legal hamle kalmaz | "Hamle kalmadı" |

---

## Yolculuk → Zorluk

Süre, uygulama paketine gömülü istasyon/kenar verisinden hesaplanır
(network yok, GPS yok).

| Profil | Süre | Hedef | Başlangıç engeli | Zor parça | Undo |
|---|---:|---:|---:|---:|---:|
| Mini | 0–5 dk | 120 | %0 | %5 | 1 |
| Kısa | 6–10 dk | 260 | %0 | %10 | 1 |
| Standart | 11–20 dk | 520 | %4 | %18 | 1 |
| Uzun | 21–35 dk | 900 | %8 | %25 | 0 |
| Maraton | 36+ dk | 1400 | %12 | %32 | 0 |

Bu değerler prototip tuning değerleridir, nihai denge değildir:
[`lib/features/journey/models/difficulty_profile.dart`](lib/features/journey/models/difficulty_profile.dart)

### Metro ilerlemesi

```text
progress = aktifOyunSüresi / tahminiYolculukSüresi   // 0.0 – 1.0
```

**Konum izni istenmez.** Sayaç yalnızca oyun aktifken işler; uygulama arka
plana alınınca hem oyun hem sayaç durur.

---

## Mimari

Oyun kuralları Flutter widget'larından tamamen ayrıdır. `domain/` altındaki
fonksiyonlar saf ve test edilebilirdir; UI onları bilmez, sadece controller'ı
dinler.

```text
lib/
  app/            uygulama kabuğu, tema, rotalar, servis scope'u
  core/           sabitler, formatlayıcılar, local storage
  data/metro/     gömülü istasyon ve kenar verisi (değiştirilebilir katman)
  features/
    journey/      istasyon/rota modelleri, süre ve zorluk servisleri, home ekranı
    game/
      domain/     saf kurallar: board, piece, scoring, game_state
      application/game_controller, piece_generator
      presentation/oyun ekranı ve widget'ları
    progress/     metro ilerleme göstergesi
test/
  game/  journey/  widget/  helpers/
```

### Saf (test edilebilir) çekirdek

`lib/features/game/domain/board.dart`

- `canPlace` · `placePiece` · `findCompletedRows` · `findCompletedColumns`
- `clearLines` · `canPlaceAnywhere` · `findFirstLegalPosition` · `hasAnyLegalMove`

`lib/features/game/domain/scoring.dart` → `calculateScore`

`lib/features/journey/services/` → `RouteService.estimate` · `difficultyFor`

### Bağımlılıklar

Yalnızca `shared_preferences` (en iyi skor + haptic tercihi). Yazı tipleri
pakete gömülüdür — çalışma anında font indirilmez.
Firebase, analytics, reklam, login, cloud save, push ve API çağrısı
**bilinçli olarak yoktur** — MVP offline-first'tür.

---

## Test Kapsamı

97 test: board kuralları, parça geometrisi, skor/combo, game-over tespiti,
parça üretimi ve adalet (fairness) garantisi, rota süresi ve zorluk sınırları,
controller yaşam döngüsü, Türkçe biçimlendirme, home/oyun ekranı widget
testleri (sürükle-bırak dahil).

```bash
flutter test
```

---

## Bilinen Sınırlar

Detaylı liste ve production TODO'ları: [HANDOFF.md](HANDOFF.md)

- Tek hat (M2) ve yaklaşık süreler — prototip verisi, doğruluk iddiası yoktur.
- Resmi Metro İstanbul logosu/marka görseli kullanılmaz; tüm görseller özgün
  ve basit şekillerdir.
- Tek tema (koyu), yalnızca dikey yön.
- Tipografi ve renk düzeni resmi arayüzü referans alır; ticari yayın öncesi
  marka incelemesi gerekir.
- Ses efekti yoktur; haptic opsiyoneldir.
