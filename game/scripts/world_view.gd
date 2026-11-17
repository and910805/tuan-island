extends Node2D
var player_emotes:Dictionary={}

const FurnitureArt=preload("res://scripts/furniture_sprite_art.gd")
const LivestockArt=preload("res://scripts/livestock_scene_art.gd")
var livestock_pet_feedback:Dictionary={}
const CookingFeedback=preload("res://scripts/cooking_feedback.gd")
const BoboArt=preload("res://scripts/bobo_art.gd")
const TransitArt=preload("res://scripts/transit_art.gd")
const StationLifeArt=preload("res://scripts/station_life_art.gd")
const ShippingArt=preload("res://scripts/shipping_art.gd")
const LanyangLifeArt=preload("res://scripts/lanyang_life_art.gd")
const MineArt=preload("res://scripts/mine_art.gd")
const TeaArt=preload("res://scripts/tea_ceramics_art.gd")
const TeaResidents=preload("res://scripts/tea_resident_art.gd")
const JinguashiArt=preload("res://scripts/jinguashi_art.gd")
const LanyangArt=preload("res://scripts/lanyang_art.gd")
const MemoryIcons=preload("res://assets/ui-life/icons.png")
const CommunityArt=preload("res://scripts/community_art.gd")
const CommunityFeedback=preload("res://scripts/community_feedback.gd")
const AutomationArt=preload("res://scripts/automation_art.gd")
const Industry=preload("res://scripts/industry.gd")
const IndustryArt=preload("res://scripts/industry_art.gd")
const WaterworksArt=preload("res://scripts/waterworks_art.gd")
const MineDrillArt=preload("res://scripts/mine_drill_art.gd")
const Forestry=preload("res://scripts/forestry.gd")
const ForestryUI=preload("res://scripts/forestry_ui.gd")
const ForestryArt=preload("res://scripts/forestry_art.gd")
const LogisticsArt=preload("res://scripts/logistics_art.gd")
const ProcessingQueueUI=preload("res://scripts/processing_queue_ui.gd")
const TillerArt=preload("res://scripts/tiller_art.gd")
const SeederArt=preload("res://scripts/seeder_art.gd")
const HarvesterArt=preload("res://scripts/harvester_art.gd")
const FarmFeedback=preload("res://scripts/farm_feedback.gd")
const ToolActionFeedback=preload("res://scripts/tool_action_feedback.gd")
const FishingFeedback=preload("res://scripts/fishing_feedback.gd")
const SheepShelter=preload("res://scripts/sheep_shelter.gd")
const FishingArt=preload("res://scripts/fishing_art.gd")
const BakeryArt=preload("res://scripts/bakery_art.gd")
const FEEDBACK_ICONS:={"radish":3,"lettuce":4,"wheat":5,"radish_seed":6,"lettuce_seed":7,"wheat_seed":8,
	"carrot":18,"potato":19,"tomato":20,"carrot_seed":21,"potato_seed":22,"tomato_seed":23}
