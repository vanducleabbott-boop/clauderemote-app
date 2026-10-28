import sys
from PIL import Image, ImageDraw, ImageFilter
N=1024; SS=4; W=N*SS
img=Image.new('RGB',(W,W),(240,238,230))
d=ImageDraw.Draw(img)
grid=[".OOOOOOOOO.",
      ".OOOOOOOOO.",
      "OOKOOOOOKOO",
      "OOOOOOOOOOO",
      "OOOOOOOOOOO",
      ".OOOOOOOOO.",
      ".OOOOOOOOO.",
      ".O.O...O.O.",
      ".O.O...O.O."]
u=52*SS
gx=int(150*SS); gy=int(170*SS)
def cells(ch):
    for r,row in enumerate(grid):
        for c,v in enumerate(row):
            if v in ch: yield gx+c*u, gy+r*u
# white sticker outline
o=18*SS
for x,y in cells('OK'): d.rectangle([x-o,y-o,x+u+o-1,y+u+o-1],fill=(255,255,255))
for x,y in cells('O'): d.rectangle([x,y,x+u-1,y+u-1],fill=(217,119,87))
for x,y in cells('K'): d.rectangle([x,y,x+u-1,y+u-1],fill=(20,20,20))
# Cloudflare-style cloud badge, bottom right
def cloud(dr, ox, oy, s, col):
    dr.ellipse([ox+0*s, oy+40*s, ox+90*s, oy+130*s], fill=col)
    dr.ellipse([ox+50*s, oy+0*s, ox+190*s, oy+140*s], fill=col)
    dr.ellipse([ox+150*s, oy+50*s, ox+230*s, oy+130*s], fill=col)
    dr.rounded_rectangle([ox+40*s, oy+80*s, ox+200*s, oy+130*s], radius=25*s, fill=col)
s=1.55*SS; ox=int(500*SS); oy=int(650*SS)
def both(dr, dx, dy, c1, c2):
    cloud(dr, ox+int(200*SS)+dx, oy+int(40*SS)+dy, s*0.6, c1)
    cloud(dr, ox+dx, oy+dy, s, c2)
for dx in range(-16,17,8):
    for dy in range(-16,17,8):
        both(d, dx*SS, dy*SS, (255,255,255), (255,255,255))
both(d, 0, 0, (251,173,65), (246,130,31))
img=img.resize((N,N),Image.LANCZOS)
img.save(sys.argv[1])
