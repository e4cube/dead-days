extends "res://tests/test_clinic_slice.gd"
func run():
    game=load("res://visual_slice_v1.tscn").instantiate()
    root.add_child(game)
    await process_frame
    game.store=load("res://scripts/save_store.gd").new("user://tests/audio_%d"%Time.get_ticks_usec())
    game.model.rules.zombie_spawns=[]
    game.new_run()
    for id in game.audio.clips:
        var clip: AudioStreamWAV=game.audio.clips[id]
        check(clip.data.size()>2000 and clip.mix_rate==22050,"nonempty PCM "+id)
        check(clip.data==game.audio.synthesize(game.audio.config.effects[id],22050).data,"repeatable PCM "+id)
        var peak:=0
        for i in clip.data.size()/2: peak=maxi(peak,absi(clip.data.decode_s16(i*2)))
        check(peak>100 and peak<26215,"non-silent bounded signal "+id)
    check(game.audio.voices.size()==8,"bounded voice pool")
    for pair in [["step","melee"],["step","impact"],["impact","gunshot"]]:
        check(game.audio.clips[pair[0]].data!=game.audio.clips[pair[1]].data,"distinct sound recipe "+str(pair))
    await to_point(Vector2(-7,1.2))
    key(KEY_E)
    game.refresh_hud()
    check(game.audio.played.get("door",0)==1,"actual door event triggers audio")
    await to_point(Vector2(-7,-2.25))
    key(KEY_E)
    game.refresh_hud()
    check(game.audio.played.get("step",0)>0 and game.audio.played.get("loot",0)>0,"actual movement and loot trigger audio")
    await to_point(Vector2(-7,2.5))
    Input.action_press("run")
    await to_point(Vector2(-4,2.5))
    Input.action_release("run")
    check(game.audio.played.get("run",0)>0,"running footsteps")
    check(game.try_attack(),"real melee action")
    check(game.audio.played.get("melee",0)==1,"successful melee feedback")
    check(game.audio.played.get("impact",0)==0,"empty swing does not claim impact")
    game.player.rotation.y=0
    game.sync_position()
    game.model.state.zombies=[game.model.make_zombie("audio_target",[game.player.position.x,0,game.player.position.z+.8])]
    game.build_world()
    game.model.state.combat.attack_cd=0
    check(game.try_attack() and game.audio.played.get("impact",0)==1,"actual melee contact triggers separate impact")
    game.model.state.inventory.pistol=1
    game.model.use_item("pistol")
    game.model.state.firearms.loaded=1 # Explicit finite-ammo audio fixture.
    game.model.state.combat.attack_cd=0
    check(game.try_attack(),"one loaded round fires")
    game.refresh_hud()
    check(game.audio.played.get("gunshot",0)==1 and game.model.state.firearms.loaded==0,"real shot consumes round and triggers shot audio")
    game.model.state.combat.attack_cd=0
    check(not game.try_attack() and game.audio.played.get("gunshot",0)==1,"empty gun produces no shot sound")
    game.model.damage_player(5,"audio_fixture")
    game.refresh_hud()
    check(game.audio.played.get("hurt",0)==1,"real damage transaction triggers feedback")
    var played: Dictionary=game.audio.played.duplicate()
    game.save_run()
    game.continue_run()
    game.refresh_hud()
    check(game.audio.played==played,"restore does not replay history")
    var noises: Array=game.model.state.noises.duplicate(true)
    key(KEY_M)
    game.audio.play_effect("gunshot")
    check(game.audio.played==played and game.model.state.noises==noises,"mute and playback never change perception state")
    key(KEY_M)
    game.audio.play_effect("gunshot")
    check(game.audio.played.get("gunshot",0)==2 and game.model.state.noises==noises,"unmute restores playback without AI noise")
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../work/audio-v2"))
    for id in ["step","melee","impact","gunshot"]:
        game.audio.clips[id].save_to_wav(ProjectSettings.globalize_path("res://../work/audio-v2/"+id+".wav"))
    for i in 20: await process_frame
    game.queue_free()
    for i in 3: await process_frame
    if failures==0: print("GAME_AUDIO_OK")
    quit(0 if failures==0 else 1)
