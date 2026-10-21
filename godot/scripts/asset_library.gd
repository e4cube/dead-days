extends RefCounted
## Asset instantiation only; imported GLBs never own authoritative gameplay collisions.
static func attach(parent: Node3D, id: String, offset: Vector3 = Vector3.ZERO) -> Node3D:
    var instance: Node3D = load("res://assets/" + id + ".glb").instantiate()
    parent.add_child(instance)
    instance.position = offset
    return instance

static func cutaway(instance: Node3D, enabled: bool) -> void:
    for mesh in instance.find_children("*", "MeshInstance3D", true, false):
        if str(mesh.name).begins_with("DD_Hide_"):
            mesh.visible = not enabled
        elif str(mesh.name).begins_with("DD_Cut_"):
            mesh.visible = enabled
