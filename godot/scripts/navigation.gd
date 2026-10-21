extends RefCounted
## Navigation is derived from the same collision rectangles that build the world.
var grid := AStarGrid2D.new()
var revision := 0
var clearance := 0.32

func rebuild(sources: Array, rule: Dictionary) -> void:
    clearance = rule.clearance
    grid.region = Rect2i(0, 0, int(rule.size[0]), int(rule.size[1]))
    grid.cell_size = Vector2.ONE * float(rule.cell_size)
    grid.offset = Vector2(rule.origin[0], rule.origin[1])
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
    grid.update()
    for y in grid.region.size.y:
        for x in grid.region.size.x:
            var id := Vector2i(x, y)
            var point := grid.get_point_position(id)
            var blocked := false
            for source in sources:
                if is_instance_valid(source.body) and source.body.collision_layer != 0 and source.rect.grow(clearance).has_point(point):
                    blocked = true
                    break
            grid.set_point_solid(id, blocked)
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
    var start := nearest(from)
    var end := nearest(to)
    var result := PackedVector3Array()
    if start.x < 0 or end.x < 0:
        return result
    for point in grid.get_point_path(start, end, true):
        result.append(Vector3(point.x, 0, point.y))
    return result
