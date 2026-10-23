extends RefCounted
## One reviewed base-color map, shared by the outdoor ground only.
const TEXTURE_PATH := "res://assets/external/aerial_grass_rock_diff_1k.png"

static func apply(ground: Node3D) -> void:
    var material := StandardMaterial3D.new()
    material.resource_name = "GameVado_CC0_AerialGrassRock"
    material.albedo_texture = load(TEXTURE_PATH)
    material.albedo_color = Color(.80, .82, .76)
    material.roughness = 1.0
    material.metallic = 0.0
    # World-space projection avoids stretching the 27x19m BoxMesh UV islands.
    material.uv1_triplanar = true
    material.uv1_world_triplanar = true
    material.uv1_scale = Vector3.ONE / 6.0
    material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    for mesh in ground.find_children("*", "MeshInstance3D", true, false):
        mesh.material_override = material
