extends "res://tests/test_clinic_slice.gd"
## One full armed expedition: prepare at home, walk the road, fight, loot the
## market, carry it back, store it, save and reload. Enemies stay enabled, which
## is the difference between this and test_connected_route (a geometry fixture).
##
## Headless, fixed step. It proves the loop holds together with real threat; it
## is not a balance or frame-rate measurement.
##
## Everything below is production input: WASD through the movement driver, space
## to swing, E to search, B to open base storage.  The walker follows a real
## navigation path one waypoint at a time and never teleports.  It also behaves
## like a survivor rather than a script: anything that comes within reach is
## stopped and killed before the route continues, and a bandage is used when the
## health drops.  Walking through a crowd swinging only when blocked is how the
## previous version of this test died at the market gate.

const STILL_FRAMES := 18
const REACH := 0.075
const CHASE_RANGE := 6.0
const MELEE_RANGE := 1.15
const HEAL_BELOW := 55.0
const WAYPOINT_BUDGET := 1800

func release_all() -> void:
    for action in ["left", "right", "forward", "back", "run"]:
        Input.action_release(action)

func step_toward(difference: Vector2) -> void:
    # The driver only presses; a stale press from the previous frame would keep
    # the survivor walking in the old direction, so every frame starts clean.
    release_all()
    preload("res://tests/movement_driver.gd").drive(game, difference)

## The first live zombie close enough to be physically in the way.
func blocking_zombie(reach: float) -> Node3D:
    var facing := Vector2(sin(game.player.rotation.y), cos(game.player.rotation.y))
    var best: Node3D = null
    var best_distance := reach
    for zombie in game.zombie_bodies:
        if zombie.record.health <= 0:
            continue
        var offset := Vector2(zombie.position.x - game.player.position.x,
            zombie.position.z - game.player.position.z)
        var distance := offset.length()
        if distance >= best_distance or distance < 0.001:
            continue
        if facing.dot(offset / distance) < 0.1:
            continue
        best_distance = distance
        best = zombie
    return best

## Anything already hunting the survivor has to be answered before the route
## continues; a wandering zombie that has not noticed us can be walked past.
func nearest_chaser(max_distance: float) -> Node3D:
    var best: Node3D = null
    var best_distance := max_distance
    for zombie in game.zombie_bodies:
        if zombie.record.health <= 0 or zombie.record.mode != "chase":
            continue
        var d: float = zombie.position.distance_to(game.player.position)
        if d < best_distance:
            best_distance = d
            best = zombie
    return best

func nearest_live_zombie(max_distance: float) -> Node3D:
    var best: Node3D = null
    var best_distance := max_distance
    for zombie in game.zombie_bodies:
        if zombie.record.health <= 0:
            continue
        var d: float = zombie.position.distance_to(game.player.position)
        if d < best_distance:
            best_distance = d
            best = zombie
    return best

## Close to melee with real movement input and swing on cooldown until the
## target drops.  Standing still at range would let a wandering zombie drift
## away, so the walk-in is part of the fight.
func engage(target: Node3D) -> bool:
    for i in 500:
        if not is_instance_valid(target) or target.record.health <= 0:
            release_all()
            return true
        if game.model.state.stats.health <= 0:
            release_all()
            return false
        var offset: Vector3 = target.position - game.player.position
        var flat := Vector2(offset.x, offset.z)
        game.player.rotation.y = atan2(offset.x, offset.z)
        if flat.length() > MELEE_RANGE:
            step_toward(flat)
        else:
            release_all()
        game.sync_position()
        if game.model.state.combat.attack_cd <= 0.0:
            key(KEY_SPACE)
        await physics_frame
    release_all()
    return false

