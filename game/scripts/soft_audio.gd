extends Node

# Original, synthesized cues: no downloaded recordings or external audio assets.
# General cues share one debounced voice. World sounds use separate players.
const RATE:=22050
const CART_ROLL_SECONDS:=0.44
const FISHING_CUES:=["fish_cast","fish_bite","fish_catch"]
const WORLD_CUES:=["machine_start","machine_claim","farm_pass","chicken","cow","sheep","duck","feed_trough","basket","meal_serve","meal_claim","stove_start","stove_claim"]
const NEARBY_CUES:={"axe":"wood_hit","pick":"stone_hit","harvest":"crop_pick"}
const NEARBY_RADIUS:=9.0
const NEARBY_MAX_GAIN:=0.32
const ACTION_DELAY_MS:=120
const FISHING_HOLDOFF_MS:=220
const Music=preload("res://scripts/scene_music.gd")
const World=preload("res://scripts/world.gd")
const MACHINE_RADIUS:=6.0
const MACHINE_GAIN:=0.32
var music:Music
var music_volume:=0.35
var volume:=0.45
var master_volume:=1.0
var ambience_volume:=0.25
var interface_volume:=0.45
var activity_captions:=true
var reduced_motion:=false
var preferred_zoom:=2
var forest_tools:=false
var standard_fishing:=false
var preferred_text_scale:=1
var fixed_area_camera:=false
var player:AudioStreamPlayer
var ambience:AudioStreamPlayer
var nearby:AudioStreamPlayer
var cart_roll:AudioStreamPlayer
var nearby_gain:=0.0
var nearby_region:=""
var machine:AudioStreamPlayer
var machine_kind:=""
var machine_gain:=0.0
var ambience_kind:=""
var ambience_streams:Dictionary={}
var cue_kind:=""
var sounds:Dictionary={}
var last_cue:=-1000
var last_fishing_cue:=-1000
var pending_action:=""
var action_due_at:=0

func _ready() -> void:
	player=AudioStreamPlayer.new()
	add_child(player)
	ambience=AudioStreamPlayer.new()
	add_child(ambience)
	nearby=AudioStreamPlayer.new()
	add_child(nearby)
	cart_roll=AudioStreamPlayer.new()
	cart_roll.stream=make_cue("cart_roll")
	add_child(cart_roll)
	machine=AudioStreamPlayer.new()
	add_child(machine)
	music=Music.new()
	add_child(music)
	music.set_volume(music_volume)
	for kind in ["action","reward","notice","memorial_bell","ceramic_chime","shell_chime"]+FISHING_CUES+WORLD_CUES+NEARBY_CUES.values():sounds[kind]=make_cue(kind)
	set_process(false)

func cue_gain(kind:String) -> float:
	if kind in ["ceramic_chime","shell_chime"]:return master_volume*ambience_volume
	return master_volume*(interface_volume if kind in ["notice","reward"] else volume)

static func action_cue(action:String,animal:String) -> String:
	match action:
		"assemble", "start_processing", "queue_processing", "toggle_auto_processing", "feed_processing":return "machine_start"
		"claim_processing", "collect_processing_output":return "machine_claim"
		"till_area", "seed_area", "harvest_area":return "farm_pass"
		"pet","chicken_hug":return "chicken"
		"feed", "livestock_feed":return "feed_trough"
		"livestock_pet","livestock_brush":return animal if animal in ["cow","sheep","duck"] else ""
		"serve_hotpot", "serve_watermelon", "serve_chowder":return "meal_serve"
		"claim_hotpot", "claim_watermelon", "claim_chowder":return "meal_claim"
		"cook", "queue_cook":return "stove_start"
		"claim_cook":return "stove_claim"
		"egg", "livestock_collect", "collector_collect", World.SEAWEED_POINT, World.WANGAN_COAST.SHELL_POINT, World.WANGAN_COAST.STAR_SAND_POINT:return "basket"
	return ""

