extends RefCounted
## Time and physiology share game minutes; no real-time timer or random narrative.
static func absolute(model: RefCounted) -> float:
    return (float(model.state.day) - 1.0) * 1440.0 + float(model.state.minutes)

static func clock(model: RefCounted) -> String:
    var minute := int(floor(model.state.minutes + 0.000001)) % 1440
    return "%02d:%02d" % [minute / 60, minute % 60]

static func daylight(model: RefCounted) -> float:
    var minute: float = model.state.minutes
    var rule: Dictionary = model.rules.time
    if minute < rule.dawn or minute >= rule.night_full:
        return 0.0
    if minute < rule.daylight_full:
        return inverse_lerp(rule.dawn, rule.daylight_full, minute)
    if minute < rule.dusk:
        return 1.0
    return 1.0 - inverse_lerp(rule.dusk, rule.night_full, minute)

static func advance(model: RefCounted, seconds: float, sleeping: bool) -> void:
    if seconds <= 0 or model.state.stats.health <= 0:
        return
    var remaining: float = seconds * float(model.rules.time.minutes_per_second)
    while remaining > 0.0000001 and model.state.stats.health > 0:
        var step: float = minf(remaining, 1440.0 - float(model.state.minutes))
        # Bound large direct model calls too; live world simulation uses much smaller steps.
        step = minf(step, 60.0)
        var previous_day := int(model.state.day)
        model.state.minutes += step
        var crossed_midnight: bool = model.state.minutes >= 1440.0 - 0.0000001
        if crossed_midnight:
            model.state.day += 1
            model.state.minutes = 0.0
        # Normalize before emitting physiological events: never write "24:00" into the journal.
        physiology(model, step, sleeping)
        remaining -= step
        if crossed_midnight:
            summarize(model, previous_day)

static func physiology(model: RefCounted, minutes: float, sleeping: bool) -> void:
    var rule: Dictionary = model.rules.survival
    var stats: Dictionary = model.state.stats
    var multiplier: float = rule.sleep_metabolism if sleeping else 1.0
    var hunger_rate: float = rule.hunger_per_minute * multiplier
    var thirst_rate: float = rule.thirst_per_minute * multiplier
    var before_hunger: float = stats.hunger
    var before_thirst: float = stats.thirst
    stats.hunger = maxf(0, before_hunger - hunger_rate * minutes)
    stats.thirst = maxf(0, before_thirst - thirst_rate * minutes)
    for id in ["hunger", "thirst"]:
        var before: float = before_hunger if id == "hunger" else before_thirst
        if before > rule.warning_threshold and stats[id] <= rule.warning_threshold:
            model.event("need_warning", "饥饿已经影响状态，需要食物。" if id == "hunger" else "口渴已经影响状态，需要饮水。", "疲惫", {"stat": id})
        if before > 0 and stats[id] <= 0:
            model.event("need_empty", "饱腹归零，饥饿开始损伤身体。" if id == "hunger" else "水分耗尽，脱水开始损伤身体。", "恐惧", {"stat": id})
    if sleeping:
        var fed_minutes := minf(minutes, maxf(0, (before_hunger - rule.healing_threshold) / hunger_rate))
        fed_minutes = minf(fed_minutes, maxf(0, (before_thirst - rule.healing_threshold) / thirst_rate))
        stats.health = minf(100, stats.health + fed_minutes * float(rule.sleep_heal_per_minute))
    var starving := maxf(0, minutes - before_hunger / hunger_rate)
    var dehydrated := maxf(0, minutes - before_thirst / thirst_rate)
    model.environment_damage(starving * float(rule.starvation_damage_per_minute) + dehydrated * float(rule.dehydration_damage_per_minute))

static func summarize(model: RefCounted, finished_day: int) -> void:
    if finished_day < 1 or finished_day >= model.state.day or finished_day <= model.state.calendar.last_summary_day:
        return
    var tally := {"summary_day": finished_day, "entered": 0, "looted": 0, "searches": 0, "kills": 0, "damage": 0.0, "used": 0, "manual": 0,"stored":0,"retrieved":0,"goals":0}
    for entry in model.state.events:
        if entry.day != finished_day:
            continue
        match entry.kind:
            "entered": tally.entered += 1
            "looted":
                tally.searches += 1
                for count in entry.payload.get("items", {}).values():
                    tally.looted += int(count)
            "killed": tally.kills += 1
            "injured": tally.damage += float(entry.payload.get("damage", 0))
            "used": tally.used += 1
            "manual": tally.manual += 1
            "stored": tally.stored += int(entry.payload.get("count",0))
            "retrieved": tally.retrieved += int(entry.payload.get("count",0))
            "goal_done": tally.goals += 1
    model.state.calendar.last_summary_day = finished_day
    var text := "第%d天总结：进入%d处，搜到%d件物资，击倒%d只，受伤%.0f点，使用%d件物品，手写%d条，存入%d件、取回%d件。" % [finished_day, tally.entered, tally.looted, tally.kills, tally.damage, tally.used, tally.manual,tally.stored,tally.retrieved]
    # Objectives are part of the day, but a day with none should not read
    # "completed 0 objectives": the sentence only appears when it happened.
    if int(tally.goals) > 0:
        text = text.left(-1) + "，完成%d个小目标。" % int(tally.goals)
    model.event("daily_summary", text, "疲惫", tally)
