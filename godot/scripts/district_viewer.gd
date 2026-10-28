extends Node3D
## Standalone District 07: track field, market and enterable villa on one block.
##
## This is a new additive scene only.  It reuses the original survivor, shared
## PBR materials and the three lightweight location GLBs; it never edits or
## references the existing street game scene.

const Assets = preload("res://scripts/asset_library.gd")
const MaterialLibrary = preload("res://scripts/material_library_v1.gd")
const CharacterVisual = preload("res://scripts/character_visual.gd")
const DISTRICT_PATH := "res://data/district_layout.json"
const MODULE_PATH := "res://data/simple_locations.json"

var district: Dictionary = {}
var modules: Dictionary = {}
var world: Node3D
var player: CharacterBody3D
var visual: CharacterVisual
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var collider_bodies: Array[StaticBody3D] = []
var lights: Array[OmniLight3D] = []
var camera_yaw := 0.0
var target_zoom := 58.0
var camera_zoom := 58.0
var camera_focus := Vector3.ZERO
var camera_ready := false
var inside_state := false
var preview_locked := false
var preview_focus := Vector3.ZERO
var preview_size := 58.0
var preview_yaw := 0.0
var villa_instance: Node3D
var villa_roof: Node3D
var villa_front: Node3D
var villa_east: Node3D
var villa_upper: Node3D
var upper_state := false
var hud_hint: Label
const STAIR_BOTTOM_LOCAL := Vector3(-3.60, .12, -3.90)
const STAIR_TOP_LOCAL := Vector3(-3.60, 3.62, -8.60)

func _ready() -> void:
    district = JSON.parse_string(FileAccess.get_file_as_string(DISTRICT_PATH))
    modules = JSON.parse_string(FileAccess.get_file_as_string(MODULE_PATH)).locations
    if district.is_empty() or modules.is_empty():
        push_error("District layout data missing")
        return
    _build_world()
    _build_player()
    _build_camera()
    _build_environment()
    _build_lights()
    _build_ui()
    update_camera(0.0)

func _build_world() -> void:
    world = Node3D.new()
    world.name = "DistrictWorld"
    add_child(world)
    var outer := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(140, 130)
    outer.mesh = plane
    outer.position.y = -.065
    outer.material_override = MaterialLibrary.material("soil")
    world.add_child(outer)
    _add_collider("DistrictGround", Vector3(0, -.23, 0), Vector3(140, .54, 130))
    for placement in district.placements:
        var asset := str(placement.asset)
        var p: Array = placement.position
        var at := Vector3(p[0], p[1], p[2])
        var instance := Assets.attach(world, asset, at)
        instance.name = "Module_" + asset
        var definitions = []
        if asset == "district_commons":
            definitions = district.commons_colliders
        elif modules.has(asset):
            definitions = modules[asset].colliders
        for definition in definitions:
            var cp: Array = definition.position
            var cs: Array = definition.size
            _add_collider(str(definition.id), at + Vector3(cp[0], cp[1], cp[2]),
                Vector3(cs[0], cs[1], cs[2]))
        if asset == "villa_courtyard":
            villa_instance = instance
            var cut: Dictionary = district.villa.cutaway
            villa_roof = instance.find_child(str(cut.roof), true, false)
            villa_front = instance.find_child(str(cut.front), true, false)
            villa_east = instance.find_child(str(cut.east), true, false)
            if cut.has("upper"):
                villa_upper = instance.find_child(str(cut.upper), true, false)
            for ramp in modules[asset].get("ramps", []):
                var rp: Array = ramp.position
                _add_ramp(str(ramp.id), at + Vector3(rp[0], rp[1], rp[2]),
                    ramp.size, float(ramp.rotation_x))
            if modules[asset].has("stair_wedge"):
                _add_stair_wedge(modules[asset].stair_wedge, at)

func _add_stair_wedge(w: Dictionary, at: Vector3) -> void:
    var x0 := at.x + float(w.x0)
    var x1 := at.x + float(w.x1)
    var z0 := at.z + float(w.z0)
    var z1 := at.z + float(w.z1)
    var y0 := float(w.y0)
    var y1 := float(w.y1)
    var body := StaticBody3D.new()
    body.name = "VillaStairWedge"
    body.collision_layer = 1
    body.collision_mask = 0
    var shape := ConvexPolygonShape3D.new()
    shape.points = PackedVector3Array([
        Vector3(x0, y0, z0), Vector3(x1, y0, z0),
        Vector3(x0, y0, z1), Vector3(x1, y0, z1),
        Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z0),
        Vector3(x0, y1, z1), Vector3(x1, y1, z1),
    ])
    var collision := CollisionShape3D.new()
    collision.shape = shape
    body.add_child(collision)
    world.add_child(body)
    collider_bodies.append(body)

func _add_ramp(id: String, at: Vector3, size: Array, rotation_x: float) -> void:
    var body := StaticBody3D.new()
    body.name = "Ramp_" + id
    body.collision_layer = 1
    body.collision_mask = 0
    body.position = at
    body.rotation.x = deg_to_rad(rotation_x)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = Vector3(size[0], size[1], size[2])
    shape.shape = box
    body.add_child(shape)
    world.add_child(body)
    collider_bodies.append(body)