const MACHINES:={"tiller":["till_area","last_till"],"seeder":["seed_area","last_seed"],"harvester":["harvest_area","last_harvest"]}
const World=preload("res://scripts/world.gd")
const TILE:=32.0
const DOCKED_BOAT:=Vector2(56.15,33.55)
const DOCK_LAUNCH_SECONDS:=2.0
const VOYAGE_ART=TransitArt.VOYAGE_ART
var dock_launch_started:=-INF
const Art=preload("res://scripts/world_pixel_art.gd")
const VillagePreview=preload("res://scripts/village_preview_art.gd")
const CharacterSprites=preload("res://scripts/character_sprite_art.gd")
const CropSprites=preload("res://scripts/crop_sprite_art.gd")
const RoofVisibility=preload("res://scripts/roof_visibility.gd")
const LabelLayout=preload("res://scripts/world_label_layout.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const FlowerWorldArt=preload("res://scripts/flower_world_art.gd")
const SaltWorldArt=preload("res://scripts/salt_world_art.gd")
const MarketStall=preload("res://scripts/market_stall.gd")
const MarketVisitors=preload("res://scripts/market_visitors.gd")
const MarketDisplay=preload("res://scripts/market_display.gd")
const FlowerSceneArt=preload("res://scripts/flower_scene_art.gd")
const MarketItemArt=preload("res://scripts/inventory_item_art.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const FishMeetUI=preload("res://scripts/fishing_meet_ui.gd")
const ShowcaseUI=preload("res://scripts/showcase_ui.gd")
const SouvenirUI=preload("res://scripts/souvenir_exchange_ui.gd")
const SouvenirArt=preload("res://scripts/souvenir_art.gd")
const KeepsakeArt=preload("res://scripts/resident_keepsake_art.gd")
const RevisitArt=preload("res://scripts/lanyang_revisit_art.gd")
const TowerArt=preload("res://scripts/water_tower_art.gd")
const JgArt=preload("res://scripts/jinguashi_revisit_art.gd")
const TeaRevisitArt=preload("res://scripts/tea_revisit_art.gd")
const SaltRevisitArt=preload("res://scripts/salt_revisit_art.gd")
const SaltBrineArt=preload("res://scripts/salt_brine_art.gd")
const GoldPanArt=preload("res://scripts/gold_panning_art.gd")
const OreRouteArt=preload("res://scripts/ore_route_art.gd")
const ORE_CART_TILES_PER_SECOND:=9.0
const RevisitUI=preload("res://scripts/lanyang_revisit_ui.gd")
const MemoryExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
var village_art_preview:=false
## T071 家園布置題：client-local selected prop (the page palette sets it; never sent until placing).
var showcase_kind:="flower_pot"
## T071 家園布置題：fade tree crowns over the sign / plot (tests turn it off for a before frame).
var showcase_fade_trees:=true
## While a chapter panel is open main.gd sets the focus prefix it owns (e.g.
## "salt:"); any other focused prompt is hidden. Empty = no filtering.
var hide_interaction_prompt:=false
var first_crop_cue_rect:=Rect2()
var village_art:RefCounted
var character_art:RefCounted
var crop_art:RefCounted
const STEP_LENGTH:=0.58
var data:Dictionary={}
var player_id:=""
var camera:=Vector2.ZERO
var camera_frame:=Vector3.ZERO
var fixed_area_camera:=false:
	set(value):
		if fixed_area_camera==value:return
		fixed_area_camera=value
		camera_frame=Vector3.ZERO
var target:=Vector2i.ZERO
var photograph_mode:=false
var show_target:=false
var placement_style:=""
var selected:="hoe"
var building:="floor"
var area_drag:=false
var area_start:=Vector2i.ZERO
var font:FontVariation
var elapsed:=0.0
var reduced_motion:=false
var label_text_scale:=1.0
var night_lamp_pool:GradientTexture2D
var zoom:=2.0
var display_positions:Dictionary={}
var starts:Dictionary={}
var goals:Dictionary={}
var interpolation_clock:=0.1
var facings:Dictionary={}
var gait:Dictionary={}
var walking:Dictionary={}
var stride_stop:Dictionary={}
var world_labels:Array[Dictionary]=[]
var character_label_obstacles:Array[Rect2]=[]
var focused_label:=""
var interaction_key_label:="E"
## Optional screen-pixel rects (before zoom) of visible HUD the focused label should avoid.
var label_avoid_rects:Array[Rect2]=[]
## Screen-pixel rects (before zoom) of opaque HUD cards that passive world labels
## must not peek out from under (only the 望安 arrival card sets this).
var label_hide_rects:Array[Rect2]=[]
var supply_networks:Dictionary={}
var tiller_world=World.new()
var seed_kind:="radish"
var farm_feedback:=FarmFeedback.new()
var tool_feedback:=ToolActionFeedback.new()
## T017 evidence counters, only ever incremented by the real draw path:
## held = held-tool icons drawn, particles = target particles drawn,
## lunge = held draws with a body lunge, angles = distinct held-tool angles.
var tool_draw_stats:={"held":0,"particles":0,"lunge":0,"angles":{}}
var fishing_feedback:=FishingFeedback.new()
var sheep_shelter:=SheepShelter.new()
var chicken_draw_stats:={"ground":0,"carried":0}
var sprinkler_sprays:Dictionary={}
var brine_transfer_started:=-INF
var brine_transfer_delta:=0
var ore_cart_push_started:=-INF
var community_feedback:=CommunityFeedback.new()
var mine_feedback:Dictionary={}
var freight_departure:=-10.0
var feedback_atlas:Texture2D

func harvester_preview(center:Vector2i) -> Dictionary:
	if data.is_empty():return {"cells":[],"skipped":{},"yields":{}}
	tiller_world.state=data
	tiller_world._region=region_id()
	return World.HARVESTER.plan(tiller_world,player_id,center)

func draw_farm_machine(kind:String,at:Vector2,facing:Vector2i,working:bool) -> void:
	match kind:
		"tiller":TillerArt.draw_machine(self,at,facing,elapsed,working,reduced_motion)
		"seeder":SeederArt.draw_machine(self,at,facing,elapsed,working,reduced_motion)
		"harvester":HarvesterArt.draw_machine(self,at,facing,elapsed,working,reduced_motion)

func seeder_preview(center:Vector2i) -> Dictionary:
	if data.is_empty():return {"cells":[],"eligible":[],"skipped":{}}
	tiller_world.state=data
	tiller_world._region=region_id()
	return World.SEEDER.plan(tiller_world,player_id,center,seed_kind)

func tiller_preview(center:Vector2i) -> Dictionary:
	if data.is_empty():return {"cells":[],"skipped":{}}
	tiller_world.state=data
	tiller_world._region=region_id()
	return World.TILLER.plan(tiller_world,player_id,center)

func tree_planting_preview(tile:Vector2i)->String:
	var person:Dictionary=data.get("players",{}).get(player_id,{})
	if person.is_empty():return ""
	if Vector2(person.x,person.y).distance_to(Vector2(tile)+Vector2(0.5,0.5))>3.2:
		return "靠近一點再種樹苗"
	tiller_world.state=data
	tiller_world._region=region_id()
	return tiller_world.tree_planting_problem(player_id,tile)

func update_snapshot(snapshot:Dictionary,id:String) -> Array:
	var changed_region:=region_id()!=str(snapshot.get("region_id","home"))
	var recenter_camera:=data.is_empty() or changed_region or id!=player_id or float(snapshot.get("time",0))<float(data.get("time",0))
	_observe_sprinklers(snapshot,recenter_camera)
	sheep_shelter.observe(snapshot,elapsed,recenter_camera)
	if recenter_camera or not World.TRANSIT.boat_open(snapshot):
		dock_launch_started=-INF
	elif not data.is_empty() and region_id()==World.REGIONS.HOME and not World.TRANSIT.boat_open(data):
		dock_launch_started=elapsed
	if changed_region or id!=player_id or float(snapshot.get("time",0))<float(data.get("time",0)):
		brine_transfer_started=-INF
	elif region_id()==World.SALT_BRINE.REGION:
		var difference:=World.SALT_BRINE.level(snapshot)-World.SALT_BRINE.level(data)
		if difference!=0:
			brine_transfer_started=elapsed
			brine_transfer_delta=difference
	if changed_region or id!=player_id or float(snapshot.get("time",0))<float(data.get("time",0)):
		ore_cart_push_started=-INF
	elif region_id()==World.ORE_ROUTE.REGION:
		var old_stage:=World.ORE_ROUTE.stage(data)
		var new_stage:=World.ORE_ROUTE.stage(snapshot)
		if new_stage!=old_stage:
			ore_cart_push_started=elapsed if old_stage>0 and new_stage==old_stage+1 else -INF
	if recenter_camera:livestock_pet_feedback.clear()
	if changed_region:
		farm_feedback.reset()
		community_feedback.reset()
		mine_feedback.clear()
		freight_departure=-10.0
		display_positions.clear()
		starts.clear()
		goals.clear()
		facings.clear()
		gait.clear()
		walking.clear()
		stride_stop.clear()
		show_target=false
		area_drag=false
	elif region_id().begins_with("mine_"):
		var previous:Dictionary=data.get("mine_depths",{}).get("ready",{}).get(region_id(),{})
		var latest:Dictionary=snapshot.get("mine_depths",{}).get("ready",{}).get(region_id(),{})
		for cell in latest:
			if float(latest[cell])>float(previous.get(cell,0)):mine_feedback[cell]=elapsed
		var previous_freight:String=data.get("mine_freight",{}).get("own_job",{}).get("status","")
		var latest_freight:String=snapshot.get("mine_freight",{}).get("own_job",{}).get("status","")
		if previous_freight=="draft" and latest_freight=="transit":freight_departure=elapsed
	if not recenter_camera and not data.is_empty() and str(snapshot.get("region_id","home"))=="home":
		var old_animals:Dictionary=data.get("livestock",{})
		var new_animals:Dictionary=snapshot.get("livestock",{})
		for animal_id:String in World.LIVESTOCK.ANIMALS:
			var last_pet:=float(new_animals.get(animal_id,{}).get("last_pet",-1))
			var previous_pet:=float(old_animals.get(animal_id,{}).get("last_pet",-1))
			if last_pet>previous_pet and float(snapshot.get("time",0))-last_pet<=LivestockArt.PET_SECONDS:
				livestock_pet_feedback[animal_id]=elapsed
			if animal_id in ["cow","duck"] and int(new_animals.get(animal_id,{}).get("feed",0))>int(old_animals.get(animal_id,{}).get("feed",0)):
				livestock_pet_feedback[animal_id]=elapsed
	farm_feedback.observe(data,snapshot,elapsed)
	var fresh_tools:=tool_feedback.observe(data,snapshot,id,elapsed)
	for actor in fresh_tools:
		var action:=tool_feedback.active(actor,elapsed)
		if action.get("tool","")=="seed":
			farm_feedback.mark_sprout(World.key(action.cell),data,snapshot,elapsed)
	community_feedback.observe(data,snapshot,elapsed)
	fishing_feedback.update(snapshot,id,elapsed)
	data=snapshot
	player_id=id
	supply_networks=Industry.networks(snapshot)
	interpolation_clock=0.0
	for who in data.players:
		var p:Dictionary=data.players[who]
		var goal:=Vector2(p.x,p.y)
		var current:Vector2=display_positions.get(who,goal)
		var jumped:=current.distance_to(goal)>4.0
		if jumped and who==id:recenter_camera=true
		if p.has(World.REGIONS.Springs.REST_SEAT_KEY) or jumped:
			current=goal
			gait.erase(who)
			stride_stop.erase(who)
		starts[who]=current
		goals[who]=goal
		display_positions[who]=current
	if recenter_camera and display_positions.has(id) and is_inside_tree():update_camera(display_positions[id],true)
	for who in display_positions.keys():
		if not data.players.has(who):
			display_positions.erase(who)
			starts.erase(who)
			goals.erase(who)
			facings.erase(who)
			gait.erase(who)
			walking.erase(who)
			stride_stop.erase(who)
	return fresh_tools

func _observe_sprinklers(snapshot:Dictionary,reset:bool) -> void:
	if reset or data.is_empty():
		sprinkler_sprays.clear()
		return
	var previous:Dictionary=data.get("objects",{})
	var latest:Dictionary=snapshot.get("objects",{})
	for key in sprinkler_sprays.keys():
		if not latest.has(key) or elapsed-float(sprinkler_sprays[key])>=AutomationArt.SPRAY_DURATION:
			sprinkler_sprays.erase(key)
	for key in latest:
		var device:Dictionary=latest[key]
		if not Industry.SPRINKLER_CAPACITIES.has(device.get("type","")):continue
		var old:Dictionary=previous.get(key,{})
		var watered_at:=float(device.get("last_water",-1.0))
		if watered_at>=0.0 and watered_at>float(old.get("last_water",-1.0)):
			sprinkler_sprays[key]=elapsed

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if village_art_preview:
		village_art=VillagePreview.new()
		village_art.setup()
		character_art=CharacterSprites.new()
		if not character_art.setup():character_art=null
		crop_art=CropSprites.new()
		if not crop_art.setup():crop_art=null
	feedback_atlas=load("res://assets/ui-inventory/items.png") as Texture2D
	font=preload("res://scripts/island_type.gd").regular()

func _process(dt:float) -> void:
	elapsed+=dt
	interpolation_clock=minf(interpolation_clock+dt,0.1)
	for who in display_positions:
		var previous:Vector2=display_positions[who]
		var next:=Vector2(starts[who]).lerp(Vector2(goals[who]),interpolation_clock/0.1)
		var travel:=next-previous
		display_positions[who]=next
		if travel.length_squared()>0.00000001:
			var facing:Vector2i=facings.get(who,Vector2i.DOWN)
			# Keep the previous axis on diagonals so minor rounding cannot flip the pose.
			if absf(travel.x)>absf(travel.y)*1.08 or (facing.x!=0 and absf(travel.x)*1.08>=absf(travel.y)):
				facings[who]=Vector2i(int(signf(travel.x)),0)
			else:
				facings[who]=Vector2i(0,int(signf(travel.y)))
			var step_distance:=1.8 if character_art else STEP_LENGTH
			gait[who]=fposmod(float(gait.get(who,0.0))+travel.length()*TAU/step_distance,TAU)
			stride_stop[who]=elapsed+0.075
		walking[who]=elapsed<float(stride_stop.get(who,0.0))
		if not walking[who]:gait[who]=0.0
	if data.has("players") and data.players.has(player_id):
		var p:Dictionary=data.players[player_id]
		var visual_position:Vector2=display_positions.get(player_id,Vector2(p.x,p.y))
		update_camera(visual_position)
	queue_redraw()

func update_camera(position:Vector2,recenter:bool=false) -> void:
	var extent:=get_viewport_rect().size
	var scale_value:=view_zoom()
	var frame:=Vector3(extent.x,extent.y,scale_value)
	var anchor:=extent*0.5+Vector2(0,40) if village_art_preview else Vector2(740,460)
	var centered:=position*TILE-anchor/scale_value
	if recenter or not fixed_area_camera or camera_frame!=frame:
		camera=centered.round()
	else:
		var margin:=Vector2(minf(extent.x*0.10,112.0),minf(extent.y*0.09,72.0))/scale_value
		camera=camera.clamp((centered-margin).ceil(),(centered+margin).floor())
	camera_frame=frame

func to_cell(screen:Vector2) -> Vector2i:
	return Vector2i(((screen/view_zoom()+camera)/TILE).floor())

func view_zoom() -> float:
	return 1.0 if region_id().begins_with("mine_") else zoom

func draw_cell(at:Vector2) -> Vector2i:
	return Vector2i(((at+camera)/TILE).floor())

func screen(p:Vector2) -> Vector2:
	return p*TILE-camera

func region_id() -> String:
	return str(data.get("region_id","home"))

func ore_cart_travel_seconds(stage:int) -> float:
	var track:=World.ORE_ROUTE.TRACK
	return float(track.find(World.ORE_ROUTE.cart_cell(stage))-track.find(World.ORE_ROUTE.cart_cell(stage-1)))/ORE_CART_TILES_PER_SECOND

func ore_cart_push_pose(stage:int,position:Vector2) -> Dictionary:
	var age:=elapsed-ore_cart_push_started
	if reduced_motion or stage<2 or not is_finite(age) or age<0.0:return {}
	var duration:=ore_cart_travel_seconds(stage)
	if age>=duration:return {}
	var origin:=World.ORE_ROUTE.cart_cell(stage-1)
	var track:=World.ORE_ROUTE.TRACK
	var first_step:Vector2i=track[track.find(origin)+1]-origin
	var facing:=ToolActionFeedback.facing_toward(position,origin,first_step)
	var progress:=age/duration
	return {"facing":facing,"lean":roundf(sin(PI*pow(progress,0.55))*5.0)}

func ore_cart_position(stage:int) -> Vector2:
	var destination:=World.ORE_ROUTE.cart_cell(stage)
	var destination_index:=World.ORE_ROUTE.TRACK.find(destination)
	var travel:=(elapsed-ore_cart_push_started)*ORE_CART_TILES_PER_SECOND
	if reduced_motion or stage<2 or not is_finite(travel):return Vector2(destination)
	var origin_index:=World.ORE_ROUTE.TRACK.find(World.ORE_ROUTE.cart_cell(stage-1))
	var index:=float(origin_index)+maxf(0.0,travel)
	if index>=destination_index:return Vector2(destination)
	var step:=floori(index)
	return Vector2(World.ORE_ROUTE.TRACK[step]).lerp(Vector2(World.ORE_ROUTE.TRACK[step+1]),index-step)

func _draw() -> void:
	chicken_draw_stats={"ground":0,"carried":0}
	if data.is_empty():return
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*view_zoom())
	world_labels.clear()
	character_label_obstacles.clear()
	focused_label="" if hide_interaction_prompt else interaction_focus()
	var size:=get_viewport_rect().size/view_zoom()
	var home:=region_id()==World.REGIONS.HOME
	var deer_site:=World.Deer.site(data) if home and World.Deer.present(data) else Vector2i(-1,-1)
	var courtyard:=home and World.WANGAN_MEMORY.courtyard_available(data)
	var mining:=region_id()=="jinguashi"
	var transit:=TransitArt.NAMES.has(region_id())
	var tea_region:=region_id() in ["maokong","yingge"]
	var flower_region:=region_id()==World.FLOWER_NURSERY.REGION
	var salt_region:=region_id()==World.SALT_PAN.REGION
	var tea_sites:=tea_points(region_id(),data)
	var tea_record:Dictionary=data.get("tea_ceramics",{}).get("own_record",{}) if tea_region else {}
	var resident_at_station:Dictionary=World.STATION_LIFE.RESIDENTS.get(region_id(),{})
	var station_repaired:bool=data.get("station_life",{}).get("repairs",{}).get(region_id(),false)
	var bobo_sites:Dictionary=World.Village.Workshop.sites(data) if mining else {}
	var depth:=int(region_id().trim_prefix("mine_")) if region_id().begins_with("mine_") else 0
	var survey_cell:Vector2i=World.MINE_SURVEY.POINTS.get(depth,Vector2i(-1,-1))
	var placing_drill:=show_target and selected=="build" and building=="mine_drill" and depth>0
	var festival:Dictionary=data.get("festival",{})
	var bell_cell:=World.Festival.target(festival) if home and festival.get("active",false) else Vector2i(-1000,-1000)
	var from:=Vector2i((camera/TILE).floor())-Vector2i(2,2)
	var to:=from+Vector2i(ceili(size.x/TILE)+5,ceili(size.y/TILE)+6)
	var springs:=World.WARM_SPRINGS
	var in_springs:=region_id()==springs.REGION
	var in_inn:=in_springs and springs.in_inn(data.players.get(player_id,{}))
	draw_rect(Rect2(Vector2.ZERO,size),Color("74b8b0"))
	for y in range(from.y,to.y):
		for x in range(from.x,to.x):
			var p:=Vector2i(x,y)
			var at:=screen(Vector2(p))
			var k:=World.key(p)
			if in_springs:
				if in_inn:
					if springs.INN_ROOM.has_point(p):ground_tile(at,"floor","tea_house")
					else:draw_rect(Rect2(at,Vector2(32,32)),Color("241e1b"))
				else:springs.ground(self,at,p)
				continue
			if region_id()==World.REGIONS.StarGarden.REGION:
				World.REGIONS.StarGarden.ground(self,at,p)
				continue
			if region_id()==World.REGIONS.Bamboo.REGION:
				World.REGIONS.Bamboo.ground(self,at,p)
				if data.crops.has(k):crop_tile(at,data.crops[k])
				continue
			if flower_region:
				var flower_land:=World.land(p,region_id())
				FlowerWorldArt.ground(self,at,p,flower_land)
				if flower_land:
					if data.ground.has(k):ground_tile(at,data.ground[k].type,str(data.ground[k].get("style","")))
					if data.crops.has(k):crop_tile(at,data.crops[k])
				continue
			if salt_region:
				SaltWorldArt.ground(self,at,p,data,elapsed,reduced_motion)
				if World.land(p,region_id()) and not World.SALT_PAN.blocked(p):
					if data.ground.has(k):ground_tile(at,data.ground[k].type,str(data.ground[k].get("style","")))
					if data.crops.has(k):crop_tile(at,data.crops[k])
				continue
			if not home:
				var outer_wet:=not World.land(p,region_id()) if mining or depth>0 or transit or tea_region else World.REGIONS.water(p)
				if tea_region:
					TeaArt.ground(self,at,p,region_id(),not outer_wet)
					continue
				elif transit:
					TransitArt.ground(self,at,p,region_id(),not outer_wet)
					continue
				if depth>0:
					if depth==3 and World.MINES.POOL.has_point(p):MineArt.draw_pool(self,at)
					else:
						MineArt.ground(self,at,p,not outer_wet,depth)
						if not outer_wet:MineArt.draw_track(self,at,p,depth)
				elif mining:JinguashiArt.draw_ground(self,at,p,not outer_wet)
				else:LanyangArt.draw_ground(self,at,p,outer_wet)
				if not outer_wet:
					if data.ground.has(k):ground_tile(at,data.ground[k].type,str(data.ground[k].get("style","")))
					if data.crops.has(k):crop_tile(at,data.crops[k])
				continue
			var wet:bool=not World.land(p) or ((x==55 or x==56) and not (data.board and y>=29 and y<=31))
			if village_art and VillagePreview.contains(p):
				village_art.draw_ground(self,at,p,data)
				if not wet:
					if data.ground.has(k):ground_tile(at,data.ground[k].type,str(data.ground[k].get("style","")))
					if data.crops.has(k):crop_tile(at,data.crops[k])
				continue
			if wet:
				water_tile(at,p)
				continue
			var hash_value:=absi(x*7127+y*19391)
			var color:=Color("a8c88b") if hash_value%3==0 else Color("acce8d")
			draw_rect(Rect2(at,Vector2(32,32)),color)
			if hash_value%5==0:
				draw_rect(Rect2(at+Vector2(6,10),Vector2(3,5)),Color("8db476"))
				draw_rect(Rect2(at+Vector2(10,8),Vector2(3,7)),Color("8db476"))
			if hash_value%29==0:flower(at+Vector2(19,13),Color("faf1b4"))
			if (y>=29 and y<=31 and x>=35 and x<=54) or (x>=39 and x<=41 and y>=28 and y<=37):
				draw_rect(Rect2(at,Vector2(32,32)),Color("d9c798"))
				if hash_value%3==0:draw_rect(Rect2(at+Vector2(8,12),Vector2(7,3)),Color("c5b181"))
			if x in [55,56] and data.board:
				draw_rect(Rect2(at,Vector2(32,32)),Color("99744c"))
				for j in range(4):draw_rect(Rect2(at+Vector2(1,j*8),Vector2(30,6)),Color("cfaa70"))
			if data.ground.has(k):ground_tile(at,data.ground[k].type,str(data.ground[k].get("style","")))
			if data.crops.has(k):crop_tile(at,data.crops[k])
	if depth>0:MineArt.draw_perimeter(self,screen(Vector2.ZERO),depth,elapsed,reduced_motion)
	if courtyard:
		var court:Rect2i=World.WANGAN_MEMORY.COURT
		for y in range(court.position.y,court.end.y):
			for x in range(court.position.x,court.end.x):
				ground_tile(screen(Vector2(x,y)),"spring_pebble_path")
	if home:
		var coast:=World.WANGAN_COAST
		var pool_at:=screen(Vector2(coast.STAR_POOL.position))
		if Rect2(Vector2.ZERO,size).intersects(Rect2(pool_at-Vector2(8,6),Vector2(80,44))):
			coast.draw_star_pool(self,pool_at,float(data.get("time",0.0)),elapsed,reduced_motion)
			if selected=="fish" and data.get("wangan_star_walk",false):
				world_label(pool_at+Vector2(32,-16),"星砂潮池・金邊蝦","star_tidepool")
		var anchor:=screen(coast.WEIR_AT)
		if Rect2(Vector2.ZERO,size).intersects(Rect2(anchor,coast.WEIR_SIZE)):
			coast.draw_weir(self,anchor,float(data.get("time",0.0)),elapsed,reduced_motion)
	if salt_region:draw_salt_pans()
	if not in_inn and depth==0:draw_night_ground(size,from,to)
	if home and data.get("picnic",false):
		var a:=screen(Vector2(39,28))
		var b:=screen(Vector2(45,28))
		draw_line(a,b,Color("e8d1a1"),2)
		for j in range(9):
			var flag:=a+Vector2(j*22+3,0)
			draw_colored_polygon(PackedVector2Array([flag,flag+Vector2(14,0),flag+Vector2(7,14)]),Color("d59d83") if j%2==0 else Color("87afa0"))
	var shipping_cell:=World.SHIPPING.cell_for(data) if home else Vector2i(-1,-1)
	var table_cell:=World.COMMUNITY.table_cell(data) if home else Vector2i(-1,-1)
	var market_cell:=MarketStall.active_cell(data) if home else MarketStall.NO_CELL
	var guests_today:Array=market_guests()
	var voyage_passengers:Dictionary={}
	for id:String in data.players:
		var skipper:String=data.players[id].get("voyage_captain","")
		if not skipper.is_empty() and data.players.get(skipper,{}).get("at_sea",false):voyage_passengers[skipper]=id
	var harvest_on:=home and HarvestUI.on_field(data)
	# T071 河岸釣魚會：進行中時用繩索與浮標標出指定水域（地面層之上、人物之下）。
	var fishmeet_on:=home and FishMeetUI.on_field(data)
	if fishmeet_on and FishMeetUI.waters_marked(data):FishMeetUI.draw_waters(self,elapsed,reduced_motion)
	# T071 家園布置題：解鎖後在地面層標出臨時展示地塊（靜態）；道具與告示牌在下面的列排序裡畫。
	var showcase_plot:=home and ShowcaseUI.plot_shown(data)
	var showcase_sign:=home and ShowcaseUI.sign_shown(data)
	var showcase_target:=ShowcaseUI.view_target(self) if focused_label==ShowcaseUI.PLOT_POINT else ShowcaseUI.NO_CELL
	if home:draw_hedgehog_site()
	if showcase_plot:ShowcaseUI.draw_plot(self,data,showcase_target)
	# T071 紀念品交換攤：渡口野餐後、使用中的攤位格（暫停時不畫）。
	var souvenir_cell:=SouvenirUI.booth_cell(data) if home else SouvenirUI.NO_CELL
	# 第 40 章風鈴節廣場地方記憶展：風鈴節開幕後、使用中的展台格（暫停時不畫）。
	var exhibit_cell:=MemoryExhibitUI.stand_cell(data) if home else MemoryExhibitUI.NO_CELL
	# 望安開場：小栗留的田（木樁、麻繩與名牌），只給還在第一株作物步驟的本人看；
	# 地面層之上、道具與人物之下，首次出貨後消失。
	var first_crop:=World.CHAPTER_ONE.first_crop_step(data,player_id) if home else {}
	first_crop_cue_rect=WanganUI.draw_plot(self,data,player_id,first_crop) if home else Rect2()
	draw_fox_clues()
	var exit_cell:=World.REGIONS.exit_cell(region_id())
	if transit or tea_region:
		if tea_region:TeaArt.draw_backdrop(self,screen(Vector2.ZERO),region_id())
		else:TransitArt.draw_landmarks(self,camera,region_id())
		var transit_points:Dictionary=World.TRANSIT.points(region_id())
		for gate in transit_points:
			var stop:Dictionary=transit_points[gate]
			var at:=screen(Vector2(stop.cell))
			if not lanyang_cell_occupied(stop.cell):FurnitureArt.draw_sprite(self,at,"sign")
			if focused_label=="transit:"+str(gate):
				world_label(at+Vector2(16,26),stop.label,"transit:"+str(gate))
	var lanyang_life:Dictionary=data.get("lanyang_life",{})
	var garden_pots:Array=data.get(World.RESIDENT_GOALS.GARDEN_KEY,[])
	var cart_stage:=World.ORE_ROUTE.stage(data) if mining else 0
	var cart_position:=ore_cart_position(cart_stage) if mining else Vector2.ZERO
	var gardener_cell:=lanyang_gardener_cell() if region_id()==World.REGIONS.LANYANG else Vector2i(-1,-1)
	var rest_choice:=str(data.players.get(player_id,{}).get(springs.REST_SEAT_KEY,""))
	var rest_cell:Vector2i=springs.REST_SEATS.get(rest_choice,Vector2i(-1,-1))
	if in_inn:
		var runner:=Rect2(screen(Vector2(65.15,22.0)),Vector2(22,154))
		draw_rect(runner,Color("4d7667"))
		draw_rect(runner.grow(-3),Color("d0ab73"),false,1.0)
		for mark in range(5):
			var at:=runner.position+Vector2(11,14+32*mark)
			draw_colored_polygon(PackedVector2Array([at-Vector2(0,5),at+Vector2(5,0),at+Vector2(0,5),at-Vector2(5,0)]),Color("bd8d59"))
	# Draw all tall props and people in row order, keeping feet as sorting origin.
	for y in range(from.y,to.y):
		for x in range(from.x,to.x):
			var p:=Vector2i(x,y)
			var at:=screen(Vector2(p))
			var k:=World.key(p)
			if tea_region:
				if region_id()=="maokong" and p==World.TEA_REVISIT.HOUSE_SITE and World.TEA_REVISIT.house_open(data):
					FurnitureArt.draw_sprite(self,at,"table")
					var cups:=World.TEA_SERVICE.portions(data,World.TEA_REVISIT.HOUSE_KEY)
					if data.get(World.TEA_REVISIT.HOUSE_KEY,{}).get("occupied",false):
						TeaRevisitArt.draw_teaware(self,at+Vector2(0,-10))
						if cups>0:TeaRevisitArt.draw_steam(self,at+Vector2(21,-1),elapsed,reduced_motion)
					if focused_label=="tea:house":
						var title:="茶屋・熱茶剩 %d 杯"%cups if cups>0 else "茶屋展示桌"
						world_label(at+Vector2(28,2),title,"tea:house",true)
					continue
				for choice:String in data.get("chacha_tea_chairs",{}):
					var seat:Dictionary=World.RESIDENT_GOALS.TEA_CHAIRS[choice]
					if seat.cell==p:FurnitureArt.draw_sprite(self,at,"chair",seat.tint)
				if not tea_sites.has(p):continue
				var site:String=tea_sites[p]
				if site in ["host","potter"]:
					TeaResidents.draw_resident(self,at+Vector2(16,25),site)
				else:
					TeaArt.draw_site(self,at,"pick" if site.begins_with("pick:") else site)
					TeaArt.draw_feedback(self,at,site,tea_record,float(data.time),elapsed,reduced_motion)
				var id:="tea:"+site
				if id==focused_label or site in ["host","potter","roast","pack","kiln"]:
					world_label(at+Vector2(16,-25 if site in ["host","potter"] else -17),tea_site_label(site),id)
				continue
			if flower_region:
				if x==from.x:draw_flower_row(y)
				if data.objects.has(k):object_sprite(at,data.objects[k].type,data.objects[k])
				continue
			if salt_region:
				if x==from.x:draw_salt_row(y)
				if data.objects.has(k):object_sprite(at,data.objects[k].type,data.objects[k])
				continue
			if transit:
				TransitArt.roadside(self,at,p,region_id(),village_art)
				if p==StationLifeArt.CORNERS[region_id()] and not lanyang_cell_occupied(p):
					StationLifeArt.draw_corner(self,at,station_repaired)
				continue
			if data.get("forest",{}).has(k):
				var planted:Dictionary=data.forest[k]
				if planted.mature:
					tree(at)
					if show_target and p==target and selected=="axe":world_label(at+Vector2(16,-36),"栽培成樹 · 可採硬木","")
				else:sapling(at,float(planted.growth)/World.TREE_TIME)
			elif not data.removed.has(k):
				var resource:String=World.base_resource(p,region_id())
				if resource=="tree":tree(at)
				elif resource=="rock":rock(at)
				elif resource=="grass":grass(at)
			if not data.get("forest",{}).has(k) and not data.objects.has(k) and not data.crops.has(k):
				draw_resource_finish(at,p)
			if data.objects.has(k):object_sprite(at,data.objects[k].type,data.objects[k])
			if depth==0 and p==exit_cell and (not home or data.get("picnic",false)):
				if not data.objects.has(k) and not data.crops.has(k) and not data.get("forest",{}).has(k) and not data.ground.has(k) and not data.get("roofs",{}).has(k):LanyangArt.draw_exit(self,at)
				var gate:=World.TRANSIT.point_at(region_id(),p)
				var caption:String=World.TRANSIT.points(region_id())[gate].label if not gate.is_empty() else "回風鈴渡口"
				if home and gate=="ferry" and int(data.get("dock_stage",0))>0:
					caption="合作小船" if World.TRANSIT.boat_open(data) else "碼頭已修復"
				world_label(at+Vector2(16,-18),caption,"transit:"+gate if not gate.is_empty() else "travel")
			if depth>0:
				if p==survey_cell and not lanyang_cell_occupied(p):
					draw_texture_rect_region(MemoryIcons,Rect2(at,Vector2(32,32)),Rect2(32,96,32,32))
					if focused_label=="mine_survey":world_label(at+Vector2(16,-14),"側洞觀察","mine_survey")
				var places:Dictionary={World.MINES.UP:[1,"上一層","up"],World.MINES.REST:[2,"休息補水","rest"],World.MINES.SERVICE:[3,"礦務工程","service"]}
				if depth<World.MINES.MAX_DEPTH:places[World.MINES.DOWN]=[0,"往下一層","down"]
				if depth>World.MINES.SHALLOW_DEPTH:places[World.MINES.LIFT]=[-1,"升降台","lift"]
				if places.has(p):
					var info:Array=places[p]
					var freight_station:=p==World.MINES.SERVICE and depth in [4,5] and int(data.get("mine_depths",{}).get("unlocked",1))>=5
					var occupied:bool=data.objects.has(k) or data.crops.has(k) or data.get("forest",{}).has(k) or data.get("roofs",{}).has(k)
					if not occupied:
						if freight_station:
							var job:Dictionary=data.get("mine_freight",{}).get("own_job",{})
							var loaded:bool=job.get("status","")=="draft" and not job.get("items",{}).is_empty()
							MineArt.draw_freight(self,at,"loaded" if loaded else "cart",elapsed-freight_departure,reduced_motion)
						elif info[0]<0:MineArt.draw_lift(self,at)
						else:MineArt.draw_prop(self,at,info[0])
						if depth==1 and p==World.MINES.REST:
							var fixtures:=int(data.get("bobo_rest_fixtures",0))
							if (fixtures&1)!=0:MineArt.draw_freight(self,at+Vector2(-14,0),"post",-1.0,reduced_motion,22)
							if (fixtures&2)!=0:MineArt.draw_freight(self,at+Vector2(22,10),"crate",-1.0,reduced_motion,22)
					world_label(at+Vector2(16,-18),"礦車裝載站" if freight_station else info[1],"mine_site:"+str(info[2]))
				if p in World.MINES.NODES:
					var mineral:String=World.MINES.ORES[depth-1]
					var available:=float(data.get("mine_depths",{}).get("ready",{}).get(region_id(),{}).get(k,0))<=float(data.time)
					match mineral:
						"gold_ore":MineArt.draw_prop(self,at,4)
						"copper_ore":AutomationArt.draw_copper(self,at,available)
						_:rock(at)
					var age:=elapsed-float(mine_feedback.get(k,-10.0))
					if age<0.7:MineArt.draw_strike(self,at,age,reduced_motion)
					if focused_label=="extract:"+k and not (placing_drill and p==World.MINE_DRILL.NODE):
						world_label(at+Vector2(16,-18),str(World.NAMES.get(mineral,"礦料")) if available else "礦點整理中","extract:"+k)
				if depth==1:
					var visitor:Dictionary=data.players.get(player_id,{})
					var phase:=int(visitor.get("mud_alcove",0))
					if phase==0 and p==World.MINES.MUD_GATE:
						var title:="小泥團 · 喜歡蘿蔔"
						var lunge:=0.0
						if data.get("world_mode")=="adventure":
							title="小泥團 · 可挑戰"
							var duel:Dictionary=visitor.get("mud_duel",{})
							var strike_at:=float(duel.get("strike_at",-100.0))
							if float(data.time)<strike_at:title="向左或向右閃避！"
							elif float(data.time)<strike_at+World.MINES.MUD_RECOVERY:
								title="現在反擊！" if duel.get("dodged",false) else "等小泥團停下再試"
								if not reduced_motion:
									var age:=float(data.time)-strike_at
									if age<0.45:lunge=roundf(sin(age/0.45*PI)*10.0)
						MineArt.draw_mudling(self,at+Vector2(-22,10+lunge),elapsed,reduced_motion)
						world_label(at+Vector2(16,-8),title,"mine_mud")
					elif phase>0 and p==World.MINES.MUD_GATE+Vector2i.DOWN:
						MineArt.draw_mudling(self,at+Vector2(10,-4),elapsed,reduced_motion)
					if phase==1 and p==World.MINES.MUD_REWARD:
						AutomationArt.draw_copper(self,at,true)
						world_label(at+Vector2(16,-8),"側洞銅礦料","mine_mud")
				continue
			if mining:
				# 先畫軌道與月台，此列的台車在人物之前繪製。
				if p in World.ORE_ROUTE.TRACK:
					if not lanyang_cell_occupied(p): # 舊存檔在軌道格上蓋了東西時不蓋過它（台車照畫）
						OreRouteArt.draw_track(self,at,p)
						if p==World.ORE_ROUTE.STOPS[0]:OreRouteArt.draw_platform(self,at,"load")
						elif p==World.ORE_ROUTE.STOPS[-1]:OreRouteArt.draw_platform(self,at,"unload")
				if p==JinguashiArt.ENTRANCE_ANCHOR:
					JinguashiArt.draw_entrance(self,at)
					if data.players.has(player_id):
						var visitor:Dictionary=data.players[player_id]
						if Vector2(visitor.x,visitor.y).distance_to(Vector2(p)+Vector2(0.5,1.5))<3.2:
							world_label(at+Vector2(16,-122),"合作礦場入口","mine_site:entry")
				if p==JinguashiArt.STATION and not lanyang_cell_occupied(p):
					JinguashiArt.draw_station(self,at,village_art)
				if p==bobo_sites.table:
					if not lanyang_cell_occupied(p):BoboArt.draw(self,at+Vector2(-8,-16),"table")
					if focused_label=="bobo_sort":world_label(at+Vector2(16,32),"礦樣整理桌","bobo_sort")
				if p in [Vector2i(19,17),Vector2i(23,17)] and not World.land(p,region_id()) and not lanyang_cell_occupied(p):
					BoboArt.draw(self,at+Vector2(-8,-16),"lantern")
				# 第 40 章河邊淘砂金：西岸外水面上的淘砂處（木棧板與淘砂盤），靠近時顯示名牌。
				if p==World.GOLD_PANNING.SITE:
					GoldPanArt.draw_site(self,at,elapsed,reduced_motion)
					if focused_label==GoldPanArt.POINT:world_label(at+Vector2(16,-18),World.GOLD_PANNING.SITE_NAME,GoldPanArt.POINT)
				if p in World.JINGUASHI.NODES:
					var ready:bool=float(data.get("jinguashi",{}).get("ready",{}).get(k,0))<=float(data.time)
					JinguashiArt.draw_mine_bed(self,at)
					JinguashiArt.draw_rock_ledge(self,at,village_art,p)
					AutomationArt.draw_copper(self,at,ready)
					if focused_label=="mine:"+k:world_label(at+Vector2(16,-18),"淺層銅礦" if ready else "礦料補充中","mine:"+k)
				continue
			if not home:
				# Canal service and blockage props belong only to Lanyang.
				if region_id()!=World.REGIONS.LANYANG:continue
				if p in World.LANYANG_LIFE.BLOCKAGES and not lanyang_life.get("cleared",{}).has(k):
					LanyangLifeArt.draw_detail(self,at,LanyangLifeArt.BLOCKAGE,elapsed,reduced_motion)
					if focused_label=="ditch:"+k:
						var section:String=["北段","中段","南段"][World.LANYANG_LIFE.BLOCKAGES.find(p)]
						world_label(at+Vector2(16,-9),"清理%s水口"%section,"ditch:"+k)
				if lanyang_life.get("repaired",false) and p in World.HISTORY_MEMORY.OBSERVATIONS:
					var at_fork:=p==World.LANYANG_REVISIT.GATE_CELL and World.LANYANG_REVISIT.unlocked(data)
					if at_fork \
						and not lanyang_cell_occupied(p) and not lanyang_cell_occupied(p+Vector2i.RIGHT):
						var levels:=World.LANYANG_REVISIT.gates(data)
						draw_texture(RevisitArt.fork_texture(int(levels[0]),int(levels[1])),at)
					var observed:Array=data.get("history_memory",{}).get("own_memory",{}).get("seen",[])
					if k not in observed:
						draw_texture_rect_region(MemoryIcons,Rect2(at+Vector2(4,-6),Vector2(24,24)),Rect2(128,32,32,32))
					if focused_label=="memory:"+k:
						# 第 40 章：準備好的島民在這三格看到回訪的動作（調閘／巡看）。
						var revisit_prompt:=RevisitUI.cell_prompt(data,p)
						var label_offset:=Vector2(32,0) if at_fork else Vector2(16,-12)
						world_label(at+label_offset,revisit_prompt if not revisit_prompt.is_empty() else "觀察水路","memory:"+k,at_fork)
				if p==Vector2i(33,28) and data.get("history_memory",{}).get("plaque",false) and not lanyang_cell_occupied(p):
					FurnitureArt.draw_sprite(self,at,"sign")
				if not garden_pots.is_empty() and p in World.RESIDENT_GOALS.GARDEN_POTS and not lanyang_cell_occupied(p):
					var pot_index:=World.RESIDENT_GOALS.GARDEN_POTS.find(p)
					if pot_index<garden_pots.size():
						var flower_index:=World.RESIDENT_GOALS.GARDEN_FLOWERS.find(garden_pots[pot_index].flower)
						draw_texture_rect_region(preload("res://assets/lanyang-life/shared-garden-pots.png"),Rect2(at+Vector2(0,-5),Vector2(32,32)),Rect2(flower_index*32,0,32,32))
				if p==World.LANYANG_LIFE.SERVICE:
					if lanyang_life.get("repaired",false) and not lanyang_cell_occupied(p):
						LanyangLifeArt.draw_detail(self,at,LanyangLifeArt.SLUICE,elapsed,true)
					if focused_label=="gardener":
						var gardener_prompt:=RevisitUI.gardener_prompt(data)
						world_label(at+Vector2(16,-10),gardener_prompt if not gardener_prompt.is_empty() else "星禾的園藝服務","gardener")
				if p==gardener_cell:
					LanyangLifeArt.draw_person(self,at)
					if focused_label!="gardener":world_label(at+Vector2(16,-22),"星禾","")
				if p==Vector2i(36,29) and lanyang_life.get("repaired",false) and not lanyang_cell_occupied(p):
					LanyangLifeArt.draw_detail(self,at,LanyangLifeArt.NURSERY,elapsed,true)
				continue
			if village_art and VillagePreview.contains(p):village_art.draw_coastal_prop(self,at,p)
			if p==World.Festival.TREE_CELL:
				draw_wind_chime_tree(at)
				if focused_label=="lingpopo_tree":world_label(at+Vector2(16,-36),"查看風鈴樹","lingpopo_tree")
			if data.get("festival_story_open",false) and World.Festival.VISITORS.has(p):
				draw_festival_visitor(at,World.Festival.VISITORS[p])
			if p==Vector2i(40,29):
				board(at)
				if data.has(World.RESIDENT_GOALS.MURAL_KEY):
					draw_texture(preload("res://assets/ui-inventory/public-mural.png"),at+Vector2(18,-4))
				if data.get("mine_freight",{}).get("own_job",{}).get("status","")=="held":
					MineArt.draw_freight(self,at+Vector2(16,16),"post",-1.0,reduced_motion,16)
			if p==Vector2i(43,29):shop(at)
			if p==shipping_cell:
				ShippingArt.draw_landmark(self,at)
				world_label(at+Vector2(16,-16),"出貨箱","shipping")
			if p==market_cell:draw_market_stall(at,p)
			if harvest_on and p in World.HARVEST.CELLS:draw_harvest_prop(at,p)
			if fishmeet_on and p==World.FISH_MEET.SIGN:
				FishMeetUI.draw_sign(self,at,FurnitureArt)
				world_label(at+Vector2(16,-5),FishMeetUI.sign_title(data,focused_label==FishMeetUI.POINT),FishMeetUI.POINT)
			if showcase_sign and p==World.SHOWCASE.SIGN:
				ShowcaseUI.draw_sign(self,at,FurnitureArt)
				world_label(at+Vector2(16,-5),ShowcaseUI.sign_title(data,focused_label==ShowcaseUI.POINT),ShowcaseUI.POINT)
			if showcase_plot and World.SHOWCASE.in_plot(p):
				var piece:=ShowcaseUI.piece_at(data,p)
				if not piece.is_empty():ShowcaseUI.draw_piece(self,at,piece)
				if p==showcase_target:world_label(at+Vector2(16,-2),ShowcaseUI.prompt(data,p,showcase_kind),ShowcaseUI.PLOT_POINT)
			if p==souvenir_cell:
				SouvenirUI.draw_booth(self,at)
				world_label(at+Vector2(16,-27),SouvenirUI.booth_title(focused_label==SouvenirUI.POINT),SouvenirUI.POINT)
			if p==table_cell:
				var meals:Dictionary=data.get("community",{})
				var servings:int=int(meals.get("hotpot",{}).get("portions",0))
				var chowder:int=int(meals.get("chowder",{}).get("portions",0))
				var fruit:int=int(meals.get("watermelon",{}).get("portions",0))
				# 茶陶上桌: plain view for the art ({} when no set, so the table draws as before);
				# current_round reads the snapshot time, so yesterday's round comes back cold.
				var table_tea:Dictionary={}
				var table_tea_cups:int=0
				if World.TEA_SERVICE.placed(data):
					table_tea={"placed":true}
					var table_tea_round:Dictionary=World.TEA_SERVICE.current_round(data)
					if not table_tea_round.is_empty():
						table_tea["style"]=str(table_tea_round.style)
						table_tea["left"]=int(table_tea_round.left)
						table_tea["cold"]=table_tea_round.cold==true
						table_tea_cups=int(table_tea_round.portions)
				CommunityArt.draw_table(self,at,elapsed,reduced_motion,data.get("public_kitchen",{}),community_feedback.sample(elapsed,reduced_motion),servings,fruit,World.TABLE_WARMER.installed(data),table_tea,chowder)
				CommunityArt.draw_plates_served(self,at,community_feedback.sample_shared(elapsed,reduced_motion or photograph_mode))
				CommunityArt.draw_portions_taken(self,at,community_feedback.sample_claims(elapsed,reduced_motion or photograph_mode))
				if data.get("festival_story_open",false):draw_festival_table(at)
				if focused_label=="community":
					var dishes:=PackedStringArray()
					if servings>0:dishes.append("火鍋 %d"%servings)
					if fruit>0:dishes.append("西瓜 %d"%fruit)
					if chowder>0:dishes.append("濃湯 %d"%chowder)
					if table_tea_cups>0:dishes.append("茶 %d"%table_tea_cups)
					world_label(at+Vector2(16,-4)," · ".join(dishes) if not dishes.is_empty() else "渡口餐桌","community")
			if p==bell_cell:
				draw_rect(Rect2(at+Vector2(3,3),Vector2(26,26)),Color("fff1af"),false,2.0)
				draw_rect(Rect2(at+Vector2(14,-11),Vector2(4,9)),Color("66856c"))
				draw_rect(Rect2(at+Vector2(10,-3),Vector2(12,11)),Color("e4b456"))
				draw_rect(Rect2(at+Vector2(8,7),Vector2(16,3)),Color("c88f43"))
				draw_rect(Rect2(at+Vector2(14,10),Vector2(4,6)),Color("efc867"))
				world_label(at+Vector2(35,6),"風鈴","bell",true)
			if p==Vector2i(54,25):
				rock(at)
				var remaining:=maxi(0,ceili(float(data.get("quarry",{}).get("ready",0))-float(data.time)))
				if focused_label!="copper":world_label(at+Vector2(16,-10),"採石點" if remaining==0 else "石層恢復 %d 秒"%remaining,"quarry")
			if p==World.SEAWEED_CELL:
				var remaining:=ceili(float(data.get("seaweed_ready",0.0))-float(data.time))
				var ripe:=remaining<=0
				var frond:=preload("res://scripts/inventory_item_art.gd").icon("seaweed")
				if frond:draw_texture_rect(frond,Rect2(at+Vector2(4,6),Vector2(24,24)),false,Color.WHITE if ripe else Color(1,1,1,0.35))
				world_label(at+Vector2(16,-4),"採集海苔" if ripe else "海苔約 %d 秒後長成"%remaining,World.SEAWEED_POINT)
			if p==World.WANGAN_COAST.SHELL_CELL:
				var coast:=World.WANGAN_COAST
				var covered:=coast.high_tide(float(data.time))
				var ready:=float(data.get("wangan_shell_ready",0.0))<=float(data.time)
				if not covered and ready:
					draw_texture_rect(preload("res://assets/ui-inventory/wangan-shell.png"),Rect2(at+Vector2(2,5),Vector2(24,24)),false)
				if focused_label==coast.SHELL_POINT:
					var title:="退潮再來撿貝殼" if covered else ("撿潮紋貝殼" if ready else "貝殼剛被撿走")
					world_label(at+Vector2(16,-5),title,coast.SHELL_POINT)
			if p==World.WANGAN_COAST.STAR_REPAIR and not data.get("wangan_star_walk",false):
				FurnitureArt.draw_sprite(self,at,"sign")
				world_label(at+Vector2(16,-12),"星砂步道・待修",World.WANGAN_COAST.STAR_REPAIR_POINT)
			if p==World.WANGAN_COAST.STAR_SAND and data.get("wangan_star_walk",false):
				var remaining:=ceili(float(data.get("wangan_star_sand_ready",0.0))-float(data.time))
				if remaining<=0:draw_texture(preload("res://assets/bakery/crystal-sand.png"),at)
				world_label(at+Vector2(16,-5),"採集晶砂" if remaining<=0 else "晶砂約 %d 秒後露出"%remaining,World.WANGAN_COAST.STAR_SAND_POINT)
			if p==World.WANGAN_COAST.DOCK_ORDERS and data.get("wangan_star_walk",false):
				FurnitureArt.draw_sprite(self,at,"sign")
				if focused_label==World.WANGAN_COAST.DOCK_ORDERS_POINT:
					world_label(at+Vector2(16,-12),"望安碼頭訂單",World.WANGAN_COAST.DOCK_ORDERS_POINT)
			if p==World.COPPER_CELL:
				var ready:=float(data.get("copper",{}).get("ready",0))<=float(data.time)
				AutomationArt.draw_copper(self,at,ready)
				world_label(at+Vector2(16,-18),"運入礦料" if ready else "等待補貨","copper")
		# 第 40 章地方記憶展：after the whole row, so the base rock at (40,26) stays behind the
		# stand's right post instead of covering its pedestals (screenshots, before/).
		if exhibit_cell!=MemoryExhibitUI.NO_CELL and y==exhibit_cell.y:
			var stand_at:=screen(Vector2(exhibit_cell))
			MemoryExhibitUI.draw_stand(self,stand_at,exhibit_cell)
			world_label(stand_at+MemoryExhibitUI.LABEL_ANCHOR,MemoryExhibitUI.stand_title(data,focused_label==MemoryExhibitUI.POINT),MemoryExhibitUI.POINT)
		if mining and floori(cart_position.y+0.5)==y and cart_position.x>=from.x and cart_position.x<to.x:
			var cart_at:=screen(cart_position).round()
			OreRouteArt.draw_cart(self,cart_at,cart_stage>0,elapsed,reduced_motion)
			if focused_label==OreRouteArt.POINT:world_label(cart_at+Vector2(16,-18),World.ORE_ROUTE.cart_label(data),OreRouteArt.POINT)
		for resident in World.Village.ids_for_region(region_id()):
			if resident=="xiaoli":continue # Already drawn behind the seed stall.
			var npc:Dictionary=World.Village.NPCS[resident]
			var resident_cell:Vector2i=World.Village.resident_cell(data,resident)
			if resident_cell.y==y:
				var at:=screen(Vector2(resident_cell)+Vector2(0.5,0.7))
				if resident!="bobo" or not BoboArt.draw(self,at-Vector2(24,44),"person"):
					person_sprite(at,Color(npc.color),resident)
				var label_offset:=Vector2(-25,-26) if Vector2(bell_cell-resident_cell).length()<=1.0 else Vector2(0,-47)
				if resident!="bobo" or focused_label=="bobo":world_label(at+label_offset,npc.name,resident)
		if not resident_at_station.is_empty() and resident_at_station.cell.y==y:
			var at:=screen(Vector2(resident_at_station.cell)+Vector2(0.5,0.72)).round()
			StationLifeArt.draw_person(self,at,region_id(),elapsed,reduced_motion)
			var resident_focus:="station_resident:"+region_id()
			if focused_label==resident_focus:world_label(at+Vector2(0,-47),resident_at_station.name,resident_focus)
		# T066：棉棉（飼料站旁）、阿潮（渡口碼頭旁）、暖暖（暖泉溪畔）。
		# 三位都暫用既有居民圖格加染色，專用像素圖待做。
		for walk_id:String in World.RESIDENT_BOND.WALK_UP:
			if walk_id=="nuannuan" and in_springs and rest_cell.x>=0:continue
			var walk_spot:Array=World.bond_place(data,walk_id)
			var walk_cell:Vector2i=walk_spot[1]
			if str(walk_spot[0])!=region_id() or walk_cell.y!=y or not World.RESIDENT_BOND.present(data,walk_id):continue
			var walk_foot:=screen(Vector2(walk_cell)+Vector2(0.5,0.7))
			person_sprite(walk_foot,Color("e8d9c4"),walk_id)
			world_label(walk_foot+Vector2(0,-47),World.RESIDENT_BOND.name_of(walk_id),walk_id)
		if in_springs:
			if in_inn and y in range(springs.INN_ROOM.position.y,springs.INN_ROOM.end.y):
				for x in range(springs.INN_ROOM.position.x,springs.INN_ROOM.end.x):
					var cell:=Vector2i(x,y)
					var at:=screen(Vector2(cell))
					if cell==springs.INN_EXIT:
						world_label(at+Vector2(16,12),"回到溪畔",springs.INN_PORTAL)
					elif y==springs.INN_ROOM.position.y or y==springs.INN_ROOM.end.y-1 or x in [springs.INN_ROOM.position.x,springs.INN_ROOM.end.x-1]:
						object_sprite(at,"wall")
						if y==springs.INN_ROOM.position.y and x in [62,68]:object_sprite(at,"window")
					elif springs.INN_FURNITURE.has(cell):
						var kind:String=springs.INN_FURNITURE[cell]
						var decor:={"type":kind,"inn_bed_vertical":true} if kind==Industry.INN_BED else {}
						object_sprite(at,kind,decor)
						var point:="%s:%s"%[springs.INN_USE,World.key(cell)]
						if focused_label==point:world_label(at+Vector2(16,-14),"休息" if kind==Industry.INN_BED else "坐下",point)
			if y==springs.INN_FOOTPRINT.end.y-1:
				var origin:=screen(Vector2(springs.INN_FOOTPRINT.position))
				springs.draw_inn(self,origin,elapsed,reduced_motion)
				world_label(origin+Vector2(64,-26),"暖泉旅舍",springs.INN_POINT)
			if y==springs.BATH_ORIGIN.y:
				var at:=screen(Vector2(springs.BATH_ORIGIN))
				var repaired:bool=data.get(springs.BATH_KEY,false)
				var art:=preload("res://assets/ui-life/inn-stone-footbath.png") if repaired else preload("res://assets/ui-life/inn-public-bath-closed.png")
				draw_texture(art,at)
				if repaired and not reduced_motion:
					for i in 3:
						var phase:=fposmod(elapsed*0.42+float(i)*0.28,1.0)
						draw_circle(at+Vector2(27.0+20*i,26.0-phase*19.0),2.0+phase*3.0,Color(0.88,0.98,0.89,sin(phase*PI)*0.24))
				world_label(at+Vector2(48,-10),"公共泡腳池" if repaired else "待修泡腳池",springs.BATH_ACTION)
			for choice:String in springs.REST_SEATS:
				var seat:Vector2i=springs.REST_SEATS[choice]
				if seat.y!=y:continue
				var at:=screen(Vector2(seat))
				if choice=="porch":
					object_sprite(at,World.RESIDENT_GOALS.STONE_BENCH)
				else:
					var art:=preload("res://assets/ui-life/inn-rest-seats.png")
					var source:=Rect2(0 if choice=="stream" else 32,0,32,32)
					for dx in [0,28]:
						draw_texture_rect_region(art,Rect2(at+Vector2(dx,-4),Vector2(32,32)),source)
			if rest_cell.y==y:
				var companion:=screen(Vector2(rest_cell)+Vector2(1.42,0.66))
				if character_art:character_art.draw_seated(self,companion,false,"nuannuan")
				else:person_sprite(companion,Color("e8d9c4"),"nuannuan")
		if home and data.get("picnic",false):
			if y==World.Dog.SITE.y:
				var dog_at:=screen(Vector2(World.Dog.SITE)+Vector2(0.5,0.55)).round()
				var own_dog:Dictionary=data.get("players",{}).get(player_id,{}).get(World.Dog.FIELD,{})
				if not own_dog.get("following",false):draw_texture(World.Dog.texture(),dog_at-Vector2(10,12))
				if focused_label=="companion_dog":world_label(dog_at+Vector2(0,-18),World.Dog.NAME,"companion_dog")
			for id:String in World.LIVESTOCK.ANIMALS:
				var animal:Dictionary=World.LIVESTOCK.ANIMALS[id]
				if animal.cell.y!=y:continue
				var foot:=screen(Vector2(animal.cell)+Vector2(0.5,0.9)).round()
				var record:Dictionary=data.get("livestock",{}).get(id,{})
				if id=="sheep":draw_rabbit_basket(foot+Vector2(-30,2))
				var corner:=int(data.get("sheep_comfort_fixtures",0)) if id=="sheep" else 0
				if (corner&1)!=0:draw_sheep_comfort(foot+Vector2(16,-34),0)
				if (corner&2)!=0:draw_sheep_comfort(foot+Vector2(17,-18),1)
				var reaction_age:=elapsed-float(livestock_pet_feedback.get(id,-INF))
				var brushing:bool=id=="sheep" and record.get("last_care","")=="brush"
				var quiet:=reduced_motion or photograph_mode
				var animal_foot:=foot+sheep_shelter.offset(elapsed,quiet) if id=="sheep" else foot
				var offset:=Vector2.ZERO if brushing else LivestockArt.reaction_offset(id,reaction_age,int(record.get("bond",0)),quiet)
				if id=="duck":draw_duck(foot,record,reaction_age)
				else:
					var sheep:bool=id=="sheep"
					var walking_frame:=sheep_shelter.walking_frame(elapsed,quiet) if sheep else -1
					if sheep:LivestockArt.draw_station(self,foot,id,LivestockArt.state_for(record),elapsed,quiet)
					LivestockArt.draw(self,animal_foot,id,LivestockArt.state_for(record),quiet,elapsed,Vector2i(offset),brushing and reaction_age>=0.0 and reaction_age<LivestockArt.PET_SECONDS,walking_frame,sheep,sheep and sheep_shelter.walking(elapsed,quiet) and sheep_shelter.facing_right(),view_zoom())
				if id=="sheep" and (corner&1)!=0:draw_sheep_comfort(foot+Vector2(16,-34),0)
				if brushing:LivestockArt.draw_brushing(self,animal_foot,reaction_age,quiet)
				if id=="sheep":
					var play:Dictionary=data.get(World.RESIDENT_GOALS.SHEEP_PLAY_KEY,{})
					var age:=float(data.time)-float(play.get("at",-10))
					if age<World.RESIDENT_GOALS.SHEEP_PLAY_SECONDS:
						var lift:=0.0 if reduced_motion else absf(sin(age*5.0))*4.0
						draw_sheep_comfort(foot+Vector2(-29,-14-lift),2 if play.get("toy")=="ball" else 3)
				if record.has("collector"):
					var equipment:=LivestockArt.collector_texture(int(record.collector),World.LIVESTOCK.COLLECTOR_CAPACITY)
					draw_texture(equipment,foot+Vector2(12,-10))
				if id!="duck" and livestock_pet_feedback.has(id):
					LivestockArt.draw_pet_heart(self,animal_foot+offset,reaction_age,quiet)
				if focused_label=="livestock:"+id:
					var caption:String=animal.name
					if record.get("managed_pen",false) and not World.LIVESTOCK.pen_status(data.get("objects",{}),id):
						caption+="・圈舍待修"
					world_label(foot+Vector2(0,-42),caption,"livestock:"+id)
		# T071 客人演出：有攤位開張的世界日，攤位前站著幾位逛市集的客人（純呈現）。
		if home and World.RESIDENT_GOALS.ARU_PARK_VIEW.y==y:
			var post:=screen(Vector2(World.RESIDENT_GOALS.ARU_PARK_VIEW)).round()
			FurnitureArt.draw_sprite(self,post+Vector2(-18,7),"sign")
			if focused_label=="aru_park":world_label(post+Vector2(16,-8),"公共長椅地塊","aru_park")
		var wangan:=World.WANGAN_MEMORY
		if courtyard and y==wangan.COURT.position.y:
			var house_at:=screen(Vector2(wangan.COURT.position)).round()
			draw_texture(preload("res://assets/ui-life/wangan-courtyard-house.png"),house_at+Vector2(0,-38))
			if data.get("picnic",false):draw_cat_home(house_at+Vector2(74,20))
		elif home and not courtyard and data.get("picnic",false) and y==World.Cat.site(data).y:
			draw_cat_home(screen(Vector2(World.Cat.site(data))+Vector2(0.5,0.55)))
		if courtyard and y==wangan.COURT_SIGN.y:
			var sample_at:=screen(Vector2(wangan.COURT_SIGN)).round()
			draw_texture_rect(preload("res://assets/ui-life/wangan-wall-samples.png"),Rect2(sample_at+Vector2(-4,0),Vector2(40,12)),false)
			if focused_label==wangan.COURT_POINT:world_label(sample_at+Vector2(16,-10),"看看老屋的石牆",wangan.COURT_POINT)
		if home and wangan.SITE.y==y:
			var post:=screen(Vector2(wangan.SITE)).round()
			FurnitureArt.draw_sprite(self,post,"sign")
			world_label(post+Vector2(16,-13),"花宅觀察牌",wangan.POINT)
		if home and wangan.WEIR_SITE.y==y:
			var post:=screen(Vector2(wangan.WEIR_SITE)).round()
			FurnitureArt.draw_sprite(self,post,"sign")
			world_label(post+Vector2(16,-13),"石滬觀察牌",wangan.WEIR_POINT)
		if home and wangan.WEIR_LOOKOUT.y==y:
			var post:=screen(Vector2(wangan.WEIR_LOOKOUT)+Vector2(0.75,0)).round()
			FurnitureArt.draw_sprite(self,post,"sign")
			world_label(post+Vector2(16,-13),"南岸觀潮點",wangan.WEIR_LOOKOUT_POINT)
		var lamp_cell:=World.RESIDENT_GOALS.VOYAGE_LAMP_CELL
		if home and lamp_cell.y==y and data.get(World.RESIDENT_GOALS.DOCK_LIGHT,false):
			draw_texture_rect_region(VOYAGE_ART,Rect2(screen(Vector2(lamp_cell))-Vector2(8,20),Vector2(48,48)),Rect2(96,0,48,48))
		if home and y==floori(DOCKED_BOAT.y) and World.TRANSIT.boat_open(data):
			draw_cooperative_boat()
		for guest:Dictionary in guests_today:
			if floori(float(guest.position.y))==y:draw_market_guest(guest)
		if home and y==World.Squirrel.SITE.y:draw_squirrel_site()
		if home and y==World.Seal.SITE.y:draw_seal_site()
		if deer_site.x>=0 and y==deer_site.y:
			var deer_at:=screen(Vector2(deer_site)+Vector2(0.55,0.8)).round()
			var blink:=not reduced_motion and fposmod(elapsed,3.7)>3.45
			draw_texture(World.Deer.texture(blink),deer_at-Vector2(14,24))
			if focused_label==World.Deer.POINT:world_label(deer_at+Vector2(0,-29),World.Deer.NAME,World.Deer.POINT)
		for id in data.players:
			var person:Dictionary=data.players[id]
			var visual_position:Vector2=display_positions.get(id,Vector2(person.x,person.y))
			if floori(visual_position.y)==y:
				var at:=screen(visual_position).round()
				var local:bool=id==player_id
				var rest_seat:=str(person.get(springs.REST_SEAT_KEY,""))
				var inn_chair:=rest_seat.begins_with(springs.INN_USE+":")
				if in_springs and (springs.REST_SEATS.has(rest_seat) or rest_seat==springs.BATH_ACTION or inn_chair):
					if rest_seat==springs.BATH_ACTION:at.y-=22.0
					if inn_chair:at=screen(Vector2(World.cell(rest_seat.get_slice(":",1)))+Vector2(0.5,0.72)).round()
					if character_art:character_art.draw_seated(self,at,bool(person.get("blue_outfit",false)))
					else:person_sprite(at,Color("d88f73"),"farmer")
					continue
				if person.get("at_sea",false):
					var skipper:String=person.get("voyage_captain","")
					if not skipper.is_empty() and voyage_passengers.get(skipper)==id:continue
					var blue:bool=person.get(World.RESIDENT_GOALS.VOYAGE_PAINT,false)
					var rock:=0.0 if reduced_motion else sin(elapsed*3.0)*1.5
					var deck:=at+Vector2(0,rock).round()
					draw_texture_rect_region(VOYAGE_ART,Rect2(deck-Vector2(24,33),Vector2(48,48)),Rect2(48 if blue else 0,0,48,48))
					person_sprite(deck+Vector2(-8,2),Color("d88f73"),"farmer",Vector2i.DOWN,0.0,false,person.get("blue_outfit",false))
					var guest:Dictionary=data.players.get(voyage_passengers.get(id,""),{})
					person_sprite(deck+Vector2(10,-1),Color("a1bac6"),"achao" if guest.is_empty() else "farmer",Vector2i.DOWN,0.0,false,guest.get("blue_outfit",false))
					continue
				var seat:Dictionary=person.get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
				var seat_obj:Dictionary=data.objects.get(seat.get("cell",""),{})
				if seat_obj.get("type")==Industry.FOOT_BATH and int(seat.get("side",-1)) in range(Industry.FOOT_BATH_SEATS.size()):
					var offset:Vector2=Industry.FOOT_BATH_SEATS[int(seat.side)]
					if Industry.is_vertical(seat_obj):offset=Vector2(2.0-offset.y,offset.x)
					var place:=screen(Vector2(World.cell(seat.cell))+offset).round()
					if character_art:character_art.draw_seated(self,place,bool(person.get("blue_outfit",false)))
					else:person_sprite(place,Color("d88f73"),"farmer" if local else "guest")
					continue
				if not seat.is_empty() and data.objects.get(seat.get("cell",""),{}).get("type") in World.RESIDENT_GOALS.DOUBLE_BENCHES:
					var bench:=World.cell(seat.cell)
					var offset:=Vector2(World.master_bench_offset(data.objects[seat.cell]))*float(seat.side)
					var sitting_at:=screen(Vector2(bench)+Vector2(0.55,0.81)+offset).round()
					if character_art:character_art.draw_seated(self,sitting_at,bool(person.get("blue_outfit",false)))
					else:person_sprite(sitting_at,Color("d88f73"),"farmer" if local else "guest")
					continue
				var shirt:=Color("d88f73") if local else Color.from_hsv([0.55,0.76,0.44][absi(hash(id))%3],0.32,0.77)
				var operation:=farm_feedback.active(id,elapsed)
				var machine_kind:String=operation.get("kind","")
				if machine_kind.is_empty() and local:
					for kind in MACHINES:
						if selected==MACHINES[kind][0] and int(person.get("inventory",{}).get(kind,0))>0:
							machine_kind=kind
				var machine_facing:Vector2i=facings.get(id,Vector2i.DOWN)
				var working_now:=not operation.is_empty()
				if working_now or (local and show_target and not machine_kind.is_empty()):
					var cell:Vector2i=operation.get("center",target)
					var origin:Vector2=operation.get("origin",visual_position)
					var towards:=Vector2(cell)+Vector2(0.5,0.5)-origin
					if towards.length()>0.25:
						machine_facing=Vector2i(int(signf(towards.x)),0) if absf(towards.x)>absf(towards.y) else Vector2i(0,int(signf(towards.y)))
				var push:=0.0
				if working_now and not reduced_motion:
					push=6.0*sin(PI*clampf((elapsed-float(operation.started))/FarmFeedback.DURATION,0.0,1.0))
				var machine_at:=at+Vector2(machine_facing)*(18.0+push)+Vector2(0,12)
				if not machine_kind.is_empty() and machine_facing==Vector2i.UP:
					draw_farm_machine(machine_kind,machine_at,machine_facing,working_now)
				var fishing:=fishing_feedback.state_for(id,float(data.time),elapsed)
				var facing:Vector2i=facings.get(id,Vector2i.DOWN)
				if fishing.get("phase","") in ["cast","wait","ready","catch"]:
					var toward:Vector2=fishing.target-visual_position
					if absf(toward.x)>absf(toward.y):facing=Vector2i.RIGHT if toward.x>0 else Vector2i.LEFT
					else:facing=Vector2i.DOWN if toward.y>0 else Vector2i.UP
				# T017 hand-tool action: fishing and farm machines keep priority (one action pose at a time).
				var cancelling:bool=fishing.get("phase","")=="cancel"
				var tool_plan:=tool_action_plan(id) if (fishing.is_empty() or cancelling) and operation.is_empty() else {}
				if cancelling and (not tool_plan.is_empty() or not operation.is_empty()):
					fishing={}
				var cart_pose:=ore_cart_push_pose(cart_stage,visual_position) if mining and local and fishing.is_empty() and tool_plan.is_empty() and not walking.get(id,false) else {}
				var lean:=FishingArt.angler_lean(fishing,elapsed,reduced_motion or photograph_mode)
				var cuddling:bool=World.CHICKEN_CUDDLE.holder(data)==id
				if cuddling:
					tool_plan={}
					fishing={}
					lean=0.0 if reduced_motion or photograph_mode else 1.0
				if not cart_pose.is_empty():lean=float(cart_pose.lean)
				if not tool_plan.is_empty():
					facing=tool_plan.facing
					lean=float(tool_plan.body_lean)
				if not cart_pose.is_empty():facing=cart_pose.facing
				if not tool_plan.is_empty() and facing==Vector2i.UP:draw_tool_held(at,tool_plan)
				person_sprite((at+tool_plan.get("lunge",Vector2.ZERO)).round(),shirt,"farmer" if local else "guest",facing,float(gait.get(id,0.0)),cart_pose.is_empty() and bool(walking.get(id,false)),bool(person.get("blue_outfit",false)),bool(person.get(World.RESIDENT_GOALS.APRON_KEY,false)),lean)
				var cat:Dictionary=person.get(World.Cat.FIELD,{})
				var dog:Dictionary=person.get(World.Dog.FIELD,{})
				var fox:Dictionary=person.get(World.Fox.FIELD,{})
				if fox.get("following",false):draw_following_pet(id,visual_position,fox,"fox")
				elif dog.get("following",false):draw_following_pet(id,visual_position,dog,"dog")
				elif cat.get("following",false):draw_following_pet(id,visual_position,cat,"cat")
				elif person.get(World.Rabbit.FIELD,{}).get("following",false):draw_following_pet(id,visual_position)
				if not tool_plan.is_empty() and facing!=Vector2i.UP:draw_tool_held(at,tool_plan)
				if cuddling:
					World.CHICKEN_CUDDLE.draw(self,at,elapsed,reduced_motion or photograph_mode)
					chicken_draw_stats.carried+=1
					if local:world_label(at+Vector2(0,-64),"抱抱糯米雞 · 互動鍵放開","")
				if not machine_kind.is_empty() and machine_facing!=Vector2i.UP:
					draw_farm_machine(machine_kind,machine_at,machine_facing,working_now)
				if not fishing.is_empty():
					var float_pos:=screen(fishing.target)
					FishingArt.draw(self,at,float_pos,fishing,reduced_motion or photograph_mode,elapsed,view_zoom())
				if harvest_on:
					var carried:=HarvestUI.carried(data,str(id))
					if not carried.is_empty():draw_harvest_carry(at,carried)
				var text:String=person.name
				if not (local and (placing_drill or focused_label in ["bobo","bobo_sort"] or focused_label.begins_with("transit:") or focused_label.begins_with("station_resident:") or focused_label.begins_with("tea:") or focused_label.begins_with("flower:") or focused_label.begins_with("salt:"))):
					world_label(at+Vector2(0,-40),text,"")
				var emote:Dictionary=player_emotes.get(id,{})
				if int(emote.get("until",0))>Time.get_ticks_msec() and emote.get("region")==region_id():
					world_label(at+Vector2(0,-62),str(emote.caption),"")
	if home:
		# A resident chicken gives the first clearing a living, gentle focal point.
		var chicken_pos:=Vector2(45.7,33.8)
		var animal:Dictionary=data.get("animal",{})
		var fed_at:=float(animal.get("egg_ready",-1))-World.CHICKEN_EGG_SECONDS
		var since_feed:=float(data.time)-fed_at
		var approach:=World.RESIDENT_GOALS.CHICKEN_APPROACH_SECONDS
		if not reduced_motion:
			chicken_pos.x+=sin(elapsed*0.5)*0.6
			if since_feed>=0.0 and since_feed<=approach+4.0:
				var weight:=minf(since_feed/approach,(approach+4.0-since_feed)/2.0)
				chicken_pos=chicken_pos.lerp(Vector2(World.CHICKEN_CELL)+Vector2(0.5,0.5),clampf(weight,0.0,1.0))
		var held:bool=not World.CHICKEN_CUDDLE.holder(data).is_empty()
		if not held:
			chicken(screen(chicken_pos))
			chicken_draw_stats.ground+=1
			world_label(screen(chicken_pos)+Vector2(0,-25),"糯米雞","animal")
		var basket_at:=screen(Vector2(46.5,34.7))
		if animal.has("basket_eggs"):
			var basket:=preload("res://scripts/salt_revisit_art.gd").empty_basket_texture()
			draw_texture(basket,basket_at-Vector2(16,28))
		var loose_egg:=float(animal.get("egg_ready",-1))>=0 and float(data.time)>=float(animal.egg_ready)
		if int(animal.get("basket_eggs",0))>0 or loose_egg:
			var egg_at:=basket_at-Vector2(3,19) if animal.has("basket_eggs") else screen(chicken_pos)+Vector2(12,0)
			if not character_art or not character_art.draw_egg(self,egg_at+Vector2(3,8)):
				draw_rect(Rect2(egg_at,Vector2(6,8)),Color("fff4d4"))
				draw_rect(Rect2(egg_at+Vector2(1,-2),Vector2(4,11)),Color("fff4d4"))
		if not held and float(data.time)-float(animal.get("last_pet",-30))<3:
			var heart:=screen(chicken_pos)+Vector2(8,-30)
			draw_rect(Rect2(heart,Vector2(4,4)),Color("d98e87"))
			draw_rect(Rect2(heart+Vector2(5,0),Vector2(4,4)),Color("d98e87"))
			draw_rect(Rect2(heart+Vector2(2,3),Vector2(5,4)),Color("d98e87"))
	# Local player only; the body is drawn at display_positions, so occlusion uses that.
	var local_drawn:Vector2=display_positions.get(player_id,Vector2.INF)
	var faded_roofs:Dictionary=RoofVisibility.faded(data,player_id,local_drawn)
	for k in data.get("roofs",{}):
		var tile:=World.cell(k)
		var at:=screen(Vector2(tile))
		var alpha:=0.16 if faded_roofs.has(k) else 1.0
		roof_sprite(at,alpha,str(data.roofs[k].type),str(data.roofs[k].get("style","")))
	var forestry_focus:Dictionary=data.get("objects",{}).get(focused_label,{})
	if forestry_focus.get("type","")=="forester":
		for offset in Forestry.OFFSETS:
			ForestryArt.draw_plot_marker(self,screen(Vector2(World.cell(focused_label)+offset)),Color.WHITE)
	# Weather sits above ground/props/roofs but below world labels and targeting; HUD is a separate layer.
	if not in_inn:draw_weather(size)
	if show_target and not photograph_mode and region_id()==World.REGIONS.HOME and data.has("can_build_public_plot") and selected=="build":
		var plot:=World.PUBLIC_BUILD_PLOT
		var origin:=screen(Vector2(plot.position))
		var tint:=Color("e7d9a4") if data.can_build_public_plot else Color("e89a7d")
		draw_rect(Rect2(origin+Vector2.ONE,Vector2(plot.size*32)-Vector2(2,2)),tint,false,1.0)
		world_label(origin+Vector2(plot.size.x*16,-4),"渡口北側公共地塊" if data.can_build_public_plot else "公共地塊 · 需施工授權","public_build_plot")
	if show_target and not photograph_mode and region_id()==World.REGIONS.HOME and selected=="build":
		var floor_piece:Dictionary=data.ground.get(World.key(target),{})
		var builder:Dictionary=data.players.get(player_id,{})
		if floor_piece.get("type")=="floor" and floor_piece.get("owner")==player_id and not builder.is_empty():
			if Vector2(builder.x,builder.y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=3.2:
				world_label(screen(Vector2(target))+Vector2(16,-4),"家園權限","floor_placement_access",true)
	if show_target and not photograph_mode and region_id()==World.REGIONS.HOME:
		var room_floor:Dictionary=data.ground.get(World.key(target),{})
		if room_floor.get("owner_visit",false) and room_floor.get("owner")!=player_id and room_floor.get("visit_guest")!=player_id:
			world_label(screen(Vector2(target))+Vector2(16,-4),"私人區域未開放參觀","private_room")
	if show_target and not photograph_mode and region_id()==World.REGIONS.HOME and selected=="remove":
		var furniture:Dictionary=data.objects.get(World.key(target),{})
		var builder:Dictionary=data.players.get(player_id,{})
		if furniture.get("owner")==player_id and furniture.get("type") in World.PLOT_PERMISSIONS.SHARED_REMOVAL_FURNITURE and not furniture.get("aru_public",false) and not builder.is_empty():
			if Vector2(builder.x,builder.y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=3.2:
				world_label(screen(Vector2(target))+Vector2(16,-4),"家具拆除權限","furniture_remove_access",true)
	if first_crop.get("id","")=="buy_seed":
		first_crop_cue_rect=WanganUI.draw_step_cue(self,first_crop)
	elif home and first_crop.is_empty() and data.get("players",{}).has(player_id) and World.CHAPTER_ONE.phase(data)=="works":
		first_crop_cue_rect=WanganUI.draw_step_cue(self,World.CHAPTER_ONE.next_step(data))
	elif home and first_crop.is_empty() and World.CHAPTER_ONE.needs_starter_kit(data,player_id):
		first_crop_cue_rect=WanganUI.draw_step_cue(self,{"id":"starter_kit","cell":World.CHAPTER_ONE.STARTER_CELL})
	elif home and first_crop.is_empty() and World.CHAPTER_ONE.phase(data)=="meal" and not data.get("festival",{}).get("active",false) and World.CHAPTER_ONE.can_serve_picnic(data,player_id):
		first_crop_cue_rect=WanganUI.draw_step_cue(self,{"id":"works","cell":Vector2i(40,29)})
	elif home and first_crop.is_empty() and data.get("players",{}).has(player_id) and World.CHAPTER_ONE.phase(data)=="complete" and not data.get("festival",{}).get("active",false) and not data.get("tea_ceramics",{}).get("own_record",{}).get("intro",false):
		first_crop_cue_rect=WanganUI.draw_step_cue(self,{"id":"tea_intro","cell":World.TEA_CERAMICS.RECEIVER})
	draw_world_labels()
	if selected=="fish" and not hide_interaction_prompt:
		var cast:Dictionary=data.players.get(player_id,{}).get("fishing",{})
		var now:=float(data.time)
		if not cast.is_empty() and now>=float(cast.ready):
			var float_pos:=screen(FishingFeedback.target_of(cast))
			if cast.has("band") and World.FishingTracking.progress(cast,now)<World.FishingTracking.DURATION:
				FishingArt.draw_tracking(self,float_pos,cast,now)
			else:FishingArt.draw_ready_label(self,float_pos,font)
	for id in data.players:
		var operation:=farm_feedback.active(id,elapsed)
		var fishing:=fishing_feedback.state_for(id,float(data.time),elapsed)
		if not operation.is_empty():draw_farm_feedback(operation)
		elif fishing.is_empty() or fishing.get("phase","")=="cancel":
			if not reduced_motion and not photograph_mode:
				for record:Dictionary in tool_feedback.target_tails(id,elapsed):
					var tail_plan:=tool_record_plan(id,record)
					draw_tool_target(tail_plan,screen(record.origin).round())
			var tool_plan:=tool_action_plan(id)
			if not tool_plan.is_empty():
				var person:Dictionary=data.players[id]
				var foot:Vector2=display_positions.get(id,Vector2(person.x,person.y))
				draw_tool_target(tool_plan,screen(foot).round())
	if show_target and not photograph_mode:
		var at:=screen(Vector2(target))
		var blocked:Dictionary={}
		if selected=="build":
			blocked=build_placement_blocks(target,building)
			var offsets:=build_placement_offsets(building)
			if offsets.size()>1:
				var tint:=Color("f9e4a4") if blocked.is_empty() else Color("df8c79")
				var extent:=Vector2(offsets.back())*32.0+Vector2(28,28)
				draw_rect(Rect2(at+Vector2(2,2),extent),tint,false,1.0)
		if selected in ["till_area","seed_area","harvest_area"]:
			var preview:=tiller_preview(target) if selected=="till_area" else seeder_preview(target)
			if selected=="harvest_area":preview=harvester_preview(target)
			var person:Dictionary=data.players.get(player_id,{})
			var has_fuel:=int(person.get("inventory",{}).get("charcoal",0))>0
			for y in range(target.y-1,target.y+2):
				for x in range(target.x-1,target.x+2):
					var tile:=Vector2i(x,y)
					var valid:bool=World.key(tile) in preview.cells
					var tint:=Color("b3d894") if valid and has_fuel else Color("db9980")
					if selected=="seed_area" and has_fuel and preview.skipped.get(World.key(tile),"")=="種子不足":tint=Color("e2c26b")
					if selected=="harvest_area" and has_fuel and preview.skipped.get(World.key(tile),"")=="還沒成熟":tint=Color("e2c26b")
					var tile_at:=screen(Vector2(tile))
					draw_rect(Rect2(tile_at+Vector2(1,1),Vector2(30,30)),Color(tint,0.13))
					draw_rect(Rect2(tile_at+Vector2(2,2),Vector2(28,28)),tint,false,1.0)
		draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),Color(1,0.98,0.78,0.16))
		var outline:=Color("fff4c2")
		if selected=="plant_tree":
			outline=Color("b3d894") if tree_planting_preview(target).is_empty() else Color("db9980")
		draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),outline,false,2.0)
		if selected=="build":
			draw_rect(Rect2(at+Vector2(4,4),Vector2(24,24)),Color(0.9,0.9,0.75,0.22))
			if building=="mine_drill":draw_drill_placement()
			if building=="forester":
				for offset in Forestry.OFFSETS:
					ForestryArt.draw_plot_marker(self,screen(Vector2(target+offset)),Color(1,1,1,0.8))
			if Industry.SPRINKLER_CAPACITIES.has(building):
				for offset in Industry.sprinkler_offsets(building):
					var nearby:=screen(Vector2(target+offset))
					draw_rect(Rect2(nearby+Vector2(2,2),Vector2(28,28)),Color(0.4,0.8,0.8,0.22))
					draw_rect(Rect2(nearby+Vector2(2,2),Vector2(28,28)),Color("9fd2cf"),false,1.0)
			if blocked.is_empty():draw_build_placement_art(at)
			for tile:Vector2i in blocked:
				var edge:=screen(Vector2(tile))+Vector2(2,2)
				draw_rect(Rect2(edge,Vector2(28,28)),Color("572c2773"))
				draw_rect(Rect2(edge,Vector2(28,28)),Color("df8c79"),false,2.0)
				draw_line(edge+Vector2(8,8),edge+Vector2(20,20),Color("ffd2bf"),2.0)
				draw_line(edge+Vector2(20,8),edge+Vector2(8,20),Color("ffd2bf"),2.0)
	if area_drag:
		var a:=Vector2i(mini(area_start.x,target.x),mini(area_start.y,target.y))
		var b:=Vector2i(maxi(area_start.x,target.x),maxi(area_start.y,target.y))
		var count:=(b.x-a.x+1)*(b.y-a.y+1)
		if count<=World.build_area_limit(data.get("players",{}).get(player_id,{})):
			draw_rect(Rect2(screen(Vector2(a)),Vector2(b-a+Vector2i.ONE)*TILE),Color(0.96,0.92,0.67,0.23))
			var cost:="%d 格"%count
			for item in ["wood","stone","fiber"]:
				if World.BUILD[building].has(item):cost+=" · "+World.NAMES[item]+" %d"%(int(World.BUILD[building][item])*count)
			label_at(screen(Vector2(a))+Vector2(16,-10),cost)

