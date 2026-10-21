extends RefCounted
## Modular layout in world metres. Collisions share the same dimensions as Blender.
const Assets = preload("res://scripts/asset_library.gd")
static func build(game: Node3D) -> Node3D:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house_layout.json"))
    var origin := Vector3.ZERO
    for definition in game.model.rules.buildings:
        if definition.id == layout.building:
            origin.x = definition.x
    var details := Assets.attach(game.world, "house_details", origin)
    for obstacle in layout.obstacles:
        var at: Array = obstacle.position
        var size: Array = obstacle.size
        var body: Node3D = game.collision_box(origin + Vector3(at[0],at[1],at[2]), Vector3(size[0],size[1],size[2]))
        body.name = "HouseObstacle_" + obstacle.id
    for i in range(18):
        var x := -12.0 + float(i%9)*3.0
        var z := -8.0 if i<9 else 7.0
        var tree := Assets.attach(game.world,"tree_oak",Vector3(x,0,z))
        tree.rotation.y = i*1.7
        tree.scale = Vector3.ONE * (0.72 + (i%3)*.12)
        game.collision_box(Vector3(x,.7,z),Vector3(.28,1.4,.28))
    var lamp := OmniLight3D.new()
    lamp.name = "HouseLamp"
    var at: Array = layout.lamp.position
    lamp.position = origin + Vector3(at[0],at[1],at[2])
    lamp.light_color = Color(layout.lamp.color)
    lamp.light_energy = layout.lamp.energy
    lamp.omni_range = layout.lamp.range
    # One local light, no expensive per-tree or per-prop dynamic shadow lights.
    lamp.shadow_enabled = true
    lamp.visible = game.model.state.get("house_light", true)
    game.world.add_child(lamp)
    game.box(game.world,lamp.position + Vector3.UP * .15,Vector3(.45,.12,.45),Color("e4cf9a"),false)
    return details
