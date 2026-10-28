extends RefCounted
static func build(game: Node3D) -> void:
    var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interior_lights.json"))
    var lights := {}
    var fixtures := {}
    for b in game.model.rules.buildings:
        if not definitions.has(b.id):
            continue
        var d: Dictionary = definitions[b.id]
        var p: Array = d.position
        var light := OmniLight3D.new()
        light.name="InteriorLight_"+b.id
        light.position=Vector3(b.x+p[0],p[1],p[2])
        light.light_color=Color(d.color)
        light.light_energy=d.energy
        light.omni_range=d.range
        light.shadow_enabled=false
        game.world.add_child(light)
        lights[b.id]=light
        var fixture: Node3D = game.box(game.world,light.position,Vector3(.65,.12,.15),Color("c7c9b5"),false)
        fixtures[b.id]=fixture
    game.world.set_meta("interior_lights",lights)
    game.world.set_meta("interior_fixtures",fixtures)
    update(game)
static func update(game: Node3D) -> void:
    for id in game.world.get_meta("house_lamps",{}):
        game.world.get_meta("house_lamps")[id].visible=game.model.light_enabled(id)
    for id in game.world.get_meta("interior_lights",{}):
        game.world.get_meta("interior_lights")[id].visible=game.model.light_enabled(id)
static func cutaway(game: Node3D, view: Vector3) -> void:
    for id in game.world.get_meta("interior_fixtures",{}):
        game.world.get_meta("interior_fixtures")[id].visible=not game.inside(id) or view.z>0