func refresh_gains() -> void:
	if music:music.set_volume(master_volume*music_volume)
	if ambience:ambience.volume_db=Music.to_db(master_volume*ambience_volume)
	if nearby:nearby.volume_db=Music.to_db(nearby_gain*master_volume*volume)
	if machine:machine.volume_db=Music.to_db(machine_gain*master_volume*volume)
	if cart_roll:
		cart_roll.volume_db=Music.to_db(master_volume*volume*0.75)
		if master_volume*volume<=0.0:cart_roll.stop()
	if player and player.playing:
		var gain:=cue_gain(cue_kind)
		if gain<=0.0:player.stop()
		else:player.volume_db=Music.to_db(gain)

func set_world(snapshot:Dictionary,own_id:String) -> void:
	music.set_world(snapshot,own_id)
	var region:=str(snapshot.get("region_id","home"))
	if region!=nearby_region:
		nearby_region=region
		nearby.stop()
		cart_roll.stop()
		stop_machine()
	if DisplayServer.get_name()=="headless":return
	var person:Dictionary=snapshot.get("players",{}).get(own_id,{})
	update_machine(snapshot,person)
	if region==Music.Springs.REGION and Music.Springs.in_inn(person):
		stop_ambience()
		return
	var zone:=Music.home_zone(snapshot,Vector2(float(person.get("x",0)),float(person.get("y",0)))) if region=="home" else ""
	var kind:="cave" if region.begins_with("mine_") else "wind"
	if zone in ["home_coast","home_river",Music.SOUTH_SHORE_TRACK,Music.STAR_SHORE_TRACK] or region in ["toucheng","beimen"]:kind="water"
	if person.get("at_sea",false):kind="surf"
	if kind==ambience_kind:return
	if not ambience_streams.has(kind):ambience_streams[kind]=make_ambience(kind)
	ambience_kind=kind
	ambience.stream=ambience_streams[kind]
	ambience.volume_db=Music.to_db(master_volume*ambience_volume)
	ambience.play()

static func machine_profile(device:Dictionary,now:float) -> String:
	var kind:String=device.get("type","")
	if kind not in World.LOGISTICS.PROCESSORS and kind not in World.INDUSTRY.MANUAL_STATIONS and kind not in ["waterworks","mine_drill"]:return ""
	var queue:Dictionary=device.get("processing",{})
	var active:Dictionary=queue.get("active",{})
	if float(active.get("finish",0.0))<=now and float(device.get("job",{}).get("ready",0.0))<=now:return ""
	if kind in ["small_smelter","glass_furnace","clay_kiln","charcoal_kiln"]:return "furnace"
	if kind=="waterworks":return "waterwheel"
	return "mechanism"

static func completed_batch(previous:Dictionary,snapshot:Dictionary,own_id:String) -> String:
	if previous.is_empty() or previous.get("region_id")!=snapshot.get("region_id"):return ""
	var person:Dictionary=snapshot.get("players",{}).get(own_id,{})
	if person.is_empty():return ""
	var listener:=Vector2(person.x,person.y)
	var current:Dictionary=snapshot.get("objects",{})
	var closest:=MACHINE_RADIUS
	var machine_name:=""
	for key:String in previous.get("objects",{}):
		var past:Dictionary=previous.objects[key]
		var active:Dictionary=past.get("processing",{}).get("active",{})
		if active.is_empty() or active.get("owner")!=own_id:continue
		var device:Dictionary=current.get(key,{})
		var ready:Array=device.get("processing",{}).get("ready",[])
		if not ready.any(func(entry:Dictionary):return entry.id==active.id and entry.owner==own_id):continue
		var distance:=listener.distance_to(Vector2(World.cell(key))+Vector2(0.5,0.5))
		if distance>=closest:continue
		closest=distance
		machine_name=World.BUILD.get(device.get("type",""),{}).get("name","機台")
	return machine_name

