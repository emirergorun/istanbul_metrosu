"""Tünele Kaç kapağı: logonun dili, yazısız, kartı tam kaplayan dikey sahne.

Kullanım (proje kökünden):  python3 tool/tunnel_escape/draw_cover.py
Çıktı: assets/images/games/tunele_kac_cover.png (660x1200, kart oranı 0.55)

Başlığı Flutter yazıyor (Bungee), bu yüzden görselde yazı yok; sol üst
iki satır sakin bırakıldı. Palet oyuncunun verdiği logodan: sıcak kömür
tahta, kırık beyaz metrolar, kırmızı iki vagonlu hedef, sarı oklu tünel.
"""
from PIL import Image, ImageDraw, ImageFilter

SS = 3                      # süper örnekleme
W, H = 660, 1200
CELL = 110
Y0 = -5                     # ızgara dikeyde ortalı: 11 satır = 1210 px

BOARD = (38, 35, 35)
TILE = (54, 51, 52)
TILE_EDGE = (46, 43, 44)
CAR = (232, 221, 204)
CAR_ROOF = (244, 236, 223)
CAR_EDGE = (184, 170, 151)
WINDOW = (43, 42, 46)
LIGHT = (255, 246, 222)
RED = (226, 44, 48)
RED_ROOF = (240, 86, 82)
RED_EDGE = (160, 30, 32)
RED_WINDOW = (44, 20, 22)
STONE = (112, 107, 104)
STONE_DARK = (84, 80, 78)
SIGNAL = (244, 186, 48)

img = Image.new('RGB', (W * SS, H * SS), BOARD)
d = ImageDraw.Draw(img)


def s(v):
    return int(round(v * SS))


def cell_rect(col, row, w=1, h=1, inset=0.0):
    x0 = col * CELL + inset * CELL
    y0 = Y0 + row * CELL + inset * CELL
    x1 = (col + w) * CELL - inset * CELL
    y1 = Y0 + (row + h) * CELL - inset * CELL
    return [s(x0), s(y0), s(x1), s(y1)]


# Karolar
for row in range(11):
    for col in range(6):
        d.rounded_rectangle(cell_rect(col, row, inset=0.045), radius=s(16), fill=TILE_EDGE)
        r = cell_rect(col, row, inset=0.06)
        d.rounded_rectangle(r, radius=s(14), fill=TILE)

# Sağ kenar peron çizgisi
TARGET_ROW = 5
edge_x = W - 7
d.rounded_rectangle([s(edge_x - 3), s(0), s(edge_x + 3), s(Y0 + TARGET_ROW * CELL + 4)], radius=s(3), fill=SIGNAL)
d.rounded_rectangle([s(edge_x - 3), s(Y0 + (TARGET_ROW + 1) * CELL - 4), s(edge_x + 3), s(H)], radius=s(3), fill=SIGNAL)

shadow_layer = Image.new('L', img.size, 0)
sd = ImageDraw.Draw(shadow_layer)


def car_shadow(rect, radius):
    x0, y0, x1, y1 = rect
    sd.rounded_rectangle([x0, y0 + s(7), x1, y1 + s(9)], radius=radius, fill=150)


cars = []  # (col,row,len,horizontal,is_target)


def car(col, row, length, horizontal, target=False):
    cars.append((col, row, length, horizontal, target))


# Sahne: sıkışmış bir depo, kırmızı metro tünele bakıyor.
car(4, 0, 2, False)            # sağ üst dikey
car(5, -1, 3, False)           # kenardan taşan uzun dikey
car(1, 2, 3, True)             # başlığın altında uzun yatay
car(0, 3, 2, False)            # sol dikey
car(4, 2, 2, False)            # tünel yolunu kesen dikeyin üst komşusu
car(2, 3, 2, True)
car(0, TARGET_ROW, 2, True, target=True)
car(3, 4, 2, False)            # kırmızının önündeki engel
car(2, 6, 3, True)
car(0, 6, 2, False)
car(5, 6, 3, False)
car(1, 8, 2, False)
car(2, 8, 3, True)
car(4, 9, 2, True)
car(0, 10, 2, True)
car(3, 10, 3, False)

for col, row, length, horizontal, target in cars:
    w, h = (length, 1) if horizontal else (1, length)
    rect = cell_rect(col, row, w, h, inset=0.085)
    car_shadow(rect, s(26))

shadow = Image.new('RGB', img.size, (10, 8, 8))
img.paste(shadow, (0, 0), shadow_layer.filter(ImageFilter.GaussianBlur(s(7))).point(lambda v: int(v * 0.55)))
d = ImageDraw.Draw(img)


