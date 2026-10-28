extends SceneTree
var failures:=0
func check(value: bool,message: String):
    if not value:
        failures+=1
        printerr("FAIL: ",message)
func _initialize():
    call_deferred("run")
func run():
    var game=load("res://main.tscn").instantiate()
    root.add_child(game)
    await process_frame
    var body:=StaticBody3D.new()
    root.add_child(body)
    game.nav_sources=[{"body":body,"rect":Rect2(0,0,1,1)}]
    game.navigation.rebuild(game.nav_sources,game.model.rules.navigation)
    var corner:=Vector3(1.2,0,1.2)
    check(game.safe_position(corner)==corner,"circular actor clears rectangular corner")
    var contact:=Vector3(1.27994,0,.5)
    check(game.safe_position(contact)==contact,"sub-millimetre contact roundoff does not move saved actor")
    var penetration:=Vector3(1.2,0,.5)
    check(game.safe_position(penetration).distance_to(penetration)>.01,"real penetration still moves to walkable cell")
    body.collision_layer=0
    check(game.safe_position(Vector3(.5,0,.5))==Vector3(.5,0,.5),"open door rectangle does not relocate actor")
    body.queue_free()
    print("RESTORE_POSITIONS_OK" if failures==0 else "RESTORE_POSITIONS_FAILED")
    quit(0 if failures==0 else 1)
