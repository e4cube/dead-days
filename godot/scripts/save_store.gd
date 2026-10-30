extends RefCounted
## Immutable snapshots: exclusive names; no legacy path, no overwriting player saves.
##
## Two file-name predicates on purpose:
##   * `is_snapshot` is deliberately loose (save_*.json) because older builds and
##     hand-made fixtures used other stems, and a legacy save must still load.
##   * `is_timestamped` is strict (save_<digits>_<digits>.json) because rotation
##     deletes files, and it may only ever delete names this store produced.
const Model = preload("res://scripts/survival.gd")
const PREFIX := "save_"
const SUFFIX := ".json"
var directory: String
var keep := 8
var last_error := ""
var last_trimmed := 0

func _init(root: String = "user://saves") -> void:
    directory = root

static func is_snapshot(name: String) -> bool:
    return name.begins_with(PREFIX) and name.ends_with(SUFFIX)

## Zero padded digits make plain string comparison agree with chronological order.
static func is_timestamped(name: String) -> bool:
    if not is_snapshot(name):
        return false
    var stem := name.substr(PREFIX.length(), name.length() - PREFIX.length() - SUFFIX.length())
    var parts := stem.split("_")
    if parts.size() != 2:
        return false
    for part in parts:
        if part.length() == 0:
            return false
        for index in part.length():
            var code := part.unicode_at(index)
            if code < 48 or code > 57:
                return false
    return true

func _list(match_timestamped: bool) -> Array:
    var dir := DirAccess.open(directory)
    if dir == null:
        return []
    var names: Array = []
    for name in dir.get_files():
        var wanted := is_timestamped(name) if match_timestamped else is_snapshot(name)
        if wanted:
            names.append(name)
    names.sort()
    names.reverse()
    return names

## Loadable candidates, newest first: every save_*.json the player may own.
func snapshots() -> Array:
    return _list(false)

## Files this store wrote and may therefore rotate away, newest first.
func timestamped() -> Array:
    return _list(true)

func newest() -> Dictionary:
    var names := timestamped()
    if names.is_empty():
        names = snapshots()
    if names.is_empty():
        return {}
    return {"name": names[0], "path": directory.path_join(names[0])}

func save(model: RefCounted) -> String:
    last_error = ""
    last_trimmed = 0
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
    _trim()
    return path

## Only runs after a snapshot was committed, so a failed save never deletes anything.
func _trim() -> void:
    var names := timestamped()
    if names.size() <= keep:
        return
    for index in range(keep, names.size()):
        if DirAccess.remove_absolute(directory.path_join(names[index])) == OK:
            last_trimmed += 1

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
    var names := snapshots()
    for name in names:
        var parser := JSON.new()
        if parser.parse(FileAccess.get_file_as_string(directory.path_join(name))) != OK:
            continue
        var candidate: Variant = parser.data
        if model.valid(candidate):
            model.restore(candidate)
            return true
    last_error = "没有可用存档" if names.is_empty() else "没有通过校验的存档（原文件未修改）"
    return false
