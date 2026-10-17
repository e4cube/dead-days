# -*- coding: utf-8 -*-
"""
末日生存日志 · Dead Days
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
import datetime

# selftest 必须在 pygame.init 之前设置 dummy 驱动
SELFTEST = "--selftest" in sys.argv
if SELFTEST:
    os.environ["SDL_VIDEODRIVER"] = "dummy"
    os.environ["SDL_AUDIODRIVER"] = "dummy"

import pygame

WIDTH, HEIGHT = 960, 600
TILE = 32
MAP_W, MAP_H = 120, 120
DAY_LEN = 360.0          # 现实秒 / 游戏一天
DAWN = 360.0             # 06:00 = 360 分钟

GRASS, ROAD, WALL, FLOOR, DOOR, TREE, WATER = range(7)
WALKABLE = {GRASS, ROAD, FLOOR, DOOR}

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SAVE_FILE = os.path.join(BASE_DIR, "save.json")
EXPORT_DIR = os.path.join(BASE_DIR, "exports")

WEAPONS = [("拳头", 12), ("棒球棍", 30), ("砍刀", 45)]
MOODS = ["平静", "疲惫", "恐惧", "希望", "绝望"]
MOOD_COLORS = {
    "平静": (180, 200, 180), "疲惫": (200, 180, 120),
    "恐惧": (220, 130, 130), "希望": (130, 200, 230), "绝望": (150, 120, 160),
}
TILE_COLORS = {
    GRASS: (86, 125, 70), ROAD: (72, 72, 78), WALL: (112, 82, 54),
    FLOOR: (152, 132, 102), DOOR: (92, 62, 32), TREE: (50, 95, 50),
    WATER: (62, 92, 165),
}

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

    # 道路网
    for r in (25, 65, 105):
        for i in range(MAP_W):
            for d in (-1, 0, 1):
                set_t(r + d, i, ROAD)
                set_t(i, r + d, ROAD)

    # 房屋
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
        # 门
        side = rng.randrange(4)
        if side == 0:   dx, dy = rng.randint(x + 1, x + w - 2), y
        elif side == 1: dx, dy = rng.randint(x + 1, x + w - 2), y + h - 1
        elif side == 2: dx, dy = x, rng.randint(y + 1, y + h - 2)
        else:           dx, dy = x + w - 1, rng.randint(y + 1, y + h - 2)
        set_t(dx, dy, DOOR)
        # 容器
        for _ in range(rng.randint(1, 3)):
            cx = rng.randint(x + 1, x + w - 2)
            cy = rng.randint(y + 1, y + h - 2)
            containers.append({"x": cx, "y": cy, "looted": False})
        houses.append((x, y, w, h))

    # 湖
    lx, ly = rng.randint(15, MAP_W - 15), rng.randint(15, MAP_H - 15)
    for yy in range(ly - 8, ly + 9):
        for xx in range(lx - 8, lx + 9):
            if (xx - lx) ** 2 / 64 + (yy - ly) ** 2 / 49 <= 1 and get_t(xx, yy) == GRASS:
                set_t(xx, yy, WATER)

    # 树
    n = 0
    while n < 380:
        x, y = rng.randrange(MAP_W), rng.randrange(MAP_H)
        if get_t(x, y) == GRASS:
            set_t(x, y, TREE); n += 1

    return m, houses, containers

# ---------------------------------------------------------------- 僵尸

class Zombie:
    __slots__ = ("x", "y", "hp", "speed", "ang", "retarget", "atk_cd")
    def __init__(self, x, y, rng=None):
        r = rng or random
        self.x, self.y = x, y
        self.hp = r.randint(40, 70)
        self.speed = r.uniform(34, 58)
        self.ang = r.uniform(0, math.tau)
        self.retarget = r.uniform(1, 4)
        self.atk_cd = 0.0

# ---------------------------------------------------------------- 游戏主体

class Game:
    def __init__(self):
        self.state = "MENU"
        self.zombies = []
        self.msgs = []          # (text, ttl)
        self.particles = []     # [x,y,vx,vy,ttl,color]
        self.journal_scroll = 0
        self.journal_input = ""
        self.journal_mood = 0
        self.has_save = os.path.exists(SAVE_FILE)
        self.minimap = None

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
        self.atk_cd = 0.0
        self.hurt_cd = 0.0
        self.injury_log_cd = 0.0
        self.lowhp_log_cd = 0.0
        self.spawn_t = 0.0
        self.shake = 0.0
        self.swing_t = 0.0
        self.first_zombie_seen = False
        self.dusk_logged_day = 0
        self.state = "PLAY"
        self.add_log("第1天。醒来的时候，城里已经全是它们了。收音机里只剩杂音。"
                     "我得活下去——把这本子写满，写到有人找到它的那天。", "恐惧")

    def _init_world(self):
        self.map, self.houses, self.containers = gen_world(self.seed)
        self.minimap = pygame.Surface((MAP_W, MAP_H))
        for y in range(MAP_H):
            for x in range(MAP_W):
                self.minimap.set_at((x, y), TILE_COLORS[self.map[y * MAP_W + x]])

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
        self.atk_cd = self.hurt_cd = 0.0
        self.injury_log_cd = self.lowhp_log_cd = 0.0
        self.spawn_t = 0.0
        self.shake = self.swing_t = 0.0
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
            if z.hp <= 0:
                self.zombies.remove(z)
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
        # 喝湖水
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
        self.advance_minutes(dt * 1440 / DAY_LEN)

        # ---- 移动 ----
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

        if pygame.K_SPACE in pressed:
            self.try_attack()

        # ---- 需求 ----
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

        # ---- 黄昏提示 ----
        if 1170 <= self.minutes < 1200 and self.dusk_logged_day != self.day:
            self.dusk_logged_day = self.day
            self.add_log("天黑了。远处又响起那种声音。今晚也得睁着一只眼睡。", "恐惧")

        # ---- 冷却 ----
        self.atk_cd = max(0, self.atk_cd - dt)
        self.hurt_cd = max(0, self.hurt_cd - dt)
        self.injury_log_cd = max(0, self.injury_log_cd - dt)
        self.lowhp_log_cd = max(0, self.lowhp_log_cd - dt)
        self.swing_t = max(0, self.swing_t - dt)
        self.shake = max(0, self.shake - dt * 20)

        # ---- 补员 ----
        self.spawn_t -= dt
        target = min(10 + self.day * 2, 48)
        if self.spawn_t <= 0 and len(self.zombies) < target:
            self.spawn_t = 1.5
            self.spawn_zombie()

        # ---- 僵尸 ----
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
        # 分离
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

        # ---- 粒子/消息 ----
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

    def render(self, surf):
        if self.state == "MENU":
            self.render_menu(surf)
            return
        cx, cy = self.camera()
        x0, y0 = int(cx // TILE), int(cy // TILE)
        x1, y1 = x0 + WIDTH // TILE + 2, y0 + HEIGHT // TILE + 2
        for ty in range(max(0, y0), min(MAP_H, y1)):
            for tx in range(max(0, x0), min(MAP_W, x1)):
                t = self.map[ty * MAP_W + tx]
                rx, ry = tx * TILE - cx, ty * TILE - cy
                pygame.draw.rect(surf, TILE_COLORS[t], (rx, ry, TILE, TILE))
                if t == TREE:
                    pygame.draw.circle(surf, (34, 72, 34),
                                       (int(rx + 16), int(ry + 14)), 11)
        for c in self.containers:
            rx, ry = c["x"] * TILE - cx, c["y"] * TILE - cy
            if -32 < rx < WIDTH and -32 < ry < HEIGHT:
                col = (110, 110, 110) if c["looted"] else (150, 100, 45)
                pygame.draw.rect(surf, col, (rx + 8, ry + 8, 16, 16))
                pygame.draw.rect(surf, (60, 40, 20), (rx + 8, ry + 8, 16, 16), 1)
        p = self.player
        for z in self.zombies:
            rx, ry = z.x - cx, z.y - cy
            if -32 < rx < WIDTH + 32 and -32 < ry < HEIGHT + 32:
                pygame.draw.circle(surf, (58, 108, 58), (int(rx), int(ry)), 11)
                pygame.draw.circle(surf, (30, 60, 30), (int(rx), int(ry)), 11, 2)
                ex = math.cos(z.ang) * 5; ey = math.sin(z.ang) * 5
                pygame.draw.circle(surf, (200, 60, 60),
                                   (int(rx + ex), int(ry + ey)), 2)
        # 玩家
        rx, ry = p["x"] - cx, p["y"] - cy
        pygame.draw.circle(surf, (225, 220, 205), (int(rx), int(ry)), 10)
        pygame.draw.circle(surf, (90, 90, 80), (int(rx), int(ry)), 10, 2)
        fx, fy = math.cos(p["facing"]), math.sin(p["facing"])
        pygame.draw.line(surf, (90, 90, 80), (rx, ry),
                         (rx + fx * 14, ry + fy * 14), 3)
        if self.swing_t > 0:
            pygame.draw.arc(surf, (240, 240, 200),
                            (rx - 30, ry - 30, 60, 60),
                            -p["facing"] - 1.0, -p["facing"] + 1.0, 3)
        for pt in self.particles:
            pygame.draw.circle(surf, pt[5],
                               (int(pt[0] - cx), int(pt[1] - cy)), 3)
        # 黑夜
        dk = darkness(self.minutes)
        if dk > 0:
            ov = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
            ov.fill((5, 5, 30, int(dk * 255)))
            surf.blit(ov, (0, 0))
        self.render_hud(surf)
        if self.state == "JOURNAL":
            self.render_journal(surf)
        elif self.state == "DEAD":
            self.render_dead(surf)

    def draw_text(self, surf, text, x, y, size=16, color=(230, 230, 230),
                  center=False):
        img = get_font(size).render(text, True, color)
        r = img.get_rect()
        r.center = (x, y) if center else r.center
        if not center:
            r.topleft = (x, y)
        surf.blit(img, r)

    def render_hud(self, surf):
        p = self.player
        pygame.draw.rect(surf, (0, 0, 0, 120), (8, 8, 190, 96))
        self.draw_text(surf, f"第 {self.day} 天  {self.clock()}", 16, 14, 18)
        bars = [("生命", p["hp"], (200, 60, 60)), ("饱食", p["hunger"], (210, 140, 50)),
                ("水分", p["thirst"], (70, 130, 210)), ("精力", p["fatigue"], (90, 180, 90))]
        for i, (label, v, col) in enumerate(bars):
            y = 38 + i * 17
            self.draw_text(surf, label, 16, y, 13)
            pygame.draw.rect(surf, (50, 50, 50), (56, y + 2, 130, 10))
            pygame.draw.rect(surf, col, (56, y + 2, int(130 * v / 100), 10))
        # 物品栏
        wname = WEAPONS[p["weapon"]][0]
        info = f"武器:{wname}  罐头×{self.inv['food']}[1]  水×{self.inv['water']}[2]  绷带×{self.inv['bandage']}[3]"
        pygame.draw.rect(surf, (0, 0, 0, 120), (8, HEIGHT - 32, 470, 26))
        self.draw_text(surf, info, 16, HEIGHT - 28, 15)
        # 击杀
        self.draw_text(surf, f"击杀 {self.stats['kills']}", WIDTH - 90, 14, 15,
                       (220, 120, 120))
        # 小地图
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
        # 提示消息
        for i, m in enumerate(self.msgs[-4:]):
            self.draw_text(surf, m[0], WIDTH // 2, 30 + i * 22, 16,
                           (255, 240, 180), center=True)

    def render_menu(self, surf):
        surf.fill((18, 22, 18))
        self.draw_text(surf, "末日生存日志", WIDTH // 2, 150, 56,
                       (220, 210, 190), center=True)
        self.draw_text(surf, "DEAD DAYS", WIDTH // 2, 200, 20,
                       (140, 130, 120), center=True)
        self.draw_text(surf, "N — 新的求生", WIDTH // 2, 300, 22,
                       (200, 220, 200), center=True)
        if self.has_save:
            self.draw_text(surf, "C — 继续（读取存档）", WIDTH // 2, 340, 22,
                           (200, 220, 200), center=True)
        ctrl = ("WASD 移动 · Shift 奔跑 · 空格 攻击 · E 搜刮/喝水 · "
                "1/2/3 吃/喝/包扎 · T 睡觉 · J 日志 · Esc 存档退出")
        self.draw_text(surf, ctrl, WIDTH // 2, 430, 15, (150, 150, 140),
                       center=True)
        self.draw_text(surf, "活下去。然后把每一天写下来。",
                       WIDTH // 2, 470, 15, (170, 150, 130), center=True)

    def render_dead(self, surf):
        ov = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        ov.fill((20, 0, 0, 180))
        surf.blit(ov, (0, 0))
        s = self.stats
        self.draw_text(surf, "你死了", WIDTH // 2, 180, 52, (230, 90, 90),
                       center=True)
        self.draw_text(surf, f"存活 {self.day} 天 · 击杀 {s['kills']} · "
                             f"搜刮 {s['searches']} 处 · 日志 {len(self.journal)} 条",
                       WIDTH // 2, 250, 20, (220, 200, 200), center=True)
        self.draw_text(surf, "F5 — 导出生存日志（Markdown）    R — 重新开始",
                       WIDTH // 2, 330, 20, (200, 220, 200), center=True)
        self.draw_text(surf, "日志的最后几页：", WIDTH // 2, 400, 15,
                       (180, 160, 160), center=True)
        for i, e in enumerate(self.journal[-3:]):
            line = f"第{e['day']}天 {e['time']} · {e['text'][:34]}"
            self.draw_text(surf, line, WIDTH // 2, 425 + i * 20, 13,
                           (160, 140, 140), center=True)

    def render_journal(self, surf):
        ov = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        ov.fill((10, 10, 8, 225))
        surf.blit(ov, (0, 0))
        px, py, pw, ph = 120, 50, WIDTH - 240, HEIGHT - 150
        pygame.draw.rect(surf, (235, 228, 205), (px, py, pw, ph))
        pygame.draw.rect(surf, (120, 100, 70), (px, py, pw, ph), 3)
        self.draw_text(surf, f"生存日志 —— 第 {self.day} 天",
                       px + 20, py + 14, 22, (60, 45, 30))
        self.draw_text(surf, "J/Esc 合上 · Enter 写下 · ←/→ 心情 · F5 导出 · 滚轮翻页",
                       px + 20, py + 44, 13, (120, 100, 80))
        font = get_font(15)
        # 组装行
        lines = []
        for e in self.journal:
            head = f"第{e['day']}天 {e['time']} · {e['mood']}" \
                   + ("" if e["auto"] else " ✎")
            lines.append((head, (110, 70, 40), True))
            for ln in wrap_text(e["text"], font, pw - 60):
                lines.append((ln, (50, 40, 30), False))
            lines.append(("", (0, 0, 0), False))
        line_h = 21
        view_h = ph - 130
        max_scroll = max(0, len(lines) * line_h - view_h)
        self.journal_scroll = clamp(self.journal_scroll, 0, max_scroll)
        if self.journal_scroll < 0:
            self.journal_scroll = 0
        start = int(self.journal_scroll // line_h)
        y = py + 70 - (self.journal_scroll % line_h)
        clip = surf.get_clip()
        surf.set_clip((px + 10, py + 66, pw - 20, view_h))
        for ln, col, bold in lines[start:]:
            if y > py + 66 + view_h:
                break
            if ln:
                self.draw_text(surf, ln, px + 30, int(y), 15,
                               col if not bold else col)
            y += line_h
        surf.set_clip(clip)
        # 输入区
        iy = py + ph - 52
        pygame.draw.rect(surf, (250, 245, 225), (px + 15, iy, pw - 30, 40))
        pygame.draw.rect(surf, (150, 130, 100), (px + 15, iy, pw - 30, 40), 2)
        mood = MOODS[self.journal_mood]
        mc = MOOD_COLORS[mood]
        hint = self.journal_input if self.journal_input else "写下今天想说的话……"
        self.draw_text(surf, hint, px + 25, iy + 10, 16,
                       (50, 40, 30) if self.journal_input else (160, 150, 130))
        pygame.draw.rect(surf, mc, (px + pw - 105, iy + 8, 90, 24))
        self.draw_text(surf, f"心情:{mood}", px + pw - 60, iy + 12, 14,
                       (40, 35, 30), center=True)

# ---------------------------------------------------------------- 自检

def selftest():
    g = Game()
    screen = pygame.Surface((WIDTH, HEIGHT))
    dt = 1 / 60
    g.new_game()
    assert g.walkable(g.player["x"], g.player["y"]), "spawn not walkable"

    # 1. 移动
    x0 = g.player["x"]
    for _ in range(120):
        g.update(dt, {pygame.K_d})
    assert g.player["x"] > x0, "move failed"

    # 2. 搜刮
    c = g.containers[0]
    g.player["x"], g.player["y"] = c["x"] * TILE + 16, c["y"] * TILE + 16
    before = sum(g.inv.values())
    g.interact()
    assert c["looted"], "container not looted"

    # 3. 战斗：贴脸放一只僵尸打它
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

    # 4. 被咬掉血 + 受伤日志
    hp0 = g.player["hp"]
    g.zombies.append(Zombie(g.player["x"] + 10, g.player["y"]))
    jn0 = len(g.journal)
    for _ in range(150):
        g.update(dt, set())
        if g.player["hp"] < hp0:
            break
    assert g.player["hp"] < hp0, "zombie did not attack"
    g.zombies.clear()

    # 5. 物品使用
    g.inv["food"] = 2; g.inv["water"] = 2; g.inv["bandage"] = 1
    g.player["hunger"] = 40
    g.use_item("food")
    assert g.player["hunger"] > 60 and g.inv["food"] == 1, "eat failed"

    # 6. 睡觉到黎明
    g.player["fatigue"] = 30
    g.minutes = 1300  # 21:40
    jn = len(g.journal)
    g.do_sleep()
    assert g.player["fatigue"] == 100, "sleep did not restore fatigue"
    assert abs(g.minutes - DAWN) < 1, "did not wake at dawn"
    assert len(g.journal) > jn, "sleep produced no log"

    # 7. 跨天与黎明日记
    g.minutes = 1439
    day0 = g.day
    g.advance_minutes(5)
    assert g.day == day0 + 1, "day rollover failed"

    # 8. 手写日志 + 导出
    g.journal.append({"day": g.day, "time": g.clock(), "mood": "希望",
                      "text": "自检手写条目。", "auto": False})
    fn = g.export_journal()
    assert os.path.exists(fn), "export missing"

    # 9. 存档/读档往返
    g.save_game()
    jlen = len(g.journal)
    g2 = Game()
    g2.load_game()
    assert len(g2.journal) == jlen and g2.day == g.day, "save/load mismatch"

    # 10. 死亡路径
    g.player["hp"] = 1
    g.die("自检")
    assert g.state == "DEAD", "death state wrong"
    assert "终章" in g.journal[-1]["text"], "no final entry"

    # 11. 渲染冒烟
    for st in ("MENU", "PLAY", "JOURNAL", "DEAD"):
        g.state = st
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
                        g.journal_scroll = 10 ** 9   # 滚到最新
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
