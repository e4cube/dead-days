extends SceneTree
## Save-slot acceptance: three slots stay isolated, slot 1 keeps the historical
## path so old progress still loads, snapshot rotation only ever deletes its own
## files, and manual backups survive rotation.
const Model = preload("res://scripts/survival.gd")
const Store = preload("res://scripts/save_store.gd")
const Slots = preload("res://scripts/save_slots.gd")
var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func fresh() -> RefCounted:
    var model = Model.new()
    model.start()
    model.state.zombies = []
    return model

func count(dir: String) -> int:
    return Store.new(dir).timestamped().size()

func names(dir: String) -> Array:
    return Store.new(dir).timestamped()

func _initialize() -> void:
    compiles()
    layout()
    isolation()
    rotation()
    rotation_keeps_foreign_files()
    legacy()
    summaries()
    newest()
    backups()
    export_save()
    guards()
    print("SAVE_SLOTS_OK" if failures == 0 else "SAVE_SLOTS_FAILED")
    quit(0 if failures == 0 else 1)

## A script that fails to parse must fail this run, not silently pass it.
func compiles() -> void:
    var slot_probe = Slots.new()
    check(slot_probe != null, "save_slots.gd parses")
    var store_probe = Store.new()
    check(store_probe != null, "save_store.gd parses")

## Slot 1 must stay at the legacy root or every save made before slots existed
## would silently disappear from the menu.
func layout() -> void:
    var slots = Slots.new()
    check(slots.directory(1) == "user://saves", "slot 1 keeps the historical path")
    check(slots.directory(2) == "user://saves/slot_2", "slot 2 lives in a subdirectory")
    check(slots.directory(3) == "user://saves/slot_3", "slot 3 lives in a subdirectory")
    check(slots.directory(0) == "user://saves", "clamping a bad slot keeps the legacy path")
    check(Slots.valid_slot(1) and Slots.valid_slot(3), "slots 1..3 are valid")
    check(not Slots.valid_slot(0) and not Slots.valid_slot(4), "slots outside 1..3 are rejected")
    var custom = Slots.new("user://tests/slot_root")
    check(custom.directory(2) == "user://tests/slot_root/slot_2", "the root is overridable for tests")

func isolation() -> void:
    var root := "user://tests/slots_iso_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    var model = fresh()
    check(not slots.store(2).save(model).is_empty(), "slot 2 accepts a save")
    check(count(slots.directory(2)) == 1, "slot 2 holds exactly one snapshot")
    check(count(slots.directory(1)) == 0, "slot 1 is untouched by a slot 2 save")
    check(not slots.store(3).save(model).is_empty(), "slot 3 accepts a save")
    check(count(slots.directory(2)) == 1, "slot 2 is untouched by a slot 3 save")
    var loaded = Model.new()
    check(slots.store(3).load_latest(loaded), "slot 3 reloads its own snapshot")
    var empty = Model.new()
    var slot_one = slots.store(1)
    check(not slot_one.load_latest(empty), "an empty slot refuses to load")
    check(slot_one.last_error == "没有可用存档", "an empty slot explains itself")
    check(empty.state.is_empty(), "a failed load leaves the model untouched")

## Rotation runs only after a commit and only over real snapshot names.
func rotation() -> void:
    var root := "user://tests/slots_rot_%d" % Time.get_ticks_usec()
    var store = Store.new(root)
    store.keep = 3
    var model = fresh()
    for index in range(6):
        model.state.minutes = float(index)
        check(not store.save(model).is_empty(), "rotation fixture save %d" % index)
    var kept := names(root)
    check(kept.size() == 3, "rotation keeps exactly the configured number, got %d" % kept.size())
    check(store.last_trimmed == 1 or store.last_trimmed == 0, "the last save reports its own trim count")
    var newest: Dictionary = store.newest()
    check(not newest.is_empty() and newest.name == kept[0], "the newest snapshot survives rotation")
    var loaded = Model.new()
    check(store.load_latest(loaded), "a rotated slot still loads")
    check(loaded.state.minutes == 5.0, "the newest state is the one restored")
    check(not FileAccess.file_exists(root.path_join(kept[0]) + ".tmp"), "no temporary file is left behind")

func rotation_keeps_foreign_files() -> void:
    var root := "user://tests/slots_foreign_%d" % Time.get_ticks_usec()
    var store = Store.new(root)
    store.keep = 1
    DirAccess.make_dir_recursive_absolute(root)
    for name in ["notes.txt", "save_bad.json", "save_1_2_3.json", "backup_00000000000000000001_0000000001.json"]:
        var file := FileAccess.open(root.path_join(name), FileAccess.WRITE)
        file.store_string("keep me")
        file.close()
    var model = fresh()
    for index in range(3):
        check(not store.save(model).is_empty(), "foreign fixture save %d" % index)
    check(names(root).size() == 1, "only one timestamped snapshot is kept")
    check(store.is_snapshot("save_bad.json"), "a loose save name is still a load candidate")
    check(not store.is_timestamped("save_bad.json"), "a loose save name is never rotated away")
    check(not store.is_timestamped("save_1_2_3.json"), "extra separators are not ours")
    for name in ["notes.txt", "save_bad.json", "save_1_2_3.json", "backup_00000000000000000001_0000000001.json"]:
        check(FileAccess.file_exists(root.path_join(name)), "rotation must not delete " + name)

