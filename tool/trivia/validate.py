#!/usr/bin/env python3
"""Metro Bilgi soru veritabanı denetçisi.

Tek iş yapar: bir soru dosyasını okuyup kalite kapısından geçirir.
Ürün kodu değil, içerik aracı — `tool/` altında durmasının sebebi bu.

Kullanım:  python3 tool/trivia/validate.py <dosya.json> [--strict]
"""
import json, sys, re, collections

CATEGORIES = {
    'history': 'Tarih',
    'culture_art': 'Kültür & Sanat',
    'sports': 'Spor',
    'geography_city': 'Coğrafya & Şehir',
    'istanbul': 'İstanbul',
    'general_knowledge': 'Genel Kültür',
}
DIFFICULTIES = {'easy', 'medium', 'hard'}
# Kategori başına eşit sayı **artık aranmıyor**. İstanbul kategorisi
# bilinçli olarak daha kalabalık: oyunun konusu bu şehir. Tarih ise çok
# zor yıl-ezberi soruları silindiği için küçüldü.
MIN_TOTAL = 1200
MIN_PER_CATEGORY = 150
PER_CATEGORY = 200

# "Soru" değil şablon olan gövdeler.
VAGUE = re.compile(
    r'doğru (temel )?bilgi|ile ilişkilidir|doğru karşılık|hangi tür kavram'
    r'|doğru ek bilgi|tanımla eşleşir|doğru kurum|en çok hangi alanla'
    r'|hangi yerle ilişkili|hangi başlangıç noktası veya şehirle'
    r'|bağlamında değerlendi',
    re.I,
)
BANNED = re.compile(r'hepsi|hiçbiri|yukarıdakilerin', re.I)


def skeleton(text):
    t = re.sub(r'\d+', '#', text)
    t = re.sub(r"[A-ZÇĞİÖŞÜ][a-zçğıöşü']+", 'X', t)
    return re.sub(r'\s+', ' ', t).strip().lower()