def draw_car(col, row, length, horizontal, target):
    w, h = (length, 1) if horizontal else (1, length)
    x0, y0, x1, y1 = cell_rect(col, row, w, h, inset=0.085)
    body, roof, edge, win = (RED, RED_ROOF, RED_EDGE, RED_WINDOW) if target else (CAR, CAR_ROOF, CAR_EDGE, WINDOW)
    rad = s(28)
    d.rounded_rectangle([x0, y0, x1, y1], radius=rad, fill=edge)
    d.rounded_rectangle([x0 + s(4), y0 + s(2), x1 - s(4), y1 - s(6)], radius=rad - s(3), fill=body)
    d.rounded_rectangle([x0 + s(13), y0 + s(11), x1 - s(13), y1 - s(15)], radius=rad - s(10), fill=roof)
    along = (x1 - x0) if horizontal else (y1 - y0)
    unit = along / length
    for i in range(length):
        c = unit * (i + 0.5)
        if horizontal:
            cx, cy = x0 + c, (y0 + y1) / 2 - s(3)
            ww, hh = unit * (0.40 if target else 0.46), (y1 - y0) * 0.44
        else:
            cx, cy = (x0 + x1) / 2, y0 + c - s(3)
            ww, hh = (x1 - x0) * 0.44, unit * 0.46
        d.rounded_rectangle([cx - ww / 2, cy - hh / 2, cx + ww / 2, cy + hh / 2], radius=s(9), fill=win)
    # farlar
    lr = s(4.2)
    for end in (0.08, 0.92):
        if target and end > 0.5:
            continue
        for side in (-1, 1):
            if horizontal:
                px, py = x0 + (x1 - x0) * end, (y0 + y1) / 2 + side * (y1 - y0) * 0.27
            else:
                px, py = (x0 + x1) / 2 + side * (x1 - x0) * 0.27, y0 + (y1 - y0) * end
            d.ellipse([px - lr, py - lr, px + lr, py + lr], fill=LIGHT)
    if target:
        mid = (x0 + x1) / 2
        d.line([mid, y0 + s(8), mid, y1 - s(8)], fill=edge, width=s(5))
        nx, ny = x1 - s(18), (y0 + y1) / 2 - s(3)
        a = s(9)
        d.line([(nx - a, ny - a * 1.2), (nx + a * 0.4, ny), (nx - a, ny + a * 1.2)], fill=(255, 236, 230), width=s(5), joint='curve')


for spec in cars:
    draw_car(*spec)

# Tünel: sağ kenarda, hedef satırının son hücresinde; önünde üç sarı ok.
ty0 = Y0 + TARGET_ROW * CELL
cy = ty0 + CELL / 2

glow = Image.new('L', img.size, 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([s(4 * CELL + 10), s(cy - 34), s(5 * CELL + 10), s(cy + 34)], fill=120)
glow = glow.filter(ImageFilter.GaussianBlur(s(18)))
img.paste(Image.new('RGB', img.size, SIGNAL), (0, 0), glow.point(lambda v: int(v * 0.35)))
d = ImageDraw.Draw(img)

for i, alpha in enumerate((0.5, 0.75, 1.0)):
    x = 4 * CELL + 36 + i * 24
    col = tuple(int(TILE[k] + (SIGNAL[k] - TILE[k]) * alpha) for k in range(3))
    h = 15
    d.line([(s(x - 11), s(cy - h)), (s(x + 4), s(cy)), (s(x - 11), s(cy + h))],
           fill=col, width=s(7), joint='curve')

# Kemer: taş halka, içi karanlık; sağ kenardan dışarı taşar.
arch_left = 5 * CELL + 6
outer = [s(arch_left), s(ty0 + 2), s(W + 40), s(ty0 + CELL - 2)]
d.rounded_rectangle([outer[0], outer[1] + s(6), outer[2], outer[3] + s(6)], radius=s(34), fill=(20, 18, 18))
d.rounded_rectangle(outer, radius=s(34), fill=STONE)
d.rounded_rectangle([outer[0], outer[3] - s(18), outer[2], outer[3]], radius=s(16), fill=STONE_DARK)
inner = [s(arch_left + 16), s(ty0 + 17), s(W + 40), s(ty0 + CELL - 17)]
d.rounded_rectangle(inner, radius=s(24), fill=(8, 8, 9))
# derinlik: içe doğru koyulaşan iki şerit
d.rounded_rectangle([inner[0] + s(8), inner[1] + s(8), inner[2], inner[3] - s(8)], radius=s(18), fill=(3, 3, 4))
for jx in (arch_left + 30, arch_left + 60):
    d.line([s(jx), s(ty0 + 3), s(jx), s(ty0 + 16)], fill=STONE_DARK, width=s(3))
    d.line([s(jx), s(ty0 + CELL - 16), s(jx), s(ty0 + CELL - 4)], fill=STONE_DARK, width=s(3))

# Hafif derinlik: alt kenara doğru kararan örtü, başlık alanına doğru açılan.
shade = Image.new('L', img.size, 0)
sh = ImageDraw.Draw(shade)
for i in range(60):
    y = s(H * (0.62 + i * 0.0064))
    sh.rectangle([0, y, s(W), s(H)], fill=int(i * 1.4))
img.paste(Image.new('RGB', img.size, (8, 7, 7)), (0, 0), shade)

out = img.resize((W, H), Image.LANCZOS)
out.save('assets/images/games/tunele_kac_cover.png', optimize=True)
print('ok')
