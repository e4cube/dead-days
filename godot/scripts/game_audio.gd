extends Node
## Original deterministic synthesis, now placed in the world instead of the mix.
##
## Two rules this file keeps, because they are what make sound trustworthy:
## 1. Playback never writes into the model. AI noise is produced by the model's
##    own `noise()` call, never by a speaker, so a growl can never wake a horde
##    and a horde can never growl itself awake.
## 2. Distance and storeys decide whether a sound exists at all. Past
##    `max_distance` nothing is scheduled, so a fight across the map costs no
##    voices and stays silent, the way it should.
const AudioSpace = preload("res://scripts/audio_space.gd")
const POOL := 16
const GROWL_COOLDOWN := 2.6

var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
var clips: Dictionary = {}
var voices: Array[AudioStreamPlayer3D] = []
var played: Dictionary = {}
var last: Array = []
var voice_clock: Dictionary = {}
var muted := false
var cursor := 0
var stride := 0.0
var voice_index := 0
var listener := Vector3.ZERO
var space: Dictionary = {}

func _ready():
    space = AudioSpace.settings(config.get("space"))
    for id in config.effects:
        clips[id] = synthesize(config.effects[id], int(config.sample_rate))
    for i in maxi(4, int(config.get("voices", POOL))):
        var voice := AudioStreamPlayer3D.new()
        voice.volume_db = float(config.volume_db)
        # Attenuation is computed here from planar distance plus storey gap;
        # letting the engine attenuate from a top-down camera would just measure
        # the camera height instead of the actual distance on the ground.
        voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
        voice.panning_strength = float(space.get("pan_strength", 1.0))
        voice.unit_size = 1.0
        voice.max_distance = float(space.max_distance) * 4.0
        add_child(voice)
        voices.append(voice)

static func synthesize(recipe: Dictionary, rate: int) -> AudioStreamWAV:
    var rng := RandomNumberGenerator.new()
    rng.seed = 74123
    var data := PackedByteArray()
    var frames := int(float(recipe.duration) * rate)
    data.resize(frames * 2)
    var filtered := 0.0
    for i in frames:
        var t := float(i) / rate
        filtered = lerpf(filtered, rng.randf_range(-1, 1), .55)
        var tone := sin(TAU * float(recipe.frequency) * t * (1.0 - .25 * t))
        var envelope := minf(t * 1500.0, 1.0) * exp(-float(recipe.decay) * t) * (1.0 - float(i) / frames)
        var value := clampf(lerpf(tone, filtered, float(recipe.noise)) * float(recipe.gain) * envelope, -.8, .8)
        match str(recipe.get("shape", "legacy")):
            "foot":
                value = (sin(TAU * float(recipe.frequency) * t) * exp(-45 * t) * .7 + filtered * exp(-70 * t) * .3) * float(recipe.gain)
            "swing":
                value = filtered * pow(sin(PI * float(i) / frames), 2) * float(recipe.gain)
            "impact":
                value = (sin(TAU * 95 * t) * exp(-26 * t) * .7 + filtered * exp(-90 * t) * .6) * float(recipe.gain)
            "shot":
                value = (rng.randf_range(-1, 1) * exp(-100 * t) + filtered * exp(-12 * t) * .24 + sin(TAU * 60 * t) * exp(-23 * t) * .35) * float(recipe.gain)
            "growl":
                # A slow wobble on the fundamental: the same throat would otherwise
                # read as an engine idling.
                var wobble := sin(TAU * 3.4 * t)
                var throat := sin(TAU * (float(recipe.frequency) + wobble * 5.0) * t)
                value = (throat * .62 + filtered * .55 + sin(TAU * float(recipe.frequency) * 2.0 * t) * .18) * float(recipe.gain) * envelope
            "snarl":
                value = (filtered * .85 + sin(TAU * float(recipe.frequency) * t * (1.0 + .5 * sin(TAU * 9.0 * t))) * .35) * float(recipe.gain) * envelope
            "death":
                var sinking := float(recipe.frequency) * (1.0 - .4 * minf(1.0, t / maxf(0.05, float(recipe.duration))))
                value = (sin(TAU * sinking * t) * .7 + filtered * .5) * float(recipe.gain) * envelope
            "glass":
                # High, sharp, and gone: shatter with no tail to muddle the next cue.
                value = (rng.randf_range(-1, 1) * exp(-14 * t) * .8 + sin(TAU * float(recipe.frequency) * t) * exp(-38 * t) * .3) * float(recipe.gain)
        value = clampf(value, -.79, .79)
        data.encode_s16(i * 2, int(value * 32767))
    var clip := AudioStreamWAV.new()
    clip.format = AudioStreamWAV.FORMAT_16_BITS
    clip.mix_rate = rate
    clip.stereo = false
    clip.data = data
    return clip

