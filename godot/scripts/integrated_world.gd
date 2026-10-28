extends "res://scripts/game.gd"
## Connected east expansion: original street + District 07 + Halvorsen Works.
##
## This is an additive scene.  The original street, rules, saves and tests are
## untouched; this script extends the existing game world eastward, opens the
## old boundary, and adds custom search points in the new interiors.

const DISTRICT_PATH := "res://data/district_layout.json"
const SIMPLE_PATH := "res://data/simple_locations.json"
const FACTORY_PATH := "res://data/factory_layout.json"

const COMMONS_AT := Vector3(90.0, 0.0, -22.5)
const TRACK_AT := Vector3(90.0, 0.0, -47.5)
const MARKET_AT := Vector3(67.0, 0.0, -14.5)
const VILLA_AT := Vector3(114.0, 0.0, -14.5)
const FACTORY_AT := Vector3(165.5, 0.0, 22.0)

const VILLA_INNER := Rect2(109.65, -26.35, 12.70, 8.70)
const MARKET_INNER := Rect2(51.4, -27.0, 31.2, 25.0)
const FACTORY_INNER := Rect2(152.95, 15.25, 25.10, 14.20)
const VILLA_UPPER_Y := 2.15
const STAIR_LABEL_POS := Vector3(110.40, 2.25, -18.10)

const WORLD = preload("res://scripts/connected_model.gd")

var district_data: Dictionary = {}
var simple_data: Dictionary = {}
var factory_data: Dictionary = {}
var commons_instance: Node3D
var track_instance: Node3D
var market_instance: Node3D
var villa_instance: Node3D
var factory_instance: Node3D
var villa_roof: Node3D
var villa_front: Node3D
var villa_east: Node3D
var villa_upper: Node3D
var factory_roof: Node3D
var factory_south: Node3D
var factory_east: Node3D
var custom_containers: Array[Dictionary] = []
var custom_labels: Array[Label3D] = []
var module_lights: Array[OmniLight3D] = []
var stair_label: Label3D
var bed_label: Label3D
var preview_locked := false
var preview_focus := Vector3.ZERO
var preview_size := 30.0
var preview_yaw := 0.0
var expedition
var assembling:=false
var far_elapsed: Dictionary={}
var simulated_near:=0
var simulated_far:=0
var map_toggle: Button

func _ready() -> void:
    model = WORLD.new()
    store = Store.new("user://saves/east_expanse_v1")
    export_directory = "user://exports/east_expanse_v1"
    visual_slice_v1 = true
    district_data = JSON.parse_string(FileAccess.get_file_as_string(DISTRICT_PATH))
    simple_data = JSON.parse_string(FileAccess.get_file_as_string(SIMPLE_PATH))
    factory_data = JSON.parse_string(FileAccess.get_file_as_string(FACTORY_PATH))
    if district_data.is_empty() or simple_data.is_empty() or factory_data.is_empty():
        push_error("Connected world layout data is missing")
    super._ready()
    expedition=preload("res://scripts/expedition_panel.gd").new()
    add_child(expedition)
    expedition.setup(self)
    var map_button:=Button.new()
    map_toggle=map_button
    map_button.text="地图 [Tab]"
    map_button.position=Vector2(16,100)
    map_button.pressed.connect(func():
        if active: open_panel("map"))
    expedition.add_child(map_button)
    button(menu,"导入旧街区存档（原快照保留）",import_street_save)

func import_street_save() -> void:
    var previous=Store.new("user://saves")
    if not previous.load_latest(model):
        notice.text=previous.last_error
        return
    build_world()
    active=true
    menu.hide()
    close_panel()
    last_notice="旧快照已在内存升级；F5将另存到整图目录。"

func show_menu() -> void:
    super.show_menu()
    hud.text="DEAD DAYS / 灰湾与东部连片区域\n市集、别墅、操场与工厂已接入；整图快照独立保存。"
    hint.text="WASD 移动 · Shift 跑步 · E 搜刮 · B 存取 · I 背包 · Tab 地图 · J 日志 · F5 保存"

func _physics_process(delta: float) -> void:
    if expedition!=null and expedition.is_open(): return
    super._physics_process(delta)
    if active and not model.state.is_empty(): model.discover(player.position)

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and active:
        if expedition!=null and expedition.is_open():
            if event.keycode in [KEY_ESCAPE,KEY_I,KEY_B,KEY_TAB]: expedition.close()
            return
        if event.keycode==KEY_TAB:
            open_panel("map")
            return
    super._unhandled_key_input(event)

