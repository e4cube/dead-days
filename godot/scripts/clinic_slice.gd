extends RefCounted
const Assets = preload("res://scripts/asset_library.gd")
static func build(game: Node3D) -> Node3D:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/clinic_layout.json"))
    var origin := Vector3.ZERO
    for definition in game.model.rules.buildings:
        if definition.id==layout.building:
            origin.x=definition.x
    var details := Assets.attach(game.world,"clinic_details",origin)
    var boxes: Array = []
    var marks: Array = []
    for mesh in details.find_children("*","MeshInstance3D",true,false):
        if str(mesh.name).begins_with("DD_Keep_MedBox"):
            boxes.append(mesh)
        elif str(mesh.name).begins_with("DD_Keep_MedMark"):
            marks.append(mesh)
    details.set_meta("medicine_boxes",boxes)
    details.set_meta("medicine_marks",marks)
    for obstacle in layout.obstacles:
        var p: Array = obstacle.position
        var s: Array = obstacle.size
        var body: Node3D = game.collision_box(origin+Vector3(p[0],p[1],p[2]),Vector3(s[0],s[1],s[2]))
        body.name="ClinicObstacle_"+obstacle.id
    return details

static func stock(details: Node3D, count: int) -> void:
    for group in ["medicine_boxes","medicine_marks"]:
        var meshes: Array = details.get_meta(group,[])
        for i in meshes.size():
            meshes[i].visible=i<count
