extends Node

# Original, synthesized cues: no downloaded recordings or external audio assets.
# One voice and a short debounce keep simultaneous actions from stacking loudly.
const RATE:=22050
const FISHING_CUES:=["fish_cast","fish_bite","fish_catch"]
const ACTION_DELAY_MS:=120
const FISHING_HOLDOFF_MS:=220
var volume:=0.45
var reduced_motion:=true
var preferred_zoom:=2
var forest_tools:=false
var standard_fishing:=false
var preferred_text_scale:=1
var player:AudioStreamPlayer
var sounds:Dictionary={}
var last_cue:=-1000
var last_fishing_cue:=-1000
var pending_action:=""
var action_due_at:=0

func _ready() -> void:
	player=AudioStreamPlayer.new()
	add_child(player)
	for kind in ["action","reward","notice"]+FISHING_CUES:sounds[kind]=make_cue(kind)
	set_process(false)

static func make_cue(kind:String) -> AudioStreamWAV:
	var duration:=0.24 if kind=="reward" else 0.10
	if kind in FISHING_CUES:duration=float({"fish_cast":0.18,"fish_bite":0.24,"fish_catch":0.30}[kind])
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
			"fish_cast":
				wave=sin(TAU*(310.0*t-510.0*t*t))*0.11+sin(TAU*(710.0*t-1030.0*t*t))*0.022
			"fish_bite":
				wave=note(t,698.46,0.11)+note(t-0.08,880.0,0.14)
				envelope=1.0
			"fish_catch":
				wave=note(t,523.25,0.13)+note(t-0.055,659.25,0.14)+note(t-0.11,783.99,0.19)
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
	if player==null or volume<=0.0:return false
	if not preview and not fishing:
		if player.playing and player.stream in [sounds.fish_cast,sounds.fish_bite,sounds.fish_catch]:return false
		if now-last_cue<120:return false
	last_cue=now
	player.stop()
	player.volume_db=linear_to_db(volume)
	player.stream=sounds.get(kind,sounds.action)
	player.play()
	return true

func defer_action(kind:String)->void:
	if volume<=0.0 or Time.get_ticks_msec()-last_fishing_cue<FISHING_HOLDOFF_MS:return
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
	cancel_pending_action()
	last_cue=-1000
	last_fishing_cue=-1000
	if player:
		player.stop()
		player.stream=null

func _exit_tree() -> void:close()

func load_preferences(path:String) -> bool:
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return false
	var amount=config.get_value("comfort","volume",0.45)
	if (amount is float or amount is int) and is_finite(float(amount)) and float(amount)>=0.0 and float(amount)<=1.0:volume=float(amount)
	var motion=config.get_value("comfort","reduced_motion",true)
	if motion is bool:reduced_motion=motion
	forest_tools=config.get_value("comfort","forest_tools",false)==true
	standard_fishing=config.get_value("comfort","standard_fishing",false)==true
	var zoom=config.get_value("comfort","zoom",2)
	if (zoom is int or zoom is float) and zoom in [1,2]:preferred_zoom=int(zoom)
	var text_scale=config.get_value("comfort","text_scale",1)
	if (text_scale is int or text_scale is float) and int(text_scale) in range(4):preferred_text_scale=int(text_scale)
	return true

func save_preferences(path:String,amount:float,motion:bool,zoom:int,use_forest:Variant=null,track_fish:Variant=null,text_scale:Variant=null) -> bool:
	var chosen_text_scale:int=preferred_text_scale if text_scale==null else int(text_scale)
	if not is_finite(amount) or amount<0.0 or amount>1.0 or zoom not in [1,2] or chosen_text_scale not in range(4):return false
	var config:=ConfigFile.new()
	config.set_value("comfort","volume",amount)
	config.set_value("comfort","reduced_motion",motion)
	config.set_value("comfort","zoom",zoom)
	var chosen:bool=forest_tools if use_forest==null else use_forest==true
	config.set_value("comfort","forest_tools",chosen)
	var fishing:bool=standard_fishing if track_fish==null else track_fish==true
	config.set_value("comfort","standard_fishing",fishing)
	config.set_value("comfort","text_scale",chosen_text_scale)
	if config.save(path)!=OK:return false
	volume=amount;reduced_motion=motion;preferred_zoom=zoom
	forest_tools=chosen
	standard_fishing=fishing
	preferred_text_scale=chosen_text_scale
	if volume==0.0:
		cancel_pending_action()
		if player:player.stop()
	return true