func open_panel(kind: String) -> void:
    if expedition!=null and kind in ["inventory","storage","map"]:
        model.discover(player.position)
        panel.hide()
        expedition.open(kind,storage_container)
        return
    super.open_panel(kind)

func close_panel() -> void:
    if expedition!=null: expedition.close()
    super.close_panel()

func new_run() -> void:
    super.new_run()
    last_notice = "东侧道路已接通 DISTRICT 07 与 HALVORSEN WORKS；E 搜刮柜子和摊位。"

func continue_run() -> void:
    super.continue_run()
    if active:
        last_notice = "已载入连片街区；东侧道路可前往市集、别墅与工厂。"

func build_world() -> void:
    assembling=true
    far_elapsed.clear()
    super.build_world()
    _extend_east()
    assembling=false
    var clear: Vector3 = safe_position(player.position)
    if clear.distance_to(player.position)>.01:
        player.position=clear
        sync_position()
        model.event("layout_adjusted","整图陈设更新，移到附近可通行位置。")
    update_camera(0)
    for zombie in zombie_bodies:
        zombie.show_state_label = false
        if zombie.record.health<=0: continue
        var safe:=safe_position(zombie.position)
        zombie.position=safe
        zombie.write_position()

func tick_world(seconds: float, sleeping: bool) -> void:
    model.tick_combat(seconds)
    model.advance_time(seconds,sleeping)
    simulated_near=0
    simulated_far=0
    var policy: Dictionary=model.world_definition.simulation
    for zombie in zombie_bodies:
        var distance: float=zombie.position.distance_to(player.position)
        zombie.visible=distance<minf(float(policy.render_radius),enemy_distance)
        if zombie.record.health<=0: continue
        var urgent: bool=zombie.record.mode!="wander" or distance<float(policy.active_radius)
        for noise in model.state.noises:
            var p: Array=noise.position
            if zombie.position.distance_to(Vector3(p[0],p[1],p[2]))<=float(noise.radius): urgent=true
        if urgent:
            zombie.tick(seconds)
            far_elapsed.erase(zombie.record.id)
            simulated_near+=1
        else:
            var elapsed: float=float(far_elapsed.get(zombie.record.id,0))+seconds
            if elapsed>=float(policy.far_tick_seconds):
                zombie.tick(elapsed)
                elapsed=0
                simulated_far+=1
            far_elapsed[zombie.record.id]=elapsed
    if sleeping:
        model.state.stats.stamina=minf(100,model.state.stats.stamina+float(model.rules.stamina_recovery)*seconds)

func safe_position(at: Vector3) -> Vector3:
    # Base assembly has not attached the extension yet. Do not reinterpret its saved floor.
    if at.x>34.5 and not is_instance_valid(factory_instance): return at
    return super.safe_position(at)

func _extend_east() -> void:
    custom_containers.clear()
    custom_labels.clear()
    module_lights.clear()
    _open_east_boundary()
    _add_extension_ground()
    _add_connector_roads()
    commons_instance = _attach_commons()
    track_instance = _attach_module("track_field", TRACK_AT)
    market_instance = _attach_module("market_square", MARKET_AT)
    villa_instance = _attach_module("villa_courtyard", VILLA_AT)
    factory_instance = _attach_factory()
    _bind_villa_cutaway()
    _bind_factory_cutaway()
    _add_stair_wedge(VILLA_AT)
    _add_district_lights()
    _add_signs()
    _add_stairs_label()
    _add_villa_bed()
    _register_custom_containers()
    _rebuild_navigation()

func _rebuild_navigation() -> void:
    var rule: Dictionary = model.world_definition.navigation
    navigation.rebuild(nav_sources, rule)

func apply_door(id: String, impact: bool = false) -> void:
    super.apply_door(id, impact)
    if not assembling: call_deferred("refresh_door_navigation", id)

func _open_east_boundary() -> void:
    var b: Dictionary = model.rules.street_bounds
    var edge_x := float(b.max_x)
    for child in world.get_children():
        if child is StaticBody3D and absf(child.position.x - edge_x) < .05:
            for i in range(nav_sources.size() - 1, -1, -1):
                if nav_sources[i].body == child:
                    nav_sources.remove_at(i)
            child.queue_free()
    # New far boundary of the extended world.
    _collider_box("east_world_edge", Vector3(195.0, 1.4, -22.0),
        Vector3(.4, 2.8, 108.0))
    _collider_box("north_world_edge", Vector3(114.0, 1.4, -76.0),
        Vector3(162.0, 2.8, .4))
    _collider_box("south_world_edge", Vector3(114.0, 1.4, 48.0),
        Vector3(162.0, 2.8, .4))