func _add_collider(id: String, at: Vector3, size: Vector3) -> void:
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
    collider_bodies.append(body)

func _build_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Survivor"
    player.collision_layer = 2
    player.collision_mask = 1
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
    var spawn: Array = district.spawn
    player.position = Vector3(spawn[0], spawn[1], spawn[2])
    player.rotation.y = deg_to_rad(float(district.spawn_yaw))
    world.add_child(player)
    camera_zoom = float(district.camera.size)
    target_zoom = camera_zoom

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.name = "DistrictCamera"
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = camera_zoom
    camera.near = .05
    camera.far = 180.0
    world.add_child(camera)
    camera.current = true
    camera_ready = false

func _build_environment() -> void:
    var e: Dictionary = district.environment
    sun = DirectionalLight3D.new()
    sun.name = "DistrictSun"
    var sr: Array = e.sun_rotation
    sun.rotation_degrees = Vector3(sr[0], sr[1], sr[2])
    sun.light_color = Color(str(e.sun_color))
    sun.light_energy = float(e.sun_energy)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 150.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
    sun.directional_shadow_split_1 = .18
    sun.directional_shadow_split_2 = .50
    sun.directional_shadow_blend_splits = true
    world.add_child(sun)

    environment = WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(str(e.background))
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(str(e.ambient_color))
    env.ambient_light_energy = float(e.ambient_energy)
    env.tonemap_mode = Environment.TONE_MAPPER_ACES
    env.tonemap_exposure = .90
    env.fog_enabled = true
    env.fog_light_color = Color("344249")
    env.fog_light_energy = .34
    env.fog_density = float(e.get("fog_density", .0045))
    env.adjustment_enabled = true
    env.adjustment_contrast = 1.06
    env.adjustment_saturation = .95
    environment.environment = env
    world.add_child(environment)

func _build_lights() -> void:
    for definition in district.lights:
        _add_light(definition, Vector3.ZERO)
    for placement in district.placements:
        var asset := str(placement.asset)
        if asset == "district_commons" or not modules.has(asset):
            continue
        var p: Array = placement.position
        var at := Vector3(p[0], p[1], p[2])
        for definition in modules[asset].get("lights", []):
            _add_light(definition, at)

func _add_light(definition: Dictionary, offset: Vector3) -> void:
    var p: Array = definition.position
    var light := OmniLight3D.new()
    light.position = offset + Vector3(p[0], p[1], p[2])
    light.light_color = Color(str(definition.color))
    light.light_energy = float(definition.energy)
    light.omni_range = float(definition.range)
    light.omni_attenuation = 1.35
    light.shadow_enabled = false
    world.add_child(light)
    lights.append(light)

func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var bar := ColorRect.new()
    bar.color = Color(0.035, 0.047, 0.052, .82)
    bar.position = Vector2(28, 24)
    bar.size = Vector2(455, 78)
    layer.add_child(bar)
    var accent := ColorRect.new()
    accent.color = Color("b8893f")
    accent.position = Vector2(28, 24)
    accent.size = Vector2(5, 78)
    layer.add_child(accent)
    var title := Label.new()
    title.position = Vector2(48, 32)
    title.text = str(district.name)
    title.add_theme_font_size_override("font_size", 20)
    title.add_theme_color_override("font_color", Color("e9dfc8"))
    title.add_theme_color_override("font_outline_color", Color(0, 0, 0, .8))
    title.add_theme_constant_override("outline_size", 3)
    layer.add_child(title)
    var sub := Label.new()
    sub.position = Vector2(48, 62)
    sub.text = "新独立街区 · 田径场 / 市集 / 可进入别墅"
    sub.add_theme_font_size_override("font_size", 13)
    sub.add_theme_color_override("font_color", Color("aab7b1"))
    layer.add_child(sub)
    hud_hint = Label.new()
    hud_hint.text = "WASD 移动 · Shift 奔跑 · Q/E 环绕 · E 楼梯上下楼 · 滚轮缩放 · R 回到入口 · Esc 退出"
    hud_hint.add_theme_font_size_override("font_size", 15)
    hud_hint.add_theme_color_override("font_color", Color("d8d4c3"))
    hud_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
    hud_hint.add_theme_constant_override("outline_size", 4)
    layer.add_child(hud_hint)

func _process(delta: float) -> void:
    if not is_instance_valid(player):
        return
    var inside := inside_villa()
    var upper := inside and player.position.y > float(modules.villa_courtyard.get("upper_y", 99.0))
    if inside != inside_state or upper != upper_state:
        inside_state = inside
        upper_state = upper
        apply_villa_cutaway(inside)
    if not preview_locked:
        if Input.is_key_pressed(KEY_Q):
            camera_yaw -= delta * 1.4
        if Input.is_key_pressed(KEY_E):
            camera_yaw += delta * 1.4
        target_zoom = clampf(target_zoom, float(district.camera.min_zoom),
            float(district.camera.max_zoom))
        camera_zoom = lerpf(camera_zoom, target_zoom, 1.0 - exp(-delta * 10.0))
    update_camera(delta)
    if hud_hint:
        hud_hint.position = Vector2(30, get_viewport().get_visible_rect().size.y - 42)

