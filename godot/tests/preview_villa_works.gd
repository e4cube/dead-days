extends SceneTree
## Preview of the villa works: the yard gate closed and open, the hung front door,
## the filled pool, and the containers the materials come from. Presentation only;
## the rules live in tests/test_sites_v1.gd.

var output := "res://../work/villa-works"
var game

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    call_deferred("run")

func wait_frames(count: int) -> void:
    for i in count:
        await process_frame

func shot(name: String) -> void:
    await wait_frames(6)
    if DisplayServer.get_name() != "headless":
        root.get_texture().get_image().save_png(
            ProjectSettings.globalize_path(output + "/" + name + ".png"))

func view(at: Vector3, focus: Vector3, size: float, yaw := 0.0) -> void:
    game.teleport_player(at)
    game.update_cutaways()
    game.preview_view(focus, size, yaw)
    await wait_frames(3)

func run() -> void:
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size = Vector2i(1600, 900)
    game = load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/preview_villa_%d" % Time.get_ticks_usec())
    game.new_run()
    await wait_frames(20)
    game.set_physics_process(false)

    await view(Vector3(106.1, .12, 3.5), Vector3(106.1, 1.1, -2.5), 17.0)
    await shot("01-yard-gate-open-gap")

    await view(Vector3(112.85, .12, -15.2), Vector3(112.85, 1.1, -17.5), 9.0)
    await shot("02-villa-front-gap")

    await view(Vector3(123.3, .12, -8.0), Vector3(123.3, .5, -10.8), 13.0)
    await shot("03-pool-dry")

    game.model.complete_site("villa_gate")
    game.model.complete_site("villa_door")
    game.model.complete_site("villa_water")
    game.sync_sites()
    await wait_frames(3)

    await view(Vector3(106.1, .12, 3.5), Vector3(106.1, 1.1, -2.5), 17.0)
    await shot("04-yard-gate-closed")

    game.model.toggle_door("villa_gate")
    game.apply_door("villa_gate")
    await view(Vector3(106.1, .12, 1.2), Vector3(106.1, 1.1, -3.0), 15.0)
    await shot("05-yard-gate-open")

    game.model.toggle_door("villa_gate")
    game.apply_door("villa_gate")

    await view(Vector3(112.85, .12, -15.2), Vector3(112.85, 1.1, -17.5), 9.0)
    await shot("06-villa-front-door")

    game.model.toggle_door("villa_door")
    game.apply_door("villa_door")
    await view(Vector3(112.85, .12, -19.4), Vector3(112.85, 1.1, -17.0), 9.0)
    await shot("07-villa-front-door-open-inside")
    game.model.toggle_door("villa_door")
    game.apply_door("villa_door")

    await view(Vector3(123.3, .12, -8.0), Vector3(123.3, .5, -10.8), 13.0)
    await shot("08-pool-filled")

    await view(Vector3(119.0, 2.6, -4.5), Vector3(121.5, .3, -8.5), 22.0)
    await shot("09-yard-pool-wide")

    game.model.DoorDamage.hit(game.model, "villa_gate", 120.0, "preview")
    game.apply_door("villa_gate")
    await view(Vector3(106.1, .12, 2.2), Vector3(106.1, 1.1, -2.5), 13.0)
    await shot("10-yard-gate-breached")
    await view(Vector3(106.1, .12, -5.4), Vector3(106.1, .4, -2.5), 11.0)
    await shot("10b-yard-gate-breached-inside")

    await view(Vector3(155.0, .12, 22.0), Vector3(153.4, 1.0, 22.0), 10.0)
    await shot("11-factory-pipe-rack")

    await view(Vector3(160.0, .12, 24.6), Vector3(162.5, .9, 27.0), 12.0)
    await shot("12-factory-gate-stack")

    await view(Vector3(73.4, .12, -15.4), Vector3(73.4, .9, -17.4), 10.0)
    await shot("13-market-hardware-stall")

    print("VILLA_WORKS_PREVIEW_OK")
    quit()