## How many live zombies are inside a radius, and where their weight sits.  A
## three-against-one melee is a loss at this damage tuning, so the walker needs
## to see a pack forming before it is surrounded.
func crowd_count(radius: float) -> int:
    var total := 0
    for zombie in game.zombie_bodies:
        if zombie.record.health <= 0:
            continue
        if Vector2(zombie.position.x - game.player.position.x,
                zombie.position.z - game.player.position.z).length() < radius:
            total += 1
    return total

func crowd_center(radius: float) -> Vector2:
    var sum := Vector2.ZERO
    var total := 0
    for zombie in game.zombie_bodies:
        if zombie.record.health <= 0:
            continue
        var offset := Vector2(zombie.position.x - game.player.position.x,
            zombie.position.z - game.player.position.z)
        if offset.length() < radius:
            sum += offset
            total += 1
    if total == 0:
        return Vector2(game.player.position.x, game.player.position.z - 1.0)
    return Vector2(game.player.position.x, game.player.position.z) + sum / float(total)

## Fall back to ground the survivor already crossed.  The keyboard driver walks
## one axis at a time, so "walk away" only works as a path with waypoints; a raw
## vector makes the survivor slide sideways along the pack instead of leaving.
func retreat_to(goal: Vector3) -> void:
    var path: PackedVector3Array = game.navigation.path(game.player.position, goal)
    if path.is_empty():
        var away := Vector2(game.player.position.x - goal.x, game.player.position.z - goal.z)
        if away.length() < 0.01:
            away = Vector2(0, 1)
        for i in 24:
            if game.model.state.stats.health <= 0:
                break
            step_toward(away * 3.0)
            await physics_frame
        release_all()
        return
    for point in path:
        for i in 90:
            if game.model.state.stats.health <= 0:
                release_all()
                return
            var difference := Vector2(point.x, point.z) - Vector2(game.player.position.x, game.player.position.z)
            if difference.length() < REACH:
                break
            step_toward(difference)
            await physics_frame
    release_all()

## Bandages live in slot 3 and are the medicine key the HUD advertises.
func heal_if_hurt() -> void:
    if game.model.state.stats.health >= HEAL_BELOW:
        return
    if game.model.state.inventory.get("bandage", 0) <= 0:
        return
    key(KEY_3)

## Walk to one waypoint with production input only.  Returns false when the
## budget runs out, which makes the caller replan from where we actually stand.
func walk_to(goal: Vector2, fallback: Vector3, fighting: bool = true, sprinting: bool = false, budget: int = WAYPOINT_BUDGET) -> bool:
    var last := Vector2(game.player.position.x, game.player.position.z)
    var still := 0
    var side := 1.0
    for i in budget:
        if game.model.state.stats.health <= 0:
            release_all()
            return false
        if fighting and crowd_count(3.0) >= 2:
            await retreat_to(fallback)
            heal_if_hurt()
            still = 0
            last = Vector2(game.player.position.x, game.player.position.z)
            continue
        var threat := nearest_chaser(CHASE_RANGE) if fighting else null
        if fighting and threat == null:
            var brush := nearest_live_zombie(1.4)
            if brush != null and brush.position.distance_to(game.player.position) < 1.0:
                threat = brush
        if threat != null:
            await engage(threat)
            heal_if_hurt()
            still = 0
            last = Vector2(game.player.position.x, game.player.position.z)
            continue
        var difference: Vector2 = goal - Vector2(game.player.position.x, game.player.position.z)
        if difference.length() < REACH:
            release_all()
            await physics_frame
            return true
        step_toward(difference)
        if sprinting:
            # Zombies walk at 1.65 and the survivor runs at 4.5, so a looted
            # counter is escaped by speed, not by another fight.
            Input.action_press("run")
        await physics_frame
        var now := Vector2(game.player.position.x, game.player.position.z)
        if now.distance_to(last) < 0.012:
            still += 1
        else:
            still = 0
            last = now
        if still >= STILL_FRAMES:
            # A zombie in the lane is the common case; anything else is a piece
            # of geometry the grid does not know about, so nudge sideways and
            # let the caller plan a fresh path from the new position.
            release_all()
            var blocker := blocking_zombie(1.6)
            if blocker != null:
                await engage(blocker)
            else:
                var heading := (goal - now).normalized()
                step_toward(Vector2(-heading.y, heading.x) * side * 2.0)
                for n in 18:
                    await physics_frame
                release_all()
                side = -side
            still = 0
            last = Vector2(game.player.position.x, game.player.position.z)
    release_all()
    return false

