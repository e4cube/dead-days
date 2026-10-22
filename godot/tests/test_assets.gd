extends SceneTree
const Visual = preload("res://scripts/character_visual.gd")
const Assets = preload("res://scripts/asset_library.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        printerr("FAIL: ", message)

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
    check(manifest.assets.size() == 10, "ten reusable source assets")
    for id in manifest.assets:
        var entry: Dictionary = manifest.assets[id]
        var packed: PackedScene = load("res://assets/" + entry.file)
        check(packed != null, "imports " + id)
        if packed == null:
            continue
        var asset := packed.instantiate()
        root.add_child(asset)
        check(asset.find_children("*", "CollisionObject3D", true, false).is_empty(), "GLB has no duplicate gameplay collision " + id)
        var meshes := asset.find_children("*", "MeshInstance3D", true, false)
        check(meshes.size() == entry.meshes, "mesh budget " + id)
        check(entry.triangles <= 2000, "low-poly triangle budget " + id)
        if id == "loot_crate":
            check(meshes.size() == 1 and meshes[0].get_aabb().size.is_equal_approx(Vector3(1.2, 1.0, 0.7)), "crate meter dimensions retained")
        if id in ["player", "zombie"]:
            var skeletons := asset.find_children("*", "Skeleton3D", true, false)
            var players := asset.find_children("*", "AnimationPlayer", true, false)
            check(skeletons.size() == 1 and skeletons[0].get_bone_count() == 16, "16-bone skeleton " + id)
            check(players.size() == 1, "animation library " + id)
            if id == "player":
                check(players[0].has_animation("run") and "run" in entry.clips, "run survives GLB export and manifest")
            for name in ["stand", "move", "attack", "hurt", "death"]:
                check(players[0].has_animation(name), "exported clip " + id + "/" + name)
                if players[0].has_animation(name):
                    var animation: Animation = players[0].get_animation(name)
                    check(animation.length >= 0.19 and animation.get_track_count() > 0, "nonempty bone tracks " + name)
            var weighted := 0
            for mesh in meshes:
                if mesh.skin != null and mesh.skin.get_bind_count() >= 16:
                    var arrays: Array = mesh.mesh.surface_get_arrays(0)
                    if arrays[Mesh.ARRAY_WEIGHTS] != null and arrays[Mesh.ARRAY_WEIGHTS].size() > 0:
                        weighted += 1
            check(weighted == meshes.size(), "real skinned vertex weights " + id)
        if id.begins_with("building_"):
            Assets.cutaway(asset, false)
            var hidden := 0
            var cuts := 0
            for mesh in meshes:
                if str(mesh.name).begins_with("DD_Hide_"):
                    hidden += 1
                    check(mesh.visible, "exterior roof/wall visible")
                if str(mesh.name).begins_with("DD_Cut_"):
                    cuts += 1
                    check(not mesh.visible, "no duplicate exterior cut wall")
            check(hidden > 4 and cuts == 3, "building cutaway contract " + id)
            Assets.cutaway(asset, true)
            for mesh in meshes:
                if str(mesh.name).begins_with("DD_Hide_"):
                    check(mesh.visible == ("_Back" in str(mesh.name) or "_West" in str(mesh.name)), "interior removes foreground occlusion and retains background trims")
                if str(mesh.name).begins_with("DD_Cut_"):
                    check(mesh.visible, "interior low wall retained")
        asset.queue_free()
        await process_frame
    for kind in ["player", "zombie"]:
        var visual := Visual.new()
        root.add_child(visual)
        visual.setup(kind)
        check(visual.animator.get_animation("move").loop_mode == Animation.LOOP_LINEAR, "runtime loop policy " + kind)
        var index: int = visual.skeleton.find_bone("thigh_L")
        var standing: Quaternion = visual.skeleton.get_bone_pose_rotation(index)
        visual.sample("move", 0.2)
        var before: Quaternion = visual.skeleton.get_bone_pose_rotation(index)
        visual.sample("move", 0.5)
        var after: Quaternion = visual.skeleton.get_bone_pose_rotation(index)
        check(absf(before.dot(after)) < 0.9999, "sampling moves an actual bone " + kind)
        visual.sample("stand", 0)
        check(absf(standing.dot(visual.skeleton.get_bone_pose_rotation(index))) > 0.99999, "moving legs return to standing pose " + kind)
        visual.trigger("attack")
        visual.sample("attack", 0.15)
        check(visual.current_action == "attack", "attack animation selectable")
        visual.sample("hurt", 0.1)
        index = visual.skeleton.find_bone("spine")
        check(visual.skeleton.get_bone_pose_rotation(index).angle_to(Quaternion.IDENTITY) > 0.1, "hurt pose changes skeleton")
        visual.sample("death", 0)
        index = visual.skeleton.find_bone("root")
        check(visual.skeleton.get_bone_pose_rotation(index).angle_to(Quaternion.IDENTITY) > 1.5, "death reconstructs terminal corpse pose")
        if kind == "player":
            check(visual.animator.get_animation("run").loop_mode == Animation.LOOP_LINEAR, "run loops")
            visual.set_weapon(true)
            check(visual.weapon != null and visual.weapon.visible, "weapon is skinned to hand")
            visual.set_weapon(false)
            check(not visual.weapon.visible, "no equipped-weapon phantom")
        visual.queue_free()
        await process_frame
    print("ASSET_IMPORT_OK" if failures == 0 else "ASSET_IMPORT_FAILED")
    quit(0 if failures == 0 else 1)
