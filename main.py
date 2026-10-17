# -*- coding: utf-8 -*-
"""
末日生存日志 · Dead Days v0.2（画面重制版）
俯视角僵尸生存 + 生存日志 单机游戏（Python + Pygame）

操作：
  WASD/方向键 移动 | Shift 奔跑 | 空格 攻击 | E 搜刮/喝水
  1 吃罐头 2 喝水 3 绷带 | T 睡觉到黎明 | J 日志 | Esc 存档并回主菜单
  日志界面：直接打字输入，←/→ 选心情，Enter 写下，滚轮翻页，F5 导出
"""
import os
import sys
import json
import math
import random

SELFTEST = "--selftest" in sys.argv
if SELFTEST:
    os.environ["SDL_VIDEODRIVER"] = "dummy"
    os.environ["SDL_AUDIODRIVER"] = "dummy"

import pygame

WIDTH, HEIGHT = 960, 600
TILE = 32
MAP_W, MAP_H = 120, 120
DAY_LEN = 360.0
DAWN = 360.0

GRASS, ROAD, WALL, FLOOR, DOOR, TREE, WATER = range(7)
WALKABLE = {GRASS, ROAD, FLOOR, DOOR}

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SAVE_FILE = os.path.join(BASE_DIR, "save.json")
EXPORT_DIR = os.path.join(BASE_DIR, "exports")

WEAPONS = [("拳头", 12), ("棒球棍", 30), ("砍刀", 45)]
WEAPON_COLORS = [(0, 0, 0), (150, 105, 60), (180, 185, 195)]
MOODS = ["平静", "疲惫", "恐惧", "希望", "绝望"]
MOOD_COLORS = {
    "平静": (180, 200, 180), "疲惫": (200, 180, 120),
    "恐惧": (220, 130, 130), "希望": (130, 200, 230), "绝望": (150, 120, 160),
}
ZOMBIE_SHIRTS = [(88, 78, 96), (70, 88, 78), (98, 70, 70), (78, 78, 84)]

# ---------------------------------------------------------------- 工具

_font_cache = {}
def get_font(size):
    if size not in _font_cache:
        for name in ("microsoftyahei", "msyh", "simhei", "simsun", "arialunicode"):
            path = pygame.font.match_font(name)
            if path:
                _font_cache[size] = pygame.font.Font(path, size)
                break
        else:
            _font_cache[size] = pygame.font.Font(None, size)
    return _font_cache[size]

def wrap_text(text, font, max_w):
    lines, cur = [], ""
    for ch in text:
        if ch == "\n":
            lines.append(cur); cur = ""; continue
        if font.size(cur + ch)[0] > max_w and cur:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines

def clamp(v, a, b):
    return max(a, min(b, v))

def darkness(minutes):
    h = minutes / 60.0
    if 8 <= h < 17:
        return 0.0
    if 17 <= h < 20:
        return (h - 17) / 3 * 0.62
    if 20 <= h or h < 5:
        return 0.62
    return 0.62 * (1 - (h - 5) / 3)

# ---------------------------------------------------------------- 程序化贴图

def build_tiles(map_data):
    """生成每种地形的贴图变体 + 每格变体索引 + 道路标线方向"""
    rng = random.Random(20261017)
    surfs = {}
    variants = [0] * (MAP_W * MAP_H)
    road_line = [0] * (MAP_W * MAP_H)

    def base(color):
        s = pygame.Surface((TILE, TILE))
        s.fill(color)
        return s

    # 草地 ×3 变体
    grass = []
    for v in range(3):
        s = base((88 + v * 4, 126 + v * 3, 72 + v * 2))
        for _ in range(7):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            c = rng.choice([(70, 105, 58), (105, 145, 85), (78, 116, 64)])
            pygame.draw.circle(s, c, (x, y), rng.randint(1, 2))
        for _ in range(2):  # 草叶
            x, y = rng.randrange(4, 28), rng.randrange(4, 28)
            pygame.draw.line(s, (60, 95, 52), (x, y), (x - 2, y - 4), 1)
            pygame.draw.line(s, (96, 138, 80), (x, y), (x + 2, y - 4), 1)
        grass.append(s)
    surfs[GRASS] = grass

    # 道路
    road = []
    for v in range(2):
        s = base((74, 74, 80))
        for _ in range(10):
            x, y = rng.randrange(TILE), rng.randrange(TILE)
            c = rng.choice([(64, 64, 70), (84, 84, 90), (70, 70, 76)])
            pygame.draw.circle(s, c, (x, y), 1)
        road.append(s)
    surfs[ROAD] = road

    # 木地板
    floor_s = base((156, 136, 106))
    for i in range(4):
        y = i * 8 + 7
        pygame.draw.line(floor_s, (130, 110, 84), (0, y), (TILE, y), 1)
    for i in range(3):
        x = rng.randrange(6, 26); y = rng.randrange(6, 26)
        pygame.draw.circle(floor_s, (138, 117, 88), (x, y), 2)
    pygame.draw.rect(floor_s, (120, 100, 76), (0, 0, TILE, TILE), 1)
    surfs[FLOOR] = [floor_s]

    # 砖墙
    wall = base((118, 88, 60))
    for row in range(4):
        y = row * 8 + 7
        pygame.draw.line(wall, (88, 62, 40), (0, y), (TILE, y), 1)
        off = 8 if row % 2 else 0
        for bx in range(off, TILE, 16):
            pygame.draw.line(wall, (88, 62, 40), (bx, y - 7), (bx, y), 1)
    pygame.draw.rect(wall, (142, 110, 78), (0, 0, TILE, 4))
    pygame.draw.rect(wall, (70, 48, 32), (0, 0, TILE, TILE), 1)
    surfs[WALL] = [wall]

    # 门
    door = base((98, 66, 36))
    pygame.draw.rect(door, (70, 46, 24), (2, 2, TILE - 4, TILE - 4), 2)
    pygame.draw.rect(door, (112, 78, 44), (6, 6, TILE - 12, TILE - 12), 1)
    pygame.draw.circle(door, (205, 175, 95), (24, 16), 2)
    surfs[DOOR] = [door]

    # 树
    tree = grass[1].copy()
    pygame.draw.rect(tree, (82, 58, 38), (14, 20, 4, 6))
    pygame.draw.circle(tree, (40, 80, 40), (16, 14), 11)
    pygame.draw.circle(tree, (52, 98, 50), (12, 11), 7)
    pygame.draw.circle(tree, (66, 118, 62), (19, 9), 5)
    pygame.draw.circle(tree, (30, 62, 30), (16, 14), 11, 1)
    surfs[TREE] = [tree]

    # 水
    water = base((56, 88, 158))
    for _ in range(6):
        x, y = rng.randrange(TILE), rng.randrange(TILE)
        pygame.draw.circle(water, (48, 76, 140), (x, y), rng.randint(1, 3))
    surfs[WATER] = [water]

    # 每格变体 + 道路标线方向
    for y in range(MAP_H):
        for x in range(MAP_W):
            i = y * MAP_W + x
            t = map_data[i]
            if t == GRASS:
                variants[i] = rng.randrange(3)
            elif t == ROAD:
                variants[i] = rng.randrange(2)
                up = map_data[i - MAP_W] if y > 0 else None
                dn = map_data[i + MAP_W] if y < MAP_H - 1 else None
                lf = map_data[i - 1] if x > 0 else None
                rt = map_data[i + 1] if x < MAP_W - 1 else None
                if up == ROAD and dn == ROAD and lf != ROAD and rt != ROAD:
                    road_line[i] = 1
                elif lf == ROAD and rt == ROAD and up != ROAD and dn != ROAD:
                    road_line[i] = 2
    return surfs, variants, road_line

