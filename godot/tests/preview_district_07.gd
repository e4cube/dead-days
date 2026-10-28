extends SceneTree

var output := "res://../work/district"

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

func run() -> void:
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size = Vector2i(1920, 1080)
    var scene = load("res://locations/district_07.tscn").instantiate()
    root.add_child(scene)
    await wait_frames(24)

    scene.teleport_player(Vector3(0.0, .12, 18.0))
    scene.preview_view(Vector3(0.0, 1.2, 1.0), 88.0, 0.0)
    await shot("01-district-overview")

    scene.teleport_player(Vector3(24.0, .12, 12.0))
    scene.preview_view(Vector3(24.0, 1.5, 7.0), 30.0, 0.0)
    await shot("02-villa-exterior")

    scene.teleport_player(Vector3(22.0, .12, .5))
    scene.preview_view(Vector3(26.0, 1.3, .6), 14.0, 0.0)
    await shot("03-villa-interior")

    print("DISTRICT_07_PREVIEW_OK")
    quit()
