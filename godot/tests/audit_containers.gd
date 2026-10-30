extends SceneTree
## Dump every container with its contents so a survival route can be authored
## against real ids instead of guesses.
const World = preload("res://scripts/connected_model.gd")

func _initialize() -> void:
    var model = World.new()
    model.start()
    model.state.zombies = []
    var ids: Array = model.state.containers.keys()
    ids.sort()
    for id in ids:
        var items: Dictionary = model.state.containers[id]
        var text := ""
        for item in items:
            text += "%s=%d " % [item, int(items[item])]
        print("%s | %s | %s" % [id, model.container_name(id), text.strip_edges()])
    print("zombies %d" % model.state.zombies.size())
    print("DONE")
    quit(0)
