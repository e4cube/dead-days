extends CharacterBody3D
const Timeline = preload("res://scripts/survival_time.gd")
## World-space perception, finite memory and path following. The record is authoritative/saveable.
var game
var record: Dictionary
var rule: Dictionary
var route := PackedVector3Array()
var route_index := 0
var replan_left := 0.0
var nav_revision := -1
var hit_flash := 0.0
var torso: MeshInstance3D
var state_label: Label3D
var arm: Node3D
var visual_root: Node3D

func setup(owner_game: Node3D, data: Dictionary) -> void:
    game = owner_game
    record = data
    rule = game.model.rules.zombie
    collision_layer = 4
    collision_mask = 1 | 2 | 4
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.28
    shape.height = 1.7
    collider.shape = shape
    collider.position.y = 0.9
    add_child(collider)
    visual_root = Node3D.new()
    add_child(visual_root)
    var body: Node3D = game.box(visual_root, Vector3(0, 0.95, 0), Vector3(0.52, 0.8, 0.36), Color("58725a"), false)
    torso = body.get_child(0)
    game.box(visual_root, Vector3(0, 1.58, 0), Vector3(0.4, 0.4, 0.4), Color("7f9775"), false)
    for x in [-0.16, 0.16]:
        game.box(visual_root, Vector3(x, 0.35, 0), Vector3(0.2, 0.7, 0.24), Color("414d47"), false)
    arm = Node3D.new()
    arm.position = Vector3(0.34, 1.2, 0)
    visual_root.add_child(arm)
    game.box(arm, Vector3(0, -0.22, 0.2), Vector3(0.15, 0.5, 0.15), Color("7f9775"), false)
    state_label = Label3D.new()
    state_label.font_size = 24
    state_label.pixel_size = 0.009
    state_label.position.y = 2.1
    state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    add_child(state_label)
    position = vector(record.position)
    rotation.y = record.heading
    update_visual(0)

func vector(value: Array) -> Vector3:
    return Vector3(value[0], value[1], value[2])

func write_position() -> void:
    record.position = [position.x, position.y, position.z]
    record.heading = rotation.y

func sees_player() -> bool:
    if record.health <= 0 or game.model.state.stats.health <= 0:
        return false
    var offset: Vector3 = game.player.position - position
    offset.y = 0
    var distance := offset.length()
    if distance > float(rule.sight_range) * lerpf(float(rule.night_sight_multiplier), 1.0, Timeline.daylight(game.model)):
        return false
    var facing := Vector3(sin(rotation.y), 0, cos(rotation.y))
    if distance > rule.close_sight and facing.dot(offset.normalized()) < cos(deg_to_rad(rule.fov_degrees * 0.5)):
        return false
    return game.line_clear(position, game.player.position)

func hear() -> bool:
    var heard: Dictionary = {}
    for sound in game.model.state.noises:
        if sound.id <= record.last_noise:
            continue
        var target := vector(sound.position)
        var radius: float = sound.radius
        if not game.line_clear(position, target):
            radius *= float(game.model.rules.noise.wall_multiplier)
        if Vector2(position.x - target.x, position.z - target.z).length() <= radius:
            heard = sound
    if heard.is_empty():
        return false
    record.last_noise = heard.id
    record.target = heard.position.duplicate()
    record.memory = rule.search_seconds
    if record.mode == "wander":
        record.alert_left = rule.alert_seconds
        record.mode = "alert"
    elif record.mode != "alert":
        record.mode = "search"
    replan_left = 0
    return true

