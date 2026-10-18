extends Node3D
const Model = preload("res://scripts/survival.gd")
const Store = preload("res://scripts/save_store.gd")
var model = Model.new()
var store = Store.new()
var active := false
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var doors := {}
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
    title.text = "DEAD DAYS / 末日生存日志\n阶段 B · 搜刮与日志切片"
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
    var background := Panel.new()
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.add_theme_stylebox_override("panel", style)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    panel.add_child(background)
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
        button(inventory_actions, "使用" + model.rules.items[id].name, func():
            use(id)
            refresh_panel())
    button(panel, "关闭 [I / J / Esc]", close_panel)
    panel.hide()

func show_menu() -> void:
    active = false
    menu.show()
    panel.hide()
    hud.text = "DEAD DAYS  /  重构分支\n新存档独立于 Pygame v0.3；阶段 C 的僵尸与睡眠尚未接入。"
    hint.text = "WASD 移动 · Shift 跑步 · E 开关门/搜刮 · I 背包 · J 日志 · 1/2/3 使用物品 · F5 保存 · Esc 保存回菜单"

func new_run() -> void:
    model.start()
    build_world()
    active = true
    menu.hide()
    close_panel()
    last_notice = "先走近住宅门按 E，再进入屋内搜刮柜子。"

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
    world = Node3D.new()
    add_child(world)
    box(world, Vector3(0, -0.25, -1), Vector3(27, 0.5, 19), Color("49594a"))
    box(world, Vector3(0, 0.015, 3), Vector3(26, 0.03, 4), Color("454b50"), false)
    for x in range(-12, 13, 3):
        box(world, Vector3(x, 0.04, 3), Vector3(1, 0.03, 0.1), Color("c7bb87"), false)
    for b in model.rules.buildings:
        var x: float = b.x
        var color := Color(b.color)
        box(world, Vector3(x, 0.04, -2.5), Vector3(5.5, 0.08, 5), color.darkened(0.35), false)
        box(world, Vector3(x, 1.3, -5), Vector3(5.7, 2.6, 0.2), color)
        box(world, Vector3(x - 2.75, 1.3, -2.5), Vector3(0.2, 2.6, 5), color)
        # Low front and east walls are intentional architectural cutaways; collisions remain full height.
        for side in [-1, 1]:
            var wall := box(world, Vector3(x + side * 1.85, 1.3, 0), Vector3(1.9, 2.6, 0.2), color)
            wall.get_child(0).scale.y = 0.3
            wall.get_child(0).position.y = -0.91
        var east := box(world, Vector3(x + 2.75, 1.3, -2.5), Vector3(0.2, 2.6, 5), color)
        east.get_child(0).scale.y = 0.3
        east.get_child(0).position.y = -0.91
        doors[b.id] = box(world, Vector3(x, 1.0, 0), Vector3(1.7, 2, 0.16), Color("6b503e"))
        var container_body := box(world, Vector3(x, 0.5, -3), Vector3(1.2, 1, 0.7), Color("99714c"))
        var asset: PackedScene = load("res://assets/loot_crate.glb")
        var crate := asset.instantiate() as Node3D
        container_body.get_child(0).hide()
        crate.position.y = -0.5
        container_body.add_child(crate)
        label3(world, b.name, Vector3(x, 3.1, -5))
        label3(world, "柜子 [E]", Vector3(x, 1.6, -3))
        apply_door(b.id)
    # Boundary bodies prevent leaving the playable block.
    for x in [-13.5, 13.5]:
        box(world, Vector3(x, 1, -1), Vector3(0.3, 2, 19), Color("36433a"))
    for z in [-10.5, 8.5]:
        box(world, Vector3(0, 1, z), Vector3(27, 2, 0.3), Color("36433a"))
    player = CharacterBody3D.new()
    player.name = "Survivor"
    world.add_child(player)
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.28
    capsule.height = 1.7
    shape.shape = capsule
    shape.position.y = 0.9
    player.add_child(shape)
    box(player, Vector3(0, 0.95, 0), Vector3(0.5, 0.8, 0.35), Color("c5ab5e"), false)
    box(player, Vector3(0, 1.6, 0), Vector3(0.36, 0.36, 0.36), Color("d7bc9a"), false)
    for x in [-0.16, 0.16]:
        box(player, Vector3(x, 0.35, 0), Vector3(0.2, 0.7, 0.24), Color("3c4d5c"), false)
    var p: Array = model.state.position
    player.position = Vector3(p[0], p[1], p[2])
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.size = 19
    world.add_child(camera)
    camera.current = true
    update_camera()
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -30, 0)
    light.light_energy = 1.1
    light.shadow_enabled = true
    world.add_child(light)
    var env := WorldEnvironment.new()
    env.environment = Environment.new()
    env.environment.background_mode = Environment.BG_COLOR
    env.environment.background_color = Color("19232b")
    env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.environment.ambient_light_color = Color("c6d7e6")
    env.environment.ambient_light_energy = 0.65
    world.add_child(env)

