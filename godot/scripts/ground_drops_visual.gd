extends RefCounted
const Assets=preload("res://scripts/asset_library.gd")
static func update(game: Node3D) -> void:
    for id in game.model.state.ground_drops:
        var occupied: bool=game.model.container_weight(id)>0
        if not game.ground_visuals.has(id):
            if not occupied: continue
            var holder:=Node3D.new()
            holder.name="GroundItems_"+id
            game.world.add_child(holder)
            var visual:=Assets.attach(holder,"loot_crate")
            visual.scale=Vector3.ONE*.30
            game.label3(holder,"落地物资 [E / B]",Vector3(0,.75,0))
            game.ground_visuals[id]=holder
        var d: Dictionary=game.model.state.ground_drops[id]
        game.ground_visuals[id].position=Vector3(d.position[0],float(d.position[1])+.025,d.position[2])
        game.ground_visuals[id].visible=occupied