func _add_extension_ground() -> void:
    var ground := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(216.0, .18, 124.0)
    ground.mesh = box
    ground.position = Vector3(100.0, -.10, -14.0)
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("66704b")
    mat.roughness = 1.0
    ground.material_override = mat
    world.add_child(ground)
    var backdrop := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(520, 420)
    backdrop.mesh = plane
    backdrop.position = Vector3(100.0, -.20, -14.0)
    var backdrop_mat := StandardMaterial3D.new()
    backdrop_mat.albedo_color = Color("5e6947")
    backdrop_mat.roughness = 1.0
    backdrop.material_override = backdrop_mat
    world.add_child(backdrop)
    _collider_box("extension_ground", Vector3(100.0, -.21, -14.0),
        Vector3(216.0, .40, 124.0))

func _add_connector_roads() -> void:
    _road(Vector3(37.9, .035, 3.0), Vector3(7.2, .07, 4.7))
    _road(Vector3(140.4, .035, 1.5), Vector3(3.2, .07, 3.8))
    _road(Vector3(155.0, .035, .0), Vector3(31.0, .07, 4.0))
    _road(Vector3(170.0, .035, 1.5), Vector3(4.0, .07, 3.8))
    for x in [36.5, 39.5]:
        _paint_line(Vector3(x, .075, 3.0), Vector3(.10, .008, 4.5))
    for z in [-1.2, .0, 1.2]:
        _paint_line(Vector3(155.0, .075, z), Vector3(31.0, .008, .10))
    for z in [.4, 1.4]:
        _paint_line(Vector3(170.0, .075, z), Vector3(.10, .008, .8))

func _road(at: Vector3, size: Vector3) -> void:
    var road := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    road.mesh = mesh
    road.position = at
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("252a2c")
    mat.roughness = .94
    road.material_override = mat
    world.add_child(road)

func _paint_line(at: Vector3, size: Vector3) -> void:
    var line := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    line.mesh = mesh
    line.position = at
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color("d2c7a7")
    mat.roughness = .8
    line.material_override = mat
    world.add_child(line)

func _attach_commons() -> Node3D:
    var node := Assets.attach(world, "district_commons", COMMONS_AT)
    node.name = "DistrictCommons"
    for definition in district_data.commons_colliders:
        var p: Array = definition.position
        var s: Array = definition.size
        _collider_box(str(definition.id), COMMONS_AT + Vector3(p[0], p[1], p[2]),
            Vector3(s[0], s[1], s[2]))
    return node

func _attach_module(asset: String, at: Vector3) -> Node3D:
    var node := Assets.attach(world, asset, at)
    node.name = "Module_" + asset
    var layout: Dictionary = simple_data.locations[asset]
    for definition in layout.colliders:
        var p: Array = definition.position
        var s: Array = definition.size
        _collider_box(str(definition.id), at + Vector3(p[0], p[1], p[2]),
            Vector3(s[0], s[1], s[2]))
    for ramp in layout.get("ramps", []):
        var rp: Array = ramp.position
        _ramp_body(str(ramp.id), at + Vector3(rp[0], rp[1], rp[2]), ramp.size,
            float(ramp.get("rotation_x", 0.0)))
    for definition in layout.get("lights", []):
        _module_light(definition, at)
    return node

func _attach_factory() -> Node3D:
    var node := Assets.attach(world, "factory_grounds", FACTORY_AT)
    node.name = "HalvorsenIronworks"
    for definition in factory_data.colliders:
        var p: Array = definition.position
        var s: Array = definition.size
        _collider_box(str(definition.id), FACTORY_AT + Vector3(p[0], p[1], p[2]),
            Vector3(s[0], s[1], s[2]))
    for definition in factory_data.get("lights", []):
        _module_light(definition, FACTORY_AT)
    return node

func _collider_box(id: String, at: Vector3, size: Vector3) -> void:
    var body := StaticBody3D.new()
    body.name = "ExtensionCollider_" + id
    body.collision_layer = 1
    body.collision_mask = 0
    body.position = at
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = size
    shape.shape = box
    body.add_child(shape)
    world.add_child(body)
    if size.y > .55 and at.y + size.y * .5 > .30:
        nav_sources.append({
            "body": body,
            "rect": Rect2(at.x - size.x * .5, at.z - size.z * .5,
                size.x, size.z),
        })

