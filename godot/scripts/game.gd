extends Node3D
const Assets = preload("res://scripts/asset_library.gd")
const CharacterVisual = preload("res://scripts/character_visual.gd")
const Timeline = preload("res://scripts/survival_time.gd")
const Rest = preload("res://scripts/rest.gd")
const Model = preload("res://scripts/survival.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Zombie = preload("res://scripts/zombie.gd")
const Store = preload("res://scripts/save_store.gd")
var model = Model.new()
var store = Store.new()
var active := false
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var doors := {}
var nav_sources: Array = []
var navigation = Navigation.new()
var zombie_bodies: Array = []
var run_noise_left := 0.0
var player_visual: Node3D
var building_visuals: Dictionary = {}
var door_visuals: Dictionary = {}
var open_leaves: Dictionary = {}
var hud: Label
var hint: Label
var notice: Label
var menu: VBoxContainer
var panel: VBoxContainer
var journal_text: RichTextLabel
var entry: LineEdit
var mood: OptionButton
var inventory_actions: HBoxContainer
var write_button: Button
var export_button: Button
var panel_kind := ""
var last_notice := ""
var export_directory := "user://exports"

func _ready() -> void:
    bind("left", KEY_A)
    bind("right", KEY_D)
    bind("forward", KEY_W)
    bind("back", KEY_S)
    bind("run", KEY_SHIFT)
    bind("attack", KEY_SPACE)
    get_tree().auto_accept_quit = false
    build_ui()
    show_menu()

func bind(action: String, code: int) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var key := InputEventKey.new()
    key.physical_keycode = code
    InputMap.action_add_event(action, key)

func button(parent: Control, caption: String, callback: Callable) -> Button:
    var b := Button.new()
    b.text = caption
    b.pressed.connect(callback)
    parent.add_child(b)
    return b

func build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var shade := ColorRect.new()
    shade.color = Color(0.03, 0.04, 0.06, 0.88)
    shade.position = Vector2(16, 14)
    shade.size = Vector2(1120, 108)
    shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(shade)
    hud = Label.new()
    hud.position = Vector2(30, 20)
    hud.add_theme_font_size_override("font_size", 19)
    layer.add_child(hud)
    hint = Label.new()
    hint.position = Vector2(30, 625)
    layer.add_child(hint)
    notice = Label.new()
    notice.position = Vector2(30, 660)
    layer.add_child(notice)
    menu = VBoxContainer.new()
    menu.position = Vector2(395, 200)
    menu.custom_minimum_size = Vector2(360, 0)
    layer.add_child(menu)
    var title := Label.new()
    title.text = "DEAD DAYS / 末日生存日志\n阶段 C3 · 低多边形街区"
    title.add_theme_font_size_override("font_size", 26)
    menu.add_child(title)
    button(menu, "新游戏（保留所有已有快照）", new_run)
    button(menu, "继续最近有效存档", continue_run)
    button(menu, "退出", func(): get_tree().quit())
    panel = VBoxContainer.new()
    panel.position = Vector2(300, 150)
    panel.custom_minimum_size = Vector2(720, 0)
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.04, 0.05, 0.07, 0.98)
    # Draw on the VBox itself: a Panel child would be resized to zero height by the container.
    panel.draw.connect(func(): panel.draw_style_box(style, Rect2(Vector2(-16, -12), panel.size + Vector2(32, 24))))
    panel.resized.connect(panel.queue_redraw)
    layer.add_child(panel)
    journal_text = RichTextLabel.new()
    journal_text.custom_minimum_size = Vector2(700, 330)
    panel.add_child(journal_text)
    entry = LineEdit.new()
    entry.placeholder_text = "写下真实经历（最多500字）"
    entry.max_length = 500
    panel.add_child(entry)
    mood = OptionButton.new()
    for text in ["平静", "疲惫", "恐惧", "希望", "绝望"]:
        mood.add_item(text)
    panel.add_child(mood)
    write_button = button(panel, "写入日志", func():
        model.manual(entry.text, mood.get_item_text(mood.selected))
        entry.clear()
        refresh_panel())
    export_button = button(panel, "导出 Markdown", export_journal)
    inventory_actions = HBoxContainer.new()
    panel.add_child(inventory_actions)
    for id in model.rules.items:
        button(inventory_actions, ("装备" if model.rules.items[id].get("kind", "") == "weapon" else "使用") + model.rules.items[id].name, func():
            use(id)
            refresh_panel())
    button(panel, "关闭 [I / J / Esc]", close_panel)
    panel.hide()