# ---------------------------------------------------------------- 世界生成

def gen_world(seed):
    rng = random.Random(seed)
    m = [GRASS] * (MAP_W * MAP_H)

    def set_t(x, y, t):
        if 0 <= x < MAP_W and 0 <= y < MAP_H:
            m[y * MAP_W + x] = t

    def get_t(x, y):
        if 0 <= x < MAP_W and 0 <= y < MAP_H:
            return m[y * MAP_W + x]
        return WALL

    for r in (25, 65, 105):
        for i in range(MAP_W):
            for d in (-1, 0, 1):
                set_t(r + d, i, ROAD)
                set_t(i, r + d, ROAD)

    houses, containers = [], []
    for _ in range(300):
        if len(houses) >= 14:
            break
        w, h = rng.randint(7, 11), rng.randint(6, 9)
        x, y = rng.randint(2, MAP_W - w - 3), rng.randint(2, MAP_H - h - 3)
        ok = True
        for yy in range(y - 2, y + h + 2):
            for xx in range(x - 2, x + w + 2):
                if get_t(xx, yy) in (ROAD, WALL, FLOOR, DOOR, WATER):
                    ok = False; break
            if not ok:
                break
        if not ok:
            continue
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                edge = xx in (x, x + w - 1) or yy in (y, y + h - 1)
                set_t(xx, yy, WALL if edge else FLOOR)
        side = rng.randrange(4)
        if side == 0:   dx, dy = rng.randint(x + 1, x + w - 2), y
        elif side == 1: dx, dy = rng.randint(x + 1, x + w - 2), y + h - 1
        elif side == 2: dx, dy = x, rng.randint(y + 1, y + h - 2)
        else:           dx, dy = x + w - 1, rng.randint(y + 1, y + h - 2)
        set_t(dx, dy, DOOR)
        for _ in range(rng.randint(1, 3)):
            cx = rng.randint(x + 1, x + w - 2)
            cy = rng.randint(y + 1, y + h - 2)
            containers.append({"x": cx, "y": cy, "looted": False})
        houses.append((x, y, w, h))

    lx, ly = rng.randint(15, MAP_W - 15), rng.randint(15, MAP_H - 15)
    for yy in range(ly - 8, ly + 9):
        for xx in range(lx - 8, lx + 9):
            if (xx - lx) ** 2 / 64 + (yy - ly) ** 2 / 49 <= 1 and get_t(xx, yy) == GRASS:
                set_t(xx, yy, WATER)

    n = 0
    while n < 380:
        x, y = rng.randrange(MAP_W), rng.randrange(MAP_H)
        if get_t(x, y) == GRASS:
            set_t(x, y, TREE); n += 1

    return m, houses, containers

# ---------------------------------------------------------------- 僵尸

class Zombie:
    __slots__ = ("x", "y", "hp", "speed", "ang", "retarget", "atk_cd",
                 "col", "phase")
    def __init__(self, x, y, rng=None):
        r = rng or random
        self.x, self.y = x, y
        self.hp = r.randint(40, 70)
        self.speed = r.uniform(34, 58)
        self.ang = r.uniform(0, math.tau)
        self.retarget = r.uniform(1, 4)
        self.atk_cd = 0.0
        self.col = r.choice(ZOMBIE_SHIRTS)
        self.phase = r.uniform(0, math.tau)

# ---------------------------------------------------------------- 角色绘制

def draw_actor(surf, sx, sy, facing, body_col, skin_col, t, phase=0.0,
               walking=True, zombie=False, weapon=0):
    bob = math.sin(t * 11 + phase) * 1.6 if walking else 0.0
    fx, fy = math.cos(facing), math.sin(facing)
    px, py = -fy, fx
    # 影子
    sh = pygame.Surface((26, 12), pygame.SRCALPHA)
    pygame.draw.ellipse(sh, (0, 0, 0, 60), (0, 0, 26, 12))
    surf.blit(sh, (sx - 13, sy + 6))
    # 腿（行走交替）
    step = math.sin(t * 11 + phase) * 4 if walking else 0
    for s in (-1, 1):
        lx = sx + px * 3.5 * s + fx * step * s
        ly = sy + py * 3.5 * s + fy * step * s + 5
        pygame.draw.circle(surf, (52, 52, 60), (int(lx), int(ly)), 3)
    # 身体
    pygame.draw.circle(surf, tuple(max(0, c - 40) for c in body_col),
                       (int(sx), int(sy + bob)), 10)
    pygame.draw.circle(surf, body_col, (int(sx), int(sy + bob - 1)), 9)
    if zombie:
        pygame.draw.circle(surf, (60, 48, 52),
                           (int(sx - px * 4), int(sy + bob - py * 4)), 2)
        # 双臂前伸
        for s in (-1, 1):
            ax = sx + fx * 13 + px * 4 * s
            ay = sy + bob + fy * 13 + py * 4 * s
            pygame.draw.line(surf, skin_col, (sx, sy + bob), (ax, ay), 3)
            pygame.draw.circle(surf, skin_col, (int(ax), int(ay)), 3)
    else:
        ax = sx + fx * 10 + px * 5
        ay = sy + bob + fy * 10 + py * 5
        pygame.draw.line(surf, skin_col, (sx, sy + bob), (ax, ay), 3)
        if weapon > 0:
            wl = 14 + weapon * 4
            wx, wy = ax + fx * wl, ay + fy * wl
            pygame.draw.line(surf, WEAPON_COLORS[weapon], (ax, ay), (wx, wy),
                             4 if weapon == 1 else 3)
            if weapon == 2:
                pygame.draw.circle(surf, (220, 225, 235), (int(wx), int(wy)), 2)
    # 头
    hx = sx + fx * 4
    hy = sy + bob + fy * 4 - 2
    pygame.draw.circle(surf, tuple(max(0, c - 30) for c in skin_col),
                       (int(hx), int(hy)), 6)
    pygame.draw.circle(surf, skin_col, (int(hx), int(hy - 1)), 5)
    if zombie:
        ex, ey = hx + fx * 4, hy + fy * 4 - 1
        pygame.draw.circle(surf, (215, 60, 60),
                           (int(ex + px * 2), int(ey + py * 2)), 1)
        pygame.draw.circle(surf, (215, 60, 60),
                           (int(ex - px * 2), int(ey - py * 2)), 1)

# ---------------------------------------------------------------- 游戏主体

