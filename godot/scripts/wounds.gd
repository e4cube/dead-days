extends RefCounted
## Wounds, bleeding and infection. The first real source of permanent death.
##
## Three decisions shape this file:
##
## 1. **Every roll happens once and is written down.** The wound type is decided
##    when the hit lands; whether it festers is decided when the incubation runs
##    out. A reload never re-rolls, so nobody savescums a bite away.
## 2. **Bleeding is immediate, infection is patient.** That is what makes first
##    aid a sequence — stop the blood now, disinfect before the four hours are
##    up, close it if you can — instead of three interchangeable buttons.
## 3. **No body parts.** A top-down game has no limb targeting; writing "left
##    forearm" here would be false precision. Severity and type carry the stakes.
const KINDS := ["scratch", "laceration", "bite"]
## Everything that is consumed by the first-aid sequence, in the order a player
## would actually reach for it.
const MEDICAL := ["bandage", "antiseptic", "suture_kit", "antibiotic"]

static func is_medical(id: String) -> bool:
    return MEDICAL.has(id)

static func table(model) -> Dictionary:
    var value: Variant = model.rules.get("wounds")
    return value if value is Dictionary else {}

static func kind_rule(model, kind: String) -> Dictionary:
    var kinds: Dictionary = table(model).get("kinds", {})
    var entry: Variant = kinds.get(kind)
    return entry if entry is Dictionary else {}

static func kind_name(model, kind: String) -> String:
    return str(kind_rule(model, kind).get("name", kind))

## Physical damage is not always a wound; a shove against a door should not
## leave a scar. The weights live in rules so the mix can be tuned without code.
static func roll_hit(model) -> String:
    var chances: Dictionary = table(model).get("hit_chance", {})
    var total := 0.0
    for key in chances:
        total += maxf(0.0, float(chances[key]))
    if total <= 0.0:
        return "none"
    ensure(model)
    # A counter for every landed blow, not just every recorded wound: two hits in
    # the same game minute must not roll the same number, or a scratch would
    # repeat itself for as long as the fight lasted.
    var seq := int(model.state.hit_seq) + 1
    model.state.hit_seq = seq
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("hit:%d:%d" % [seq, int(model.state.day)])
    var roll := rng.randf() * total
    for key in chances:
        roll -= maxf(0.0, float(chances[key]))
        if roll <= 0.0:
            return str(key)
    return "none"

static func ensure(model) -> void:
    if not model.state.get("wounds") is Array:
        model.state.wounds = []
    if not (model.state.get("wound_seq") is int or model.state.get("wound_seq") is float):
        model.state.wound_seq = int(model.state.wounds.size())
    if not (model.state.get("hit_seq") is int or model.state.get("hit_seq") is float):
        model.state.hit_seq = 0

static func add_state(model) -> void:
    model.state.wounds = []
    model.state.wound_seq = 0
    model.state.hit_seq = 0
    model.state.schema = 8

static func cap(model) -> int:
    return maxi(1, int(table(model).get("max", 32)))

## Records a wound. Returns the new record, or an empty dictionary when the cap
## is reached — a body can only take so much before the bookkeeping stops
## mattering and the bleeding alone decides it.
static func hit(model, kind: String, attacker: String = "") -> Dictionary:
    ensure(model)
    if not KINDS.has(kind) or model.state.wounds.size() >= cap(model):
        return {}
    var record := {
        "id": int(model.state.wound_seq) + 1,
        "kind": kind,
        "age": 0.0,
        "cleaned": false,
        "sutured": false,
        "dressed": false,
        "judged": false,
        "infected": false,
        "attacker": str(attacker),
    }
    model.state.wound_seq = int(record.id)
    model.state.wounds.append(record)
    var line := "被僵尸撕开一道%s。" % kind_name(model, kind)
    match kind:
        "bite":
            line = "被僵尸咬穿了皮肉。牙印很深，血止不住。"
        "laceration":
            line = "被僵尸的指甲划开一道撕裂伤，皮肉翻着。"
        "scratch":
            line = "被抓出几道抓伤，火辣辣地疼。"
    model.event("wounded", line, "恐惧", {"wound": record.id, "kind": kind, "attacker": str(attacker)})
    return record