func _physics_process(delta: float) -> void:
    if not is_instance_valid(player) or preview_locked:
        return
    var input := Vector3.ZERO
    if Input.is_key_pressed(KEY_W):
        input.z -= 1
    if Input.is_key_pressed(KEY_S):
        input.z += 1
    if Input.is_key_pressed(KEY_A):
        input.x -= 1
    if Input.is_key_pressed(KEY_D):
        input.x += 1
    var direction := input.normalized().rotated(Vector3.UP, camera_yaw)
    var speed := 4.8 if Input.is_key_pressed(KEY_SHIFT) else 2.8
    player.velocity.x = direction.x * speed
    player.velocity.z = direction.z * speed
    if not player.is_on_floor():
        player.velocity.y -= 18.0 * delta
    else:
        player.velocity.y = -.6
    player.move_and_slide()
    var speed_now := Vector2(player.velocity.x, player.velocity.z).length()
    if direction.length_squared() > .01:
        visual.rotation.y = lerp_angle(visual.rotation.y,
            atan2(direction.x, direction.z), 1.0 - exp(-delta * 14.0))
    if speed_now > 4.2:
        visual.sample("run", delta)
    elif speed_now > .25:
        visual.sample("move", delta)
    else:
        visual.sample("stand", delta)

func inside_villa() -> bool:
    if not district.has("villa"):
        return false
    var b: Dictionary = district.villa.inside_bounds
    return (player.position.x > float(b.min_x) and player.position.x < float(b.max_x)
        and player.position.z > float(b.min_z) and player.position.z < float(b.max_z))

func apply_villa_cutaway(cut: bool) -> void:
    for node in [villa_roof, villa_front, villa_east]:
        if is_instance_valid(node):
            node.visible = not cut
    if is_instance_valid(villa_upper):
        villa_upper.visible = (not cut) or upper_state

func update_camera(delta: float = 0.0) -> void:
    if not is_instance_valid(camera):
        return
    var focus := player.position + Vector3(0, float(district.camera.focus_height), 0)
    var size := camera_zoom
    if inside_state:
        var p: Array = (district.villa.get("upper_focus", district.villa.interior_focus)
            if upper_state else district.villa.interior_focus)
        focus = Vector3(p[0], p[1], p[2])
        size = float(district.villa.get("upper_size", district.villa.interior_size)
            if upper_state else district.villa.interior_size)
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
    var offset: Array = district.camera.offset
    camera.position = camera_focus + Vector3(offset[0], offset[1], offset[2]).rotated(Vector3.UP, camera_yaw)
    camera.look_at(camera_focus)

func _unhandled_input(event: InputEvent) -> void:
    if preview_locked:
        return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            target_zoom = clampf(target_zoom - 1.8, float(district.camera.min_zoom), float(district.camera.max_zoom))
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            target_zoom = clampf(target_zoom + 1.8, float(district.camera.min_zoom), float(district.camera.max_zoom))
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_E and _near_stairs():
            _use_stairs()
            return
        if event.keycode == KEY_R:
            reset_player()
        elif event.keycode == KEY_ESCAPE:
            get_tree().quit()

func _villa_point(local: Vector3) -> Vector3:
    var p: Array = district.villa.position
    return Vector3(p[0], p[1], p[2]) + local

func _near_stairs() -> bool:
    var flat := Vector2(player.position.x, player.position.z)
    return (flat.distance_to(Vector2(_villa_point(STAIR_BOTTOM_LOCAL).x,
            _villa_point(STAIR_BOTTOM_LOCAL).z)) < 1.4
        or flat.distance_to(Vector2(_villa_point(STAIR_TOP_LOCAL).x,
            _villa_point(STAIR_TOP_LOCAL).z)) < 1.4)

func _use_stairs() -> void:
    if player.position.y > float(modules.villa_courtyard.get("upper_y", 99.0)):
        player.position = _villa_point(STAIR_BOTTOM_LOCAL)
    else:
        player.position = _villa_point(STAIR_TOP_LOCAL)
    player.velocity = Vector3.ZERO
    camera_ready = false

func reset_player() -> void:
    var spawn: Array = district.spawn
    player.position = Vector3(spawn[0], spawn[1], spawn[2])
    player.velocity = Vector3.ZERO
    player.rotation.y = deg_to_rad(float(district.spawn_yaw))
    camera_yaw = 0.0
    target_zoom = float(district.camera.size)
    camera_zoom = target_zoom
    preview_locked = false
    camera_ready = false
    inside_state = false
    upper_state = false
    apply_villa_cutaway(false)

func teleport_player(position: Vector3) -> void:
    player.position = position
    player.velocity = Vector3.ZERO
    camera_ready = false

func preview_view(focus: Vector3, size: float, yaw_degrees: float) -> void:
    preview_locked = true
    preview_focus = focus
    preview_size = size
    preview_yaw = deg_to_rad(yaw_degrees)
    update_camera(0.0)
