extends SceneTree
## Native AudioStreamPlayer regression, no world save or test credentials.
const Music=preload("res://scripts/scene_music.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func scene(region:String,time:float,roof:="")->Dictionary:
	return {"region_id":region,"time":time,"players":{"reader":{"x":41.5,"y":35.5}},"roofs":{} if roof.is_empty() else {"41,35":{"type":roof}}}
func run()->void:
	assert(DisplayServer.get_name()!="headless","Needs a real native audio driver")
	var music:=Music.new()
	root.add_child(music)
	music.set_volume(0.12)
	var results:Array=[]
	for entry in [[scene("home",1200.0),"home_night"],[scene("home",600.0,"roof"),"house_interior"],[scene("home",600.0,"greenhouse_roof"),"greenhouse_interior"],[scene("lanyang",600.0),"lanyang"],[scene("mine_7",600.0),"mine_7"]]:
		music.set_title()
		music.set_world(scene("home",600.0),"reader")
		music.set_epilogue(true)
		await create_timer(0.06).timeout
		var voice:=music.current
		var fade:=music.fade
		music.set_world(entry[0],"reader")
		music.set_world(entry[0],"reader")
		expect(music.scene_id=="festival_epilogue" and music.current==voice and music.fade==fade and voice.playing,"Background updates never interrupt or restart the story recording")
		expect(music.story_return_track==entry[1],"Story remembers the latest underlying scene: "+entry[1])
		expect(music.world_region==entry[0].region_id and music.pending_track.is_empty(),"Underlying region tracks changes without a delayed zone switch")
		music.set_epilogue(false)
		expect(music.scene_id==entry[1] and music.current.playing,"Closing the story starts the current scene recording: "+entry[1])
		await create_timer(Music.FADE_SECONDS+0.05).timeout
		expect(music.current.playing and not music.outgoing.playing,"Story crossfade settles to only the requested scene")
		results.append({"expected":entry[1],"actual":music.scene_id})
	# Multiple changes while reading: only the final scene should return.
	music.set_epilogue(true)
	music.set_world(scene("lanyang",600.0),"reader")
	music.set_world(scene("home",1200.0),"reader")
	music.set_world(scene("home",1200.0,"roof"),"reader")
	music.set_volume(0.0)
	music.set_epilogue(false)
	expect(music.scene_id=="house_interior" and music.current.volume_db==Music.SILENT_DB and music.outgoing.volume_db==Music.SILENT_DB,"Latest scene wins and both crossfade voices respect mute")
	music.set_title()
	expect(music.story_return_track.is_empty() and music.world_region.is_empty(),"Returning to title clears the background scene")
	music.set_epilogue(false)
	expect(music.scene_id=="title","A stale close cannot return to a departed world")
	music.stop()
	expect(not music.current.playing and not music.outgoing.playing,"Cleanup stops both voices")
	music.queue_free()
	await process_frame
	await process_frame
	print("MUSIC_STORY_RETURN checks=%d failures=%d cases=%s"%[checks,failures,JSON.stringify(results)])
	quit(int(failures>0))
