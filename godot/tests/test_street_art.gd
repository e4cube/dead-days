extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ",message)
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/street_manifest.json"))
    check(manifest.assets.size()==7,"seven real reusable street assets")
    for id in manifest.assets:
        var entry: Dictionary = manifest.assets[id]
        var instance: Node3D = load("res://assets/"+entry.file).instantiate()
        root.add_child(instance)
        var meshes := instance.find_children("*","MeshInstance3D",true,false)
        var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
        var budget: float=(rules.world_bounds.max_x-rules.world_bounds.min_x)*90 if id=="street_ground" else 3000
        check(meshes.size()==entry.meshes and entry.triangles<budget,"street asset mesh/triangle budget "+id)
        check(instance.find_children("*","CollisionObject3D",true,false).is_empty(),"no duplicate imported collision "+id)
        for mesh in meshes:
            check(mesh.mesh.get_surface_count()>0,"real mesh geometry "+id)
        instance.queue_free()
    var game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.new_run()
    game.active=false
    check(game.world.has_node("StreetGround"),"modeled paving and road wear are integrated")
    for i in 3:
        await physics_frame
    var grass: MultiMeshInstance3D = game.world.get_node("StreetGrass")
    var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/street_art.json"))
    check(grass.multimesh.instance_count==data.grass.size() and data.grass.size()>200,"grass uses one MultiMesh batch")
    var car: Node3D = game.world.get_node("StreetObstacle_car_left")
    var registered := false
    for source in game.nav_sources:
        registered = registered or source.body==car
    check(registered and car.collision_layer==1,"car participates in physical navigation")
    check(not game.line_clear(Vector3(-10,0,3),Vector3(-10,0,6)),"car has real sight-blocking volume")
    check(game.navigation.path(Vector3(-10,0,3),Vector3(-10,0,6.2)).size()>10,"route goes around car")
    var lamps: Array = game.world.get_meta("street_lamps")
    var configured_lamps:=0
    for prop in data.props:
        if prop.asset=="street_lamp": configured_lamps+=1
    check(lamps.size()==configured_lamps and not lamps[0].visible,"configured daytime lamps are off")
    # Explicit lighting fixture; actual sleep/day progression is tested separately.
    game.model.state.minutes=1320
    game.update_lighting()
    check(lamps[0].visible and lamps[0].light_energy>.8 and not lamps[0].shadow_enabled,"night lights use bounded unshadowed local lighting")
    print("STREET_ART_OK" if failures==0 else "STREET_ART_FAILED")
    quit(0 if failures==0 else 1)
