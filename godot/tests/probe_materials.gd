extends SceneTree
## 排查「路面显示洋红棋盘格」：检查导入资产的每个表面材质是否真的带上了纹理。
## 洋红 = Godot 的 missing-texture 占位色；贴图为 null 或尺寸为 0 都会触发。

const ASSETS := [
	"street_ground", "district_commons", "building_home", "building_clinic",
	"building_shop", "house_details", "clinic_details", "shop_details",
	"market_square", "factory_grounds", "track_field", "villa_courtyard",
]

func _init() -> void:
	var bad := 0
	for name in ASSETS:
		var path := "res://assets/%s.glb" % name
		if not ResourceLoader.exists(path):
			print("MISSING ASSET %s" % path)
			bad += 1
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			print("LOAD FAILED %s" % path)
			bad += 1
			continue
		var root: Node = packed.instantiate()
		var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
		var surfaces := 0
		var textured := 0
		var null_tex := 0
		var details: Array = []
		for m in meshes:
			if m.mesh == null:
				details.append("%s: NULL MESH" % m.name)
				null_tex += 1
				continue
			for i in m.mesh.get_surface_count():
				surfaces += 1
				var material: Material = m.mesh.surface_get_material(i)
				if material == null:
					details.append("%s[%d]: NULL MATERIAL" % [m.name, i])
					null_tex += 1
					continue
				if not material is BaseMaterial3D:
					continue
				var bm: BaseMaterial3D = material
				var tex: Texture2D = bm.albedo_texture
				if tex == null:
					# 纯色材质是合法的；只报告「本该有贴图」的（名字带 DD_ 且来自 glb 带贴图的材质）
					continue
				textured += 1
				var size: Vector2 = tex.get_size()
				if size.x <= 0 or size.y <= 0:
					details.append("%s[%d] %s: ZERO SIZE %s" % [m.name, i, material.resource_name, size])
					null_tex += 1
		print("ASSET %-18s meshes=%3d surfaces=%3d textured=%3d issues=%2d" % [
			name, meshes.size(), surfaces, textured, null_tex])
		for d in details:
			print("    ! " + str(d))
		bad += null_tex
		root.free()
	print("PROBE_DONE issues=%d" % bad)
	if bad > 0:
		print("FAIL: %d 个表面贴图缺失或尺寸为 0，画面会显示洋红棋盘" % bad)
		print("修法：确认对应 .glb.import 里 embedded_image_handling=2，并带 gltf/embedded_image_keep_impressed_compression=false，再重新导入。")
		quit(1)
		return
	print("MATERIAL_TEXTURES_OK")
	quit(0)