## Read-only: weather comes from weather.gd via the snapshot time/region; nothing is written back.
func weather_info() -> Dictionary:
	return WeatherArt.current(data)

## Roofed cells count as indoor/sheltered for rain presentation.
func rain_sheltered(cell:Vector2i) -> bool:
	var roofs:Dictionary=data.get("roofs",{})
	return roofs.has(World.key(cell)) or (region_id()=="home" and data.get("picnic",false) and (int(data.get("sheep_comfort_fixtures",0))&1)!=0 and cell==World.LIVESTOCK.ANIMALS.sheep.cell+Vector2i.RIGHT)

static func night_darkness(world_time:float) -> float:
	var minute:=fposmod(world_time,World.WEATHER.DAY_SECONDS)
	if minute>=1080.0:return smoothstep(1080.0,1200.0,minute)
	return 1.0-smoothstep(300.0,360.0,minute)

func draw_cooperative_boat() -> void:
	var at:=screen(DOCKED_BOAT).round()
	var still:=reduced_motion or photograph_mode
	var bob:=0.0 if still else roundf(sin(elapsed*2.0))
	draw_texture_rect_region(VOYAGE_ART,Rect2(at+Vector2(-24,-40+bob),Vector2(48,48)),Rect2(48,0,48,48))
	var age:=elapsed-dock_launch_started
	if still or age>=DOCK_LAUNCH_SECONDS:return
	var progress:=age/DOCK_LAUNCH_SECONDS
	for index in 6:
		var direction:=Vector2.from_angle(TAU*index/6.0)
		var point:=(at+Vector2(0,-8)+direction*(9.0+progress*22.0)).round()
		var tint:=Color(1.0,0.9,0.6,1.0-progress)
		draw_rect(Rect2(point-Vector2(1,2),Vector2(2,4)),tint)
		draw_rect(Rect2(point-Vector2(2,1),Vector2(4,2)),tint)

