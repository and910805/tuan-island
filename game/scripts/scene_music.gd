extends Node

const Market=preload("res://scripts/market_stall.gd")
const Transit=preload("res://scripts/transit.gd")
const COURTYARD_TRACK:="home_courtyard"
const SOUTH_SHORE_TRACK:="home_south_shore"
const STAR_SHORE_TRACK:="home_star_shore"
const TEA_HOUSE_TRACK:="maokong_tea_house"
const SALT_PAN_TRACK:="beimen_salt_pans"
const ZONE_TRACKS:=["home_forest","home_river","home_coast","home_market",COURTYARD_TRACK,SOUTH_SHORE_TRACK,STAR_SHORE_TRACK,TEA_HOUSE_TRACK,SALT_PAN_TRACK]
const SaltPan=preload("res://scripts/salt_pan.gd")
# Keep the connecting paths in the same music zone as the working pools.
const SALT_WORK_AREA:=Rect2(11.0,12.0,30.0,21.0)
const SALT_APPRENTICE_AREA:=Rect2(41.0,19.0,7.0,5.0)
const TeaHouse=preload("res://scripts/tea_revisit.gd")
const TEA_HOUSE_MUSIC_RADIUS:=2.5
const Springs=preload("res://scripts/warm_springs.gd")
const WanganCoast=preload("res://scripts/wangan_coast.gd")
const WanganMemory=preload("res://scripts/wangan_memory.gd")
const INN_TRACK:="warm_springs_interior"
const SETTING_TRACKS:=["house_interior","greenhouse_interior","island_voyage",INN_TRACK]
const MILESTONE_TRACKS:=["story_bridge","story_picnic","story_kitchen","story_hoist","story_boat"]
const ZONE_DWELL_SECONDS:=2.8
const FADE_SECONDS:=1.1
const BRIDGE_AND_RIVER:=Rect2(51.0,25.0,10.0,22.0)
const WEST_WOODS:=Rect2(15.0,15.0,15.0,30.0)
const SILENT_DB:=-80.0

var scene_id:=""
var volume:=0.35
var current:AudioStreamPlayer
var outgoing:AudioStreamPlayer
var fade:Tween
var blend:=1.0
var outgoing_gain:=0.0
var world_region:=""
var pending_track:=""
var pending_seconds:=0.0
var story_return_track:=""
var milestone_return_track:=""

static func track_for(region:String,world_time:float) -> String:
	if region=="home":
		var hour:=fposmod(world_time,1440.0)/60.0
		if hour<6.0 or hour>=19.0:return "home_night"
	return region

func _ready() -> void:
	current=make_player()
	outgoing=make_player()
	set_process(false)

func make_player() -> AudioStreamPlayer:
	var voice:=AudioStreamPlayer.new()
	add_child(voice)
	voice.volume_db=SILENT_DB
	voice.finished.connect(_finish_milestone.bind(voice))
	return voice

static func home_zone(snapshot:Dictionary,position:Vector2) -> String:
	var market:=Market.active_cell(snapshot)
	if market!=Market.NO_CELL and position.distance_squared_to(Vector2(market)+Vector2(0.5,0.5))<=9.0:
		return "home_market"
	if Rect2(WanganMemory.COURT).has_point(position) and WanganMemory.courtyard_available(snapshot):return COURTYARD_TRACK
	if WanganCoast.VISITOR_AREA.has_point(position):return SOUTH_SHORE_TRACK
	if snapshot.get("wangan_star_walk",false) and WanganCoast.star_shore(Vector2i(position.floor())):return STAR_SHORE_TRACK
	var pier:=Vector2(Transit.STATIONS.home.cell)+Vector2(0.5,0.5)
	if position.distance_squared_to(pier)<=7.5 or WanganCoast.ferry_walk(Vector2i(position.floor())):return "home_coast"
	if BRIDGE_AND_RIVER.has_point(position):return "home_river"
	if WEST_WOODS.has_point(position):return "home_forest"
	return ""

static func local_track(snapshot:Dictionary,region:String,person:Dictionary) -> String:
	if person.is_empty():return ""
	if region==Springs.REGION and Springs.in_inn(person):return INN_TRACK
	if person.get("at_sea",false):return "island_voyage"
	var position:=Vector2(float(person.x),float(person.y))
	var roof:Dictionary=snapshot.get("roofs",{}).get("%d,%d"%[floori(position.x),floori(position.y)],{})
	match roof.get("type",""):
		"roof":return "house_interior"
		"greenhouse_roof":return "greenhouse_interior"
	if region==TeaHouse.FILL_REGION and TeaHouse.house_open(snapshot):
		var table:=Vector2(TeaHouse.HOUSE_SITE)+Vector2(0.5,0.5)
		if position.distance_squared_to(table)<=TEA_HOUSE_MUSIC_RADIUS*TEA_HOUSE_MUSIC_RADIUS:return TEA_HOUSE_TRACK
	if region==SaltPan.REGION:
		if SALT_WORK_AREA.has_point(position) or SALT_APPRENTICE_AREA.has_point(position) or Rect2(SaltPan.HERITAGE_VIEW).has_point(position):
			return SALT_PAN_TRACK
	return home_zone(snapshot,position) if region=="home" else ""

