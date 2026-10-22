extends SceneTree
## Physics integration fixtures deliberately place actors to isolate wall, FOV and combat cases.
var game
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func frames(count: int) -> void:
    for i in count:
        await physics_frame

func fixture(player_at: Vector3, zombies: Array, opened: bool = false) -> void:
    game.model.rules.zombie_spawns = zombies
    game.new_run()
    game.active = false
    game.player.position = player_at
    game.player.rotation.y = PI
    game.model.state.doors.home = opened
    game.apply_door("home")
    game.navigation.rebuild(game.nav_sources, game.model.rules.navigation)
    await frames(2)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    print("USER_DATA_ROOT / ", ProjectSettings.globalize_path("user://"))
    await fixture(Vector3(-7, 0, -2), [{"id": "wall", "position": [-7, 0, 0.8]}])
    var z = game.zombie_bodies[0]
    check(not game.line_clear(z.position, game.player.position), "closed door occludes ray")
    check(not z.sees_player(), "closed door blocks sight")
    game.model.noise(game.player.position, 4, "quiet_test")
    check(not z.hear(), "wall attenuates faint noise")
    game.model.noise(game.player.position, 10, "loud_test")
    check(z.hear() and z.record.mode == "alert", "loud noise through wall alerts")
    check(z.record.target[2] == -2, "hearing remembers source rather than tracking player")
    z.record.windup = 0.01
    z.tick(0.02)
    check(game.model.state.stats.health == 100, "windup cannot hit through closed door")
    game.model.state.doors.home = true
    game.apply_door("home")
    await frames(2)
    z.rotation.y = PI
    check(z.sees_player(), "open door exposes player")
    await fixture(Vector3(-7, 0, 3), [{"id": "fov", "position": [-7, 0, 6]}])
    z = game.zombie_bodies[0]
    z.rotation.y = 0
    check(not z.sees_player(), "outside visual cone is unseen")
    z.rotation.y = PI
    check(z.sees_player(), "visual cone detects in front")
    # Weapon fan, cooldown, wall occlusion and dead actor collision.
    await fixture(Vector3(-7, 0, 0.7), [{"id": "combat", "position": [-7, 0, -0.7]}])
    z = game.zombie_bodies[0]
    game.model.loot("home")
    check(game.model.use_item("club"), "equip real looted weapon")
    game.active = true
    check(game.try_attack(), "attack spends stamina")
    check(z.record.health == 70, "player cannot hit through door")
    check(z.hear() and z.record.last_noise == game.model.state.noise_sequence, "combat sound alerts an unseen zombie")
    check(not game.try_attack(), "attack cooldown cannot be bypassed")
    game.active = false
    game.model.state.doors.home = true
    game.apply_door("home")
    await frames(2)
    game.model.tick_combat(1)
    game.active = true
    game.player.rotation.y = 0
    game.try_attack()
    check(z.record.health == 70, "attack fan rejects rear target")
    game.player.rotation.y = PI
    for i in 3:
        game.model.tick_combat(1)
        game.try_attack()
    check(z.record.health == 0 and z.record.mode == "dead", "weapon damages and kills")
    check(z.collision_layer == 0, "dead zombie no longer blocks movement")
    var health: float = game.model.state.stats.health
    z.tick(2)
    check(game.model.state.stats.health == health, "dead zombie never attacks")
    game.active = false
    # A living attack takes time, can miss if target leaves, and triggers medical consequences.
    await fixture(Vector3(-7, 0, 3), [{"id": "bite", "position": [-7, 0, 3.9]}])
    z = game.zombie_bodies[0]
    z.tick(0.01)
    check(z.record.windup > 0 and game.model.state.stats.health == 100, "zombie telegraphs windup")
    game.player.position.z = 1
    z.tick(0.5)
    check(game.model.state.stats.health == 100, "moving out of reach avoids hit")
    game.player.position.z = z.position.z - 0.9
    z.record.attack_cd = 0
    z.rotation.y = PI
    z.tick(0.01)
    z.tick(0.5)
    check(game.model.state.stats.health == 90, "living zombie hits after windup")
    check(not game.model.damage_player(10, "bite"), "player hurt immunity prevents stacked hits")
    game.model.loot("clinic")
    check(game.model.use_item("bandage") and game.model.state.stats.health == 100, "bandage heals actual wound")
    # Navigation must go around the back wall and enter via the open front door.
    var rear_spawn: float = -float(game.model.rules.buildings[0].get("depth",5)) - 2.0
    await fixture(Vector3(11, 0, 6), [{"id": "route", "position": [-7, 0, rear_spawn]}], true)
    z = game.zombie_bodies[0]
    var path: PackedVector3Array = game.navigation.path(z.position, Vector3(-7, 0, -1.4))
    check(path.size() > 15, "path routes around building instead of direct wall")
    var reached_front := false
    z.record.mode = "search"
    z.record.target = [-7, 0, -1.4]
    z.record.memory = 30
    for i in 850:
        z.tick(1.0 / 60.0)
        reached_front = reached_front or z.position.z > -0.1
        await physics_frame
        if game.inside("home") and z.position.distance_to(Vector3(-7, 0, -1.4)) < 0.6:
            break
    check(reached_front and z.position.distance_to(Vector3(-7, 0, -1.4)) < 0.7, "actual zombie rounds wall and enters doorway")
    # Close a door after route creation; next tick must invalidate cached route.
    game.model.state.doors.home = false
    game.apply_door("home")
    game.navigation.rebuild(game.nav_sources, game.model.rules.navigation)
    z.tick(0.02)
    check(z.nav_revision == game.navigation.revision, "door update invalidates cached navigation")
    await fixture(Vector3(-7, 0, -3.9), [{"id": "a", "position": [-7, 0, 3]}, {"id": "b", "position": [-7, 0, 3]}])
    for i in 90:
        for actor in game.zombie_bodies:
            actor.tick(1.0 / 60.0)
        await physics_frame
    check(game.zombie_bodies[0].position.distance_to(game.zombie_bodies[1].position) > 0.5, "coincident zombies separate")
    print("THREATS_OK" if failures == 0 else "THREATS_FAILED")
    game.queue_free()
    await process_frame
    quit(0 if failures == 0 else 1)