class Game:
    def __init__(self):
        self.state = "MENU"
        self.zombies = []
        self.msgs = []
        self.particles = []
        self.decals = []
        self.journal_scroll = 0
        self.journal_input = ""
        self.journal_mood = 0
        self.has_save = os.path.exists(SAVE_FILE)
        self.minimap = None
        self.anim_t = 0.0
        self.moving = False
        self._light = None
        self._glow = None
        self._vignette = None

    # ---------- 开局 ----------

    def new_game(self):
        self.seed = random.randrange(10 ** 9)
        self._init_world()
        px, py = 65 * TILE + 16, 65 * TILE + 16
        self.player = dict(x=px, y=py, hp=100.0, hunger=85.0, thirst=85.0,
                           fatigue=90.0, weapon=0, facing=0.0)
        self.inv = {"food": 1, "water": 1, "bandage": 0}
        self.day, self.minutes = 1, DAWN
        self.journal = []
        self.stats = {"kills": 0, "searches": 0, "damage": 0.0}
        self.pkills = self.psearches = 0
        self.pdamage = 0.0
        self.zombies = []
        self.decals = []
        self.atk_cd = 0.0
        self.hurt_cd = 0.0
        self.injury_log_cd = 0.0
        self.lowhp_log_cd = 0.0
        self.spawn_t = 0.0
        self.shake = 0.0
        self.swing_t = 0.0
        self.dust_t = 0.0
        self.first_zombie_seen = False
        self.dusk_logged_day = 0
        self.state = "PLAY"
        self.add_log("第1天。醒来的时候，城里已经全是它们了。收音机里只剩杂音。"
                     "我得活下去——把这本子写满，写到有人找到它的那天。", "恐惧")

    def _init_world(self):
        self.map, self.houses, self.containers = gen_world(self.seed)
        self.tile_surfs, self.variants, self.road_line = build_tiles(self.map)
        self.minimap = pygame.Surface((MAP_W, MAP_H))
        mm_colors = {
            GRASS: (86, 125, 70), ROAD: (72, 72, 78), WALL: (112, 82, 54),
            FLOOR: (152, 132, 102), DOOR: (92, 62, 32), TREE: (50, 95, 50),
            WATER: (62, 92, 165),
        }
        for y in range(MAP_H):
            for x in range(MAP_W):
                self.minimap.set_at((x, y), mm_colors[self.map[y * MAP_W + x]])

    def save_game(self):
        if self.state == "DEAD":
            return
        data = {
            "seed": self.seed, "day": self.day, "minutes": self.minutes,
            "player": self.player, "inv": self.inv,
            "looted": [i for i, c in enumerate(self.containers) if c["looted"]],
            "journal": self.journal, "stats": self.stats,
        }
        with open(SAVE_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
        self.has_save = True

    def load_game(self):
        with open(SAVE_FILE, "r", encoding="utf-8") as f:
            d = json.load(f)
        self.seed = d["seed"]
        self._init_world()
        for i in d["looted"]:
            if 0 <= i < len(self.containers):
                self.containers[i]["looted"] = True
        self.player = d["player"]
        self.inv = d["inv"]
        self.day, self.minutes = d["day"], d["minutes"]
        self.journal = d["journal"]
        self.stats = d["stats"]
        self.pkills = self.psearches = 0
        self.pdamage = 0.0
        self.zombies = []
        self.decals = []
        self.atk_cd = self.hurt_cd = 0.0
        self.injury_log_cd = self.lowhp_log_cd = 0.0
        self.spawn_t = 0.0
        self.shake = self.swing_t = self.dust_t = 0.0
        self.first_zombie_seen = True
        self.dusk_logged_day = self.day
        self.state = "PLAY"
        self.msg("已读取存档")

    # ---------- 日志 ----------

    def clock(self):
        return f"{int(self.minutes // 60):02d}:{int(self.minutes % 60):02d}"

    def auto_mood(self):
        p = self.player
        if p["hp"] < 30 or p["hunger"] < 15 or p["thirst"] < 15:
            return "绝望"
        if p["hp"] < 55 or p["fatigue"] < 25:
            return "恐惧"
        if p["fatigue"] < 50:
            return "疲惫"
        if self.pkills >= 5:
            return "平静"
        return random.choice(["平静", "疲惫", "希望"])

    def add_log(self, text, mood=None, auto=True):
        self.journal.append({
            "day": self.day, "time": self.clock(),
            "mood": mood or self.auto_mood(), "text": text, "auto": auto,
        })

    def export_journal(self):
        os.makedirs(EXPORT_DIR, exist_ok=True)
        fn = os.path.join(EXPORT_DIR,
                          f"生存日志_第{self.day}天_{len(self.journal)}条.md")
        s = self.stats
        out = [f"# 末日生存日志", "",
               f"> 存活 {self.day} 天 · 击杀 {s['kills']} · "
               f"搜刮 {s['searches']} 处 · 共 {len(self.journal)} 条", ""]
        for e in self.journal:
            tag = "（自动）" if e["auto"] else "（手写）"
            out.append(f"**第{e['day']}天 {e['time']} · {e['mood']}**{tag}")
            out.append("")
            out.append(e["text"])
            out.append("")
        with open(fn, "w", encoding="utf-8") as f:
            f.write("\n".join(out))
        return fn

    # ---------- 时间 ----------

    def advance_minutes(self, total):
        while total > 0:
            step = min(total, 5.0)
            prev = self.minutes
            self.minutes += step
            if self.minutes >= 1440:
                self.minutes -= 1440
                self.day += 1
            if prev < DAWN <= self.minutes:
                self.dawn_summary()
            total -= step

    def dawn_summary(self):
        pd = self.day - 1
        if pd < 1:
            return
        parts = [f"第{pd}天过去了。"]
        if self.pkills:
            parts.append(f"昨天杀了 {self.pkills} 只。")
        if self.psearches:
            parts.append(f"搜了 {self.psearches} 个地方。")
        if self.pdamage > 30:
            parts.append("伤得不轻，浑身疼。")
        if not (self.pkills or self.psearches):
            parts.append("躲了一整天，什么也没做。")
        p = self.player
        if p["hunger"] < 30:
            parts.append("肚子一直在叫。")
        if p["thirst"] < 30:
            parts.append("嘴唇裂了，得找水。")
        parts.append("天亮了，继续。")
        self.add_log("".join(parts))
        self.pkills = self.psearches = 0
        self.pdamage = 0.0
        self.save_game()

    def do_sleep(self):
        p = self.player
        near = [z for z in self.zombies
                if math.hypot(z.x - p["x"], z.y - p["y"]) < 150]
        if near:
            self.msg("附近有僵尸，无法入睡！")
            return
        delta = (DAWN - self.minutes) % 1440 or 1440
        self.advance_minutes(delta)
        p["fatigue"] = 100.0
        p["hunger"] = clamp(p["hunger"] - 25, 0, 100)
        p["thirst"] = clamp(p["thirst"] - 30, 0, 100)
        fed = p["hunger"] > 20 and p["thirst"] > 20
        p["hp"] = clamp(p["hp"] + (15 if fed else 5), 0, 100)
        if random.random() < 0.25:
            for _ in range(2):
                ang = random.uniform(0, math.tau)
                zx = clamp(p["x"] + math.cos(ang) * 90, 32, MAP_W * TILE - 32)
                zy = clamp(p["y"] + math.sin(ang) * 90, 32, MAP_H * TILE - 32)
                self.zombies.append(Zombie(zx, zy))
            self.add_log("睡到一半被拍门声惊醒——它们找到我了。连觉都睡不安稳。", "恐惧")
        else:
            self.add_log("睡了一觉。梦里没有嘶吼声，醒来却更累了。")
        self.msg("睡到了黎明")
        self.save_game()

    # ---------- 战斗与交互 ----------

    def msg(self, text):
        self.msgs.append([text, 2.8])

    def spawn_particles(self, x, y, color, n=8):
        for _ in range(n):
            a = random.uniform(0, math.tau)
            v = random.uniform(40, 140)
            self.particles.append([x, y, math.cos(a) * v, math.sin(a) * v,
                                   random.uniform(0.2, 0.5), color])

    def add_decal(self, x, y):
        self.decals.append((x + random.uniform(-6, 6),
                            y + random.uniform(-6, 6),
                            random.randint(4, 9)))
        if len(self.decals) > 220:
            self.decals.pop(0)

    def try_attack(self):
        if self.atk_cd > 0:
            return
        self.atk_cd = 0.42
        self.swing_t = 0.15
        p = self.player
        p["fatigue"] = clamp(p["fatigue"] - 4, 0, 100)
        name, dmg = WEAPONS[p["weapon"]]
        reach = 50 + p["weapon"] * 6
        hit = False
        for z in list(self.zombies):
            dx, dy = z.x - p["x"], z.y - p["y"]
            d = math.hypot(dx, dy)
            if d > reach:
                continue
            ang = math.atan2(dy, dx)
            diff = abs((ang - p["facing"] + math.pi) % math.tau - math.pi)
            if diff > math.radians(65):
                continue
            hit = True
            z.hp -= dmg * random.uniform(0.8, 1.2)
            z.x += math.cos(ang) * 26
            z.y += math.sin(ang) * 26
            self.spawn_particles(z.x, z.y, (170, 30, 30))
            self.add_decal(z.x, z.y)
            if z.hp <= 0:
                self.zombies.remove(z)
                self.add_decal(z.x, z.y)
                self.add_decal(z.x, z.y)
                self.stats["kills"] += 1
                self.pkills += 1
                if self.stats["kills"] == 1:
                    self.add_log(f"第一次杀死它们中的一个。用{name}。"
                                 "它倒下去的时候，我吐了很久。")
                elif self.stats["kills"] % 10 == 0:
                    self.add_log(f"第 {self.stats['kills']} 只。已经麻木了，"
                                 "数着数着就习惯了。")
        if hit:
            self.shake = max(self.shake, 2)

    def hurt(self, dmg, source=""):
        if self.hurt_cd > 0:
            return
        self.hurt_cd = 0.25
        p = self.player
        p["hp"] -= dmg
        self.stats["damage"] += dmg
        self.pdamage += dmg
        self.shake = 6
        self.spawn_particles(p["x"], p["y"], (200, 40, 40), 10)
        self.add_decal(p["x"], p["y"])
        if self.injury_log_cd <= 0:
            self.injury_log_cd = 6
            self.add_log(random.choice([
                "被挠了一下，口子不深，但一直在烧。",
                "它抓到我的胳膊了。希望只是皮外伤。",
                "又被咬边缘蹭到……千万别感染，千万别。",
            ]), "恐惧")
        if p["hp"] <= 0:
            self.die(source or "僵尸")

    def die(self, cause):
        self.state = "DEAD"
        self.add_log(f"【终章】第{self.day}天。我没能撑过去。{cause}。"
                     "如果你捡到这本子……替我看看明天的太阳。", "绝望")
        if os.path.exists(SAVE_FILE):
            os.remove(SAVE_FILE)
        self.has_save = False

    def interact(self):
        p = self.player
        best, bd = None, 46
        for c in self.containers:
            if c["looted"]:
                continue
            d = math.hypot(c["x"] * TILE + 16 - p["x"], c["y"] * TILE + 16 - p["y"])
            if d < bd:
                best, bd = c, d
        if best is not None:
            best["looted"] = True
            self.stats["searches"] += 1
            self.psearches += 1
            r = random.random()
            if r < 0.15:
                self.msg("一无所获")
                if random.random() < 0.4:
                    self.add_log("翻了一间屋子，空的。连一粒米都没剩下。", "疲惫")
            elif r < 0.55:
                n = random.randint(1, 2)
                self.inv["food"] += n
                self.msg(f"获得 罐头×{n}")
            elif r < 0.75:
                n = random.randint(1, 2)
                self.inv["water"] += n
                self.msg(f"获得 瓶装水×{n}")
            elif r < 0.88:
                self.inv["bandage"] += 1
                self.msg("获得 绷带×1")
            else:
                if p["weapon"] < 2:
                    p["weapon"] += 1
                    name = WEAPONS[p["weapon"]][0]
                    self.msg(f"获得武器：{name}！")
                    self.add_log(f"找到一把{name}。握在手里，第一次觉得"
                                 "自己不是猎物。")
                else:
                    self.inv["food"] += 1
                    self.msg("获得 罐头×1")
            return
        tx, ty = int(p["x"] // TILE), int(p["y"] // TILE)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                x, y = tx + dx, ty + dy
                if 0 <= x < MAP_W and 0 <= y < MAP_H \
                        and self.map[y * MAP_W + x] == WATER:
                    p["thirst"] = clamp(p["thirst"] + 50, 0, 100)
                    p["hp"] -= 3
                    self.msg("喝了湖水（-3 HP）")
                    self.add_log("实在渴得受不了，喝了湖里的水。有点腥，"
                                 "希望别拉肚子。", "疲惫")
                    if p["hp"] <= 0:
                        self.die("一湖水")
                    return
        self.msg("附近没有可搜刮的东西")

    def use_item(self, kind):
        p = self.player
        if kind == "food" and self.inv["food"] > 0:
            self.inv["food"] -= 1
            p["hunger"] = clamp(p["hunger"] + 45, 0, 100)
            self.msg("吃了罐头（+45 饱食）")
        elif kind == "water" and self.inv["water"] > 0:
            self.inv["water"] -= 1
            p["thirst"] = clamp(p["thirst"] + 45, 0, 100)
            self.msg("喝了水（+45 水分）")
        elif kind == "bandage" and self.inv["bandage"] > 0:
            self.inv["bandage"] -= 1
            p["hp"] = clamp(p["hp"] + 30, 0, 100)
            self.msg("包扎了伤口（+30 HP）")
        else:
            self.msg("没有对应物品")

    # ---------- 更新 ----------

    def walkable(self, x, y):
        for cx in (-9, 9):
            for cy in (-9, 9):
                tx, ty = int((x + cx) // TILE), int((y + cy) // TILE)
                if not (0 <= tx < MAP_W and 0 <= ty < MAP_H):
                    return False
                if self.map[ty * MAP_W + tx] not in WALKABLE:
                    return False
        return True

    def spawn_zombie(self):
        p = self.player
        for _ in range(30):
            x = random.uniform(32, MAP_W * TILE - 32)
            y = random.uniform(32, MAP_H * TILE - 32)
            d = math.hypot(x - p["x"], y - p["y"])
            if 380 < d < 900 and self.walkable(x, y):
                self.zombies.append(Zombie(x, y))
                return

    def update(self, dt, pressed):
        p = self.player
        self.anim_t += dt
        self.advance_minutes(dt * 1440 / DAY_LEN)

        running = (pygame.K_LSHIFT in pressed or pygame.K_RSHIFT in pressed) \
            and p["fatigue"] > 0
        speed = 205 if running else 135
        if p["fatigue"] <= 0:
            speed *= 0.55
        mx = my = 0
        if pygame.K_w in pressed or pygame.K_UP in pressed:    my -= 1
        if pygame.K_s in pressed or pygame.K_DOWN in pressed:  my += 1
        if pygame.K_a in pressed or pygame.K_LEFT in pressed:  mx -= 1
        if pygame.K_d in pressed or pygame.K_RIGHT in pressed: mx += 1
        self.moving = bool(mx or my)
        if mx or my:
            n = math.hypot(mx, my)
            mx, my = mx / n, my / n
            p["facing"] = math.atan2(my, mx)
            nx, ny = p["x"] + mx * speed * dt, p["y"] + my * speed * dt
            if self.walkable(nx, p["y"]):
                p["x"] = nx
            if self.walkable(p["x"], ny):
                p["y"] = ny
            if running:
                p["fatigue"] = clamp(p["fatigue"] - 6 * dt, 0, 100)
                self.dust_t -= dt
                if self.dust_t <= 0:
                    self.dust_t = 0.12
                    self.particles.append([p["x"] - mx * 8, p["y"] - my * 8 + 6,
                                           random.uniform(-12, 12),
                                           random.uniform(-18, -6), 0.35,
                                           (150, 140, 120)])

        if pygame.K_SPACE in pressed:
            self.try_attack()

        p["hunger"] = clamp(p["hunger"] - 100 / 600 * dt, 0, 100)
        p["thirst"] = clamp(p["thirst"] - 100 / 480 * dt, 0, 100)
        p["fatigue"] = clamp(p["fatigue"] - 100 / 1400 * dt, 0, 100)
        if p["hunger"] <= 0:    p["hp"] -= 1.2 * dt
        if p["thirst"] <= 0:    p["hp"] -= 2.0 * dt
        if p["fatigue"] <= 0:   p["hp"] -= 0.4 * dt
        if p["hunger"] > 60 and p["thirst"] > 60 and p["hp"] > 0:
            p["hp"] = clamp(p["hp"] + 0.6 * dt, 0, 100)
        if p["hp"] <= 0:
            cause = "饥渴交加" if (p["hunger"] <= 0 or p["thirst"] <= 0) else "力竭"
            self.die(cause)
            return
        if p["hp"] < 25 and self.lowhp_log_cd <= 0:
            self.lowhp_log_cd = 20
            self.add_log("伤越来越重了。视线有点发黑。得找个地方躲起来。", "绝望")

        if 1170 <= self.minutes < 1200 and self.dusk_logged_day != self.day:
            self.dusk_logged_day = self.day
            self.add_log("天黑了。远处又响起那种声音。今晚也得睁着一只眼睡。", "恐惧")

        self.atk_cd = max(0, self.atk_cd - dt)
        self.hurt_cd = max(0, self.hurt_cd - dt)
        self.injury_log_cd = max(0, self.injury_log_cd - dt)
        self.lowhp_log_cd = max(0, self.lowhp_log_cd - dt)
        self.swing_t = max(0, self.swing_t - dt)
        self.shake = max(0, self.shake - dt * 20)

        self.spawn_t -= dt
        target = min(10 + self.day * 2, 48)
        if self.spawn_t <= 0 and len(self.zombies) < target:
            self.spawn_t = 1.5
            self.spawn_zombie()

        night = darkness(self.minutes) > 0.2
        sight = (150 if night else 230) + (80 if running else 0)
        for z in self.zombies:
            dx, dy = p["x"] - z.x, p["y"] - z.y
            d = math.hypot(dx, dy) or 1
            z.atk_cd -= dt
            z.retarget -= dt
            if d < sight:
                z.ang = math.atan2(dy, dx)
                if not self.first_zombie_seen:
                    self.first_zombie_seen = True
                    self.add_log("第一次近距离看见它们。眼睛是灰的，"
                                 "动作一卡一卡的，像坏掉的木偶。", "恐惧")
            elif z.retarget <= 0:
                z.retarget = random.uniform(1.5, 4)
                z.ang = random.uniform(0, math.tau)
            sp = z.speed * (1.15 if night else 1.0) * (1.3 if d < sight else 0.55)
            nx = z.x + math.cos(z.ang) * sp * dt
            ny = z.y + math.sin(z.ang) * sp * dt
            if self.walkable(nx, z.y):
                z.x = nx
            else:
                z.ang = random.uniform(0, math.tau)
            if self.walkable(z.x, ny):
                z.y = ny
            else:
                z.ang = random.uniform(0, math.tau)
            if d < 28 and z.atk_cd <= 0:
                z.atk_cd = 0.9
                self.hurt(random.uniform(7, 13), "僵尸的撕咬")
                if self.state == "DEAD":
                    return
        zs = self.zombies
        for i in range(len(zs)):
            for j in range(i + 1, len(zs)):
                a, b = zs[i], zs[j]
                dx, dy = b.x - a.x, b.y - a.y
                d2 = dx * dx + dy * dy
                if 0 < d2 < 400:
                    d = math.sqrt(d2)
                    push = (20 - d) / 2 / d
                    a.x -= dx * push; a.y -= dy * push
                    b.x += dx * push; b.y += dy * push

        for pt in list(self.particles):
            pt[0] += pt[2] * dt; pt[1] += pt[3] * dt; pt[4] -= dt
            if pt[4] <= 0:
                self.particles.remove(pt)
        for m in list(self.msgs):
            m[1] -= dt
            if m[1] <= 0:
                self.msgs.remove(m)

    # ---------- 渲染 ----------

    def camera(self):
        p = self.player
        cx = clamp(p["x"] - WIDTH / 2, 0, MAP_W * TILE - WIDTH)
        cy = clamp(p["y"] - HEIGHT / 2, 0, MAP_H * TILE - HEIGHT)
        if self.shake > 0:
            cx += random.uniform(-self.shake, self.shake)
            cy += random.uniform(-self.shake, self.shake)
        return cx, cy

    def _build_light(self):
        R = 300
        s = pygame.Surface((R * 2, R * 2), pygame.SRCALPHA)
        s.fill((5, 5, 30, 255))
        for i in range(16):
            r = 300 - i * 10
            a = int((i / 15) ** 1.6 * 230)
            pygame.draw.circle(s, (0, 0, 0, a), (R, R), max(r, 1))
        self._light = s
        g = pygame.Surface((R * 2, R * 2), pygame.SRCALPHA)
        for r, c in ((280, (9, 7, 3)), (210, (15, 11, 5)),
                     (150, (22, 16, 7)), (95, (30, 22, 10))):
            pygame.draw.circle(g, c, (R, R), r)
        self._glow = g
        v = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        for i in range(9):
            pygame.draw.rect(v, (0, 0, 0, 7),
                             (i * 7, i * 7, WIDTH - i * 14, HEIGHT - i * 14), 7)
        self._vignette = v

    def render(self, surf):
        if self._vignette is None:
            self._build_light()
        if self.state == "MENU":
            self.render_menu(surf)
            return
        t = self.anim_t
        cx, cy = self.camera()
        x0, y0 = int(cx // TILE), int(cy // TILE)
        x1, y1 = x0 + WIDTH // TILE + 2, y0 + HEIGHT // TILE + 2
        for ty in range(max(0, y0), min(MAP_H, y1)):
            for tx in range(max(0, x0), min(MAP_W, x1)):
                i = ty * MAP_W + tx
                tl = self.map[i]
                rx, ry = tx * TILE - cx, ty * TILE - cy
                surf.blit(self.tile_surfs[tl][self.variants[i]], (rx, ry))
                if tl == ROAD and self.road_line[i]:
                    if self.road_line[i] == 1:
                        for yy in range(0, TILE, 10):
                            pygame.draw.line(surf, (190, 170, 90),
                                             (rx + 16, ry + yy),
                                             (rx + 16, ry + yy + 5), 2)
                    else:
                        for xx in range(0, TILE, 10):
                            pygame.draw.line(surf, (190, 170, 90),
                                             (rx + xx, ry + 16),
                                             (rx + xx + 5, ry + 16), 2)
                elif tl == WATER:
                    off = math.sin(t * 2 + tx * 0.8 + ty) * 3
                    pygame.draw.line(surf, (110, 150, 210),
                                     (rx + 5, ry + 10 + off),
                                     (rx + 16, ry + 10 + off), 1)
                    pygame.draw.line(surf, (110, 150, 210),
                                     (rx + 14, ry + 22 - off),
                                     (rx + 26, ry + 22 - off), 1)
        # 血迹
        for dx_, dy_, r_ in self.decals:
            rx, ry = dx_ - cx, dy_ - cy
            if -16 < rx < WIDTH + 16 and -16 < ry < HEIGHT + 16:
                pygame.draw.circle(surf, (118, 22, 22), (int(rx), int(ry)), r_)
                pygame.draw.circle(surf, (90, 14, 14),
                                   (int(rx + 3), int(ry + 2)), max(2, r_ - 3))
        # 容器（木箱）
        for c in self.containers:
            rx, ry = c["x"] * TILE - cx, c["y"] * TILE - cy
            if -32 < rx < WIDTH and -32 < ry < HEIGHT:
                col = (105, 100, 92) if c["looted"] else (152, 104, 48)
                dark = (70, 66, 60) if c["looted"] else (102, 68, 30)
                pygame.draw.rect(surf, dark, (rx + 7, ry + 9, 18, 16))
                pygame.draw.rect(surf, col, (rx + 7, ry + 7, 18, 16))
                pygame.draw.line(surf, dark, (rx + 7, ry + 15),
                                 (rx + 25, ry + 15), 1)
                pygame.draw.rect(surf, dark, (rx + 7, ry + 7, 18, 16), 1)
                if not c["looted"]:
                    pygame.draw.rect(surf, (180, 132, 66),
                                     (rx + 14, ry + 7, 4, 16))
        # 僵尸
        for z in self.zombies:
            rx, ry = z.x - cx, z.y - cy
            if -32 < rx < WIDTH + 32 and -32 < ry < HEIGHT + 32:
                chasing = math.hypot(z.x - self.player["x"],
                                     z.y - self.player["y"]) < 240
                draw_actor(surf, rx, ry, z.ang, z.col, (148, 172, 122),
                           t, z.phase, walking=True, zombie=True)
                if chasing:
                    pygame.draw.circle(surf, (200, 60, 60),
                                       (int(rx), int(ry - 18)), 2)
        # 玩家
        p = self.player
        draw_actor(surf, p["x"] - cx, p["y"] - cy, p["facing"],
                   (74, 104, 142), (228, 198, 168), t, 0.0,
                   walking=self.moving, zombie=False, weapon=p["weapon"])
        if self.swing_t > 0:
            rx, ry = p["x"] - cx, p["y"] - cy
            a = 1 - self.swing_t / 0.15
            arc_s = pygame.Surface((90, 90), pygame.SRCALPHA)
            pygame.draw.arc(arc_s, (245, 240, 200, max(0, int(220 * (1 - a)))),
                            (15, 15, 60, 60),
                            -p["facing"] - 1.1, -p["facing"] + 1.1, 4)
            surf.blit(arc_s, (rx - 45, ry - 45))
        # 粒子
        for pt in self.particles:
            pygame.draw.circle(surf, pt[5],
                               (int(pt[0] - cx), int(pt[1] - cy)), 3)
        # 黑夜 + 玩家光照
        dk = darkness(self.minutes)
        if dk > 0.02:
            ov = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
            ov.fill((5, 5, 30, 255))
            psx, psy = p["x"] - cx, p["y"] - cy
            ov.blit(self._light, (psx - 300, psy - 300),
                    special_flags=pygame.BLEND_RGBA_MIN)
            ov.set_alpha(int(dk * 255))
            surf.blit(ov, (0, 0))
            if dk > 0.5:
                surf.blit(self._glow, (psx - 300, psy - 300),
                          special_flags=pygame.BLEND_RGB_ADD)
        surf.blit(self._vignette, (0, 0))
        self.render_hud(surf)
        if self.state == "JOURNAL":
            self.render_journal(surf)
        elif self.state == "DEAD":
            self.render_dead(surf)

    def draw_text(self, surf, text, x, y, size=16, color=(230, 230, 230),
                  center=False):
        img = get_font(size).render(text, True, color)
        r = img.get_rect()
        if center:
            r.center = (x, y)
        else:
            r.topleft = (x, y)
        surf.blit(img, r)

    def render_hud(self, surf):
        p = self.player
        panel = pygame.Surface((196, 104), pygame.SRCALPHA)
        pygame.draw.rect(panel, (14, 14, 18, 170), (0, 0, 196, 104),
                         border_radius=8)
        pygame.draw.rect(panel, (70, 70, 80, 200), (0, 0, 196, 104), 1,
                         border_radius=8)
        surf.blit(panel, (8, 8))
        is_night = darkness(self.minutes) > 0.2
        ic = (120, 130, 190) if is_night else (240, 200, 80)
        pygame.draw.circle(surf, ic, (24, 24), 6)
        if is_night:
            pygame.draw.circle(surf, (24, 24, 30), (27, 22), 5)
        self.draw_text(surf, f"第 {self.day} 天  {self.clock()}", 38, 14, 17)
        bars = [("生命", p["hp"], (205, 70, 70)),
                ("饱食", p["hunger"], (215, 145, 55)),
                ("水分", p["thirst"], (75, 135, 215)),
                ("精力", p["fatigue"], (95, 185, 95))]
        for i, (label, v, col) in enumerate(bars):
            y = 40 + i * 17
            self.draw_text(surf, label, 16, y, 13)
            pygame.draw.rect(surf, (42, 42, 48), (56, y + 2, 132, 11),
                             border_radius=5)
            if v > 0:
                pygame.draw.rect(surf, col, (56, y + 2,
                                             max(4, int(132 * v / 100)), 11),
                                 border_radius=5)
            pygame.draw.rect(surf, (80, 80, 90), (56, y + 2, 132, 11), 1,
                             border_radius=5)
        inv_panel = pygame.Surface((486, 32), pygame.SRCALPHA)
        pygame.draw.rect(inv_panel, (14, 14, 18, 170), (0, 0, 486, 32),
                         border_radius=8)
        pygame.draw.rect(inv_panel, (70, 70, 80, 200), (0, 0, 486, 32), 1,
                         border_radius=8)
        surf.blit(inv_panel, (8, HEIGHT - 40))
        wname = WEAPONS[p["weapon"]][0]
        slots = [(f"武器·{wname}", (210, 190, 150)),
                 (f"罐头×{self.inv['food']} [1]", (215, 145, 55)),
                 (f"水×{self.inv['water']} [2]", (95, 155, 225)),
                 (f"绷带×{self.inv['bandage']} [3]", (225, 120, 120))]
        sx = 20
        for text, col in slots:
            self.draw_text(surf, text, sx, HEIGHT - 33, 14, col)
            sx += get_font(14).size(text)[0] + 18
        self.draw_text(surf, f"击杀 {self.stats['kills']}", WIDTH - 92, 12, 14,
                       (225, 130, 130))
        mm = pygame.transform.scale(self.minimap, (120, 120))
        surf.blit(mm, (WIDTH - 132, 32))
        pygame.draw.rect(surf, (200, 200, 200), (WIDTH - 132, 32, 120, 120), 1)
        cx, cy = self.camera()
        vx = WIDTH - 132 + cx / (MAP_W * TILE) * 120
        vy = 32 + cy / (MAP_H * TILE) * 120
        pygame.draw.rect(surf, (255, 255, 255),
                         (vx, vy, WIDTH / (MAP_W * TILE) * 120,
                          HEIGHT / (MAP_H * TILE) * 120), 1)
        pxx = WIDTH - 132 + p["x"] / (MAP_W * TILE) * 120
        pyy = 32 + p["y"] / (MAP_H * TILE) * 120
        pygame.draw.circle(surf, (255, 80, 80), (int(pxx), int(pyy)), 2)
        for i, m in enumerate(self.msgs[-4:]):
            a = min(1.0, m[1])
            col = (int(255 * a), int(240 * a), int(180 * a))
            self.draw_text(surf, m[0], WIDTH // 2, 30 + i * 22, 16, col,
                           center=True)

    def render_menu(self, surf):
        surf.fill((16, 19, 16))
        rng = random.Random(7)
        for _ in range(26):
            x, y = rng.randrange(WIDTH), rng.randrange(HEIGHT)
            r = rng.randint(18, 46)
            pygame.draw.circle(surf, (22, 30, 22), (x, y), r)
        surf.blit(self._vignette, (0, 0))
        self.draw_text(surf, "末日生存日志", WIDTH // 2, 150, 56,
                       (222, 212, 190), center=True)
        pygame.draw.line(surf, (150, 40, 40), (WIDTH // 2 - 130, 185),
                         (WIDTH // 2 + 130, 185), 2)
        self.draw_text(surf, "D E A D   D A Y S", WIDTH // 2, 206, 18,
                       (150, 120, 110), center=True)
        self.draw_text(surf, "N — 新的求生", WIDTH // 2, 300, 22,
                       (205, 225, 205), center=True)
        if self.has_save:
            self.draw_text(surf, "C — 继续（读取存档）", WIDTH // 2, 340, 22,
                           (205, 225, 205), center=True)
        ctrl = ("WASD 移动 · Shift 奔跑 · 空格 攻击 · E 搜刮/喝水 · "
                "1/2/3 吃/喝/包扎 · T 睡觉 · J 日志 · Esc 存档退出")
        self.draw_text(surf, ctrl, WIDTH // 2, 430, 15, (150, 150, 140),
                       center=True)
        self.draw_text(surf, "活下去。然后把每一天写下来。",
                       WIDTH // 2, 462, 15, (172, 152, 132), center=True)
        self.draw_text(surf, "v0.2 画面重制版", WIDTH - 100, HEIGHT - 24, 12,
                       (90, 90, 85))

    def render_dead(self, surf):
        ov = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        ov.fill((22, 2, 2, 185))
        surf.blit(ov, (0, 0))
        surf.blit(self._vignette, (0, 0))
        s = self.stats
        self.draw_text(surf, "你死了", WIDTH // 2, 180, 52, (232, 92, 92),
                       center=True)
        pygame.draw.line(surf, (120, 30, 30), (WIDTH // 2 - 70, 220),
                         (WIDTH // 2 + 70, 220), 2)
        self.draw_text(surf, f"存活 {self.day} 天 · 击杀 {s['kills']} · "
                             f"搜刮 {s['searches']} 处 · 日志 {len(self.journal)} 条",
                       WIDTH // 2, 252, 20, (222, 202, 202), center=True)
        self.draw_text(surf, "F5 — 导出生存日志（Markdown）    R — 重新开始",
                       WIDTH // 2, 330, 20, (202, 222, 202), center=True)
        self.draw_text(surf, "—— 日志的最后几页 ——", WIDTH // 2, 396, 15,
                       (182, 162, 162), center=True)
        for i, e in enumerate(self.journal[-3:]):
            line = f"第{e['day']}天 {e['time']} · {e['text'][:34]}"
            self.draw_text(surf, line, WIDTH // 2, 422 + i * 20, 13,
                           (162, 142, 142), center=True)

    def render_journal(self, surf):
        ov = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        ov.fill((8, 8, 6, 210))
        surf.blit(ov, (0, 0))
        px, py, pw, ph = 120, 50, WIDTH - 240, HEIGHT - 150
        pygame.draw.rect(surf, (98, 82, 58), (px - 6, py - 6, pw + 12, ph + 12),
                         border_radius=4)
        pygame.draw.rect(surf, (237, 229, 207), (px, py, pw, ph),
                         border_radius=2)
        for ly in range(py + 70, py + ph - 60, 21):
            pygame.draw.line(surf, (205, 196, 172), (px + 24, ly),
                             (px + pw - 24, ly), 1)
        pygame.draw.line(surf, (200, 120, 110), (px + 22, py + 8),
                         (px + 22, py + ph - 8), 1)
        self.draw_text(surf, f"生存日志 —— 第 {self.day} 天",
                       px + 34, py + 14, 22, (62, 46, 30))
        self.draw_text(surf, "J/Esc 合上 · Enter 写下 · ←/→ 心情 · F5 导出 · 滚轮翻页",
                       px + 34, py + 44, 13, (128, 108, 84))
        font = get_font(15)
        lines = []
        for e in self.journal:
            mc = MOOD_COLORS.get(e["mood"], (110, 70, 40))
            head_col = tuple(int(c * 0.55) for c in mc)
            head = f"第{e['day']}天 {e['time']} · {e['mood']}" \
                   + ("" if e["auto"] else " ✎")
            lines.append((head, head_col))
            for ln in wrap_text(e["text"], font, pw - 80):
                lines.append((ln, (56, 44, 32)))
            lines.append(("", (0, 0, 0)))
        line_h = 21
        view_h = ph - 130
        max_scroll = max(0, len(lines) * line_h - view_h)
        self.journal_scroll = clamp(self.journal_scroll, 0, max_scroll)
        start = int(self.journal_scroll // line_h)
        y = py + 70 - (self.journal_scroll % line_h)
        clip = surf.get_clip()
        surf.set_clip((px + 10, py + 66, pw - 20, view_h))
        for ln, col in lines[start:]:
            if y > py + 66 + view_h:
                break
            if ln:
                self.draw_text(surf, ln, px + 36, int(y), 15, col)
            y += line_h
        surf.set_clip(clip)
        iy = py + ph - 52
        pygame.draw.rect(surf, (250, 245, 226), (px + 28, iy, pw - 56, 40),
                         border_radius=4)
        pygame.draw.rect(surf, (152, 132, 102), (px + 28, iy, pw - 56, 40), 2,
                         border_radius=4)
        mood = MOODS[self.journal_mood]
        hint = self.journal_input if self.journal_input else "写下今天想说的话……"
        self.draw_text(surf, hint, px + 40, iy + 10, 16,
                       (52, 42, 32) if self.journal_input else (162, 152, 132))
        mc = MOOD_COLORS[mood]
        pygame.draw.rect(surf, mc, (px + pw - 140, iy + 8, 96, 24),
                         border_radius=12)
        self.draw_text(surf, f"心情:{mood}", px + pw - 92, iy + 13, 13,
                       (42, 36, 30), center=True)

# ---------------------------------------------------------------- 自检

def selftest():
    g = Game()
    screen = pygame.Surface((WIDTH, HEIGHT))
    dt = 1 / 60
    g.new_game()
    assert g.walkable(g.player["x"], g.player["y"]), "spawn not walkable"

    x0 = g.player["x"]
    for _ in range(120):
        g.update(dt, {pygame.K_d})
    assert g.player["x"] > x0, "move failed"

    c = g.containers[0]
    g.player["x"], g.player["y"] = c["x"] * TILE + 16, c["y"] * TILE + 16
    g.interact()
    assert c["looted"], "container not looted"

    g.player["facing"] = 0
    z = Zombie(g.player["x"] + 30, g.player["y"])
    z.hp = 20
    g.zombies.append(z)
    for _ in range(40):
        g.atk_cd = 0
        g.try_attack()
        g.update(dt, set())
        if not g.zombies:
            break
    assert g.stats["kills"] >= 1, "kill failed"

    hp0 = g.player["hp"]
    g.zombies.append(Zombie(g.player["x"] + 10, g.player["y"]))
    for _ in range(150):
        g.update(dt, set())
        if g.player["hp"] < hp0:
            break
    assert g.player["hp"] < hp0, "zombie did not attack"
    g.zombies.clear()

    g.inv["food"] = 2; g.inv["water"] = 2; g.inv["bandage"] = 1
    g.player["hunger"] = 40
    g.use_item("food")
    assert g.player["hunger"] > 60 and g.inv["food"] == 1, "eat failed"

    g.player["fatigue"] = 30
    g.minutes = 1300
    jn = len(g.journal)
    g.do_sleep()
    assert g.player["fatigue"] == 100, "sleep did not restore fatigue"
    assert abs(g.minutes - DAWN) < 1, "did not wake at dawn"
    assert len(g.journal) > jn, "sleep produced no log"

    g.minutes = 1439
    day0 = g.day
    g.advance_minutes(5)
    assert g.day == day0 + 1, "day rollover failed"

    g.journal.append({"day": g.day, "time": g.clock(), "mood": "希望",
                      "text": "自检手写条目。", "auto": False})
    fn = g.export_journal()
    assert os.path.exists(fn), "export missing"

    g.save_game()
    jlen = len(g.journal)
    g2 = Game()
    g2.load_game()
    assert len(g2.journal) == jlen and g2.day == g.day, "save/load mismatch"

    g.player["hp"] = 1
    g.die("自检")
    assert g.state == "DEAD", "death state wrong"
    assert "终章" in g.journal[-1]["text"], "no final entry"

    # 渲染冒烟（白天+黑夜+全部界面）
    for mins in (600, 1320):
        g.minutes = mins
        for st in ("PLAY", "JOURNAL", "DEAD"):
            g.state = st
            g.render(screen)
    g.state = "MENU"
    g.render(screen)

    print(f"SELFTEST OK | kills={g.stats['kills']} journal={len(g.journal)} "
          f"export={os.path.basename(fn)}")
    return 0

# ---------------------------------------------------------------- 主循环

def main():
    pygame.init()
    if SELFTEST:
        return selftest()
    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption("末日生存日志 · Dead Days")
    pygame.key.start_text_input()
    clock = pygame.time.Clock()
    g = Game()
    running = True
    while running:
        dt = min(clock.tick(60) / 1000, 0.05)
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                if g.state in ("PLAY", "JOURNAL"):
                    g.save_game()
                running = False
            elif ev.type == pygame.KEYDOWN:
                k = ev.key
                if g.state == "MENU":
                    if k == pygame.K_n:
                        g.new_game()
                    elif k == pygame.K_c and g.has_save:
                        g.load_game()
                elif g.state == "PLAY":
                    if k == pygame.K_e:
                        g.interact()
                    elif k == pygame.K_1:
                        g.use_item("food")
                    elif k == pygame.K_2:
                        g.use_item("water")
                    elif k == pygame.K_3:
                        g.use_item("bandage")
                    elif k == pygame.K_t:
                        g.do_sleep()
                    elif k == pygame.K_j:
                        g.state = "JOURNAL"
                        g.journal_scroll = 10 ** 9
                        g.journal_input = ""
                    elif k == pygame.K_ESCAPE:
                        g.save_game()
                        g.state = "MENU"
                elif g.state == "JOURNAL":
                    if k in (pygame.K_j, pygame.K_ESCAPE):
                        g.state = "PLAY"
                    elif k == pygame.K_RETURN:
                        if g.journal_input.strip():
                            g.journal.append({
                                "day": g.day, "time": g.clock(),
                                "mood": MOODS[g.journal_mood],
                                "text": g.journal_input.strip(),
                                "auto": False,
                            })
                            g.journal_input = ""
                            g.journal_scroll = 10 ** 9
                    elif k == pygame.K_BACKSPACE:
                        g.journal_input = g.journal_input[:-1]
                    elif k == pygame.K_LEFT:
                        g.journal_mood = (g.journal_mood - 1) % len(MOODS)
                    elif k == pygame.K_RIGHT:
                        g.journal_mood = (g.journal_mood + 1) % len(MOODS)
                    elif k == pygame.K_F5:
                        g.msg(f"已导出：{os.path.basename(g.export_journal())}")
                elif g.state == "DEAD":
                    if k == pygame.K_r:
                        g.new_game()
                    elif k == pygame.K_F5:
                        g.export_journal()
                        g.msg("日志已导出")
            elif ev.type == pygame.TEXTINPUT and g.state == "JOURNAL":
                if len(g.journal_input) < 80:
                    g.journal_input += ev.text
            elif ev.type == pygame.MOUSEWHEEL and g.state == "JOURNAL":
                g.journal_scroll -= ev.y * 60
        if g.state == "PLAY":
            pressed = {i for i, v in enumerate(pygame.key.get_pressed()) if v}
            g.update(dt, pressed)
        g.render(screen)
        pygame.display.flip()
    pygame.quit()
    return 0

if __name__ == "__main__":
    sys.exit(main())