func show_menu() -> void:
    active = false
    menu.show()
    panel.hide()
    hud.text = "DEAD DAYS  /  重构分支\n新旧存档隔离；昼夜与生存时钟已接入。住宅床边可R短休、T睡到黎明。"
    hint.text = "WASD 移动 · Shift 跑步 · 空格攻击 · E 开关门/搜刮 · I 背包 · J 日志 · 1/2/3 使用物品 · F5 保存 · Esc 保存回菜单"

func new_run() -> void:
    model.start()
    build_world()
    active = true
    menu.hide()
    close_panel()
    last_notice = "先搜刮住宅的木棍并装备；街道东端有僵尸。跑步和战斗会引来注意。"

func continue_run() -> void:
    if not store.load_latest(model):
        notice.text = store.last_error
        return
    build_world()
    active = true
    menu.hide()
    close_panel()
    last_notice = "读档成功，已恢复位置、门、容器、背包及日志。"

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid: bool = true) -> Node3D:
    var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
    parent.add_child(root)
    root.position = pos
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    visual.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.albedo_color = color
    mat.roughness = 1.0
    visual.material_override = mat
    root.add_child(visual)
    if solid:
        var collision := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        collision.shape = shape
        root.add_child(collision)
    if solid and parent == world and pos.y + size.y * 0.5 > 0.3:
        nav_sources.append({"body": root, "rect": Rect2(Vector2(pos.x - size.x * 0.5, pos.z - size.z * 0.5), Vector2(size.x, size.z))})
    return root

func label3(parent: Node3D, text: String, pos: Vector3) -> void:
    var label := Label3D.new()
    label.text = text
    label.position = pos
    label.font_size = 38
    label.pixel_size = 0.012
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    parent.add_child(label)