func draw_night_ground(size:Vector2,from:Vector2i,to:Vector2i) -> void:
	var strength:=night_darkness(float(data.get("time",0.0)))
	if strength<=0.0:return
	# Darken the terrain before drawing the scene's objects, people and labels.
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.075,0.11,0.25,0.45*strength))
	if night_lamp_pool==null:
		var ramp:=Gradient.new()
		ramp.offsets=PackedFloat32Array([0.0,0.42,1.0])
		ramp.colors=PackedColorArray([Color(1.0,0.82,0.43,0.52),Color(1.0,0.70,0.37,0.23),Color(1.0,0.62,0.30,0.0)])
		night_lamp_pool=GradientTexture2D.new()
		night_lamp_pool.gradient=ramp
		night_lamp_pool.fill=GradientTexture2D.FILL_RADIAL
		night_lamp_pool.fill_from=Vector2(0.5,0.5)
		night_lamp_pool.fill_to=Vector2(1.0,0.5)
	var visible:=Rect2i(from,to-from)
	var objects:Dictionary=data.get("objects",{})
	for key:String in objects:
		if objects[key].get("type","") not in ["lamp","lantern_post"]:continue
		var cell:=World.cell(key)
		if visible.has_point(cell):draw_night_lamp(cell,strength)
	var dock:=World.RESIDENT_GOALS.VOYAGE_LAMP_CELL
	if region_id()==World.REGIONS.HOME and data.get(World.RESIDENT_GOALS.DOCK_LIGHT,false) and visible.has_point(dock):
		draw_night_lamp(dock,strength)

func draw_night_lamp(cell:Vector2i,strength:float) -> void:
	var center:=screen(Vector2(cell)+Vector2(0.5,0.65))
	draw_texture_rect(night_lamp_pool,Rect2(center-Vector2(52,30),Vector2(104,60)),false,Color(1,1,1,strength))

func draw_weather(size:Vector2) -> void:
	var info:Dictionary=weather_info()
	if info.is_empty():return
	var shade:Color=WeatherArt.tint(info)
	if shade.a>0.0:draw_rect(Rect2(Vector2.ZERO,size),shade)
	if info.id in ["windy","snowy"]:
		draw_drifting_weather(size,info.id=="snowy")
		return
	if not WeatherArt.rains(info):return
	if reduced_motion:
		# No movement at all: a few fixed, world-anchored puddle marks on open ground.
		var from:=Vector2i((camera/TILE).floor())
		var to:=from+Vector2i(ceili(size.x/TILE)+1,ceili(size.y/TILE)+1)
		var marks:=0
		for y in range(from.y,to.y):
			for x in range(from.x,to.x):
				if marks>=WeatherArt.MAX_STATIC_MARKS:return
				var cell:=Vector2i(x,y)
				var offset:Vector2=WeatherArt.static_mark(cell)
				if offset.x<0.0 or rain_sheltered(cell):continue
				WeatherArt.draw_ripple(self,screen(Vector2(cell))+offset,0.7)
				marks+=1
		return
	for i in range(WeatherArt.MAX_DROPS):
		var sample:Vector3=WeatherArt.drop(i,elapsed,camera,size)
		var land:=Vector2(sample.x,sample.y)
		if rain_sheltered(draw_cell(land)):continue
		if sample.z<WeatherArt.FALL_PART:
			var head:Vector2=WeatherArt.streak_head(sample)
			if rain_sheltered(draw_cell(head)) or rain_sheltered(draw_cell(head+Vector2(0,8))):continue
			WeatherArt.draw_streak(self,head)
		else:
			WeatherArt.draw_ripple(self,land,WeatherArt.ripple_strength(sample))

func draw_drifting_weather(size:Vector2,snow:bool) -> void:
	if reduced_motion:
		if not snow:return
		var start:=Vector2i((camera/TILE).floor())
		var end:=start+Vector2i(ceili(size.x/TILE)+1,ceili(size.y/TILE)+1)
		var marks:=0
		for y in range(start.y,end.y):
			for x in range(start.x,end.x):
				if marks>=WeatherArt.MAX_STATIC_MARKS:return
				var cell:=Vector2i(x,y)
				var offset:=WeatherArt.static_mark(cell)
				if offset.x<0.0 or rain_sheltered(cell) or not World.land(cell,region_id()):continue
				WeatherArt.draw_drift(self,screen(Vector2(cell))+offset,0.45,true)
				marks+=1
		return
	for index in (WeatherArt.SNOW_FLAKES if snow else WeatherArt.WIND_FLECKS):
		var sample:=WeatherArt.drift(index,elapsed,camera,size,snow)
		var at:=Vector2(sample.x,sample.y)
		if not rain_sheltered(draw_cell(at)):WeatherArt.draw_drift(self,at,sample.z,snow)

static func build_tint(style: String) -> Color:
	return {"tea_house":Color("d1dca5"),"coast":Color("a3dbe8")}.get(style,Color.WHITE)

func roof_sprite(at:Vector2,alpha:=1.0,kind:="roof",style:="") -> void:
	if kind=="greenhouse_roof":
		draw_texture(preload("res://assets/bakery/greenhouse-roof.png"),at+Vector2(0,-8),Color(1,1,1,alpha))
		return
	draw_rect(Rect2(at+Vector2(0,-8),Vector2(32,32)),Color(0.62,0.46,0.30,alpha)*build_tint(style))
	for j in range(4):draw_rect(Rect2(at+Vector2(1,-7+j*8),Vector2(30,6)),Color(0.81,0.65,0.39,alpha)*build_tint(style))

func water_tile(at:Vector2,p:Vector2i) -> void:
	var c:=Color("76b9b4") if (p.x+p.y)%3==0 else Color("7fc3ba")
	draw_rect(Rect2(at,Vector2(32,32)),c)
	if absi(p.x*7+p.y*11)%5==0:
		draw_rect(Rect2(at+Vector2(5,13),Vector2(14,2)),Color("a8d9ca"))
		draw_rect(Rect2(at+Vector2(17,16),Vector2(7,2)),Color("a8d9ca"))

func draw_festival_table(at:Vector2) -> void:
	FurnitureArt.draw_sprite(self,at+Vector2(-12,3),"lamp")
	FurnitureArt.draw_sprite(self,at+Vector2(15,3),"lamp")
	var bloom:=preload("res://scripts/inventory_item_art.gd").icon("orange_blossom")
	if bloom!=null:
		for offset:Vector2 in [Vector2(3,-7),Vector2(18,-9)]:
			draw_texture_rect(bloom,Rect2(at+offset,Vector2(12,12)),false)

func draw_sheep_comfort(at:Vector2,frame:int) -> void:
	draw_texture_rect_region(preload("res://assets/ui-inventory/sheep-comfort.png"),Rect2(at.round(),Vector2(32,32)),Rect2(frame*32,0,32,32))

func draw_festival_visitor(at:Vector2,id:String) -> void:
	var feet:=at+Vector2(16,24)
	match id:
		"alei":
			var sprite:=preload("res://scripts/flower_resident_art.gd").resident_texture()
			if sprite!=null:draw_texture(sprite,feet-Vector2(16,48))
		"xinghe":LanyangLifeArt.draw_person(self,at)
		"chacha","potter":
			preload("res://scripts/tea_resident_art.gd").draw_resident(self,feet,"host" if id=="chacha" else "potter")

func draw_wind_chime_tree(at:Vector2) -> void:
	tree(at)
	if not data.get("festival_story_open",false):return
	var bloom:=preload("res://scripts/inventory_item_art.gd").icon("orange_blossom")
	if bloom!=null:
		for offset:Vector2 in [Vector2(4,-24),Vector2(16,-21),Vector2(21,-10),Vector2(7,-8)]:
			draw_texture_rect(bloom,Rect2(at+offset,Vector2(12,12)),false)
	if focused_label=="board":world_label(at+Vector2(16,-41),"風鈴樹開花了","")

func flower(at:Vector2,c:Color) -> void:
	draw_rect(Rect2(at+Vector2(1,2),Vector2(2,8)),Color("6e9e67"))
	draw_rect(Rect2(at+Vector2(-2,-1),Vector2(8,4)),c)
	draw_rect(Rect2(at+Vector2(0,-3),Vector2(4,8)),c)
	draw_rect(Rect2(at+Vector2(1,0),Vector2(2,2)),Color("daa466"))

func tree(at:Vector2) -> void:
	var pose:=tool_feedback.resource_pose(draw_cell(at),"axe",elapsed,reduced_motion or photograph_mode)
	var angle:float=pose.angle
	var pivot:=at+Vector2(16,29)
	var zoom_scale:=Vector2.ONE*view_zoom()
	draw_set_transform((pivot-pivot.rotated(angle))*zoom_scale,angle,zoom_scale)
	_draw_tree_sprite(at)
	draw_set_transform(Vector2.ZERO,0.0,zoom_scale)

func draw_resource_finish(at:Vector2,cell:Vector2i) -> void:
	if village_art==null or (region_id()==World.REGIONS.HOME and not VillagePreview.contains(cell)):return
	var ending:=tool_feedback.resource_finish(cell,elapsed,reduced_motion or photograph_mode)
	if ending.is_empty():return
	var is_tree:bool=ending.kind=="tree"
	var texture:Texture2D=village_art.props[absi(cell.x*17+cell.y*31)%4 if is_tree else 6]
	var size:=Vector2(texture.get_size())
	if not is_tree and region_id()=="jinguashi":size*=0.84+0.12*float((cell.x+cell.y)%3)
	var origin:Vector2=(at+Vector2(16-size.x/2,29-size.y)).round()
	var progress:float=ending.progress
	var tint:=Color(1,1,1,float(ending.alpha))
	if is_tree:
		tint.a*=showcase_tree_alpha(at)
		var pivot:=at+Vector2(16,29)
		var angle:=1.35*smoothstep(0.0,1.0,progress)
		var zoom_scale:=Vector2.ONE*view_zoom()
		draw_set_transform((pivot-pivot.rotated(angle))*zoom_scale,angle,zoom_scale)
		draw_texture_rect(texture,Rect2(origin,size),false,tint)
		draw_set_transform(Vector2.ZERO,0.0,zoom_scale)
	else:
		var source_size:=Vector2(texture.get_size())
		for half in 2:
			var shift:=Vector2((-1 if half==0 else 1)*roundf(7.0*progress),roundf(5.0*progress*progress))
			var source:=Rect2(Vector2(half*source_size.x/2,0),Vector2(source_size.x/2,source_size.y))
			var dest:=Rect2(origin+Vector2(half*size.x/2,0)+shift,Vector2(size.x/2,size.y))
			draw_texture_rect_region(texture,dest,source,tint)

func _draw_tree_sprite(at:Vector2) -> void:
	if village_art and (region_id()!=World.REGIONS.HOME or VillagePreview.contains(draw_cell(at))):
		var crown:=showcase_tree_alpha(at)
		if crown<1.0:
			var texture:Texture2D=village_art.props[absi(draw_cell(at).x*17+draw_cell(at).y*31)%4]
			draw_texture_rect(texture,village_tree_rect(at),false,Color(1,1,1,crown))
			return
		village_art.draw_tree(self,at,draw_cell(at))
		return
	Art.pixel(self,at,3,24,28,5,Color(0.20,0.35,0.21,0.18))
	Art.pixel(self,at,10,22,15,5,Color("795c43"))
	Art.pixel(self,at,13,1,9,25,Color("795c43"))
	Art.pixel(self,at,14,5,4,19,Color("ac8056"))
	Art.pixel(self,at,15,16,2,5,Color("c09863"))
	# Integer steps shape the broad lobes and the overhanging shadow.
	for rect in [Rect2i(9,-31,15,4),Rect2i(5,-27,23,5),Rect2i(1,-22,31,7),Rect2i(-2,-15,37,14),Rect2i(1,-1,31,8),Rect2i(6,7,21,4),Rect2i(12,11,12,3)]:
		draw_rect(Rect2(at+Vector2(rect.position),Vector2(rect.size)),Color("486c4c"))
	for rect in [Rect2i(10,-29,13,5),Rect2i(6,-25,21,6),Rect2i(3,-19,28,8),Rect2i(0,-12,33,10),Rect2i(3,-2,27,7),Rect2i(8,5,18,4)]:
		draw_rect(Rect2(at+Vector2(rect.position),Vector2(rect.size)),Color("629060"))
	for rect in [Rect2i(10,-27,10,3),Rect2i(6,-24,18,6),Rect2i(5,-19,14,6),Rect2i(8,-14,15,4),Rect2i(3,-9,11,5),Rect2i(19,-8,11,6)]:
		draw_rect(Rect2(at+Vector2(rect.position),Vector2(rect.size)),Color("79a86a"))
	Art.pixel(self,at,10,-23,6,2,Color("97ba78"))
	Art.pixel(self,at,5,-17,4,2,Color("97ba78"))
	Art.pixel(self,at,22,-5,5,2,Color("8eb676"))
	Art.pixel(self,at,9,1,3,3,Color("c3aa65"))
	Art.pixel(self,at,25,-12,2,2,Color("a3b773"))

