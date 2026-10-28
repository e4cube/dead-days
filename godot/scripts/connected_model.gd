extends "res://scripts/survival.gd"
## Register the complete world before start/load validation, never during scene assembly.
var world_definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/connected_world.json"))

func _init() -> void:
    rules.street_bounds = rules.world_bounds.duplicate(true)
    rules.world_bounds = world_definition.bounds.duplicate(true)
    rules.world_revision = world_definition.revision
    rules.navigation = world_definition.navigation.duplicate(true)
    for spawn in world_definition.enemy_spawns: rules.zombie_spawns.append(spawn.duplicate(true))
    rules.drop_floors = world_definition.drop_floors.duplicate(true)
    rules.sites = world_definition.get("sites", []).duplicate(true)
    for definition in world_definition.containers:
        rules.containers.append(definition.duplicate(true))
    for definition in world_definition.beds:
        rules.beds.append(definition.duplicate(true))

func start() -> void:
    super.start()
    state.world_id = world_definition.id
    state.exploration={"discovered":[],"markers":[],"observed":{},"base":"home"}

func valid(candidate: Variant) -> bool:
    if not candidate is Dictionary: return false
    if candidate.has("world_id") and candidate.world_id != world_definition.id: return false
    if candidate.has("world_id") and int(candidate.get("world_revision", 0)) < 3: return false
    if not valid_position(candidate.get("position")): return false
    var p: Array=candidate.position
    var b: Dictionary=world_definition.bounds
    if p[0]<b.min_x or p[0]>b.max_x or p[2]<b.min_z or p[2]>b.max_z or p[1]<-.5 or p[1]>6.7: return false
    if candidate.has("world_id") and not candidate.has("exploration"): return false
    if candidate.has("exploration"):
        var e: Variant=candidate.exploration
        if not e is Dictionary or not e.get("discovered") is Array or not e.get("markers") is Array or e.markers.size()>64: return false
        var known:=[]
        for region in world_definition.regions: known.append(region.id)
        for id in e.discovered:
            if id not in known: return false
        for marker in e.markers:
            if not marker is Dictionary or not marker.get("text") is String or marker.text.length()>80 or not valid_position(marker.get("position")): return false
    return super.valid(candidate)

func restore(candidate: Dictionary) -> void:
    var previous_revision: int=int(candidate.get("world_revision",0))
    super.restore(candidate)
    if previous_revision<3:
        var existing:=[]
        for zombie in state.zombies: existing.append(zombie.id)
        for spawn in world_definition.enemy_spawns:
            if spawn.id not in existing: state.zombies.append(make_zombie(spawn.id,spawn.position))
    state.world_id = world_definition.id
    if not state.has("exploration"): state.exploration={"discovered":[],"markers":[]}
    # Older snapshots predate observation records and the chosen base.
    if not state.exploration.has("observed"): state.exploration.observed={}
    if not state.exploration.get("base") is String: state.exploration.base="home"

## Records what the player last actually saw in a container. The map only ever
## shows this, so an untouched cupboard keeps its contents secret.
func observe(container_id: String) -> void:
    if not state.has("exploration") or not state.containers.has(container_id):
        return
    if not state.exploration.has("observed"):
        state.exploration.observed={}
    var total:=0
    for item in state.containers[container_id]:
        total+=int(state.containers[container_id][item])
    state.exploration.observed[container_id]={"count":total,"day":state.day,"minutes":state.minutes}

func observed(container_id: String) -> Dictionary:
    if not state.has("exploration"): return {}
    return state.exploration.get("observed",{}).get(container_id,{})

func base_id() -> String:
    if not state.has("exploration"): return "home"
    return str(state.exploration.get("base","home"))

## The authored interiors are claimable on the same terms as the street houses.
## A shelter is the whole volume of the place, so the villa's upper floor counts
## as part of the same base instead of a separate unreachable one.
func zones() -> Array:
    var result: Array = super.zones()
    for zone in world_definition.get("base_zones",[]):
        var r: Array = zone.rect
        result.append({"id":str(zone.id),"name":str(zone.name),
            "rect":Rect2(r[0],r[1],r[2],r[3]),
            "min_y":float(zone.get("min_y",-0.5)),"max_y":float(zone.get("max_y",6.7))})
    return result

func set_base(id: String) -> bool:
    for zone in zones():
        if str(zone.id)==id:
            if not state.has("exploration"): return false
            state.exploration.base=id
            event("base_set","把"+base_name(id)+"设为据点。","希望",{"building":id})
            return true
    return false

func discover(at: Vector3) -> void:
    for region in world_definition.regions:
        var r: Array=region.rect
        if Rect2(r[0],r[1],r[2],r[3]).has_point(Vector2(at.x,at.z)) and region.id not in state.exploration.discovered:
            state.exploration.discovered.append(region.id)
            event("region_discovered","到达"+region.name+"，已记入地图。","希望",{"region":region.id})

func mark(at: Vector3, caption: String) -> bool:
    var b: Dictionary=world_definition.bounds
    if state.exploration.markers.size()>=64 or at.x<b.min_x or at.x>b.max_x or at.z<b.min_z or at.z>b.max_z: return false
    state.exploration.markers.append({"position":[at.x,at.y,at.z],"text":caption.strip_edges().left(80)})
    return true