def audit(path):
    data = json.load(open(path, encoding='utf-8'))
    qs = data['questions']
    errors, warnings, stats = [], [], {}

    def err(msg): errors.append(msg)
    def warn(msg): warnings.append(msg)

    # --- sayım ---
    stats['toplam'] = len(qs)
    if len(qs) < MIN_TOTAL:
        err(f'toplam {len(qs)}, en az {MIN_TOTAL} olmalı')

    by_cat = collections.Counter(q['category'] for q in qs)
    stats['kategori'] = dict(by_cat)
    for cat in CATEGORIES:
        if by_cat[cat] < MIN_PER_CATEGORY:
            err(f'{cat}: {by_cat[cat]} soru, en az {MIN_PER_CATEGORY} olmalı')
    for cat in by_cat:
        if cat not in CATEGORIES:
            err(f'bilinmeyen kategori: {cat}')

    # --- kayıt bütünlüğü ---
    ids = collections.Counter(q['id'] for q in qs)
    for qid, n in ids.items():
        if n > 1:
            err(f'tekrar eden id: {qid} ({n})')

    for q in qs:
        qid = q['id']
        if q.get('difficulty') not in DIFFICULTIES:
            err(f'{qid}: geçersiz zorluk {q.get("difficulty")!r}')
        if len(q['options']) != 4:
            err(f'{qid}: {len(q["options"])} seçenek')
        if len(set(q['options'])) != 4:
            err(f'{qid}: tekrar eden seçenek')
        if not 0 <= q['correctAnswerIndex'] < len(q['options']):
            err(f'{qid}: geçersiz correctAnswerIndex')
        if not q['question'].strip():
            err(f'{qid}: boş soru')
        if not q.get('source', '').strip():
            err(f'{qid}: kaynak yok')
        if q.get('categoryLabel') != CATEGORIES.get(q['category']):
            err(f'{qid}: categoryLabel kategoriyle uyuşmuyor')
        if any(BANNED.search(o) for o in q['options']):
            err(f'{qid}: yasaklı seçenek (hepsi/hiçbiri)')

    # --- içerik kalitesi ---
    vague = [q['id'] for q in qs if VAGUE.search(q['question'])]
    stats['muglak_govde'] = len(vague)
    if vague:
        err(f'şablon/muğlak soru gövdesi: {len(vague)} (ör. {vague[:3]})')

    # Cevap sorunun içinde geçiyorsa soru kendini ele veriyor demektir.
    # Tek ve iki harfli cevaplar (element sembolleri gibi) hariç: onlar
    # sorunun herhangi bir sözcüğünün içinde rastlantıyla geçebilir.
    taut = [
        q['id'] for q in qs
        if len(q['options'][q['correctAnswerIndex']].strip()) > 2
        and q['options'][q['correctAnswerIndex']].strip().lower()
        in q['question'].lower()
    ]
    stats['totoloji'] = len(taut)
    if taut:
        err(f'totoloji (cevap soruda geçiyor): {len(taut)} (ör. {taut[:3]})')

    texts = collections.Counter(q['question'].strip().lower() for q in qs)
    exact = [t for t, n in texts.items() if n > 1]
    stats['tam_tekrar'] = len(exact)
    if exact:
        err(f'tam tekrar eden soru: {len(exact)}')

    sk = collections.Counter(skeleton(q['question']) for q in qs)
    stats['farkli_iskelet'] = len(sk)
    worst = sk.most_common(1)[0]
    stats['en_sik_iskelet'] = worst[1]
    if worst[1] > 25:
        warn(f'tek iskelet {worst[1]} kez: {worst[0][:60]}')

    # --- cevap konumu ---
    pos = collections.Counter(q['correctAnswerIndex'] for q in qs)
    stats['cevap_konumu'] = {'ABCD'[i]: pos[i] for i in range(4)}
    for i in range(4):
        share = pos[i] / len(qs)
        if not 0.20 <= share <= 0.30:
            err(f'cevap konumu {"ABCD"[i]}: %{100*share:.1f} (hedef %25)')

    # deterministik desen: ardışık 8 soruda A→B→C→D tekrarı
    seq = [q['correctAnswerIndex'] for q in qs]
    runs = sum(
        1 for i in range(len(seq) - 7)
        if seq[i:i + 8] == [0, 1, 2, 3, 0, 1, 2, 3]
    )
    if runs:
        err(f'öngörülebilir A→B→C→D deseni: {runs} yerde')

    # --- uzunluk yanlılığı ---
    cc = cw = ic = iw = 0
    cn = inn = longest = shortest = 0
    for q in qs:
        o, i = q['options'], q['correctAnswerIndex']
        cc += len(o[i]); cw += len(o[i].split()); cn += 1
        for j, x in enumerate(o):
            if j != i:
                ic += len(x); iw += len(x.split()); inn += 1
        lens = [len(x) for x in o]
        if lens[i] == max(lens) and lens.count(max(lens)) == 1: longest += 1
        if lens[i] == min(lens) and lens.count(min(lens)) == 1: shortest += 1

    stats['dogru_ort_karakter'] = round(cc / cn, 2)
    stats['yanlis_ort_karakter'] = round(ic / inn, 2)
    stats['dogru_ort_kelime'] = round(cw / cn, 2)
    stats['yanlis_ort_kelime'] = round(iw / inn, 2)
    stats['en_uzun_dogru_yuzde'] = round(100 * longest / len(qs), 1)
    stats['en_kisa_dogru_yuzde'] = round(100 * shortest / len(qs), 1)

    if abs(cc / cn - ic / inn) > 2.0:
        err(f'uzunluk yanlılığı: doğru {cc/cn:.1f} vs yanlış {ic/inn:.1f} karakter')
    if stats['en_uzun_dogru_yuzde'] > 32:
        err(f'en uzun seçenek %{stats["en_uzun_dogru_yuzde"]} oranında doğru')

    # --- zorluk ---
    for cat in CATEGORIES:
        sub = [q for q in qs if q['category'] == cat]
        if not sub: continue
        dist = collections.Counter(q['difficulty'] for q in sub)
        stats.setdefault('zorluk', {})[cat] = {
            d: round(100 * dist[d] / len(sub)) for d in ('easy', 'medium', 'hard')
        }

    # --- kaynak çeşitliliği ---
    for cat in CATEGORIES:
        srcs = {q['source'] for q in qs if q['category'] == cat}
        if len(srcs) == 1:
            warn(f'{cat}: 200 sorunun tamamı tek kaynağı gösteriyor')

    return errors, warnings, stats


if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'assets/data/trivia.json'
    errors, warnings, stats = audit(path)

    print(f'=== {path}')
    for k, v in stats.items():
        print(f'  {k}: {v}')
    if warnings:
        print(f'\nUYARI ({len(warnings)}):')
        for w in warnings: print('  -', w)
    if errors:
        print(f'\nHATA ({len(errors)}):')
        for e in errors: print('  -', e)
        sys.exit(1)
    print('\nKalite kapısı geçildi.')
