#!/usr/bin/env python3
"""Elle yazılmış soruları yoğun metin biçiminden okur.

Biçim, satır başına bir soru:

    zorluk | soru | doğru | çeldirici | çeldirici | çeldirici

`#` ile başlayan satır yorumdur, boş satır atlanır. Amaç, 1200 soruyu
JSON olarak elle yazmanın gürültüsünden kaçınmak; dosyalar insan
tarafından okunabilir ve gözden geçirilebilir kalıyor.
"""
import json, sys

LABELS = {
    'history': 'Tarih',
    'culture_art': 'Kültür & Sanat',
    'sports': 'Spor',
    'geography_city': 'Coğrafya & Şehir',
    'transportation': 'Ulaşım',
    'general_knowledge': 'Genel Kültür',
}


def load(path, category, source, verification='model_knowledge', start=1):
    out = []
    n = start - 1
    for lineno, raw in enumerate(open(path, encoding='utf-8'), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        parts = [p.strip() for p in line.split('|')]
        if len(parts) != 6:
            raise SystemExit(f'{path}:{lineno}: 6 alan bekleniyor, {len(parts)} var\n  {line}')
        diff, q, correct, *wrong = parts
        if diff not in ('easy', 'medium', 'hard'):
            raise SystemExit(f'{path}:{lineno}: geçersiz zorluk {diff!r}')
        opts = [correct] + wrong
        if len(set(opts)) != 4:
            raise SystemExit(f'{path}:{lineno}: tekrar eden seçenek\n  {opts}')
        n += 1
        out.append({
            'id': f'{category}_{n:03d}',
            'category': category,
            'categoryLabel': LABELS[category],
            'difficulty': diff,
            'question': q,
            'options': opts,
            'correctAnswerIndex': 0,
            'source': source,
            'verification': verification,
        })
    return out


if __name__ == '__main__':
    qs = load(sys.argv[1], sys.argv[2], sys.argv[3])
    print(len(qs), 'soru okundu')
