extends RefCounted
## Navigation is derived from the same collision rectangles that build the world.
##
## A full rebuild used to visit every grid cell and test it against every
## collision rectangle (280x168 cells x 300+ sources).  Doors toggle several
## times per minute, so that scan was the main hitching source when opening or
## closing a door.  Cells are now rasterised from each rectangle instead, and a
## door-only change patches just the cells around that door.
##
## Floors: a source carries the vertical span it occupies (`min_y`/`max_y`).
## When the rule declares more than one floor, every floor gets its own grid and
## a source only blocks the floors it actually reaches into.  Without that split
## a second-floor slab is a rectangle in plan view and used to seal the ground
## floor underneath it.  Thin slabs are treated as the walkable surface of the
## floor they belong to, never as an obstacle.
##
## Stairs connect two floors.  `path()` plans on each floor and stitches the legs
## together with a ramp segment, so an actor can be told to follow a target that
## stands one storey above it.
class FloorData:
	var grid := AStarGrid2D.new()
	var solid: Dictionary = {}
	var min_y := -1000000.0
	var max_y := 1000000.0
	var ground_y := 0.0

var floors: Array[FloorData] = []
## Stair links: {"id", "from", "to", "bottom": [x, z], "top": [x, z]}.
var stairs: Array = []
## Floor 0 grid.  Kept as a plain field because the save sanitiser and several
## callers reach for `navigation.grid.get_point_position()` directly.
var grid: AStarGrid2D
var revision := 0
var clearance := 0.32
var _cell := 0.5
var _origin := Vector2.ZERO
var configured := false
## A* queries are capped per physics frame.  A dense horde replans on staggered
## timers, but a gunshot can wake dozens on the same frame; the cap keeps that
## spike off the frame budget and lets each actor keep its previous route.
const PATH_BUDGET := 8
## Anything thinner than this reads as a floor slab rather than furniture.
const SLAB_HEIGHT := 0.35
var _budget_frame := -1
var _budget_used := 0

func rebuild(sources: Array, rule: Dictionary) -> void:
	_configure(rule)
	floors.clear()
	var defs: Array = rule.get("floors", [])
	if defs.is_empty():
		var only := FloorData.new()
		only.ground_y = float(rule.get("ground_y", 0.0))
		floors.append(only)
	else:
		for definition in defs:
			var floor := FloorData.new()
			floor.min_y = float(definition.get("min_y", -1000000.0))
			floor.max_y = float(definition.get("max_y", 1000000.0))
			floor.ground_y = float(definition.get("ground_y", 0.0))
			floors.append(floor)
	stairs = (rule.get("stairs", []) as Array).duplicate(true)
	for floor in floors:
		_setup_grid(floor, rule)
	var split := floors.size() > 1
	for source in sources:
		for floor in floors:
			if _belongs(source, floor, split):
				_stamp(source, floor)
	grid = floors[0].grid
	configured = true
	revision += 1

func _configure(rule: Dictionary) -> void:
	clearance = float(rule.clearance)
	_cell = float(rule.cell_size)
	_origin = Vector2(rule.origin[0], rule.origin[1])

func _setup_grid(floor, rule: Dictionary) -> void:
	floor.grid.clear()
	floor.grid.region = Rect2i(0, 0, int(rule.size[0]), int(rule.size[1]))
	floor.grid.cell_size = Vector2.ONE * _cell
	floor.grid.offset = _origin
	floor.grid.update()
	floor.grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	floor.grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	floor.grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	floor.solid.clear()

## True when this source has a vertical overlap with the floor's band.
func _belongs(source: Dictionary, floor, split: bool) -> bool:
	if not split:
		return true
	var low := float(source.get("min_y", -1000000.0))
	var high := float(source.get("max_y", 1000000.0))
	if high <= floor.min_y + 0.05 or low >= floor.max_y:
		return false
	# A thin slab whose top sits on this floor's walking height is the floor
	# itself, not a wall.  Other thin props (table tops, shelf boards) still
	# block: only the surface the floor stands on is dropped.
	if high - low <= SLAB_HEIGHT and absf(high - floor.ground_y) <= 0.15:
		return false
	return true

