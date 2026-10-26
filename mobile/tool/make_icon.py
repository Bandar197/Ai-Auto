import math, sys
from PIL import Image, ImageDraw
out = sys.argv[1]
S = 1024
def symbol(d, cx, cy, r, w):
    teal = (0, 200, 170, 255); white = (255, 255, 255, 255)
    # gauge arc (220° sweep)
    d.arc([cx-r, cy-r, cx+r, cy+r], start=160, end=380, fill=teal, width=w)
    # ticks
    for i in range(1, 6):
        a = math.radians(160 + i*220/6)
        x1, y1 = cx + (r-w*1.6)*math.cos(a), cy + (r-w*1.6)*math.sin(a)
        x2, y2 = cx + (r-w*2.6)*math.cos(a), cy + (r-w*2.6)*math.sin(a)
        d.line([x1, y1, x2, y2], fill=white, width=max(4, w//3))
    # pulse line through the centre (diagnostics)
    pts = [(-1.0, 0), (-0.45, 0), (-0.3, -0.35), (-0.12, 0.38), (0.05, -0.55), (0.2, 0.15), (0.32, 0), (1.0, 0)]
    pts = [(cx + x*r*0.82, cy + r*0.18 + y*r*0.6) for x, y in pts]
    d.line(pts, fill=white, width=w//2, joint='curve')
    d.ellipse([cx-w*0.7, cy+r*0.18-w*0.7, cx+w*0.7, cy+r*0.18+w*0.7], fill=teal)

# full icon (iOS + legacy Android)
img = Image.new('RGBA', (S, S))
px = img.load()
for y in range(S):
    t = y / S
    c = (int(10 + 10*t), int(25 + 20*t), int(60 + 40*t), 255)
    for x in range(S):
        px[x, y] = c
symbol(ImageDraw.Draw(img), S/2, S/2 + 70, 330, 64)
img.convert('RGB').save(f'{out}/icon.png')
# adaptive foreground: symbol inside the 66% safe zone
fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
symbol(ImageDraw.Draw(fg), S/2, S/2 + 50, 250, 50)
fg.save(f'{out}/icon_foreground.png')
print('ok')
