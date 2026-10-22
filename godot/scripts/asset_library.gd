extends RefCounted
## Asset instantiation only; imported GLBs never own authoritative gameplay collisions.
static func attach(parent: Node3D, id: String, offset: Vector3 = Vector3.ZERO) -> Node3D:
    var instance: Node3D = load("res://assets/" + id + ".glb").instantiate()
    parent.add_child(instance)
    instance.position = offset
    return instance

static func cutaway(instance: Node3D, enabled: bool, view: Vector3 = Vector3(1,1,1)) -> void:
    for mesh in instance.find_children("*", "MeshInstance3D", true, false):
        var name := str(mesh.name)
        var foreground := true
        if "_Front" in name:
            foreground = view.z >= 0
        elif "_East" in name:
            foreground = view.x >= 0
        elif "_Back" in name:
            foreground = view.z <= 0
        elif "_West" in name:
            foreground = view.x <= 0
        if name.begins_with("DD_Hide_"):
            mesh.visible = not enabled or (not foreground and ("_Front" in name or "_East" in name or "_Back" in name or "_West" in name))
        elif name.begins_with("DD_Cut_"):
            mesh.visible = enabled and foreground
        elif name in ["DD_Keep_Back", "DD_Keep_West"]:
            mesh.visible = not enabled or not foreground