func tick(delta: float) -> void:
    if record.health <= 0:
        update_visual(delta)
        return
    hit_flash = maxf(0, hit_flash - delta)
    record.attack_cd = maxf(0, record.attack_cd - delta)
    var visible_target := sees_player()
    if visible_target:
        record.mode = "chase"
        record.target = [game.player.position.x, 0, game.player.position.z]
        record.memory = rule.search_seconds
        record.had_target = true
    elif hear():
        pass
    elif record.mode == "chase":
        record.mode = "search"
    if not visible_target and record.mode in ["alert", "search"]:
        record.memory = maxf(0, record.memory - delta)
        if record.mode == "alert":
            record.alert_left = maxf(0, record.alert_left - delta)
            if record.alert_left <= 0:
                record.mode = "search"
        if record.memory <= 0:
            record.mode = "wander"
            record.patrol_left = 0.0
            if record.had_target:
                record.had_target = false
                game.on_target_lost()
    if record.mode == "wander":
        record.patrol_left = maxf(0, record.patrol_left - delta)
        if record.patrol_left <= 0:
            # Deterministic local patrol; never retarget the hidden player.
            var offsets := [Vector3(1.4, 0, 0), Vector3(0, 0, -1.4), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4)]
            var target: Vector3 = position + offsets[int(record.patrol_index) % offsets.size()]
            record.patrol_index += 1
            record.target = [target.x, 0, target.z]
            record.patrol_left = rule.patrol_seconds
            replan_left = 0
    var distance: float = Vector2(position.x - game.player.position.x, position.z - game.player.position.z).length()
    if record.windup > 0:
        record.windup = maxf(0, record.windup - delta)
        if record.windup <= 0:
            if distance <= rule.attack_range and visible_target:
                game.model.damage_player(rule.attack_damage, record.id)
            record.attack_cd = rule.attack_cooldown
    elif visible_target and distance <= rule.attack_range and record.attack_cd <= 0:
        record.windup = rule.attack_windup
    var movement := Vector3.ZERO
    if record.windup <= 0 and not (visible_target and distance < rule.attack_range * 0.8):
        movement = follow_path(delta)
    var separation := Vector3.ZERO
    for other in game.zombie_bodies:
        if other == self or other.record.health <= 0:
            continue
        var away: Vector3 = position - other.position
        away.y = 0
        if away.length() < rule.separation_radius:
            var strength: float = 1.0 - away.length() / rule.separation_radius
            if away.length() < 0.001:
                away = Vector3.RIGHT if str(record.id) < str(other.record.id) else Vector3.LEFT
            separation += away.normalized() * strength
    movement += separation * float(rule.separation_strength)
    var speed: float = rule.chase_speed if record.mode in ["chase", "search"] else rule.walk_speed
    movement = movement.limit_length(speed)
    velocity = Vector3(movement.x, -2, movement.z)
    # Explicit swept displacement keeps accelerated rest simulation in the same time units.
    var recovering: Array = []
    for other in game.zombie_bodies:
        if other != self and other.record.health > 0 and position.distance_to(other.position) < 0.58:
            # Let the repulsion move initially intersecting capsules apart; environment/player sweeps stay active.
            add_collision_exception_with(other)
            recovering.append(other)
    var motion := velocity * delta
    for slide in 3:
        var collision := move_and_collide(motion)
        if collision == null:
            break
        motion = collision.get_remainder().slide(collision.get_normal())
        if motion.length_squared() < 0.0000001:
            break
    for other in recovering:
        remove_collision_exception_with(other)
    if movement.length() > 0.1:
        rotation.y = lerp_angle(rotation.y, atan2(movement.x, movement.z), minf(1, delta * 8))
    elif record.mode == "search":
        rotation.y = wrapf(rotation.y + delta, -PI, PI)
    write_position()
    update_visual(delta)

func follow_path(delta: float) -> Vector3:
    replan_left -= delta
    if replan_left <= 0 or nav_revision != game.navigation.revision:
        route = game.navigation.path(position, vector(record.target))
        route_index = 1 if route.size() > 1 else 0
        replan_left = rule.repath_seconds
        nav_revision = game.navigation.revision
    while route_index < route.size() and Vector2(position.x - route[route_index].x, position.z - route[route_index].z).length() < 0.13:
        route_index += 1
    if route_index >= route.size() or record.mode == "alert":
        return Vector3.ZERO
    var toward := route[route_index] - position
    toward.y = 0
    var speed: float = rule.walk_speed if record.mode == "wander" else rule.chase_speed
    return toward.normalized() * minf(speed, toward.length() / maxf(delta, 0.001))

func take_hit(damage: float) -> void:
    if game.model.damage_zombie(record, damage):
        hit_flash = 0.2
        record.windup = 0.0
        if record.health > 0:
            record.mode = "alert"
            record.target = [game.player.position.x, 0, game.player.position.z]
            record.memory = rule.search_seconds
            record.alert_left = rule.alert_seconds
        update_visual(0)

func update_visual(_delta: float) -> void:
    if record.health <= 0:
        collision_layer = 0
        collision_mask = 0
        visual_root.rotation.z = PI / 2
        visual_root.position.y = 0.25
        state_label.position.y = 0.65
        state_label.text = "倒地"
        state_label.modulate = Color("7b817a")
        return
    var colors := {"wander": Color("78956c"), "alert": Color("d0ad5c"), "chase": Color("b75647"), "search": Color("ae8a5a")}
    torso.material_override.albedo_color = Color.WHITE if hit_flash > 0 else colors[record.mode]
    state_label.text = {"wander": "游荡", "alert": "警觉", "chase": "追击", "search": "搜索"}[record.mode] + " %.0f" % record.health
    arm.rotation.x = -1.0 if record.windup > 0 else 0.0
