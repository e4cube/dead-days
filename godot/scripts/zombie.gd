extends CharacterBody3D
const CharacterVisual = preload("res://scripts/character_visual.gd")
const Timeline = preload("res://scripts/survival_time.gd")
## World-space perception, finite memory and path following. The record is authoritative/saveable.
var game
var record: Dictionary
var rule: Dictionary
var route := PackedVector3Array()
var route_index := 0
var replan_left := 0.0
var nav_revision := -1
var path_goal:=Vector3.INF
var hit_flash := 0.0
var state_label: Label3D
var show_state_label := false
var visual_root: Node3D
var excepted: Dictionary = {}
var label_shown := false

func setup(owner_game: Node3D, data: Dictionary) -> void:
    game = owner_game
    record = data
    rule = game.model.rules.zombie
    collision_layer = 4
    collision_mask = 1 | 2 | 4
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = game.model.rules.actor.radius
    shape.height = game.model.rules.actor.height
    collider.shape = shape
    collider.position.y = game.model.rules.actor.center_y
    add_child(collider)
    visual_root = CharacterVisual.new()
    add_child(visual_root)
    visual_root.setup("zombie")
    visual_root.set_appearance(record.get("appearance","civilian"))
    visual_root.position.y = float(game.model.rules.actor.center_y) - float(game.model.rules.actor.height) * 0.5
    state_label = Label3D.new()
    state_label.font_size = 24
    state_label.pixel_size = 0.009
    state_label.position.y = 2.1
    state_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    state_label.visible = show_state_label
    label_shown = show_state_label
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
    if absf(offset.y)>2.0: return false # Planar AI cannot attack a different floor.
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

func blocked_door() -> Dictionary:
    if record.mode not in ["chase","search"] or record.memory<=0: return {}
    var target:=vector(record.target)
    for building in game.model.rules.buildings:
        if game.model.state.doors[building.id]: continue
        var target_inside: bool=preload("res://scripts/rest.gd").inside(game.model,building.id,target)
        var self_inside: bool=preload("res://scripts/rest.gd").inside(game.model,building.id,position)
        # Investigate the remembered room entrance, never the hidden player's current position.
        if target_inside==self_inside: continue
        if not self_inside and (position.z<0 or position.z>5 or absf(position.x-float(building.x))>4): continue
        return {"id":building.id,"goal":Vector3(building.x,0,-.85 if self_inside else .85)}
    return {}

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
    var barrier:=blocked_door()
    var bash_near: bool=not barrier.is_empty() and Vector2(position.x-barrier.goal.x,position.z).length()<=float(game.model.rules.door_damage.reach)
    var distance: float = Vector2(position.x - game.player.position.x, position.z - game.player.position.z).length()
    if record.windup > 0:
        record.windup = maxf(0, record.windup - delta)
        if record.windup <= 0:
            var committed_door: String=record.get("attack_door","")
            if not committed_door.is_empty():
                if bash_near and barrier.id==committed_door:
                    game.hit_door(committed_door,record.id)
            elif distance <= rule.attack_range and visible_target:
                game.model.damage_player(rule.attack_damage, record.id)
            record.attack_door=""
            record.attack_cd = rule.attack_cooldown
    elif visible_target and distance <= rule.attack_range and record.attack_cd <= 0:
        record.attack_door=""
        record.windup = rule.attack_windup
        visual_root.trigger("attack")
    elif not visible_target and bash_near and record.attack_cd<=0:
        record.attack_door=barrier.id
        record.windup=rule.attack_windup
        visual_root.trigger("attack")
    var movement := Vector3.ZERO
    if record.windup <= 0 and not (visible_target and distance < rule.attack_range * 0.8):
        movement = follow_path(delta,barrier.goal if not barrier.is_empty() else vector(record.target)) if not bash_near else Vector3.ZERO
    var separation := Vector3.ZERO
    var close_pairs: Array = []
    for other in game.zombie_bodies:
        if other == self or other.record.health <= 0:
            continue
        var away: Vector3 = position - other.position
        away.y = 0
        var planar := away.length()
        if planar < rule.separation_radius:
            var strength: float = 1.0 - planar / rule.separation_radius
            if planar < 0.001:
                away = Vector3.RIGHT if str(record.id) < str(other.record.id) else Vector3.LEFT
            separation += away.normalized() * strength
        # Let the repulsion move initially intersecting capsules apart; environment/player sweeps stay active.
        if position.distance_squared_to(other.position) < 0.3364:
            close_pairs.append(other)
    movement += separation * float(rule.separation_strength)
    var speed: float = rule.chase_speed if record.mode in ["chase", "search"] else rule.walk_speed
    movement = movement.limit_length(speed)
    velocity = Vector3(movement.x, -2, movement.z)
    # Explicit swept displacement keeps accelerated rest simulation in the same time units.
    _sync_collision_exceptions(close_pairs)
    var motion := velocity * delta
    for slide in 3:
        var collision := move_and_collide(motion)
        if collision == null:
            break
        motion = collision.get_remainder().slide(collision.get_normal())
        if motion.length_squared() < 0.0000001:
            break
    if bash_near:
        var toward_door: Vector3=Vector3(barrier.goal.x,0,0)-position
        rotation.y=lerp_angle(rotation.y,atan2(toward_door.x,toward_door.z),minf(1,delta*12))
    elif movement.length() > 0.1:
        rotation.y = lerp_angle(rotation.y, atan2(movement.x, movement.z), minf(1, delta * 8))
    elif record.mode == "search":
        rotation.y = wrapf(rotation.y + delta, -PI, PI)
    write_position()
    update_visual(delta)