## Same rect VillagePreview.draw_prop uses for the tree sprite of this cell.
func village_tree_rect(at:Vector2) -> Rect2:
	if village_art==null or village_art.props.size()!=16:return Rect2(at,Vector2(32,32))
	var cell:=draw_cell(at)
	var size:=Vector2((village_art.props[absi(cell.x*17+cell.y*31)%4] as Texture2D).get_size())
	return Rect2((at+Vector2(16-size.x/2,29-size.y)).round(),size)

## T071 家園布置題：tree crowns that cover the sign or the display plot are drawn
## see-through (like faded roofs) so the sign, the pieces and the target stay visible.
func showcase_tree_alpha(at:Vector2) -> float:
	if not showcase_fade_trees or village_art==null or village_art.props.size()!=16:return 1.0
	if region_id()!=World.REGIONS.HOME or not ShowcaseUI.plot_shown(data):return 1.0
	var area:=ShowcaseUI.plot_rect(self).merge(ShowcaseUI.sign_rect(self))
	return ShowcaseUI.TREE_ALPHA if village_tree_rect(at).intersects(area.grow(-2.0)) else 1.0

func sapling(at:Vector2,progress:float) -> void:
	ForestryArt.draw_sapling(self,at,progress)

func rock(at:Vector2) -> void:
	var pose:=tool_feedback.resource_pose(draw_cell(at),"pick",elapsed,reduced_motion or photograph_mode)
	var zoom_scale:=Vector2.ONE*view_zoom()
	draw_set_transform(pose.shift*zoom_scale,0.0,zoom_scale)
	_draw_rock_sprite(at)
	draw_set_transform(Vector2.ZERO,0.0,zoom_scale)

func _draw_rock_sprite(at:Vector2) -> void:
	if region_id()=="jinguashi" and village_art:
		JinguashiArt.draw_rock_ledge(self,at,village_art,draw_cell(at))
		return
	if village_art and (region_id()!=World.REGIONS.HOME or VillagePreview.contains(draw_cell(at))):
		village_art.draw_prop(self,at,6)
		return
	draw_rect(Rect2(at+Vector2(2,23),Vector2(28,6)),Color(0.2,0.3,0.3,0.15))
	draw_rect(Rect2(at+Vector2(3,9),Vector2(25,17)),Color("869b98"))
	draw_rect(Rect2(at+Vector2(8,4),Vector2(15,21)),Color("aab9ac"))
	draw_rect(Rect2(at+Vector2(7,8),Vector2(12,7)),Color("c1cbb8"))
	draw_rect(Rect2(at+Vector2(21,15),Vector2(5,8)),Color("758c89"))

func grass(at:Vector2) -> void:
	if village_art and (region_id()!=World.REGIONS.HOME or VillagePreview.contains(draw_cell(at))):
		village_art.draw_prop(self,at,4 if (draw_cell(at).x+draw_cell(at).y)%3==0 else 7)
		return
	for x in [7,13,20]:
		draw_rect(Rect2(at+Vector2(x,12+x%5),Vector2(4,13)),Color("709c5e"))
		draw_rect(Rect2(at+Vector2(x-3,16),Vector2(4,4)),Color("83af6c"))

func ground_tile(at:Vector2,kind:String,style:="") -> void:
	if kind=="spring_pebble_path":
		draw_texture_rect_region(preload("res://assets/village-preview/terrain.png"),Rect2(at,Vector2(32,32)),Rect2(96,64,32,32),Color("f3c99c"))
		return
	var tint:=build_tint(style)
	if village_art and (region_id()!=World.REGIONS.HOME or VillagePreview.contains(draw_cell(at))):
		village_art.draw_tile(self,at,10 if kind=="floor" else 11,tint)
		return
	if kind=="floor":
		draw_rect(Rect2(at,Vector2(32,32)),Color("987650")*tint)
		for j in range(4):draw_rect(Rect2(at+Vector2(1,j*8+1),Vector2(30,6)),Color("c6a174")*tint)
	else:
		draw_rect(Rect2(at+Vector2(1,1),Vector2(30,30)),Color("b6b7a3")*tint)
		draw_rect(Rect2(at+Vector2(3,3),Vector2(25,24)),Color("d5d1b7")*tint)

func crop_tile(at:Vector2,crop:Dictionary) -> void:
	draw_crop_tile(at,crop)
	if crop.get("owner","")!=player_id:return
	var definition:Dictionary=World.CROPS.get(crop.get("kind",""),{})
	if definition.is_empty() or float(crop.growth)<float(definition.time):return
	if World.farming_level(data.get("players",{}).get(player_id,{}))>=World.MASTER_FARMING_LEVEL:
		draw_texture(preload("res://assets/bakery/ripe-sparkle.png"),at+Vector2(22,1))

## 這格作物是否正在等季節（只讀快照；規則在 World.plot_dormant）。
func crop_dormant(tile:Vector2i,crop:Dictionary) -> bool:
	var roof=data.get("roofs",{}).get(World.key(tile),{})
	return World.plot_dormant(crop,roof if roof is Dictionary else {},region_id(),tile,float(data.get("time",0.0)))

func draw_crop_tile(at:Vector2,crop:Dictionary) -> void:
	var wet:bool=crop.wet
	if village_art and (region_id()!=World.REGIONS.HOME or VillagePreview.contains(draw_cell(at))):
		village_art.draw_tile(self,at,7 if wet else 15)
	else:
		draw_rect(Rect2(at+Vector2(1,1),Vector2(30,30)),Color("8b6a4e") if wet else Color("b68b62"))
		for j in range(3):draw_rect(Rect2(at+Vector2(4,6+j*8),Vector2(24,2)),Color("735c47") if wet else Color("9f774f"))
		Art.pixel(self,at,2,2,28,2,Color("a48362") if wet else Color("d3a377"))
		Art.pixel(self,at,2,28,28,2,Color("6f5746") if wet else Color("94704f"))
		for soil in [Vector2i(6,10),Vector2i(23,18),Vector2i(11,24)]:
			Art.pixel(self,at,soil.x,soil.y,3,1,Color("c5a584") if wet else Color("e1b98b"))
	if crop.kind=="":return
	var tile:=draw_cell(at)
	var quiet:=reduced_motion or photograph_mode
	at+=farm_feedback.sprout_offset(World.key(tile),elapsed,quiet)
	if crop_art:
		var sway:=0 if quiet else CropSprites.breeze_offset(elapsed,tile)
		var press:=tool_feedback.crop_press(tile,elapsed,quiet)
		if press>0:
			# Transform only the plant art around its root. Never transform terrain,
			# camera, labels or subsequent objects; restore the view zoom at once.
			var root_at:=(at+CropSprites.FOOT).round()
			draw_set_transform(root_at*view_zoom(),0.0,Vector2(view_zoom(),view_zoom()*(1.0-press/29.0)))
			crop_art.draw_crop(self,-CropSprites.FOOT,crop,crop_dormant(tile,crop),0)
			draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*view_zoom())
		else:crop_art.draw_crop(self,at,crop,crop_dormant(tile,crop),sway)
		return
	var progress:float=float(crop.growth)/float(World.CROPS[crop.kind].time)
	if crop.kind=="pumpkin":
		# Q05: pumpkin only has bakery-atlas art (no geometric stand-in).
		BakeryArt.draw_crop(self,at,3 if progress>=1.0 else (2 if progress>=0.65 else (1 if progress>=0.25 else 0)))
		return
	if progress<0.25:
		draw_rect(Rect2(at+Vector2(14,13),Vector2(4,10)),Color("7aaa59"))
		draw_rect(Rect2(at+Vector2(10,12),Vector2(7,4)),Color("b1ca73"))
		draw_rect(Rect2(at+Vector2(17,9),Vector2(6,5)),Color("95b76a"))
	elif crop.kind=="wheat":
		var c:=Color("e9c774") if progress>=1 else Color("a3b56a")
		for x in [10,16,22]:
			draw_rect(Rect2(at+Vector2(x,6),Vector2(2,20)),Color("91a052"))
			Art.pixel(self,at,x-2,6,6,8,c.darkened(0.14))
			Art.pixel(self,at,x-1,4,4,10,c)
			Art.pixel(self,at,x-2,8,2,2,c.lightened(0.25))
			Art.pixel(self,at,x+2,11,2,2,c.lightened(0.25))
	elif crop.kind=="lettuce":
		draw_rect(Rect2(at+Vector2(7,11),Vector2(20,15)),Color("5d965e"))
		draw_rect(Rect2(at+Vector2(9,8),Vector2(15,14)),Color("93bf75"))
		draw_rect(Rect2(at+Vector2(13,9),Vector2(7,10)),Color("b6d68c"))
	elif crop.kind=="tomato":
		draw_rect(Rect2(at+Vector2(15,5),Vector2(3,22)),Color("8d7955"))
		draw_rect(Rect2(at+Vector2(6,9),Vector2(21,12)),Color("65985d"))
		for fruit in [Vector2i(8,13),Vector2i(20,16),Vector2i(16,7)]:
			var color:=Color("dc725b") if progress>=1 else Color("a7bc6e")
			Art.pixel(self,at,fruit.x,fruit.y+1,7,4,color.darkened(0.22))
			Art.pixel(self,at,fruit.x+1,fruit.y,5,6,color)
			Art.pixel(self,at,fruit.x+1,fruit.y+1,2,2,color.lightened(0.38))
	elif crop.kind=="potato":
		draw_rect(Rect2(at+Vector2(7,9),Vector2(18,13)),Color("79a160"))
		if progress>=1:
			draw_rect(Rect2(at+Vector2(7,21),Vector2(9,6)),Color("c7a16f"))
			draw_rect(Rect2(at+Vector2(18,19),Vector2(9,7)),Color("d7b47f"))
	elif crop.kind=="carrot":
		draw_rect(Rect2(at+Vector2(13,11),Vector2(8,14)),Color("df9d5c") if progress>=0.65 else Color("80a965"))
		draw_rect(Rect2(at+Vector2(15,24),Vector2(4,4)),Color("d88c4c"))
		draw_rect(Rect2(at+Vector2(8,7),Vector2(18,5)),Color("77a863"))
	else:
		if progress>0.65:
			draw_rect(Rect2(at+Vector2(11,15),Vector2(12,11)),Color("f1e5d0"))
			draw_rect(Rect2(at+Vector2(14,25),Vector2(6,3)),Color("decaab"))
		draw_rect(Rect2(at+Vector2(15,8),Vector2(4,11)),Color("619c59"))
		draw_rect(Rect2(at+Vector2(7,7),Vector2(10,5)),Color("94bd6d"))
		draw_rect(Rect2(at+Vector2(19,4),Vector2(7,7)),Color("80b362"))
	if progress>=1:
		Art.pixel(self,at,26,1,2,6,Color("ffe7a0"))
		Art.pixel(self,at,24,3,6,2,Color("ffe7a0"))

func quilt_bed_sprite(at:Vector2,vertical:bool,pigment:String,render_scale:=1.0) -> void:
	var art:=preload("res://assets/ui-life/inn-quilt-bed-vertical.png") if vertical else preload("res://assets/ui-life/inn-quilt-bed.png")
	var frame:=Vector2(art.get_width(),art.get_height()/2.0)
	var box:=Rect2(at,frame*render_scale)
	var tint:=Color.WHITE
	if pigment=="blue_dye":tint=Color(0.60,0.85,1.45)
	elif pigment=="orange_dye":tint=Color(1.22,0.79,0.55)
	draw_texture_rect_region(art,box,Rect2(Vector2.ZERO,frame))
	draw_texture_rect_region(art,box,Rect2(Vector2(0,frame.y),frame),tint)

func build_placement_offsets(kind:String) -> Array:
	if kind in Industry.FIXED_SQUARE_STATIONS or kind in Industry.EXPANDABLE_STATIONS or kind in Industry.ORIENTABLE_FOOTPRINTS:
		return Industry.station_cells(kind,kind==Industry.INN_BED)
	if kind in World.RESIDENT_GOALS.DOUBLE_BENCHES:return [Vector2i.ZERO,Vector2i.RIGHT]
	return [Vector2i.ZERO]

func build_placement_blocks(anchor:Vector2i,kind:String) -> Dictionary:
	var blocked:Dictionary={}
	for offset:Vector2i in build_placement_offsets(kind):
		var tile:=anchor+offset
		var key:=World.key(tile)
		if not World.land(tile,region_id()):blocked[tile]="需要陸地"
		elif kind in World.BLUEPRINT_DESIGN.ROOF_KINDS:
			if data.get("roofs",{}).has(key):blocked[tile]="已有屋頂"
			elif kind=="roof" and data.get("ground",{}).get(key,{}).get("type")!="floor":blocked[tile]="需先鋪木地板"
		elif data.get("crops",{}).has(key):blocked[tile]="已有作物"
		elif data.get("objects",{}).has(key):blocked[tile]="已有物件"
		elif kind in World.BLUEPRINT_DESIGN.GROUND_KINDS and data.get("ground",{}).has(key):blocked[tile]="已有鋪面"
	return blocked

func draw_build_placement_art(at:Vector2) -> void:
	var tint:=Color(Color.WHITE,0.58)
	if Industry.SPRINKLER_CAPACITIES.has(building):
		AutomationArt.draw_sprinkler(self,at,{},0.0,true,building,tint)
	elif building in IndustryArt.DEVICES:
		IndustryArt.draw_device(self,at,building,{},0.0,true,tint)
	else:
		match building:
			"forester":ForestryArt.draw_station(self,at,{},0.0,true,tint)
			Industry.CLAY_KILN:draw_texture(preload("res://assets/bakery/clay-kiln.png"),at+Vector2(0,-16),tint)
			Industry.SMELTER:draw_texture(preload("res://assets/industry/small-smelter.png"),at+Vector2(0,-12),tint)
			Industry.TOWER_KIND,"water_pipe":
				var mask:=0
				var directions:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
				for index in directions.size():
					var device:Dictionary=data.objects.get(World.key(target+directions[index]),{})
					if device.get("owner","")==player_id and device.get("type","") in Industry.NETWORK:
						mask|=1<<index
				if building==Industry.TOWER_KIND:TowerArt.draw_tower(self,at,{},mask,tint)
				else:
					var pipe:=IndustryArt.pipe_texture(mask)
					if pipe!=null:draw_texture(pipe,at,tint)
			_:FurnitureArt.draw_placement(self,at,building,build_tint(placement_style))