## Bleeding per game minute. Dressing slows it, suturing nearly stops it; the
## two multiply, which is what makes doing both worth the supplies.
static func bleed_rate(model, wound: Dictionary) -> float:
    var rate := float(kind_rule(model, str(wound.get("kind", ""))).get("bleed", 0.0))
    if rate <= 0.0:
        return 0.0
    var tuning: Dictionary = table(model)
    if bool(wound.get("dressed", false)):
        rate *= float(tuning.get("dress_factor", 0.18))
    if bool(wound.get("sutured", false)):
        rate *= float(tuning.get("suture_factor", 0.05))
    return rate

static func total_bleed(model) -> float:
    var total := 0.0
    for wound in model.state.get("wounds", []):
        total += bleed_rate(model, wound)
    return total

static func infecting(model) -> bool:
    for wound in model.state.get("wounds", []):
        if bool(wound.get("infected", false)):
            return true
    return false

static func count(model, predicate: String = "") -> int:
    var total := 0
    for wound in model.state.get("wounds", []):
        match predicate:
            "bleeding":
                if bleed_rate(model, wound) > 0.0:
                    total += 1
            "open":
                if not bool(wound.get("dressed", false)):
                    total += 1
            "infected":
                if bool(wound.get("infected", false)):
                    total += 1
            _:
                total += 1
    return total

## Chance that a wound turns bad, given what has been done to it so far.
## Cleaning is the big lever; suturing a dirty wound only helps a little.
static func infection_chance(model, kind: String, cleaned: bool, sutured: bool) -> float:
    var base := float(kind_rule(model, kind).get("infection", 0.0))
    var tuning: Dictionary = table(model)
    if cleaned:
        base *= float(tuning.get("cleaned_factor", 0.30))
    if sutured:
        base *= float(tuning.get("sutured_factor", 0.85))
    return clampf(base, 0.0, 1.0)

## Deterministic from the wound id: the same bite always resolves the same way,
## which is what makes "no reloading your way out of it" true.
static func resolves_infected(model, wound: Dictionary) -> bool:
    var rng := RandomNumberGenerator.new()
    rng.seed = hash("wound:%s:%s" % [str(wound.get("id", 0)), str(wound.get("kind", ""))])
    return rng.randf() < infection_chance(model, str(wound.get("kind", "")),
        bool(wound.get("cleaned", false)), bool(wound.get("sutured", false)))

static func worst(model, mode: String = "") -> Dictionary:
    var best: Dictionary = {}
    var best_rate := 0.0
    for wound in model.state.get("wounds", []):
        var rate := bleed_rate(model, wound)
        var eligible := true
        match mode:
            "dress": eligible = not bool(wound.get("dressed", false)) and rate > 0.0
            "clean": eligible = not bool(wound.get("cleaned", false)) and not bool(wound.get("infected", false))
            "suture": eligible = not bool(wound.get("sutured", false)) and bool(wound.get("cleaned", false)) and not bool(wound.get("infected", false))
            _: eligible = rate > 0.0
        if not eligible:
            continue
        if best.is_empty() or rate > best_rate:
            best = wound
            best_rate = rate
    return best

static func dress(model) -> bool:
    var wound := worst(model, "dress")
    if wound.is_empty():
        return false
    wound.dressed = true
    model.event("wound_dressed", "给%s缠上绷带，血流慢了下来。" % kind_name(model, str(wound.kind)),
        "平静", {"wound": wound.id, "kind": wound.kind})
    return true

static func clean(model) -> bool:
    var wound := worst(model, "clean")
    if wound.is_empty():
        return false
    wound.cleaned = true
    model.event("wound_cleaned", "用酒精冲了冲%s，伤口边缘干净了。" % kind_name(model, str(wound.kind)),
        "希望", {"wound": wound.id, "kind": wound.kind})
    return true