## Follow a real navigation path.  Empty paths happen when the per-frame A*
## budget is spent, so a few frames of patience are part of the contract.
func travel(goal: Vector3, fighting: bool = true, sprinting: bool = false, push: bool = false) -> void:
    for attempt in 5:
        if game.model.state.stats.health <= 0:
            break
        var path: PackedVector3Array = game.navigation.path(game.player.position, goal)
        if path.is_empty():
            await physics_frame
            continue
        var complete := true
        var behind: Vector3 = game.player.position
        var history: Array[Vector3] = []
        for point in path:
            history.append(point)
            if history.size() > 8:
                behind = history[history.size() - 8]
            if not await walk_to(Vector2(point.x, point.z), behind, fighting, sprinting):
                complete = false
                break
        if complete:
            # The grid keeps a capsule-width margin around furniture, so a
            # container can sit just outside the last free cell.  Only the last
            # step into a container pushes past that margin; leaving the grid
            # elsewhere would strand the next path on the wrong side of a wall.
            if push:
                var gap := Vector2(goal.x, goal.z) - Vector2(game.player.position.x, game.player.position.z)
                if gap.length() > 0.3 and gap.length() <= 2.2:
                    await walk_to(Vector2(goal.x, goal.z), goal, false, false, 240)
            return
    check(false, "route blocked at %s toward %s" % [str(game.player.position), str(goal)])

func killed_count() -> int:
    var total := 0
    for item in game.model.state.events:
        if item.kind == "killed":
            total += 1
    return total

func market_kills() -> int:
    var total := 0
    for zombie in game.model.state.zombies:
        if str(zombie.id).begins_with("market_z") and zombie.health <= 0:
            total += 1
    return total

