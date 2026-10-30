extends RefCounted
## Three save slots on top of the immutable-snapshot store.
##
## Slot 1 keeps the historical `user://saves` path so progress made before slots
## existed still loads; slots 2 and 3 live in subdirectories. Backups go into a
## `backups/` subdirectory of each slot, outside snapshot rotation, so a manual
## backup survives even after the snapshots around it are trimmed away.
const Store = preload("res://scripts/save_store.gd")
const COUNT := 3
const ROOT := "user://saves"
const BACKUP_PREFIX := "backup_"
const EXPORT_ROOT := "user://exports"
var root: String
## Overridable so tests never write into the player's real export folder.
var export_root := EXPORT_ROOT

func _init(base: String = ROOT) -> void:
    root = base

static func valid_slot(slot: int) -> bool:
    return slot >= 1 and slot <= COUNT

func directory(slot: int) -> String:
    if slot <= 1:
        return root
    return root.path_join("slot_%d" % slot)

func store(slot: int) -> RefCounted:
    return Store.new(directory(slot))

func backup_directory(slot: int) -> String:
    return directory(slot).path_join("backups")

## Reads the newest snapshot of one slot without touching a live model, so the
## menu can describe every slot before the run that owns it is loaded.
func summary(slot: int) -> Dictionary:
    var snapshots := store(slot)
    var stamps: Array = snapshots.timestamped()
    var newest: Dictionary = snapshots.newest()
    var record := {
        "slot": slot,
        "present": not newest.is_empty(),
        "name": newest.get("name", ""),
        "path": newest.get("path", ""),
        "count": snapshots.snapshots().size(),
        "stamp": "" if stamps.is_empty() else stamps[0],
        "day": 0,
        "minutes": 0.0,
        "health": 0.0,
        "items": 0,
        "backups": backups(slot).size(),
    }
    # A legacy `save_*.json` name carries no timestamp; sort it below every real
    # snapshot instead of letting its letters win the "newest" comparison.
    record.key = record.stamp if not record.stamp.is_empty() else "0" + String(record.name)
    if newest.is_empty():
        return record
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(newest.path))
    if not (parsed is Dictionary):
        return record
    var state: Dictionary = parsed
    var stats: Dictionary = state.get("stats", {})
    var inventory: Dictionary = state.get("inventory", {})
    record.day = int(state.get("day", 0))
    record.minutes = float(state.get("minutes", 0.0))
    record.health = float(stats.get("health", 0.0))
    for id in inventory:
        record.items += int(inventory[id])
    return record

func label(slot: int) -> String:
    var record := summary(slot)
    if not record.present:
        return "存档 %d · 空槽" % slot
    var hour := int(record.minutes) / 60
    var minute := int(record.minutes) % 60
    return "存档 %d · 第%d天 %02d:%02d · 生命%d · %d件" % [slot, record.day, hour, minute, int(record.health), record.items]

## Snapshot names are zero padded, so the newest name is also the newest save,
## whichever slot it came from.
func newest_slot() -> int:
    var best := 0
    var best_key := ""
    for slot in range(1, COUNT + 1):
        var record := summary(slot)
        if not record.present:
            continue
        var key: String = record.key
        if key > best_key:
            best_key = key
            best = slot
    return best

func backup(slot: int, model: RefCounted) -> String:
    if not model.valid(model.state):
        return ""
    var folder := backup_directory(slot)
    if DirAccess.make_dir_recursive_absolute(folder) != OK:
        return ""
    var path := folder.path_join("%s%020d_%010d.json" % [BACKUP_PREFIX, int(Time.get_unix_time_from_system() * 1000000), Time.get_ticks_usec()])
    var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
    if file == null:
        return ""
    file.store_string(JSON.stringify(model.state))
    file.flush()
    var result := file.get_error()
    file.close()
    if result != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
        return ""
    return path

func backups(slot: int) -> Array:
    var dir := DirAccess.open(backup_directory(slot))
    if dir == null:
        return []
    var names: Array = []
    for name in dir.get_files():
        if name.begins_with(BACKUP_PREFIX) and name.ends_with(Store.SUFFIX):
            names.append(name)
    names.sort()
    names.reverse()
    return names

func restore_backup(slot: int, model: RefCounted, name: String) -> bool:
    if not (name.begins_with(BACKUP_PREFIX) and name.ends_with(Store.SUFFIX)):
        return false
    var path := backup_directory(slot).path_join(name)
    if not FileAccess.file_exists(path):
        return false
    var candidate = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not model.valid(candidate):
        return false
    model.restore(candidate)
    return true

## Manual export of the live state. Desktop writes a real file and reports the
## path; the browser hands the same JSON to the download shelf.
func export_save(slot: int, model: RefCounted) -> String:
    if not model.valid(model.state):
        return ""
    var text := JSON.stringify(model.state)
    if OS.has_feature("web"):
        JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "dead-days-slot%d.json" % slot, "application/json")
        return "存档副本已下载"
    if DirAccess.make_dir_recursive_absolute(export_root) != OK:
        return ""
    var stem := "dead-days-slot%d_%d" % [slot, int(Time.get_unix_time_from_system())]
    var path := export_root.path_join(stem + ".json")
    # Two exports inside the same second must not overwrite each other.
    var index := 1
    while FileAccess.file_exists(path):
        path = export_root.path_join("%s-%d.json" % [stem, index])
        index += 1
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return ""
    file.store_string(text)
    file.close()
    return ProjectSettings.globalize_path(path)
