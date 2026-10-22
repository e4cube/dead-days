extends SceneTree
var game
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)
func frames(count: int) -> void:
    for i in count:
        await physics_frame
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.new_run()
    Input.action_press("right")
    await frames(12)
    check(game.player_visual.current_action == "move", "walking selects imported walk")
    var walk_speed: float = Vector2(game.player.velocity.x,game.player.velocity.z).length()
    var stamina: float = game.model.state.stats.stamina
    Input.action_press("run")
    await frames(12)
    check(game.player_visual.current_action == "run", "actual sprint selects imported run")
    check(Vector2(game.player.velocity.x,game.player.velocity.z).length() > walk_speed, "sprint really moves faster")
    check(game.model.state.stats.stamina < stamina and not game.model.state.noises.is_empty(), "sprint retains stamina and sound costs")
    var visual = game.player_visual
    var index: int = visual.skeleton.find_bone("thigh_L")
    var pose: Quaternion = visual.skeleton.get_bone_pose_rotation(index)
    await frames(6)
    check(pose.angle_to(visual.skeleton.get_bone_pose_rotation(index)) > .1, "run animates weighted leg bones")
    Input.action_release("right")
    Input.action_release("run")
    await frames(3)
    check(game.player_visual.current_action == "stand", "stopping exits run")
    game.try_attack()
    check(game.player_visual.current_action == "attack", "attack still takes priority")
    print("CHARACTER_MOTION_OK" if failures==0 else "CHARACTER_MOTION_FAILED")
    quit(0 if failures==0 else 1)
