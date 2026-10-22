extends RefCounted
const Assets = preload("res://scripts/asset_library.gd")

static func build(game: Node3D) -> void:
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/street_art.json"))
    var lamps: Array = []
    for definition in data.props:
        var p: Array = definition.position
        var at := Vector3(p[0],p[1],p[2])
        var visual := Assets.attach(game.world,definition.asset,at)
        visual.name = "StreetArt_"+definition.id
        visual.rotation.y = definition.get("yaw",0.0)
        if definition.has("collision"):
            var size: Array = definition.collision
            var body: Node3D = game.collision_box(at+Vector3.UP*float(size[1])*.5,Vector3(size[0],size[1],size[2]))
            body.name = "StreetObstacle_"+definition.id
        if definition.asset == "street_lamp":
            var light := OmniLight3D.new()
            light.position = at + Vector3(.73,2.58,0).rotated(Vector3.UP,visual.rotation.y)
            light.light_color = Color("ffddb0")
            light.omni_range = 4.5
            light.shadow_enabled = false
            game.world.add_child(light)
            lamps.append(light)
    game.world.set_meta("street_lamps",lamps)
    # A single shared mesh and MultiMesh batch for all grass placements.
    var template: Node3D = load("res://assets/grass_clump.glb").instantiate()
    var meshes := template.find_children("*","MeshInstance3D",true,false)
    var batch := MultiMeshInstance3D.new()
    batch.name = "StreetGrass"
    batch.multimesh = MultiMesh.new()
    batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
    batch.multimesh.mesh = meshes[0].mesh
    batch.multimesh.instance_count = data.grass.size()
    batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    batch.visibility_range_end = 45
    for i in data.grass.size():
        var p: Array = data.grass[i]
        var basis := Basis(Vector3.UP,float(i)*2.399963).scaled(Vector3.ONE*float(p[2]))
        batch.multimesh.set_instance_transform(i,Transform3D(basis,Vector3(p[0],.025,p[1])))
    game.world.add_child(batch)
    template.free()

static func lighting(game: Node3D, day: float) -> void:
    for lamp in game.world.get_meta("street_lamps",[]):
        lamp.light_energy = (1-day)*.85
        lamp.visible = day < .95
