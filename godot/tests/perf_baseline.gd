extends SceneTree
## Repeatable render baseline for the connected world.
##
## Every scene rebuilds the world from scratch, teleports the stationary player,
## then samples real process-frame intervals with VSync disabled so the result
## shows headroom rather than a 60 Hz lock.  Simulation still runs through the
## normal _physics_process path; nothing here fakes gameplay time.
##
## Usage:
##   Godot --path godot --resolution 1920x1080 --script res://tests/perf_baseline.gd -- 1920 1080
##
## Output: work/perf-baseline/perf-<width>x<height>.json

const WARMUP := 60
const SAMPLES := 150

const SCENES := [
	{"key": "home_indoor", "label": "住宅室内", "position": Vector3(-7.0, 0.2, -3.0)},
	{"key": "market", "label": "市集摊位", "position": Vector3(63.0, 0.2, -17.0)},
	{"key": "factory", "label": "工厂车间", "position": Vector3(160.0, 0.2, 22.0)},
	{"key": "horde_chase", "label": "尸群追击", "position": Vector3(63.0, 0.2, -17.0), "horde": true},
	{"key": "gunshot", "label": "枪声聚集", "position": Vector3(63.0, 0.2, -17.0), "gunshot": true},
]

var width := 1920
var height := 1080
var quality := "medium"
var only := ""
var game

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() >= 2:
		width = int(user_args[0])
		height = int(user_args[1])
	if user_args.size() >= 3:
		quality = str(user_args[2])
	if user_args.size() >= 4:
		only = str(user_args[3])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(width, height)
	var gpu := RenderingServer.get_video_adapter_name()
	var renderer := RenderingServer.get_current_rendering_method()
	print("PERF_GPU: ", gpu, " / ", renderer, " / ", width, "x", height, " / quality=", quality, " / scene=", only)

	var output := []
	for scene in SCENES:
		if not only.is_empty() and str(scene.key) != only:
			continue
		var row := await measure(scene)
		output.append(row)
		print("PERF_SCENE ", row.key, " mean_fps=", row.mean_fps, " p95=", row.p95_ms, "ms max=", row.max_ms, "ms near=", row.simulated_near)

	var payload := {
		"godot": Engine.get_version_info().string,
		"renderer": renderer,
		"gpu": gpu,
		"viewport": [width, height],
		"vsync": "disabled",
		"quality": quality,
		"warmup_frames": WARMUP,
		"sample_frames": SAMPLES,
		"fixture": "stationary player, world rebuilt per scene, normal _physics_process simulation, VSync off; not a free-play guarantee",
		"scenes": output,
	}
	var dir := ProjectSettings.globalize_path("res://").path_join("../work/perf-baseline")
	DirAccess.make_dir_recursive_absolute(dir)
	var name := "perf-%dx%d.json" % [width, height] if only.is_empty() else "perf-single-%s.json" % only
	var path := dir.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("PERF_BASELINE_OK ", path)
	quit(0)

func measure(scene: Dictionary) -> Dictionary:
	if is_instance_valid(game):
		root.remove_child(game)
		game.queue_free()
		game = null
		await process_frame
		await process_frame
	game = load("res://locations/integrated_world.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.store = load("res://scripts/save_store.gd").new("user://tests/perf_%s_%d" % [scene.key, Time.get_ticks_usec()])
	game.new_run()
	# Set the tier directly: tests must not overwrite the player's saved setting.
	game.quality = quality
	game.apply_quality()
	var at: Vector3 = scene.position
	game.teleport_player(at)
	game.update_camera(0)
	game.update_cutaways()
	await process_frame
	if scene.get("horde", false):
		_arrange_horde(at)
	if scene.get("gunshot", false):
		game.model.noise(at, 32.0, "gunshot")

	var intervals: Array[float] = []
	var process_ms: Array[float] = []
	var physics_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var primitives: Array[float] = []
	var stamp := Time.get_ticks_usec()
	for index in WARMUP + SAMPLES:
		await process_frame
		var now := Time.get_ticks_usec()
		if index >= WARMUP:
			intervals.append(float(now - stamp) / 1000.0)
			process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		stamp = now

	var sorted_intervals := intervals.duplicate()
	sorted_intervals.sort()
	var total := 0.0
	for value in intervals:
		total += value
	var mean_ms := total / maxf(float(intervals.size()), 1.0)
	return {
		"key": scene.key,
		"label": scene.label,
		"mean_fps": snappedf(1000.0 / maxf(mean_ms, 0.0001), 0.01),
		"mean_ms": snappedf(mean_ms, 0.01),
		"p50_ms": snappedf(_percentile(sorted_intervals, 0.50), 0.01),
		"p95_ms": snappedf(_percentile(sorted_intervals, 0.95), 0.01),
		"p99_ms": snappedf(_percentile(sorted_intervals, 0.99), 0.01),
		"max_ms": snappedf(sorted_intervals[sorted_intervals.size() - 1], 0.01),
		"stutter_over_33ms": _count_over(intervals, 33.0),
		"process_ms": snappedf(_mean(process_ms), 0.01),
		"physics_ms": snappedf(_mean(physics_ms), 0.01),
		"draw_calls": int(_mean(draw_calls)),
		"primitives": int(_mean(primitives)),
		"actors": game.zombie_bodies.size(),
		"simulated_near": game.simulated_near,
		"simulated_far": game.simulated_far,
	}

## Ring the market population around the stationary player so the chase scene
## measures real pathing/separation cost instead of a quiet street.
## Regions live on the spawn definition, not in the saveable zombie record.
func _arrange_horde(at: Vector3) -> void:
	var regions := {}
	for spawn in game.model.world_definition.enemy_spawns:
		regions[str(spawn.id)] = str(spawn.get("region", ""))
	var index := 0
	for zombie in game.zombie_bodies:
		if regions.get(str(zombie.record.id), "") != "market":
			continue
		var angle := TAU * float(index % 24) / 24.0
		var radius := 4.0 + float(index % 5) * 1.2
		var spot := at + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		zombie.position = spot
		zombie.record.position = [spot.x, spot.y, spot.z]
		zombie.record.mode = "chase"
		zombie.record.target = [at.x, 0.0, at.z]
		zombie.record.memory = 6.0
		index += 1

func _percentile(sorted_values: Array[float], ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(int(floor(float(sorted_values.size() - 1) * ratio)), 0, sorted_values.size() - 1)
	return sorted_values[index]

func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())

func _count_over(values: Array[float], limit: float) -> int:
	var count := 0
	for value in values:
		if value > limit:
			count += 1
	return count
