extends RefCounted
## Immutable snapshots: exclusive names; no legacy path, no overwriting player saves.
const Model = preload("res://scripts/survival.gd")
var directory: String
var last_error := ""

func _init(root: String = "user://saves") -> void:
    directory = root

func save(model: RefCounted) -> String:
    last_error = ""
    if not model.valid(model.state):
        last_error = "状态未通过校验"
        return ""
    if DirAccess.make_dir_recursive_absolute(directory) != OK:
        last_error = "无法创建存档目录"
        return ""
    var path := directory.path_join("save_%020d_%010d.json" % [int(Time.get_unix_time_from_system() * 1000000), Time.get_ticks_usec()])
    if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".tmp"):
        last_error = "存档文件名冲突"
        return ""
    var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
    if file == null:
        last_error = "无法写入存档"
        return ""
    file.store_string(JSON.stringify(model.state))
    file.flush()
    var result := file.get_error()
    file.close()
    if result != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
        last_error = "存档提交失败，旧快照保留"
        return ""
    if OS.has_feature("web"):
        var key := "deaddays:snapshot:" + directory
        JavaScriptBridge.eval("localStorage.setItem(%s,%s)" % [JSON.stringify(key), JSON.stringify(JSON.stringify(model.state))])
    return path

func load_latest(model: RefCounted) -> bool:
    last_error = ""
    if OS.has_feature("web"):
        var key := "deaddays:snapshot:" + directory
        var raw = JavaScriptBridge.eval("localStorage.getItem(%s)" % JSON.stringify(key))
        if raw is String:
            var candidate = JSON.parse_string(raw)
            if model.valid(candidate):
                model.restore(candidate)
                return true
    var dir := DirAccess.open(directory)
    if dir == null:
        last_error = "没有可用存档"
        return false
    var names := dir.get_files()
    names.sort()
    names.reverse()
    for name in names:
        if not name.begins_with("save_") or not name.ends_with(".json"):
            continue
        var parser := JSON.new()
        if parser.parse(FileAccess.get_file_as_string(directory.path_join(name))) != OK:
            continue
        var candidate: Variant = parser.data
        if model.valid(candidate):
            model.restore(candidate)
            return true
    last_error = "没有通过校验的存档（原文件未修改）"
    return false