func _ramp_body(id: String, at: Vector3, size: Array, rotation_x: float) -> void:
    var body := StaticBody3D.new()
    body.name = "ExtensionRamp_" + id
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

func _module_light(definition: Dictionary, at: Vector3) -> void:
    var p: Array = definition.position
    var light := OmniLight3D.new()
    light.position = at + Vector3(p[0], p[1], p[2])
    light.light_color = Color(str(definition.color))
    light.light_energy = float(definition.energy)
    light.omni_range = float(definition.range)
    light.omni_attenuation = 1.4
    light.shadow_enabled = false
    world.add_child(light)
    module_lights.append(light)

func _add_district_lights() -> void:
    for definition in district_data.get("lights", []):
        _module_light(definition, COMMONS_AT)

func _bind_villa_cutaway() -> void:
    var cut: Dictionary = simple_data.locations.villa_courtyard.cutaway
    villa_roof = villa_instance.find_child(str(cut.roof), true, false)
    villa_front = villa_instance.find_child(str(cut.front), true, false)
    villa_east = villa_instance.find_child(str(cut.east), true, false)
    if cut.has("upper"):
        villa_upper = villa_instance.find_child(str(cut.upper), true, false)

func _bind_factory_cutaway() -> void:
    var cut: Dictionary = factory_data.cutaway
    factory_roof = factory_instance.find_child(str(cut.roof), true, false)
    factory_south = factory_instance.find_child(str(cut.south_wall), true, false)
    factory_east = factory_instance.find_child(str(cut.east_wall), true, false)

func _add_signs() -> void:
    _label3("东区  /  DISTRICT 07  →", Vector3(37.6, 2.5, 5.2))
    _label3("HALVORSEN  WORKS  ↓", Vector3(166.0, 2.9, -1.0))
    _label3("市集  /  MARKET", Vector3(67.0, 2.4, -2.0))
    _label3("别墅  /  VILLA 07", Vector3(114.0, 5.9, -2.0))

func _label3(text: String, at: Vector3) -> void:
    var label := Label3D.new()
    label.text = text
    label.position = at
    label.font_size = 26
    label.pixel_size = .014
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color("e8ddc1")
    label.outline_size = 4
    world.add_child(label)

func _add_stair_wedge(at: Vector3) -> void:
    var w: Dictionary = simple_data.locations.villa_courtyard.stair_wedge
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

func _add_stairs_label() -> void:
    stair_label = Label3D.new()
    stair_label.text = "楼梯  /  二楼"
    stair_label.position = STAIR_LABEL_POS
    stair_label.font_size = 21
    stair_label.pixel_size = .011
    stair_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    stair_label.modulate = Color("f0dfb6")
    stair_label.outline_size = 3
    world.add_child(stair_label)

func _add_villa_bed() -> void:
    var bed_id := "villa_upstairs_bed"
    var known := false
    for definition in model.rules.beds:
        if str(definition.id) == bed_id:
            known = true
            break
    if not known:
        model.rules.beds.append({
            "id": bed_id,
            "building": "villa_07",
            "position": [119.55, 3.62, -24.78],
            "use_radius": 2.0,
            "area": {"min_x": 109.65, "max_x": 122.35,
                     "min_z": -26.35, "max_z": -17.65,
                     "min_y": 2.15, "max_y": 6.0},
        })
    bed_label = Label3D.new()
    bed_label.text = "二楼床  [R/T]"
    bed_label.position = Vector3(119.55, 4.85, -24.78)
    bed_label.font_size = 21
    bed_label.pixel_size = .011
    bed_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    bed_label.modulate = Color("f0dfb6")
    bed_label.outline_size = 3
    world.add_child(bed_label)

func _register_custom_containers() -> void:
    for definition in model.world_definition.containers:
        var pos: Array = definition.position
        var at := Vector3(pos[0], pos[1], pos[2])
        custom_containers.append({
            "id": str(definition.id),
            "name": str(definition.name),
            "area": str(definition.area),
            "position": at,
            "label": _container_label(str(definition.name), at),
        })

func _rules_has_container(id: String) -> bool:
    for definition in model.rules.containers:
        if str(definition.id) == id:
            return true
    return false

