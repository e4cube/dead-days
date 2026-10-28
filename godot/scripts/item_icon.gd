extends Control
## Square item badge. Kept separate from the list so the same glyph can be
## reused in the detail header and the map legend.

var item_id := ""
var pixels := 28.0
var dimmed := false

func setup(id: String, side: float = 28.0) -> void:
	item_id = id
	pixels = side
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	queue_redraw()

func set_dimmed(value: bool) -> void:
	dimmed = value
	modulate = Color(1, 1, 1, 0.45) if value else Color.WHITE
	queue_redraw()

func _draw() -> void:
	if item_id.is_empty():
		return
	var box := minf(size.x, size.y)
	var at := Vector2((size.x - box) * 0.5, (size.y - box) * 0.5)
	var tint := preload("res://scripts/item_icons.gd").color_for(item_id)
	draw_rect(Rect2(Vector2.ZERO, size), Color(tint.r, tint.g, tint.b, 0.10))
	draw_rect(Rect2(Vector2.ZERO, size), Color(tint.r, tint.g, tint.b, 0.35), false, 1.0)
	preload("res://scripts/item_icons.gd").draw(self, item_id, at, box)
