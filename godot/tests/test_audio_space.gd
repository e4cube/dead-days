extends SceneTree
## Distance, storeys and the one-way rule between sound and perception.
##
## This test exists because the previous audio work could only prove "a clip was
## scheduled", never "a sound three rooms away is quieter than one at your feet".
## Everything about volume here is a pure function, so the number can be checked
## without an audio device and without trusting a pair of ears.
const Audio = preload("res://scripts/game_audio.gd")
const AudioSpace = preload("res://scripts/audio_space.gd")
const World = preload("res://scripts/connected_model.gd")

var failures := 0

func check(value: bool, message: String) -> void:
    if not value:
        failures += 1
        printerr("FAIL: ", message)

func config() -> Dictionary:
    return AudioSpace.settings({
        "reference_distance": 3.0, "max_distance": 42.0, "rolloff_db": 7.0,
        "floor_db": -34.0, "floor_gap": 1.5, "floor_penalty_db": -12.0,
    })

func _initialize() -> void:
    # --- 距离曲线 ---
    var space := config()
    check(is_equal_approx(AudioSpace.level_db(0.0, 0, 0, space), 0.0), "at the ear is full volume")
    check(is_equal_approx(AudioSpace.level_db(3.0, 0, 0, space), 0.0), "the reference edge is still full")
    check(is_equal_approx(AudioSpace.level_db(6.0, 0, 0, space), -7.0), "one doubling costs the rolloff")
    check(is_equal_approx(AudioSpace.level_db(12.0, 0, 0, space), -14.0), "the curve keeps doubling")
    check(is_equal_approx(AudioSpace.level_db(24.0, 0, 0, space), -21.0), "three doublings, three steps")
    var previous := 0.0
    for step in range(1, 40):
        var current := AudioSpace.level_db(float(step), 0, 0, space)
        check(current <= previous + 0.0001, "loudness never rises with distance at %d m" % step)
        previous = current
    check(AudioSpace.level_db(41.0, 0, 0, space) >= -34.0, "the floor keeps the farthest audible cue audible")

    # --- 楼层 ---
    check(is_equal_approx(AudioSpace.level_db(2.0, 3.56, 0.0, space), -12.0),
        "a floor slab costs the storey penalty")
    check(is_equal_approx(AudioSpace.level_db(2.0, 0.0, 0.4, space), 0.0),
        "one stair step is not a storey")
    check(AudioSpace.level_db(2.0, 3.56, 0.0, space) < AudioSpace.level_db(2.0, 0.0, 0.0, space),
        "someone upstairs reads as farther than someone beside you")

    # --- 静音边界 ---
    check(AudioSpace.audible(41.9, space), "just inside the radius is audible")
    check(not AudioSpace.audible(42.0, space), "the radius itself is silent")
    check(not AudioSpace.audible(-1.0, space), "a negative distance is refused")
    check(not AudioSpace.audible(INF, space), "infinity is refused")
    check(not AudioSpace.audible(NAN, space), "NaN is refused")
    check(not is_finite(AudioSpace.level_db(60.0, 0, 0, space)), "past the radius there is no level at all")

    # --- 脏配置不炸 ---
    var broken := AudioSpace.settings({"reference_distance": -5, "max_distance": "loud",
        "rolloff_db": 999, "floor_gap": -1, "floor_penalty_db": 50})
    check(float(broken.reference_distance) >= 0.5, "a negative reference falls back to a usable one")
    check(float(broken.max_distance) > float(broken.reference_distance), "the radius stays outside the reference")
    check(float(broken.rolloff_db) <= 48.0, "the rolloff is clamped")
    check(float(broken.floor_penalty_db) <= 0.0, "the storey penalty can only make things quieter")
    check(float(broken.floor_gap) >= 0.0, "a negative gap is clamped")
    check(AudioSpace.settings(null) == AudioSpace.settings({}), "a missing config falls back cleanly")

    # --- 真实音频节点 ---
    var audio = Audio.new()
    root.add_child(audio)
    await process_frame
    check(audio.voices.size() == int(audio.config.voices), "the pool matches the configured size")
    check(audio.clips.size() == audio.config.effects.size(), "every configured effect has a clip")
    for id in ["growl", "snarl", "death", "glass"]:
        check(audio.clips.has(id), "the new cue exists: " + id)
        var clip: AudioStreamWAV = audio.clips[id]
        var peak := 0
        for i in clip.data.size() / 2:
            peak = maxi(peak, absi(clip.data.decode_s16(i * 2)))
        check(peak > 100 and peak < 26215, "bounded, non-silent signal for " + id)
    check(audio.clips.growl.data != audio.clips.step.data, "a growl is not a footstep")
    check(audio.clips.snarl.data != audio.clips.growl.data, "a snarl is not a growl")

    audio.set_listener(Vector3.ZERO)
    check(audio.play_at("growl", Vector3(2.0, 0.0, 0.0)), "a near sound is scheduled")
    check(audio.played.get("growl", 0) == 1, "the near sound is counted once")
    check(is_equal_approx(float(audio.last.back().distance), 2.0), "the recorded distance is the planar one")
    check(is_equal_approx(float(audio.last.back().db), 0.0), "a near sound plays at full level")

    check(not audio.play_at("growl", Vector3(100.0, 0.0, 0.0)), "a sound across the map is never scheduled")
    check(audio.played.get("growl", 0) == 1, "the silent one is not counted")

    check(audio.play_at("growl", Vector3(8.0, 0.0, 0.0)), "eight metres is still audible")
    # 8 m from a 3 m reference is 2.67x, i.e. 1.42 doublings, i.e. -9.9 dB.
    check(float(audio.last.back().db) < -9.0 and float(audio.last.back().db) > -11.0,
        "eight metres costs about 1.4 doublings")

    audio.play_at("snarl", Vector3(1.0, 3.56, 0.0))
    check(is_equal_approx(float(audio.last.back().db), -12.0), "the storey penalty reaches the mixer")

    # --- 同一声源节流 ---
    audio.reset([])
    check(audio.zombie_voice("growl", Vector3(1.0, 0.0, 0.0), "z1"), "a body speaks once")
    check(not audio.zombie_voice("growl", Vector3(1.0, 0.0, 0.0), "z1"), "the same body is throttled")
    check(audio.zombie_voice("growl", Vector3(1.0, 0.0, 0.0), "z2"), "another body is separate")
    check(not audio.zombie_voice("growl", Vector3(90.0, 0.0, 0.0), "z3"), "an inaudible growl is refused")
    check(not audio.voice_clock.has("z3:growl"), "a refused growl does not spend the cooldown")
    audio.reset([])
    check(audio.zombie_voice("growl", Vector3(1.0, 0.0, 0.0), "z1"), "loading a save re-arms the voices")

    # --- 静音 ---
    audio.toggle_mute()
    var muted_before: int = audio.played.get("growl", 0)
    check(not audio.play_at("growl", Vector3(1.0, 0.0, 0.0)), "muting schedules nothing")
    check(audio.played.get("growl", 0) == muted_before, "a muted sound is not counted")
    audio.toggle_mute()
    check(audio.play_at("growl", Vector3(1.0, 0.0, 0.0)), "unmuting restores playback")

    # --- 池子不越界 ---
    var pool: int = audio.voices.size()
    for i in 60:
        audio.play_at("step", Vector3(1.0, 0.0, 0.0))
    check(audio.voices.size() == pool, "the voice pool never grows")
    check(audio.voice_index >= 0 and audio.voice_index < pool, "the pool cursor stays inside the pool")

    # --- 声音永远不写感知状态 ---
    var model = World.new()
    model.start()
    model.state.zombies = []
    var noises: int = model.state.noises.size()
    audio.set_listener(Vector3.ZERO)
    audio.play_at("gunshot", Vector3(0.5, 0.0, 0.0))
    audio.zombie_voice("growl", Vector3(1.0, 0.0, 0.0), "z9")
    audio.zombie_voice("death", Vector3(1.0, 0.0, 0.0), "z9")
    check(model.state.noises.size() == noises, "playback appends no AI noise")
    check(model.state.zombies.is_empty(), "playback summons no zombie")

    audio.reset(model.state.events)
    var before: Dictionary = audio.played.duplicate(true)
    audio.sync(model.state.events)
    check(audio.played == before, "loading a save does not replay its history")

    # --- 事件映射仍然有效 ---
    model.event("fired", "测试枪声。")
    model.event("door", "测试开门。")
    audio.sync(model.state.events)
    check(audio.played.get("gunshot", 0) >= 2, "a shot event still reaches the mixer")
    check(audio.played.get("door", 0) >= 1, "a door event still reaches the mixer")

    print("AUDIO_SPACE_OK" if failures == 0 else "AUDIO_SPACE_FAILED")
    quit(0 if failures == 0 else 1)
