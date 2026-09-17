#!/usr/bin/env python3
"""İstanbul kategorisi için elle yazılmış sorular.

Kategori "Ulaşım" iken yalnızca metro ağını soruyordu. "İstanbul" olarak
genişledi: şehrin coğrafyası, semtleri, yapıları ve ulaşımı aynı çatı
altında.

Buradaki sorular **kolay ve orta** seviyede tutuldu. Amaç oyuncuyu
elemek değil; zor soru zaten havuzun geri kalanında var ve oranı %12'ye
indirildi. Şehirde yaşayan ya da şehri bilen birinin cevaplayabileceği
şeyler soruluyor: tanınan yapılar, bilinen semtler, günlük ulaşım.

Biçim: (zorluk, soru, doğru cevap, çeldirici, çeldirici, çeldirici)

Çeldiriciler **aynı aileden** seçildi: bir semt sorusunun çeldiricileri
de semt, bir köprü sorusununki de köprü. Farklı ailelerden çeldirici
(bir semt sorusuna "Ankara" koymak) soruyu okumadan elenebilir hâle
getirir.
"""

Q = [
    # --- Coğrafya ve konum ---
    ('easy', 'İstanbul Boğazı hangi iki denizi birbirine bağlar?',
     'Karadeniz ile Marmara Denizi', 'Ege ile Akdeniz',
     'Marmara ile Ege Denizi', 'Karadeniz ile Ege Denizi'),
    ('easy', 'İstanbul kaç kıta üzerinde kurulmuştur?',
     'İki', 'Bir', 'Üç', 'Dört'),
    ('easy', 'Haliç İstanbul’un hangi yakasındadır?',
     'Avrupa Yakası', 'Anadolu Yakası', 'Adalar', 'Boğaz’ın ortası'),
    ('easy', 'Adalar ilçesi İstanbul’un hangi denizinde yer alır?',
     'Marmara Denizi', 'Karadeniz', 'Ege Denizi', 'Akdeniz'),
    ('medium', 'İstanbul’un en büyük adası hangisidir?',
     'Büyükada', 'Heybeliada', 'Burgazada', 'Kınalıada'),
    ('medium', 'Çamlıca Tepesi İstanbul’un hangi yakasındadır?',
     'Anadolu Yakası', 'Avrupa Yakası', 'Adalar', 'Silivri'),
    ('easy', 'İstanbul’un Karadeniz kıyısındaki ilçesi hangisidir?',
     'Şile', 'Maltepe', 'Bakırköy', 'Ataşehir'),
    ('medium', 'Belgrad Ormanı hangi ilçe sınırlarındadır?',
     'Sarıyer', 'Kadıköy', 'Pendik', 'Avcılar'),
    ('medium', 'İstanbul’un en batıdaki ilçesi hangisidir?',
     'Silivri', 'Tuzla', 'Şile', 'Beykoz'),
    ('medium', 'İstanbul’un en doğudaki ilçesi hangisidir?',
     'Tuzla', 'Silivri', 'Arnavutköy', 'Bakırköy'),

    # --- Tarihî yapılar ---
    ('easy', 'Ayasofya hangi ilçededir?',
     'Fatih', 'Beşiktaş', 'Üsküdar', 'Şişli'),
    ('easy', 'Topkapı Sarayı hangi yarımadadadır?',
     'Tarihi Yarımada', 'Kadıköy Yarımadası', 'Bostancı', 'Florya'),
    ('easy', 'Kız Kulesi hangi sular üzerindedir?',
     'İstanbul Boğazı', 'Haliç', 'Küçükçekmece Gölü', 'Terkos Gölü'),
    ('easy', 'Galata Kulesi hangi ilçededir?',
     'Beyoğlu', 'Kadıköy', 'Bakırköy', 'Zeytinburnu'),
    ('medium', 'Dolmabahçe Sarayı hangi ilçededir?',
     'Beşiktaş', 'Fatih', 'Üsküdar', 'Eyüpsultan'),
    ('medium', 'Rumeli Hisarı hangi amaçla yaptırılmıştır?',
     'Boğaz geçişini denetlemek', 'Saray olarak yaşamak',
     'Liman deposu kurmak', 'Rasathane kurmak'),
    ('medium', 'Yerebatan Sarnıcı ne amaçla yapılmıştır?',
     'Su depolamak', 'Tahıl depolamak', 'Gemi onarmak', 'Pazar kurmak'),
    ('easy', 'Kapalıçarşı hangi ilçededir?',
     'Fatih', 'Şişli', 'Kadıköy', 'Beykoz'),
    ('medium', 'Süleymaniye Camii’nin mimarı kimdir?',
     'Mimar Sinan', 'Mimar Kemaleddin', 'Sedefkâr Mehmed Ağa',
     'Mimar Hayreddin'),
    ('medium', 'Sultanahmet Camii halk arasında hangi adla anılır?',
     'Mavi Cami', 'Yeşil Cami', 'Beyaz Cami', 'Altın Cami'),
    ('medium', 'Beylerbeyi Sarayı Boğaz’ın hangi yakasındadır?',
     'Anadolu Yakası', 'Avrupa Yakası', 'Haliç kıyısı', 'Adalar'),
    ('medium', 'Haydarpaşa Garı hangi ilçededir?',
     'Kadıköy', 'Üsküdar', 'Maltepe', 'Ataşehir'),
    ('medium', 'Sirkeci Garı tarihte hangi tren hattının son durağıydı?',
     'Orient Express', 'Trans-Sibirya', 'Bağdat Demiryolu', 'Hicaz Demiryolu'),

    # --- Köprüler ve geçişler ---
    ('easy', 'İstanbul Boğazı üzerindeki ilk köprünün bugünkü adı nedir?',
     '15 Temmuz Şehitler Köprüsü', 'Fatih Sultan Mehmet Köprüsü',
     'Yavuz Sultan Selim Köprüsü', 'Haliç Köprüsü'),
    ('medium', 'Yavuz Sultan Selim Köprüsü üzerinde hangi ulaşım türü de vardır?',
     'Demiryolu', 'Metro', 'Tramvay', 'Teleferik'),
    ('easy', 'Marmaray hangi iki yakayı deniz altından bağlar?',
     'Avrupa ile Anadolu', 'Avrupa ile Adalar',
     'Anadolu ile Adalar', 'Silivri ile Şile'),
    ('medium', 'Avrasya Tüneli hangi araçlara açıktır?',
     'Otomobil', 'Tren', 'Metro', 'Tramvay'),
    ('medium', 'Haliç üzerindeki metro köprüsü hangi hatta aittir?',
     'M2', 'M4', 'M6', 'M9'),

    # --- Ulaşım ---
    ('easy', 'İstanbul’da toplu taşımada kullanılan kartın adı nedir?',
     'İstanbulkart', 'Şehirkart', 'Ulaşımkart', 'Marmarakart'),
    ('easy', 'Vapur İstanbul’da hangi ulaşım türüdür?',
     'Deniz ulaşımı', 'Raylı sistem', 'Karayolu', 'Havayolu'),
    ('medium', 'Metrobüs hattı hangi yol üzerinde işler?',
     'E-5 (D-100)', 'TEM Otoyolu', 'Sahil yolu', 'Kuzey Marmara Otoyolu'),
    ('medium', 'Tünel, İstanbul’da hangi iki noktayı bağlayan füniküler hattır?',
     'Karaköy ile Beyoğlu', 'Kabataş ile Taksim',
     'Eminönü ile Sirkeci', 'Üsküdar ile Kadıköy'),
    ('medium', 'İstanbul’un Avrupa Yakası’ndaki havalimanı hangisidir?',
     'İstanbul Havalimanı', 'Sabiha Gökçen Havalimanı',
     'Esenboğa Havalimanı', 'Adnan Menderes Havalimanı'),
    ('medium', 'Sabiha Gökçen Havalimanı hangi yakadadır?',
     'Anadolu Yakası', 'Avrupa Yakası', 'Adalar', 'Silivri'),
    ('easy', 'Nostaljik tramvay hangi caddede işler?',
     'İstiklal Caddesi', 'Bağdat Caddesi', 'Barbaros Bulvarı',
     'Vatan Caddesi'),
    ('medium', 'Teleferik İstanbul’da hangi amaçla kullanılır?',
     'Yokuş çıkmak', 'Boğaz geçmek', 'Havalimanına gitmek',
     'Adalara gitmek'),

    # --- Semtler ve meydanlar ---
    ('easy', 'Taksim Meydanı hangi ilçededir?',
     'Beyoğlu', 'Şişli', 'Beşiktaş', 'Fatih'),
    ('easy', 'İstiklal Caddesi hangi meydanda başlar?',
     'Taksim', 'Beyazıt', 'Üsküdar', 'Kadıköy'),
    ('medium', 'Bağdat Caddesi hangi yakadadır?',
     'Anadolu Yakası', 'Avrupa Yakası', 'Adalar', 'Haliç kıyısı'),
    ('medium', 'Moda semti hangi ilçededir?',
     'Kadıköy', 'Üsküdar', 'Beşiktaş', 'Sarıyer'),
    ('medium', 'Nişantaşı hangi ilçededir?',
     'Şişli', 'Beyoğlu', 'Fatih', 'Bakırköy'),
    ('medium', 'Ortaköy hangi ilçededir?',
     'Beşiktaş', 'Sarıyer', 'Beyoğlu', 'Üsküdar'),
    ('medium', 'Eminönü hangi ilçenin içindedir?',
     'Fatih', 'Beyoğlu', 'Zeytinburnu', 'Bayrampaşa'),
    ('medium', 'Levent iş merkezleri hangi ilçededir?',
     'Beşiktaş', 'Şişli', 'Kâğıthane', 'Sarıyer'),
    ('medium', 'Maslak hangi ilçenin sınırlarındadır?',
     'Sarıyer', 'Şişli', 'Beşiktaş', 'Kâğıthane'),
    ('easy', 'Kadıköy’deki ünlü boğa heykeli hangi semttedir?',
     'Kadıköy Meydanı', 'Moda', 'Fenerbahçe', 'Bostancı'),

    # --- Kültür ve günlük hayat ---
    ('easy', 'Mısır Çarşısı’nın diğer adı nedir?',
     'Baharatçılar Çarşısı', 'Kuyumcular Çarşısı',
     'Halıcılar Çarşısı', 'Kitapçılar Çarşısı'),
    ('medium', 'Pierre Loti Tepesi hangi ilçededir?',
     'Eyüpsultan', 'Beykoz', 'Sancaktepe', 'Esenler'),
    ('medium', 'Miniatürk hangi ilçededir?',
     'Beyoğlu', 'Kadıköy', 'Ataşehir', 'Üsküdar'),
    ('medium', 'Rahmi M. Koç Müzesi hangi kıyıdadır?',
     'Haliç', 'Boğaz', 'Marmara', 'Karadeniz'),
    ('medium', 'İstanbul Modern hangi semtte yer alır?',
     'Karaköy', 'Kadıköy', 'Bakırköy', 'Maltepe'),
    ('medium', 'Beşiktaş’ın stadyumunun adı nedir?',
     'Tüpraş Stadyumu', 'Ülker Stadyumu',
     'Rams Park', 'Atatürk Olimpiyat Stadyumu'),
    ('medium', 'Fenerbahçe’nin stadyumu hangi semttedir?',
     'Kadıköy', 'Beşiktaş', 'Seyrantepe', 'Bakırköy'),
    ('medium', 'Atatürk Olimpiyat Stadyumu hangi ilçededir?',
     'Başakşehir', 'Bağcılar', 'Esenyurt', 'Beylikdüzü'),

    # --- Şehir yönetimi ve yaşam ---
    ('easy', 'İstanbul’un belediye yapısında en üst yönetim hangisidir?',
     'Büyükşehir Belediyesi', 'İlçe belediyesi', 'Muhtarlık',
     'Mahalle meclisi'),
    ('medium', 'İstanbul’un su ihtiyacını yöneten kurum hangisidir?',
     'İSKİ', 'İETT', 'İGDAŞ', 'İSPARK'),
    ('medium', 'İstanbul’da otobüs işletmesini yürüten kurum hangisidir?',
     'İETT', 'İSKİ', 'İGDAŞ', 'İBB Spor'),
    ('medium', 'Terkos Gölü İstanbul için ne sağlar?',
     'İçme suyu', 'Elektrik', 'Doğal gaz', 'Sulama'),
    ('medium', 'İstanbul’un plaka kodu kaçtır?',
     '34', '06', '35', '16'),
    ('medium', 'İstanbul hangi coğrafi bölgede yer alır?',
     'Marmara', 'Ege', 'Karadeniz', 'İç Anadolu'),

    # --- Ulaşım alışkanlıkları ---
    ('easy', 'Metroda öncelikli koltuklar kimler içindir?',
     'Yaşlı ve engelliler', 'Kart sahipleri', 'Öğrenciler',
     'Uzun yol yolcuları'),
    ('easy', 'Yürüyen merdivende hangi taraf geçiş içindir?',
     'Sol taraf', 'Sağ taraf', 'Orta', 'Her iki taraf'),
    ('medium', 'Metroda peronda sarı çizgi neyi belirtir?',
     'Güvenli bekleme sınırı', 'Bilet kontrol noktası',
     'Engelli alanı', 'Bisiklet alanı'),
]
