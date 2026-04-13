"""
generate_sprites.py
Generates 16x16 isometric pixel-art placeholder PNGs for every building
and resource icon needed by Consell.

Output paths match exactly what is declared in config/buildings.json
and config/resources.json, relative to the project root.
"""

from PIL import Image
import os, math

# ── Palette ────────────────────────────────────────────────────────
T   = (0,   0,   0,   0)    # transparent
W   = (255, 255, 255, 255)  # white
BLK = (30,  30,  30,  255)  # near-black outline
SKY = (120, 180, 240, 255)  # light blue (window / sky)

# Earth tones
GRASS  = (80,  160,  60,  255)
DIRT   = (160, 110,  60,  255)
STONE  = (140, 140, 140, 255)
STONE2 = (100, 100, 100, 255)

# Wood tones
WOOD_L = (200, 150,  80, 255)
WOOD_D = (140, 100,  50, 255)

# Roof colours
ROOF_R = (180,  60,  50, 255)   # red tile
ROOF_B = (50,   80, 150, 255)   # blue slate
ROOF_G = (60,  130,  80, 255)   # green thatch
ROOF_Y = (210, 170,  40, 255)   # yellow straw
ROOF_P = (120,  60, 160, 255)   # purple banner roof

# Misc
GOLD   = (220, 180,  40, 255)
WATER  = ( 60, 130, 200, 255)
WATER2 = ( 40,  90, 160, 255)
GREEN  = ( 70, 160,  60, 255)
RED    = (200,  50,  50, 255)
DARK   = ( 50,  50,  80, 255)


# ── Helpers ────────────────────────────────────────────────────────
def new(w=16, h=16):
    return Image.new("RGBA", (w, h), T)

def px(img, coords, color):
    """Paint a list of (x,y) pixels with color."""
    for x, y in coords:
        if 0 <= x < img.width and 0 <= y < img.height:
            img.putpixel((x, y), color)

def row(img, y, x0, x1, color):
    px(img, [(x, y) for x in range(x0, x1+1)], color)

def col(img, x, y0, y1, color):
    px(img, [(x, y) for y in range(y0, y1+1)], color)