static func suture(model) -> bool:
    var wound := worst(model, "suture")
    if wound.is_empty():
        return false
    wound.sutured = true
    model.event("wound_sutured", "把%s缝上了，血基本止住。" % kind_name(model, str(wound.kind)),
        "希望", {"wound": wound.id, "kind": wound.kind})
    return true

static func cure(model) -> bool:
    var cured := 0
    for wound in model.state.get("wounds", []):
        if bool(wound.get("infected", false)):
            wound.infected = false
            wound.judged = true
            wound.age = 0.0
            cured += 1
    if cured <= 0:
        return false
    model.event("cured", "抗生素压住了感染，身上终于不那么烫了。", "希望", {"wounds": cured})
    return true

## First aid is not a menu of equal options: the order is the medicine.
static func medical_reason(model, id: String) -> String:
    match id:
        "bandage":
            if count(model) <= 0:
                return "身上没有需要包扎的伤口"
            return "" if not worst(model, "dress").is_empty() else "伤口都已经包扎过了"
        "antiseptic":
            if count(model) <= 0:
                return "身上没有需要消毒的伤口"
            if not worst(model, "clean").is_empty():
                return ""
            return "伤口都已经消毒过了" if not infecting(model) else "感染已经发起来了，消毒压不住"
        "suture_kit":
            if count(model) <= 0:
                return "身上没有需要缝合的伤口"
            var wound := worst(model, "suture")
            if not wound.is_empty():
                return ""
            if count(model, "infected") > 0:
                return "感染的伤口不能再缝"
            return "先消毒再缝合"
        "antibiotic":
            return "" if infecting(model) else "没有感染，不用吃抗生素"
    return "不是医疗用品"

static func use_medical(model, id: String) -> bool:
    var blocked := medical_reason(model, id)
    if not blocked.is_empty():
        return false
    var tuning: Dictionary = table(model)
    match id:
        "bandage":
            if not dress(model):
                return false
            model.state.inventory[id] = int(model.state.inventory.get(id, 0)) - 1
            model.state.stats.health = minf(100.0, float(model.state.stats.health) + float(tuning.get("bandage_heal", 8.0)))
            return true
        "antiseptic":
            if not clean(model):
                return false
            model.state.inventory[id] = int(model.state.inventory.get(id, 0)) - 1
            return true
        "suture_kit":
            if not suture(model):
                return false
            model.state.inventory[id] = int(model.state.inventory.get(id, 0)) - 1
            return true
        "antibiotic":
            if not cure(model):
                return false
            model.state.inventory[id] = int(model.state.inventory.get(id, 0)) - 1
            return true
    return false

## Called from the shared clock: every wound ages, bleeds, and either closes or
## turns septic while the player is doing something else.
static func physiology(model, minutes: float) -> void:
    if minutes <= 0.0 or float(model.state.stats.health) <= 0.0:
        return
    var list: Array = model.state.get("wounds", [])
    if list.is_empty():
        return
    var bleeding := 0.0
    var sepsis := 0.0
    var closed: Array = []
    for index in range(list.size()):
        var wound: Dictionary = list[index]
        wound.age = float(wound.get("age", 0.0)) + minutes
        var rule := kind_rule(model, str(wound.kind))
        if not bool(wound.get("judged", false)) and float(wound.age) >= float(rule.get("incubation_minutes", 480)):
            wound.judged = true
            wound.infected = resolves_infected(model, wound)
            if bool(wound.infected):
                model.event("infected", "%s开始发烫、发红，八成是感染了。" % kind_name(model, str(wound.kind)),
                    "绝望", {"wound": wound.id, "kind": wound.kind})
        bleeding += bleed_rate(model, wound)
        if bool(wound.get("infected", false)):
            sepsis += float(table(model).get("infection_damage_per_minute", 0.02))
        elif float(wound.age) >= float(rule.get("heal_minutes", 900)):
            closed.append(index)
    for index in range(closed.size() - 1, -1, -1):
        list.remove_at(int(closed[index]))
    for index in closed:
        model.event("wound_healed", "身上少了一处伤口。", "平静", {"wounds": list.size()})
    if bleeding <= 0.0 and sepsis <= 0.0:
        return
    var damage := (bleeding + sepsis) * minutes
    if damage <= 0.0:
        return
    var before := float(model.state.stats.health)
    model.state.stats.health = maxf(0.0, before - damage)
    if before >= 25.0 and float(model.state.stats.health) < 25.0 and float(model.state.stats.health) > 0.0:
        model.event("near_death", "伤口在流血，视线开始发黑。", "绝望",
            {"cause": "bleeding" if bleeding >= sepsis else "infection"})
    if float(model.state.stats.health) <= 0.0:
        model.event("died", "血从指缝里流干了。" if bleeding >= sepsis else "感染烧穿了最后一点力气。",
            "绝望", {"cause": "bleeding" if bleeding >= sepsis else "infection"})

