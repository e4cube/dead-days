extends RefCounted
## Presentation-only quality tiers.
##
## Nothing here changes simulation: enemy count, perception, damage, noise and
## saves are identical on every tier.  Only shadows, draw distance, vegetation
## distance and on-screen enemy render radius differ, so a low-end laptop can
## keep the same world while dropping the expensive parts.
##
## The player's choice is stored in user://settings.cfg and applied after the
## world is assembled, so a reload keeps the tier.

const PATH := "user://settings.cfg"
const ORDER := ["low", "medium", "high"]
const LABELS := {
	"low": "低：集显 / 普通笔记本",
	"medium": "中：默认",
	"high": "高：独立显卡",
}
const PRESETS := {
	"low": {
		"shadow": false,
		"shadow_size": 1024,
		"shadow_distance": 24.0,
		"scene_distance": 40.0,
		"grass_distance": 20.0,
		"enemy_distance": 40.0,
		"hud_interval": 140,
	},
	"medium": {
		"shadow": true,
		"shadow_size": 2048,
		"shadow_distance": 45.0,
		"scene_distance": 60.0,
		"grass_distance": 45.0,
		"enemy_distance": 60.0,
		"hud_interval": 100,
	},
	"high": {
		"shadow": true,
		"shadow_size": 4096,
		"shadow_distance": 70.0,
		"scene_distance": 90.0,
		"grass_distance": 60.0,
		"enemy_distance": 80.0,
		"hud_interval": 80,
	},
}

static func preset(id: String) -> Dictionary:
	return PRESETS.get(id, PRESETS.medium).duplicate()

static func load_choice() -> String:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return "medium"
	var stored := str(config.get_value("video", "quality", "medium"))
	return stored if PRESETS.has(stored) else "medium"

static func store_choice(id: String) -> void:
	if not PRESETS.has(id):
		return
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("video", "quality", id)
	config.save(PATH)

static func next(id: String) -> String:
	var index := ORDER.find(id)
	return ORDER[(index + 1) % ORDER.size()]

static func label(id: String) -> String:
	return str(LABELS.get(id, id))
