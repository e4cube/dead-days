extends RefCounted
const Assets = preload("res://scripts/asset_library.gd")
static func build(game: Node3D) -> Node3D:
    var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop_layout.json"))
    var origin := Vector3.ZERO
    for b in game.model.rules.buildings:
        if b.id=="shop":
            origin.x=b.x
    var details := Assets.attach(game.world,"shop_details",origin)
    for prefix in ["FoodCan","FoodLabel","WaterBody","WaterCap","WaterNeck"]:
        var group: Array = []
        for mesh in details.find_children("*","MeshInstance3D",true,false):
            if str(mesh.name).begins_with("DD_Keep_"+prefix):
                group.append(mesh)
        details.set_meta(prefix,group)
    for obstacle in layout.obstacles:
        var p: Array = obstacle.position
        var s: Array = obstacle.size
        var body: Node3D = game.collision_box(origin+Vector3(p[0],p[1],p[2]),Vector3(s[0],s[1],s[2]))
        body.name="ShopObstacle_"+obstacle.id
    return details
static func stock(details: Node3D, inventory: Dictionary) -> void:
    for prefix in ["FoodCan","FoodLabel","WaterBody","WaterCap","WaterNeck"]:
        var count: int = inventory.get("food" if prefix.begins_with("Food") else "water",0)
        var meshes: Array = details.get_meta(prefix,[])
        for i in meshes.size():
            meshes[i].visible=i<count
