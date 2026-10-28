extends Control
## Schematic world-coordinate map; never samples hidden inventories or enemies.
##
## Layers, back to front: discovered regions, roads, building footprints,
## observed container state, markers, player.  A container is drawn hollow until
## the player has actually opened or stored into it, so untouched loot stays
## secret; the state shown is the last observation, never a live reading.
var game
var zoom:=1.0
var pan:=Vector2.ZERO
var floor_index:=0
var marker_text: LineEdit
var dragging:=false

const COLOR_FLOOR := Color("182321")
const COLOR_UNSEEN := Color("26332e")
const COLOR_SEEN := Color("48564b")
const COLOR_EDGE := Color("84927e")
const COLOR_ROAD := Color("3d4340")
const COLOR_ROAD_EDGE := Color("5c6358")
const COLOR_BUILDING := Color("6b6350")
const COLOR_BUILDING_EDGE := Color("ad9d78")
const COLOR_BASE := Color("c9954a")
const COLOR_CONTAINER := Color("c8b482")

func scale_factor() -> float:
    return maxf(.001,minf(size.x/225.0,size.y/145.0))*zoom
func to_screen(at: Vector2) -> Vector2:
    return size*.5+(at-Vector2(90,-14))*scale_factor()+pan
func to_world(at: Vector2) -> Vector2:
    return (at-size*.5-pan)/scale_factor()+Vector2(90,-14)

func _rect_world(r: Array) -> Rect2:
    return Rect2(to_screen(Vector2(r[0],r[1])),Vector2(r[2],r[3])*scale_factor())

func _draw() -> void:
    if game==null or game.model.state.is_empty(): return
    draw_rect(Rect2(Vector2.ZERO,size),COLOR_FLOOR)
    var definition: Dictionary=game.model.world_definition
    var discovered: Array=game.model.state.exploration.discovered
    # 1. Regions: explored ground only.
    for region in definition.regions:
        var rect:=_rect_world(region.rect)
        var seen: bool=region.id in discovered
        draw_rect(rect,COLOR_SEEN if seen else COLOR_UNSEEN)
        draw_rect(rect,COLOR_EDGE,false,1)
    # 2. Roads drawn as filled bands so they read as travel space, not land.
    for road in definition.get("roads",[]):
        var rect:=_rect_world(road.rect)
        draw_rect(rect,COLOR_ROAD)
        draw_rect(rect,COLOR_ROAD_EDGE,false,1)
    # 3. Building footprints on the current floor.
    for structure in definition.get("structures",[]):
        if int(structure.get("floor",0))!=(1 if floor_index==1 else 0): continue
        var rect:=_rect_world(structure.rect)
        draw_rect(rect,COLOR_BUILDING)
        draw_rect(rect,COLOR_BUILDING_EDGE,false,1.5)
    for building in game.model.rules.buildings:
        if floor_index!=0: continue
        var box:=Rect2(to_screen(Vector2(building.x-3,-float(building.get("depth",7)))),
            Vector2(6,float(building.get("depth",7)))*scale_factor())
        draw_rect(box,COLOR_BUILDING)
        draw_rect(box,COLOR_BUILDING_EDGE,false,1.5)
    # 4. Base of operations.
    var base: String=game.model.base_id()
    for building in game.model.rules.buildings:
        if building.id!=base: continue
        var box:=Rect2(to_screen(Vector2(building.x-3,-float(building.get("depth",7)))),
            Vector2(6,float(building.get("depth",7)))*scale_factor())
        draw_rect(box.grow(2),COLOR_BASE,false,2)
        draw_string(ThemeDB.fallback_font,box.position+Vector2(0,-4),"据点",HORIZONTAL_ALIGNMENT_LEFT,-1,13,COLOR_BASE)
    # 5. Region labels.
    for region in definition.regions:
        var r: Array=region.rect
        var text_position:=to_screen(Vector2(r[0],r[1]+r[3]))+Vector2(5,-6)
        draw_string(ThemeDB.fallback_font,text_position,region.name if region.id in discovered else "未探索",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("d9d9bf"))
    # 6. Containers: hollow = never observed, filled = observed with loot, cross = observed empty.
    for definition_item in definition.containers:
        if definition_item.building not in discovered: continue
        var p: Array=definition_item.position
        if (p[1]>2.15)!=(floor_index==1): continue
        var point:=to_screen(Vector2(p[0],p[2]))
        var seen: Dictionary=game.model.observed(str(definition_item.id))
        if seen.is_empty():
            draw_arc(point,3.5,0,TAU,12,COLOR_CONTAINER,1.2,true)
            continue
        if int(seen.get("count",0))<=0:
            draw_line(point+Vector2(-3,-3),point+Vector2(3,3),Color("7b817a"),1.5)
            draw_line(point+Vector2(-3,3),point+Vector2(3,-3),Color("7b817a"),1.5)
            continue
        draw_circle(point,3.5,COLOR_CONTAINER)
        draw_string(ThemeDB.fallback_font,point+Vector2(6,-4),"%d件"%int(seen.get("count",0)),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e8ddc1"))
    # 7. Player markers, matched to the floor.
    for marker in game.model.state.exploration.markers:
        if (marker.position[1]>2.15)!=(floor_index==1): continue
        var point:=to_screen(Vector2(marker.position[0],marker.position[2]))
        draw_circle(point,5,Color("dfac60"))
        draw_string(ThemeDB.fallback_font,point+Vector2(8,-5),marker.text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f1d9ad"))
    var at: Vector3=game.player.position
    if (at.y>2.15)==(floor_index==1):
        var p:=to_screen(Vector2(at.x,at.z))
        var direction:=Vector2(sin(game.player.rotation.y),cos(game.player.rotation.y))
        draw_circle(p,6,Color("e9efb6"))
        draw_line(p,p+direction*18,Color("e9efb6"),3)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_LEFT: dragging=event.pressed
        if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
            zoom=clampf(zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),.6,5)
        if event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
            var p:=to_world(event.position)
            game.model.mark(Vector3(p.x,3.62 if floor_index==1 else 0,p.y),marker_text.text if not marker_text.text.is_empty() else "待探索")
        queue_redraw()
        accept_event()
    if event is InputEventMouseMotion and dragging:
        pan+=event.relative
        queue_redraw()
