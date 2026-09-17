#!/usr/bin/env python3
"""Zorluk etiketlerini soru metninden türetir.

Kaynak dosyalarda yazarken verilen etiket bir ilk tahmindir ve kategoriler
arasında tutarsız kalıyordu. Burada tek bir kural kümesi uygulanır, sonra
kategori içinde hedef dağılıma (%45 kolay / %43 orta / %12 zor) yaklaşacak
şekilde sınırdaki kayıtlar kaydırılır.

Zor dilimi bilerek dar: bu havuzdaki zor soruların çoğu yıl ezberi
("hangi yılda imzalandı", dört yıl şıkkı). Çoktan seçmelide bu tür, elemeyle
daraltılamadığı için tahmine düşüyor ve üç canla oynanan bir oyunda
yolculuğu erken bitiriyordu. Oran %20'den %12'ye indirildi; sorular
silinmedi, yalnızca daha seyrek karşılaşılıyor.

Kaydırma rastgele değil, **sıralamayla** yapılır: her sorunun bir zorluk
puanı vardır, kategori bu puana göre sıralanır ve dilimlenir. Böylece
"gerçekten zor" olanlar zor dilimde kalır ve sonuç yeniden üretilebilir.
"""
import re, collections

TARGET = (('easy', 0.45), ('medium', 0.43), ('hard', 0.12))

# Herkesin bildiği temel olgular.
EASY = re.compile(
    r'başkenti|kaç gün|kaç ay|kaç kenar|hangi iki kıta|kaç oyuncu'
    r'|kaç dakika sürer|en kalabalık|acil çağrı|kimyasal formülü'
    r'|kaç gezegen|en yakın gezegen|en büyük gezegen|doğal uydusu'
    r'|iç açıları toplamı|hangi bayram|kaç yılda bir', re.I)

# Tarih, teknik terim ve uzmanlık bilgisi.
HARD = re.compile(
    r'hangi yıl|kaç yılında|yüzyılda|kısaltması|sembolü nedir'
    r'|birimi nedir|kaç istasyon|sefer süresi|sonraki durak'
    r'|hangi eseriyle|nazım biçimi|antlaşma|hangi yöntemle', re.I)

# Tanım soruları orta-zor arası; kaydırmada önce bunlar zora çıkar.
TERM = re.compile(r'ne ad verilir|ne denir|neyi ifade eder', re.I)


def score(question):
    """Büyük puan = daha zor."""
    t = question
    if EASY.search(t):
        return 0
    s = 1
    if TERM.search(t):
        s = 2
    if HARD.search(t):
        s = 3
    return s


def assign(questions):
    """Kategori içinde hedef dağılıma göre etiketler."""
    by_cat = collections.defaultdict(list)
    for q in questions:
        by_cat[q['category']].append(q)

    for items in by_cat.values():
        # Kararlı sıralama: puan, sonra kimlik. Aynı girdi aynı çıktıyı verir.
        ordered = sorted(items, key=lambda q: (score(q['question']), q['id']))
        n = len(ordered)
        easy_n = round(TARGET[0][1] * n)
        medium_n = round(TARGET[1][1] * n)
        for i, q in enumerate(ordered):
            if i < easy_n:
                q['difficulty'] = 'easy'
            elif i < easy_n + medium_n:
                q['difficulty'] = 'medium'
            else:
                q['difficulty'] = 'hard'
    return questions