func build_world() -> void:
    if is_instance_valid(world):
        remove_child(world)
        world.queue_free()
    doors.clear()
    building_visuals.clear()
    door_visuals.clear()
    open_leaves.clear()
    nav_sources.clear()
    zombie_bodies.clear()
    run_noise_left = 0
    world = Node3D.new()
    add_child(world)
    box(world, Vector3(0, -0.25, -1), Vector3(27, 0.5, 19), Color("49594a"))
    box(world, Vector3(0, 0.015, 3), Vector3(26, 0.03, 4), Color("454b50"), false)
    for x in range(-12, 13, 3):
        box(world, Vector3(x, 0.04, 3), Vector3(1, 0.03, 0.1), Color("c7bb87"), false)
    for b in model.rules.buildings:
        var x: float = b.x
        building_visuals[b.id] = Assets.attach(world, b.asset, Vector3(x, 0, 0))
        collision_box(Vector3(x, 1.3, -5), Vector3(5.7, 2.6, 0.2))
        collision_box(Vector3(x - 2.75, 1.3, -2.5), Vector3(0.2, 2.6, 5))
        collision_box(Vector3(x + 2.75, 1.3, -2.5), Vector3(0.2, 2.6, 5))
        for side in [-1, 1]:
            collision_box(Vector3(x + side * 1.85, 1.3, 0), Vector3(1.9, 2.6, 0.2))
        doors[b.id] = collision_box(Vector3(x, 1, 0), Vector3(1.7, 2, 0.16))
        door_visuals[b.id] = Assets.attach(doors[b.id], "door", Vector3(-0.85, -1, 0))
        open_leaves[b.id] = collision_box(Vector3(x - 0.85, 1, 0.85), Vector3(0.16, 2, 1.7))
        open_leaves[b.id].collision_layer = 0
        var container_body := collision_box(Vector3(x, 0.5, -3), Vector3(1.2, 1, 0.7))
        Assets.attach(container_body, b.container_asset, Vector3(0, -0.5, 0))
        label3(world, b.name, Vector3(x, 3.8, -5))
        label3(world, "柜子 [E]", Vector3(x, 1.5, -3))
        apply_door(b.id)
    for definition in model.rules.beds:
        var position: Vector3 = Rest.bed_position(model, definition)
        var size := Vector3(definition.size[0], definition.size[1], definition.size[2])
        var bed := collision_box(position + Vector3.UP * (size.y * 0.5), size)
        Assets.attach(bed, "bed", Vector3(0, -size.y * 0.5, 0))
        label3(world, "床 [R/T]", position + Vector3.UP * 1.5)
    for furniture in model.rules.furniture:
        for building in model.rules.buildings:
            if furniture.building == building.id:
                var size := Vector3(furniture.size[0], furniture.size[1], furniture.size[2])
                var position := Vector3(building.x + furniture.offset[0], size.y * 0.5, furniture.offset[2])
                var body := collision_box(position, size)
                Assets.attach(body, furniture.asset, Vector3(0, -size.y * 0.5, 0))
    # Boundary bodies prevent leaving the playable block.
    for x in [-13.5, 13.5]:
        box(world, Vector3(x, 1, -1), Vector3(0.3, 2, 19), Color("36433a"))
    for z in [-10.5, 8.5]:
        box(world, Vector3(0, 1, z), Vector3(27, 2, 0.3), Color("36433a"))
    player = CharacterBody3D.new()
    player.name = "Survivor"
    player.collision_layer = 2
    player.collision_mask = 1 | 4
    world.add_child(player)
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = model.rules.actor.radius
    capsule.height = model.rules.actor.height
    shape.shape = capsule
    shape.position.y = model.rules.actor.center_y
    player.add_child(shape)
    player_visual = CharacterVisual.new()
    player.add_child(player_visual)
    player_visual.setup("player")
    player_visual.position.y = float(model.rules.actor.center_y) - float(model.rules.actor.height) * 0.5
    var p: Array = model.state.position
    player.position = Vector3(p[0], p[1], p[2])
    player.rotation.y = model.state.combat.facing
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 19
    world.add_child(camera)
    camera.current = true
    update_camera()
    sun = DirectionalLight3D.new()
    var light := sun
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.light_energy = 1.1
    light.shadow_enabled = true
    world.add_child(light)
    environment = WorldEnvironment.new()
    var env := environment
    env.environment = Environment.new()
    env.environment.background_mode = Environment.BG_COLOR
    env.environment.background_color = Color("19232b")
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color("c6d7e6")
    env.environment.ambient_light_energy = 0.65
    world.add_child(env)
    navigation.rebuild(nav_sources, model.rules.navigation)
    var safe := safe_position(player.position)
    if safe.distance_to(player.position) > 0.01:
        player.position = safe
        sync_position()
        model.event("layout_adjusted", "室内陈设更新，已移到附近可通行的位置。", "平静")
    for record in model.state.zombies:
        var at := Vector3(record.position[0], record.position[1], record.position[2])
        var clear := safe_position(at) if record.health > 0 else at
        if clear.distance_to(at) > 0.01:
            record.position = [clear.x, clear.y, clear.z]
        var zombie = Zombie.new()
        world.add_child(zombie)
        zombie.setup(self, record)
        zombie_bodies.append(zombie)
    update_player_visual(0)
    update_cutaways()
    update_lighting()

func apply_door(id: String) -> void:
    var body: StaticBody3D = doors[id]
    var opened: bool = model.state.doors[id]
    body.collision_layer = 0 if opened else 1
    open_leaves[id].collision_layer = 1 if opened else 0
    door_visuals[id].rotation.y = -PI / 2 if opened else 0.0

func update_camera() -> void:
    camera.position = player.position + Vector3(11, 15, 14)
    camera.look_at(player.position + Vector3(0, 0.5, 0))

func nearby() -> Dictionary:
    var closest := float(model.rules.interaction_range)
    var target := {}
    for b in model.rules.buildings:
        for kind in ["door", "container"]:
            var pos := Vector3(b.x, 0, 0 if kind == "door" else -3)
            var distance := Vector2(player.position.x - pos.x, player.position.z - pos.z).length()
            # Containers may only be searched from inside their room.
            if kind == "container" and not inside(b.id):
                continue
            if distance < closest:
                closest = distance
                target = {"id": b.id, "kind": kind}
    return target

func inside(id: String) -> bool:
    return Rest.inside(model, id, player.position)

