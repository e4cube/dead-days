extends RefCounted
## Reuses the Blender door GLB. Presentation never owns collision or durability.
static func apply(game, id: String, impact: bool=false) -> void:
    var leaf: Node3D=game.door_visuals[id]
    var previous: Tween=leaf.get_meta("impact_tween") if leaf.has_meta("impact_tween") else null
    if previous!=null and previous.is_valid(): previous.kill()
    leaf.visible=true
    leaf.position=Vector3(-.85,-1,0)
    leaf.rotation=Vector3.ZERO
    if game.model.DoorDamage.broken(game.model,id):
        var landed:=Vector3(-.85,-.90,.12)
        if impact:
            var tween:=leaf.create_tween().set_parallel(true)
            tween.tween_property(leaf,"rotation:x",PI*.5,.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
            tween.tween_property(leaf,"position",landed,.38)
            leaf.set_meta("impact_tween",tween)
        else:
            leaf.rotation.x=PI*.5
            leaf.position=landed
    elif game.model.state.doors[id]:
        leaf.rotation.y=-PI*.5
    elif impact:
        var tween:=leaf.create_tween()
        tween.tween_property(leaf,"rotation:y",.035,.045)
        tween.tween_property(leaf,"rotation:y",-.018,.065)
        tween.tween_property(leaf,"rotation:y",0.0,.09)
        leaf.set_meta("impact_tween",tween)