func update_machine(snapshot:Dictionary,person:Dictionary) -> void:
	if person.is_empty() or person.get("at_sea",false):
		stop_machine()
		return
	var listener:=Vector2(person.x,person.y)
	var now:=float(snapshot.get("time",0.0))
	var closest:=MACHINE_RADIUS
	var kind:=""
	var objects:Dictionary=snapshot.get("objects",{})
	for key:String in objects:
		var profile:=machine_profile(objects[key],now)
		if profile.is_empty():continue
		var distance:=listener.distance_to(Vector2(World.cell(key))+Vector2(0.5,0.5))
		if distance>=closest:continue
		closest=distance
		kind=profile
	if kind.is_empty():
		stop_machine()
		return
	machine_gain=MACHINE_GAIN*pow(1.0-closest/MACHINE_RADIUS,2.0)
	machine.volume_db=Music.to_db(machine_gain*master_volume*volume)
	if kind==machine_kind:return
	if not ambience_streams.has(kind):ambience_streams[kind]=make_ambience(kind)
	machine_kind=kind
	machine.stream=ambience_streams[kind]
	machine.play()

func stop_machine() -> void:
	if machine_kind.is_empty():return
	machine_kind=""
	machine_gain=0.0
	machine.stop()

func play_nearby_tools(actors:Array,records:Dictionary,own_id:String,listener:Vector2) -> bool:
	if nearby.playing or master_volume*volume<=0.0:return false
	var closest:=NEARBY_RADIUS
	var cue:=""
	for actor in actors:
		if actor==own_id:continue
		var action:Dictionary=records.get(actor,{})
		if not NEARBY_CUES.has(action.get("tool","")):continue
		var distance:=listener.distance_to(Vector2(action.cell)+Vector2(0.5,0.5))
		if distance>=closest:continue
		closest=distance
		cue=NEARBY_CUES[action.tool]
	if cue.is_empty():return false
	nearby_gain=NEARBY_MAX_GAIN*pow(1.0-closest/NEARBY_RADIUS,2.0)
	nearby.volume_db=Music.to_db(nearby_gain*master_volume*volume)
	nearby.stream=sounds[cue]
	nearby.play()
	return true

func set_title() -> void:
	stop_ambience()
	stop_machine()
	music.set_title()

func stop_ambience() -> void:
	ambience_kind=""
	if ambience:ambience.stop()

static func make_ambience(kind:String) -> AudioStreamWAV:
	const AMBIENCE_RATE:=11025
	const LENGTH:=AMBIENCE_RATE*4
	var samples:=PackedByteArray()
	samples.resize(LENGTH*2)
	var bins:Array[int]=[103,187,271,383,491,629,797]
	if kind=="water":bins=[139,237,359,521,733,1019,1381]
	elif kind=="surf":bins=[59,127,211,317,541,827,1193]
	elif kind=="cave":bins=[41,61,97,137,187,241,311]
	elif kind=="mechanism":bins=[196,395,597,800,1103,1409,1871]
	elif kind=="waterwheel":bins=[131,221,361,497,711,983,1471]
	elif kind=="furnace":bins=[97,151,233,361,587,911,1301]
	for i in LENGTH:
		var phase:=TAU*i/LENGTH
		var wave:=0.0
		for index in bins.size():
			wave+=sin(bins[index]*phase+float(index*index))*sin(0.5+phase*(index%3+1))
		var swell:=0.65+0.24*sin(phase*(3 if kind=="water" else 1))
		if kind=="surf":swell=0.38+0.57*pow(0.5-0.5*cos(phase),2.0)
		if kind=="mechanism":swell*=0.62+0.36*sin(phase*8.0)
		if kind=="waterwheel":swell*=0.66+0.29*sin(phase*4.0)
		if kind=="furnace":swell*=0.79+0.18*sin(phase*2.0)
		samples.encode_s16(i*2,roundi(wave*swell*210.0))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=AMBIENCE_RATE
	stream.data=samples
	stream.loop_mode=AudioStreamWAV.LOOP_FORWARD
	stream.loop_end=LENGTH
	return stream