func interact() -> void:
    if model.state.stats.health <= 0 or model.state.rest.active:
        return
    var target := nearby()
    if target.is_empty():
        last_notice = "靠近门或屋内柜子后按 E。"
        return
    if target.kind == "door":
        if model.state.doors[target.id] and absf(player.position.z) < 0.6 and absf(player.position.x - doors[target.id].position.x) < 1.2:
            last_notice = "先离开门口，避免关门夹住自己。"
            return
        if model.state.doors[target.id]:
            for zombie in zombie_bodies:
                if zombie.record.health > 0 and absf(zombie.position.z) < 0.55 and absf(zombie.position.x - doors[target.id].position.x) < 1.15:
                    last_notice = "有僵尸挡在门洞，无法关门。"
                    return
        model.toggle_door(target.id)
        apply_door(target.id)
        navigation.rebuild(nav_sources, model.rules.navigation)
        model.noise(player.position, model.rules.noise.door_radius, "door")
        last_notice = model.state.events.back().text
    else:
        var count: int = model.loot(target.id)
        last_notice = "获得 %d 件物资；未带走的留在柜中。" % count if count else "柜子已空或负重不足。"

func sync_position() -> void:
    model.state.position = [player.position.x, player.position.y, player.position.z]
    model.state.combat.facing = player.rotation.y

func save_run() -> bool:
    sync_position()
    var path: String = store.save(model)
    last_notice = "已保存：" + path if not path.is_empty() else store.last_error
    return not path.is_empty()

func _physics_process(delta: float) -> void:
    if not active or panel.visible:
        return
    if model.state.stats.health <= 0:
        refresh_hud()
        return
    if model.state.rest.active:
        if Input.get_vector("left", "right", "forward", "back").length() > 0 or Input.is_action_pressed("attack"):
            Rest.cancel(model, "主动起身")
            last_notice = "已停止休息。"
        else:
            advance_rest(delta)
        update_player_visual(delta)
        update_lighting()
        refresh_hud()
        return
    var input := Input.get_vector("left", "right", "forward", "back")
    var running: bool = Input.is_action_pressed("run") and model.state.stats.stamina > 0
    var speed: float = model.rules.run_speed if running else model.rules.walk_speed
    player.velocity = Vector3(input.x * speed, -2.0, input.y * speed)
    player.move_and_slide()
    if input.length() > 0.1:
        player.rotation.y = lerp_angle(player.rotation.y, atan2(input.x, input.y), delta * 12)
    model.state.stats.stamina = clampf(model.state.stats.stamina + (-float(model.rules.stamina_run_cost) if running and input.length() > 0 else float(model.rules.stamina_recovery)) * delta, 0, 100)
    run_noise_left = maxf(0, run_noise_left - delta)
    if running and input.length() > 0 and run_noise_left <= 0:
        model.noise(player.position, model.rules.noise.run_radius, "running")
        run_noise_left = model.rules.noise.run_interval
    if Input.is_action_pressed("attack"):
        try_attack()
    sync_position()
    tick_world(delta, false)
    discover_zombies()
    update_player_visual(delta)
    for b in model.rules.buildings:
        if inside(b.id):
            model.enter(b.id)
    update_camera()
    update_cutaways()
    update_lighting()
    refresh_hud()

func tick_world(seconds: float, sleeping: bool) -> void:
    model.tick_combat(seconds)
    model.advance_time(seconds, sleeping)
    for zombie in zombie_bodies:
        zombie.tick(seconds)
    if sleeping:
        model.state.stats.stamina = minf(100, model.state.stats.stamina + float(model.rules.stamina_recovery) * seconds)

func advance_rest(delta: float) -> void:
    sync_position()
    var rule: Dictionary = model.rules.rest
    var budget: float = minf(delta * float(rule.acceleration), float(rule.step_seconds) * int(rule.max_steps_per_frame))
    for index in int(rule.max_steps_per_frame):
        if not model.state.rest.active or budget <= 0:
            break
        var blocked: String = Rest.reason(model, model.state.rest.bed)
        if not blocked.is_empty():
            Rest.cancel(model, blocked, "僵尸" in blocked)
            last_notice = "休息中断：" + blocked
            break
        var remaining: float = float(model.state.rest.target) - Timeline.absolute(model)
        if remaining <= 0.0000001:
            complete_rest()
            break
        var seconds: float = minf(minf(budget, float(rule.step_seconds)), remaining / float(model.rules.time.minutes_per_second))
        tick_world(seconds, true)
        budget -= seconds
        blocked = Rest.reason(model, model.state.rest.bed)
        if not blocked.is_empty():
            Rest.cancel(model, blocked, "僵尸" in blocked)
            last_notice = "休息中断：" + blocked
            break
        if Timeline.absolute(model) >= float(model.state.rest.target) - 0.0000001:
            complete_rest()
            break