## A save written before the timestamp scheme must still load, and its name is
## not something rotation is allowed to delete.
func legacy() -> void:
    var root := "user://tests/slots_legacy_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    var model = fresh()
    model.state.minutes = 555.0
    DirAccess.make_dir_recursive_absolute(slots.directory(1))
    var file := FileAccess.open(slots.directory(1).path_join("save_old.json"), FileAccess.WRITE)
    file.store_string(JSON.stringify(model.state))
    file.close()
    var loaded = Model.new()
    check(slots.store(1).load_latest(loaded), "a legacy save still loads")
    check(loaded.state.minutes == 555.0, "the legacy state is what came back")
    check(slots.summary(1).present, "a legacy save shows up in the slot summary")
    check(slots.store(1).timestamped().is_empty(), "a legacy name is not a rotation candidate")
    var store = slots.store(1)
    store.keep = 2
    for index in range(4):
        check(not store.save(model).is_empty(), "legacy fixture save %d" % index)
    check(FileAccess.file_exists(slots.directory(1).path_join("save_old.json")), "rotation keeps the legacy file")
    check(count(slots.directory(1)) == 2, "rotation still trims timestamped files to keep")

func summaries() -> void:
    var root := "user://tests/slots_sum_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    check(not slots.summary(1).present, "an empty slot reports itself empty")
    check(slots.label(1) == "存档 1 · 空槽", "an empty slot is labelled as such")
    var model = fresh()
    model.state.minutes = float(8 * 60 + 5)
    model.state.stats.health = 88.0
    model.state.inventory = {"water": 2, "food": 1}
    check(not slots.store(2).save(model).is_empty(), "summary fixture save")
    var record := slots.summary(2)
    check(record.present, "a filled slot reports itself present")
    check(record.day == 1, "the summary carries the day")
    check(record.minutes == float(8 * 60 + 5), "the summary carries the clock")
    check(record.health == 88.0, "the summary carries health")
    check(record.items == 3, "the summary counts carried items")
    check(record.count == 1, "the summary counts snapshots")
    check(slots.label(2).contains("第1天 08:05"), "the label renders a readable clock: " + slots.label(2))
    check(slots.label(2).contains("生命88"), "the label renders health: " + slots.label(2))

func newest() -> void:
    var root := "user://tests/slots_new_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    check(slots.newest_slot() == 0, "no slot holds a save yet")
    DirAccess.make_dir_recursive_absolute(slots.directory(3))
    var older := slots.directory(3).path_join("save_00000000000000001000_0000000001.json")
    var newer := slots.directory(1).path_join("save_00000000000000002000_0000000002.json")
    DirAccess.make_dir_recursive_absolute(slots.directory(1))
    var model = fresh()
    for path in [older, newer]:
        var file := FileAccess.open(path, FileAccess.WRITE)
        file.store_string(JSON.stringify(model.state))
        file.close()
    check(slots.newest_slot() == 1, "the newest snapshot wins across slots, got %d" % slots.newest_slot())
    var loaded = Model.new()
    check(slots.store(slots.newest_slot()).load_latest(loaded), "the cross-slot pick really loads")
    check(loaded.valid(loaded.state), "the cross-slot pick validates")

func backups() -> void:
    var root := "user://tests/slots_bak_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    var model = fresh()
    model.state.stats.health = 71.0
    check(not slots.store(2).save(model).is_empty(), "backup fixture save")
    var backup: String = slots.backup(2, model)
    check(not backup.is_empty(), "a backup is written")
    check(FileAccess.file_exists(backup), "the backup file exists")
    check(slots.backups(2).size() == 1, "the backup is listed")
    check(count(slots.directory(2)) == 1, "a backup does not count as a snapshot")
    check(slots.summary(2).backups == 1, "the summary counts backups")
    model.state.stats.health = 10.0
    check(slots.restore_backup(2, model, slots.backups(2)[0]), "the backup restores")
    check(model.state.stats.health == 71.0, "the backup restores the backed-up health")
    check(not slots.restore_backup(2, model, "save_00000000000000000000_0000000000.json"), "snapshots are not backups")
    check(not slots.restore_backup(2, model, "backup_missing.json"), "a missing backup is rejected")

func export_save() -> void:
    var root := "user://tests/slots_exp_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    # The real export folder is the player's; a test must never write into it.
    slots.export_root = root.path_join("exports")
    var model = fresh()
    var result: String = slots.export_save(1, model)
    check(not result.is_empty(), "a desktop export reports a path")
    if not OS.has_feature("web"):
        check(FileAccess.file_exists(result), "the exported file exists: " + result)
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(result))
        var reloaded = Model.new()
        check(reloaded.valid(parsed), "the exported JSON is a valid save")
        check(int(parsed.get("day", 0)) == int(model.state.day), "the export carries the run")
        var again: String = slots.export_save(1, model)
        check(again != result, "a second export in the same second does not overwrite the first")
        check(FileAccess.file_exists(result) and FileAccess.file_exists(again), "both exports survive")
        var dir := DirAccess.open(slots.export_root)
        check(dir != null and dir.get_files().size() == 2, "exports all land in the configured folder")
    var broken = Model.new()
    broken.state.minutes = -1.0
    check(slots.export_save(1, broken) == "", "an invalid state is not exported")
    check(slots.backup(1, broken) == "", "an invalid state is not backed up")

## A slot whose directory was never created must not throw, and an invalid model
## must not produce a snapshot even when the directory exists.
func guards() -> void:
    var root := "user://tests/slots_guard_%d" % Time.get_ticks_usec()
    var slots = Slots.new(root)
    check(slots.backups(3).is_empty(), "listing backups of a missing slot returns nothing")
    check(slots.summary(3).backups == 0, "summarising a missing slot is safe")
    var broken = Model.new()
    broken.state.minutes = -5.0
    var slot_one = slots.store(1)
    check(slot_one.save(broken) == "", "an invalid state is not saved")
    check(slot_one.last_error == "状态未通过校验", "the refusal is explained")
    check(count(slots.directory(1)) == 0, "a refused save leaves no snapshot behind")
