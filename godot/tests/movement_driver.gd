extends RefCounted
## Produces real keyboard input for both outdoor world movement and indoor turn/walk.
static func drive(game: Node3D, difference: Vector2) -> void:
    if not game.isometric_camera and (game.inside("home") or game.inside("clinic") or game.inside("shop")):
        var direction := Vector2(signf(difference.x),0) if absf(difference.x)>.055 else Vector2(0,signf(difference.y))
        var angle := wrapf(atan2(direction.x,direction.y)-game.player.rotation.y,-PI,PI)
        if absf(angle)>.055:
            Input.action_press("right" if angle>0 else "left")
        else:
            Input.action_press("forward")
    elif absf(difference.x)>.055:
        Input.action_press("right" if difference.x>0 else "left")
    else:
        Input.action_press("back" if difference.y>0 else "forward")