func complete_rest() -> void:
    Rest.finish(model)
    var text: String = model.state.events.back().text
    if save_run():
        last_notice = text + " 已自动保存。"

func closest_bed() -> String:
    var nearest := ""
    var distance := INF
    for definition in model.rules.beds:
        var position: Vector3 = Rest.bed_position(model, definition)
        var d := Vector2(player.position.x - position.x, player.position.z - position.z).length()
        if d <= definition.use_radius and d < distance:
            distance = d
            nearest = definition.id
    return nearest

func request_rest(kind: String) -> void:
    if model.state.rest.active:
        Rest.cancel(model, "主动起身")
        last_notice = "已停止休息。"
        return
    sync_position()
    var blocked: String = Rest.begin(model, closest_bed(), kind)
    last_notice = blocked if not blocked.is_empty() else "正在加速休息；T或移动可起身，F5可保存。"

func update_lighting() -> void:
    var day: float = Timeline.daylight(model)
    sun.light_energy = lerpf(0.12, 1.1, day)
    sun.light_color = Color("8badd4").lerp(Color("fff1d4"), day)
    sun.rotation_degrees.x = lerpf(-12.0, -55.0, day)
    environment.environment.ambient_light_energy = lerpf(0.22, 0.65, day)
    environment.environment.background_color = Color("0c1524").lerp(Color("19232b"), day)

func refresh_hud() -> void:
    var rest_text: String = " · 正在休息" if model.state.rest.active else ""
    hud.text = "DEAD DAYS / 第%d天 %s · 阶段C3%s\n生命 %.0f  饱腹 %.0f  饮水 %.0f  体力 %.0f  负重 %.1f/%.1f kg  %s\nWASD 移动 · Shift跑步 · E交互 · I背包 · J日志 · 空格攻击 · 1/2/3使用 4装备 · R短休 T睡眠 · Esc菜单" % [model.state.day, Timeline.clock(model), rest_text, model.state.stats.health, model.state.stats.hunger, model.state.stats.thirst, model.state.stats.stamina, model.weight(), model.rules.capacity, model.rules.weapons[model.state.combat.equipped].name]
    var target := nearby()
    hint.text = "[E] " + ("开关门" if target.get("kind") == "door" else "搜索柜子") + " / " + model.building_name(target.id) if not target.is_empty() else "住宅床边可 R 休息一小时；18:00后可 T 睡到次日06:00。"
    if not closest_bed().is_empty():
        hint.text = "床边：[R] 休息一小时 · [T] 夜间睡到黎明；先关门并摆脱追击。"
    notice.text = "你已死亡。J查看日志；Esc保存回菜单，新游戏重新开始。" if model.state.stats.health <= 0 else last_notice

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo or not active:
        return
    var code: int = event.keycode
    if code == KEY_ESCAPE:
        if panel.visible:
            close_panel()
        elif save_run():
            show_menu()
        return
    if code == KEY_I or code == KEY_J:
        if panel.visible:
            close_panel()
        else:
            open_panel("inventory" if code == KEY_I else "journal")
        return
    if panel.visible:
        return
    if code in [KEY_T, KEY_R]:
        request_rest("night" if code == KEY_T else "hour")
        return
    if model.state.rest.active and code != KEY_F5:
        return
    match code:
        KEY_E: interact()
        KEY_F5: save_run()
        KEY_1: use("food")
        KEY_2: use("water")
        KEY_3: use("bandage")
        KEY_4: use("club")
        KEY_SPACE: try_attack()

func use(id: String) -> void:
    if model.use_item(id):
        last_notice = ("已装备：" if model.rules.items[id].get("kind", "") == "weapon" else "使用成功：") + model.rules.items[id].name
    else:
        last_notice = "物品不足或当前无需使用。"

func open_panel(kind: String) -> void:
    panel_kind = kind
    panel.show()
    entry.visible = kind == "journal"
    mood.visible = kind == "journal"
    write_button.visible = kind == "journal"
    export_button.visible = kind == "journal"
    inventory_actions.visible = kind == "inventory"
    refresh_panel()