## Mark only the cells a single collision rectangle can cover.
func _stamp(source: Dictionary, floor) -> void:
	if not is_instance_valid(source.body) or source.body.collision_layer == 0:
		return
	var rect: Rect2 = source.rect.grow(clearance)
	for id in _cell_range(rect):
		if not floor.grid.is_in_boundsv(id):
			continue
		var point: Vector2 = floor.grid.get_point_position(id)
		if rect.has_point(point) and not floor.solid.has(id):
			floor.solid[id] = true
			floor.grid.set_point_solid(id, true)

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
	var split := floors.size() > 1
	var grow := area.grow(clearance + _cell)
	var cells := _cell_range(grow)
	for floor in floors:
		for id in cells:
			if floor.solid.has(id):
				floor.solid.erase(id)
				floor.grid.set_point_solid(id, false)
		for source in sources:
			if is_instance_valid(source.body) and source.body.collision_layer != 0 \
					and source.rect.grow(clearance).intersects(grow) \
					and _belongs(source, floor, split):
				_stamp(source, floor)
	revision += 1

func cell(pos: Vector3) -> Vector2i:
	var p := (Vector2(pos.x, pos.z) - _origin) / _cell
	return Vector2i(roundi(p.x), roundi(p.y))

## Index of the floor whose band contains `height`; clamps to the nearest band.
func floor_index(height: float) -> int:
	if floors.is_empty():
		return 0
	for i in floors.size():
		var floor = floors[i]
		if height >= floor.min_y - 0.05 and height < floor.max_y:
			return i
	return 0 if height < floors[0].min_y else floors.size() - 1

func ground_y(index: int) -> float:
	if floors.is_empty():
		return 0.0
	return floors[clampi(index, 0, floors.size() - 1)].ground_y

func nearest(pos: Vector3) -> Vector2i:
	return nearest_in(pos, floor_index(pos.y))

func nearest_in(pos: Vector3, index: int) -> Vector2i:
	if floors.is_empty():
		return Vector2i(-1, -1)
	var floor = floors[clampi(index, 0, floors.size() - 1)]
	var center := cell(pos)
	var best := Vector2i(-1, -1)
	var distance := INF
	for y in range(center.y - 2, center.y + 3):
		for x in range(center.x - 2, center.x + 3):
			var id := Vector2i(x, y)
			if floor.grid.is_in_boundsv(id) and not floor.grid.is_point_solid(id):
				var d: float = floor.grid.get_point_position(id).distance_squared_to(Vector2(pos.x, pos.z))
				if d < distance:
					best = id
					distance = d
	return best

## Plan across floors when needed.  The whole request costs one budget slot so a
## two-leg route cannot starve the other actors waiting for a plan.
func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if floors.is_empty():
		return PackedVector3Array()
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_used = 0
	if _budget_used >= PATH_BUDGET:
		return PackedVector3Array()
	_budget_used += 1
	var start_floor := floor_index(from.y)
	var end_floor := floor_index(to.y)
	if start_floor == end_floor:
		return _plan(start_floor, from, to)
	var link := _stair_between(start_floor, end_floor)
	if link.is_empty():
		# No way up: stay on this floor instead of returning a straight line
		# through a wall.
		return _plan(start_floor, from, to)
	var near: Vector3 = _link_point(link, start_floor)
	var far: Vector3 = _link_point(link, end_floor)
	var result := _plan(start_floor, from, near)
	if result.is_empty():
		result = PackedVector3Array([near])
	result.append_array(_ramp(near, far))
	var upper := _plan(end_floor, far, to)
	if upper.is_empty():
		upper = PackedVector3Array([to])
	result.append_array(upper)
	return result

func _plan(index: int, from: Vector3, to: Vector3) -> PackedVector3Array:
	if floors.is_empty():
		return PackedVector3Array()
	var floor = floors[clampi(index, 0, floors.size() - 1)]
	var start := nearest_in(from, index)
	var end := nearest_in(to, index)
	var result := PackedVector3Array()
	if start.x < 0 or end.x < 0:
		return result
	for point in floor.grid.get_point_path(start, end, true):
		result.append(Vector3(point.x, floor.ground_y, point.y))
	return result

func _stair_between(from_floor: int, to_floor: int) -> Dictionary:
	for link in stairs:
		var a := int(link.get("from", 0))
		var b := int(link.get("to", 1))
		if (a == from_floor and b == to_floor) or (a == to_floor and b == from_floor):
			return link
	return {}

## Contact point of a stair on the given floor, in world space.
func _link_point(link: Dictionary, index: int) -> Vector3:
	var on_bottom := int(link.from) == index
	var point: Array = link.bottom if on_bottom else link.top
	return Vector3(float(point[0]), ground_y(index), float(point[1]))

func _ramp(near: Vector3, far: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	var steps := 4
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		result.append(near.lerp(far, t))
	return result