func object_sprite(at:Vector2,kind:String,object_data:Dictionary={}) -> void:
	if kind==World.Squirrel.ORNAMENT:
		draw_texture_rect(World.Squirrel.texture(World.Squirrel.KIT),Rect2(at+Vector2(7,-12),Vector2(18,22)),false)
		return
	if kind==Industry.FOOT_BATH:
		if Industry.square_part(object_data)>0:return
		var art:=preload("res://assets/ui-life/inn-stone-footbath-vertical.png") if Industry.is_vertical(object_data) else preload("res://assets/ui-life/inn-stone-footbath.png")
		draw_texture(art,at)
		var own_seat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
		if own_seat.get("cell")!=World.key(draw_cell(at)) and data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			world_label(at+Vector2(art.get_width()/2.0,-14),"暖石泡腳池",focused_label)
		return
	if kind==Industry.INN_BED:
		if Industry.square_part(object_data)<=0:
			quilt_bed_sprite(at-Vector2(0,9),Industry.is_vertical(object_data),str(object_data.get("dye","")))
		return
	if kind==World.INN_TEA_TABLE:
		var atlas:=preload("res://assets/ui-life/inn-tea-table.png")
		draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-12),Vector2(32,36)),Rect2(0,0,32,36))
		var index:=0
		for tea:String in World.INN_TEA_ITEMS:
			var tint:=Color("ffe0ad") if tea==World.GINGER_TEA else Color.WHITE
			for cup in int(object_data.get("items",{}).get(tea,0)):
				draw_texture_rect_region(atlas,Rect2(at+Vector2(8+index*10,-2),Vector2(8,8)),Rect2(32,0,8,8),tint)
				index+=1
		var table_key:=World.key(draw_cell(at))
		if focused_label==table_key:world_label(at+Vector2(16,-22),"暖薑茶小桌",table_key)
		return
	if kind==World.WELCOME_SIGN.KIND:
		draw_texture(preload("res://assets/ui-life/inn-welcome-sign.png"),at+Vector2(0,-10))
		var sign_key:=World.key(draw_cell(at))
		if focused_label==sign_key:world_label(at+Vector2(16,-22),"迎賓牌",sign_key)
		return
	if kind=="towel_rack":
		draw_texture(preload("res://assets/ui-life/towel-rack.png"),at+Vector2(0,-14))
		return
	if kind==Industry.ANIMAL_COLLECTOR:
		draw_texture(preload("res://assets/automation/animal-collector.png"),at+Vector2(0,-16))
		var count:=int(object_data.get("collector_count",0))
		if count>0:
			var item:=World.AnimalCollector.item_for(str(object_data.collector_animal))
			var icon:=preload("res://scripts/inventory_item_art.gd").icon(item)
			if icon:draw_texture_rect(icon,Rect2(at+Vector2(8,-22),Vector2(16,16)),false)
		var tile:=World.key(draw_cell(at))
		if focused_label==tile:world_label(at+Vector2(16,-25),"動物收集器",tile)
		return
	if kind in Industry.TWO_CELL_STATIONS:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		var art:Texture2D
		if kind==Industry.DYE_TABLE:
			art=preload("res://assets/bakery/dye-table-vertical.png") if vertical else preload("res://assets/bakery/dye-table.png")
		elif kind==Industry.FABRIC_SCREEN:
			art=preload("res://assets/ui-life/inn-fabric-screen-vertical.png") if vertical else preload("res://assets/ui-life/inn-fabric-screen.png")
		elif kind==Industry.LUGGAGE_RACK:
			art=preload("res://assets/ui-life/inn-luggage-rack-vertical.png") if vertical else preload("res://assets/ui-life/inn-luggage-rack.png")
		else:
			art=preload("res://assets/automation/assembly-table-vertical.png") if vertical else preload("res://assets/automation/assembly-table.png")
		draw_texture(art,at+Vector2(0,-16))
		if kind==Industry.LUGGAGE_RACK:
			var items:Dictionary=object_data.get("items",{})
			var slot:=0
			for item:String in items:
				var icon:Texture2D=preload("res://scripts/inventory_item_art.gd").icon(item)
				for count in int(items[item]):
					var offset:=Vector2(8,-13+slot*32) if vertical else Vector2(8+slot*32,-13)
					if icon:draw_texture_rect(icon,Rect2(at+offset,Vector2(16,16)),false)
					slot+=1
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			world_label(at+Vector2(art.get_width()/2.0,-20),World.BUILD[kind].name,focused_label)
		return
	if kind==Industry.CLAY_KILN:
		var part:=Industry.square_part(object_data)
		if part>0:return
		draw_texture(preload("res://assets/bakery/clay-kiln.png"),at+Vector2(0,-16))
		if not object_data.get("processing",{}).get("active",{}).is_empty():
			var glow:=0.65 if reduced_motion else 0.56+0.16*sin(elapsed*3.8)
			draw_rect(Rect2(at+Vector2(25,43),Vector2(14,4)),Color(1.0,0.52,0.18,glow))
		var device_key:=World.key(draw_cell(at))
		var focus_in_footprint:bool=data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at)
		if focused_label==device_key or focus_in_footprint:
			world_label(at+Vector2(32,-19),"陶窯",focused_label)
		return
	if kind==World.INDUSTRY.SMELTER:
		if int(object_data.get("smelter_part",0))==0:
			draw_texture(preload("res://assets/industry/small-smelter.png"),at+Vector2(0,-12))
			if not object_data.get("processing",{}).get("active",{}).is_empty():
				var intensity:=0.75 if reduced_motion else 0.68+sin(elapsed*3.5)*0.12
				draw_rect(Rect2(at+Vector2(17,32),Vector2(23,7)),Color(1.0,0.54,0.20,intensity))
		return
	if kind==World.RESIDENT_GOALS.MASTER_BENCH:
		if not object_data.get("bench_end",false):
			var asset:=preload("res://assets/ui-life/master-bench-vertical.png") if object_data.get("bench_vertical",false) else preload("res://assets/ui-life/master-bench.png")
			draw_texture(asset,at+Vector2(0,-7))
		return
	if kind==World.RESIDENT_GOALS.STONE_BENCH:
		if not object_data.get("bench_end",false):
			var asset:=preload("res://assets/ui-life/spring-stone-bench-vertical.png") if object_data.get("bench_vertical",false) else preload("res://assets/ui-life/spring-stone-bench.png")
			draw_texture(asset,at+Vector2(0,-10))
		return
	if kind==World.WALL_FIXTURES.LIGHT:
		draw_texture(preload("res://assets/ui-life/warm-lamp-niche.png"),at+Vector2(0,-15))
		return
	if kind in World.RESIDENT_GOALS.FESTIVAL_BELL_KINDS:
		var age:=float(data.get("time",0.0))-float(object_data.get("bell_at",-5.0))
		if kind==World.RESIDENT_GOALS.SHELL_CHIME:
			var art:=preload("res://assets/ui-inventory/wangan-shell-chime.png")
			var frame:=Rect2(at+Vector2(0,-12),Vector2(32,44))
			draw_texture_rect_region(art,frame,Rect2(0,0,32,44))
			if not reduced_motion and age>=0.0 and age<1.5:
				frame.position.x+=roundf(sin(age*14.0)*3.0*(1.0-age/1.5))
			draw_texture_rect_region(art,frame,Rect2(32,0,32,44))
			return
		if kind==World.RESIDENT_GOALS.CERAMIC_CHIME:
			draw_texture(preload("res://assets/ui-life/ceramic-eave-chime.png"),at+Vector2(0,-12))
			if age>=0.0 and age<1.5:
				var glow:=Color(1.0,0.85,0.66,1.0-age/1.5)
				draw_line(at+Vector2(5,1),at+Vector2(8,4),glow,1.0)
				draw_line(at+Vector2(24,4),at+Vector2(27,1),glow,1.0)
			return
		var texture:=preload("res://assets/ui-inventory/memorial-bell-copper.png") if kind==World.RESIDENT_GOALS.FESTIVAL_BELL else preload("res://assets/ui-inventory/memorial-bell-reward.png")
		draw_texture(texture,at+Vector2(0,-6))
		if age<1.5:
			var offset:=0.0 if reduced_motion else sin(age*13.0)*3.0
			var glow:=Color(1.0,0.86,0.48,1.0-age/1.5)
			draw_line(at+Vector2(2-offset,10),at+Vector2(-1-offset,8),glow,1.0)
			draw_line(at+Vector2(26+offset,10),at+Vector2(29+offset,8),glow,1.0)
		return
	if kind=="conveyor":
		var cargo:Dictionary=object_data.get("items",{})
		var blocked_reason:=""
		if object_data.get("enabled",false) and not cargo.is_empty():
			var ahead:Vector2i=draw_cell(at)+World.LOGISTICS.DIRECTIONS[int(object_data.dir)]
			var destination:Dictionary=data.objects.get(World.key(ahead),{})
			blocked_reason=World.LOGISTICS.delivery_block(object_data,destination,destination)
		LogisticsArt.draw_belt(self,at,object_data,float(data.get("time",0)),reduced_motion or photograph_mode,not blocked_reason.is_empty())
		if not cargo.is_empty():
			var icon:Texture2D=load("res://scripts/inventory_item_art.gd").icon(str(cargo.keys()[0]))
			if icon:draw_texture_rect(icon,Rect2(at+Vector2(8,8),Vector2(16,16)),false)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:
			var direction:String=["↑","→","↓","←"][int(object_data.get("dir",1))]
			var caption:="輸送帶 %s · %s"%[direction,World.NAMES.get(object_data.get("filter","wood"),"")]
			if not object_data.get("enabled",false):caption+=" · 已停止"
			elif not blocked_reason.is_empty():caption+=" · "+blocked_reason
			world_label(at+Vector2(16,-12),caption,device_key)
		return
	if kind=="forester":
		ForestryArt.draw_station(self,at,object_data,float(data.get("time",0)),reduced_motion or photograph_mode)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:
			var caption:="林務工作站 · "+Forestry.field_status(object_data)
			tiller_world.state=data
			tiller_world._region=region_id()
			var advice:=ForestryUI.operation_advice(tiller_world,World.cell(device_key),object_data)
			if not str(advice.short).is_empty():caption="林務工作站 · "+str(advice.short)
			world_label(at+Vector2(16,-30),caption,device_key)
		return
	if kind=="water_pipe":
		var pipe_key:=World.key(draw_cell(at))
		var mask:=10
		if not object_data.is_empty():
			mask=0
			var offsets:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
			for index in offsets.size():
				var neighbor:Dictionary=data.objects.get(World.key(draw_cell(at)+offsets[index]),{})
				if neighbor.get("owner","")==object_data.get("owner","") and neighbor.get("type","") in Industry.NETWORK:mask|=1<<index
		var info:Dictionary=supply_networks.get(pipe_key,{})
		var supplied:bool=info.get("flow_visible",false)
		IndustryArt.draw_pipe(self,at,mask,supplied,float(data.get("time",0)),reduced_motion or photograph_mode,elapsed)
		if not object_data.is_empty() and show_target and target==draw_cell(at):
			world_label(at+Vector2(16,-8),Industry.pipe_caption(mask,info),"")
		return
	# 第 40 章分流閘：水管接頭＋木閘框（三種設定外觀不同；靜態），預覽與一般繪製都畫。
	if kind==Industry.GATE_KIND:
		var gate_mask:=10
		if not object_data.is_empty():
			gate_mask=0
			var gate_offsets:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
			for index in gate_offsets.size():
				var neighbor:Dictionary=data.objects.get(World.key(draw_cell(at)+gate_offsets[index]),{})
				if neighbor.get("owner","")==object_data.get("owner","") and neighbor.get("type","") in Industry.NETWORK:gate_mask|=1<<index
		var mode:=RevisitArt.mode_of(object_data)
		RevisitArt.draw_gate(self,at,mode,gate_mask)
		var gate_key:=World.key(draw_cell(at))
		if not object_data.is_empty() and focused_label==gate_key:world_label(at+Vector2(16,-10),"分流閘 · "+Industry.gate_mode_name(mode),gate_key)
		return
	# 第 40 章水塔：地面水管接頭＋架高的水塔（32×48，水位窗與出水／只蓄水外觀；靜態），預覽與一般繪製都畫。
	if kind==Industry.TOWER_KIND:
		var tower_mask:=10
		if not object_data.is_empty():
			tower_mask=0
			var tower_offsets:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
			for index in tower_offsets.size():
				var neighbor:Dictionary=data.objects.get(World.key(draw_cell(at)+tower_offsets[index]),{})
				if neighbor.get("owner","")==object_data.get("owner","") and neighbor.get("type","") in Industry.NETWORK:tower_mask|=1<<index
		TowerArt.draw_tower(self,at,object_data,tower_mask)
		var tower_key:=World.key(draw_cell(at))
		if not object_data.is_empty() and focused_label==tower_key:
			var enabled:bool=object_data.get("enabled",false)
			var caption:="水塔 · 水 %d／%d · %s"%[int(object_data.get("water",0)),Industry.TOWER_CAPACITY,Industry.tower_enabled_name(enabled)]
			var quota:=Industry.tower_quota(object_data)
			if enabled and quota>0:
				var day:=Industry.tower_day(float(data.get("time",0.0)))
				var left:=maxi(0,quota-Industry.tower_quota_used(object_data,day))
				caption+=(" · 配額剩 %d"%left) if left>0 else " · 配額已用完"
			world_label(at+Vector2(16,-26),caption,tower_key)
		return
	# 第 40 章分水木牌（蘭陽回訪紀念）：程式繪製 32px 圖，任何訪客可互動看來源。
	if kind==World.LANYANG_REVISIT.PLAQUE_KIND:
		RevisitArt.draw_plaque(self,at)
		var plaque_key:=World.key(draw_cell(at))
		if not object_data.is_empty() and focused_label==plaque_key:world_label(at+Vector2(16,-8),World.LANYANG_REVISIT.PLAQUE_NAME,plaque_key)
		return
	# 第 40 章礦燈（金瓜石回訪紀念）：程式繪製 32px 圖（靜態，只是裝飾），任何訪客可互動看來源。
	if kind==World.JINGUASHI_REVISIT.LANTERN_KIND:
		JgArt.draw_lantern(self,at)
		var lantern_key:=World.key(draw_cell(at))
		if not object_data.is_empty() and focused_label==lantern_key:world_label(at+Vector2(16,-8),World.JINGUASHI_REVISIT.LANTERN_NAME,lantern_key)
		return
	# 第 40 章茶陶組（貓空與鶯歌回訪紀念）：程式繪製 32px 圖（靜態，只是裝飾），任何訪客可互動看來源。
	if kind==World.TEA_REVISIT.TEAWARE_KIND:
		TeaRevisitArt.draw_teaware(self,at)
		var teaware_key:=World.key(draw_cell(at))
		if not object_data.is_empty() and focused_label==teaware_key:world_label(at+Vector2(16,-2),World.TEA_REVISIT.TEAWARE_NAME,teaware_key)
		return
	# 第 40 章鹽籃（臺南北門回訪紀念）：程式繪製 32px 圖（靜態，只是裝飾），任何訪客可互動看來源。
	if kind==World.SALT_REVISIT.BASKET_KIND:
		SaltRevisitArt.draw_basket(self,at)
		var basket_key:=World.key(draw_cell(at))
		if not object_data.is_empty() and focused_label==basket_key:world_label(at+Vector2(16,-6),World.SALT_REVISIT.BASKET_NAME,basket_key)
		return
	if kind=="mine_drill":
		MineDrillArt.draw(self,at,object_data,float(data.get("time",0)),elapsed,reduced_motion)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:world_label(at+Vector2(16,-20),"礦脈採掘機",device_key)
		return
	if kind=="waterworks":
		WaterworksArt.draw(self,at,object_data,float(data.get("time",0)),elapsed,reduced_motion)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:world_label(at+Vector2(16,-27),"水力加工台",device_key)
		return
	if kind in ["seed_maker","loom"]:
		var part:=Industry.square_part(object_data)
		if part>0:return
		var art:=preload("res://assets/bakery/loom.png") if kind=="loom" else preload("res://assets/bakery/seed-maker.png")
		if part==0:
			draw_texture_rect(art,Rect2(at+Vector2(0,-32),Vector2(64,96)),false)
		else:
			draw_texture(art,at+Vector2(0,-16))
		var device_key:=World.key(draw_cell(at))
		var focus_on_loom:bool=part==0 and data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at)
		if focused_label==device_key or focus_on_loom:
			world_label(at+Vector2(32,-20) if part==0 else at+Vector2(16,-20),World.BUILD[kind].name,focused_label)
		return
	if kind=="glass_furnace":
		var part:=Industry.square_part(object_data)
		if part>0:return
		preload("res://scripts/glass_furnace_art.gd").draw(self,at,object_data,float(data.get("time",0)),reduced_motion,part==0)
		var device_key:=World.key(draw_cell(at))
		var focus_on_furnace:bool=part==0 and data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at)
		if focused_label==device_key or focus_on_furnace:
			world_label(at+Vector2(32,-20) if part==0 else at+Vector2(16,-20),World.BUILD[kind].name,focused_label)
		return
	if kind=="jam_pot":
		draw_texture(preload("res://assets/bakery/jam-pot.png"),at+Vector2(0,-16))
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:world_label(at+Vector2(16,-20),"果醬鍋",device_key)
		return
	if kind=="mill":
		# Q05 flour mill: the formal PNG (same placement as the furniture route)
		# plus work overlays classified from this authoritative snapshot object at
		# the snapshot world time; read-only, never a geometric placeholder.
		var mill_status:Dictionary=BakeryArt.draw_mill_runtime(self,at,object_data,float(data.get("time",0)),elapsed,reduced_motion)
		var mill_key:=World.key(draw_cell(at))
		if focused_label==mill_key:
			world_label(at+Vector2(16,-26),World.BUILD[kind].name+BakeryArt.MillFeedback.caption(mill_status),mill_key)
		return
	if kind in ["water_tank","water_pump","sawmill","charcoal_kiln"]:
		IndustryArt.draw_device(self,at,kind,object_data,float(data.get("time",0)),reduced_motion or photograph_mode,Color.WHITE,elapsed)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:
			var caption:String=World.BUILD[kind].name
			if kind=="water_tank":caption+=" · 水 %d／48"%int(object_data.get("water",0))
			elif kind in ["sawmill","charcoal_kiln"]:
				caption+=ProcessingQueueUI.world_status(object_data,float(data.get("time",0)))
			world_label(at+Vector2(16,-26),caption,device_key)
		return
	if Industry.SPRINKLER_CAPACITIES.has(kind):
		var now:=float(data.get("time",0))
		var object_key:=World.key(draw_cell(at))
		var spray_age:=elapsed-float(sprinkler_sprays.get(object_key,-INF))
		AutomationArt.draw_sprinkler(self,at,object_data,spray_age,reduced_motion or photograph_mode,kind)
		if focused_label==object_key:
			world_label(at+Vector2(16,-22),"%s · 水 %d／%d · %s"%[World.BUILD[kind].name,object_data.get("water",0),Industry.SPRINKLER_CAPACITIES[kind],Industry.sprinkler_status(object_data,now)],object_key)
		return
	if kind=="supply_box":
		draw_texture(preload("res://assets/bakery/supply-box.png"),at)
		return
	if kind=="expedition_tent":
		draw_texture(preload("res://assets/bakery/expedition-tent.png"),at+Vector2(0,-16))
		var tent_key:=World.key(draw_cell(at))
		if focused_label==tent_key:world_label(at+Vector2(16,-23),World.BUILD[kind].name,tent_key)
		return
	if kind in ["author_sign","author_shelf"]:
		var art:Texture2D=preload("res://assets/bakery/author-sign.png") if kind=="author_sign" else preload("res://assets/bakery/author-shelf.png")
		draw_texture(art,at+Vector2(0,-16))
		var display_key:=World.key(draw_cell(at))
		if focused_label==display_key:world_label(at+Vector2(16,-26),World.BUILD[kind].name,display_key)
		return
	if kind=="fish_display":
		draw_texture(preload("res://assets/bakery/fish-display.png"),at+Vector2(0,-16))
		var display_key:=World.key(draw_cell(at))
		if focused_label==display_key:world_label(at+Vector2(16,-26),World.BUILD[kind].name,display_key)
		return
	if kind==World.RESIDENT_GOALS.BASIC_TEA_SET:
		draw_texture(preload("res://assets/ui-inventory/basic-tea-set.png"),at+Vector2(0,-6))
		return
	if kind=="wood_mailbox":
		draw_texture(preload("res://assets/ui-inventory/wood-mailbox.png"),at+Vector2(0,-12))
		var mailbox_key:=World.key(draw_cell(at))
		if focused_label==mailbox_key:world_label(at+Vector2(16,-26),World.BUILD[kind].name,mailbox_key)
		return
	if kind in World.RESIDENT_GOALS.WARDROBES:
		draw_texture(preload("res://assets/ui-inventory/inn-lattice-wardrobe.png") if kind==World.RESIDENT_GOALS.INN_WARDROBE else preload("res://assets/ui-inventory/guest-wardrobe.png"),at+Vector2(0,-13))
		var wardrobe_key:=World.key(draw_cell(at))
		if focused_label==wardrobe_key:world_label(at+Vector2(16,-26),World.BUILD[kind].name,wardrobe_key)
		return
	if kind=="sketch_easel":
		draw_texture(preload("res://assets/ui-inventory/sketch-easel.png"),at+Vector2(0,-16))
		var easel_key:=World.key(draw_cell(at))
		if focused_label==easel_key:world_label(at+Vector2(16,-27),World.BUILD[kind].name,easel_key)
		return
	if kind=="rope_rack":
		draw_texture(preload("res://assets/ui-inventory/rope-rack.png"),at+Vector2(0,-16))
		var rack_key:=World.key(draw_cell(at))
		if focused_label==rack_key:world_label(at+Vector2(16,-26),World.BUILD[kind].name,rack_key)
		return
	if kind=="master_flower_bed":
		draw_texture(preload("res://assets/bakery/master-flower-bed.png"),at+Vector2(0,-16))
		return
	if kind=="greenhouse_rack":
		draw_texture(preload("res://assets/bakery/greenhouse-rack.png"),at+Vector2(0,-16))
		return
	if kind in ["ore_display","flower_pot"] and FurnitureArt.draw_sprite(self,at,kind):return
	# T071 紀念票兌換裝飾：程式繪製的 32px 圖，預覽美術與一般繪製都畫（其他家具在一般
	# 繪製也有自己的圖形）。
	if SouvenirArt.has_kind(kind) and SouvenirArt.draw(self,at,kind):return
	# T066 居民紀念小物（十二種）：同樣是程式繪製的 32px 圖。
	if KeepsakeArt.has_kind(kind) and KeepsakeArt.draw(self,at,kind):return
	var pigment:String=object_data.get("dye","")
	if Industry.FURNITURE_DYES.has(pigment):
		var palette:=Color(0.66,0.9,1.35) if pigment=="blue_dye" else Color(1.18,0.79,0.54)
		if FurnitureArt.draw_sprite(self,at,kind,build_tint(str(object_data.get("style","")))*palette):return
	if village_art:
		var obj:Dictionary=data.objects.get(World.key(draw_cell(at)),{})
		if (kind!="door" or not obj.get("open",false)) and FurnitureArt.draw_sprite(self,at,kind,build_tint(str(obj.get("style","")))):
			if kind=="stove":_draw_cooking_feedback(at,obj)
			return
	if village_art and VillagePreview.contains(draw_cell(at)) and kind in ["long_bench","planter"]:
		village_art.draw_prop(self,at,{"long_bench":11,"planter":4}[kind],0.75 if kind=="planter" else 1.0)
		return
	if kind in ["long_bench","sofa"]:
		draw_rect(Rect2(at+Vector2(1,0),Vector2(30,16)),Color("ab845d"))
		draw_rect(Rect2(at+Vector2(1,12),Vector2(30,12)),Color("d9b580") if kind=="long_bench" else Color("c89580"))
		for x in [3,25]:draw_rect(Rect2(at+Vector2(x,24),Vector2(4,6)),Color("8d694c"))
		if kind=="sofa":
			Art.pixel(self,at,3,2,26,11,Color("bb806d"))
			Art.pixel(self,at,4,3,11,9,Color("d9a18b"))
			Art.pixel(self,at,17,3,11,9,Color("d9a18b"))
			Art.pixel(self,at,1,11,5,11,Color("bb806d"))
			Art.pixel(self,at,26,11,5,11,Color("bb806d"))
			Art.pixel(self,at,7,14,18,2,Color("ebbaa0"))
		else:
			Art.pixel(self,at,3,2,26,2,Color("d4a777"))
			Art.pixel(self,at,2,8,28,1,Color("987253"))
			Art.pixel(self,at,4,17,24,1,Color("ad825b"))
	elif kind=="planter":
		draw_rect(Rect2(at+Vector2(2,15),Vector2(28,13)),Color("be9869"))
		for x in [8,16,24]:flower(at+Vector2(x,10),Color("efd59c") if x==16 else Color("d99d91"))
	elif kind=="sign":
		draw_rect(Rect2(at+Vector2(14,8),Vector2(4,22)),Color("92724f"))
		draw_rect(Rect2(at+Vector2(2,-5),Vector2(28,19)),Color("d5b27e"))
		draw_rect(Rect2(at+Vector2(7,2),Vector2(18,3)),Color("8b7757"))
	elif kind in ["wall","window","door"]:
		var tint:=build_tint(str(object_data.get("style","")))
		draw_rect(Rect2(at+Vector2(0,-14),Vector2(32,43)),Color("946c4f")*tint)
		for j in range(4):draw_rect(Rect2(at+Vector2(1,-12+j*10),Vector2(30,8)),Color("c29468")*tint)
		draw_rect(Rect2(at+Vector2(0,-16),Vector2(32,4)),Color("deba83")*tint)
		if kind=="window":
			draw_rect(Rect2(at+Vector2(7,-9),Vector2(18,20)),Color("6c9290")*tint)
			draw_rect(Rect2(at+Vector2(9,-7),Vector2(14,16)),Color("b5d8c8")*tint)
			draw_rect(Rect2(at+Vector2(15,-9),Vector2(3,20)),Color("dfb985")*tint)
		if kind=="door":
			var obj:Dictionary=data.objects.get(World.key(draw_cell(at)),{})
			if obj.get("open",false):
				draw_rect(Rect2(at+Vector2(4,-10),Vector2(24,39)),Color("728e64")*tint)
				draw_rect(Rect2(at+Vector2(2,-10),Vector2(6,39)),Color("d0a36c")*tint)
			else:
				draw_rect(Rect2(at+Vector2(4,-10),Vector2(24,39)),Color("aa7e53")*tint)
				draw_rect(Rect2(at+Vector2(22,8),Vector2(4,4)),Color("f3d794")*tint)
	elif kind in ["chest","private_chest"]:
		draw_rect(Rect2(at+Vector2(3,9),Vector2(26,20)),Color("916448"))
		draw_rect(Rect2(at+Vector2(3,5),Vector2(26,10)),Color("cb9a5c"))
		draw_rect(Rect2(at+Vector2(6,7),Vector2(4,21)),Color("e5c181"))
		draw_rect(Rect2(at+Vector2(23,7),Vector2(4,21)),Color("e5c181"))
		draw_rect(Rect2(at+Vector2(14,13),Vector2(5,6)),Color("e8d69d"))
		if kind=="private_chest":draw_rect(Rect2(at+Vector2(12,12),Vector2(9,9)),Color("739ba2"))
	elif kind=="bench":
		draw_rect(Rect2(at+Vector2(4,15),Vector2(4,15)),Color("8f6a4c"))
		draw_rect(Rect2(at+Vector2(24,15),Vector2(4,15)),Color("8f6a4c"))
		draw_rect(Rect2(at+Vector2(0,6),Vector2(32,12)),Color("cba16b"))
		draw_rect(Rect2(at+Vector2(5,3),Vector2(11,4)),Color("6b8e85"))
		draw_rect(Rect2(at+Vector2(19,1),Vector2(3,12)),Color("7d6048"))
	elif kind=="bed":
		draw_rect(Rect2(at+Vector2(3,0),Vector2(26,31)),Color("9e7955"))
		draw_rect(Rect2(at+Vector2(5,3),Vector2(22,24)),Color("e7dcae"))
		draw_rect(Rect2(at+Vector2(6,12),Vector2(20,15)),Color("ca8c79"))
		draw_rect(Rect2(at+Vector2(8,5),Vector2(16,7)),Color("fff0cd"))
		Art.pixel(self,at,8,11,16,2,Color("dac29b"))
		Art.pixel(self,at,7,14,18,2,Color("e9b79c"))
		Art.pixel(self,at,7,25,18,2,Color("a76e60"))
		for x in [10,16,22]:Art.pixel(self,at,x,20,2,2,Color("e7b89f"))
	elif kind=="lamp":
		draw_rect(Rect2(at+Vector2(14,-5),Vector2(4,35)),Color("8e6c4e"))
		draw_rect(Rect2(at+Vector2(8,-10),Vector2(16,15)),Color("bf9963"))
		draw_rect(Rect2(at+Vector2(11,-7),Vector2(10,9)),Color("ffe6a1"))
	elif kind=="table":
		draw_rect(Rect2(at+Vector2(5,13),Vector2(4,17)),Color("8e6949"))
		draw_rect(Rect2(at+Vector2(23,13),Vector2(4,17)),Color("8e6949"))
		draw_rect(Rect2(at+Vector2(1,2),Vector2(30,19)),Color("b68c5c"))
		draw_rect(Rect2(at+Vector2(3,1),Vector2(26,14)),Color("dfbb83"))
		Art.pixel(self,at,4,3,24,1,Color("efd39d"))
		Art.pixel(self,at,6,7,20,1,Color("c79d6a"))
		Art.pixel(self,at,5,12,22,1,Color("c79d6a"))
		Art.pixel(self,at,7,15,18,2,Color("c79d6a"))
	elif kind=="chair":
		draw_rect(Rect2(at+Vector2(8,-1),Vector2(16,16)),Color("c39b68"))
		draw_rect(Rect2(at+Vector2(6,12),Vector2(20,10)),Color("dfbb83"))
		draw_rect(Rect2(at+Vector2(8,22),Vector2(4,8)),Color("99744d"))
		draw_rect(Rect2(at+Vector2(20,22),Vector2(4,8)),Color("99744d"))
	elif kind=="stove":
		draw_rect(Rect2(at+Vector2(2,1),Vector2(28,28)),Color("909b91"))
		draw_rect(Rect2(at+Vector2(4,4),Vector2(24,8)),Color("b5bbaa"))
		draw_rect(Rect2(at+Vector2(9,15),Vector2(14,13)),Color("5c625a"))
		draw_rect(Rect2(at+Vector2(7,-3),Vector2(18,8)),Color("636f66"))
		var obj:Dictionary=data.objects.get(World.key(draw_cell(at)),{})
		_draw_cooking_feedback(at,obj)

func _draw_cooking_feedback(at:Vector2,obj:Dictionary) -> void:
	var status:=CookingFeedback.draw(self,at,obj,float(data.get("time",0)),elapsed,reduced_motion or photograph_mode)
	if int(status.ready)>0:
		world_label(at+Vector2(16,-18),"料理好了 · %d 鍋待領"%int(status.ready),World.key(draw_cell(at)))

func person_sprite(at:Vector2,shirt:Color,style:="guest",facing:=Vector2i.DOWN,phase:=0.0,walking_now:=false,blue_workwear:=false,milu_apron:=false,cart_push:=0.0) -> void:
	character_label_obstacles.append(LabelLayout.body_rect(at))
	if character_art:
		character_art.draw_person(self,at,shirt,style,facing,phase,walking_now,reduced_motion,blue_workwear,milu_apron,cart_push)
		return
	Art.person(self,at,Color("648eaa") if blue_workwear else shirt,style,facing,phase,walking_now,reduced_motion,milu_apron)

func board(at:Vector2) -> void:
	if village_art:
		village_art.draw_prop(self,at,9)
		world_label(at+Vector2(16,-28),"公告板","board")
		return
	draw_rect(Rect2(at+Vector2(4,12),Vector2(4,20)),Color("8c684a"))
	draw_rect(Rect2(at+Vector2(25,12),Vector2(4,20)),Color("8c684a"))
	draw_rect(Rect2(at+Vector2(-2,-12),Vector2(36,30)),Color("936d4d"))
	draw_rect(Rect2(at+Vector2(2,-8),Vector2(28,22)),Color("ead8aa"))
	draw_rect(Rect2(at+Vector2(7,-4),Vector2(10,13)),Color("fff2cf"))
	draw_rect(Rect2(at+Vector2(20,-2),Vector2(6,8)),Color("bdcc9b"))
	world_label(at+Vector2(16,-21),"公告板","board")

func shop(at:Vector2) -> void:
	if village_art:
		village_art.draw_prop(self,at,8)
		if character_art:
			person_sprite(at+Vector2(16,27),Color("b9a66d"),"xiaoli")
			village_art.draw_shop_occluders(self,at)
		CommunityArt.draw_shop_detail(self,at,data)
		world_label(at+Vector2(16,-39),"小栗・渡口小店" if data.get("picnic",false) else ("小栗・種子攤" if character_art else "種子攤"),"shop")
		return
	draw_rect(Rect2(at+Vector2(-8,12),Vector2(48,19)),Color("a57b55"))
	draw_rect(Rect2(at+Vector2(-8,9),Vector2(48,6)),Color("d9b17a"))
	draw_rect(Rect2(at+Vector2(-7,-16),Vector2(3,27)),Color("96734c"))
	draw_rect(Rect2(at+Vector2(34,-16),Vector2(3,27)),Color("96734c"))
	person_sprite(at+Vector2(15,11),Color("8faf8c"))
	draw_rect(Rect2(at+Vector2(-9,-27),Vector2(48,11)),Color("db987d"))
	for j in range(4):draw_rect(Rect2(at+Vector2(-9+j*12,-27),Vector2(6,11)),Color("f2dfb9"))
	draw_rect(Rect2(at+Vector2(-2,6),Vector2(10,7)),Color("e7c47f"))
	world_label(at+Vector2(16,-37),"種子攤","shop")

func draw_rabbit_basket(at:Vector2) -> void:
	var rabbit:Dictionary=data.get("players",{}).get(player_id,{}).get(World.Rabbit.FIELD,{})
	if rabbit.get("following",false):return
	var basket:=preload("res://scripts/salt_revisit_art.gd").empty_basket_texture()
	draw_texture_rect(basket,Rect2(at+Vector2(-12,-16),Vector2(24,21)),false)
	draw_texture(World.Rabbit.texture(elapsed,reduced_motion,not rabbit.is_empty()),at+Vector2(-7,-17))

func draw_cat_home(at:Vector2) -> void:
	var cat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.Cat.FIELD,{})
	if not cat.get("following",false):draw_cat(at.round(),cat)
	if focused_label=="companion_cat":world_label(at+Vector2(0,-18),World.Cat.NAME,"companion_cat")

func draw_cat(at:Vector2,cat:Dictionary) -> void:
	var age:=float(data.get("time",0))-float(cat.get("last_pet",-30))
	var reacting:=age>=0.0 and age<1.35
	if reacting and cat.get("last_play")=="yarn":
		var travel:=0.0 if reduced_motion else sin(age/1.35*PI)
		draw_texture(World.Cat.yarn_texture(),(at+Vector2(8+travel*15,-5)).round())
		at.x+=roundf(travel*10)
	draw_texture(World.Cat.texture(reacting and cat.get("last_play")=="pet"),at-Vector2(8,12))

func draw_duck(station:Vector2,record:Dictionary,reaction_age:float) -> void:
	var art=World.LIVESTOCK.Duck
	for offset:Vector2 in [Vector2(1.1,-0.35),Vector2(2.8,0.15),Vector2(1.13,1.75),Vector2(2.85,1.7)]:
		var reeds_at:=screen(Vector2(art.SITE)+offset).round()
		draw_texture(art.reed_texture(),reeds_at-Vector2(5,6))
	var swimming:bool=not record.get("managed_pen",false) and reaction_age>=LivestockArt.PET_SECONDS
	var foot:=station
	if swimming:
		foot=screen(art.swim_position(float(data.time),reduced_motion)).round()
		draw_rect(Rect2(foot+Vector2(-12,-2),Vector2(8,1)),Color("9ed5cc"))
		draw_rect(Rect2(foot+Vector2(-17,1),Vector2(12,1)),Color("57aec0"))
	else:
		LivestockArt.draw_pet_heart(self,foot,reaction_age,reduced_motion)
	draw_texture(art.texture(),foot-Vector2(9,9))
	if int(record.get("ready",0))>0:
		draw_texture(art.texture(true),station+Vector2(4,-6))

func draw_seal_site() -> void:
	var at:=screen(Vector2(World.Seal.SITE)+Vector2(0.5,0.72)).round()
	var present:=World.Seal.present(float(data.time))
	if present:
		var blink:=not reduced_motion and fposmod(elapsed,3.4)>3.1
		draw_texture(World.Seal.texture(blink),at-Vector2(13,12))
	elif not photograph_mode:
		FurnitureArt.draw_sprite(self,at-Vector2(16,23),"sign")
	if focused_label==World.Seal.POINT:
		world_label(at+Vector2(0,-18),World.Seal.NAME if present else "南岸海豹觀察點",World.Seal.POINT)