static func make_cue(kind:String) -> AudioStreamWAV:
	var duration:=0.24 if kind=="reward" else 0.10
	if kind=="memorial_bell":duration=0.68
	if kind=="ceramic_chime":duration=0.62
	if kind=="shell_chime":duration=0.52
	if kind in FISHING_CUES:duration=float({"fish_cast":0.18,"fish_bite":0.24,"fish_catch":0.30}[kind])
	if kind in WORLD_CUES:duration=0.36
	if kind in NEARBY_CUES.values():duration=0.22
	if kind=="cart_roll":duration=CART_ROLL_SECONDS
	var samples:=int(RATE*duration)
	var bytes:=PackedByteArray()
	bytes.resize(samples*2)
	for i in range(samples):
		var t:=float(i)/RATE
		var envelope:=minf(t/0.012,1.0)*pow(1.0-float(i)/samples,2.0)
		var frequency:=440.0 if kind=="action" else (330.0 if kind=="notice" else 523.25)
		var wave:=sin(TAU*frequency*t)*0.11
		if kind=="reward":wave+=sin(TAU*659.25*t)*0.035
		match kind:
			"cart_roll":
				var wheel:=0.45+0.55*pow(maxf(0.0,cos(TAU*18.0*t)),5.0)
				var rumble:=0.047*sin(TAU*94*t)+0.032*sin(TAU*143*t)+0.016*sin(TAU*617*t)
				wave=wheel*rumble+note(t-0.015,357.0,0.09)*0.55+note(t-0.29,218.0,0.14)*0.65
				envelope=minf(t/0.016,1.0)*clampf((duration-t)/0.045,0.0,1.0)
			"memorial_bell":
				wave=note(t,523.25,0.68)*0.66+note(t,1280.0,0.33)*0.27
				envelope=1.0
			"ceramic_chime":
				wave=note(t,440.0,0.59)*0.64+note(t,711.0,0.24)*0.24
				envelope=1.0
			"shell_chime":
				wave=note(t,1160.0,0.20)*0.36+note(t-0.06,1485.0,0.24)*0.27+note(t-0.15,970.0,0.27)*0.24
				envelope=1.0
			"fish_cast":
				wave=sin(TAU*(310.0*t-510.0*t*t))*0.11+sin(TAU*(710.0*t-1030.0*t*t))*0.022
			"fish_bite":
				wave=note(t,698.46,0.11)+note(t-0.08,880.0,0.14)
				envelope=1.0
			"fish_catch":
				wave=note(t,523.25,0.13)+note(t-0.055,659.25,0.14)+note(t-0.11,783.99,0.19)
				envelope=1.0
			"machine_start":
				wave=note(t,176.0,0.09)+note(t-0.06,268.0,0.11)+note(t-0.14,145.0,0.19)
				envelope=1.0
			"machine_claim":
				wave=note(t,315.0,0.15)+note(t-0.09,475.0,0.18)
				envelope=1.0
			"farm_pass":
				var teeth:=0.42+0.58*pow(maxf(0.0,cos(TAU*(24.0*t-23.0*t*t))),3.0)
				var motor:=sin(TAU*(112.0*t-37.0*t*t))*0.105+sin(TAU*228.0*t)*0.036
				wave=teeth*motor+note(t-0.16,268.0,0.12)*0.35
			"chicken":
				wave=note(t,630.0,0.09)+note(t-0.086,512.0,0.12)
				envelope=1.0
			"cow":
				wave=sin(TAU*(158.0*t-40.0*t*t))*0.12+sin(TAU*(317.0*t-80.0*t*t))*0.032
			"sheep":
				wave=sin(TAU*(392.0*t-150.0*t*t))*(0.09+0.028*sin(TAU*13.0*t))
			"duck":
				wave=note(t,210.0,0.09)*0.55+note(t-0.12,182.0,0.12)*0.5
				envelope=1.0
			"feed_trough":
				wave=note(t,244.0,0.08)*0.72+note(t-0.045,570.0,0.045)*0.4
				wave+=note(t-0.083,424.0,0.064)*0.42+note(t-0.13,285.0,0.11)*0.54
				envelope=1.0
			"basket":
				wave=note(t,294.0,0.09)+note(t-0.10,354.0,0.13)
				envelope=1.0
			"meal_serve":
				wave=note(t,260.0,0.10)*0.8+note(t-0.035,730.0,0.14)*0.58+note(t-0.074,1140.0,0.09)*0.28
				envelope=1.0
			"meal_claim":
				wave=note(t,435.0,0.10)*0.58+note(t-0.070,580.0,0.14)*0.70
				envelope=1.0
			"stove_start":
				wave=note(t,198.0,0.09)*0.65+note(t-0.047,285.0,0.13)*0.72+note(t-0.083,790.0,0.07)*0.22
				envelope=1.0
			"stove_claim":
				wave=note(t,392.0,0.13)*0.65+note(t-0.072,523.25,0.18)*0.72
				envelope=1.0
			"wood_hit":
				wave=(sin(TAU*140.0*t)+0.43*sin(TAU*231.0*t))*0.13
			"stone_hit":
				wave=(sin(TAU*580.0*t)+0.46*sin(TAU*1231.0*t))*0.12
			"crop_pick":
				wave=note(t,420.0,0.11)+note(t-0.05,540.0,0.12)
				envelope=1.0
		bytes.encode_s16(i*2,int(wave*envelope*32767.0))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=RATE
	stream.stereo=false
	stream.data=bytes
	return stream

