extends Node
## Original deterministic synthesis. Playback never creates AI perception events.
var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/audio.json"))
var clips: Dictionary={}
var voices: Array[AudioStreamPlayer]=[]
var played: Dictionary={}
var muted:=false
var cursor:=0
var stride:=0.0
var voice_index:=0
func _ready():
    for id in config.effects: clips[id]=synthesize(config.effects[id],int(config.sample_rate))
    for i in int(config.voices):
        var voice:=AudioStreamPlayer.new()
        voice.volume_db=float(config.volume_db)
        add_child(voice)
        voices.append(voice)
static func synthesize(recipe: Dictionary, rate: int) -> AudioStreamWAV:
    var rng:=RandomNumberGenerator.new()
    rng.seed=74123
    var data:=PackedByteArray()
    var frames:=int(float(recipe.duration)*rate)
    data.resize(frames*2)
    var filtered:=0.0
    for i in frames:
        var t:=float(i)/rate
        filtered=lerpf(filtered,rng.randf_range(-1,1),.55)
        var tone:=sin(TAU*float(recipe.frequency)*t*(1.0-.25*t))
        var envelope:=minf(t*1500.0,1.0)*exp(-float(recipe.decay)*t)*(1.0-float(i)/frames)
        var value:=clampf(lerpf(tone,filtered,float(recipe.noise))*float(recipe.gain)*envelope,-.8,.8)
        match str(recipe.get("shape","legacy")):
            "foot":
                value=(sin(TAU*float(recipe.frequency)*t)*exp(-45*t)*.7+filtered*exp(-70*t)*.3)*float(recipe.gain)
            "swing":
                value=filtered*pow(sin(PI*float(i)/frames),2)*float(recipe.gain)
            "impact":
                value=(sin(TAU*95*t)*exp(-26*t)*.7+filtered*exp(-90*t)*.6)*float(recipe.gain)
            "shot":
                value=(rng.randf_range(-1,1)*exp(-100*t)+filtered*exp(-12*t)*.24+sin(TAU*60*t)*exp(-23*t)*.35)*float(recipe.gain)
        value=clampf(value,-.79,.79)
        data.encode_s16(i*2,int(value*32767))
    var clip:=AudioStreamWAV.new()
    clip.format=AudioStreamWAV.FORMAT_16_BITS
    clip.mix_rate=rate
    clip.stereo=false
    clip.data=data
    return clip
func reset(events: Array):
    cursor=events.size() # Restoring snapshots must never replay historical sounds.
    stride=0
    for voice in voices: voice.stop()
func play_effect(id: String):
    if muted or not clips.has(id) or voices.is_empty(): return
    var voice:=voices[voice_index]
    voice_index=(voice_index+1)%voices.size()
    voice.stream=clips[id]
    voice.play()
    played[id]=played.get(id,0)+1
func movement(distance: float,running: bool):
    stride+=clampf(distance,0,2)
    if stride>=float(config.step_distance):
        stride=fmod(stride,float(config.step_distance))
        play_effect("run" if running else "step")
func sync(events: Array):
    if cursor>events.size(): cursor=events.size()
    for i in range(cursor,events.size()):
        match events[i].kind:
            "door": play_effect("door")
            "door_hit","door_broken": play_effect("door")
            "fired": play_effect("gunshot")
            "injured": play_effect("hurt")
            "looted","recovered","stored","retrieved","dropped": play_effect("loot")
            "reloaded","unloaded": play_effect("reload")
    cursor=events.size()
func toggle_mute():
    muted=not muted
    if muted:
        for voice in voices: voice.stop()
func _exit_tree():
    for voice in voices:
        voice.stop()
        voice.stream=null
    voices.clear()
    clips.clear()