func draw_squirrel_site() -> void:
	var at:=screen(Vector2(World.Squirrel.SITE)+Vector2(0.5,0.65)).round()
	var present:=World.Squirrel.present(float(data.time))
	if present:
		var hop:=0.0 if reduced_motion else roundf(maxf(0.0,sin(elapsed*3.5))*3.0)
		draw_texture(World.Squirrel.texture(),at-Vector2(9,12+hop))
	else:FurnitureArt.draw_sprite(self,at-Vector2(16,23),"sign")
	if focused_label==World.Squirrel.POINT:
		world_label(at+Vector2(0,-21),World.Squirrel.NAME if present else "林邊觀察站",World.Squirrel.POINT)

func draw_hedgehog_site() -> void:
	var site:=World.Hedgehog.site(data)
	var at:=screen(Vector2(site)+Vector2(0.5,0.5)).round()
	var player:Dictionary=data.get("players",{}).get(player_id,{})
	var status:=World.Hedgehog.phase(player,float(data.time))
	draw_rect(Rect2(at+Vector2(-7,2),Vector2(14,4)),Color("7a574d"))
	draw_rect(Rect2(at+Vector2(-8,0),Vector2(16,3)),Color("ddbe98"))
	draw_rect(Rect2(at+Vector2(-5,1),Vector2(10,2)),Color("b68369"))
	if status in ["waiting","visiting"]:
		var radish:=MarketItemArt.icon("radish")
		if radish:draw_texture_rect(radish,Rect2(at+Vector2(-5,-8),Vector2(10,10)),false)
	if status in ["visiting","visited"]:
		var nibble:=status=="visiting" and not reduced_motion and fposmod(elapsed,1.2)>0.8
		draw_texture(World.Hedgehog.texture(nibble),at+Vector2(-22,-7))
	if focused_label==World.Hedgehog.POINT:
		world_label(at+Vector2(0,-18),"刺蝟食盤" if status in ["empty","waiting"] else World.Hedgehog.NAME,World.Hedgehog.POINT)

func draw_fox_clues() -> void:
	var viewer:Dictionary=data.get("players",{}).get(player_id,{})
	if region_id()==World.Fox.REGION:
		var fox_at:=screen(Vector2(World.Fox.SITE)+Vector2(0.5,0.65)).round()
		if not viewer.get(World.Fox.FIELD,{}).get("following",false):
			draw_texture(World.Fox.texture(),fox_at-Vector2(10,12))
		if focused_label=="companion_fox":world_label(fox_at+Vector2(0,-22),World.Fox.NAME,"companion_fox")
		for id:String in World.Fox.points(viewer):
			if not id.begins_with("fox_track:"):continue
			var at:=screen(Vector2(World.cell(id.trim_prefix("fox_track:")))+Vector2(0.5,0.5)).round()
			for mark:Vector2 in [Vector2(-6,0),Vector2(0,-5),Vector2(6,1)]:
				draw_rect(Rect2(at+mark,Vector2(4,3)),Color("b99a6f"))
			if focused_label==id:world_label(at+Vector2(0,-12),"觀察足印",id)
	elif region_id()=="home":
		for tile:Vector2i in World.Fox.visible_clues(World,data,viewer):
			var at:=screen(Vector2(tile)+Vector2(0.5,0.2)).round()
			var offset:=0.0 if reduced_motion else roundf(sin(elapsed*4.0)*3.0)
			draw_texture(World.Fox.texture(),at+Vector2(-10,-23+offset),Color(1,1,1,0.92))

func draw_following_pet(id:String,position:Vector2,pet:Dictionary={},kind:="rabbit") -> void:
	var heading:=Vector2(facings.get(id,Vector2i.DOWN))
	var side:=Vector2(-heading.y,heading.x)
	tiller_world.state=data
	tiller_world._region=region_id()
	var spot:=Vector2.INF
	for flank:Vector2 in [side,-side]:
		var target_at:=position-heading*0.48+flank*0.58
		if not tiller_world.blocked(Vector2i(target_at.floor())):
			spot=target_at
			break
	if spot==Vector2.INF:
		if not photograph_mode:return
		spot=position+Vector2(0.55,0.18)
	var bounce:=0.0
	if not reduced_motion and not photograph_mode and walking.get(id,false):bounce=roundf(absf(sin(elapsed*10.0))*4.0)
	var foot:=(screen(spot)-Vector2(0,bounce if kind=="rabbit" else bounce*0.5)).round()
	match kind:
		"fox":draw_texture(World.Fox.texture(),foot-Vector2(10,11))
		"dog":draw_texture(World.Dog.texture(pet.get("last_play")=="toy"),foot-Vector2(10,12))
		"cat":draw_cat(foot,pet)
		_:draw_texture(World.Rabbit.texture(elapsed,reduced_motion),foot-Vector2(7,9))

func chicken(at:Vector2) -> void:
	if character_art and character_art.draw_chicken(self,at,reduced_motion,elapsed):return
	draw_rect(Rect2(at+Vector2(-6,1),Vector2(14,3)),Color(0.3,0.4,0.2,0.15))
	draw_rect(Rect2(at+Vector2(-7,-8),Vector2(14,10)),Color("fff0d2"))
	draw_rect(Rect2(at+Vector2(2,-13),Vector2(8,10)),Color("fff6dc"))
	draw_rect(Rect2(at+Vector2(3,-16),Vector2(5,4)),Color("d78a75"))
	draw_rect(Rect2(at+Vector2(9,-8),Vector2(4,3)),Color("d9ab62"))
	draw_rect(Rect2(at+Vector2(6,-10),Vector2(2,2)),Color("584d3c"))