static func note(t:float,frequency:float,duration:float)->float:
	if t<0.0 or t>=duration:return 0.0
	var envelope:=minf(t/0.012,1.0)*pow(1.0-t/duration,2.0)
	return envelope*(sin(TAU*frequency*t)*0.095+sin(TAU*2.0*frequency*t)*0.018)

func play_cue(kind:String="action",preview:bool=false) -> bool:
	var now:=Time.get_ticks_msec()
	var fishing:=kind in FISHING_CUES
	if fishing:
		cancel_pending_action()
		last_fishing_cue=now
	var gain:=cue_gain(kind)
	if player==null or gain<=0.0:return false
	if not preview and not fishing:
		if player.playing and player.stream in [sounds.fish_cast,sounds.fish_bite,sounds.fish_catch]:return false
		if now-last_cue<120:return false
	last_cue=now
	player.stop()
	cue_kind=kind
	player.volume_db=linear_to_db(gain)
	player.stream=sounds.get(kind,sounds.action)
	player.play()
	return true

func play_cart_roll(seconds:float)->void:
	var gain:=master_volume*volume*0.75
	if gain<=0.0:return
	cart_roll.volume_db=Music.to_db(gain)
	cart_roll.pitch_scale=CART_ROLL_SECONDS/seconds
	cart_roll.play()

func defer_action(kind:String)->void:
	if kind in WORLD_CUES:
		cancel_pending_action()
	elif pending_action in WORLD_CUES:
		return
	if cue_gain(kind)<=0.0 or Time.get_ticks_msec()-last_fishing_cue<FISHING_HOLDOFF_MS:return
	pending_action=kind
	action_due_at=Time.get_ticks_msec()+ACTION_DELAY_MS
	set_process(true)

func _process(_delta:float)->void:
	if Time.get_ticks_msec()<action_due_at:return
	var kind:=pending_action
	cancel_pending_action()
	if not kind.is_empty():play_cue(kind)

func cancel_pending_action()->void:
	pending_action=""
	set_process(false)

func close() -> void:
	if music:music.stop()
	stop_ambience()
	stop_machine()
	stop_cues()

func stop_cues() -> void:
	cancel_pending_action()
	last_cue=-1000
	last_fishing_cue=-1000
	nearby_region=""
	if nearby:nearby.stop()
	if cart_roll:cart_roll.stop()
	if player:
		player.stop()
		player.stream=null

func _exit_tree() -> void:close()

