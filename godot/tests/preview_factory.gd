extends SceneTree
## Deterministic real-renderer screenshots for the additive factory location.

var scene
var output: String = "res://../work/factory"

func wait_frames(count: int) -> void:
    for i in count:
        await process_frame

func shot(name: String) -> void:
    await wait_frames(4)
    if DisplayServer.get_name() != "headless":
        var image := root.get_texture().get_image()
        image.save_png(ProjectSettings.globalize_path(output + "/" + name + ".png"))

func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
    call_deferred("run")

func run() -> void:
    scene = load("res://factory_grounds.tscn").instantiate()
    root.add_child(scene)
    await wait_frames(20)

    scene.preview_view(Vector3(0.0, 2.5, 5.6), 35.5, 0.0, false)
    await shot("01-factory-approach")

    scene.teleport_player(Vector3(11.0, .12, .6))
    scene.preview_view(Vector3(1.2, 1.35, 1.1), 15.6, 8.0, true)
    await shot("02-factory-interior")

    scene.teleport_player(Vector3(-16.0, .12, 12.5))
    scene.preview_view(Vector3(-15.5, 5.6, 4.8), 22.0, -18.0, false)
    await shot("03-silos-and-pipe-bridge")

    scene.teleport_player(Vector3(2.3, .12, 12.0))
    scene.preview_view(Vector3(-1.0, 2.0, 5.0), 33.0, 5.0, false)
    scene.set_dusk(true)
    await shot("04-factory-dusk")

    print("FACTORY_PREVIEW_OK")
    quit(0)
