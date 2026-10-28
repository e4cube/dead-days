extends SceneTree
## Floor chase acceptance: a ground-floor zombie has to walk the villa stairs and
## reach the player on the second floor, and it must never hit through the slab.
##
## Covers the four things the multi-floor navigation change is responsible for:
##   1. two floor grids exist and the upper slab no longer seals the ground floor
##   2. path() stitches a ground-floor leg, the flight and an upper-floor leg
##   3. a zombie standing under the player cannot damage them
##   4. noise pulls it up the stairs and it lands hits only after arriving
var game
var failures := 0

func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func frames(count: int) -> void:
    for i in count:
        await physics_frame

func _initialize() -> void:
    call_deferred("run")

func free_distance(nav, at: Vector3) -> float:
    var index: int = nav.floor_index(at.y)
    var cell: Vector2i = nav.nearest_in(at, index)
    var floor = nav.floors[index]
    var best := INF
    for y in range(cell.y - 2, cell.y + 3):
        for x in range(cell.x - 2, cell.x + 3):
            var id := Vector2i(x, y)
            if floor.grid.is_in_boundsv(id) and not floor.grid.is_point_solid(id):
                best = minf(best, floor.grid.get_point_position(id).distance_to(Vector2(at.x, at.z)))
    return best

func run() -> void:
    game = load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/floor_chase_%d" % Time.get_ticks_usec())
    game.model.rules.zombie_spawns = []
    game.new_run()
    await frames(2)
    var nav = game.navigation
    # 1. Two grids, and the upper slab is a surface rather than a wall.
    check(nav.floors.size() == 2, "connected world builds one navigation grid per floor")
    check(is_equal_approx(nav.floors[1].ground_y, 3.56), "upper floor ground height matches the villa slab")
    for probe in [Vector3(112.75, 0, -23.6), Vector3(115.95, 0, -23.6), Vector3(121.4, 0, -22.0)]:
        check(free_distance(nav, probe) < 1.2,
            "ground floor stays walkable under the upper slab at " + str(probe))
    check(free_distance(nav, Vector3(119.0, 3.56, -22.8)) < 1.2, "upper floor is walkable at the chest")
    check(free_distance(nav, Vector3(110.4, 3.56, -23.5)) < 1.2, "upper floor is walkable at the stair head")
    # 2. A route from the ground floor to the upper floor passes through the stairs.
    var route: PackedVector3Array = nav.path(Vector3(112.5, 0, -19.5), Vector3(119.0, 3.56, -22.8))
    var climbed := false
    for point in route:
        if point.y > 2.5:
            climbed = true
    check(route.size() > 6 and climbed, "cross-floor path climbs the stairs instead of walking flat")

    # 3. Standing directly under the player must not deal damage.
    game.model.rules.zombie_spawns = [{"id": "under", "position": [115.5, 0.05, -21.0]}]
    game.new_run()
    game.active = false
    await frames(2)
    game.player.position = Vector3(115.5, 3.62, -21.0)
    await frames(4)
    var under = game.zombie_bodies[0]
    var before: float = game.model.state.stats.health
    under.record.mode = "chase"
    under.record.target = [115.5, 3.62, -21.0]
    under.record.windup = 0.01
    under.tick(0.02)
    check(game.model.state.stats.health == before, "zombie one floor below cannot hit through the slab")
    check(absf(under.position.y - game.player.position.y) > 2.0, "fixture really is on another floor")

    # 4. Noise pulls it upstairs and only then does it land hits.
    game.active = true
    var climbed_up := false
    var health_start: float = game.model.state.stats.health
    for i in 1080:
        if i % 20 == 0:
            game.model.noise(game.player.position, 14.0, "floor_chase_test")
        await physics_frame
        if under.position.y > 3.0:
            climbed_up = true
        if climbed_up and game.model.state.stats.health < health_start:
            break
    check(climbed_up, "zombie walks the stairs and reaches the upper floor (y=%.2f)" % under.position.y)
    check(under.position.y > 3.0, "zombie finished the climb instead of hovering mid-flight")
    check(game.model.state.stats.health < health_start,
        "zombie hits the player after arriving on their floor (hp %.0f)" % game.model.state.stats.health)
    var strip: Dictionary = {"y": under.position.y, "hp": game.model.state.stats.health}
    print("FLOOR_CHASE_TRACE ", JSON.stringify(strip))

    # 5. A zombie that has climbed is still on the upper floor after a round trip
    #    through the save file; the floor is derived from its stored height.
    game.player.position = Vector3(115.5, 3.62, -21.0)
    under.position = Vector3(114.8, 3.51, -21.6)
    var stored: float = under.position.y
    var saved: bool = game.save_run()
    check(saved, "floor chase state saves")
    game.continue_run()
    check(game.active, "floor chase state continues")
    await frames(2)
    var reloaded = game.zombie_bodies[0]
    check(absf(reloaded.position.y - stored) < 0.6, "reloaded zombie keeps its floor")
    check(game.navigation.floor_index(reloaded.position.y) == 1, "reloaded zombie resolves to the upper floor")

    if failures == 0:
        print("FLOOR_CHASE_OK")
    quit(0 if failures == 0 else 1)
