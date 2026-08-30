import struct, zlib, math
from pathlib import Path

SRC = "Artwork/copiste-logo.png"

def read_png(path):
    data = Path(path).read_bytes()
    pos, idat = 8, b""
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]
        chunk = data[pos+8:pos+8+ln]
        if typ == b"IHDR":
            w, h, bd, ct, _, _, _ = struct.unpack(">IIBBBBB", chunk)
        elif typ == b"IDAT":
            idat += chunk
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0:1,2:3,3:1,4:2,6:4}[ct]
    stride = w*ch
    out = bytearray(); prev = bytearray(stride); i = 0
    for _ in range(h):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i+stride]); i += stride
        for x in range(stride):
            a = line[x-ch] if x >= ch else 0
            b = prev[x]
            c = prev[x-ch] if x >= ch else 0
            if f == 1: line[x] = (line[x]+a) & 255
            elif f == 2: line[x] = (line[x]+b) & 255
            elif f == 3: line[x] = (line[x]+(a+b)//2) & 255
            elif f == 4:
                pa, pb, pc = abs(b-c), abs(a-c), abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x]+pr) & 255
        out += line; prev = line
    return w, h, ch, out

def write_png(path, w, h, rgba):
    raw = b"".join(b"\x00" + bytes(rgba[y*w*4:(y+1)*w*4]) for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t+d) & 0xffffffff)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    Path(path).write_bytes(png)

w, h, ch, px = read_png(SRC)

# Glyph is light on a near-black ground: luminance becomes the template's alpha.
LO, HI = 40.0, 225.0
alpha = [[0.0]*w for _ in range(h)]
for y in range(h):
    for x in range(w):
        o = (y*w+x)*ch
        r, g, b = px[o], px[o+1], px[o+2]
        a = px[o+3]/255 if ch == 4 else 1.0
        luma = 0.299*r + 0.587*g + 0.114*b
        alpha[y][x] = max(0.0, min(1.0, (luma-LO)/(HI-LO))) * a

# Crop to the glyph so it fills the menu bar rather than floating in its dark plate.
xs = [x for y in range(h) for x in range(w) if alpha[y][x] > 0.15]
ys = [y for y in range(h) for x in range(w) if alpha[y][x] > 0.15]
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
gw, gh = x1-x0+1, y1-y0+1
side = max(gw, gh)
pad = int(side*0.04)
side += 2*pad
ox, oy = x0 - (side-gw)//2, y0 - (side-gh)//2
print(f"glyph bbox {gw}x{gh} at ({x0},{y0}) -> square {side}")

def square(sx, sy):
    """Alpha at source coords, 0 outside the image."""
    if 0 <= sx < w and 0 <= sy < h:
        return alpha[sy][sx]
    return 0.0

def resample(size, slash=False):
    scale = side/size
    out = bytearray(size*size*4)
    # Slash geometry in destination space: top-left to bottom-right, SF Symbol style.
    for dy in range(size):
        for dx in range(size):
            acc = n = 0.0
            for sy in range(int(dy*scale), max(int(dy*scale)+1, int((dy+1)*scale))):
                for sx in range(int(dx*scale), max(int(dx*scale)+1, int((dx+1)*scale))):
                    acc += square(ox+sx, oy+sy); n += 1
            a = acc/n if n else 0.0
            if slash:
                # Anti-diagonal stroke, lower-left to upper-right, as SF Symbols draw it.
                d = abs(dx+dy-(size-1))/math.sqrt(2)
                gap, stroke = size*0.085, size*0.040
                if d < stroke: a = 1.0
                elif d < gap: a = 0.0
            o = (dy*size+dx)*4
            out[o+3] = int(round(max(0.0, min(1.0, a))*255))
    return out

for name, slash in (("MenuIcon", False), ("MenuIconOff", True)):
    for size, suffix in ((18, ""), (36, "@2x")):
        write_png(f"Sources/Copiste/Resources/{name}{suffix}.png", size, size, resample(size, slash))
        print("wrote", f"{name}{suffix}.png", f"{size}x{size}")

# Full-colour app icon: pad the artwork to a square on its own background colour, for
# Scripts/make_icons.sh to turn into Icon.icns.
bg = (px[0], px[1], px[2], 255)
s = max(w, h)
canvas = bytearray()
for y in range(s):
    for x in range(s):
        sx, sy = x-(s-w)//2, y-(s-h)//2
        if 0 <= sx < w and 0 <= sy < h:
            o = (sy*w+sx)*ch
            canvas += bytes((px[o], px[o+1], px[o+2], px[o+3] if ch == 4 else 255))
        else:
            canvas += bytes(bg)
write_png("Artwork/appicon-square.png", s, s, canvas)
print("wrote square app icon", s)
