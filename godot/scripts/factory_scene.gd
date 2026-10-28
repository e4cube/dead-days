extends Node3D
## Standalone abandoned-factory location.
##
## This scene deliberately does not instantiate or modify game.gd, the street,
## save data or any survival rule.  It reuses only the shared PBR material
## library, the original survivor visual and the original grass prop.

const Assets = preload("res://scripts/asset_library.gd")
const MaterialLibrary = preload("res://scripts/material_library_v1.gd")
const CharacterVisual = preload("res://scripts/character_visual.gd")
const LAYOUT_PATH := "res://data/factory_layout.json"

var layout: Dictionary = {}
var world: Node3D
var factory: Node3D
var player: CharacterBody3D
var visual: CharacterVisual
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var roof: Node3D
var south_wall: Node3D
var east_wall: Node3D
var blocker_bodies: Array[StaticBody3D] = []
var local_lights: Array[OmniLight3D] = []
var camera_yaw := 0.0
var camera_zoom := 27.0
var target_zoom := 27.0
var camera_focus := Vector3.ZERO
var camera_ready := false
var inside_hall := false
var manual_cutaway := false
var preview_locked := false
var preview_focus := Vector3.ZERO
var preview_size := 27.0
var preview_yaw := 0.0
var ui_root: CanvasLayer
var hud_title: Label
var hud_hint: Label
var player_speed := 0.0

func _ready() -> void:
    layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
    if layout.is_empty():
        push_error("factory_layout.json could not be read")
        return
    _build_world()
    _build_player()
    _build_camera()
    _build_environment()
    _build_local_lights()
    _build_grass()
    _build_ui()
    apply_cutaway(false)
    update_camera(0.0)

func _build_world() -> void:
    world = Node3D.new()
    world.name = "FactoryWorld"
    add_child(world)
    # Broad fallback ground so the authored 50 x 40 m site never floats in the void.
    var outer := MeshInstance3D.new()
    outer.name = "OuterSoil"
    var plane := PlaneMesh.new()
    plane.size = Vector2(100.0, 86.0)
    outer.mesh = plane
    outer.position.y = -.07
    outer.material_override = MaterialLibrary.material("soil")
    world.add_child(outer)
    # Ground collision sits at the authored yard level.  The 2 cm visual
    # clearance keeps feet from z-fighting while remaining imperceptible.
    _add_collider_body("Ground", Vector3(0.0, -.23, 0.0), Vector3(60.0, .54, 50.0))

    factory = Assets.attach(world, "factory_grounds", Vector3.ZERO)
    factory.name = "HalvorsenIronworks"

    var cutaway: Dictionary = layout.cutaway
    roof = factory.find_child(str(cutaway.roof), true, false)
    south_wall = factory.find_child(str(cutaway.south_wall), true, false)
    east_wall = factory.find_child(str(cutaway.east_wall), true, false)
    if roof == null or south_wall == null or east_wall == null:
        push_error("Factory cutaway groups are missing from the GLB")

    for definition in layout.colliders:
        var p: Array = definition.position
        var s: Array = definition.size
        _add_collider_body(str(definition.id), Vector3(p[0], p[1], p[2]),
            Vector3(s[0], s[1], s[2]))

