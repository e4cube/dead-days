extends RefCounted
const Firearms=preload("res://scripts/firearms.gd")
static func ensure(model) -> void:
    if not model.state.has("ground_drops"):
        model.state.ground_drops={}
        model.state.drop_sequence=0

static func valid_place(model,p: Array) -> bool:
    if not model.valid_position(p): return false
    var on_floor: bool=absf(p[1])<=.01
    for floor_rule in model.rules.get("drop_floors",[]):
        var r: Array=floor_rule.rect
        if Rect2(r[0],r[1],r[2],r[3]).has_point(Vector2(p[0],p[2])) and absf(p[1]-float(floor_rule.height))<.01:
            on_floor=true
    if not on_floor: return false
    var b: Dictionary=model.rules.world_bounds
    return p[0]>=b.min_x and p[0]<=b.max_x and p[2]>=b.min_z and p[2]<=b.max_z

static func valid(model,candidate: Dictionary) -> bool:
    if not candidate.has("ground_drops") and not candidate.has("drop_sequence"):
        return true
    if not candidate.get("ground_drops") is Dictionary or not model.integer(candidate.get("drop_sequence"),0,1e12):
        return false
    if candidate.ground_drops.size()>int(model.rules.ground_drops.max_places):
        return false
    for id in candidate.ground_drops:
        var d: Variant=candidate.ground_drops[id]
        if not d is Dictionary or not model.integer(d.get("sequence"),1,candidate.drop_sequence) or id!="ground_%010d"%int(d.sequence) or not d.get("position") is Array or not valid_place(model,d.position):
            return false
        if not d.get("room") is String or (d.room!="" and not candidate.doors.has(d.room)):
            return false
        if not candidate.containers.get(id) is Dictionary or not model.valid_items(candidate.containers[id]):
            return false
        var weight:=0.0
        for item in candidate.containers[id]: weight+=float(model.rules.items[item].weight)*float(candidate.containers[id][item])
        if weight>float(model.rules.ground_drops.capacity)+.0001: return false
    return true

static func reason(model,item: String) -> String:
    if model.state.stats.health<=0 or model.state.rest.active or not model.rules.items.has(item) or model.state.inventory.get(item,0)<=0:
        return "当前没有可放下的物品"
    if item=="pistol" and (Firearms.loaded(model)>0 or model.state.get("firearms",{}).get("reload_left",0)>0):
        return "手枪须结束装填并按U卸弹后才能放下"
    return ""

static func put_one(model,item: String,at: Vector3,room: String) -> String:
    if not reason(model,item).is_empty(): return ""
    var height:=0.0
    for floor_rule in model.rules.get("drop_floors",[]):
        var r: Array=floor_rule.rect
        if absf(at.y-float(floor_rule.height))<.5 and Rect2(r[0],r[1],r[2],r[3]).has_point(Vector2(at.x,at.z)):
            height=float(floor_rule.height)
    if absf(at.y-height)>.5: return "" # Unsupported mezzanines/stairs must not drop through a floor.
    if not valid_place(model,[at.x,height,at.z]) or (room!="" and not model.state.doors.has(room)): return ""
    ensure(model)
    var id: String=""
    var empty: String=""
    for candidate in model.state.ground_drops:
        var d: Dictionary=model.state.ground_drops[candidate]
        var p: Array=d.position
        if absf(p[1]-height)<.1 and Vector2(p[0]-at.x,p[2]-at.z).length()<=float(model.rules.ground_drops.merge_distance) and d.room==room:
            id=candidate
            break
        if model.container_weight(candidate)==0: empty=candidate
    if id.is_empty():
        if not empty.is_empty():
            id=empty # Reuse an empty slot; never delete IDs referenced by journal entries.
        elif model.state.ground_drops.size()<int(model.rules.ground_drops.max_places):
            model.state.drop_sequence+=1
            id="ground_%010d"%int(model.state.drop_sequence)
            model.state.containers[id]={}
            model.state.ground_drops[id]={"sequence":model.state.drop_sequence}
        else:
            return ""
        model.state.ground_drops[id].position=[at.x,height,at.z]
        model.state.ground_drops[id].room=room
    if model.container_weight(id)+float(model.rules.items[item].weight)>float(model.rules.ground_drops.capacity)+.0001:
        return ""
    model.state.inventory[item]-=1
    model.state.containers[id][item]=model.state.containers[id].get(item,0)+1
    if model.state.inventory[item]==0 and model.state.combat.equipped==item: model.state.combat.equipped="fists"
    model.event("dropped","放下"+model.rules.items[item].name+" ×1。","平静",{"item":item,"count":1,"container":id,"position":[at.x,height,at.z]})
    return id
