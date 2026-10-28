extends SceneTree

var output := "res://../work/integrated"
var game

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    call_deferred("run")

func wait_frames(count: int) -> void:
    for i in count:
        await process_frame

func shot(name: String) -> void:
    await wait_frames(5)
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
    root.content_scale_size = Vector2i(1920, 1080)
    game = load("res://locations/integrated_world.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store = load("res://scripts/save_store.gd").new("user://tests/preview_integrated_%d" % Time.get_ticks_usec())
    game.export_directory = game.store.directory + "/exports"
    game.new_run()
    await wait_frames(20)
    game.set_physics_process(false)

    await view(Vector3(104.0, .12, 3.0), Vector3(110.0, 1.2, 8.0), 132.0)
    await shot("01-connected-world")

    await view(Vector3(38.0, .12, 3.0), Vector3(45.0, 1.2, 2.0), 32.0)
    await shot("02-street-to-district")

    await view(Vector3(90.0, .12, 3.0), Vector3(90.0, 1.2, -10.0), 78.0)
    await shot("03-district")

    await view(Vector3(67.0, .12, -14.0), Vector3(67.0, 1.1, -14.5), 29.0)
    await shot("04-market")

    await view(Vector3(114.0, .12, -11.0), Vector3(114.0, 2.2, -14.5), 27.0)
    await shot("05-villa-two-storey")

    await view(Vector3(112.0, .12, -22.0), Vector3(116.0, 1.3, -21.9), 14.0)
    await shot("06-villa-ground-floor")

    await view(Vector3(116.0, 3.62, -22.0), Vector3(116.0, 4.55, -21.9), 14.0)
    await shot("07-villa-upper-floor")

    await view(Vector3(165.5, .12, 22.0), Vector3(165.5, 1.25, 22.0), 15.0)
    await shot("08-factory-interior")

    await view(Vector3(168.0, .12, 2.0), Vector3(170.0, 1.2, 1.0), 24.0)
    await shot("09-factory-gate")

    await view(Vector3(165.5, .12, 32.0), Vector3(165.5, 2.2, 22.0), 38.0)
    await shot("10-factory-exterior")

    await view(Vector3(150.0, .12, 2.0), Vector3(156.0, 1.2, 2.0), 48.0)
    await shot("11-district-factory-link")

    print("INTEGRATED_PREVIEW_OK")
    quit()