func follow_path(delta: float,goal: Vector3) -> Vector3:
    replan_left -= delta
    if replan_left <= 0 or nav_revision != game.navigation.revision or path_goal.distance_squared_to(goal)>.01:
        var fresh: PackedVector3Array = game.navigation.path(position, goal)
        if fresh.size() > 0:
            route = fresh
            route_index = 1 if route.size() > 1 else 0
        elif route.is_empty():
            # Budget refused this frame: walk straight at the goal so the actor
            # keeps closing instead of freezing until its next replan.
            var direct := goal - position
            direct.y = 0
            if direct.length() > 0.05:
                var direct_speed: float = rule.walk_speed if record.mode == "wander" else rule.chase_speed
                return direct.normalized() * minf(direct_speed, direct.length() / maxf(delta, 0.001))
        path_goal=goal
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

## Keep physics exceptions stable between frames: adding/removing them every
## frame for a dense horde was measurable physics overhead.
func _sync_collision_exceptions(pairs: Array) -> void:
    for other in excepted.keys():
        if not pairs.has(other) or not is_instance_valid(other):
            if is_instance_valid(other):
                remove_collision_exception_with(other)
            excepted.erase(other)
    for other in pairs:
        if not excepted.has(other):
            add_collision_exception_with(other)
            excepted[other] = true

func take_hit(damage: float) -> void:
    if game.model.damage_zombie(record, damage):
        hit_flash = 0.2
        visual_root.trigger("hurt")
        record.windup = 0.0
        record.attack_door=""
        if record.health > 0:
            record.mode = "alert"
            record.target = [game.player.position.x, 0, game.player.position.z]
            record.memory = rule.search_seconds
            record.alert_left = rule.alert_seconds
        update_visual(0)

func update_visual(delta: float) -> void:
    if show_state_label != label_shown:
        label_shown = show_state_label
        state_label.visible = show_state_label
    if record.health <= 0:
        collision_layer = 0
        collision_mask = 0
        visual_root.sample("death", 0)
        if show_state_label:
            state_label.position.y = 0.65
            state_label.text = "倒地"
            state_label.modulate = Color("7b817a")
        return
    var action := "stand"
    if hit_flash > 0:
        action = "hurt"
    elif record.windup > 0 or record.attack_cd > float(rule.attack_cooldown) - 0.28:
        action = "attack"
    elif Vector2(velocity.x, velocity.z).length() > 0.1:
        action = "move"
    visual_root.sample(action, delta)
    if show_state_label:
        state_label.text = {"wander": "游荡", "alert": "警觉", "chase": "追击", "search": "搜索"}[record.mode] + " %.0f" % record.health
