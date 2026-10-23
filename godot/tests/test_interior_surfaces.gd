extends SceneTree
var failures := 0
func check(value: bool, message: String) -> void:
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func shot(name: String) -> void:
    for i in 5:
        await process_frame
    if DisplayServer.get_name()!="headless":
        root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../work/surface-"+name+".png"))
func _initialize() -> void:
    call_deferred("run")
func run() -> void:
    var game = load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.new_run()
    game.active=false
    var materials: Dictionary = game.house_details.get_meta("surface_materials")
    check(materials.size()==8,"shared wood fabric ceramic metal recipes loaded")
    var count := 0
    var basin: MeshInstance3D
    var feet := 0
    for mesh in game.house_details.find_children("*","MeshInstance3D",true,false):
        if mesh.material_override is ShaderMaterial:
            count+=1
        if str(mesh.name).begins_with("DD_Keep_Sink") and not "Drain" in str(mesh.name):
            basin=mesh
        if str(mesh.name).begins_with("DD_Keep_SofaFoot"):
            feet+=1
    check(count>50 and feet==4,"actual imported furnishings use shared surfaces and sofa has support feet")
    check(basin!=null and basin.get_aabb().size.y>.15,"sink retains a real deep basin")
    check(not game.house_details.find_children("DD_Keep_Kitchen","MeshInstance3D",true,false).size(),"solid block beneath sink replaced by cabinet frame")
    var collider_count: int = game.nav_sources.size()
    # Asset detail preview only: fixture camera, not an end-to-end player screenshot.
    game.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
    game.camera.fov=68
    game.player_visual.hide()
    for child in game.get_children():
        if child is CanvasLayer:
            child.visible=false
    for child in game.world.get_children():
        if child is Label3D:
            child.visible=false
    game.camera.position=Vector3(-5.6,1.65,-4.7)
    game.camera.look_at(Vector3(-4.75,.92,-3.5))
    await shot("kitchen-detail-preview")
    game.camera.position=Vector3(-7.25,1.35,-2.3)
    game.camera.look_at(Vector3(-9.1,.5,-1))
    await shot("living-detail-preview")
    check(game.nav_sources.size()==collider_count,"surface previews do not replace collision geometry")
    print("INTERIOR_SURFACES_OK" if failures==0 else "INTERIOR_SURFACES_FAILED")
    quit(0 if failures==0 else 1)