func _add_collider_body(id: String, at: Vector3, size: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = "Collider_" + id
    body.collision_layer = 1
    body.collision_mask = 0
    body.position = at
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    world.add_child(body)
    blocker_bodies.append(body)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Survivor"
    player.collision_layer = 2
    player.collision_mask = 1 | 4
    player.up_direction = Vector3.UP
    player.floor_snap_length = .24
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = .28
    capsule.height = 1.7
    shape.shape = capsule
    shape.position.y = .90
    player.add_child(shape)
    visual = CharacterVisual.new()
    player.add_child(visual)
    visual.setup("player")
    visual.position.y = .05
    var spawn: Array = layout.spawn
    player.position = Vector3(spawn[0], spawn[1], spawn[2])
    player.rotation.y = deg_to_rad(float(layout.spawn_yaw))
    world.add_child(player)
    camera_zoom = float(layout.camera.exterior_size)
    target_zoom = camera_zoom

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.name = "FactoryCamera"
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = camera_zoom
    camera.near = .05
    camera.far = 120.0
    world.add_child(camera)
    camera.current = true
    camera_ready = false

func _build_environment() -> void:
    sun = DirectionalLight3D.new()
    sun.name = "LateAfternoonSun"
    sun.rotation_degrees = Vector3(-53.0, -32.0, 0.0)
    sun.light_color = Color("fff4e8")
    sun.light_energy = 1.00
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 85.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun.directional_shadow_split_1 = .22
    sun.directional_shadow_split_2 = .55
    sun.directional_shadow_blend_splits = true
    world.add_child(sun)

    environment = WorldEnvironment.new()
    environment.name = "FactoryAtmosphere"
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color("1e282e")
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("b9c6cb")
    env.ambient_light_energy = .50
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = .89
    env.fog_enabled = true
    env.fog_light_color = Color("344249")
    env.fog_light_energy = .40
    env.fog_density = .005
    env.fog_aerial_perspective = .30
    env.adjustment_enabled = true
    env.adjustment_contrast = 1.08
    env.adjustment_saturation = .92
    environment.environment = env
    world.add_child(environment)

func _build_local_lights() -> void:
    for definition in layout.lights:
        var p: Array = definition.position
        var light := OmniLight3D.new()
        light.name = "FactoryLight_" + str(definition.id)
        light.position = Vector3(p[0], p[1], p[2])
        light.light_color = Color(str(definition.color))
        light.light_energy = float(definition.energy)
        light.omni_range = float(definition.range)
        light.omni_attenuation = 1.4
        light.shadow_enabled = bool(definition.get("shadow", false))
        world.add_child(light)
        local_lights.append(light)

func _build_grass() -> void:
    var template: Node3D = load("res://assets/grass_clump.glb").instantiate()
    var meshes := template.find_children("*", "MeshInstance3D", true, false)
    if meshes.is_empty():
        template.free()
        return
    var batch := MultiMeshInstance3D.new()
    batch.name = "FactoryDryGrass"
    batch.multimesh = MultiMesh.new()
    batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
    batch.multimesh.mesh = meshes[0].mesh
    batch.multimesh.instance_count = layout.grass.size()
    batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    batch.visibility_range_end = 44.0
    for i in layout.grass.size():
        var p: Array = layout.grass[i]
        var basis := Basis(Vector3.UP, float(i) * 2.399963).scaled(Vector3.ONE * float(p[2]))
        batch.multimesh.set_instance_transform(i, Transform3D(basis, Vector3(p[0], .055, p[1])))
    world.add_child(batch)
    template.free()

func _build_ui() -> void:
    ui_root = CanvasLayer.new()
    ui_root.name = "FactoryHud"
    add_child(ui_root)
    var bar := ColorRect.new()
    bar.color = Color(0.035, 0.047, 0.052, .82)
    bar.position = Vector2(28, 24)
    bar.size = Vector2(420, 78)
    ui_root.add_child(bar)
    var accent := ColorRect.new()
    accent.color = Color("b8893f")
    accent.position = Vector2(28, 24)
    accent.size = Vector2(5, 78)
    ui_root.add_child(accent)
    hud_title = Label.new()
    hud_title.position = Vector2(48, 32)
    hud_title.text = "哈尔沃森铁工厂  /  HALVORSEN IRONWORKS"
    hud_title.add_theme_font_size_override("font_size", 19)
    hud_title.add_theme_color_override("font_color", Color("e9dfc8"))
    hud_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, .8))
    hud_title.add_theme_constant_override("outline_size", 3)
    ui_root.add_child(hud_title)
    var sub := Label.new()
    sub.position = Vector2(48, 61)
    sub.text = "废弃工厂 · 独立场景切片  /  ABANDONED FACTORY"
    sub.add_theme_font_size_override("font_size", 13)
    sub.add_theme_color_override("font_color", Color("aab7b1"))
    ui_root.add_child(sub)
    hud_hint = Label.new()
    hud_hint.position = Vector2(30, 1000)
    hud_hint.text = "WASD 移动 · Shift 奔跑 · Q/E 环绕 · 滚轮缩放 · R 回到入口 · H 剖切 · Esc 退出"
    hud_hint.add_theme_font_size_override("font_size", 15)
    hud_hint.add_theme_color_override("font_color", Color("d8d4c3"))
    hud_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
    hud_hint.add_theme_constant_override("outline_size", 4)
    ui_root.add_child(hud_hint)

func _process(delta: float) -> void:
    if not is_instance_valid(player):
        return
    if preview_locked:
        update_camera(delta)
        return
    if Input.is_key_pressed(KEY_Q):
        camera_yaw -= delta * 1.6
    if Input.is_key_pressed(KEY_E):
        camera_yaw += delta * 1.6
    camera_zoom = lerpf(camera_zoom, target_zoom, 1.0 - exp(-delta * 10.0))
    var inside := inside()
    if inside != inside_hall:
        inside_hall = inside
        apply_cutaway(inside_hall or manual_cutaway)
    update_camera(delta)
    if hud_hint:
        hud_hint.position = Vector2(30, get_viewport().get_visible_rect().size.y - 42)

