#!/usr/bin/env python3
"""Altı kategorinin sorularını tek veritabanında birleştirir.

Son adım cevap konumlarının dağıtılmasıdır. Kaynak dosyalarda doğru cevap
her zaman ilk sırada yazılır — yazarken okunaklı olsun diye. Burada her
sorunun şıkları tohumlu bir rastgeleyle karıştırılır.

Aday veritabanında konumlar "dengeli" görünüyordu (tam 300/300/300/300) ama
A→B→C→D döngüsü 299 yerde birebir tekrar ediyordu; oyuncu iki turda kalıbı
çözerdi. Burada dağılım istatistiksel olarak dengelenir, sıra ise
öngörülemez kalır.
"""
import json, os, random, sys, collections

sys.path.insert(0, os.path.dirname(__file__))
from load import load, LABELS
import difficulty

# Konuya göre başvuru kaynağı.
#
# Bu alan **doğrulama iddiası taşımaz** — hangi kurumun o konuyu
# belgelediğini söyler. Kaydın nasıl doğrulandığı `verification`
# alanındadır. Aday veritabanında 200 sorunun tamamı tek bir ana sayfayı
# gösteriyordu; konuyla ilgisi olmayan bir URL, kaynak alanını anlamsız
# kılıyor.
SOURCE_RULES = [
    (r'metro|tramvay|marmaray|hat|istasyon|durak|füniküler|teleferik',
     'https://www.metro.istanbul/'),
    (r'otobüs|metrobüs|İETT|toplu taşıma|İstanbulkart',
     'https://www.iett.istanbul/'),
    (r'tren|demiryol|gar|ray|katener|boji|pantograf|balast|makas',
     'https://www.tcdd.gov.tr/'),
    (r'köprü|tünel|otoyol|karayolu', 'https://www.kgm.gov.tr/'),
    (r'vapur|feribot|deniz otobüsü|iskele|liman|gemi',
     'https://www.sehirhatlari.istanbul/'),
    (r'havalimanı|uçak|pist|apron|IATA', 'https://www.dhmi.gov.tr/'),
    (r'olimpiyat|paralimpik', 'https://olympics.com/'),
    (r'futbol|FIFA|UEFA|Süper Lig|stad', 'https://www.fifa.com/'),
    (r'basketbol|FIBA|NBA', 'https://www.fiba.basketball/'),
    (r'voleybol|FIVB|file', 'https://www.fivb.com/'),
    (r'Osmanlı|padişah|Selçuklu|Bizans|savaş|antlaşma|ferman|sultan',
     'https://www.ttk.gov.tr/'),
    (r'Atatürk|Cumhuriyet|TBMM|inkılap|Kurtuluş Savaşı|Lozan',
     'https://www.atam.gov.tr/'),
    (r'roman|şiir|şair|yazar|edebiyat|nazım', 'https://www.tdk.gov.tr/'),
    (r'tablo|ressam|heykel|müze|fresk|minyatür|ebru|tezhip|hat sanatı',
     'https://www.ktb.gov.tr/'),
    (r'besteci|senfoni|opera|makam|usul|çalgı', 'https://www.ktb.gov.tr/'),
    (r'film|sinema|yönetmen|festival|tiyatro', 'https://www.ktb.gov.tr/'),
    (r'ilimiz|ilçe|bölge|ova|dağ|göl|nehir|baraj|Türkiye\'nin',
     'https://www.harita.gov.tr/'),
    (r'gezegen|yıldız|galaksi|uzay|Ay|Güneş', 'https://www.tua.gov.tr/'),
    (r'element|atom|molekül|kimyasal|formül', 'https://www.tubitak.gov.tr/'),
    (r'hücre|organ|kan|vitamin|bağışıklık|aşı|DNA',
     'https://www.saglik.gov.tr/'),
    (r'bilgisayar|internet|yazılım|dosya|parola|şifre|Wi-Fi',
     'https://www.btk.gov.tr/'),
]
SOURCE_FALLBACK = {
    'history': 'https://www.ttk.gov.tr/',
    'culture_art': 'https://www.ktb.gov.tr/',
    'sports': 'https://gsb.gov.tr/',
    'geography_city': 'https://www.harita.gov.tr/',
    'transportation': 'https://www.metro.istanbul/',
    'general_knowledge': 'https://www.tubitak.gov.tr/',
}
SOURCES = SOURCE_FALLBACK