func run() -> void:
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size=Vector2i(1920,1080)
    game=load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/connected_expedition_%d"%Time.get_ticks_usec())
    game.new_run()

    check(game.model.state.zombies.size()>=80,"expedition starts with the full population alive")
    var alive_at_start:=0
    for zombie in game.model.state.zombies:
        if zombie.health>0: alive_at_start+=1
    check(alive_at_start>=80,"population alive count")

    # --- prepare at home -------------------------------------------------
    # x = -7 is the clear lane through the front door; the kitchen partition
    # spans x -6.31..-4.25 on this row, so a waypoint there is inside a wall.
    await travel(Vector3(-7,0,1.2))
    key(KEY_E)
    await travel(Vector3(-7,0,-2.4))
    check(game.inside("home"),"entered home to prepare")
    check(game.nearby().get("kind")=="container","home cabinet is reachable")
    key(KEY_E)
    check(game.model.weight()>0,"home supplies looted before departure")
    check(game.model.state.inventory.get("club",0)>0,"found the club to fight with")
    game.use("club")
    check(game.model.state.combat.equipped=="club","club equipped")
    await shot("expedition-01-prepared")

    # --- walk the road ---------------------------------------------------
    await travel(Vector3(-7,0,1.2))
    check(not game.inside("home"),"left the base through the front door")
    await travel(Vector3(-7,0,3.0))

    # --- clinic detour ---------------------------------------------------
    # The street between here and District 07 holds more single fights than one
    # health bar covers, so a real plan picks up medicine first.  The clinic is
    # the only bandage source on this side of the map.
    await travel(Vector3(0,0,1.2))
    key(KEY_E)
    await travel(Vector3(0,0,-1.9))
    check(game.inside("clinic"),"reached the clinic on the way east")
    key(KEY_E)
    var bandages: int = int(game.model.state.inventory.get("bandage",0))
    check(bandages>0,"carrying medicine for the road")
    await travel(Vector3(0,0,1.2))
    check(not game.inside("clinic"),"left the clinic without losing the door")

    await travel(Vector3(28,0,3))
    await travel(Vector3(43,0,3))
    await shot("expedition-02-road")
    await travel(Vector3(67,0,-8))
    check("market_07" in game.model.state.exploration.discovered,"market region discovered on arrival")

    # --- encounter -------------------------------------------------------
    # Most of the fighting happens on the way in, so the proof is the journal
    # and the body count rather than one scripted duel at a fixed spot.
    var kills_before:=killed_count()
    var target := nearest_chaser(8.0)
    if target != null and target.record.health > 0:
        await engage(target)
    check(killed_count()>kills_before or market_kills()>=1,"the road produced a real encounter")
    check(market_kills()>=1,"melee put a market zombie down")
    check(killed_count()>0,"the encounter is written to the journal")
    check(game.model.state.stats.health>0,"survived the encounter")
    await shot("expedition-03-encounter")

    # --- loot the market -------------------------------------------------
    # The produce stalls sit on the west aisle.  The stall itself is a solid
    # counter, so the standing spot is the aisle cell beside it.
    await travel(Vector3(57.25,0,-17.0), true, false, true)
    check(game.nearby().get("id")=="market_produce_a","reached the produce stall")
    key(KEY_E)
    var carried: float = game.model.weight()
    check(carried>0,"market supplies looted")
    check(not game.model.observed("market_produce_a").is_empty(),"loot leaves an observation record for the map")
    var observed_count := int(game.model.observed("market_produce_a").get("count",-1))
    var remaining := 0
    for item in game.model.state.containers.market_produce_a:
        remaining += int(game.model.state.containers.market_produce_a[item])
    check(observed_count==remaining,"observation matches what was left behind")
    await shot("expedition-04-market-loot")

    await travel(Vector3(67,0,-8))
    await travel(Vector3(43,0,3))
    await travel(Vector3(-7,0,3.0))
    await travel(Vector3(-7,0,1.2))
    await travel(Vector3(-7,0,-2.4))
    check(game.inside("home"),"returned inside the base")
    key(KEY_B)
    check(game.expedition.is_open(),"base storage opens")
    var carried_items: Dictionary=game.model.state.inventory.duplicate(true)
    for item in carried_items:
        game.expedition.selected=item
        game.expedition.transfer(true,10000)
    check(game.model.weight()==0.0,"everything stowed at the base")
    check(game.model.base_id()=="home","home remains the base")
    await shot("expedition-05-stored")
    game.expedition.close()

    # --- save / reload ---------------------------------------------------
    var kills:=killed_count()
    check(game.save_run(),"expedition saves")
    game.continue_run()
    check(game.inside("home") and game.model.weight()==0.0,"position and stowed inventory restored")
    check("market_07" in game.model.state.exploration.discovered,"market discovery restored")
    check(killed_count()==kills,"kill records restored")
    var dead_restored:=0
    for zombie in game.model.state.zombies:
        if zombie.health<=0: dead_restored+=1
    check(dead_restored>=1,"killed zombie stays dead after reload")
    check(not game.model.observed("market_produce_a").is_empty(),"observation survives reload")
    var market_left:=0
    for item in game.model.state.containers.market_produce_a:
        market_left+=int(game.model.state.containers.market_produce_a[item])
    check(market_left==remaining,"looted market stock does not refill on load")
    await shot("expedition-06-restored")

    print("END hp=%.0f kills=%d at %s" % [game.model.state.stats.health, killed_count(),
        str(game.player.position)])
    print("CONNECTED_EXPEDITION_OK" if failures==0 else "CONNECTED_EXPEDITION_FAILED")
    quit(0 if failures==0 else 1)