def save(img, rel_path):
    full = os.path.join("/home/claude/Consell", rel_path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    img.save(full)
    print(f"  ✓ {rel_path}")


# ══════════════════════════════════════════════════════════════════
#  ISOMETRIC BASE  (diamond ground tile, 16×8 usable area)
#  Convention: iso top at y≈3, widest point y≈7, bottom tip y≈11
# ══════════════════════════════════════════════════════════════════

def draw_iso_ground(img, top, side_l, side_r):
    """Draw a flat isometric diamond tile."""
    # top face (rows 3-7)
    widths = [2, 6, 10, 14, 16, 14, 10, 6, 2]  # symmetric diamond
    starts = [7, 5,  3,  1,  0,  1,  3, 5, 7]
    for i, (w, s) in enumerate(zip(widths, starts)):
        row(img, 3+i, s, s+w-1, top)
    # left side face (rows 8-11)
    for i in range(4):
        row(img, 8+i, i, 7-i, side_l)
    # right side face (rows 8-11)
    for i in range(4):
        row(img, 8+i, 8+i, 15-i, side_r)
    # outline
    px(img, [(7,3),(8,3)], BLK)
    px(img, [(0,7),(15,7)], BLK)
    px(img, [(7,12),(8,12)], BLK)


# ══════════════════════════════════════════════════════════════════
#  BUILDING SPRITES
# ══════════════════════════════════════════════════════════════════

def make_tent():
    img = new()
    # ground patch
    row(img, 12, 4, 11, GRASS)
    row(img, 13, 5, 10, GRASS)
    # tent body (triangle silhouette)
    for y in range(5, 12):
        half = 6 - (y - 5)
        x0 = 8 - half
        x1 = 8 + half
        row(img, y, x0, x1, ROOF_Y)
    # tent shadow / side shading
    for y in range(8, 12):
        col(img, 4+(12-y)//2, y, y, WOOD_D)
    # door
    px(img, [(7,10),(8,10),(7,11),(8,11)], DARK)
    # outline peak
    px(img, [(8,5)], BLK)
    return img

def make_cottage():
    img = new()
    # ground
    row(img, 13, 3, 12, GRASS)
    row(img, 14, 4, 11, GRASS)
    # walls (left face darker)
    for y in range(8, 12):
        row(img, y, 4, 7,  WOOD_D)  # left wall
        row(img, y, 8, 11, WOOD_L)  # right wall
    # roof
    for i, w in enumerate([2, 6, 10, 12]):
        row(img, 4+i, 8-w//2, 8+w//2-1, ROOF_R)
    # window
    px(img, [(5,9),(6,9),(5,10),(6,10)], SKY)
    px(img, [(9,9),(10,9),(9,10),(10,10)], SKY)
    # door
    px(img, [(7,10),(8,10),(7,11),(8,11)], DARK)
    # chimney
    col(img, 5, 4, 7, STONE)
    px(img, [(4,4),(6,4)], STONE2)
    return img

def make_market():
    img = new()
    # wide base
    for y in range(9, 13):
        row(img, y, 2, 13, WOOD_L)
    for y in range(9, 13):
        row(img, y, 2, 5, WOOD_D)
    # awning
    row(img, 7, 1, 14, ROOF_R)
    row(img, 8, 2, 13, ROOF_R)
    # stall posts
    col(img, 3,  8, 12, WOOD_D)
    col(img, 12, 8, 12, WOOD_D)
    # goods on counter
    px(img, [(5,10),(6,10),(8,10),(10,10)], GOLD)
    px(img, [(7,10)], RED)
    # sign
    row(img, 5, 5, 10, WOOD_L)
    row(img, 6, 5, 10, GOLD)
    px(img, [(5,5),(10,5),(5,6),(10,6)], BLK)
    return img

def make_farm():
    img = new()
    # soil rows (isometric-ish)
    for i in range(4):
        row(img, 10+i, 2+i, 13-i, DIRT)
    for i in range(4):
        row(img, 6+i, 3+i, 12-i, GRASS)
    # crop rows
    for x in range(4, 12, 2):
        col(img, x, 7, 9, GREEN)
        px(img, [(x,6)], GREEN)
    # small barn
    for y in range(4, 8):
        row(img, y, 10, 13, WOOD_L)
    row(img, 3, 10, 13, ROOF_R)
    row(img, 4, 10, 13, ROOF_R)
    px(img, [(11,6),(12,6)], DARK)
    return img

def make_well():
    img = new()
    # ground ring
    for y in range(10, 13):
        row(img, y, 5, 10, STONE)
    row(img, 10, 5, 10, STONE2)
    # well walls circle-ish
    px(img, [(5,9),(6,8),(7,8),(8,8),(9,8),(10,9)], STONE)
    px(img, [(5,10),(10,10)], STONE2)
    # water inside
    px(img, [(6,9),(7,9),(8,9),(9,9)], WATER)
    # posts & crossbar
    col(img, 5, 5, 9, WOOD_D)
    col(img, 10, 5, 9, WOOD_D)
    row(img, 5, 4, 11, WOOD_L)
    # roof
    for i, w in enumerate([2,4,6,8]):
        row(img, 2+i, 8-w//2, 8+w//2, ROOF_R)
    # bucket
    px(img, [(7,7),(8,7),(7,8),(8,8)], WOOD_D)
    col(img, 7, 6, 7, BLK)
    return img

def make_road():
    img = new()
    # cobblestone diamond
    draw_iso_ground(img, STONE, STONE2, STONE)
    # stone pattern
    for coords in [[(3,4),(7,4),(11,4)],
                   [(1,6),(5,6),(9,6),(13,6)],
                   [(3,8),(7,8),(11,8)]]:
        px(img, coords, STONE2)
    return img

def make_tavern():
    img = new()
    # ground
    row(img, 13, 2, 13, GRASS)
    # walls
    for y in range(7, 13):
        row(img, y, 3, 7,  WOOD_D)
        row(img, y, 8, 12, WOOD_L)
    # big roof
    for i, w in enumerate([4, 8, 12, 14]):
        row(img, 3+i, 8-w//2, 8+w//2-1, ROOF_B)
    # windows with warm light
    px(img, [(4,8),(5,8),(4,9),(5,9)], GOLD)
    px(img, [(9,8),(10,8),(9,9),(10,9)], GOLD)
    # door (wide)
    row(img, 11, 6, 9, DARK)
    row(img, 12, 6, 9, DARK)
    # sign hanging
    row(img, 5, 6, 9, WOOD_L)
    px(img, [(6,4),(9,4)], WOOD_D)
    col(img, 6, 4, 5, WOOD_D)
    col(img, 9, 4, 5, WOOD_D)
    # chimney smoke hint
    col(img, 4, 2, 3, STONE)
    return img

def make_guard_post():
    img = new()
    # stone tower base
    for y in range(6, 13):
        row(img, y, 4, 11, STONE)
    for y in range(6, 13):
        row(img, y, 4, 6, STONE2)
    # battlements
    px(img, [(4,5),(6,5),(8,5),(10,5)], STONE)
    px(img, [(4,4),(6,4),(8,4),(10,4)], STONE2)
    # arrow slit window
    col(img, 7, 8, 10, DARK)
    col(img, 8, 8, 10, DARK)
    # flag
    col(img, 9, 2, 5, WOOD_L)
    px(img, [(10,2),(11,2),(10,3),(11,3),(10,4)], RED)
    # door arch
    px(img, [(6,12),(7,12),(8,12),(9,12)], DARK)
    px(img, [(6,11),(9,11)], DARK)
    px(img, [(5,11),(10,11)], STONE2)
    return img


# ══════════════════════════════════════════════════════════════════
#  RESOURCE ICONS  (16×16, flat / top-down feel)
# ══════════════════════════════════════════════════════════════════

def make_icon_food():
    img = new()
    # bread loaf shape
    for y in range(5, 11):
        half = 4 - abs(y-7)
        row(img, y, 8-half-2, 8+half+1, (200,140,60,255))
    row(img, 5, 5, 10, (220,160,80,255))
    row(img, 6, 4, 11, (220,160,80,255))
    # crust line
    row(img, 7, 4, 11, (180,110,40,255))
    # seeds
    px(img, [(6,6),(9,6),(7,8),(11,8)], (140,80,30,255))
    return img

def make_icon_water():
    img = new()
    # droplet
    px(img, [(7,3),(8,3)], WATER)
    for y in range(4,10):
        half = min(y-3, 10-y, 4)
        row(img, y, 8-half, 8+half-1, WATER)
    row(img, 10, 5, 10, WATER2)
    row(img, 11, 6,  9, WATER2)
    px(img, [(7,12),(8,12)], WATER2)
    # shine
    px(img, [(6,6),(7,5)], (180,220,255,255))
    return img

def make_icon_wood():
    img = new()
    # three log cross-sections stacked
    offsets = [(3,10),(7,8),(5,5)]
    for ox, oy in offsets:
        for dy in range(3):
            row(img, oy+dy, ox, ox+5, WOOD_L)
        row(img, oy, ox, ox+5, WOOD_D)
        # ring
        px(img, [(ox+2,oy+1),(ox+3,oy+1)], WOOD_D)
    return img

def make_icon_stone():
    img = new()
    # pile of stones
    stones = [
        (3, 9, 6, 3), (9, 9, 4, 3),
        (1, 11,5, 2), (7,11, 6, 2), (13,11,2,2),
        (5, 7, 4, 3), (10, 7, 4, 3),
    ]
    for sx, sy, sw, sh in stones:
        for dy in range(sh):
            row(img, sy+dy, sx, sx+sw-1, STONE if dy==0 else STONE2)
    return img

def make_icon_gold():
    img = new()
    # coin stack
    for i in range(4):
        y = 11 - i*2
        row(img, y,   4, 11, GOLD)
        row(img, y+1, 4, 11, (180,140,30,255))
        px(img, [(4,y),(11,y),(4,y+1),(11,y+1)], BLK)
    # shine on top coin
    px(img, [(6,4),(7,3),(8,3)], W)
    return img


# ══════════════════════════════════════════════════════════════════
#  TERRAIN TILES  (16×16 iso ground)
# ══════════════════════════════════════════════════════════════════

def make_terrain_grass():
    img = new()
    draw_iso_ground(img, (90,170,70,255), (60,120,45,255), (70,140,55,255))
    # grass tufts on top face
    px(img, [(5,5),(9,5),(7,6),(11,6),(6,7)], (50,140,40,255))
    return img

def make_terrain_water():
    img = new()
    draw_iso_ground(img, WATER, WATER2, (50,100,170,255))
    # wave lines
    row(img, 5, 3,  7, (100,180,230,255))
    row(img, 7, 8, 12, (100,180,230,255))
    return img

def make_terrain_forest():
    img = new()
    draw_iso_ground(img, (60,130,50,255), (40,90,35,255), (50,110,40,255))
    # tree on top
    for y in range(0,5):
        half = y+1
        row(img, y, 8-half, 8+half-1, (50,120,40,255))
    col(img, 7, 4, 7, WOOD_D)
    col(img, 8, 4, 7, WOOD_D)
    return img

def make_terrain_mountain():
    img = new()
    draw_iso_ground(img, STONE, STONE2, (110,110,110,255))
    # peak
    for y in range(0,6):
        half = y+1
        row(img, y, 8-half, 8+half-1, STONE)
    # snow cap
    px(img, [(7,0),(8,0),(7,1),(8,1),(6,2),(9,2)], W)
    return img

def make_terrain_sand():
    img = new()
    draw_iso_ground(img, (210,185,120,255), (170,145,90,255), (190,165,105,255))
    # ripple lines
    row(img, 5, 4,  8, (190,165,100,255))
    row(img, 7, 6, 11, (190,165,100,255))
    return img

def make_terrain_fertile():
    img = new()
    draw_iso_ground(img, (100,80,40,255), (70,55,25,255), (85,65,30,255))
    # furrow lines
    for i in range(3):
        row(img, 4+i*2, 2+i, 13-i, (60,40,15,255))
    return img


# ══════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════

SPRITES = {
    # Buildings
    "assets/textures/buildings/tent.png":       make_tent,
    "assets/textures/buildings/cottage.png":    make_cottage,
    "assets/textures/buildings/market.png":     make_market,
    "assets/textures/buildings/farm.png":       make_farm,
    "assets/textures/buildings/well.png":       make_well,
    "assets/textures/buildings/road.png":       make_road,
    "assets/textures/buildings/tavern.png":     make_tavern,
    "assets/textures/buildings/guard_post.png": make_guard_post,
    # Resource icons
    "assets/icons/resource_food.png":  make_icon_food,
    "assets/icons/resource_water.png": make_icon_water,
    "assets/icons/resource_wood.png":  make_icon_wood,
    "assets/icons/resource_stone.png": make_icon_stone,
    "assets/icons/resource_gold.png":  make_icon_gold,
    # Terrain tiles
    "assets/textures/terrain/grass.png":    make_terrain_grass,
    "assets/textures/terrain/water.png":    make_terrain_water,
    "assets/textures/terrain/forest.png":   make_terrain_forest,
    "assets/textures/terrain/mountain.png": make_terrain_mountain,
    "assets/textures/terrain/sand.png":     make_terrain_sand,
    "assets/textures/terrain/fertile.png":  make_terrain_fertile,
}

if __name__ == "__main__":
    print(f"Generating {len(SPRITES)} sprites…\n")
    for rel_path, fn in SPRITES.items():
        save(fn(), rel_path)
    print(f"\nDone! All sprites saved to assets/")