## Where the ears are. A top-down game has one listener and it is the player.
func set_listener(at: Vector3) -> void:
    listener = at

## Returns true only when a sound was actually scheduled. Everything past
## `max_distance`, muted, or missing from the bank returns false, which keeps the
## call site honest and keeps `played` a count of audible events.
func play_at(id: String, at: Vector3, force: bool = false) -> bool:
    if muted or not clips.has(id) or voices.is_empty():
        return false
    var distance := AudioSpace.planar_distance(listener, at)
    if not force and not AudioSpace.audible(distance, space):
        return false
    var gain := AudioSpace.level_db(distance, at.y, listener.y, space)
    if not is_finite(gain):
        return false
    var voice: AudioStreamPlayer3D = voices[voice_index]
    voice_index = (voice_index + 1) % voices.size()
    voice.stream = clips[id]
    voice.position = Vector3(at.x, at.y, at.z)
    voice.volume_db = float(config.volume_db) + gain
    voice.play()
    played[id] = played.get(id, 0) + 1
    last.append({"id": id, "distance": distance, "db": gain})
    if last.size() > 16:
        last.pop_front()
    return true

## The player's own sounds sit on the listener, so they are always full volume.
func play_effect(id: String):
    play_at(id, listener)

## A zombie's voice is throttled per body so a crowd does not turn into a chorus.
## The cooldown is only recorded once a sound was actually scheduled, so a growl
## that was too far away to hear never eats the next one.
func zombie_voice(kind: String, at: Vector3, source_id: String = "") -> bool:
    var key := str(source_id) + ":" + kind
    var now := float(Time.get_ticks_msec()) / 1000.0
    if float(voice_clock.get(key, -999.0)) + GROWL_COOLDOWN > now:
        return false
    if not play_at(kind, at):
        return false
    voice_clock[key] = now
    return true

func reset(events: Array):
    cursor = events.size() # Restoring snapshots must never replay historical sounds.
    stride = 0
    last.clear()
    voice_clock.clear()
    for voice in voices:
        voice.stop()

func movement(distance: float, running: bool):
    stride += clampf(distance, 0, 2)
    if stride >= float(config.step_distance):
        stride = fmod(stride, float(config.step_distance))
        play_effect("run" if running else "step")

func sync(events: Array):
    if cursor > events.size(): cursor = events.size()
    for i in range(cursor, events.size()):
        match events[i].kind:
            "door": play_effect("door")
            "door_hit", "door_broken": play_effect("door")
            "fired": play_effect("gunshot")
            "injured": play_effect("hurt")
            "looted", "recovered", "stored", "retrieved", "dropped": play_effect("loot")
            "reloaded", "unloaded": play_effect("reload")
    cursor = events.size()

func toggle_mute():
    muted = not muted
    if muted:
        for voice in voices:
            voice.stop()

func _exit_tree():
    for voice in voices:
        voice.stop()
        voice.stream = null
    voices.clear()
    clips.clear()