func load_preferences(path:String) -> bool:
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return false
	var amount=config.get_value("comfort","volume",0.45)
	if (amount is float or amount is int) and is_finite(float(amount)) and float(amount)>=0.0 and float(amount)<=1.0:volume=float(amount)
	var music_amount=config.get_value("comfort","music_volume",0.0 if volume==0.0 else 0.35)
	if (music_amount is float or music_amount is int) and is_finite(float(music_amount)) and float(music_amount)>=0.0 and float(music_amount)<=1.0:music_volume=float(music_amount)
	master_volume=read_gain(config,"master_volume",1.0)
	interface_volume=read_gain(config,"interface_volume",volume)
	ambience_volume=read_gain(config,"ambience_volume",0.0 if volume==0.0 and music_volume==0.0 else 0.25)
	activity_captions=config.get_value("comfort","activity_captions",true)!=false
	refresh_gains()
	var motion=config.get_value("comfort","reduced_motion",false)
	reduced_motion=motion if motion is bool else true
	forest_tools=config.get_value("comfort","forest_tools",false)==true
	standard_fishing=config.get_value("comfort","standard_fishing",false)==true
	var zoom=config.get_value("comfort","zoom",2)
	if (zoom is int or zoom is float) and zoom in [1,2]:preferred_zoom=int(zoom)
	var text_scale=config.get_value("comfort","text_scale",1)
	if (text_scale is int or text_scale is float) and int(text_scale) in range(4):preferred_text_scale=int(text_scale)
	fixed_area_camera=config.get_value("comfort","fixed_area_camera",false)==true
	return true

static func read_gain(config:ConfigFile,key:String,fallback:float) -> float:
	var value:Variant=config.get_value("comfort",key,fallback)
	return float(value) if valid_gain(value) else fallback

static func valid_gain(value:Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=1.0

func save_preferences(path:String,amount:float,motion:bool,zoom:int,use_forest:Variant=null,track_fish:Variant=null,text_scale:Variant=null,music_amount:Variant=null,levels:Dictionary={},camera_mode:Variant=null) -> bool:
	if camera_mode!=null and not camera_mode is bool:return false
	var chosen_camera:bool=fixed_area_camera if camera_mode==null else camera_mode
	if music_amount!=null and not (music_amount is float or music_amount is int):return false
	var chosen_music:=music_volume if music_amount==null else float(music_amount)
	if not is_finite(chosen_music) or chosen_music<0.0 or chosen_music>1.0:return false
	var chosen_text_scale:int=preferred_text_scale if text_scale==null else int(text_scale)
	if not is_finite(amount) or amount<0.0 or amount>1.0 or zoom not in [1,2] or chosen_text_scale not in range(4):return false
	var new_master:Variant=levels.get("master_volume",master_volume)
	var new_ambience:Variant=levels.get("ambience_volume",ambience_volume)
	var new_interface:Variant=levels.get("interface_volume",amount if levels.is_empty() else interface_volume)
	if not valid_gain(new_master) or not valid_gain(new_ambience) or not valid_gain(new_interface):return false
	var captions:Variant=levels.get("activity_captions",activity_captions)
	if not captions is bool:return false
	var config:=ConfigFile.new()
	config.set_value("comfort","volume",amount)
	config.set_value("comfort","music_volume",chosen_music)
	config.set_value("comfort","master_volume",new_master)
	config.set_value("comfort","ambience_volume",new_ambience)
	config.set_value("comfort","interface_volume",new_interface)
	config.set_value("comfort","activity_captions",captions)
	config.set_value("comfort","reduced_motion",motion)
	config.set_value("comfort","zoom",zoom)
	var chosen:bool=forest_tools if use_forest==null else use_forest==true
	config.set_value("comfort","forest_tools",chosen)
	var fishing:bool=standard_fishing if track_fish==null else track_fish==true
	config.set_value("comfort","standard_fishing",fishing)
	config.set_value("comfort","text_scale",chosen_text_scale)
	config.set_value("comfort","fixed_area_camera",chosen_camera)
	if config.save(path)!=OK:return false
	music_volume=chosen_music
	master_volume=float(new_master)
	ambience_volume=float(new_ambience)
	interface_volume=float(new_interface)
	activity_captions=captions
	volume=amount;reduced_motion=motion;preferred_zoom=zoom
	forest_tools=chosen
	standard_fishing=fishing
	preferred_text_scale=chosen_text_scale
	fixed_area_camera=chosen_camera
	if cue_gain(pending_action)==0.0:
		cancel_pending_action()
	refresh_gains()
	return true