func apply_door(id: String) -> void:
    var body: StaticBody3D = doors[id]
    var opened: bool = model.state.doors[id]
    body.get_child(0).visible = not opened
    body.collision_layer = 0 if opened else 1

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
    for b in model.rules.buildings:
        if b.id == id:
            return absf(player.position.x - b.x) < 2.45 and player.position.z < -0.4 and player.position.z > -4.75
    return false

func interact() -> void:
    var target := nearby()
    if target.is_empty():
        last_notice = "靠近门或屋内柜子后按 E。"
        return
    if target.kind == "door":
        if model.state.doors[target.id] and absf(player.position.z) < 0.6 and absf(player.position.x - doors[target.id].position.x) < 1.2:
            last_notice = "先离开门口，避免关门夹住自己。"
            return
        model.toggle_door(target.id)
        apply_door(target.id)
        last_notice = model.state.events.back().text
    else:
        var count: int = model.loot(target.id)
        last_notice = "获得 %d 件物资；未带走的留在柜中。" % count if count else "柜子已空或负重不足。"

func sync_position() -> void:
    model.state.position = [player.position.x, player.position.y, player.position.z]

func save_run() -> bool:
    sync_position()
    var path: String = store.save(model)
    last_notice = "已保存：" + path if not path.is_empty() else store.last_error
    return not path.is_empty()

func _physics_process(delta: float) -> void:
    if not active or panel.visible:
        return
    # World-relative controls are labeled explicitly; camera is fixed orthographic isometric.
    var input := Input.get_vector("left", "right", "forward", "back")
    var running: bool = Input.is_action_pressed("run") and model.state.stats.stamina > 0
    var speed: float = model.rules.run_speed if running else model.rules.walk_speed
    player.velocity = Vector3(input.x * speed, -2.0, input.y * speed)
    player.move_and_slide()
    if input.length() > 0.1:
        player.rotation.y = lerp_angle(player.rotation.y, atan2(input.x, input.y), delta * 12)
    model.state.stats.stamina = clampf(model.state.stats.stamina + (-float(model.rules.stamina_run_cost) if running and input.length() > 0 else float(model.rules.stamina_recovery)) * delta, 0, 100)
    for b in model.rules.buildings:
        if inside(b.id):
            model.enter(b.id)
    sync_position()
    update_camera()
    hud.text = "DEAD DAYS / 第%d天 06:00 · 阶段B\n生命 %.0f  饱腹 %.0f  饮水 %.0f  体力 %.0f    负重 %.1f / %.1f kg\nWASD 世界方向移动 · Shift 跑步 · E 交互 · I 背包 · J 日志 · 1食物 2水 3绷带 · F5保存 · Esc菜单" % [model.state.day, model.state.stats.health, model.state.stats.hunger, model.state.stats.thirst, model.state.stats.stamina, model.weight(), model.rules.capacity]
    var target := nearby()
    hint.text = "[E] " + ("开关门" if target.get("kind") == "door" else "搜索柜子") + " / " + model.building_name(target.id) if not target.is_empty() else "住宅 / 诊所 / 杂货店：沿街找门，搜刮后可带往其他房屋。"
    notice.text = last_notice

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
    match code:
        KEY_E: interact()
        KEY_F5: save_run()
        KEY_1: use("food")
        KEY_2: use("water")
        KEY_3: use("bandage")

func use(id: String) -> void:
    last_notice = "使用成功：" + model.rules.items[id].name if model.use_item(id) else "物品不足或当前无需使用。"

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
