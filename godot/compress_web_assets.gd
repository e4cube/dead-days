extends SceneTree
func _initialize():
    var directory=DirAccess.open("res://.godot/imported")
    var before:=0
    var after:=0
    for name in directory.get_files():
        if not name.ends_with(".scn"):continue
        var path="res://.godot/imported/"+name
        before+=FileAccess.get_file_as_bytes(path).size()
        var resource=ResourceLoader.load(path)
        if resource==null or ResourceSaver.save(resource,path,ResourceSaver.FLAG_COMPRESS)!=OK:
            push_error("Compression failed: "+name)
            quit(1)
            return
        after+=FileAccess.get_file_as_bytes(path).size()
    print("WEB_SCENE_COMPRESSION_OK ",before," -> ",after)
    quit()