func _physics_process(delta: float) -> void:
    if not is_instance_valid(player):
        return
    var input := Vector3.ZERO
    if Input.is_key_pressed(KEY_W):
        input.z -= 1.0
    if Input.is_key_pressed(KEY_S):
        input.z += 1.0
    if Input.is_key_pressed(KEY_A):
        input.x -= 1.0
    if Input.is_key_pressed(KEY_D):
        input.x += 1.0
    var direction := input.normalized().rotated(Vector3.UP, camera_yaw)
    var sprint := Input.is_key_pressed(KEY_SHIFT)
    var speed := 5.0 if sprint else 2.9
    player.velocity.x = direction.x * speed
    player.velocity.z = direction.z * speed
    if not player.is_on_floor():
        player.velocity.y -= 18.0 * delta
    else:
        player.velocity.y = -.6
    player.move_and_slide()
    player_speed = Vector2(player.velocity.x, player.velocity.z).length()
    if direction.length_squared() > .01:
        visual.rotation.y = lerp_angle(visual.rotation.y,
            atan2(direction.x, direction.z), 1.0 - exp(-delta * 14.0))
    if player_speed > 4.2:
        visual.sample("run", delta)
    elif player_speed > .25:
        visual.sample("move", delta)
    else:
        visual.sample("stand", delta)

func update_camera(delta: float = 0.0) -> void:
    if not is_instance_valid(player) or not is_instance_valid(camera):
        return
    var cam_data: Dictionary = layout.camera
    var focus := player.position + Vector3(0, float(cam_data.focus_height), 0)
    var size := camera_zoom
    if inside_hall:
        focus = Vector3(0.4, 1.05, .2).lerp(player.position + Vector3(0, .75, 0), .35)
        size = minf(camera_zoom, float(cam_data.interior_size))
    if preview_locked:
        focus = preview_focus
        size = preview_size
        camera_yaw = preview_yaw
    var blend := 1.0 if delta <= 0.0 or preview_locked else 1.0 - exp(-delta * 7.0)
    if not camera_ready:
        camera_focus = focus
        camera_ready = true
    else:
        camera_focus = camera_focus.lerp(focus, blend)
    camera.size = lerpf(camera.size, size, blend)
    var offset: Array = cam_data.offset
    camera.position = camera_focus + Vector3(offset[0], offset[1], offset[2]).rotated(Vector3.UP, camera_yaw)
    camera.look_at(camera_focus)

func inside() -> bool:
    if not is_instance_valid(player):
        return false
    var b: Dictionary = layout.camera.inside_bounds
    var p := player.position
    return p.x > float(b.min_x) and p.x < float(b.max_x) and p.z > float(b.min_z) and p.z < float(b.max_z)

func apply_cutaway(cut: bool) -> void:
    for node in [roof, south_wall, east_wall]:
        if is_instance_valid(node):
            node.visible = not cut

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            target_zoom = clampf(target_zoom - 1.4, float(layout.camera.min_zoom), float(layout.camera.max_zoom))
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            target_zoom = clampf(target_zoom + 1.4, float(layout.camera.min_zoom), float(layout.camera.max_zoom))
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_R:
            reset_player()
        elif event.keycode == KEY_H:
            manual_cutaway = not manual_cutaway
            apply_cutaway(manual_cutaway or inside_hall)
        elif event.keycode == KEY_ESCAPE:
            get_tree().quit()

func reset_player() -> void:
    var spawn: Array = layout.spawn
    player.position = Vector3(spawn[0], spawn[1], spawn[2])
    player.velocity = Vector3.ZERO
    camera_yaw = 0.0
    target_zoom = float(layout.camera.exterior_size)
    camera_zoom = target_zoom
    preview_locked = false
    manual_cutaway = false
    camera_ready = false
    inside_hall = false
    apply_cutaway(false)

# --- Small public hooks used only by the deterministic preview/test scripts ---
func teleport_player(position: Vector3) -> void:
    player.position = position
    player.velocity = Vector3.ZERO
    camera_ready = false

func preview_view(focus: Vector3, size: float, yaw_degrees: float, cutaway: bool) -> void:
    preview_locked = true
    preview_focus = focus
    preview_size = size
    preview_yaw = deg_to_rad(yaw_degrees)
    inside_hall = cutaway
    apply_cutaway(cutaway)
    update_camera(0.0)

func set_dusk(enabled: bool) -> void:
    sun.light_energy = .68 if enabled else 1.00
    sun.light_color = Color("93b0c8") if enabled else Color("fff4e8")
    sun.rotation_degrees = Vector3(-20.0, -50.0, 0.0) if enabled else Vector3(-53.0, -32.0, 0.0)
    var env := environment.environment
    env.ambient_light_energy = .43 if enabled else .50
    env.ambient_light_color = Color("91a7b6") if enabled else Color("b9c6cb")
    env.background_color = Color("0e151b") if enabled else Color("1e282e")
    env.fog_light_color = Color("1b272e") if enabled else Color("344249")
    env.tonemap_exposure = 1.0 if enabled else .89
    for light in local_lights:
        light.light_energy = light.light_energy * (2.2 if enabled else 1.0)