func _container_label(text: String, at: Vector3) -> Label3D:
    var label := Label3D.new()
    label.text = text + "  [E]"
    label.position = at + Vector3.UP * 1.35
    label.font_size = 21
    label.pixel_size = .011
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.modulate = Color("f0dfb6")
    label.outline_size = 3
    world.add_child(label)
    custom_labels.append(label)
    return label

func _area_contains(area: String, p: Vector3) -> bool:
    match area:
        "villa":
            return VILLA_INNER.has_point(Vector2(p.x, p.z)) and p.y < 6.7
        "market":
            return MARKET_INNER.has_point(Vector2(p.x, p.z)) and p.y < 1.8
        "factory":
            return FACTORY_INNER.has_point(Vector2(p.x, p.z)) and p.y < 4.4
    return false

func _inside_villa() -> bool:
    return VILLA_INNER.has_point(Vector2(player.position.x, player.position.z)) and player.position.y < 6.7

func _inside_factory() -> bool:
    return FACTORY_INNER.has_point(Vector2(player.position.x, player.position.z)) and player.position.y < 4.4

func nearby() -> Dictionary:
    var best: Dictionary = super.nearby()
    var closest := float(model.rules.interaction_range)
    for container in custom_containers:
        if not _area_contains(str(container.area), player.position):
            continue
        var at: Vector3 = container.position
        if absf(player.position.y - at.y) > 1.65:
            continue
        var offset := Vector2(player.position.x - at.x, player.position.z - at.z)
        if offset.length() < closest and container_line_clear(str(container.id), at):
            closest = offset.length()
            best = {"id": str(container.id), "kind": "container"}
    return best

func update_camera(delta: float = 0.0) -> void:
    if preview_locked:
        _preview_camera()
        return
    if _inside_villa() or _inside_factory():
        _module_camera(delta)
        return
    super.update_camera(delta)

func _preview_camera() -> void:
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = .05
    camera.size = preview_size
    camera.position = preview_focus + Vector3(11, 15, 14).rotated(Vector3.UP, preview_yaw)
    camera.look_at(preview_focus)
    camera_focus = preview_focus
    camera_initialized = true

func preview_view(focus: Vector3, size: float, yaw_degrees: float) -> void:
    preview_locked = true
    preview_focus = focus
    preview_size = size
    preview_yaw = deg_to_rad(yaw_degrees)
    _preview_camera()

func teleport_player(at: Vector3) -> void:
    player.position = at
    player.velocity = Vector3.ZERO
    camera_initialized = false

func _module_camera(delta: float) -> void:
    if not is_instance_valid(camera):
        return
    camera_inside = false
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.near = .05
    player_visual.visible = true
    var focus := Vector3.ZERO
    var size := 14.0
    if _inside_villa():
        var upstairs := player.position.y > VILLA_UPPER_Y
        focus = Vector3(116.0, 4.55 if upstairs else 1.25, -21.9)
        size = 13.5
    else:
        focus = Vector3(165.5, 1.25, 22.0)
        size = 13.0
    var blend := 1.0 if not camera_initialized or delta <= 0.0 else 1.0 - exp(-delta * 7.0)
    camera_focus = camera_focus.lerp(focus, blend)
    camera.size = lerpf(camera.size, size, blend)
    camera.position = camera_focus + Vector3(11, 15, 14).rotated(Vector3.UP, camera_yaw)
    camera.look_at(camera_focus)
    camera_initialized = true

func update_cutaways() -> void:
    super.update_cutaways()
    var in_villa := _inside_villa()
    var upstairs := in_villa and player.position.y > VILLA_UPPER_Y
    if is_instance_valid(villa_roof):
        villa_roof.visible = not in_villa
    if is_instance_valid(villa_front):
        villa_front.visible = not in_villa
    if is_instance_valid(villa_east):
        villa_east.visible = not in_villa
    if is_instance_valid(villa_upper):
        villa_upper.visible = (not in_villa) or upstairs
    var in_factory := _inside_factory()
    for node in [factory_roof, factory_south, factory_east]:
        if is_instance_valid(node):
            node.visible = not in_factory
    for container in custom_containers:
        var label: Label3D = container.label
        if not is_instance_valid(label):
            continue
        var at: Vector3 = container.position
        label.visible = (player.position.distance_to(at) < 9.0
            and absf(player.position.y - at.y) < 2.1)
    if is_instance_valid(stair_label):
        stair_label.visible = player.position.distance_to(STAIR_LABEL_POS) < 8.0
    if is_instance_valid(bed_label):
        bed_label.visible = player.position.distance_to(bed_label.position) < 6.0