func close_panel() -> void:
    panel.hide()
    get_viewport().gui_release_focus()

func refresh_panel() -> void:
    if panel_kind == "journal":
        journal_text.text = model.markdown()
    else:
        journal_text.text = "背包 / %.1f / %.1f kg\n\n点击下方按钮使用物品；也可关闭后按 1/2/3。\n" % [model.weight(), model.rules.capacity]
        for id in model.rules.items:
            var rule: Dictionary = model.rules.items[id]
            journal_text.text += "%s × %d  (%.1f kg/件)\n" % [rule.name, model.state.inventory.get(id, 0), rule.weight]

func export_journal() -> void:
    if DirAccess.make_dir_recursive_absolute(export_directory) != OK:
        last_notice = "导出目录无法创建"
        return
    var path := export_directory.path_join("journal_%d_%d.md" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        last_notice = "导出失败"
        return
    file.store_string(model.markdown())
    file.close()
    last_notice = "已导出：" + ProjectSettings.globalize_path(path)
    notice.text = last_notice

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if not active or save_run():
            get_tree().quit()


func line_clear(from: Vector3, to: Vector3) -> bool:
    var ray := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 1.0, to + Vector3.UP * 1.0, 1)
    return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func try_attack() -> bool:
    if not active or panel.visible or not model.begin_attack():
        return false
    player_visual.trigger("attack")
    var weapon: Dictionary = model.rules.weapons[model.state.combat.equipped]
    model.noise(player.position, model.rules.combat.noise_radius, "combat")
    var facing := Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))
    var hits := 0
    for zombie in zombie_bodies:
        if zombie.record.health <= 0:
            continue
        var offset: Vector3 = zombie.position - player.position
        offset.y = 0
        if offset.length() <= weapon.range and (offset.length() < 0.01 or facing.dot(offset.normalized()) >= cos(deg_to_rad(model.rules.combat.half_angle_degrees))) and line_clear(player.position, zombie.position):
            zombie.take_hit(weapon.damage)
            hits += 1
    last_notice = "用%s攻击，命中%d只；声响可能引来附近僵尸。" % [weapon.name, hits]
    return true

func discover_zombies() -> void:
    if model.state.seen_horde:
        return
    var count := 0
    for zombie in zombie_bodies:
        if zombie.record.health > 0 and player.position.distance_to(zombie.position) < float(model.rules.zombie.sight_range) * lerpf(float(model.rules.zombie.night_sight_multiplier), 1.0, Timeline.daylight(model)) and line_clear(player.position, zombie.position):
            count += 1
    if count > 0:
        model.state.seen_horde = true
        model.event("first_zombies", "第一次发现%s，可见%d只。" % ["尸群" if count > 1 else "僵尸", count], "恐惧", {"count": count})

func update_player_visual(delta: float) -> void:
    player_visual.set_weapon(model.state.combat.equipped == "club")
    var action := "stand"
    if model.state.stats.health <= 0:
        action = "death"
    elif model.state.combat.hurt_cd > 0.5:
        action = "hurt"
    elif model.state.combat.attack_cd > 0:
        action = "attack"
    elif not model.state.rest.active and Vector2(player.velocity.x, player.velocity.z).length() > 0.1:
        action = "move"
    player_visual.sample(action, delta)

func collision_box(position: Vector3, size: Vector3) -> Node3D:
    var body := box(world, position, size, Color.WHITE)
    body.get_child(0).hide()
    return body

func update_cutaways() -> void:
    for id in building_visuals:
        Assets.cutaway(building_visuals[id], inside(id))

func safe_position(position: Vector3) -> Vector3:
    if absf(position.y) > 0.5:
        return position
    var blocked := false
    for source in nav_sources:
        if source.body.collision_layer != 0 and source.rect.grow(float(model.rules.actor.radius)).has_point(Vector2(position.x, position.z)):
            blocked = true
            break
    if not blocked:
        return position
    var id: Vector2i = navigation.nearest(position)
    if id.x >= 0:
        var point: Vector2 = navigation.grid.get_point_position(id)
        return Vector3(point.x, 0, point.y)
    return position


func on_target_lost() -> void:
    for zombie in zombie_bodies:
        if zombie.record.health > 0 and zombie.record.had_target:
            return
    model.event("escaped", "隔断视线后，追来的僵尸搜索无果，停止了追击。", "希望")
