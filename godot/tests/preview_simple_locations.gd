extends SceneTree
## Deterministic real-renderer screenshots for the three lightweight locations.

var output := "res://../work/locations"

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    call_deferred("run")

func wait_frames(count: int) -> void:
    for i in count:
        await process_frame

func shot(name: String) -> void:
    await wait_frames(4)
    if DisplayServer.get_name() != "headless":
        root.get_texture().get_image().save_png(
            ProjectSettings.globalize_path(output + "/" + name + ".png"))

func run() -> void:
    root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
    root.content_scale_size = Vector2i(1920, 1080)
    var shots := [
        ["track_field", Vector3(0, 1.0, 0), 46.0, 0.0, "01-track-field"],
        ["market_square", Vector3(0, 1.0, -1.0), 31.0, 0.0, "02-market-square"],
        ["villa_courtyard", Vector3(0, 1.2, -1.2), 33.0, 0.0, "03-villa-courtyard"],
    ]
    for entry in shots:
        var scene = load("res://locations/" + str(entry[0]) + ".tscn").instantiate()
        root.add_child(scene)
        await wait_frames(18)
        scene.preview_view(entry[1] as Vector3, float(entry[2]), float(entry[3]))
        await shot(str(entry[4]))
        scene.queue_free()
        await wait_frames(3)
    print("SIMPLE_LOCATIONS_PREVIEW_OK")
    quit()
