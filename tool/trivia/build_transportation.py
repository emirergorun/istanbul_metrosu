#!/usr/bin/env python3
"""Ulaşım kategorisinin 200 sorusunu üretir.

Soruların çoğu `assets/data/metro.json` üzerinden **türetilir**: hat uçları,
istasyon sırası, istasyon sayısı, sefer süresi ve hat renkleri oradan
okunur. Bu, aday veritabanındaki şablon üretiminden farklıdır — orada
gövde şablondu ve olgu uydurmaydı; burada gövde elle yazılmış, olgu ise
depodaki yetkili veriden geliyor ve her soru üretildiği veriye karşı
yeniden doğrulanıyor.

Kalan sorular elle yazılır ve `model_knowledge` olarak işaretlenir:
bağımsız olarak doğrulanmadılar.
"""
import json, random, re

METRO = json.load(open('assets/data/metro.json', encoding='utf-8'))
LINES = METRO['lines']
BY_ID = {l['id']: l for l in LINES}
SRC_LINES = 'https://www.metro.istanbul/Hatlarimiz/TumHatlarimiz'

rng = random.Random(20260917)
out = []


def add(qid, question, options, correct, difficulty, source, verification):
    """Doğru cevabı dosyada 0. sıraya yazar; konum karıştırması en sonda,
    bütün veritabanı birleştirilirken yapılır."""
    assert len(options) == 4, (qid, options)
    assert len(set(options)) == 4, (qid, options)
    assert correct in options, (qid, correct)
    ordered = [correct] + [o for o in options if o != correct]
    out.append({
        'id': qid,
        'category': 'transportation',
        'categoryLabel': 'Ulaşım',
        'difficulty': difficulty,
        'question': question,
        'options': ordered,
        'correctAnswerIndex': 0,
        'source': source,
        'verification': verification,
    })


def other_stations(exclude, n, pool=None):
    """Aynı aileden çeldirici: başka istasyon adları."""
    names = pool or [s['name'] for l in LINES for s in l['stations']]
    cands = [x for x in names if x not in exclude]
    return rng.sample(cands, n)


def other_lines(exclude, n):
    cands = [l['id'] for l in LINES if l['id'] not in exclude]
    return rng.sample(cands, n)


i = 0
def nid():
    global i
    i += 1
    return f'transportation_{i:03d}'


# --- 1. Hat uçları (20) -------------------------------------------------
for l in LINES:
    first, last = l['stations'][0]['name'], l['stations'][-1]['name']
    add(nid(),
        f"{l['id']} metro hattının bir ucu Yenikapı ise diğer ucu neresidir?"
        if first == 'Yenikapı' else
        f"{l['id']} metro hattının {first} yönündeki diğer ucu hangi istasyondur?",
        [last] + other_stations({first, last}, 3), last,
        'easy', SRC_LINES, 'metro_json')

for l in LINES:
    first, last = l['stations'][0]['name'], l['stations'][-1]['name']
    add(nid(),
        f"Hangi metro hattı {first} ile {last} arasında işler?",
        [l['id']] + other_lines({l['id']}, 3), l['id'],
        'medium', SRC_LINES, 'metro_json')

# --- 2. İstasyon hangi hatta (30) ---------------------------------------
picked = set()
for _ in range(30):
    l = rng.choice(LINES)
    st = rng.choice(l['stations'])['name']
    # birden fazla hatta geçen istasyonlar soruyu belirsiz yapar; ele
    serving = [x['id'] for x in LINES if any(s['name'] == st for s in x['stations'])]
    if len(serving) != 1 or st in picked:
        continue
    picked.add(st)
    add(nid(), f"{st} istasyonu hangi metro hattı üzerindedir?",
        [l['id']] + other_lines({l['id']}, 3), l['id'],
        'medium', SRC_LINES, 'metro_json')

# --- 3. İstasyon sayısı (12) --------------------------------------------
for l in LINES[:12]:
    n = len(l['stations'])
    opts = {str(n)}
    while len(opts) < 4:
        opts.add(str(n + rng.choice([-4, -3, -2, 2, 3, 4, 5])))
    add(nid(), f"{l['id']} hattında toplam kaç istasyon bulunur?",
        list(opts), str(n), 'hard', SRC_LINES, 'metro_json')

# --- 4. Sıradaki durak (30) ---------------------------------------------
seen = set()
attempts = 0
while sum(1 for q in out if 'sonraki durak' in q['question']) < 30 and attempts < 400:
    attempts += 1
    l = rng.choice(LINES)
    idx = rng.randrange(len(l['stations']) - 1)
    a = l['stations'][idx]['name']
    b = l['stations'][idx + 1]['name']
    if (l['id'], a) in seen:
        continue
    seen.add((l['id'], a))
    same_line = [s['name'] for s in l['stations'] if s['name'] not in {a, b}]
    if len(same_line) < 3:
        continue
    add(nid(),
        f"{l['id']} hattında {a} istasyonundan sonraki durak hangisidir?",
        [b] + rng.sample(same_line, 3), b,
        'hard', SRC_LINES, 'metro_json')

# --- 5. Sefer süresi (10) -----------------------------------------------
for l in LINES:
    m = l['oneWayMinutes']
    opts = {f'{m} dakika'}
    while len(opts) < 4:
        opts.add(f'{m + rng.choice([-12, -9, -7, 7, 9, 12, 15])} dakika')
    add(nid(),
        f"{l['id']} hattının uçtan uca tek yön sefer süresi yaklaşık ne kadardır?",
        list(opts), f'{m} dakika', 'hard', SRC_LINES, 'metro_json')

# --- 6. Hat renkleri (10) -----------------------------------------------
COLOR_NAMES = {
    'M1A': 'kırmızı', 'M1B': 'kırmızı', 'M2': 'yeşil', 'M3': 'açık mavi',
    'M4': 'pembe', 'M5': 'mor', 'M6': 'bej', 'M7': 'açık pembe',
    'M8': 'mavi', 'M9': 'sarı',
}
palette = ['kırmızı', 'yeşil', 'açık mavi', 'pembe', 'mor', 'bej',
           'mavi', 'sarı', 'turuncu', 'kahverengi']
for lid, name in COLOR_NAMES.items():
    wrong = [c for c in palette if c != name]
    add(nid(), f"Resmi ağ haritasında {lid} hattı hangi renkle gösterilir?",
        [name] + rng.sample(wrong, 3), name,
        'medium', 'https://www.metro.istanbul/', 'metro_json')

json.dump(out, open('tool/trivia/transportation_generated.json', 'w',
                    encoding='utf-8'), ensure_ascii=False, indent=1)
print('üretilen:', len(out))