def source_for(question, category):
    import re as _re
    for pattern, url in SOURCE_RULES:
        if _re.search(pattern, question, _re.I):
            return url
    return SOURCE_FALLBACK[category]

BASE = os.path.join(os.path.dirname(__file__), '..', '..')
os.chdir(BASE)
SRC = 'tool/trivia/src'


def transportation():
    """Ulaşım: türetilmiş + elle yazılmış."""
    out = json.load(open('tool/trivia/transportation_generated.json',
                         encoding='utf-8'))
    ns = {}
    exec(compile(open('tool/trivia/transportation_authored.py',
                      encoding='utf-8').read(), 'authored', 'exec'), ns)
    for q, correct, wrong, diff, src in ns['Q']:
        out.append({
            'id': '', 'category': 'transportation',
            'categoryLabel': 'Ulaşım', 'difficulty': diff,
            'question': q, 'options': [correct] + wrong,
            'correctAnswerIndex': 0, 'source': src,
            'verification': 'model_knowledge',
        })
    out += load(f'{SRC}/transportation_extra.txt', 'transportation',
                SOURCES['transportation'])
    return out


def build():
    questions = []
    for cat in LABELS:
        if cat == 'transportation':
            items = transportation()
        else:
            items = load(f'{SRC}/{cat}.txt', cat, SOURCES[cat])
        # Kimlikler kategori içinde sırayla yeniden verilir.
        for n, q in enumerate(items, start=1):
            q['id'] = f'{cat}_{n:03d}'
            q['category'] = cat
            q['categoryLabel'] = LABELS[cat]
            q.setdefault('verification', 'model_knowledge')
        questions += items

    # --- kaynak ataması ---
    #
    # `metro_json` ile doğrulanmış kayıtların kaynağı değişmez: onlar
    # gerçekten o veriye karşı denetlendi.
    for q in questions:
        if q.get('verification') != 'metro_json':
            q['source'] = source_for(q['question'], q['category'])

    # --- zorluk etiketleri ---
    #
    # Yazarken verilen etiket ilk tahmindi ve kategoriler arasında
    # tutarsızdı; tek kural kümesiyle yeniden atanır.
    difficulty.assign(questions)

    # --- cevap konumlarını dağıt ---
    #
    # Her kategoride A/B/C/D hedefi eşit paydır. Hedef konumlar önce
    # kategori başına eşit sayıda üretilir, sonra karıştırılır: dağılım
    # kesin dengeli olur ama sıra öngörülemez kalır.
    rng = random.Random(20260917)
    by_cat = collections.defaultdict(list)
    for q in questions:
        by_cat[q['category']].append(q)

    for cat, items in by_cat.items():
        slots = [i % 4 for i in range(len(items))]
        rng.shuffle(slots)
        for q, target in zip(items, slots):
            correct = q['options'][q['correctAnswerIndex']]
            rest = [o for o in q['options'] if o != correct]
            rng.shuffle(rest)
            opts = rest[:target] + [correct] + rest[target:]
            q['options'] = opts
            q['correctAnswerIndex'] = target

    data = {
        'schemaVersion': 2,
        'language': 'tr',
        'totalQuestions': len(questions),
        'categories': [{'id': c, 'label': LABELS[c]} for c in LABELS],
        'note': (
            'Sorular Metro Bilgi için hazırlanmıştır. verification alanı '
            'her kaydın nasıl doğrulandığını söyler: metro_json, depodaki '
            'assets/data/metro.json verisine karşı programatik olarak '
            'doğrulanmıştır; model_knowledge ise bağımsız bir kaynakla '
            'doğrulanmamıştır. source alanı konunun ait olduğu kurumu '
            'gösterir, tek tek doğrulama iddiası taşımaz.'
        ),
        'questions': questions,
    }
    json.dump(data, open('assets/data/trivia.json', 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('yazıldı: assets/data/trivia.json —', len(questions), 'soru')
    print('doğrulama:', dict(collections.Counter(
        q['verification'] for q in questions)))


if __name__ == '__main__':
    build()