func set_world(snapshot:Dictionary,own_id:String) -> void:
	if DisplayServer.get_name()=="headless" or not story_return_track.is_empty():return
	var region:=str(snapshot.get("region_id","home"))
	var base_track:=track_for(region,float(snapshot.get("time",0.0)))
	var person:Dictionary=snapshot.get("players",{}).get(own_id,{})
	var zone:=local_track(snapshot,region,person)
	var target:=base_track if zone.is_empty() else zone
	if region!=world_region:
		milestone_return_track=""
		world_region=region
		cancel_pending()
		set_scene(target)
		return
	if person.is_empty():return
	if target==INN_TRACK or scene_id==INN_TRACK:
		milestone_return_track=""
		cancel_pending()
		set_scene(target)
		return
	if not milestone_return_track.is_empty():
		if target!="island_voyage":
			milestone_return_track=target
			return
		milestone_return_track=""
	if (zone.is_empty() and scene_id not in ZONE_TRACKS and scene_id not in SETTING_TRACKS) or target=="island_voyage" or scene_id=="island_voyage":
		cancel_pending()
		set_scene(target)
		return
	if target==scene_id:
		cancel_pending()
	elif target!=pending_track:
		pending_track=target
		pending_seconds=ZONE_DWELL_SECONDS
		set_process(true)

func _process(delta:float) -> void:
	pending_seconds-=delta
	if pending_seconds>0.0:return
	var target:=pending_track
	cancel_pending()
	set_scene(target)

func cancel_pending() -> void:
	pending_track=""
	pending_seconds=0.0
	set_process(false)

func set_title() -> void:
	story_return_track=""
	milestone_return_track=""
	world_region=""
	cancel_pending()
	set_scene("title")

func set_epilogue(active:bool) -> void:
	if active:
		if scene_id.is_empty() or not story_return_track.is_empty():return
		story_return_track=scene_id if milestone_return_track.is_empty() else milestone_return_track
		milestone_return_track=""
		cancel_pending()
		set_scene("festival_epilogue")
	elif not story_return_track.is_empty():
		var previous:=story_return_track
		story_return_track=""
		set_scene(previous)

static func milestone_for(previous:Dictionary,snapshot:Dictionary) -> String:
	if previous.is_empty() or previous.get("region_id")!=snapshot.get("region_id"):return ""
	if int(previous.get("dock_stage",0))<2 and int(snapshot.get("dock_stage",0))>=2:return "story_boat"
	if not previous.get("mine_depths",{}).get("hoist",false) and snapshot.get("mine_depths",{}).get("hoist",false):return "story_hoist"
	if not previous.get("public_kitchen",{}).get("opened",false) and snapshot.get("public_kitchen",{}).get("opened",false):return "story_kitchen"
	if not previous.get("picnic",false) and snapshot.get("picnic",false):return "story_picnic"
	if not previous.get("board",false) and snapshot.get("board",false):return "story_bridge"
	return ""

func play_milestone(track:String) -> void:
	if scene_id.is_empty() or scene_id=="island_voyage" or not story_return_track.is_empty() or track not in MILESTONE_TRACKS:return
	if milestone_return_track.is_empty():milestone_return_track=scene_id
	cancel_pending()
	set_scene(track)

func _finish_milestone(voice:AudioStreamPlayer) -> void:
	if voice!=current or milestone_return_track.is_empty():return
	var target:=milestone_return_track
	milestone_return_track=""
	set_scene(target)

func set_scene(id:String) -> void:
	if scene_id==id or DisplayServer.get_name()=="headless":return
	var path:="res://assets/music/%s.ogg"%id
	if not ResourceLoader.exists(path):return
	var track:=load(path) as AudioStreamOggVorbis
	if track==null:return
	track.loop=id not in MILESTONE_TRACKS
	if fade!=null:fade.kill()
	var incoming_gain:=0.0
	var old_gain:=outgoing_gain
	var resume_outgoing:=outgoing.playing and outgoing.stream==track
	if resume_outgoing:
		incoming_gain=outgoing_gain
	# Reuse a returning track in place. Otherwise keep the louder recording.
	if resume_outgoing or not outgoing.playing or blend>=outgoing_gain:
		var old:=current
		old_gain=blend if current.playing else 0.0
		current=outgoing
		outgoing=old
	if not resume_outgoing:
		current.stop()
		current.stream=track
		current.volume_db=SILENT_DB
		current.play()
	scene_id=id
	blend=incoming_gain
	fade=create_tween()
	fade.tween_method(func(weight:float):
		blend=lerpf(incoming_gain,1.0,weight)
		apply_gain(old_gain*(1.0-weight)),0.0,1.0,FADE_SECONDS)
	fade.tween_callback(func():
		outgoing.stop()
		outgoing.stream=null)
	apply_gain(old_gain)

func set_volume(amount:float) -> void:
	volume=amount
	if current!=null:apply_gain(outgoing_gain)

func apply_gain(prior:float) -> void:
	outgoing_gain=prior
	current.volume_db=to_db(volume*sqrt(blend))
	outgoing.volume_db=to_db(volume*sqrt(prior))

static func to_db(gain:float) -> float:
	return SILENT_DB if gain<=0.0001 else linear_to_db(gain)

func stop() -> void:
	story_return_track=""
	milestone_return_track=""
	world_region=""
	cancel_pending()
	if fade!=null:fade.kill()
	if current!=null:
		for voice:AudioStreamPlayer in [current,outgoing]:
			voice.stop()
			voice.stream=null
			voice.volume_db=SILENT_DB
	scene_id=""
	blend=1.0
	outgoing_gain=0.0
