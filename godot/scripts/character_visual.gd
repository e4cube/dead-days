extends Node3D
## Imported skin + clips, sampled in simulation time (also during accelerated rest).
var instance: Node3D
var animator: AnimationPlayer
var skeleton: Skeleton3D
var clips: Dictionary = {}
var current_action := ""
var weapon: MeshInstance3D

func setup(kind: String) -> void:
    instance = load("res://assets/" + kind + ".glb").instantiate()
    add_child(instance)
    animator = instance.find_children("*", "AnimationPlayer", true, false)[0]
    skeleton = instance.find_children("*", "Skeleton3D", true, false)[0]
    animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
    for name in animator.get_animation_list():
        var short: String = str(name).get_slice("/", str(name).get_slice_count("/") - 1)
        clips[short] = name
        animator.get_animation(name).loop_mode = Animation.LOOP_LINEAR if short in ["stand", "move", "run"] else Animation.LOOP_NONE
    for node in instance.find_children("*", "MeshInstance3D", true, false):
        if str(node.name).begins_with("DD_Weapon_Club"):
            weapon = node
    set_weapon(false)
    sample("stand", 0)

func set_weapon(equipped: bool) -> void:
    if is_instance_valid(weapon):
        weapon.visible = equipped

func trigger(action: String) -> void:
    current_action = ""
    sample(action, 0)

func sample(action: String, seconds: float) -> void:
    if not clips.has(action):
        push_error("Missing exported character clip: " + action)
        return
    if current_action != action:
        animator.stop()
        animator.play(clips[action])
        current_action = action
    if action == "death":
        animator.seek(animator.get_animation(clips[action]).length, true)
        animator.advance(0)
    else:
        animator.advance(seconds)
