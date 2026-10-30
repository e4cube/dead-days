extends RefCounted
## Procedural item glyphs drawn with primitive shapes.
##
## The project deliberately ships no external icon sheets, so every glyph is
## derived from the item id.  Drawing uses a normalised 0..1 box so one routine
## serves the 24 px list badge, the 40 px detail header and the map legend.

const COLORS := {
	"food": Color("c8a45c"),
	"water": Color("6fa8c8"),
	"bandage": Color("e8e2d4"),
	"antiseptic": Color("a7d8e8"),
	"suture_kit": Color("cfd4d8"),
	"antibiotic": Color("e8e0a0"),
	"club": Color("9a7550"),
	"pistol": Color("8a8f96"),
	"ammo_9mm": Color("c9a227"),
}

static func color_for(id: String) -> Color:
	return COLORS.get(id, Color("9aa39a"))

## `origin` is the top-left of the square that contains the glyph.
static func draw(canvas: CanvasItem, id: String, origin: Vector2, box: float) -> void:
	var base := color_for(id)
	var line := maxf(1.0, box * 0.055)
	match id:
		"food":
			# Tin can: body, lid rim, paper label band.
			canvas.draw_rect(Rect2(origin + Vector2(0.26, 0.24) * box, Vector2(0.48, 0.56) * box), base)
			canvas.draw_rect(Rect2(origin + Vector2(0.26, 0.20) * box, Vector2(0.48, 0.09) * box), base.lightened(0.35))
			canvas.draw_rect(Rect2(origin + Vector2(0.26, 0.42) * box, Vector2(0.48, 0.16) * box), base.darkened(0.42))
			canvas.draw_rect(Rect2(origin + Vector2(0.26, 0.24) * box, Vector2(0.48, 0.56) * box), base.darkened(0.55), false, line)
		"water":
			# Bottle: neck, shoulders, body with a visible water level.
			canvas.draw_rect(Rect2(origin + Vector2(0.42, 0.14) * box, Vector2(0.16, 0.12) * box), base.lightened(0.2))
			canvas.draw_rect(Rect2(origin + Vector2(0.32, 0.26) * box, Vector2(0.36, 0.58) * box), base.darkened(0.15))
			canvas.draw_rect(Rect2(origin + Vector2(0.32, 0.50) * box, Vector2(0.36, 0.34) * box), base)
			canvas.draw_rect(Rect2(origin + Vector2(0.32, 0.26) * box, Vector2(0.36, 0.58) * box), base.darkened(0.55), false, line)
		"bandage":
			# Rolled bandage seen from the side, with a loose tail.
			canvas.draw_circle(origin + Vector2(0.46, 0.46) * box, box * 0.22, base)
			canvas.draw_circle(origin + Vector2(0.46, 0.46) * box, box * 0.10, base.darkened(0.35))
			canvas.draw_line(origin + Vector2(0.62, 0.60) * box, origin + Vector2(0.80, 0.76) * box, base, box * 0.09)
			canvas.draw_arc(origin + Vector2(0.46, 0.46) * box, box * 0.22, 0.0, TAU, 20, base.darkened(0.5), line, true)
		"club":
			# Tapered wooden club on a diagonal.
			canvas.draw_line(origin + Vector2(0.24, 0.78) * box, origin + Vector2(0.74, 0.22) * box, base, box * 0.13)
			canvas.draw_line(origin + Vector2(0.66, 0.30) * box, origin + Vector2(0.78, 0.18) * box, base.lightened(0.25), box * 0.22)
			canvas.draw_circle(origin + Vector2(0.24, 0.78) * box, box * 0.05, base.darkened(0.35))
		"pistol":
			# Slide, frame and grip silhouette.
			canvas.draw_rect(Rect2(origin + Vector2(0.18, 0.34) * box, Vector2(0.56, 0.13) * box), base)
			canvas.draw_rect(Rect2(origin + Vector2(0.18, 0.47) * box, Vector2(0.26, 0.10) * box), base.darkened(0.15))
			canvas.draw_colored_polygon(PackedVector2Array([
				origin + Vector2(0.44, 0.47) * box,
				origin + Vector2(0.56, 0.47) * box,
				origin + Vector2(0.50, 0.76) * box,
				origin + Vector2(0.38, 0.76) * box,
			]), base.darkened(0.25))
			canvas.draw_rect(Rect2(origin + Vector2(0.18, 0.34) * box, Vector2(0.56, 0.13) * box), base.darkened(0.55), false, line)
		"antiseptic":
			# Screw-top bottle with a cross label: the only thing that makes a
			# dirty wound survivable.
			canvas.draw_rect(Rect2(origin + Vector2(0.34, 0.30) * box, Vector2(0.32, 0.50) * box), base.darkened(0.10))
			canvas.draw_rect(Rect2(origin + Vector2(0.42, 0.20) * box, Vector2(0.16, 0.10) * box), base.lightened(0.25))
			canvas.draw_rect(Rect2(origin + Vector2(0.46, 0.44) * box, Vector2(0.08, 0.22) * box), Color("8a2f2f"))
			canvas.draw_rect(Rect2(origin + Vector2(0.39, 0.51) * box, Vector2(0.22, 0.08) * box), Color("8a2f2f"))
			canvas.draw_rect(Rect2(origin + Vector2(0.34, 0.30) * box, Vector2(0.32, 0.50) * box), base.darkened(0.55), false, line)
		"suture_kit":
			# Curved needle with a trailing thread on a folded cloth.
			canvas.draw_rect(Rect2(origin + Vector2(0.22, 0.56) * box, Vector2(0.56, 0.20) * box), base.darkened(0.20))
			canvas.draw_arc(origin + Vector2(0.50, 0.44) * box, box * 0.20, 0.6, 3.6, 18, base.lightened(0.35), line * 1.4, true)
			canvas.draw_line(origin + Vector2(0.50, 0.62) * box, origin + Vector2(0.30, 0.80) * box, base, line)
			canvas.draw_rect(Rect2(origin + Vector2(0.22, 0.56) * box, Vector2(0.56, 0.20) * box), base.darkened(0.55), false, line)
		"antibiotic":
			# Two-tone capsule: half the only real cure for a bite.
			canvas.draw_rect(Rect2(origin + Vector2(0.22, 0.40) * box, Vector2(0.56, 0.20) * box), base)
			canvas.draw_rect(Rect2(origin + Vector2(0.22, 0.40) * box, Vector2(0.28, 0.20) * box), base.darkened(0.35))
			canvas.draw_rect(Rect2(origin + Vector2(0.22, 0.40) * box, Vector2(0.56, 0.20) * box), base.darkened(0.55), false, line)
		"ammo_9mm":
			# Two upright cartridges with brass cases and copper tips.
			for offset in [0.32, 0.56]:
				var x: float = offset
				canvas.draw_rect(Rect2(origin + Vector2(x, 0.42) * box, Vector2(0.12, 0.34) * box), Color("c9a227"))
				canvas.draw_colored_polygon(PackedVector2Array([
					origin + Vector2(x, 0.42) * box,
					origin + Vector2(x + 0.12, 0.42) * box,
					origin + Vector2(x + 0.06, 0.24) * box,
				]), Color("b0703a"))
				canvas.draw_rect(Rect2(origin + Vector2(x, 0.72) * box, Vector2(0.12, 0.05) * box), Color("8a6a1f"))
		_:
			canvas.draw_rect(Rect2(origin + Vector2(0.25, 0.25) * box, Vector2(0.5, 0.5) * box), base, false, line)
