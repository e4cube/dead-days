extends RefCounted
## Modular layout in world metres. Collisions share the same dimensions as Blender.
const Assets = preload("res://scripts/asset_library.gd")
static func build(game: Node3D) -> Node3D:
    var details := Assets.attach(game.world, "house_details", Vector3(-7,0,0))
    for spec in [[-2.35,.7],[1.72,2.06]]:
        game.collision_box(Vector3(-7+spec[0],1.15,-2.05), Vector3(spec[1],2.3,.12))
    game.collision_box(Vector3(-7.65,1.15,-3.95),Vector3(.12,2.3,2.1))
    # Furniture keeps central entry and both bedroom/kitchen archways clear.
    for spec in [[-2.15,-1.0,.85,.8,1.85],[-1.15,-1.0,.55,.45,1.0],[2.25,-3.25,.88,1.0,1.8],[2.12,-4.5,.95,1.8,.75],[-2.45,-4.5,.4,1.9,.65]]:
        game.collision_box(Vector3(-7+spec[0],spec[3]/2,spec[1]),Vector3(spec[2],spec[3],spec[4]))
    for i in range(18):
        var x := -12.0 + float(i%9)*3.0
        var z := -8.0 if i<9 else 7.0
        var tree := Assets.attach(game.world,"tree_oak",Vector3(x,0,z))
        tree.rotation.y = i*1.7
        tree.scale = Vector3.ONE * (0.72 + (i%3)*.12)
        game.collision_box(Vector3(x,.7,z),Vector3(.28,1.4,.28))
    var lamp := OmniLight3D.new()
    lamp.name = "HouseLamp"
    lamp.position = Vector3(-7,2.05,-2.6)
    lamp.light_color = Color("ffd89b")
    lamp.light_energy = 1.8
    lamp.omni_range = 6.0
    # One local light, no expensive per-tree or per-prop dynamic shadow lights.
    lamp.shadow_enabled = true
    lamp.visible = game.model.state.get("house_light", true)
    game.world.add_child(lamp)
    game.box(game.world,Vector3(-7,2.2,-2.6),Vector3(.45,.12,.45),Color("e4cf9a"),false)
    return details