func draw_drill_placement()->void:
	var target_at:=screen(Vector2(target))+Vector2(16,-15)
	if region_id() not in World.MINES.IDS:
		label_at(target_at,"需在合作礦場的礦層內放置")
		return
	var drill:=World.MINE_DRILL
	var actor:Dictionary=data.players.get(player_id,{})
	var reason:=""
	if int(data.get("mine_depths",{}).get("unlocked",1))<5:reason="先完成第四層礦道工程"
	elif data.objects.values().any(func(obj):return obj.type=="mine_drill"):reason="本層已設置一台採掘機"
	elif int(actor.get("inventory",{}).get("mine_drill_kit",0))<1:reason="背包沒有採掘機套件"
	for offset:Vector2i in drill.DIRECTIONS:
		var cell:Vector2i=drill.NODE-offset
		var key:=World.key(cell)
		var cell_at:=screen(Vector2(cell))
		var blocked:bool=not World.land(cell,region_id()) or World.REGIONS.protected(cell,region_id()) or data.objects.has(key) or data.crops.has(key) or data.get("forest",{}).has(key) or (World.base_resource(cell,region_id())!="" and not data.removed.has(key))
		var occupied:bool=data.players.values().any(func(person):return Vector2(person.x,person.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<0.8)
		var valid:=reason.is_empty() and not blocked and not occupied
		var tint:=Color("b3d894") if valid else Color("db9980")
		draw_rect(Rect2(cell_at+Vector2(2,2),Vector2(28,28)),Color(tint,0.16))
		draw_rect(Rect2(cell_at+Vector2(2,2),Vector2(28,28)),tint,false,1.0)
		if cell!=target:continue
		if valid:
			var ghost:=MineDrillArt.frame_texture(0,drill.placement(cell))
			if ghost:draw_texture(ghost,cell_at-Vector2(8,8),Color(1,1,1,0.7))
		label_at(target_at,reason if not reason.is_empty() else ("這格有物件或島民" if blocked or occupied else "合法工位 · 鑽頭朝向礦脈"))
	if drill.placement(target)<0:label_at(target_at,"選指定礦脈上下左右的空格")

func label_at(at:Vector2,text:String) -> void:
	var width:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	draw_style_box(label_box(),Rect2(at+Vector2(-width/2-6,-16),Vector2(width+12,24)))
	draw_string(font,at+Vector2(-width/2,1),text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff2ce"))

func label_box() -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=Color(0.20,0.32,0.26,0.88)
	box.set_corner_radius_all(4)
	return box

func lanyang_cell_occupied(p:Vector2i) -> bool:
	var key:=World.key(p)
	for field in ["objects","crops","ground","roofs","forest"]:
		if data.get(field,{}).has(key):return true
	return World.base_resource(p,region_id())!="" and not data.get("removed",{}).has(key)

func lanyang_gardener_cell() -> Vector2i:
	for p in [Vector2i(35,29),Vector2i(35,28),Vector2i(32,29)]:
		if not lanyang_cell_occupied(p):return p
	return Vector2i(-1,-1)

## Beimen salt pans: the 20 flat pans (after ground, before tall rows).
func draw_salt_pans() -> void:
	for entry in SaltWorldArt.draw_pans(self,screen(Vector2.ZERO),data,elapsed,reduced_motion):
		if entry[1]==focused_label:world_label(entry[0],SaltWorldArt.site_title(entry[1]),entry[1])

## Beimen salt pans: tall props/阿曬 on row `y` plus their labels. 阿曬 always
## carries a name; gates, machines, signs and the bus stop only when focused.
func draw_salt_row(y:int) -> void:
	for entry in SaltWorldArt.draw_row(self,screen(Vector2.ZERO),y,data,elapsed,reduced_motion):
		var id:String=entry[1]
		var title:=SaltWorldArt.site_title(id)
		if id=="transfer":
			var gate:=World.TRANSIT.point_at(region_id(),World.SALT_PAN.TRANSFER)
			id="transit:"+gate if not gate.is_empty() else "travel"
			title=str(World.TRANSIT.points(region_id()).get(gate,{}).get("label","鹽田站牌"))
		elif id==SaltWorldArt.BRINE_TANK_SITE:
			# 第 40 章儲滷槽：「儲滷槽・n／30 桶」 (shared level, visible to everyone).
			var level:=World.SALT_BRINE.level(data)
			title=SaltBrineArt.label(level)
			if not reduced_motion:
				var tank_at:Vector2=entry[0]-SaltBrineArt.LABEL_OFFSET
				SaltBrineArt.draw_transfer(self,tank_at,level,brine_transfer_delta,elapsed-brine_transfer_started)
		if id==focused_label or id in SaltWorldArt.RESIDENT_SITES:world_label(entry[0],title,id)

## Tianwei nursery: tall props/residents on row `y` plus their labels. Residents
## (阿蕾, 星禾) always carry a name; stations only when focused.
func draw_flower_row(y:int) -> void:
	for entry in FlowerWorldArt.draw_row(self,screen(Vector2.ZERO),y,data,elapsed,reduced_motion):
		var site:String=entry[1]
		var id:="flower:"+site
		if site=="transfer":
			var gate:=World.TRANSIT.point_at(region_id(),World.FLOWER_NURSERY.TRANSFER)
			id="transit:"+gate if not gate.is_empty() else "travel"
		if id==focused_label or site in FlowerWorldArt.RESIDENT_SITES:
			world_label(entry[0],str(FlowerWorldArt.SITE_LABELS.get(site,"")),id)

const INTERACTIVE_OBJECTS:=["chest","private_chest","supply_box","bench","bed","inn_quilt_bed","inn_stone_footbath","door","stove","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_pump","sawmill","charcoal_kiln","forester","conveyor","waterworks","mine_drill","mill","seed_maker","loom","glass_furnace","small_smelter","clay_kiln","dye_table","assembly_table","animal_collector","sketch_easel","guest_wardrobe","inn_lattice_wardrobe","wood_mailbox","rope_rack","fish_display","author_sign","author_shelf","expedition_tent","diversion_gate","water_tower","water_share_plaque","mine_lantern","tea_ware","salt_basket","long_bench","master_bench","spring_stone_bench","sign","festival_memorial_bell","keepsake_lingpopo_memorial","ceramic_eave_chime","shell_chime","inn_welcome_sign","inn_tea_table","inn_luggage_rack"]

## Beimen focus: SaltWorldArt.focus plus the 第 40 章儲滷槽 cell ("salt:brine_tank"),
## same rule (strict nearest within SaltWorldArt.RADIUS; ties keep the earlier site).
## Once SaltWorldArt.sites() lists the tank itself this adds nothing.
func salt_focus(position:Vector2) -> String:
	var transit_points:Dictionary=World.TRANSIT.points(region_id())
	var key:=SaltWorldArt.focus(position,transit_points,data.get("objects",{}),INTERACTIVE_OBJECTS)
	var sites:=SaltWorldArt.sites()
	if key==SaltWorldArt.BRINE_TANK_SITE or sites.has(SaltWorldArt.BRINE_TANK_SITE):return key
	var tank:=position.distance_to(Vector2(World.SALT_BRINE.TANK)+Vector2(0.5,0.5))
	if tank>=SaltWorldArt.RADIUS:return key
	if key.is_empty():return SaltWorldArt.BRINE_TANK_SITE
	var other:=Vector2(INF,INF)
	if sites.has(key):other=sites[key]
	elif key.begins_with("transit:"):
		var stop:Variant=transit_points.get(key.trim_prefix("transit:"))
		if stop is Dictionary and (stop as Dictionary).has("cell"):other=Vector2((stop as Dictionary).cell)+Vector2(0.5,0.5)
	elif key.count(",")==1:other=Vector2(World.cell(key))+Vector2(0.5,0.5)
	return SaltWorldArt.BRINE_TANK_SITE if tank<position.distance_to(other) else key

func interaction_focus() -> String:
	if region_id()==World.MINES.MUD_REGION and World.MINES.mud_engaged(data.players.get(player_id,{}),float(data.time)):
		return "mine_mud"
	if region_id()==World.FLOWER_NURSERY.REGION:
		var flower_visitor:Dictionary=data.get("players",{}).get(player_id,{})
		if flower_visitor.is_empty():return ""
		return FlowerWorldArt.focus(Vector2(flower_visitor.x,flower_visitor.y),World.TRANSIT.points(region_id()),data.get("objects",{}),INTERACTIVE_OBJECTS)
	if region_id()==World.SALT_PAN.REGION:
		var salt_visitor:Dictionary=data.get("players",{}).get(player_id,{})
		if salt_visitor.is_empty():return ""
		return salt_focus(Vector2(salt_visitor.x,salt_visitor.y))
	if TransitArt.NAMES.has(region_id()) or region_id() in ["maokong","yingge"]:
		var visitor:Dictionary=data.get("players",{}).get(player_id,{})
		if visitor.is_empty():return ""
		var position:=Vector2(visitor.x,visitor.y)
		var radius:=3.2
		var closest:=""
		for gate in World.TRANSIT.points(region_id()):
			var stop:Dictionary=World.TRANSIT.points(region_id())[gate]
			var distance:=position.distance_to(Vector2(stop.cell)+Vector2(0.5,0.5))
			if distance<=radius:
				radius=distance
				closest="transit:"+str(gate)
		var tea_sites:=tea_points(region_id(),data)
		for cell:Vector2i in tea_sites:
			var distance:=position.distance_to(Vector2(cell)+Vector2(0.5,0.5))
			if distance<radius:
				radius=distance
				closest="tea:"+tea_sites[cell]
		var resident:Dictionary=World.STATION_LIFE.RESIDENTS.get(region_id(),{})
		if not resident.is_empty() and position.distance_to(Vector2(resident.cell)+Vector2(0.5,0.5))<=radius:return "station_resident:"+region_id()
		return closest
	if not data.players.has(player_id):return ""
	var player:Dictionary=data.players[player_id]
	var pos:=Vector2(player.x,player.y)
	var home:=region_id()==World.REGIONS.HOME
	var mining:=region_id()=="jinguashi"
	var bobo_sites:Dictionary=World.Village.Workshop.sites(data) if mining else {}
	var depth:=int(region_id().trim_prefix("mine_")) if region_id().begins_with("mine_") else 0
	var festival:Dictionary=data.get("festival",{})
	if home and festival.get("active",false) and pos.distance_to(Vector2(World.Festival.target(festival))+Vector2(0.5,0.5))<=1.6:
		return "bell"
	# T071 家園布置題：已加入時手邊的地塊格優先（與 main._interact 相同）。
	if home and ShowcaseUI.view_target(self)!=ShowcaseUI.NO_CELL:return ShowcaseUI.PLOT_POINT
	# Match the interaction order and range in main.gd.
	var points:Dictionary={"board":Vector2(40.5,29.5),"shop":Vector2(43.5,29.5),"animal":Vector2(45.7,33.8)} if home else {}
	if region_id()==World.Fox.REGION:points.merge(World.Fox.points(data.get("players",{}).get(player_id,{})))
	if region_id()==World.REGIONS.LANYANG:
		points["gardener"]=Vector2(World.LANYANG_LIFE.SERVICE)+Vector2(0.5,0.5)
		for p in World.LANYANG_LIFE.BLOCKAGES:
			if not data.get("lanyang_life",{}).get("cleared",{}).has(World.key(p)):
				points["ditch:"+World.key(p)]=Vector2(p)+Vector2(0.5,0.5)
		if data.get("lanyang_life",{}).get("repaired",false):
			for p in World.HISTORY_MEMORY.OBSERVATIONS:points["memory:"+World.key(p)]=Vector2(p)+Vector2(0.5,0.5)
	if mining:
		points["mine_site:entry"]=Vector2(World.MINES.ENTRY)+Vector2(0.5,0.5)
		for p in World.JINGUASHI.NODES:points["mine:"+World.key(p)]=Vector2(p)+Vector2(0.5,0.5)
		points["bobo_sort"]=Vector2(bobo_sites.table)+Vector2(0.5,0.5)
		points[GoldPanArt.POINT]=Vector2(World.GOLD_PANNING.SITE)+Vector2(0.5,0.5)
		points[OreRouteArt.POINT]=Vector2(World.ORE_ROUTE.cart_cell(World.ORE_ROUTE.stage(data)))+Vector2(0.5,0.5)
	if depth>0:
		var survey_point:Vector2i=World.MINE_SURVEY.POINTS[depth]
		if not data.objects.has(World.key(survey_point)):points["mine_survey"]=Vector2(survey_point)+Vector2(0.5,0.5)
		var stations:Dictionary={"up":World.MINES.UP,"down":World.MINES.DOWN,"rest":World.MINES.REST,"service":World.MINES.SERVICE}
		for station in stations:
			if station!="down" or depth<World.MINES.MAX_DEPTH:points["mine_site:"+station]=Vector2(stations[station])+Vector2(0.5,0.5)
		if depth>World.MINES.SHALLOW_DEPTH:points["mine_site:lift"]=Vector2(World.MINES.LIFT)+Vector2(0.5,0.5)
		var mud_phase:=int(data.players.get(player_id,{}).get("mud_alcove",0))
		if depth==1 and mud_phase<2:
			var mud_cell:=World.MINES.MUD_GATE if mud_phase==0 else World.MINES.MUD_REWARD
			points["mine_mud"]=Vector2(mud_cell)+Vector2(0.5,0.5)
		for p in World.MINES.NODES:points["extract:"+World.key(p)]=Vector2(p)+Vector2(0.5,0.5)
	if depth==0 and (not home or data.get("picnic",false)):
		var travel_cell:=World.REGIONS.exit_cell(region_id())
		var gate:=World.TRANSIT.point_at(region_id(),travel_cell)
		points["transit:"+gate if not gate.is_empty() else "travel"]=Vector2(travel_cell)+Vector2(0.5,0.5)
	var shipping_cell:=World.SHIPPING.cell_for(data)
	if home and shipping_cell!=World.SHIPPING.NO_CELL:points["shipping"]=Vector2(shipping_cell)+Vector2(0.5,0.5)
	var table_cell:=World.COMMUNITY.table_cell(data)
	if home and table_cell!=Vector2i(-1,-1):points["community"]=Vector2(table_cell)+Vector2(0.5,0.5)
	if home and data.get("picnic",false):
		for id in World.LIVESTOCK.ANIMALS:
			points["livestock:"+id]=Vector2(World.LIVESTOCK.ANIMALS[id].cell)+Vector2(0.5,0.5)
		points["companion_cat"]=Vector2(World.Cat.site(data))+Vector2(0.5,0.5)
		points["companion_dog"]=Vector2(World.Dog.SITE)+Vector2(0.5,0.5)
	# 既有居民、走近型居民、物件的加入順序與 main.gd 的互動點一致（等距時名牌與互動對象相同）。
	for resident in World.Village.ids_for_region(region_id()):
		if resident=="xiaoli":continue
		var resident_cell:Vector2i=World.Village.resident_cell(data,resident)
		points[resident]=Vector2(resident_cell)+Vector2(0.5,0.5)
	if region_id()==World.REGIONS.HOME:points["aru_park"]=Vector2(World.RESIDENT_GOALS.ARU_PARK_VIEW)+Vector2(0.5,0.5)
	if home:points[World.WANGAN_MEMORY.POINT]=Vector2(World.WANGAN_MEMORY.SITE)+Vector2(0.5,0.5)
	if home and World.WANGAN_MEMORY.courtyard_available(data):points[World.WANGAN_MEMORY.COURT_POINT]=Vector2(World.WANGAN_MEMORY.COURT_SIGN)+Vector2(0.5,0.5)
	if home:points[World.Hedgehog.POINT]=Vector2(World.Hedgehog.site(data))+Vector2(0.5,0.5)
	if home:points[World.Squirrel.POINT]=Vector2(World.Squirrel.SITE)+Vector2(0.5,0.5)
	if home:points[World.Seal.POINT]=Vector2(World.Seal.SITE)+Vector2(0.5,0.5)
	if home and World.Deer.present(data):points[World.Deer.POINT]=Vector2(World.Deer.site(data))+Vector2(0.5,0.5)
	if home:points[World.WANGAN_MEMORY.WEIR_POINT]=Vector2(World.WANGAN_MEMORY.WEIR_SITE)+Vector2(0.5,0.5)
	if home:points[World.WANGAN_MEMORY.WEIR_LOOKOUT_POINT]=Vector2(World.WANGAN_MEMORY.WEIR_LOOKOUT)+Vector2(0.5,0.5)
	if home:points[World.SEAWEED_POINT]=Vector2(World.SEAWEED_CELL)+Vector2(0.5,0.5)
	if home:points[World.WANGAN_COAST.SHELL_POINT]=Vector2(World.WANGAN_COAST.SHELL_CELL)+Vector2(0.5,0.5)
	if home and data.get("wangan_star_walk",false):
		points[World.WANGAN_COAST.STAR_SAND_POINT]=Vector2(World.WANGAN_COAST.STAR_SAND)+Vector2(0.5,0.5)
		points[World.WANGAN_COAST.DOCK_ORDERS_POINT]=Vector2(World.WANGAN_COAST.DOCK_ORDERS)+Vector2(0.5,0.5)
	elif home:points[World.WANGAN_COAST.STAR_REPAIR_POINT]=Vector2(World.WANGAN_COAST.STAR_REPAIR)+Vector2(0.5,0.5)
	for walk_id:String in World.RESIDENT_BOND.WALK_UP:
		var walk_spot:Array=World.bond_place(data,walk_id)
		if str(walk_spot[0])==region_id() and World.RESIDENT_BOND.present(data,walk_id):points[walk_id]=Vector2(walk_spot[1])+Vector2(0.5,0.5)
	if region_id()==World.WARM_SPRINGS.REGION:
		points[World.WARM_SPRINGS.BATH_ACTION]=Vector2(World.WARM_SPRINGS.BATH_ENTRANCE)+Vector2(0.5,0.5)
		points[World.WARM_SPRINGS.INN_POINT]=Vector2(World.WARM_SPRINGS.INN_DOOR)+Vector2(0.5,0.5)
		if World.WARM_SPRINGS.in_inn(data.players.get(player_id,{})):World.WARM_SPRINGS.room_interactions(points)
	var market_cell:=MarketStall.active_cell(data) if home else MarketStall.NO_CELL
	if market_cell!=MarketStall.NO_CELL:points["market"]=Vector2(market_cell)+Vector2(0.5,0.5)
	# T071 豐收接力：告示牌、菜箱、三個分類籃，緊接在市集攤位之後（與 main.gd 相同）。
	if home and HarvestUI.on_field(data):
		for site:String in HarvestUI.SITES:points["harvest:"+site]=Vector2(HarvestUI.site_cell(site))+Vector2(0.5,0.5)
	# T071 河岸釣魚會告示牌，緊接在豐收接力之後（與 main.gd 相同）。
	if home and FishMeetUI.on_field(data):points[FishMeetUI.POINT]=Vector2(World.FISH_MEET.SIGN)+Vector2(0.5,0.5)
	# T071 家園布置題告示牌，緊接在河岸釣魚會之後（與 main.gd 相同）。
	if home and ShowcaseUI.sign_shown(data):points[ShowcaseUI.POINT]=Vector2(World.SHOWCASE.SIGN)+Vector2(0.5,0.5)
	# T071 紀念品交換攤，緊接在家園布置題告示牌之後（與 main.gd 相同）。
	if home and SouvenirUI.booth_shown(data):points[SouvenirUI.POINT]=Vector2(SouvenirUI.booth_cell(data))+Vector2(0.5,0.5)
	# 第 40 章地方記憶展，緊接在紀念品交換攤之後（與 main.gd 相同）。
	if home and MemoryExhibitUI.stand_shown(data):points[MemoryExhibitUI.POINT]=Vector2(MemoryExhibitUI.stand_cell(data))+Vector2(0.5,0.5)
	for key in data.objects:
		if data.objects[key].type in INTERACTIVE_OBJECTS:
			points[key]=Vector2(World.cell(key))+Vector2(0.5,0.5)
	if home:points["quarry"]=Vector2(54.5,25.5)
	if home:points["copper"]=Vector2(World.COPPER_CELL)+Vector2(0.5,0.5)
	var closest:=""
	var distance:=3.2
	for key in points:
		var candidate:=pos.distance_to(points[key])
		if candidate<distance:
			distance=candidate
			closest=key
	return World.ORE_ROUTE.preferred_interaction(data,pos,closest,points) if mining else closest

static func tea_points(region:String,snapshot:Dictionary={})->Dictionary:
	var tea=World.TEA_CERAMICS
	if region=="yingge":return {tea.POTTER:"potter",tea.CLAY:"clay",tea.KILN:"kiln"}
	if region!="maokong":return {}
	var points:Dictionary={tea.TEA_NPC:"host",tea.ROASTER:"roast",tea.PACKER:"pack"}
	if World.TEA_REVISIT.house_open(snapshot):points[World.TEA_REVISIT.HOUSE_SITE]="house"
	for node:Vector2i in tea.TEA_NODES:points[node]="pick:"+World.key(node)
	return points

static func tea_site_label(site:String)->String:
	return "茶叢" if site.begins_with("pick:") else str({"host":"茶茶","roast":"烘焙台","pack":"包裝寄運","potter":"陶師","clay":"備土台","kiln":"製罐窯"}.get(site,""))

## T071 市集攤位：reuses the 64×64 daily stall cell of assets/flowers/flower-market.png
## (FlowerSceneArt.market_texture(false), the 田尾 cooperative stall) with its feet on
## the cell. Static in every motion mode. While the local player stands in a row
## above the stall (behind it) inside its footprint, the stall is drawn translucent so
## the player is never fully hidden.
func market_stall_rect(cell:Vector2i) -> Rect2:
	var feet:=screen(Vector2(cell))+Vector2(16,30)
	return Rect2((feet-Vector2(FlowerSceneArt.market_anchor())).round(),Vector2(FlowerSceneArt.MARKET_SIZE))

func draw_market_stall(at:Vector2,cell:Vector2i) -> void:
	var rect:=market_stall_rect(cell)
	var alpha:=1.0
	if display_positions.has(player_id) and data.get("players",{}).has(player_id):
		var local:Vector2=display_positions[player_id]
		var body:=LabelLayout.body_rect(screen(local).round())
		if floori(local.y)<cell.y and rect.intersects(body):alpha=0.45
	var texture:=FlowerSceneArt.market_texture(false)
	if texture:draw_texture(texture,rect.position,Color(1,1,1,alpha))
	var own:Dictionary=data.get("own_market",{}) if data.get("own_market",{}) is Dictionary else {}
	# T071 攤位布置：本人擺上攤位的每種貨在櫃檯檯面擺一張小牌子（今日主題的牌子外框是橘色）。
	for tag:Dictionary in market_shelf_tags(cell):
		var box:Rect2=tag.rect
		draw_rect(box,Color(0.90,0.50,0.16,alpha) if tag.themed else Color(0.22,0.18,0.14,alpha))
		draw_rect(box.grow(-1),Color(1.0,0.95,0.82,alpha))
		var goods:=MarketItemArt.icon(str(tag.item))
		if goods:draw_texture_rect(goods,box.grow(-1),false,Color(1,1,1,alpha))
	var title:="市集攤位"
	if int(own.get("till",0))>0:
		title+="・可領營收"
		var coin:=MarketItemArt.icon("coins")
		if coin:draw_texture_rect(coin,Rect2(rect.position+Vector2(rect.size.x-18,2),Vector2(16,16)),false,Color(1,1,1,alpha))
	elif bool(own.get("open",false)):title+="・營業中"
	world_label(at+Vector2(16,-36),title,"market")

## T071 攤位布置（純呈現）：本人攤上每種貨的掛牌 {"item","count","themed","slot","rect"}；
## rect 是畫面座標（與 market_stall_rect 同一座標系）。只讀 own_market。
func market_shelf_tags(cell:Vector2i) -> Array:
	var own:Variant=data.get("own_market",{})
	if not own is Dictionary or cell==MarketStall.NO_CELL:return []
	var origin:=market_stall_rect(cell).position
	var result:=[]
	for entry:Dictionary in MarketDisplay.shelf(own):
		var tag:Dictionary=entry.duplicate()
		tag["rect"]=Rect2(origin+Vector2(entry.offset),MarketDisplay.TAG)
		result.append(tag)
	return result

## T071 客人演出（純呈現）：今天全島有攤位開張時，攤位前的客人。位置、朝向、染色與
## 想買的東西都由 MarketVisitors.plan 依世界日與時段決定；這裡只加上世界座標。
## 客人不擋路、不能互動，成交仍只在午夜結算。
func market_guests() -> Array:
	if region_id()!="home":return []
	var cell:=MarketStall.active_cell(data)
	if cell==MarketStall.NO_CELL:return []
	var own:Variant=data.get("own_market",{})
	if not own is Dictionary:return []
	var result:=[]
	for guest:Dictionary in MarketVisitors.plan(own,float(data.get("time",0.0))):
		var entry:Dictionary=guest.duplicate()
		entry["position"]=Vector2(cell)+Vector2(guest.offset)
		result.append(entry)
	return result

func market_guest_rect(guest:Dictionary) -> Rect2:
	var foot:=screen(guest.position).round()
	return Rect2(foot-Vector2(CharacterSprites.FOOT),Vector2(CharacterSprites.FRAME_SIZE))

func market_wish_rect(guest:Dictionary) -> Rect2:
	return Rect2(screen(guest.position).round()+Vector2(-9,-64),Vector2(18,18))

func draw_market_guest(guest:Dictionary) -> void:
	var foot:=screen(guest.position).round()
	var tint:Color=guest.tint
	# 本人站在客人身上時把客人畫成半透明，不遮住自己的角色。
	if display_positions.has(player_id) and data.get("players",{}).has(player_id):
		var local_foot:=screen(display_positions[player_id]).round()
		if LabelLayout.body_rect(local_foot).intersects(LabelLayout.body_rect(foot)):tint.a=0.45
	var phase:=0.0 if reduced_motion else MarketVisitors.shuffle_phase(int(guest.slot),elapsed)
	if character_art:character_art.draw_tinted(self,foot,guest.facing,phase,phase>0.0,reduced_motion,tint)
	else:person_sprite(foot,tint,"guest",guest.facing,phase,phase>0.0)
	var wish:=str(guest.wish)
	if wish.is_empty():return
	var icon:=MarketItemArt.icon(wish)
	if icon==null:return
	var box:=market_wish_rect(guest)
	draw_rect(box,Color(0.22,0.18,0.14,tint.a))
	draw_rect(box.grow(-1),Color(1.0,0.95,0.82,tint.a))
	draw_texture_rect(icon,box.grow(-2),false,Color(1,1,1,tint.a))

## T071 豐收接力 props (static in every motion mode; existing PNGs only):
##  sign   assets/ui-life/furniture.png "sign" with a radish icon on its board;
##  crate  assets/mine/freight.png frame 2 (wooden crate) + radish/lettuce/tomato icons;
##  basket assets/bobo/tray.png, felt recoloured per basket (HarvestUI.basket_texture),
##         with that basket's representative vegetable icon sitting in it.
## Labels: name always; the focused one says what the interact key will do.
func draw_harvest_prop(at:Vector2,cell:Vector2i) -> void:
	var site:=HarvestUI.site_at(cell)
	var id:="harvest:"+site
	var title:=HarvestUI.site_title(data,player_id,site,focused_label==id)
	match site:
		"sign":
			FurnitureArt.draw_sprite(self,at,"sign")
			var radish:=MarketItemArt.icon("radish")
			if radish:draw_texture_rect(radish,Rect2(at+Vector2(10,-4),Vector2(12,12)),false)
			world_label(at+Vector2(16,-5),title,id)
		"crate":
			for spot:Array in [[Vector2(1,-7),"radish"],[Vector2(15,-8),"tomato"],[Vector2(8,-10),"lettuce"]]:
				var icon:=MarketItemArt.icon(str(spot[1]))
				if icon:draw_texture_rect(icon,Rect2(at+Vector2(spot[0]),Vector2(16,16)),false)
			draw_texture_rect_region(MineArt.FREIGHT,Rect2(at,Vector2(32,32)),Rect2(64,0,32,32))
			world_label(at+Vector2(16,-10),title,id)
		_:
			var tray:=HarvestUI.basket_texture(site)
			if tray:draw_texture_rect(tray,Rect2(at+Vector2(-4,4),Vector2(40,30)),false)
			var icon:=HarvestUI.basket_icon(site)
			if icon:draw_texture_rect(icon,Rect2(at+Vector2(7,-1),Vector2(18,18)),false)
			# Painted name plaque in the basket colour: always readable, never pushed
			# around by the label layout (the baskets are only two tiles apart).
			var plaque:=harvest_plaque_rect(at)
			draw_rect(plaque,Color("392d23"))
			draw_rect(plaque.grow(-1),HarvestUI.BASKET_COLOUR[site])
			var plaque_name:=str(World.HARVEST.BASKET_NAMES[site])
			var text_at:=(plaque.position+Vector2((plaque.size.x-font.get_string_size(plaque_name,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x)/2.0,10)).round()
			draw_string_outline(font,text_at,plaque_name,HORIZONTAL_ALIGNMENT_LEFT,-1,10,2,Color("392d23"))
			draw_string(font,text_at,plaque_name,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("fff8e3"))
			# While another basket is focused its long prompt would push this name
			# label sideways (away from its basket); the plaque still names it.
			var other_basket:=focused_label.begins_with("harvest:") and focused_label!=id and focused_label.trim_prefix("harvest:") in World.HARVEST.BASKET_ORDER
			if not other_basket:world_label(at+Vector2(16,-2),title,id)

func harvest_plaque_rect(at:Vector2) -> Rect2:
	return Rect2(at+Vector2(3,20),Vector2(26,13))

## Rect (world px, unzoomed) of the model vegetable drawn above a carrier's head.
func harvest_carry_rect(foot:Vector2) -> Rect2:
	return Rect2(foot+Vector2(-11,-84),Vector2(22,22))

func draw_harvest_carry(foot:Vector2,kind:String) -> void:
	var box:=harvest_carry_rect(foot)
	draw_rect(box,Color("392d23"))
	draw_rect(box.grow(-1),Color("fff3d2"))
	var icon:=HarvestUI.veg_icon(kind)
	if icon:draw_texture_rect(icon,box.grow(-2),false)

func world_label(anchor:Vector2,title:String,id:String,side:=false) -> void:
	if photograph_mode:return
	world_labels.append({"anchor":anchor.round(),"title":title,"id":id,"side":side})

func draw_farm_feedback(operation:Dictionary) -> void:
	var progress:=clampf((elapsed-float(operation.started))/FarmFeedback.DURATION,0.0,1.0)
	var tint:=Color("b3d894") if operation.kind=="seeder" else Color("e8c88b")
	tint.a=0.7 if reduced_motion else 0.7*(1.0-progress)
	for changed in operation.cells:
		var at:=screen(Vector2(World.cell(changed)))
		draw_rect(Rect2(at+Vector2(3,3),Vector2(26,26)),tint,false,1.0)
		if reduced_motion:continue
		var shift:=Vector2(0,-roundf(progress*13.0))
		if operation.kind=="tiller":
			for offset in [Vector2(8,13),Vector2(19,9),Vector2(23,19)]:
				draw_rect(Rect2(at+offset+shift,Vector2(2,2)),tint)
		else:
			var icon_index:=int(FEEDBACK_ICONS.get(operation.items.get(changed,""),-1))
			if feedback_atlas and icon_index>=0:
				var region:=Rect2((icon_index%6)*32,(icon_index/6)*32,32,32)
				draw_texture_rect_region(feedback_atlas,Rect2(at+Vector2(10,8)+shift,Vector2(12,12)),region,Color(1,1,1,1.0-progress))
			elif icon_index<0:
				# Items outside the legacy feedback atlas (e.g. pumpkin) use their item icon.
				var item_icon:Texture2D=BakeryArt.icon(str(operation.items.get(changed,""))) if str(operation.items.get(changed,"")) in ["pumpkin","pumpkin_seed"] else null
				if item_icon:draw_texture_rect(item_icon,Rect2(at+Vector2(10,8)+shift,Vector2(12,12)),false,Color(1,1,1,1.0-progress))

## T017: the exact pose/particle plan the draw path uses for one actor this frame
## ({} when idle). Adds the facing toward the target and the server event record.
func tool_action_plan(id:String) -> Dictionary:
	var record:=tool_feedback.active(id,elapsed)
	if record.is_empty():return {}
	return tool_record_plan(id,record)

func tool_record_plan(id:String,record:Dictionary) -> Dictionary:
	var target_cell:Vector2i=record.to if record.tool=="move_object" else record.cell
	var facing:=ToolActionFeedback.facing_toward(record.origin,target_cell,facings.get(id,Vector2i.DOWN))
	var progress:=clampf((elapsed-float(record.started))/ToolActionFeedback.DURATION,0.0,1.0)
	var result:=ToolActionFeedback.plan(record.tool,progress,reduced_motion or photograph_mode,facing)
	result.facing=facing
	result.progress=progress
	result.record=record
	return result

## Held tool icon (existing 32px ui-life / inventory pixel art) at the hand, rotated
## around the grip. Reduced motion: fixed pose from the plan, no lunge.
func draw_tool_held(at:Vector2,tool_plan:Dictionary) -> void:
	var icon:=ToolActionFeedback.held_icon(tool_plan.tool,str(tool_plan.record.get("item","")))
	if icon==null:return
	var grip:=ToolActionFeedback.hand_grip(at,tool_plan)
	var zoom_scale:=Vector2.ONE*view_zoom()
	draw_set_transform(grip*zoom_scale,float(tool_plan.angle),zoom_scale)
	draw_texture_rect(icon,Rect2(Vector2(-8,-16),Vector2(16,16)),false)
	draw_set_transform(Vector2.ZERO,0.0,zoom_scale)
	tool_draw_stats.held+=1
	if tool_plan.lunge!=Vector2.ZERO:tool_draw_stats.lunge+=1
	tool_draw_stats.angles[snappedf(float(tool_plan.angle),0.01)]=true

## Target-cell feedback: short procedural chips/drops/dust (none with reduced motion)
## plus a harvested-crop icon rising from the plot (fixed with reduced motion).
func draw_tool_target(tool_plan:Dictionary,foot:Vector2) -> void:
	var record:Dictionary=tool_plan.record
	var cell:Vector2i=record.to if record.tool=="move_object" else record.cell
	var cell_at:=screen(Vector2(cell))
	var impact:=ToolActionFeedback.soil_impact(record.tool,tool_plan.progress,tool_plan.reduced)
	if not impact.is_empty():
		var spread:float=impact.spread
		var center:=cell_at+Vector2(16,22)
		for offset in [Vector2(-spread,-2),Vector2(spread,-2),Vector2(-spread+2,2),Vector2(spread-2,2)]:
			draw_rect(Rect2(center+offset-Vector2(2,0),Vector2(4,1)),impact.color)
	if not tool_plan.reduced and record.tool in ["seed","water"]:
		var watering:bool=record.tool=="water"
		var tint:=Color("c4e6f0") if watering else Color("ffe6a2")
		var shadow:=Color("54899a") if watering else Color("805a37")
		var grip:=ToolActionFeedback.hand_grip(foot,tool_plan)
		for point in ToolActionFeedback.farm_trail(record.tool,tool_plan.progress,grip,cell_at):
			draw_rect(Rect2(point,Vector2(3,4)),shadow)
			draw_rect(Rect2(point,Vector2(2,2)),tint)
			tool_draw_stats.particles+=1
	if record.tool=="harvest" and not str(record.item).is_empty():
		var crop_icon:=MarketItemArt.icon(str(record.item))
		if crop_icon:
			var size:=roundf(14.0*float(tool_plan.crop_scale))
			var center:=cell_at+Vector2(16,11+tool_plan.lift)
			draw_texture_rect(crop_icon,Rect2((center-Vector2.ONE*size/2.0).round(),Vector2.ONE*size),false,Color(1,1,1,tool_plan.alpha))
	if record.tool=="move_object":
		draw_rect(Rect2(cell_at+Vector2(3,3),Vector2(26,26)),Color(1,0.96,0.78,0.6),false,1.0)
	for particle:Dictionary in tool_plan.particles:
		draw_rect(Rect2(cell_at+particle.pos,particle.size),particle.color)
		tool_draw_stats.particles+=1

func compact_farm_prompt() -> bool:
	return (show_target and selected in ["till_area","seed_area","harvest_area"]) or not farm_feedback.active(player_id,elapsed).is_empty()

func label_is_clear(box:Rect2,placed:Array[Rect2],viewport:Rect2) -> bool:
	if not viewport.encloses(box):return false
	for other in placed:
		if box.grow(2).intersects(other):return false
	return true

func farm_label_title(entry:Dictionary) -> String:
	var type:String=data.get("objects",{}).get(entry.id,{}).get("type","")
	return {"sprinkler":"灑水","forester":"林務","water_tank":"水桶","water_pump":"水泵",
		"sawmill":"鋸木","charcoal_kiln":"炭窯","mill":"磨坊","seed_maker":"種子機","glass_furnace":"玻璃爐","conveyor":"輸送帶","water_tower":"水塔"}.get(type,String(entry.title).split(" · ")[0])

func world_label_placements(viewport:Rect2) -> Array[Dictionary]:
	var height:=world_label_height()
	var placed:Array[Rect2]=[]
	var result:Array[Dictionary]=[]
	var compact:=compact_farm_prompt()
	placed.append_array(label_obstacles(compact))
	var area:=LabelLayout.safe_area(viewport)
	for active in [true,false]:
		for entry in world_labels:
			if (entry.id!="" and entry.id in [focused_label,"floor_placement_access","furniture_remove_access"])!=active:continue
			if not active and display_positions.has(player_id):
				var local_foot:=screen(display_positions[player_id])
				if Vector2(entry.anchor).distance_to(local_foot)>160.0:continue
				if entry.id=="" and Vector2(entry.anchor).distance_to(local_foot+Vector2(0,-40))<2.0:continue
			if compact and not active and (data.get("objects",{}).has(entry.id) or entry.id==""):continue
			var title:String=farm_label_title(entry) if compact and active else entry.title
			var key_width:float=interaction_badge_width() if active else 0.0
			var width:float=world_label_title_width(title)+(key_width+3 if active else 0)
			var anchor:Vector2=entry.anchor
			var at:=Vector2(anchor.x if entry.side else roundf(anchor.x-width/2.0),anchor.y-height)
			var box:=Rect2(at,Vector2(width,height))
			var obstacles:=placed
			if data.get("objects",{}).get(entry.id,{}).get("type","")=="stove":
				obstacles=placed.duplicate()
				obstacles.append(CookingFeedback.display_bounds(screen(Vector2(World.cell(entry.id))).round()))
			elif entry.id==ShowcaseUI.POINT:
				obstacles=placed.duplicate()
				for tile in ShowcaseUI.pieces(data):
					obstacles.append(Rect2(screen(Vector2(World.cell(str(tile)))),Vector2(32,32)))
			var keep_centered:bool=entry.id in ["harvest:sign",ShowcaseUI.POINT]
			if not active and (entry.id=="" or World.Village.NPCS.has(entry.id)):keep_centered=true
			if not active and (not viewport.has_point(anchor) or not viewport.intersects(box)):continue
			if not active and hidden_under_card(box):continue
			if active:
				# The focused prompt steps around the local body, its name tag and HUD,
				# staying as close to its target as possible and never being dropped.
				box=LabelLayout.place(box,anchor,obstacles,area,keep_centered).rect
			else:
				if not label_is_clear(box,obstacles,area):
					var spot:=LabelLayout.place(box,anchor,obstacles,area,keep_centered)
					if not spot.clear or LabelLayout.distance_to_rect(anchor,spot.rect)>48.0:continue
					box=spot.rect
				if hidden_under_card(box):continue
			placed.append(box)
			result.append({"id":entry.id,"rect":box,"title":title,"active":active})
	return result

func hidden_under_card(box:Rect2) -> bool:
	var scale_value:=view_zoom()
	for rect in label_hide_rects:
		if box.intersects(Rect2(rect.position/scale_value,rect.size/scale_value).grow(2.0)):return true
	return false

## Areas the focused interaction label must not cover: visible HUD, the farm
## work footprint (compact mode), the local player's body and their name tag.
func label_obstacles(compact:bool) -> Array[Rect2]:
	var list:Array[Rect2]=[]
	# Protect every rendered resident/visitor, including remote players; the
	# focused label previously considered only the local player's body.
	list.append_array(character_label_obstacles)
	for who in display_positions:
		var body:=LabelLayout.body_rect(screen(display_positions[who]).round())
		if not list.has(body):list.append(body)
	var scale_value:=view_zoom()
	for rect in label_avoid_rects:list.append(Rect2(rect.position/scale_value,rect.size/scale_value))
	if first_crop_cue_rect.has_area():list.append(first_crop_cue_rect)
	if data.get("objects",{}).get(focused_label,{}).get("type","")=="mill":
		# Keep the actual 32x48 mill and its progress/badge visible as well.
		var mill_at:=screen(Vector2(World.cell(focused_label)))
		list.append(Rect2(mill_at+Vector2(0,-24),Vector2(34,56)))
	# T071 客人演出：標籤避開客人頭上的小牌子。
	for guest:Dictionary in market_guests():
		if not str(guest.wish).is_empty():list.append(market_wish_rect(guest))
	if region_id()==World.REGIONS.HOME and HarvestUI.on_field(data):
		# T071: keep the focused prompt off the basket name plaques and off every
		# carried model vegetable.
		for basket:String in World.HARVEST.BASKET_ORDER:list.append(harvest_plaque_rect(screen(Vector2(World.HARVEST.BASKETS[basket]))))
		for who in data.get("players",{}):
			if not HarvestUI.carried(data,str(who)).is_empty() and display_positions.has(who):list.append(harvest_carry_rect(screen(display_positions[who]).round()))
	if region_id()==World.REGIONS.HOME and FishMeetUI.waters_marked(data):
		# T071 河岸釣魚會：focused prompts stay off the buoys and off my own bobber
		# (the sign stands right beside the marked waters).
		for buoy:Vector2 in FishMeetUI.buoy_points(self):list.append(Rect2(buoy-Vector2(5,6),Vector2(10,12)))
		var cast:Dictionary=data.get("players",{}).get(player_id,{}).get("fishing",{})
		if not cast.is_empty():list.append(Rect2(screen(Vector2(float(cast.x),float(cast.y))),Vector2(32,32)))
	if focused_label==ShowcaseUI.PLOT_POINT:
		# T071 家園布置題：the plot prompt stays off its own target cell, the pieces and the sign.
		var showcase_cell:=ShowcaseUI.view_target(self)
		if showcase_cell!=ShowcaseUI.NO_CELL:list.append(Rect2(screen(Vector2(showcase_cell)),Vector2(32,32)))
		for tile in ShowcaseUI.pieces(data):list.append(Rect2(screen(Vector2(World.cell(str(tile)))),Vector2(32,32)))
		if ShowcaseUI.sign_shown(data):list.append(ShowcaseUI.sign_rect(self))
	if region_id()==World.REGIONS.HOME and focused_label!=MemoryExhibitUI.POINT and MemoryExhibitUI.stand_shown(data):
		# 第 40 章地方記憶展：other focused prompts (e.g. 阿榆 at the festival spot) stay off
		# the stand's wall and pedestals.
		list.append(MemoryExhibitUI.stand_inner_rect(self,MemoryExhibitUI.stand_cell(data)))
	if compact:
		var operation:=farm_feedback.active(player_id,elapsed)
		var center:Vector2i=operation.get("center",target)
		list.append(Rect2(screen(Vector2(center-Vector2i.ONE)),Vector2(96,96)))
	if display_positions.has(player_id):
		var foot:=screen(display_positions[player_id]).round()
		list.append(LabelLayout.body_rect(foot))
		# The own name tag is drawn at foot+(0,-40) by the player loop in _draw.
		var tag_anchor:=(foot+Vector2(0,-40)).round()
		for entry in world_labels:
			if entry.id=="" and Vector2(entry.anchor)==tag_anchor:
				var width:=world_label_title_width(str(entry.title))
				var height:=world_label_height()
				list.append(Rect2(Vector2(roundf(tag_anchor.x-width/2.0),tag_anchor.y-height),Vector2(width,height)))
				break
	return list

func world_label_font_size() -> int:
	return roundi((18 if view_zoom()==1.0 else 28)*label_text_scale)

func world_label_title_width(title:String) -> float:
	return ceilf(font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,world_label_font_size()).x/view_zoom())+8.0

func world_label_height() -> float:
	return ceilf(font.get_height(world_label_font_size())/view_zoom())+4.0

func interaction_badge_font_size() -> int:
	return maxi(10,roundi(10.0*view_zoom()*label_text_scale))

func interaction_badge_width() -> float:
	return maxf(13,ceilf(font.get_string_size(interaction_key_label,HORIZONTAL_ALIGNMENT_LEFT,-1,interaction_badge_font_size()).x/view_zoom())+6.0)

func draw_world_labels() -> void:
	var scale_value:=view_zoom()
	var font_size:=world_label_font_size()
	var baseline:=font.get_ascent(font_size)
	# Render Chinese at its final screen size instead of enlarging a small
	# rasterized glyph along with the pixel-art world.
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	for entry in world_label_placements(Rect2(Vector2.ZERO,get_viewport_rect().size/view_zoom())):
		var source_box:Rect2=entry.rect
		var box:=Rect2((source_box.position*scale_value).round(),(source_box.size*scale_value).round())
		var pos:=(box.position+Vector2(4*scale_value,(box.size.y-font.get_height(font_size))/2.0+baseline)).round()
		if entry.active:
			draw_rect(box.grow(2),Color("624730"))
			draw_rect(box,Color("fff0ce"))
			draw_string(font,pos,entry.title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("3e3428"))
		else:
			draw_string_outline(font,pos,entry.title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,2 if font_size<=22 else 3,Color("35402d"))
			draw_string(font,pos,entry.title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff6de"))
		if entry.active:
			var key_width:=interaction_badge_width()*scale_value
			var key_font_size:=interaction_badge_font_size()
			var key_height:=ceilf(font.get_height(key_font_size)+2.0*scale_value)
			var key_pos:=(box.position+Vector2(box.size.x-key_width-2*scale_value,(box.size.y-key_height)/2.0)).round()
			draw_rect(Rect2(key_pos,Vector2(key_width,key_height)),Color("526744"))
			var key_baseline:=(key_height-font.get_height(key_font_size))/2.0+font.get_ascent(key_font_size)
			draw_string(font,(key_pos+Vector2(3*scale_value,key_baseline)).round(),interaction_key_label,HORIZONTAL_ALIGNMENT_LEFT,-1,key_font_size,Color("fff6de"))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*scale_value)
