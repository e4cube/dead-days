extends SceneTree
## 伤口、流血与感染。
##
## 这个系统是永死的第一来源，所以测试的重点不是"能掉血"，而是三件事：
## 1. 每一次判定只发生一次并写进存档，读档不能重掷；
## 2. 止血是立刻的，感染是耐心的——顺序错了就治不好；
## 3. 没人处理就会真的死，而且死因写得清楚。
const World = preload("res://scripts/connected_model.gd")
const Wounds = preload("res://scripts/wounds.gd")

var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func fresh():
    var model = World.new()
    model.start()
    model.state.zombies = []
    return model

func _initialize() -> void:
    var model = fresh()
    check(model.state.schema == 8, "a new run starts at schema 8")
    check(model.state.wounds is Array and model.state.wounds.is_empty(), "a new body has no wounds")

    # --- 命中表：每一下都是新的一掷 ---
    var counts := {"none": 0, "scratch": 0, "laceration": 0, "bite": 0}
    var seq := []
    for i in 400:
        var kind: String = Wounds.roll_hit(model)
        if not counts.has(kind):
            counts[kind] = 0
        counts[kind] += 1
        if i < 8:
            seq.append(kind)
    check(counts.scratch > counts.bite, "抓伤比咬伤常见得多")
    check(counts.scratch > counts.laceration, "抓伤是最常见的那一种")
    check(counts.bite > 0, "咬伤会出现，只是稀少")
    check(counts.none > 0, "不是每一拳都留下伤口")
    var distinct := {}
    for kind in seq:
        distinct[kind] = true
    check(distinct.size() >= 2, "连续几下不会永远是同一种结果")
    check(counts.scratch < 400 * 0.65, "抓伤的占比没有失控：%d/400" % counts.scratch)

    # --- 伤口记录 ---
    var record := Wounds.hit(model, "laceration", "z1")
    check(not record.is_empty() and record.kind == "laceration", "记录下撕裂伤")
    check(record.id == 1 and int(model.state.wound_seq) == 1, "第一处伤口拿到 1 号")
    check(record.cleaned == false and record.sutured == false and record.dressed == false, "刚撕开时什么都没做")
    check(record.infected == false and record.judged == false, "感染还没有判定")
    check(Wounds.hit(model, "bruise").is_empty(), "未知伤种被拒绝")
    var second := Wounds.hit(model, "bite", "z2")
    check(second.id == 2, "第二处伤口拿到 2 号")
    check(model.state.wounds.size() == 2, "两处伤口都在身上")

    # --- 流血速度 ---
    model.state.wounds = [{"id": 1, "kind": "laceration", "age": 0.0, "cleaned": false,
        "sutured": false, "dressed": false, "judged": false, "infected": false, "attacker": "z1"}]
    var raw: float = Wounds.total_bleed(model)
    check(raw > 0.0, "未处理的撕裂伤在流血")
    model.state.wounds[0].dressed = true
    var dressed: float = Wounds.total_bleed(model)
    check(dressed < raw and dressed > 0.0, "包扎让血流变慢但没停")
    model.state.wounds[0].sutured = true
    var sutured: float = Wounds.total_bleed(model)
    check(sutured < dressed, "缝合之后基本止住")
    check(sutured > 0.0, "缝合也不是零")
    model.state.wounds[0].infected = true
    model.state.wounds[0].sutured = false
    check(Wounds.summary(model).find("感染") >= 0, "HUD 上写得出感染")

    # --- 医疗顺序 ---
    model = fresh()
    check(Wounds.medical_reason(model, "bandage") == "身上没有需要包扎的伤口", "没伤时绷带不给用")
    check(Wounds.medical_reason(model, "antibiotic") == "没有感染，不用吃抗生素", "没感染时抗生素不给用")
    var wound := Wounds.hit(model, "bite", "z1")
    check(Wounds.medical_reason(model, "bandage").is_empty(), "流血的咬伤可以包扎")
    check(Wounds.medical_reason(model, "suture_kit") == "先消毒再缝合", "没消毒不能缝")
    check(Wounds.medical_reason(model, "antiseptic").is_empty(), "没消毒的伤口可以消毒")
    check(Wounds.clean(model), "消毒成功")
    check(model.state.wounds[0].cleaned, "伤口记下了消毒")
    check(Wounds.medical_reason(model, "suture_kit").is_empty(), "消毒之后才能缝")
    check(Wounds.suture(model), "缝合成功")
    check(Wounds.medical_reason(model, "bandage").is_empty(), "缝完仍然可以包扎")
    check(Wounds.dress(model), "包扎成功")
    check(Wounds.medical_reason(model, "bandage") == "伤口都已经包扎过了", "同一个伤口不能包两次")
    check(Wounds.medical_reason(model, "suture_kit") == "伤口都已经消毒过了" or
        Wounds.worst(model, "suture").is_empty(), "缝过的伤口不再重复缝")
    check(not Wounds.cure(model), "没感染时没有东西可治")

    # --- 感染判定是写下来的，不是每次重掷 ---
    var mirror = fresh()
    var rng_agree := true
    for i in 40:
        var probe := {"id": i + 1, "kind": "bite", "cleaned": false, "sutured": false}
        var a: bool = Wounds.resolves_infected(model, probe)
        var b: bool = Wounds.resolves_infected(mirror, probe)
        if a != b:
            rng_agree = false
    check(rng_agree, "同一处伤在两次结算里结果相同")

    var dirty_bites := 0
    var clean_bites := 0
    for i in 300:
        if Wounds.resolves_infected(model, {"id": i + 1, "kind": "bite", "cleaned": false, "sutured": false}):
            dirty_bites += 1
        if Wounds.resolves_infected(model, {"id": i + 1, "kind": "bite", "cleaned": true, "sutured": false}):
            clean_bites += 1
    check(dirty_bites > 100, "咬伤不处理多半会感染：%d/300" % dirty_bites)
    check(clean_bites < dirty_bites, "消毒显著降低感染率：%d < %d" % [clean_bites, dirty_bites])
    var scratch_dirty := 0
    for i in 300:
        if Wounds.resolves_infected(model, {"id": i + 1, "kind": "scratch", "cleaned": false, "sutured": false}):
            scratch_dirty += 1
    check(scratch_dirty < dirty_bites / 3, "抓伤比咬伤安全得多：%d vs %d" % [scratch_dirty, dirty_bites])

    # --- 生理：不看就会流血死 ---
    model = fresh()
    Wounds.hit(model, "bite", "z1")
    var before: float = model.state.stats.health
    Wounds.physiology(model, 120.0)
    check(model.state.stats.health < before, "两小时不处理，血一直在流")
    check(model.state.stats.health > 0.0, "两小时还死不了")
    check(model.state.wounds[0].age == 120.0, "伤口在变老")

    # 半血的人遇到一处没处理的咬伤，撑不过一夜。
    model = fresh()
    model.state.stats.health = 30.0
    Wounds.hit(model, "bite", "z1")
    var minutes := 0.0
    while model.state.stats.health > 0.0 and minutes < 5000.0:
        Wounds.physiology(model, 60.0)
        minutes += 60.0
    check(model.state.stats.health <= 0.0, "一直不处理真的会死")
    var died := false
    for entry in model.state.events:
        if entry.kind == "died" and str(entry.payload.get("cause", "")) == "bleeding":
            died = true
    check(died, "死因写的是流血")

    # 包扎之后活得下去
    model = fresh()
    Wounds.hit(model, "bite", "z1")
    for i in 12:
        Wounds.hit(model, "scratch", "z1")
    for i in model.state.wounds.size():
        model.state.wounds[i].dressed = true
    model.state.stats.health = 100.0
    Wounds.physiology(model, 600.0)
    check(model.state.stats.health > 60.0, "全都包扎之后十小时不至于垮掉：%.0f" % model.state.stats.health)

    # --- 感染会烧人，抗生素能压住 ---
    model = fresh()
    Wounds.hit(model, "bite", "z1")
    model.state.wounds[0].infected = true
    model.state.wounds[0].judged = true
    model.state.stats.health = 100.0
    Wounds.physiology(model, 300.0)
    check(model.state.stats.health < 100.0, "感染持续消耗生命")
    check(model.state.stats.health > 50.0, "半小时感染还不至于要命")
    check(Wounds.infecting(model), "身上带着感染")
    check(Wounds.medical_reason(model, "antibiotic").is_empty(), "有感染时抗生素可以用")
    check(Wounds.cure(model), "抗生素压住了感染")
    check(not Wounds.infecting(model), "感染消失")
    check(model.state.wounds[0].judged, "治过之后不再重判")
    model.state.stats.health = 100.0
    Wounds.physiology(model, 300.0)
    # 感染停了，血还在流：五小时只该掉 0.04×300 ≈ 12 点，而不是加上脓毒的那份。
    check(100.0 - model.state.stats.health <= 12.5, "治好之后只剩流血，没有感染伤害：%.1f" % (100.0 - model.state.stats.health))

    # 感染的伤口不能再缝
    model = fresh()
    Wounds.hit(model, "laceration", "z1")
    model.state.wounds[0].infected = true
    check(Wounds.medical_reason(model, "suture_kit") == "感染的伤口不能再缝", "感染的伤口不给缝")

    # --- 会自己长好 ---
    model = fresh()
    Wounds.hit(model, "scratch", "z1")
    model.state.wounds[0].dressed = true
    Wounds.physiology(model, float(model.rules.wounds.kinds.scratch.heal_minutes) + 1.0)
    check(model.state.wounds.is_empty(), "抓伤过一段时间自己好了")

    # --- 上限 ---
    model = fresh()
    for i in int(model.rules.wounds.max):
        Wounds.hit(model, "scratch", "z1")
    check(model.state.wounds.size() == int(model.rules.wounds.max), "伤口数量封顶")
    check(Wounds.hit(model, "scratch", "z1").is_empty(), "超过上限不再记账")

    # --- 存档校验 ---
    model = fresh()
    Wounds.hit(model, "scratch", "z1")
    check(model.valid(model.state), "全新存档通过校验")
    var broken: Dictionary = model.state.duplicate(true)
    broken.wounds[0].age = -5.0
    check(not model.valid(broken), "负数年龄的伤口被拒绝")
    broken = model.state.duplicate(true)
    broken.wounds[0].kind = "bruise"
    check(not model.valid(broken), "未知伤种被拒绝")
    broken = model.state.duplicate(true)
    broken.wounds[0].infected = true
    broken.wounds[0].sutured = true
    check(not model.valid(broken), "感染又缝合的状态不存在，拒绝")
    broken = model.state.duplicate(true)
    broken.wounds[0].sutured = true
    broken.wounds[0].cleaned = false
    check(not model.valid(broken), "没消毒就缝合的状态不存在，拒绝")
    broken = model.state.duplicate(true)
    broken.wounds.append(broken.wounds[0].duplicate(true))
    check(not model.valid(broken), "重复 id 的伤口被拒绝")
    broken = model.state.duplicate(true)
    broken.wounds[0].erase("dressed")
    check(not model.valid(broken), "缺字段的伤口被拒绝")

    # --- 旧档迁移 ---
    var old = fresh()
    old.state.erase("wounds")
    old.state.erase("hit_seq")
    old.state.schema = 7
    check(old.valid(old.state), "schema 7 的老存档仍然能读")
    old.restore(old.state)
    check(old.state.schema == 8, "迁移到 schema 8")
    check(old.state.wounds is Array and old.state.wounds.is_empty(), "迁移之后从无伤开始")
    var migrated := false
    for entry in old.state.events:
        if entry.kind == "migrated" and str(entry.text).find("伤势") >= 0:
            migrated = true
    check(migrated, "迁移写进了日志")

    # --- 端到端：只有牙齿和指甲留下伤口 ---
    model = fresh()
    model.state.combat.hurt_cd = 0.0
    model.state.stats.health = 100.0
    model.damage_player(5.0, "environment_fixture")
    check(model.state.wounds.is_empty(), "环境伤害不留下伤口")
    var landed := false
    for i in 60:
        model.state.combat.hurt_cd = 0.0
        model.state.stats.health = 100.0
        model.damage_player(6.0, "z_fixture", true)
        if not model.state.wounds.is_empty():
            landed = true
            break
    check(landed, "僵尸的抓咬会留下伤口")
    check(int(model.state.wound_seq) >= 1, "伤口编号在推进")

    # 使用物品走的是同一套判断
    model = fresh()
    model.state.inventory = {"bandage": 1, "antiseptic": 1}
    check(not model.use_item("bandage"), "没伤口时绷带用不出去")
    check(model.state.inventory.get("bandage", 0) == 1, "没用的绷带不会被扣掉")
    Wounds.hit(model, "laceration", "z1")
    check(model.use_item("antiseptic"), "有伤口时可以消毒")
    check(model.state.inventory.get("antiseptic", 0) == 0, "消毒酒精被消耗")
    check(model.use_item("bandage"), "包扎成功")
    check(model.state.wounds[0].dressed, "伤口记下了包扎")

    print("WOUNDS_OK" if failures == 0 else "WOUNDS_FAILED")
    quit(0 if failures == 0 else 1)
