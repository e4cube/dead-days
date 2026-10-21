extends SceneTree
const Visual = preload("res://scripts/character_visual.gd")
func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var stage := Node3D.new()
    root.add_child(stage)
    var ground := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(12, 0.1, 7)
    ground.mesh = box
    ground.position = Vector3(0, -0.1, 1.5)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("47544a")
    ground.material_override = mat
    stage.add_child(ground)
    var names := ["stand", "move", "attack", "hurt", "death"]
    var titles := ["站立", "移动", "攻击", "受伤", "倒地"]
    for row in 2:
        var kind := "player" if row == 0 else "zombie"
        for index in names.size():
            var visual := Visual.new()
            stage.add_child(visual)
            visual.position = Vector3((index - 2) * 2.2, 0, row * 3)
            visual.setup(kind)
            visual.set_weapon(true)
            var seconds: float = 0.1 if names[index] == "hurt" else (0.43 if row == 1 and names[index] == "attack" else 0.2)
            if names[index] == "move":
                seconds = 0.05
            if row == 0 and names[index] == "attack":
                seconds = 0.0
            visual.sample(names[index], seconds)
            var label := Label3D.new()
            label.text = ("玩家 " if row == 0 else "僵尸 ") + titles[index]
            label.position = visual.position + Vector3(0, 2.1, 0)
            label.font_size = 30
            label.pixel_size = 0.009
            label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
            stage.add_child(label)
    var camera := Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 12.5
    stage.add_child(camera)
    camera.position = Vector3(2, 8, 11)
    camera.look_at(Vector3(0, 0.6, 1.5))
    camera.current = true
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -30, 0)
    sun.light_energy = 1.1
    sun.shadow_enabled = true
    stage.add_child(sun)
    var env := WorldEnvironment.new()
    env.environment = Environment.new()
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color("c6d7e6")
    env.environment.ambient_light_energy = 0.65
    stage.add_child(env)
    for i in 4:
        await process_frame
    if DisplayServer.get_name() != "headless":
        var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/c3-poses.png"))
        if result != OK:
            quit(1)
            return
    print("ASSET_GALLERY_OK")
    stage.queue_free()
    await process_frame
    quit(0)