## HUD 只有一行位置，所以最多列三处，剩下的合并成"等N处"：优先列感染的和
## 还在流血的，因为那才是玩家此刻必须处理的东西。
static func summary(model) -> String:
    var list: Array = model.state.get("wounds", [])
    if list.is_empty():
        return "无伤"
    var ordered: Array = list.duplicate()
    ordered.sort_custom(func(a, b):
        var a_score := (2.0 if bool(a.get("infected", false)) else 0.0) + bleed_rate(model, a)
        var b_score := (2.0 if bool(b.get("infected", false)) else 0.0) + bleed_rate(model, b)
        return a_score > b_score)
    var parts := PackedStringArray()
    for index in mini(ordered.size(), 3):
        var wound: Dictionary = ordered[index]
        var marks := ""
        if bool(wound.get("infected", false)):
            marks = "感染"
        elif bool(wound.get("sutured", false)):
            marks = "已缝合"
        elif bool(wound.get("dressed", false)):
            marks = "已包扎"
        elif bool(wound.get("cleaned", false)):
            marks = "已消毒"
        else:
            marks = "未处理"
        parts.append("%s(%s)" % [kind_name(model, str(wound.kind)), marks])
    if ordered.size() > parts.size():
        parts.append("等%d处" % (ordered.size() - parts.size()))
    var bleeding := total_bleed(model)
    return "%d处：%s%s" % [list.size(), "、".join(parts), " 流血中" if bleeding > 0.0 else ""]

static func valid(model, candidate: Dictionary) -> bool:
    var list: Variant = candidate.get("wounds")
    if not list is Array or list.size() > cap(model):
        return false
    if not (candidate.get("wound_seq") is int or candidate.get("wound_seq") is float):
        return false
    if int(candidate.wound_seq) < 0 or int(candidate.wound_seq) > 1000000:
        return false
    if candidate.has("hit_seq"):
        if not (candidate.hit_seq is int or candidate.hit_seq is float):
            return false
        if int(candidate.hit_seq) < 0 or int(candidate.hit_seq) > 10000000:
            return false
    var seen: Array = []
    for wound in list:
        if not wound is Dictionary:
            return false
        for key in ["id", "kind", "age", "cleaned", "sutured", "dressed", "judged", "infected"]:
            if not wound.has(key):
                return false
        if not KINDS.has(str(wound.kind)):
            return false
        if not (wound.id is int or wound.id is float) or int(wound.id) <= 0 or int(wound.id) > 1000000 or int(wound.id) in seen:
            return false
        seen.append(int(wound.id))
        if not (wound.age is float or wound.age is int) or not is_finite(float(wound.age)) or float(wound.age) < 0.0 or float(wound.age) > 100000.0:
            return false
        for key in ["cleaned", "sutured", "dressed", "judged", "infected"]:
            if not wound[key] is bool:
                return false
        # An infected wound cannot be sutured: the game never produces that state,
        # so a save that claims it is lying.
        if bool(wound.infected) and bool(wound.sutured):
            return false
        if bool(wound.sutured) and not bool(wound.cleaned):
            return false
    return true
