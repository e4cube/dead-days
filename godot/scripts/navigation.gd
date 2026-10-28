extends RefCounted
## Navigation is derived from the same collision rectangles that build the world.
##
## A full rebuild used to visit every grid cell and test it against every
## collision rectangle (280x168 cells x 300+ sources).  Doors toggle several
## times per minute, so that scan was the main hitching source when opening or
## closing a door.  Cells are now rasterised from each rectangle instead, and a
## door-only change patches just the cells around that door.
var grid := AStarGrid2D.new()
var revision := 0
var clearance := 0.32
var _solid: Dictionary = {}
var _cell := 0.5
var _origin := Vector2.ZERO
var configured := false
## A* queries are capped per physics frame.  A dense horde replans on staggered
## timers, but a gunshot can wake dozens on the same frame; the cap keeps that
## spike off the frame budget and lets each actor keep its previous route.
const PATH_BUDGET := 8
var _budget_frame := -1
var _budget_used := 0

func rebuild(sources: Array, rule: Dictionary) -> void:
	_configure(rule)
	grid.clear()
	grid.region = Rect2i(0, 0, int(rule.size[0]), int(rule.size[1]))
	grid.cell_size = Vector2.ONE * _cell
	grid.offset = _origin
	grid.update()
	_solid.clear()
	for source in sources:
		_stamp(source)
	configured = true
	revision += 1

func _configure(rule: Dictionary) -> void:
	clearance = float(rule.clearance)
	_cell = float(rule.cell_size)
	_origin = Vector2(rule.origin[0], rule.origin[1])
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE

## Mark only the cells a single collision rectangle can cover.
func _stamp(source: Dictionary) -> void:
	if not is_instance_valid(source.body) or source.body.collision_layer == 0:
		return
	var rect: Rect2 = source.rect.grow(clearance)
	for id in _cell_range(rect):
		if not grid.is_in_boundsv(id):
			continue
		var point := grid.get_point_position(id)
		if rect.has_point(point) and not _solid.has(id):
			_solid[id] = true
			grid.set_point_solid(id, true)

func _cell_range(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var low := Vector2i(
		floori((rect.position.x - _origin.x) / _cell) - 1,
		floori((rect.position.y - _origin.y) / _cell) - 1)
	var high := Vector2i(
		ceili((rect.end.x - _origin.x) / _cell) + 1,
		ceili((rect.end.y - _origin.y) / _cell) + 1)
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			result.append(Vector2i(x, y))
	return result

## Re-evaluate only the cells inside `area` (a door footprint, in world XZ).
func patch(sources: Array, rule: Dictionary, area: Rect2) -> void:
	if not configured or area.size.x <= 0.0:
		return
	_configure(rule)
	var grow := area.grow(clearance + _cell)
	var cells := _cell_range(grow)
	for id in cells:
		if _solid.has(id):
			_solid.erase(id)
			grid.set_point_solid(id, false)
	for source in sources:
		if is_instance_valid(source.body) and source.body.collision_layer != 0 \
				and source.rect.grow(clearance).intersects(grow):
			_stamp(source)
	revision += 1

func cell(pos: Vector3) -> Vector2i:
	var p := (Vector2(pos.x, pos.z) - grid.offset) / grid.cell_size
	return Vector2i(roundi(p.x), roundi(p.y))

func nearest(pos: Vector3) -> Vector2i:
	var center := cell(pos)
	var best := Vector2i(-1, -1)
	var distance := INF
	for y in range(center.y - 2, center.y + 3):
		for x in range(center.x - 2, center.x + 3):
			var id := Vector2i(x, y)
			if grid.is_in_boundsv(id) and not grid.is_point_solid(id):
				var d := grid.get_point_position(id).distance_squared_to(Vector2(pos.x, pos.z))
				if d < distance:
					best = id
					distance = d
	return best

func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_used = 0
	if _budget_used >= PATH_BUDGET:
		return PackedVector3Array()
	_budget_used += 1
	var start := nearest(from)
	var end := nearest(to)
	var result := PackedVector3Array()
	if start.x < 0 or end.x < 0:
		return result
	for point in grid.get_point_path(start, end, true):
		result.append(Vector3(point.x, 0, point.y))
	return result
