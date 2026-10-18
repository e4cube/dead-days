extends SceneTree
func _initialize() -> void:
    var packed: PackedScene = load("res://assets/loot_crate.glb")
    if packed == null:
        quit(1)
        return
    var asset := packed.instantiate()
    root.add_child(asset)
    var meshes := asset.find_children("*", "MeshInstance3D", true, false)
    if meshes.size() != 1:
        printerr("Expected exactly one crate mesh")
        quit(1)
        return
    var size: Vector3 = meshes[0].get_aabb().size
    if not size.is_equal_approx(Vector3(1.2, 1.0, 0.7)):
        printerr("Wrong imported dimensions: ", size)
        quit(1)
        return
    print("ASSET_IMPORT_OK / meters, Y-up / ", size)
    asset.queue_free()
    quit(0)
