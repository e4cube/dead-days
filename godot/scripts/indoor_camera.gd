extends RefCounted
static func position_for(game: Node3D, target: Vector3, desired: Vector3) -> Vector3:
    var distance := target.distance_to(desired)
    var direction := target.direction_to(desired)
    # Five probes reserve near-plane clearance around the camera, not only its centre.
    var side := direction.cross(Vector3.UP).normalized()*.13
    for offset in [Vector3.ZERO,side,-side,Vector3.UP*.13,Vector3.DOWN*.13]:
        var query := PhysicsRayQueryParameters3D.create(target+offset,desired+offset,1,[game.player.get_rid()])
        var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            distance=minf(distance,maxf(.12,(hit.position-target-offset).length()-.18))
    return target+direction*distance
