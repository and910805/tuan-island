extends SceneTree
const Main=preload("res://main.tscn")
const Music=preload("res://scripts/scene_music.gd")
const Audio=preload("res://scripts/soft_audio.gd")
const Regions=preload("res://scripts/regions.gd")
const Almanac=preload("res://scripts/life_ui_almanac.gd")
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func wait_for_cue(audio:Audio,kind:String) -> bool:
	var deadline:=Time.get_ticks_msec()+1200
	while Time.get_ticks_msec()<deadline:
		if audio.player.playing and audio.player.stream==audio.sounds[kind]:return true
		await process_frame
	return false

func run() -> void:
	var known:=["title","home_night","festival_epilogue"]+Regions.ALL+Music.ZONE_TRACKS+Music.SETTING_TRACKS
	var lengths:Dictionary={}
	for scene:String in known:
		var path:="res://assets/music/%s.ogg"%scene
		var stream:=load(path) as AudioStreamOggVorbis
		expect(stream!=null and stream.get_length()>30.0,"Exportable theme: "+scene)
		if stream!=null:
			var recording_hash:=FileAccess.get_sha256(path)
			expect(not recording_hash.is_empty() and not lengths.has(recording_hash),"Different recording bytes for "+scene)
			lengths[recording_hash]=scene
	for scene:String in Music.MILESTONE_TRACKS:
		var cue:=load("res://assets/music/%s.ogg"%scene) as AudioStreamOggVorbis
		expect(cue!=null and cue.get_length()>7.0 and cue.get_length()<13.0,"Short musical cue for "+scene)
	var unfinished:={"region_id":"home"}
	for entry:Array in [[{"board":true},"story_bridge"],[{"picnic":true},"story_picnic"],
		[{"public_kitchen":{"opened":true}},"story_kitchen"],[{"mine_depths":{"hoist":true}},"story_hoist"],
		[{"dock_stage":2},"story_boat"]]:
		var completed:=unfinished.duplicate()
		completed.merge(entry[0])
		expect(Music.milestone_for(unfinished,completed)==entry[1] and Music.milestone_for(completed,completed).is_empty(),"Each milestone triggers once: "+str(entry[1]))
		expect(Music.milestone_for({},completed).is_empty(),"First snapshot does not replay "+str(entry[1]))
	expect(Music.track_for("home",359.0)=="home_night" and Music.track_for("home",360.0)=="home","Home changes at 06:00")
	expect(Music.track_for("home",1139.0)=="home" and Music.track_for("home",1140.0)=="home_night","Home changes at 19:00")
	expect(Music.track_for("mine_12",1140.0)=="mine_12","Below ground does not follow daylight")

	expect(Music.home_zone({},Vector2(25.5,28.5))=="home_forest","West woods have their own theme")
	expect(Music.home_zone({},Vector2(53.5,37.5))=="home_river","The fishing-meet shore is in the river zone")
	expect(Music.home_zone({},Vector2(47.5,30.5))=="home_coast","The ferry pier is in the coastal zone")
	expect(Music.home_zone({},World.WANGAN_COAST.FERRY_LANDING)=="home_coast","A new player hears the harbor theme on the ferry landing")
	var court_center:=Vector2(World.WANGAN_MEMORY.COURT_SIGN)+Vector2(0.5,0.5)
	expect(Music.home_zone({},court_center)==Music.COURTYARD_TRACK,"The open courtyard has its own theme")
	var occupied_court:={"ground":{World.key(World.WANGAN_MEMORY.COURT_SIGN):{"type":"floor"}}}
	expect(Music.home_zone(occupied_court,court_center).is_empty(),"An older building on the site keeps the village theme")
	expect(Music.home_zone({},Vector2(54.5,53.5))==Music.SOUTH_SHORE_TRACK,"The southern shore uses a separate recording from the dock")
	var star_shore:=Vector2(World.WANGAN_COAST.STAR_SAND)+Vector2(0.5,0.5)
	expect(Music.home_zone({},star_shore).is_empty()
		and Music.home_zone({"wangan_star_walk":true},star_shore)==Music.STAR_SHORE_TRACK,"Repair opens a separate star shore theme")
	expect(Music.home_zone({},Vector2(36.5,30.5)).is_empty(),"A locked market does not override the plaza")
	var market_state:={"picnic":true,"objects":{"36,30":{"type":"bench"}}}
	expect(Music.home_zone(market_state,Vector2(36.5,26.5))=="home_market","Market theme follows the live fallback stall")
	expect(Music.home_zone({},Vector2(45.5,26.5)).is_empty(),"Starter fields keep the normal village theme")
	var salt_arrival:=World.SALT_PAN.ARRIVAL
	expect(Music.local_track({},World.SALT_PAN.REGION,{"x":salt_arrival.x,"y":salt_arrival.y}).is_empty(),
		"The Beimen bus stop retains the town theme")
	for origin:Vector2i in World.SALT_PAN.LOT_ORIGINS:
		expect(Music.local_track({},World.SALT_PAN.REGION,{"x":origin.x+4.5,"y":origin.y+1.5})==Music.SALT_PAN_TRACK,
			"Each salt lot's walkable divider has the working-pool theme")
	expect(Music.local_track({},"home",{"x":22.5,"y":14.5})!=Music.SALT_PAN_TRACK,
		"The salt pan theme is restricted to Beimen")
	expect(Audio.machine_profile({"type":"waterworks","job":{"ready":110.0}},100.0)=="waterwheel","A running waterworks has a waterwheel loop")
	expect(Audio.machine_profile({"type":"mine_drill","job":{"ready":100.0}},100.0).is_empty(),"A due drill is no longer audible")
	expect(Audio.machine_profile({"type":"small_smelter","processing":{"active":{"finish":110.0}}},100.0)=="furnace","An active smelter uses the furnace loop")
	expect(Audio.machine_profile({"type":"mill","auto_enabled":true,"items":{"flour":3}},100.0).is_empty(),"An enabled but idle mill is silent")

	if DisplayServer.get_name()=="headless":
		finish()
		return
	var path:="user://music-playback-%d.json"%OS.get_process_id()
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	app.settings_path="user://music-ui-%d.cfg"%OS.get_process_id()
	var mixer:Music=app.sound.music
	expect(mixer.scene_id=="title" and mixer.current.playing,"Title begins to play")
	if app.session.host(0,"配樂驗收",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world=app.session.world
	var person:Dictionary=world.state.players[app.session.profile.token]
	expect(mixer.scene_id=="home_coast" and mixer.current.playing and app.sound.ambience_kind=="water","The new dock arrival plays the coastal recording and water ambience")
	person.x=World.SPAWN.x
	person.y=World.SPAWN.y
	world.state.time=800.0
	app.session._send_snapshot(1)
	await create_timer(Music.ZONE_DWELL_SECONDS+0.1).timeout
	expect(mixer.scene_id=="home" and mixer.current.stream.loop,"Entering at daytime plays the looping village recording")
	expect(app.sound.ambience_kind=="wind" and app.sound.ambience.playing,"Village ambience has an independent looping voice")
	var local_cell:=Vector2i(int(person.x),int(person.y))
	var actor:="music-test-neighbor"
	world.add_player(actor,"鄰居")
	world.active_tokens[actor]=true
	app.session.peers[2]=actor
	app.session._record_tool_action(actor,"axe",local_cell+Vector2i(1,0),"")
	app.session._record_tool_action(actor,"pick",local_cell+Vector2i(16,0),"")
	app.session._send_snapshot(1)
	expect(not app.sound.nearby.playing,"A far-away strike produces no sound")
	app.session._record_tool_action(actor,"axe",local_cell+Vector2i(1,0),"")
	app.session._send_snapshot(1)
	expect(app.sound.nearby.playing and app.sound.nearby.stream==app.sound.sounds.wood_hit,"Nearby confirmed chop plays through the game snapshot")
	var first_gain:float=app.sound.nearby_gain
	app.session._record_tool_action(actor,"pick",local_cell+Vector2i(3,0),"")
	app.session._send_snapshot(1)
	expect(app.sound.nearby.stream==app.sound.sounds.wood_hit,"Busy nearby voice suppresses overlapping strikes")
	await create_timer(0.27).timeout
	app.session._send_snapshot(1)
	expect(not app.sound.nearby.playing,"Repeating the snapshot does not replay a strike")
	app.session._record_tool_action(actor,"pick",local_cell+Vector2i(4,0),"")
	app.session._send_snapshot(1)
	expect(app.sound.nearby.stream==app.sound.sounds.stone_hit and app.sound.nearby_gain<first_gain,"Farther strikes have lower gain")
	await create_timer(0.27).timeout
	app.session._record_tool_action(app.session.profile.token,"harvest",local_cell,"")
	app.session._send_snapshot(1)
	expect(not app.sound.nearby.playing,"The listener's own action is excluded from nearby sound")
	app.session.peers.erase(2)
	var saw:=Vector2i(41,36)
	var saw_key:=World.key(saw)
	var old_position:=Vector2(person.x,person.y)
	var token:String=app.session.profile.token
	var saved_saw:Dictionary=world.state.objects.get(saw_key,{}).duplicate(true)
	world.state.objects[saw_key]={"type":"sawmill","owner":token,"items":{}}
	person.x=41.5
	person.y=37.5
	person.inventory.wood=4
	app.session._send_snapshot(1)
	expect(not app.sound.machine.playing,"An idle saw is silent")
	app.session.perform("queue_processing",saw,"plank")
	expect(app.sound.machine.playing and app.sound.machine_kind=="mechanism"
		and app.sound.machine.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"Queuing a real plank batch starts the saw loop")
	var near_gain:float=app.sound.machine_gain
	person.y=40.5
	app.session._send_snapshot(1)
	expect(app.sound.machine.playing and app.sound.machine_gain<near_gain,"The active saw gets quieter farther away")
	person.y=45.5
	app.session._send_snapshot(1)
	expect(not app.sound.machine.playing,"Leaving the audible radius stops the loop")
	person.y=37.5
	app.session._send_snapshot(1)
	expect(app.sound.machine.playing,"Returning to the running job restores the loop")
	app.sound.master_volume=0.0
	app.sound.refresh_gains()
	var finish_time:float=world.state.objects[saw_key].processing.active.finish
	world.step(finish_time-float(world.state.time)+0.1,true)
	app.session._send_snapshot(1)
	expect(not app.sound.machine.playing and world.state.objects[saw_key].processing.ready.size()==1,"Completion stops the loop with the product still waiting to be claimed")
	expect(app.activity_caption.visible and "完工" in app.activity_caption.text and app.sound.master_volume==0.0,"A nearby completed batch is captioned with master muted")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("activity-caption.png"))==OK,"Capture activity caption")
	app._update_activity_caption(4.0)
	app.session._send_snapshot(1)
	expect(not app.activity_caption.visible,"Repeated snapshots do not repeat the completed-batch caption")
	var crop:=saw+Vector2i.RIGHT
	var crop_key:=World.key(crop)
	var old_crop:Dictionary=world.state.crops.get(crop_key,{}).duplicate(true)
	world.state.crops[crop_key]={"owner":token,"kind":"radish","growth":10000.0,"wet":true,"remaining":1}
	app.session.perform("harvest",crop)
	expect(app.activity_caption.visible and "採收完成" in app.activity_caption.text,"Real harvest displays a caption with master muted")
	if old_crop.is_empty():world.state.crops.erase(crop_key)
	else:world.state.crops[crop_key]=old_crop
	app._update_activity_caption(4.0)
	app.sound.activity_captions=false
	app._caption("不顯示",1)
	expect(not app.activity_caption.visible,"Activity captions can be disabled")
	app.sound.activity_captions=true
	app.sound.master_volume=1.0
	app.sound.refresh_gains()
	if saved_saw.is_empty():world.state.objects.erase(saw_key)
	else:world.state.objects[saw_key]=saved_saw
	person.x=old_position.x
	person.y=old_position.y
	app.session._send_snapshot(1)
	var voice:=mixer.current
	var tween:=mixer.fade
	for offset in range(3):
		person.x+=0.1
		app.session._send_snapshot(1)
	expect(mixer.current==voice and mixer.fade==tween,"Same-region snapshots leave playback and fade alone")
	await create_timer(1.22).timeout
	expect(not mixer.outgoing.playing and mixer.current.playing,"Faded voice is released")
	expect(is_equal_approx(mixer.current.volume_db,linear_to_db(app.sound.music_volume)) or app.sound.music_volume==0.0,"Current theme reaches configured loudness")

	person.x=29.9
	person.y=28.5
	app.session._send_snapshot(1)
	expect(mixer.pending_track=="home_forest","Moving into the woods queues the forest theme")
	await create_timer(0.2).timeout
	person.x=30.1
	app.session._send_snapshot(1)
	expect(mixer.pending_track.is_empty() and mixer.current==voice,"Brief boundary crossing keeps the same recording")
	person.x=25.5
	app.session._send_snapshot(1)
	await create_timer(Music.ZONE_DWELL_SECONDS+0.12).timeout
	expect(mixer.scene_id=="home_forest" and mixer.outgoing.playing,"Staying in the woods switches with a crossfade")
	for zone:Array in [[Vector2(54.5,38.5),"home_river"],[Vector2(47.5,30.5),"home_coast"]]:
		var location:Vector2=zone[0]
		person.x=location.x
		person.y=location.y
		app.session._send_snapshot(1)
		mixer._process(Music.ZONE_DWELL_SECONDS)
		expect(mixer.scene_id==zone[1],"Settling near landmark chooses "+str(zone[1]))
	person.x=court_center.x
	person.y=float(World.WANGAN_MEMORY.COURT.end.y)+0.5
	app.session._send_snapshot(1)
	for step in 8:world.move_player(token,Vector2.UP,0.25/3.6)
	app.session._send_snapshot(1)
	expect(mixer.pending_track==Music.COURTYARD_TRACK,"Walking into the stone yard queues the courtyard recording")
	await create_timer(Music.ZONE_DWELL_SECONDS+0.12).timeout
	expect(mixer.scene_id==Music.COURTYARD_TRACK and mixer.current.playing and mixer.current.stream.loop and mixer.outgoing.playing,"The old house theme crossfades and loops")
	var courtyard_voice:=mixer.current
	app._map_menu()
	await process_frame
	expect(mixer.current==courtyard_voice and mixer.current.playing,"Opening the map keeps the courtyard recording playing")
	app._close_modal()
	for step in 8:world.move_player(token,Vector2.DOWN,0.25/3.6)
	app.session._send_snapshot(1)
	expect(mixer.pending_track=="home","Leaving the courtyard queues the village recording")
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id=="home" and mixer.current.playing,"Walking out returns to the village theme")
	person.x=50.5
	person.y=50.5
	for step in 14:world.move_player(token,Vector2.DOWN,0.14)
	app.session._send_snapshot(1)
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id==Music.SOUTH_SHORE_TRACK and mixer.current.playing and app.sound.ambience_kind=="water","Walking down the boardwalk plays the south shore theme with water ambience")
	world.state.wangan_star_walk=true
	person.x=star_shore.x
	person.y=star_shore.y
	app.session._send_snapshot(1)
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id==Music.STAR_SHORE_TRACK and mixer.current.playing and app.sound.ambience_kind=="water","The unlocked star shore plays its own melody and sea ambience")
	world.state.picnic=true
	app.view.data.picnic=true # Market availability is pre-existing for this zone test.
	person.x=36.5
	person.y=30.5
	app.session._send_snapshot(1)
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id=="home_market","Unlocked market plays its own recording")
	person.x=41.5
	app.session._send_snapshot(1)
	expect(mixer.pending_track=="home" and mixer.scene_id=="home_market","Leaving a zone also waits before returning to the base theme")

	person.region="lanyang"
	app.session._send_snapshot(1)
	expect(mixer.pending_track.is_empty(),"Changing maps cancels queued home themes")
	expect(mixer.scene_id=="lanyang" and mixer.current.playing and mixer.outgoing.playing,"Travel starts overlapping tracks")
	await create_timer(0.2).timeout
	expect(mixer.blend>0.0 and mixer.blend<1.0,"Travel fade is gradual")
	person.region="mine_7"
	app.session._send_snapshot(1)
	expect(mixer.scene_id=="mine_7" and mixer.current.playing,"Rapid second transition chooses the newest floor")
	expect(app.sound.ambience_kind=="cave" and app.sound.ambience.playing,"The mine uses the cave ambience")
	await create_timer(1.22).timeout
	expect(not mixer.outgoing.playing and mixer.current.playing,"Interrupted transition leaves only the requested theme")
	person.region="home"
	person.x=41.5
	world.state.time=1200.0
	app.session._send_snapshot(1)
	expect(mixer.scene_id=="home_night","Returning after sunset plays the night arrangement")
	var roof_key:=World.key(Vector2i(int(person.x),int(person.y)))
	var roofs:Dictionary=world.state.roofs
	var original_roof:Dictionary=roofs.get(roof_key,{})
	roofs[roof_key]={"type":"roof","owner":token}
	app.session._send_snapshot(1)
	expect(mixer.pending_track=="house_interior" and mixer.scene_id=="home_night","Briefly crossing a house threshold keeps the outdoor music")
	await create_timer(Music.ZONE_DWELL_SECONDS+0.12).timeout
	expect(mixer.scene_id=="house_interior" and mixer.current.playing and mixer.outgoing.playing,"Staying in the house starts the house theme with a fade")
	roofs[roof_key]={"type":"greenhouse_roof","owner":token}
	app.session._send_snapshot(1)
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id=="greenhouse_interior" and mixer.current.playing,"The greenhouse has its own theme")
	var aboard:Dictionary=app.session.snapshot.duplicate(true)
	aboard.players[app.session.own_id].at_sea=true
	mixer.set_world(aboard,app.session.own_id)
	expect(mixer.scene_id=="island_voyage" and mixer.current.playing,"The real voyage snapshot flag overrides the shore")
	if original_roof.is_empty():roofs.erase(roof_key)
	else:roofs[roof_key]=original_roof
	app.session._send_snapshot(1)
	expect(mixer.scene_id=="home_night","Disembarking resumes the outdoor night theme")
	var resume:Dictionary=app.session.snapshot.duplicate(true)
	resume.roofs[roof_key]={"type":"roof","owner":token}
	mixer.set_title()
	mixer.set_world(resume,app.session.own_id)
	expect(mixer.scene_id=="house_interior" and mixer.pending_track.is_empty(),"First snapshot inside a roofed room starts with the house track")
	app.session._send_snapshot(1)
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id=="home_night","Leaving shelter returns to the correct outdoor time-of-day arrangement")

	person.x=40.5
	person.y=30.5
	person.inventory.wood=30
	person.inventory.stone=10
	app.session._send_snapshot(1)
	app.session.perform("donate",Vector2i(40,29))
	expect(world.state.board and mixer.scene_id=="story_bridge" and not mixer.current.stream.loop,"Completing the bridge over the normal game action plays a non-looping cue")
	voice=mixer.current
	tween=mixer.fade
	app.session._send_snapshot(1)
	expect(mixer.current==voice and mixer.fade==tween,"An unchanged completion snapshot does not restart the cue")
	var cue_duration:float=voice.stream.get_length()
	await create_timer(cue_duration+0.35).timeout
	expect(mixer.scene_id=="home_night" and mixer.current.playing,"Natural cue completion restores the current outdoor arrangement")

	app.session.snapshot.festival_story={"opened":false}
	Almanac.festival_story(app)
	expect(mixer.scene_id=="home_night","The festival checklist uses the local scene music")
	app.session.snapshot.festival_story={"opened":true}
	Almanac.festival_story(app)
	expect(mixer.scene_id=="festival_epilogue" and mixer.current.playing and mixer.current.stream.loop,
		"The opened festival dialogue plays the looping epilogue")
	voice=mixer.current
	tween=mixer.fade
	app.session._send_snapshot(1)
	app.session.snapshot.festival_story={"opened":true}
	Almanac.festival_story(app,false,1)
	expect(mixer.current==voice and mixer.fade==tween,"Snapshot and turning dialogue pages leave the recording alone")
	world.state.time=600.0
	app.session._send_snapshot(1)
	expect(mixer.scene_id=="festival_epilogue" and mixer.current==voice and mixer.story_return_track=="home",
		"Daybreak while reading updates the return theme without interrupting the story")
	# Let the reader actually hear the story before checking which voice fades
	# out. A quick close legitimately retains the louder preceding recording.
	await create_timer(Music.FADE_SECONDS+0.05).timeout
	app._close_modal()
	expect(mixer.scene_id=="home" and mixer.outgoing==voice,"Leaving the epilogue crossfades to the current daytime village")
	world.state.time=1200.0
	app.session._send_snapshot(1)
	expect(mixer.scene_id=="home_night","Subsequent snapshots still select the current time normally")

	var prefs:="user://music-prefs-%d.cfg"%OS.get_process_id()
	expect(app.sound.save_preferences(prefs,0.4,true,2,null,null,null,0.0),"Music mute saves")
	expect(is_equal_approx(mixer.current.volume_db,-80.0) and is_equal_approx(mixer.outgoing.volume_db,-80.0),"Both voices respect mute during a transition")
	expect(app.sound.play_cue("reward",true),"SFX still plays while music is muted")
	var reloaded:=Audio.new()
	root.add_child(reloaded)
	expect(reloaded.load_preferences(prefs) and reloaded.music_volume==0.0 and reloaded.volume==0.4,"Independent audio levels survive reload")
	expect(not reloaded.save_preferences(prefs,0.4,true,2,null,null,null,2.0),"Invalid music volume rejected")
	var old:=ConfigFile.new()
	old.set_value("comfort","volume",0.0)
	old.save(prefs)
	expect(reloaded.load_preferences(prefs) and reloaded.music_volume==0.0 and reloaded.interface_volume==0.0
		and reloaded.ambience_volume==0.0,"Legacy silence stays silent across the new channels")
	app._settings_menu()
	await process_frame
	var slider:=app.modal.find_child("MusicVolume",true,false) as HSlider
	var master:=app.modal.find_child("MasterVolume",true,false) as HSlider
	var ambience:=app.modal.find_child("AmbienceVolume",true,false) as HSlider
	var interface:=app.modal.find_child("InterfaceVolume",true,false) as HSlider
	var action:=app.modal.find_child("ActionVolume",true,false) as HSlider
	var captions:=app.modal.find_child("ActivityCaptions",true,false) as CheckBox
	expect(captions!=null and captions.button_pressed,"Settings exposes the default-on caption switch")
	expect(master!=null and ambience!=null and interface!=null and action!=null,"All mixer sliders are available")
	expect(slider!=null and slider.value==0.0,"Settings exposes the saved music level")
	var save:=app.modal.find_child("SaveComfort",true,false) as Button
	expect(save!=null and app.modal.get_global_rect().encloses(save.get_global_rect()),"Save button stays in the settings footer")
	if slider!=null and save!=null:
		slider.value=55.0
		save.pressed.emit()
		await process_frame
	expect(is_equal_approx(app.sound.music_volume,0.55) and is_equal_approx(app.sound.volume,0.4),"Settings changes only music volume")
	if master!=null and ambience!=null and interface!=null and action!=null and save!=null:
		master.value=50.0
		ambience.value=20.0
		interface.value=0.0
		action.value=60.0
		captions.button_pressed=false
		save.pressed.emit()
		await process_frame
		expect(is_equal_approx(mixer.volume,0.275) and is_equal_approx(app.sound.ambience.volume_db,-20.0),
			"Master multiplies both music and ambience")
		expect(not app.sound.play_cue("notice",true) and app.sound.play_cue("fish_cast",true),
			"Muting interface cues leaves fishing audible")
		expect(is_equal_approx(app.sound.player.volume_db,linear_to_db(0.30)),"Master multiplies action gain")
		expect(reloaded.load_preferences(app.settings_path) and reloaded.master_volume==0.5 and reloaded.ambience_volume==0.2
			and reloaded.interface_volume==0.0 and reloaded.volume==0.6,"All saved mixer values reload independently")
		expect(not reloaded.activity_captions,"Caption preference survives reload")
		master.value=0.0
		save.pressed.emit()
		await process_frame
		expect(mixer.volume==0.0 and app.sound.ambience.volume_db==-80.0 and not app.sound.play_cue("action",true),
			"Master mute silences three playback paths")
		master.value=50.0
		save.pressed.emit()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("music-settings.png"))==OK,"Capture audio preferences")
	var cow:Vector2i=World.LIVESTOCK.ANIMALS.cow.cell
	person.region="home"
	person.x=cow.x+0.5
	person.y=cow.y+0.5
	person.inventory.feed=1
	world.state.picnic=true
	app.session._send_snapshot(1)
	app.sound.stop_cues()
	app.session.perform("livestock_feed",cow,"cow")
	await create_timer(0.18).timeout
	expect(app.sound.player.playing and app.sound.player.stream==app.sound.sounds.feed_trough,
		"Confirmed feeding plays the trough cue through the action channel")
	await create_timer(0.45).timeout
	app.session.perform("livestock_pet",cow,"cow")
	await create_timer(0.18).timeout
	expect(app.sound.player.playing and app.sound.player.stream==app.sound.sounds.cow,
		"Petting still plays the cow cue")
	await create_timer(0.45).timeout
	expect(world.step(World.LIVESTOCK.DAY*2,true),"The fed cow produces milk")
	app.session._send_snapshot(1)
	app.session.perform("livestock_collect",cow,"cow")
	await create_timer(0.18).timeout
	expect(app.sound.player.playing and app.sound.player.stream==app.sound.sounds.basket,
		"Collecting produces the separate basket cue")
	await create_timer(0.45).timeout
	var work_plot:=Vector2i(42,36)
	person.x=42.5
	person.y=36.5
	person.inventory.tiller=1
	person.inventory.charcoal=0
	app.session._send_snapshot(1)
	app.sound.stop_cues()
	app.session.perform("till_area",work_plot)
	expect(app.sound.pending_action!="farm_pass" and app.sound.player.stream!=app.sound.sounds.farm_pass,
		"A rejected pass without fuel never plays the machine cue")
	await create_timer(0.45).timeout
	person.inventory.charcoal=1
	app.session.perform("till_area",work_plot)
	var tiller_played:=await wait_for_cue(app.sound,"farm_pass")
	expect(int(person.inventory.charcoal)==0 and tiller_played,
		"A confirmed tiller pass consumes fuel and plays the rolling cue")
	var worked_cells:Array=person.last_till.cells
	person.inventory.seeder=1
	person.inventory.harvester=1
	person.inventory.charcoal=2
	person.inventory.radish_seed=worked_cells.size()
	app.sound.stop_cues()
	app.session.perform("seed_area",work_plot,"radish")
	var seeder_played:=await wait_for_cue(app.sound,"farm_pass")
	var sown_cells:Array=person.last_seed.cells
	expect(int(person.inventory.charcoal)==1 and int(person.inventory.radish_seed)==0
		and sown_cells.size()==worked_cells.size() and worked_cells.all(func(key):return sown_cells.has(key)),
		"Seeder spends one fuel and one seed per tilled cell")
	expect(seeder_played,
		"A confirmed seeder pass plays the rolling cue")
	for key:String in worked_cells:
		expect(world.act(token,"water-"+key,"water",World.cell(key)).ok,"Water machine-sown plot "+key)
	expect(world.step(float(World.CROPS.radish.time)+1.0,true),"Machine-sown radishes mature through world time")
	app.session._send_snapshot(1)
	var before_harvest:=int(person.inventory.get("radish",0))
	app.sound.stop_cues()
	app.session.perform("harvest_area",work_plot)
	var harvester_played:=await wait_for_cue(app.sound,"farm_pass")
	var harvested_cells:Array=person.last_harvest.cells
	expect(int(person.inventory.charcoal)==0 and harvested_cells.size()==worked_cells.size()
		and worked_cells.all(func(key):return harvested_cells.has(key))
		and int(person.inventory.radish)==before_harvest+worked_cells.size(),"Harvester spends one fuel and collects the same field")
	expect(harvester_played,
		"A confirmed harvester pass plays the rolling cue")
	app._disconnected()
	expect(mixer.scene_id=="title" and mixer.current.playing,"Disconnect fades back to the title")
	expect(not app.sound.ambience.playing,"Returning to the title stops the world ambience")
	for region:String in Regions.ALL:
		var snapshot:Dictionary=world.region_snapshot(region)
		snapshot.time=800.0
		mixer.set_world(snapshot,"")
		var path_for_region:="res://assets/music/%s.ogg"%region
		expect(mixer.scene_id==region and mixer.current.playing and mixer.current.stream.loop
			and mixer.current.stream.resource_path==path_for_region,"The native player starts the region's own looping recording: "+region)
	var salt_snapshot:Dictionary=world.region_snapshot(World.SALT_PAN.REGION)
	var salt_visitor:={"x":salt_arrival.x,"y":salt_arrival.y}
	salt_snapshot.players={"visitor":salt_visitor}
	mixer.set_world(salt_snapshot,"visitor")
	expect(mixer.scene_id=="beimen" and mixer.current.playing,"Arriving at the bus stop plays the Beimen town track")
	var town_voice:=mixer.current
	salt_visitor.x=36.5
	salt_visitor.y=21.5
	mixer.set_world(salt_snapshot,"visitor")
	expect(mixer.pending_track==Music.SALT_PAN_TRACK and mixer.current==town_voice,"The salt pans wait for a sustained visit")
	await create_timer(Music.ZONE_DWELL_SECONDS+0.12).timeout
	expect(mixer.scene_id==Music.SALT_PAN_TRACK and mixer.current.playing and mixer.current.stream.loop
		and mixer.outgoing==town_voice and town_voice.playing,"The working-pool recording loops and crossfades from town")
	var salt_voice:=mixer.current
	await create_timer(Music.FADE_SECONDS+0.12).timeout
	expect(salt_voice.get_playback_position()>0.2 and not town_voice.playing,"The salt-pan recording plays through the transition")
	salt_visitor.x=salt_arrival.x
	salt_visitor.y=salt_arrival.y
	mixer.set_world(salt_snapshot,"visitor")
	expect(mixer.pending_track=="beimen","Exiting the salt pans queues the town track")
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id=="beimen" and mixer.current.playing and mixer.outgoing==salt_voice,"Leaving crossfades back to town")
	var tea_snapshot:Dictionary=world.region_snapshot("maokong")
	var tea_stand:=Vector2(World.TEA_REVISIT.HOUSE_SITE)+Vector2(-0.5,1.5)
	var visitor:={"x":tea_stand.x,"y":tea_stand.y}
	tea_snapshot.players={"visitor":visitor}
	mixer.set_world(tea_snapshot,"visitor")
	expect(mixer.scene_id=="maokong","The locked tea house site keeps the mountain theme")
	tea_snapshot.tea_revisit={"completed":true}
	tea_snapshot.festival_story={"opened":true}
	mixer.set_world(tea_snapshot,"visitor")
	expect(mixer.pending_track==Music.TEA_HOUSE_TRACK and mixer.scene_id=="maokong","The open tea house respects the zone dwell")
	await create_timer(Music.ZONE_DWELL_SECONDS+0.12).timeout
	expect(mixer.scene_id==Music.TEA_HOUSE_TRACK and mixer.current.playing and mixer.current.stream.loop
		and mixer.outgoing.playing,"The tea house recording loops and crossfades from the mountain theme")
	visitor.x+=5.0
	mixer.set_world(tea_snapshot,"visitor")
	expect(mixer.pending_track=="maokong","Leaving the tea house queues the mountain theme")
	mixer._process(Music.ZONE_DWELL_SECONDS)
	expect(mixer.scene_id=="maokong" and mixer.current.playing,"Walking away restores the mountain theme")
	var springs_snapshot:Dictionary=world.region_snapshot(Music.Springs.REGION)
	var springs_guest:={"x":28.5,"y":22.5}
	springs_snapshot.players={"visitor":springs_guest}
	mixer.set_world(springs_snapshot,"visitor")
	await create_timer(Music.FADE_SECONDS+0.12).timeout
	var outdoor_voice:=mixer.current
	var outdoor_position:float=outdoor_voice.get_playback_position()
	springs_guest.x=65.5
	springs_guest.y=26.5
	mixer.set_world(springs_snapshot,"visitor")
	expect(mixer.scene_id==Music.INN_TRACK and mixer.current.stream.loop and mixer.outgoing==outdoor_voice,"Inn plays its own theme over the fading outdoor recording")
	await create_timer(0.12).timeout
	var outdoor_db:float=outdoor_voice.volume_db
	springs_guest.x=28.5
	springs_guest.y=22.5
	mixer.set_world(springs_snapshot,"visitor")
	expect(mixer.scene_id==Music.Springs.REGION and mixer.current==outdoor_voice
		and mixer.current.get_playback_position()>=outdoor_position and is_equal_approx(mixer.current.volume_db,outdoor_db),
		"Quickly leaving the inn resumes the outdoor track without resetting its position or gain")
	app.sound.close()
	expect(not mixer.current.playing and not mixer.outgoing.playing,"Closing stops both music voices")
	app.session.shutdown()
	for file:String in [app.settings_path,prefs,path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	await create_timer(0.15).timeout
	finish()

func finish() -> void:
	print("SCENE_MUSIC_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
