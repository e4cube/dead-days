extends SceneTree
## Compress imported .scn files in place so the web pck stays small.
##
## Re-saving a .scn that holds PortableCompressedTexture2D with FLAG_COMPRESS
## drops the portable texture payload, but leaves the sibling .md5 stamp
## untouched — so the importer thinks the cache is fresh and never rebuilds it.
## The desktop build then renders those surfaces as the magenta checkerboard.
##
## Deleting the stamp forces the next `--import` to regenerate the scene from
## the .glb. Do that before running the desktop build again; play.bat does it
## automatically. tests/probe_materials.gd guards the result.
func _initialize():
    var directory=DirAccess.open("res://.godot/imported")
    if directory==null:
        push_error("Cannot open res://.godot/imported")
        quit(1)
        return
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
    print("注意：压缩会丢掉内嵌的 PortableCompressedTexture2D 像素，桌面版会变洋红。")
    print("tools/build_web_fixed.py 会在导出后自动重建导入缓存，单独跑本脚本请自己补一次 --import。")
    quit()
