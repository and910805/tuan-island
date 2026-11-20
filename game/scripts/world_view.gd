extends Node2D
var player_emotes:Dictionary={}

const MianmianSheepStep=preload("res://scripts/mianmian_sheep_step.gd")
const AruRest=preload("res://scripts/aru_rest.gd")
const MianmianHat=preload("res://scripts/mianmian_wool_hat_art.gd")
const LuoluoCap=preload("res://scripts/luoluo_courier_cap_art.gd")
const MianmianToyArt=preload("res://scripts/mianmian_toy_art.gd")
const MianmianApproach=preload("res://scripts/mianmian_chicken_approach.gd")
const FurnitureArt=preload("res://scripts/furniture_sprite_art.gd")
const SpringGardenArt=preload("res://scripts/spring_garden_art.gd")
const BeachTreasureArt=preload("res://scripts/beach_treasure_art.gd")
const StoneFloorArt=preload("res://scripts/stone_floor_art.gd")
const LivestockArt=preload("res://scripts/livestock_scene_art.gd")
var livestock_pet_feedback:Dictionary={}
var duck_feed_started:=-INF
var duck_feed_origin:=Vector2.ZERO
const CookingFeedback=preload("res://scripts/cooking_feedback.gd")
const BoboArt=preload("res://scripts/bobo_art.gd")
const TransitArt=preload("res://scripts/transit_art.gd")
const StationLifeArt=preload("res://scripts/station_life_art.gd")
const ShippingArt=preload("res://scripts/shipping_art.gd")
const LanyangLifeArt=preload("res://scripts/lanyang_life_art.gd")
const MineArt=preload("res://scripts/mine_art.gd")
const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const GuardianArt=preload("res://scripts/sleepy_stone_guardian_art.gd")
const GuardianUI=preload("res://scripts/sleepy_stone_guardian_ui.gd")
const Shy=preload("res://scripts/shy_mushroom.gd")
const ShyArt=preload("res://scripts/shy_mushroom_art.gd")
const ShyUI=preload("res://scripts/shy_mushroom_ui.gd")
const PORTER_ATLAS=preload("res://assets/mine/lost-porter-mouse.png")
const MEADOW_ATLAS=preload("res://assets/mine/meadow-guardian.png")
const MEADOW_TABLE_ATLAS=preload("res://assets/mine/meadow-offering-tables.png")
const MEADOW_FRAME:=Vector2(64,64)
const MEADOW_TABLE_FRAME:=Vector2(40,40)
const PORTER_FRAME:=Vector2(32,40)
const PORTER_TRAVEL_SECONDS:=1.4
const TeaArt=preload("res://scripts/tea_ceramics_art.gd")
const TeaResidents=preload("res://scripts/tea_resident_art.gd")
const JinguashiArt=preload("res://scripts/jinguashi_art.gd")
const LanyangArt=preload("res://scripts/lanyang_art.gd")
const MemoryIcons=preload("res://assets/ui-life/icons.png")
const CommunityArt=preload("res://scripts/community_art.gd")
const AutumnFeastArt=preload("res://scripts/autumn_feast_art.gd")
const PartyCartArt=preload("res://scripts/party_cart_art.gd")
const LostChicksArt=preload("res://scripts/lost_chicks_art.gd")
const CookingRelayArt=preload("res://scripts/cooking_relay_art.gd")
const StrollArt=preload("res://scripts/lantern_stroll_art.gd")
const WarmLanternArt=preload("res://scripts/warm_lantern_night_art.gd")
const CommunityFeedback=preload("res://scripts/community_feedback.gd")
const AutomationArt=preload("res://scripts/automation_art.gd")
const Industry=preload("res://scripts/industry.gd")
const IndustryArt=preload("res://scripts/industry_art.gd")
const ProcessingFinishFeedback=preload("res://scripts/processing_finish_feedback.gd")
const CowFollowView=preload("res://scripts/cow_follow_view.gd")
const ChickenFeedView=preload("res://scripts/chicken_feed_view.gd")
const ResidentIdle=preload("res://scripts/resident_idle.gd")
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
const EdgeGrid=preload("res://scripts/edge_grid.gd")
const EdgeArt=preload("res://scripts/edge_construction_art.gd")
## Pointer reach (tiles) from an edge line for picking an existing edge to remove.
const EDGE_REMOVE_REACH:=0.24
## Edge placement / removal ghost. "" = old tile-target behaviour. Set to edge_wall / edge_door /
## edge_window to ghost a construction, or "remove_edge" to highlight an existing edge to remove.
var edge_preview_kind:String=""
## Tint the ghost red when the server/main says the hovered edge cannot take this piece.
var edge_preview_valid:bool=true
## Optional screen-pixel pointer (viewport coordinates) for controller aim; Vector2.INF = real mouse.
var edge_pointer_override:=Vector2.INF
var _edge_rows_n:Dictionary={}
var _edge_rows_w:Dictionary={}
var _edge_parse:Dictionary={}
var _edge_ref=null
const FEEDBACK_ICONS:={"radish":3,"lettuce":4,"wheat":5,"radish_seed":6,"lettuce_seed":7,"wheat_seed":8,
	"carrot":18,"potato":19,"tomato":20,"carrot_seed":21,"potato_seed":22,"tomato_seed":23}
const MACHINES:={"tiller":["till_area","last_till"],"seeder":["seed_area","last_seed"],"harvester":["harvest_area","last_harvest"]}
const World=preload("res://scripts/world.gd")
const TILE:=32.0
const DOCKED_BOAT:=Vector2(56.15,33.55)
const DOCK_LAUNCH_SECONDS:=2.0
const VOYAGE_ART=TransitArt.VOYAGE_ART
var dock_launch_started:=-INF
var inn_swept_at:=-INF
const Art=preload("res://scripts/world_pixel_art.gd")
const VillagePreview=preload("res://scripts/village_preview_art.gd")
const CharacterSprites=preload("res://scripts/character_sprite_art.gd")
const CropSprites=preload("res://scripts/crop_sprite_art.gd")
const RoofVisibility=preload("res://scripts/roof_visibility.gd")
const LabelLayout=preload("res://scripts/world_label_layout.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
var greenhouse_memo:Dictionary={}
const FlowerWorldArt=preload("res://scripts/flower_world_art.gd")
const SaltWorldArt=preload("res://scripts/salt_world_art.gd")
const MarketStall=preload("res://scripts/market_stall.gd")
const MarketVisitors=preload("res://scripts/market_visitors.gd")
const MarketDisplay=preload("res://scripts/market_display.gd")
const MarketDecorArt=preload("res://scripts/market_decor_art.gd")
const SeaBreezeFairArt=preload("res://scripts/sea_breeze_fair_art.gd")
const FlowerSceneArt=preload("res://scripts/flower_scene_art.gd")
const MarketItemArt=preload("res://scripts/inventory_item_art.gd")
const VineArchArt=preload("res://scripts/vine_arch_art.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const FishMeetUI=preload("res://scripts/fishing_meet_ui.gd")
const ShowcaseUI=preload("res://scripts/showcase_ui.gd")
const SouvenirUI=preload("res://scripts/souvenir_exchange_ui.gd")
const PublicTillerUI=preload("res://scripts/public_tiller_ui.gd")
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
const OreRouteSelect=preload("res://scripts/ore_route_ui.gd") # T066：台車／波波空車共用選擇器
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
var active_market_carts:Array[Vector2i]=[]
var own_market_cart_open:=false
var occupied_hollow_beds:Dictionary={}
## T10: anchor cell key -> person id of whoever is reclining on that bamboo lounger.
var occupied_loungers:Dictionary={}
var player_id:=""
var camera:=Vector2.ZERO
var camera_frame:=Vector3.ZERO
var home_base_resources:Dictionary[Vector2i,String]={}
static var _draw_key_rows:Dictionary[int,PackedStringArray]={}
var fixed_area_camera:=false:
	set(value):
		if fixed_area_camera==value:return
		fixed_area_camera=value
		camera_frame=Vector3.ZERO
var target:=Vector2i.ZERO
var photograph_mode:=false
## D16: resident id drawn beside the shared table for a solo hotpot photo ("" = nobody extra).
var photo_guest:=""
var show_target:=false
var hand_farm_wide:=false
var placement_style:=""
var selected:="hoe"
var building:="floor"
var mill_build_facing := 0
var area_drag:=false
var area_start:=Vector2i.ZERO
var font:FontVariation
var elapsed:=0.0
var cooking_relay_served_at:=-INF
var lost_chick_movement:Dictionary={}
var party_cart_clock_at:=0.0
var stroll_dim:=false
var stroll_trail:Array[Vector2]=[]
var stroll_companion:=Vector2.INF
var reduced_motion:=false
var label_text_scale:=1.0
var night_lamp_pool:GradientTexture2D
var spore_lamp_pool:GradientTexture2D
var zoom:=2.0
var display_positions:Dictionary={}
## Roof tiles cut away for the local player this frame (RoofVisibility); computed once at the
## top of _draw so the roof pass and roof-linked props (bamboo curtain) share one answer.
var roof_faded:Dictionary={}
var starts:Dictionary={}
var goals:Dictionary={}
var interpolation_clock:=0.1
var movement_started:Dictionary={}
## T091: physics-tick pose of the verified private single-player host (Session.solo_motion),
## set by Main. Render-only: it replaces the 10 Hz interpolation target for the own player.
var solo_motion:Dictionary={}
var facings:Dictionary={}
var gait:Dictionary={}
var walking:Dictionary={}
var stride_stop:Dictionary={}
var world_labels:Array[Dictionary]=[]
var character_label_obstacles:Array[Rect2]=[]
var focused_label:=""
## 打瞌睡石像: bell currently highlighted by the hum playback or a ring (-1 none); pushed by main.
var guardian_lit_bell:=-1
## 害羞菇 ring/label state from ShyUI.view_state (set by main every frame; {} = idle).
var shy_view:Dictionary={}
var shy_spore_received:=0.0
var porter_walk_started:float=-INF
var hedgehog_nap_cell:=World.Hedgehog.NO_BASKET
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
var processing_finish_feedback:=ProcessingFinishFeedback.new()
var tool_feedback:=ToolActionFeedback.new()
## Local-only ring times (elapsed seconds) for 聽水風鈴, keyed by object key.
var water_chime_rings:Dictionary={}
## T017 evidence counters, only ever incremented by the real draw path:
## held = held-tool icons drawn, particles = target particles drawn,
## lunge = held draws with a body lunge, angles = distinct held-tool angles.
var tool_draw_stats:={"held":0,"particles":0,"lunge":0,"angles":{}}
var fishing_feedback:=FishingFeedback.new()
var sheep_shelter:=SheepShelter.new()
var cow_follow:=CowFollowView.new()
var chicken_feed:=ChickenFeedView.new()
var chicken_draw_stats:={"ground":0,"carried":0}
var sprinkler_sprays:Dictionary={}
var brine_transfer_started:=-INF
var brine_transfer_delta:=0
var ore_cart_push_started:=-INF
var ore_cart_push_story:=false
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

func hand_farm_preview(center:Vector2i,tool:String)->Dictionary:
	tiller_world.state=data
	tiller_world._region=region_id()
	if tool in World.WATERING_CANS:return tiller_world.hand_water_plan(player_id,center,tool)
	if tool in World.SEED_POUCHES:return tiller_world.hand_seed_plan(player_id,center,tool,seed_kind)
	if tool in World.HARVEST_SICKLES:return tiller_world.hand_harvest_plan(player_id,center,tool)
	return World.TILLER.hand_plan(tiller_world,player_id,center,tool)

func tree_planting_preview(tile:Vector2i)->String:
	var person:Dictionary=data.get("players",{}).get(player_id,{})
	if person.is_empty():return ""
	if Vector2(person.x,person.y).distance_to(Vector2(tile)+Vector2(0.5,0.5))>3.2:
		return "靠近一點再種樹苗"
	tiller_world.state=data
	tiller_world._region=region_id()
	return tiller_world.tree_planting_problem(player_id,tile)

func _observe_lost_chicks(snapshot:Dictionary,reset:bool) -> void:
	var previous:Dictionary=data.get(World.LOST_CHICKS.KEY,{})
	var current:Dictionary=snapshot.get(World.LOST_CHICKS.KEY,{})
	if reset or previous.get("round")!=current.get("round") or current.get("phase")!="run":
		lost_chick_movement.clear()
		return
	var old:Array=previous.get("chicks",[])
	var next:Array=current.get("chicks",[])
	for i in mini(old.size(),next.size()):
		var from:=Vector2(old[i].x,old[i].y)
		var to:=Vector2(next[i].x,next[i].y)
		if next[i].status=="home":
			lost_chick_movement.erase(i)
		elif from.distance_to(to)==1.0:
			lost_chick_movement[i]={"from":from,"to":to,"since":elapsed}

func _draw_lost_chicks(row:int) -> void:
	var round:Dictionary=data.get(World.LOST_CHICKS.KEY,{})
	if round.get("phase") not in ["run","results"]:return
	var still:=reduced_motion or photograph_mode
	var index:=0
	var home_index:=0
	for chick:Dictionary in round.get("chicks",[]):
		var status:String=chick.status
		var pos:=Vector2(chick.x,chick.y)
		if status=="home":
			pos=Vector2(World.LOST_CHICKS.PEN)+Vector2((home_index%3-1)*0.27,0.03-floorf(float(home_index)/3.0)*0.27)
			home_index+=1
		elif not still and lost_chick_movement.has(index):
			var hop:Dictionary=lost_chick_movement[index]
			pos=Vector2(hop.from).lerp(hop.to,clampf((elapsed-float(hop.since))/0.19,0.0,1.0))
		if floori(pos.y)==row:LostChicksArt.draw_chick(self,screen(pos),index,status,elapsed,still)
		index+=1

func _activity_bucket(person:Dictionary) -> bool:
	if region_id()!=World.REGIONS.HOME or data.get(World.LOST_CHICKS.KEY,{}).get("phase")!="run":return false
	if not data.get(World.LOST_CHICKS.VIEW_KEY,{}).get("joined",false):return false
	return World.LOST_CHICKS.AREA.has_point(Vector2i(Vector2(person.x,person.y).floor()))

func update_snapshot(snapshot:Dictionary,id:String) -> Array:
	if snapshot.has(World.SHY_SPORES.VIEW):shy_spore_received=elapsed
	var changed_region:=region_id()!=str(snapshot.get("region_id","home"))
	var recenter_camera:=data.is_empty() or changed_region or id!=player_id or float(snapshot.get("time",0))<float(data.get("time",0))
	if recenter_camera or not snapshot.get("porter_available",false):
		porter_walk_started=-INF
	elif data.get("porter_available",false):
		var previous_stage:=int(data.get("players",{}).get(id,{}).get(World.PORTER.FIELD,0))
		var next_stage:=int(snapshot.get("players",{}).get(id,{}).get(World.PORTER.FIELD,0))
		if next_stage==previous_stage+1 and next_stage<=World.PORTER.Stage.DELIVERED:porter_walk_started=elapsed
	var inn:=World.WARM_SPRINGS
	if recenter_camera:
		inn_swept_at=-INF
	elif region_id()==inn.REGION and inn.entrance_progress(data)==inn.Entrance.LEAVES and inn.entrance_progress(snapshot)==inn.Entrance.SWEPT:
		inn_swept_at=elapsed
	if recenter_camera:stroll_trail.clear()
	var old_relay:Dictionary=data.get(World.COOKING_RELAY.KEY,{})
	var next_relay:Dictionary=snapshot.get(World.COOKING_RELAY.KEY,{})
	if recenter_camera or old_relay.get("round")!=next_relay.get("round"):
		cooking_relay_served_at=-INF
	elif int(next_relay.get("plates",0))>int(old_relay.get("plates",0)):
		cooking_relay_served_at=elapsed
	if snapshot.get("region_id","")==World.PARTY_CART.REGION:party_cart_clock_at=elapsed
	_observe_lost_chicks(snapshot,recenter_camera)
	processing_finish_feedback.observe(data,snapshot,elapsed,recenter_camera)
	_observe_sprinklers(snapshot,recenter_camera)
	sheep_shelter.observe(snapshot,elapsed,recenter_camera)
	cow_follow.observe(snapshot,recenter_camera)
	chicken_feed.observe(snapshot,recenter_camera)
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
		ore_cart_push_story=false
	elif region_id()==World.ORE_ROUTE.REGION:
		var old_story:int=World.BOBO_EMPTY_CART.stage(data)
		var new_story:int=World.BOBO_EMPTY_CART.stage(snapshot)
		if new_story!=old_story:
			ore_cart_push_story=old_story>0 and new_story==old_story+1
			ore_cart_push_started=elapsed if ore_cart_push_story else -INF
		else:
			var old_stage:=World.ORE_ROUTE.stage(data)
			var new_stage:=World.ORE_ROUTE.stage(snapshot)
			if new_stage!=old_stage:
				ore_cart_push_story=false
				ore_cart_push_started=elapsed if old_stage>0 and new_stage==old_stage+1 else -INF
	if recenter_camera:
		livestock_pet_feedback.clear()
		duck_feed_started=-INF
	if recenter_camera:farm_feedback.reset()
	if changed_region:
		community_feedback.reset()
		mine_feedback.clear()
		freight_departure=-10.0
		display_positions.clear()
		starts.clear()
		goals.clear()
		movement_started.clear()
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
			if int(new_animals.get(animal_id,{}).get("feed",0))>int(old_animals.get(animal_id,{}).get("feed",0)):
				if animal_id=="duck":
					var duck=World.LIVESTOCK.Duck
					var shore:=Vector2(duck.SITE)+Vector2(0.5,0.9)
					var water:Vector2=duck.swim_position(float(data.time),false)
					var prior:Dictionary=duck.feed_pose(duck_feed_origin,shore,water,elapsed-duck_feed_started,new_animals.duck.get("managed_pen",false),false)
					var pet_active:=elapsed-float(livestock_pet_feedback.get("duck",-INF))<LivestockArt.PET_SECONDS
					duck_feed_origin=prior.get("position",shore if pet_active else water)
					duck_feed_started=elapsed
				elif animal_id=="cow":livestock_pet_feedback[animal_id]=elapsed
	farm_feedback.observe(data,snapshot,elapsed,id)
	var fresh_tools:=tool_feedback.observe(data,snapshot,id,elapsed)
	for actor in fresh_tools:
		var action:=tool_feedback.active(actor,elapsed)
		if action.get("tool","")=="seed":
			farm_feedback.mark_sprout(World.key(action.cell),data,snapshot,elapsed)
	community_feedback.observe(data,snapshot,elapsed)
	fishing_feedback.update(snapshot,id,elapsed)
	data=snapshot
	_index_edges()
	active_market_carts.clear()
	own_market_cart_open=false
	occupied_hollow_beds.clear()
	occupied_loungers.clear()
	for person_id:String in snapshot.get("players",{}):
		var anchor:String=snapshot.players[person_id].get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{}).get("cell","")
		var seat_type:String=snapshot.get("objects",{}).get(anchor,{}).get("type","")
		if seat_type==Industry.HOLLOW_BED:occupied_hollow_beds[anchor]=person_id
		elif seat_type==Industry.BAMBOO_LOUNGER:occupied_loungers[anchor]=person_id
	for tile:String in data.get("objects",{}):
		var prop:Dictionary=data.objects[tile]
		if not prop.get("market_cart_open",false):continue
		if prop.get("owner")==id:own_market_cart_open=true
		if not prop.get("market_cart_goods",[]).is_empty():active_market_carts.append(World.cell(tile))
	active_market_carts.sort_custom(func(a:Vector2i,b:Vector2i):return a.x<b.x or (a.x==b.x and a.y<b.y))
	greenhouse_memo.clear()
	player_id=id
	supply_networks=Industry.networks(snapshot)
	interpolation_clock=0.0
	for who in data.players:
		var p:Dictionary=data.players[who]
		var goal:=Vector2(p.x,p.y)
		var current:Vector2=display_positions.get(who,goal)
		var jumped:=current.distance_to(goal)>4.0
		if jumped and who==id:recenter_camera=true
		if p.has(World.REGIONS.Springs.REST_SEAT_KEY) or p.has(World.TEA_HOUSE_INTERIOR.SEAT_KEY) or jumped:
			current=goal
			gait.erase(who)
			stride_stop.erase(who)
			movement_started.erase(who)
		if not movement_started.has(who) or goals.get(who)!=goal:
			starts[who]=current
			goals[who]=goal
			movement_started[who]=elapsed
		display_positions[who]=current
	if recenter_camera and display_positions.has(id) and is_inside_tree():update_camera(display_positions[id],true)
	for who in display_positions.keys():
		if not data.players.has(who):
			display_positions.erase(who)
			starts.erase(who)
			goals.erase(who)
			movement_started.erase(who)
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
		if not village_art.setup():village_art=null
		character_art=CharacterSprites.new()
		if not character_art.setup():character_art=null
		crop_art=CropSprites.new()
		if not crop_art.setup():crop_art=null
	feedback_atlas=load("res://assets/ui-inventory/items.png") as Texture2D
	font=preload("res://scripts/island_type.gd").regular()

func _exit_tree() -> void:
	if village_art:
		village_art.finish_chunk_loads()

func _process(dt:float) -> void:
	elapsed+=dt
	cow_follow.advance(dt)
	chicken_feed.advance(dt)
	interpolation_clock=minf(interpolation_clock+dt,0.1)
	for who in display_positions:
		var previous:Vector2=display_positions[who]
		# Status and interaction snapshots may arrive between movement updates.
		# Only a new position starts another movement interpolation.
		var movement_clock:=clampf(elapsed-float(movement_started[who]),0.0,0.1)
		var interpolated:=Vector2(starts[who]).lerp(Vector2(goals[who]),movement_clock/0.1)
		if who==player_id:interpolated=_solo_motion_position(interpolated)
		# A burst of delayed snapshots can collapse several steps into one.
		# Allow catch-up without letting the walk jump across the screen.
		var next:=previous.move_toward(interpolated,World.MOVE_TILES_PER_SECOND*1.75*dt)
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
		_update_stroll_companion(visual_position)
		update_camera(visual_position)
	queue_redraw()

## Between the previous and latest authoritative physics tick. Falls back to the snapshot
## target on a stale tick (pause, shutdown, stall), other id/region/travel epoch, or a
## pose far from the snapshot goal (teleport, region change not yet snapshotted).
func _solo_motion_position(fallback:Vector2) -> Vector2:
	var m:=solo_motion
	if m.is_empty() or Engine.get_physics_frames()-int(m.frame)>3 or str(m.id)!=player_id or str(m.region)!=region_id():return fallback
	if int(data.get("players",{}).get(player_id,{}).get("travel_epoch",0))!=int(m.epoch):return fallback
	if not Vector2(m.to).distance_squared_to(Vector2(goals.get(player_id,Vector2.INF)))<=1.0:return fallback
	return Vector2(m.from).lerp(Vector2(m.to),clampf(Engine.get_physics_interpolation_fraction(),0.0,1.0))

func _update_stroll_companion(position:Vector2) -> void:
	var own:Dictionary=data.get(World.LANTERN_STROLL.VIEW_KEY,{})
	var tour:Dictionary=data.get(World.LANTERN_STROLL.KEY,{})
	stroll_companion=Vector2.INF
	if not own.get("companion",false) or int(tour.get("count",0))!=1 or region_id()!=World.REGIONS.HOME:
		stroll_trail.clear()
		return
	if not stroll_trail.is_empty() and stroll_trail.back().distance_to(position)>2.25:stroll_trail.clear()
	if stroll_trail.is_empty() or stroll_trail.back().distance_to(position)>=0.15:stroll_trail.append(position)
	while stroll_trail.size()>12:stroll_trail.pop_front()
	var left:=1.0
	var newer:=position
	for index in range(stroll_trail.size()-1,-1,-1):
		var older:=stroll_trail[index]
		var span:=newer.distance_to(older)
		if span>=left:
			stroll_companion=newer.lerp(older,left/span)
			return
		left-=span
		newer=older

func update_camera(position:Vector2,recenter:bool=false) -> void:
	var extent:=get_viewport_rect().size
	var scale_value:=view_zoom()
	var frame:=Vector3(extent.x,extent.y,scale_value)
	var centered:=position*TILE-camera_anchor(extent)/scale_value
	if recenter or not fixed_area_camera or camera_frame!=frame:
		camera=centered.round()
	else:
		var margin:=fixed_camera_margin(extent)/scale_value
		camera=camera.clamp((centered-margin).ceil(),(centered+margin).floor())
	camera_frame=frame

func camera_anchor(extent:Vector2) -> Vector2:
	return extent*0.5+Vector2(0,40) if village_art_preview else Vector2(740,460)

static func fixed_camera_margin(extent:Vector2) -> Vector2:
	return Vector2(minf(extent.x*0.10,112.0),minf(extent.y*0.09,72.0))

func view_interest_half() -> Vector2i:
	var extent:=get_viewport_rect().size
	var anchor:=camera_anchor(extent)
	var reach:=anchor.max(extent-anchor)
	if fixed_area_camera:reach+=fixed_camera_margin(extent)
	# Include off-screen sprites, draw-loop padding and time to receive the next snapshot.
	return Vector2i((reach/(view_zoom()*TILE)).ceil())+Vector2i(7,7)

func drawn_cells() -> Rect2i:
	var size:=get_viewport_rect().size/(view_zoom()*TILE)
	var origin:=Vector2i((camera/TILE).floor())-Vector2i(2,2)
	return Rect2i(origin,Vector2i(size.ceil())+Vector2i(5,6))

# Tile keys depend only on coordinates. Share the bounded rows across views,
# leaving coordinates outside the world on the existing formatting path.
static func _draw_key_row(y:int) -> PackedStringArray:
	if y<0 or y>=World.SIZE.y:return PackedStringArray()
	if not _draw_key_rows.has(y):
		var row:=PackedStringArray()
		row.resize(World.SIZE.x)
		for x in World.SIZE.x:
			row[x]=World.key(Vector2i(x,y))
		_draw_key_rows[y]=row
	return _draw_key_rows[y]

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

## --- Boundary edges (EdgeGrid rows {type,owner,open}) -------------------------------------------

## Viewport/screen pixel -> world tile coordinates (fractional), same mapping as to_cell().
func screen_to_world(screen_pos:Vector2) -> Vector2:
	return (screen_pos/view_zoom()+camera)/TILE

## Nearest side of the hovered cell for a fractional world position (tile units).
## Returns {cell:Vector2i, side:int} with side one of EdgeGrid.SIDE_N/E/S/W (not canonicalised).
func nearest_edge(world_space:Vector2) -> Dictionary:
	var cell:=Vector2i(world_space.floor())
	var f:=world_space-Vector2(cell)
	var side:=EdgeGrid.SIDE_N
	var best:=f.y
	if f.x<best:
		side=EdgeGrid.SIDE_W
		best=f.x
	if 1.0-f.x<best:
		side=EdgeGrid.SIDE_E
		best=1.0-f.x
	if 1.0-f.y<best:side=EdgeGrid.SIDE_S
	return {"cell":cell,"side":side}

func _edge_line_distance(world_space:Vector2,cell:Vector2i,side:int) -> float:
	var f:=world_space-Vector2(cell)
	match side:
		EdgeGrid.SIDE_N:return absf(f.y)
		EdgeGrid.SIDE_S:return absf(1.0-f.y)
		EdgeGrid.SIDE_W:return absf(f.x)
	return absf(1.0-f.x)

## Hovered edge context at the mouse (or edge_pointer_override), or {} when edge_preview_kind is ""
## or nothing qualifies. Keys: cell/side (hovered cell and its raw side N/E/S/W), key (canonical
## EdgeGrid key), edge_cell/edge_side (canonical owner cell, side N or W), kind (= edge_preview_kind),
## exists, existing_type, open, distance (tiles from the line).
## construction kinds: always the nearest side of the hovered cell.
## "remove_edge": only an EXISTING edge within EDGE_REMOVE_REACH of its line; {} elsewhere so the
## caller keeps its ordinary tile removal.
func target_edge() -> Dictionary:
	if not is_inside_tree():return {}
	var pointer:=edge_pointer_override if edge_pointer_override.is_finite() else get_viewport().get_mouse_position()
	return target_edge_at(pointer)

## Same as target_edge() for an explicit viewport pixel; `kind` defaults to edge_preview_kind.
func target_edge_at(screen_pos:Vector2,kind:String=edge_preview_kind) -> Dictionary:
	if kind=="" or data.is_empty():return {}
	var world_space:=screen_to_world(screen_pos)
	var edges=data.get("edges",{})
	if not (edges is Dictionary):edges={}
	var pick:=nearest_edge(world_space)
	if kind=="remove_edge":
		var best:=-1
		var best_distance:=EDGE_REMOVE_REACH
		for side in EdgeGrid.SIDE_COUNT:
			var candidate:=EdgeGrid.key(pick.cell,side)
			if candidate=="" or not edges.has(candidate):continue
			var gap:=_edge_line_distance(world_space,pick.cell,side)
			if gap<=best_distance:
				best=side
				best_distance=gap
		if best<0:return {}
		pick.side=best
	var canonical:=EdgeGrid.canonical(pick.cell,pick.side)
	if canonical.is_empty():return {}
	var edge_key:=EdgeGrid.key(canonical.cell,canonical.side)
	var row=edges.get(edge_key,{})
	if not (row is Dictionary):row={}
	return {"cell":pick.cell,"side":pick.side,"key":edge_key,"edge_cell":canonical.cell,"edge_side":canonical.side,
		"kind":kind,"exists":not row.is_empty(),"existing_type":str(row.get("type","")),"open":bool(row.get("open",false)),
		"distance":_edge_line_distance(world_space,pick.cell,pick.side)}

func edge_preview_context() -> Dictionary:
	if edge_preview_kind=="" or not show_target or photograph_mode or data.is_empty():return {}
	return target_edge()

func draw_edge_preview(context:Dictionary) -> void:
	var at:=screen(Vector2(context.edge_cell))
	var side:int=context.edge_side
	if str(context.kind)=="remove_edge":
		EdgeArt.draw_marker(self,at,side,Color("df8c79"),0.28)
		return
	var legal:bool=edge_preview_valid and not context.exists
	for cell:Vector2i in EdgeGrid.cells_of(context.key):
		if not World.land(cell,region_id()):legal=false
	var tint:=Color.WHITE if legal else Color(1.0,0.62,0.55)
	EdgeArt.draw_edge(self,at,side,str(context.kind),false,tint,0.62)
	EdgeArt.draw_marker(self,at,side,Color("fff4c2") if legal else Color("df8c79"))

func _index_edges() -> void:
	_edge_rows_n.clear()
	_edge_rows_w.clear()
	var edges=data.get("edges",null)
	_edge_ref=edges
	if not (edges is Dictionary):return
	if _edge_parse.size()>8192:_edge_parse.clear()
	for edge_key:String in edges:
		var parsed:Vector3i
		if _edge_parse.has(edge_key):
			parsed=_edge_parse[edge_key]
		else:
			parsed=Vector3i(-1,-1,-1)
			var parts:=edge_key.split(",")
			if parts.size()==3 and parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2] in ["N","W"]:
				parsed=Vector3i(int(parts[0]),int(parts[1]),EdgeGrid.SIDE_N if parts[2]=="N" else EdgeGrid.SIDE_W)
			_edge_parse[edge_key]=parsed
		if parsed.z<0:continue
		var bucket:Dictionary=_edge_rows_n if parsed.z==EdgeGrid.SIDE_N else _edge_rows_w
		if not bucket.has(parsed.y):bucket[parsed.y]=[]
		bucket[parsed.y].append([parsed.x,edge_key])

## Draw the visible edges of one row (side N: on the row's top line; side W: on each cell's left line).
func draw_edge_row(y:int,from_x:int,to_x:int,side:int) -> void:
	var edges=data.get("edges",{})
	if not (edges is Dictionary) or edges.is_empty():return
	var list:Array=(_edge_rows_n if side==EdgeGrid.SIDE_N else _edge_rows_w).get(y,[])
	if list.is_empty():return
	var local:Vector2=display_positions.get(player_id,Vector2.INF)
	for entry:Array in list:
		var x:int=entry[0]
		if x<from_x-1 or x>to_x:continue
		var row=edges.get(entry[1],{})
		if not (row is Dictionary):continue
		var kind:=str(row.get("type",""))
		if not EdgeArt.is_kind(kind):continue
		var alpha:=1.0
		# A walker just behind a front-facing wall would be hidden to the knees: see through it.
		if side==EdgeGrid.SIDE_N and local.is_finite() and local.y<float(y) and local.y>=float(y)-0.95 and local.x>float(x)-0.35 and local.x<float(x)+1.35:
			alpha=0.5
		EdgeArt.draw_edge(self,screen(Vector2(x,y)),side,kind,bool(row.get("open",false)),build_tint(str(row.get("style",""))),alpha)

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
	if not is_same(data.get("edges",null),_edge_ref):_index_edges()
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*view_zoom())
	world_labels.clear()
	character_label_obstacles.clear()
	focused_label="" if hide_interaction_prompt else interaction_focus()
	var size:=get_viewport_rect().size/view_zoom()
	var region:=region_id()
	var home:=region==World.REGIONS.HOME
	var star_garden:=region==World.REGIONS.StarGarden.REGION
	var bamboo:=region==World.REGIONS.Bamboo.REGION
	var aru_scene:=AruRest.scene(data) if home else {}
	var aru_sitters:Dictionary=aru_scene.get("sitters",{})
	if aru_sitters.has(player_id) and not hide_interaction_prompt:focused_label="aru"
	var deer_site:=World.Deer.site(data) if home and World.Deer.present(data) else Vector2i(-1,-1)
	var courtyard:=home and World.WANGAN_MEMORY.courtyard_available(data)
	var mining:=region_id()=="jinguashi"
	var cart_gallery:=region_id()==World.PARTY_CART.REGION
	var transit:=TransitArt.NAMES.has(region_id())
	var tea_region:=region_id() in ["maokong","yingge"]
	var flower_region:=region_id()==World.FLOWER_NURSERY.REGION
	var salt_region:=region_id()==World.SALT_PAN.REGION
	var tea_house:=World.TEA_HOUSE_INTERIOR
	var in_tea_house:bool=region_id()==tea_house.REGION and tea_house.inside(data.players.get(player_id,{}))
	var tea_anchors:Dictionary={}
	if region_id()==tea_house.REGION:tea_house.points(data,data.players.get(player_id,{}),tea_anchors)
	var pottery:=World.POTTERY_WORKSHOP_INTERIOR
	var in_pottery:=pottery_inside()
	var pottery_anchors:Dictionary={}
	if region_id()==pottery.REGION:pottery.points(data.players.get(player_id,{}),pottery_anchors)
	var tea_sites:Dictionary={} if in_tea_house or in_pottery else tea_points(region_id(),data)
	var tea_record:Dictionary=data.get("tea_ceramics",{}).get("own_record",{}) if tea_region else {}
	var resident_at_station:Dictionary=World.STATION_LIFE.RESIDENTS.get(region_id(),{})
	var station_repaired:bool=data.get("station_life",{}).get("repairs",{}).get(region_id(),false)
	var bobo_sites:Dictionary=World.Village.Workshop.sites(data) if mining else {}
	var depth:=int(region_id().trim_prefix("mine_")) if region_id().begins_with("mine_") else 0
	var survey_cell:Vector2i=World.MINE_SURVEY.POINTS.get(depth,Vector2i(-1,-1))
	var guardian_open:=Guardian.available(region_id(),int(data.get("mine_depths",{}).get("unlocked",1)))
	var guardian_record:Dictionary=GuardianUI.record_of(data,player_id) if guardian_open else {}
	var guardian_trial:Dictionary=data.get(World.GUARDIAN_TRIAL.KEY,{}) if guardian_open and not Guardian.awake(guardian_record) else {}
	var shy_open:=bool(data.get("picnic",false)) and Shy.available(region_id(),int(data.get("mine_depths",{}).get("unlocked",1)))
	var shy_record:Dictionary=ShyUI.record_of(data,player_id) if shy_open else {}
	var shy_adventure:=shy_open and data.has(World.SHY_SPORES.VIEW) and not Shy.open(shy_record)
	var shy_spore:Dictionary=data.get(World.SHY_SPORES.VIEW,{}) if shy_adventure else {}
	var porter_open:bool=data.get("porter_available",false)
	var meadow_open:bool=data.get(World.MEADOW.AVAILABLE,false)
	var meadow_record:=int(data.players.get(player_id,{}).get(World.MEADOW.FIELD,0))
	var meadow_trial:=World.MEADOW_ADVENTURE
	var meadow_round:Dictionary=data.get(meadow_trial.VIEW,{})
	var meadow_phase:=int(meadow_round.get("phase",-1))
	var meadow_now:=float(data.get("time",0.0))
	var porter_viewer:Dictionary=data.players.get(player_id,{})
	var porter_stage:=int(porter_viewer.get(World.PORTER.FIELD,0))
	var porter_step:=World.PORTER.visible_step(porter_stage,data) if porter_open else {}
	var porter_watches:Array=data.get("porter_watches",[])
	var porter_viewer_pos:=Vector2(porter_viewer.get("x",-999.0),porter_viewer.get("y",-999.0))
	var porter_position:=World.PORTER.mouse_feet(porter_stage)
	var porter_duration:=0.55 if porter_stage==World.PORTER.Stage.DELIVERED else PORTER_TRAVEL_SECONDS
	var porter_walking:=porter_open and not reduced_motion and porter_stage in [World.PORTER.Stage.TO_MIDDLE,World.PORTER.Stage.TO_CRATE,World.PORTER.Stage.DELIVERED] and elapsed-porter_walk_started<porter_duration
	if porter_walking:
		var travel:=smoothstep(0.0,porter_duration,elapsed-porter_walk_started)
		porter_position=World.PORTER.mouse_feet(porter_stage-1).lerp(porter_position,travel)
	var placing_drill:=show_target and selected=="build" and building=="mine_drill" and depth>0
	var festival:Dictionary=data.get("festival",{})
	var bell_cell:=World.Festival.target(festival) if home and festival.get("active",false) else Vector2i(-1000,-1000)
	var relay_cells:Dictionary=CookingRelayArt.cell_map(data) if home else {}
	var stroll_sites:=StrollArt.markers(data)
	var chicks_open:=home and LostChicksArt.available(data)
	var chicks_pen:=chicks_open and LostChicksArt.pen_shown(data)
	var drawn:=drawn_cells()
	var from:=drawn.position
	var to:=drawn.end
	roof_faded=RoofVisibility.faded(data,player_id,display_positions.get(player_id,Vector2.INF))
	var springs:=World.WARM_SPRINGS
	var in_springs:=region_id()==springs.REGION
	var in_star_garden:=region_id()==World.RESIDENT_BOND.GARDEN_REGION
	var diandian_sitting:bool=in_star_garden and data.players.values().any(func(person:Dictionary):return person.get(World.RESIDENT_GOALS.DIANDIAN_SEAT_KEY,false))
	var in_inn:=in_springs and springs.in_inn(data.players.get(player_id,{}))
	draw_rect(Rect2(Vector2.ZERO,size),Color("74b8b0"))
	if not home and village_art:village_art.release_chunks()
	var bridge_built:=home and World.STONE_WORKSHOP.bridge_open(data)
	var star_walk:=home and bool(data.get("wangan_star_walk",false))
	var chunked:bool=home and village_art!=null and village_art.draw_base(self,camera,drawn)
	var base_complete:bool=chunked and village_art.visible_base_complete
	var ground:Dictionary=data.ground
	var crops:Dictionary=data.crops
	var forest:Dictionary=data.get("forest",{})
	var objects:Dictionary=data.objects
	var stumps:Dictionary=World.WOODLAND.stumps(data) if home else {}
	for y in range(from.y,to.y):
		var keys:=_draw_key_row(y)
		var key_count:=keys.size()
		var decorations:=VillagePreview.ground_decoration_row(y) if home and village_art else PackedByteArray()
		var decoration_count:=decorations.size()
		for x in range(from.x,to.x):
			var p:=Vector2i(x,y)
			var k:=keys[x] if x>=0 and x<key_count else World.key(p)
			if home and village_art:
				var star_tile:=star_walk and World.WANGAN_COAST.star_boardwalk(p)
				var draw_terrain:bool=not chunked or (not base_complete and not village_art.has_base_tile(p)) or star_tile or (bridge_built and VillagePreview.bridge_variant(p))
				var index:=x-VillagePreview.SHORE_BOUNDS.position.x
				var prop:=decorations[index] if index>=0 and index<decoration_count else 0
				var floor_tile:Variant=ground.get(k)
				var crop:Variant=crops.get(k)
				if not draw_terrain and prop==0 and floor_tile==null and crop==null:continue
				var at:=screen(Vector2(p))
				if draw_terrain:village_art.draw_terrain_tile(self,at,p,bridge_built,star_tile)
				if prop!=0 and floor_tile==null and crop==null and not objects.has(k) and not forest.has(k):
					village_art.draw_prop(self,at,prop-1,0.5)
				if (floor_tile!=null or crop!=null) and not VillagePreview.wet_at(p,bridge_built):
					if floor_tile!=null:ground_tile(at,floor_tile.type,str(floor_tile.get("style","")))
					if crop!=null:crop_tile(at,crop)
				continue
			var at:=screen(Vector2(p))
			if cart_gallery:
				PartyCartArt.draw_floor(self,at,p)
				continue
			if in_tea_house:
				if tea_house.ROOM.has_point(p):ground_tile(at,"floor","tea_house")
				else:draw_rect(Rect2(at,Vector2(32,32)),Color("241e1b"))
				continue
			if in_pottery:
				if pottery.ROOM.has_point(p):_draw_pottery_ground(at,p)
				else:draw_rect(Rect2(at,Vector2(32,32)),Color("211a16"))
				continue
			if in_springs:
				if in_inn:
					if springs.INN_ROOM.has_point(p):ground_tile(at,"floor","tea_house")
					else:draw_rect(Rect2(at,Vector2(32,32)),Color("241e1b"))
				else:springs.ground(self,at,p)
				_draw_leaf_mat(at,k)
				continue
			if star_garden:
				World.REGIONS.StarGarden.ground(self,at,p)
				_draw_leaf_mat(at,k)
				continue
			if bamboo:
				World.REGIONS.Bamboo.ground(self,at,p)
				_draw_leaf_mat(at,k)
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
					_draw_leaf_mat(at,k)
					continue
				elif transit:
					TransitArt.ground(self,at,p,region_id(),not outer_wet)
					_draw_leaf_mat(at,k)
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
			if VillagePreview.wet_at(p,bridge_built):
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
			if x in [55,56] and bridge_built:
				draw_rect(Rect2(at,Vector2(32,32)),Color("99744c"))
				for j in range(4):draw_rect(Rect2(at+Vector2(1,j*8),Vector2(30,6)),Color("cfaa70"))
			if data.ground.has(k):ground_tile(at,data.ground[k].type,str(data.ground[k].get("style","")))
			if data.crops.has(k):crop_tile(at,data.crops[k])
	if focused_label=="leaf_mat":
		var mat_cell:=LeafMatArt.own_mat_cell(data,player_id)
		world_label(screen(Vector2(mat_cell))+Vector2(34,26),"地墊換色","leaf_mat",true)
	if focused_label==World.FOREST_MUSHROOM.SURVEY_POINT:
		var observer: Dictionary=data.players.get(player_id,{})
		var tree:=World.forest_mushroom_tree(data,Vector2(observer.get("x",0.0),observer.get("y",0.0)))
		if tree!=World.FOREST_MUSHROOM.NO_TREE:
			world_label(screen(Vector2(tree))+Vector2(16,-46),"察看樹下濕氣",World.FOREST_MUSHROOM.SURVEY_POINT)
	if depth>0:MineArt.draw_perimeter(self,screen(Vector2.ZERO),depth,elapsed,reduced_motion)
	if focused_label.begins_with("plot:"):
		var crop_cell:=World.cell(focused_label.trim_prefix("plot:"))
		world_label(screen(Vector2(crop_cell)+Vector2(0.5,0.0))+Vector2(0,-5),"查看農田",focused_label)
	if guardian_trial.has("bounds"):_draw_guardian_strike(guardian_trial)
	if not shy_spore.is_empty():
		var spores:=World.SHY_SPORES
		if shy_spore.phase==spores.Phase.WARNING:
			ShyArt.draw_spore_path(self,screen(Vector2(shy_spore.lane,spores.ORIGIN_Y)),screen(Vector2(shy_spore.lane,spores.EXIT_Y)),spores.HIT_RADIUS*TILE)
		elif shy_spore.phase==spores.Phase.PASSING:
			var speed:float=(spores.ORIGIN_Y-spores.EXIT_Y)/spores.PASS_TIME
			var interpolated_y:=maxf(spores.EXIT_Y,float(shy_spore.y)-minf(elapsed-shy_spore_received,0.1)*speed)
			ShyArt.draw_spore(self,screen(Vector2(shy_spore.lane,interpolated_y)),spores.HIT_RADIUS*TILE,0.0 if reduced_motion else sin(elapsed*4.0)*2.0)
	if meadow_open and meadow_phase==meadow_trial.Phase.WARNING:
		_draw_meadow_ring(meadow_trial.PULSE_RADIUS*TILE,Color("#f4aa67"),0.22)
	elif meadow_open and meadow_phase==meadow_trial.Phase.LANTERNS and not reduced_motion:
		var since:=meadow_now-float(meadow_round.pulse_at)
		if since>=0.0 and since<0.48:
			var wave:=since/0.48
			_draw_meadow_ring(meadow_trial.PULSE_RADIUS*TILE*lerpf(0.25,1.0,wave),Color("#ffebad",1.0-wave),0.07*(1.0-wave))
	if courtyard:
		var court:Rect2i=World.WANGAN_MEMORY.COURT
		for y in range(court.position.y,court.end.y):
			for x in range(court.position.x,court.end.x):
				ground_tile(screen(Vector2(x,y)),"spring_pebble_path")
	if home:
		var coast:=World.WANGAN_COAST
		if selected=="fish" and World.STONE_WORKSHOP.bridge_open(data):
			world_label(screen(Vector2(55,27))+Vector2(-110,0),"河灣橋釣點・橋邊限定魚","bridge_pool")
			var shoal:=World.STONE_WORKSHOP.SHOAL_RECT.position
			world_label(screen(Vector2(shoal))+Vector2(-58,18),World.STONE_WORKSHOP.SHOAL_LABEL,World.STONE_WORKSHOP.SHOAL_SPOT)
		var pool_at:=screen(Vector2(coast.STAR_POOL.position))
		if Rect2(Vector2.ZERO,size).intersects(Rect2(pool_at-Vector2(8,6),Vector2(80,44))):
			coast.draw_star_pool(self,pool_at,float(data.get("time",0.0)),elapsed,reduced_motion)
			if selected=="fish" and data.get("wangan_star_walk",false):
				world_label(pool_at+Vector2(32,-16),"星砂潮池・金邊蝦","star_tidepool")
		var anchor:=screen(coast.WEIR_AT)
		if Rect2(Vector2.ZERO,size).intersects(Rect2(anchor,coast.WEIR_SIZE)):
			coast.draw_weir(self,anchor,float(data.get("time",0.0)),elapsed,reduced_motion)
	if salt_region:draw_salt_pans()
	var visible_ground:=Rect2i(from,to-from)
	for key:String in data.objects:
		var rug:Dictionary=data.objects[key]
		if rug.type==Industry.INDIGO_CUSHION:
			var cushion_tile:=World.cell(key)
			if visible_ground.has_point(cushion_tile):
				var cushion_at:=screen(Vector2(cushion_tile))
				draw_texture(INDIGO_CUSHION_ART,cushion_at+INDIGO_CUSHION_AT)
				if key==focused_label:
					var own_seat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
					world_label(cushion_at+Vector2(16,-44),"起身" if own_seat.get("cell")==key else World.BUILD[Industry.INDIGO_CUSHION].name,key)
			continue
		if rug.type!=Industry.BRAIDED_RUG or Industry.square_part(rug)!=0:continue
		var tile:=World.cell(key)
		if visible_ground.has_point(tile):draw_texture(BRAIDED_RUG_ART,screen(Vector2(tile)))
	if in_springs and in_inn and visible_ground.has_point(springs.INN_RUG_ANCHOR):
		draw_texture(BRAIDED_RUG_ART,screen(Vector2(springs.INN_RUG_ANCHOR)))
	if in_inn and visible_ground.has_point(Vector2i(62,25)):
		draw_texture(BRAIDED_RUG_ART,screen(Vector2(62,24.5)),Color("b9d0bb"))
	if in_inn:_draw_inn_mats()
	if in_tea_house:_draw_tea_house_floor(tea_house)
	if in_pottery:_draw_pottery_floor(pottery)
	if not in_inn and not in_tea_house and not in_pottery and depth==0:draw_night_ground(size,from,to)
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
	var spring_ids:Array[String]=[]
	if home:spring_ids=SpringGardenArt.ids(data)
	var guests_today:Array=market_guests()
	var voyage_passengers:Dictionary={}
	var garden_seating:Dictionary={}
	for id:String in data.players:
		var person:Dictionary=data.players[id]
		var skipper:String=person.get("voyage_captain","")
		if not skipper.is_empty() and data.players.get(skipper,{}).get("at_sea",false):voyage_passengers[skipper]=id
		var seat:Dictionary=person.get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
		var seat_key:String=seat.get("cell","")
		var seat_furniture:Dictionary=data.objects.get(seat_key,{})
		if seat_furniture.get("type")==World.RESIDENT_GOALS.GARDEN_CHAIR:
			garden_seating[id]=Vector2(World.cell(seat_key))+Vector2(0.5,0.76)
		elif seat_furniture.get("type")==Industry.WOOD_CHAIR:
			garden_seating[id]=Vector2(World.cell(seat_key))+Vector2(0.5,0.91)
		elif seat_furniture.get("type") in World.RESIDENT_GOALS.INDEPENDENT_TWO_SEATS:
			var side:=int(seat.get("side",0))
			var offset:=Vector2(0.48+side,0.86)
			if seat_furniture.get("bench_vertical",false):offset=Vector2(0.46+side*0.10,0.72+side*1.02)
			garden_seating[id]=Vector2(World.cell(seat_key))+offset
		elif seat_furniture.get("type")==Industry.MUSHROOM_STOOL:
			garden_seating[id]=Vector2(World.cell(seat_key))+Industry.MUSHROOM_STOOL_FEET
		elif seat_furniture.get("type")==Industry.INDIGO_CUSHION:
			garden_seating[id]=Vector2(World.cell(seat_key))+Industry.INDIGO_CUSHION_FEET
		elif seat_furniture.get("type")==Industry.BEACH_CHAIR:
			var offset:=Vector2(0.5,1.22) if Industry.is_vertical(seat_furniture) else Vector2(1.0,0.80)
			garden_seating[id]=Vector2(World.cell(seat_key))+offset
		elif seat_furniture.get("type")==Industry.MUSHROOM_TABLE and int(seat.side) in range(Industry.MUSHROOM_SEATS.size()):
			garden_seating[id]=Vector2(World.cell(seat_key))+Industry.MUSHROOM_SEATS[int(seat.side)]
		elif seat_furniture.get("type")==Industry.BAMBOO_TEA_TABLE and int(seat.side) in range(4):
			garden_seating[id]=Vector2(World.cell(seat_key))+Industry.tea_table_seats(Industry.is_vertical(seat_furniture))[int(seat.side)]
		elif seat_furniture.get("type")==Industry.SHELL_TABLE:
			var x:=0.04 if int(seat.side)==0 else 0.96
			garden_seating[id]=Vector2(World.cell(seat_key))+Vector2(x,0.91)
	var harvest_on:=home and HarvestUI.on_field(data)
	# T071 河岸釣魚會：進行中時用繩索與浮標標出指定水域（地面層之上、人物之下）。
	var fishmeet_on:=home and FishMeetUI.on_field(data)
	if fishmeet_on and FishMeetUI.waters_marked(data):FishMeetUI.draw_waters(self,elapsed,reduced_motion)
	# T071 家園布置題：解鎖後在地面層標出臨時展示地塊（靜態）；道具與告示牌在下面的列排序裡畫。
	var showcase_plot:=home and ShowcaseUI.plot_shown(data)
	var showcase_sign:=home and ShowcaseUI.sign_shown(data)
	var showcase_target:=ShowcaseUI.view_target(self) if focused_label==ShowcaseUI.PLOT_POINT else ShowcaseUI.NO_CELL
	hedgehog_nap_cell=World.Hedgehog.NO_BASKET
	if home:
		hedgehog_nap_cell=World.Hedgehog.nap_cell(data,data.get("players",{}).get(player_id,{}))
		draw_hedgehog_site()
	if showcase_plot:ShowcaseUI.draw_plot(self,data,showcase_target)
	# T071 紀念品交換攤：渡口野餐後、使用中的攤位格（暫停時不畫）。
	var souvenir_cell:=SouvenirUI.booth_cell(data) if home else SouvenirUI.NO_CELL
	var tiller_rack_cell:Vector2i=World.PUBLIC_TILLER.site(data) if home else World.PUBLIC_TILLER.NO_SITE
	# 暖燈夜：lantern statues (display only), y-sorted with the village objects below.
	var warm_cells:Dictionary=WarmLanternArt.cells(data) if home else {}
	var warm_lit:Dictionary=WarmLanternArt.lamps(data) if not warm_cells.is_empty() else {}
	# 第 40 章風鈴節廣場地方記憶展：風鈴節開幕後、使用中的展台格（暫停時不畫）。
	var exhibit_cell:=MemoryExhibitUI.stand_cell(data) if home else MemoryExhibitUI.NO_CELL
	# 望安開場：小栗留的田（木樁、麻繩與名牌），只給還在第一株作物步驟的本人看；
	# 地面層之上、道具與人物之下，首次出貨後消失。
	var first_crop:=World.CHAPTER_ONE.first_crop_step(data,player_id) if home else {}
	first_crop_cue_rect=WanganUI.draw_plot(self,data,player_id,first_crop) if home else Rect2()
	var canopies:Array[Vector2i]=[]
	var pavilions:Array[Vector2i]=[]
	var visible_props:=Rect2i(from,to-from).grow(3)
	for key:String in data.get("objects",{}):
		var awning:Dictionary=data.objects[key]
		var awning_type:String=str(awning.get("type",""))
		if awning_type==Industry.IMPERFECT_TEA_PAVILION and Industry.square_part(awning)==0:
			var shelter_cell:=World.cell(key)
			# T12: ground, shadow and the lower four posts sit under every walker; the canopy follows later.
			if visible_props.has_point(shelter_cell):
				pavilions.append(shelter_cell)
				PavilionArt.draw_base(self,screen(Vector2(shelter_cell)))
			continue
		if awning_type!=Industry.COAST_AWNING or Industry.square_part(awning)!=0:continue
		var tile:=World.cell(key)
		if not visible_props.has_point(tile):continue
		canopies.append(tile)
		CoastAwningArt.draw_shadow(self,screen(Vector2(tile)),Industry.is_vertical(awning))
	draw_fox_clues()
	var exit_cell:=World.REGIONS.exit_cell(region_id())
	if (transit or tea_region) and not in_tea_house and not in_pottery:
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
	var cart_story:=mining and OreRouteSelect.story_active(data)
	var cart_stage:=OreRouteSelect.cart_stage(data) if mining else 0
	var cart_position:=ore_cart_position(cart_stage) if mining else Vector2.ZERO
	# 抵達後空車留在展覽位置（卸礦台旁），和一般台車分開畫、分開命名。
	var exhibit_cart:=mining and OreRouteSelect.story_arrived(data) and World.ORE_ROUTE.stage(data)!=World.ORE_ROUTE.LAST
	var exhibit_position:=Vector2(World.ORE_ROUTE.STOPS.back())
	if exhibit_cart and ore_cart_push_story:exhibit_position=ore_cart_position(World.ORE_ROUTE.LAST)
	var gardener_cell:=lanyang_gardener_cell() if region_id()==World.REGIONS.LANYANG else Vector2i(-1,-1)
	var own_rest_key:=str(data.players.get(player_id,{}).get(springs.REST_SEAT_KEY,""))
	var rest_choice:=springs.rest_choice(own_rest_key) # 主位或第二座位都對應同一處
	var rest_cell:Vector2i=springs.REST_SEATS.get(rest_choice,Vector2i(-1,-1))
	# 暖暖的單人備案：只有自己坐主位、且沒有真人朋友坐在第二座位時才畫在同伴位置。
	var solo_companion:=rest_cell.x>=0 and own_rest_key==rest_choice and not springs.rest_occupied(data.players,"friend:"+rest_choice)
	if in_inn:
		var runner:=Rect2(screen(Vector2(65.15,22.0)),Vector2(22,154))
		draw_rect(runner,Color("4d7667"))
		draw_rect(runner.grow(-3),Color("d0ab73"),false,1.0)
		for mark in range(5):
			var at:=runner.position+Vector2(11,14+32*mark)
			draw_colored_polygon(PackedVector2Array([at-Vector2(0,5),at+Vector2(5,0),at+Vector2(0,5),at-Vector2(5,0)]),Color("bd8d59"))
	# Draw all tall props and people in row order, keeping feet as sorting origin.
	# Resolve each resident's spot once. Searching for a free spot can consult
	# several map layers, and its answer only depends on this frame's snapshot.
	var village_residents:Dictionary={}
	for resident:String in World.Village.ids_for_region(region):
		if resident=="xiaoli":continue # Already drawn behind the seed stall.
		if photograph_mode and resident==photo_guest:continue # Joins the table below.
		if not aru_scene.is_empty() and resident=="aru":continue
		village_residents[resident]=World.Village.resident_cell(data,resident)
	var visiting_residents:Dictionary={}
	for resident:String in World.RESIDENT_BOND.WALK_UP:
		if resident=="nuannuan" and in_springs and rest_cell.x>=0:continue
		if not World.RESIDENT_BOND.present(data,resident):continue
		var spot:Array=World.bond_place(data,resident)
		if str(spot[0])==region:visiting_residents[resident]=spot[1]
	var has_beach_treasure:=BeachTreasureArt.available(data)
	var festival_story_open:bool=data.get("festival_story_open",false)
	for y in range(from.y,to.y):
		# Horizontal (N/S) edges sit on this row's top line: behind this row, in front of the row above.
		draw_edge_row(y,from.x,to.x,EdgeGrid.SIDE_N)
		var keys:=_draw_key_row(y)
		var key_count:=keys.size()
		for x in range(from.x,to.x):
			var p:=Vector2i(x,y)
			var at:=screen(Vector2(p))
			var k:=keys[x] if x>=0 and x<key_count else World.key(p)
			if in_pottery:continue
			if tea_region and not in_tea_house:
				if region_id()==pottery.REGION and p==pottery.DOOR:_draw_pottery_doorway(at)
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
				if data.objects.has(k) and data.objects[k].type not in PASS_DRAWN_OBJECTS:object_sprite(at,data.objects[k].type,data.objects[k])
				continue
			if salt_region:
				if x==from.x:draw_salt_row(y)
				if data.objects.has(k) and data.objects[k].type not in PASS_DRAWN_OBJECTS:object_sprite(at,data.objects[k].type,data.objects[k])
				continue
			if transit:
				TransitArt.roadside(self,at,p,region_id(),village_art)
				if p==StationLifeArt.CORNERS[region_id()] and not lanyang_cell_occupied(p):
					StationLifeArt.draw_corner(self,at,station_repaired)
				continue
			if bamboo and p in World.REGIONS.Bamboo.CLUMPS:
				var ripe:=World.REGIONS.Bamboo.ready(data,p)
				World.REGIONS.Bamboo.draw_clump(self,at,ripe)
				if show_target and p==target:
					var caption:="用斧頭採竹材" if ripe else "竹叢正在長新枝"
					world_label(at+Vector2(16,-37 if ripe else -13),caption,"")
				continue
			if forest.has(k):
				var planted:Dictionary=forest[k]
				if planted.mature:
					tree(at)
					if show_target and p==target and selected=="axe":world_label(at+Vector2(16,-36),"栽培成樹 · 可採硬木","")
				else:sapling(at,float(planted.growth)/World.TREE_TIME)
			elif stumps.has(k):
				draw_texture(preload("res://assets/forestry/woodland-stump.png"),at)
				if show_target and p==target and selected in ["axe","remove"]:
					world_label(at+Vector2(16,-6),"資源林樹樁 · 可保留再生","",false)
			elif not data.removed.has(k):
				var resource:String=home_base_resource(p) if home else World.base_resource(p,region_id())
				if resource=="tree":tree(at)
				elif resource=="rock":rock(at)
				elif resource=="grass":grass(at)
			if tool_feedback.finishes.has(k) and not forest.has(k) and not objects.has(k) and not crops.has(k):
				draw_resource_finish(at,p)
			if objects.has(k) and objects[k].type not in PASS_DRAWN_OBJECTS:object_sprite(at,objects[k].type,objects[k])
			if depth==0 and not cart_gallery and p==exit_cell and (not home or data.get("picnic",false)):
				if not data.objects.has(k) and not data.crops.has(k) and not data.get("forest",{}).has(k) and not data.ground.has(k) and not data.get("roofs",{}).has(k):LanyangArt.draw_exit(self,at)
				var gate:=World.TRANSIT.point_at(region_id(),p)
				var caption:String=World.TRANSIT.points(region_id())[gate].label if not gate.is_empty() else "回風鈴渡口"
				if home and gate=="ferry" and int(data.get("dock_stage",0))>0:
					caption="合作小船" if World.TRANSIT.boat_open(data) else "碼頭已修復"
				world_label(at+Vector2(16,-18),caption,"transit:"+gate if not gate.is_empty() else "travel")
			if cart_gallery or (mining and p==World.PARTY_CART.SURFACE_PORTAL):
				PartyCartArt.draw_site(self,at,p,data)
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
				if guardian_open:
					if p==Guardian.GUARDIAN:
						# Slow blink: frame 1 for a moment every few seconds (never with reduced motion).
						var blink:=not reduced_motion and fmod(elapsed,4.2)>3.8
						var phase:=int(guardian_trial.get("phase",-1))
						var trial:=World.GUARDIAN_TRIAL
						var frame:=Guardian.frame(guardian_record,blink)
						if phase==trial.Phase.WARNING:frame=2
						elif phase==trial.Phase.IMPACT:frame=3
						GuardianArt.draw_guardian(self,at+Vector2(16,30),frame,elapsed,reduced_motion)
						if phase==trial.Phase.WARNING:
							world_label(at+Vector2(16,-18),"退到標記外 · %d/2"%(int(guardian_trial.attack)+1),GuardianUI.POINT)
						elif phase==trial.Phase.SAFE and focused_label==GuardianUI.POINT:
							world_label(at+Vector2(16,-18),"躲過了 · 靠近石像",GuardianUI.POINT)
						elif focused_label==GuardianUI.POINT:
							world_label(at+Vector2(16,-18),GuardianUI.label(GuardianUI.POINT,guardian_record),GuardianUI.POINT)
					var guardian_bell:=Guardian.bell_at(p)
					if guardian_bell>=0:
						GuardianArt.draw_bell(self,at+Vector2(16,30),guardian_bell,guardian_bell==guardian_lit_bell,elapsed,reduced_motion)
						var bell_id:=GuardianUI.BELL_POINT+str(guardian_bell)
						if focused_label==bell_id:world_label(at+Vector2(16,-30),GuardianUI.label(bell_id,guardian_record),bell_id)
				if shy_open and p==Shy.MUSHROOM:
					# 害羞菇: atlas stage, quiet-wait ring (after the sprite so its pips stay visible), label.
					var shy_foot:=at+ShyUI.FOOT_OFFSET
					ShyArt.draw(self,shy_foot,Shy.frame(shy_record,bool(shy_view.get("responding",false))),elapsed,reduced_motion)
					if shy_adventure:
						if focused_label==ShyUI.POINT or not shy_spore.is_empty():world_label(at+ShyUI.LABEL_OFFSET,ShyUI.spore_label(shy_spore),ShyUI.POINT)
					else:
						ShyArt.draw_ring(self,shy_foot,float(shy_view.get("progress",0.0)),bool(shy_view.get("ready",false)),reduced_motion,elapsed)
						if focused_label==ShyUI.POINT or bool(shy_view.get("watching",false)):world_label(at+ShyUI.LABEL_OFFSET,ShyUI.label(shy_record,shy_view,selected),ShyUI.POINT)
				if porter_open:
					for index in porter_watches.size():
						var marker:Vector2=World.PORTER.WATCH_POINTS[index]
						if p!=Vector2i(marker.floor()):continue
						var center:=screen(marker).round()
						var occupied:bool=porter_watches[index] or porter_viewer_pos.distance_to(marker)<=World.PORTER.WATCH_RADIUS
						var corners:=PackedVector2Array([center+Vector2(0,-6),center+Vector2(9,0),center+Vector2(0,6),center+Vector2(-9,0),center+Vector2(0,-6)])
						draw_colored_polygon(corners.slice(0,4),Color("#485946") if occupied else Color("#65452c"))
						draw_polyline(corners,Color("#d8f7af") if occupied else Color("#ffe0a1"),1.0)
						if occupied:draw_rect(Rect2(center-Vector2(2,1),Vector2(4,2)),Color("#d8f7af"))
						if porter_viewer_pos.distance_to(marker)<1.3:
							world_label(center+Vector2(0,-14),World.PORTER.WATCH_LABELS[index],"porter_watch_%d"%index)
					if p==World.PORTER.CRATE:MineArt.draw_freight(self,at,"crate",-1.0,true,32)
					if p==Vector2i(porter_position.floor()):
						var frame:=3 if porter_stage>=World.PORTER.Stage.DELIVERED else (1+int((elapsed-porter_walk_started)*7.0)%2 if porter_walking else 0)
						var source:=Rect2(Vector2(frame%2,frame/2)*PORTER_FRAME,PORTER_FRAME)
						var foot:=screen(porter_position).round()
						draw_texture_rect_region(PORTER_ATLAS,Rect2(foot-Vector2(16,38),PORTER_FRAME),source)
						if focused_label!=World.PORTER.POINT:world_label(foot+Vector2(0,-34),World.PORTER.NAME,World.PORTER.POINT)
					if focused_label==World.PORTER.POINT and not porter_step.is_empty() and p==porter_step.cell:
						world_label(at+Vector2(16,-20),porter_step.prompt,World.PORTER.POINT)
				if meadow_open and p==World.MEADOW.CENTER:
					var frame:=World.MEADOW.frame(meadow_record)
					if meadow_record<World.MEADOW.ALL_TABLES and meadow_phase>=0:
						frame=1 if meadow_phase<=meadow_trial.Phase.LANTERNS else 2
					var source:=Rect2(Vector2(frame%2,frame/2)*MEADOW_FRAME,MEADOW_FRAME)
					var foot:=screen(World.MEADOW.FACE).round()
					draw_texture_rect_region(MEADOW_ATLAS,Rect2(foot-Vector2(32,62),MEADOW_FRAME),source)
					match focused_label:
						World.MEADOW.POINT:world_label(foot+Vector2(0,-57),"收下毛球的謝禮",focused_label)
						meadow_trial.WAKE_POINT:world_label(foot+Vector2(0,-57),"叫醒毛球 · 開始挑戰",focused_label)
						meadow_trial.CALM_POINT:world_label(foot+Vector2(0,-57),"安撫毛球",focused_label)
						_:
							var title:=World.MEADOW.NAME
							if meadow_phase==meadow_trial.Phase.WARNING:
								title="退到圈外 · %d"%maxi(1,ceili(float(meadow_round.pulse_at)-meadow_now))
							elif meadow_phase==meadow_trial.Phase.LANTERNS:title="點亮供品台 · %d/3"%meadow_round.lamps.count(true)
							elif meadow_phase==meadow_trial.Phase.CALMING:title="一起安撫毛球"
							world_label(foot+Vector2(0,-57),title,World.MEADOW.POINT)
				if meadow_open and p in World.MEADOW.TABLES:
					var index:=World.MEADOW.TABLES.find(p)
					var id:=World.MEADOW.TABLE_PREFIX+str(index)
					var full:=World.MEADOW.table_full(meadow_record,index)
					var lit:bool=meadow_phase>=0 and meadow_round.lamps[index]
					var foot:=screen(World.MEADOW.table_feet(p)).round()
					var source:=Rect2(Vector2(40 if full else 0,0),MEADOW_TABLE_FRAME)
					draw_texture_rect_region(MEADOW_TABLE_ATLAS,Rect2(foot-Vector2(20,38),MEADOW_TABLE_FRAME),source)
					if lit:
						var wick:=foot+Vector2(0,-20)
						draw_rect(Rect2(wick-Vector2(3,0),Vector2(6,4)),Color("#d58a49"))
						draw_rect(Rect2(wick-Vector2(1,3),Vector2(2,6)),Color("#fff1ab"))
					if focused_label==id:world_label(foot+Vector2(0,13),"放一顆蘿蔔",id)
					var light_id:=meadow_trial.LIGHT_PREFIX+str(index)
					if focused_label==light_id:world_label(foot+Vector2(0,13),"點亮供品台",light_id)
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
			if village_art and p in VillagePreview.COASTAL_PROP_CELLS:village_art.draw_coastal_prop(self,at,p)
			if p==World.MILL_RESTORATION.SITE.position and data.get(World.MILL_RESTORATION.SITE_VISIBLE,false):
				draw_public_mill(at)
			if p==World.Festival.TREE_CELL:
				draw_wind_chime_tree(at)
				if focused_label=="lingpopo_tree":world_label(at+Vector2(16,-36),"查看風鈴樹","lingpopo_tree")
			if festival_story_open and World.Festival.VISITORS.has(p):
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
			if p==tiller_rack_cell:
				PublicTillerUI.draw_rack(self,at)
				world_label(at+Vector2(16,PublicTillerUI.label_offset_y()),World.PUBLIC_TILLER.label(data.get("players",{}).get(player_id,{})),PublicTillerUI.POINT)
			if p==souvenir_cell:
				SouvenirUI.draw_booth(self,at)
				world_label(at+Vector2(16,-27),SouvenirUI.booth_title(focused_label==SouvenirUI.POINT),SouvenirUI.POINT)
			if warm_cells.has(p):
				var warm_id:String=warm_cells[p]
				var warm_seed:int=WarmLanternArt.stations().keys().find(warm_id)+1
				WarmLanternArt.draw_station(self,at,str(warm_lit.get(warm_id,"")),elapsed,reduced_motion or photograph_mode,warm_seed)
				var warm_point:=WarmLanternArt.POINT_PREFIX+warm_id
				if focused_label==warm_point:
					world_label(at+WarmLanternArt.LABEL_ANCHOR,WarmLanternArt.prompt(warm_id),warm_point,true)
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
				AutumnFeastArt.draw(self,at,data.get("autumn_feast",{}),elapsed,reduced_motion or photograph_mode)
				if festival_story_open:draw_festival_table(at)
				if focused_label=="community":
					var dishes:=PackedStringArray()
					if servings>0:dishes.append("火鍋 %d"%servings)
					if fruit>0:dishes.append("西瓜 %d"%fruit)
					if chowder>0:dishes.append("濃湯 %d"%chowder)
					if table_tea_cups>0:dishes.append("茶 %d"%table_tea_cups)
					world_label(at+Vector2(16,-4)," · ".join(dishes) if not dishes.is_empty() else "渡口餐桌","community")
			if chicks_open and p==World.LOST_CHICKS.SIGN:
				LostChicksArt.draw_sign(self,at)
				if focused_label==LostChicksArt.SIGN_POINT:world_label(at+Vector2(16,-8),"迷路小雞",LostChicksArt.SIGN_POINT)
			if chicks_pen and p==World.LOST_CHICKS.PEN:
				LostChicksArt.draw_pen(self,at)
			if stroll_sites.has(p):StrollArt.draw_marker(self,at,stroll_sites[p],data)
			if relay_cells.has(p):
				var relay_id:String=relay_cells[p]
				CookingRelayArt.draw(self,at,relay_id,data,elapsed,reduced_motion or photograph_mode,elapsed-cooking_relay_served_at)
				var relay_point:="cooking_relay_sign" if relay_id=="sign" else "cooking_relay:"+relay_id
				if focused_label==relay_point:world_label(at+Vector2(16,-8),CookingRelayArt.label(relay_id),relay_point)
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
			if p==World.WANGAN_COAST.STAR_REPAIR and not star_walk:
				FurnitureArt.draw_sprite(self,at,"sign")
				world_label(at+Vector2(16,-12),"星砂步道・待修",World.WANGAN_COAST.STAR_REPAIR_POINT)
			if p==World.WANGAN_COAST.STAR_SAND and star_walk:
				var remaining:=ceili(float(data.get("wangan_star_sand_ready",0.0))-float(data.time))
				if remaining<=0:draw_texture(preload("res://assets/bakery/crystal-sand.png"),at)
				world_label(at+Vector2(16,-5),"採集晶砂" if remaining<=0 else "晶砂約 %d 秒後露出"%remaining,World.WANGAN_COAST.STAR_SAND_POINT)
			if p==World.WANGAN_COAST.DOCK_ORDERS and star_walk:
				FurnitureArt.draw_sprite(self,at,"sign")
				if focused_label==World.WANGAN_COAST.DOCK_ORDERS_POINT:
					world_label(at+Vector2(16,-12),"望安碼頭訂單",World.WANGAN_COAST.DOCK_ORDERS_POINT)
				if p==World.WANGAN_COAST.SALT_PARCEL and data.get("wangan_star_walk",false):
					var parcel_coast:=World.WANGAN_COAST
					var parcel_player:Dictionary=data.get("players",{}).get(player_id,{})
					var parcel_day:=int(World.WEATHER.day_index(float(data.time)))+1
					var parcel_left:=int(parcel_player.get(parcel_coast.SALT_PARCEL_TOTAL_KEY,0))<parcel_coast.SALT_PARCEL_LIFETIME
					var parcel_ready:=parcel_left and int(parcel_player.get(parcel_coast.SALT_PARCEL_DAY_KEY,0))!=parcel_day
					var salt_icon:=preload("res://scripts/inventory_item_art.gd").icon("sea_salt")
					if salt_icon:draw_texture_rect(salt_icon,Rect2(at+Vector2(4,6),Vector2(24,24)),false,Color.WHITE if parcel_ready else Color(1,1,1,0.35))
					world_label(at+Vector2(16,-5),"領北門鹽田的海鹽" if parcel_ready else ("今天已領過海鹽" if parcel_left else "試用海鹽已領完"),parcel_coast.SALT_PARCEL_POINT)
			if p==World.COPPER_CELL:
				var ready:=float(data.get("copper",{}).get("ready",0))<=float(data.time)
				AutomationArt.draw_copper(self,at,ready)
				world_label(at+Vector2(16,-18),"運入礦料" if ready else "等待補貨","copper")
		for garden_id:String in spring_ids:
			var garden_cell:=SpringGardenArt.cell_of(garden_id)
			if garden_cell.y==y and garden_cell.x>=from.x and garden_cell.x<to.x:
				var garden_at:=screen(Vector2(garden_cell))
				var garden_done:=SpringGardenArt.collected(data,garden_id)
				SpringGardenArt.draw_sign(self,garden_at,garden_id,garden_done,elapsed,reduced_motion or photograph_mode)
				var garden_key:String=SpringGardenArt.POINT_KEYS[garden_id]
				if focused_label==garden_key:world_label(garden_at+Vector2(35,18),SpringGardenArt.title(garden_id),garden_key,true)
		if has_beach_treasure:
			for treasure:Dictionary in BeachTreasureArt.draw_row(self,screen(Vector2.ZERO),y,from.x,to.x,data,elapsed,reduced_motion or photograph_mode,display_positions.get(player_id,Vector2.INF)):
				if treasure.passive or focused_label==treasure.id:world_label(treasure.anchor,treasure.title,treasure.id,treasure.side)
		# 第 40 章地方記憶展：after the whole row, so the base rock at (40,26) stays behind the
		# stand's right post instead of covering its pedestals (screenshots, before/).
		if exhibit_cell!=MemoryExhibitUI.NO_CELL and y==exhibit_cell.y:
			var stand_at:=screen(Vector2(exhibit_cell))
			MemoryExhibitUI.draw_stand(self,stand_at,exhibit_cell)
			world_label(stand_at+MemoryExhibitUI.LABEL_ANCHOR,MemoryExhibitUI.stand_title(data,focused_label==MemoryExhibitUI.POINT),MemoryExhibitUI.POINT)
		if mining and floori(cart_position.y+0.5)==y and cart_position.x>=from.x and cart_position.x<to.x:
			var cart_at:=screen(cart_position).round()
			OreRouteArt.draw_cart(self,cart_at,cart_stage>0 and not cart_story,elapsed,reduced_motion)
			if focused_label==OreRouteArt.POINT:world_label(cart_at+Vector2(16,-18),OreRouteSelect.cart_name(data),OreRouteArt.POINT)
		if exhibit_cart and floori(exhibit_position.y+0.5)==y and exhibit_position.x>=from.x and exhibit_position.x<to.x:
			var exhibit_at:=screen(exhibit_position).round()
			OreRouteArt.draw_cart(self,exhibit_at,false,elapsed,reduced_motion)
			world_label(exhibit_at+Vector2(16,-18),World.BOBO_EMPTY_CART.label(data),"bobo_empty_cart_exhibit")
		for resident:String in village_residents:
			var resident_cell:Vector2i=village_residents[resident]
			if resident_cell.y==y:
				var npc:Dictionary=World.Village.NPCS[resident]
				var at:=screen(Vector2(resident_cell)+Vector2(0.5,0.7))
				if resident!="bobo" or not BoboArt.draw(self,at-Vector2(24,44),"person"):
					person_sprite(at,Color(npc.color),resident,Vector2i.DOWN,0.0,false,false,false,0.0,true)
				var label_offset:=Vector2(-25,-26) if Vector2(bell_cell-resident_cell).length()<=1.0 else Vector2(0,-47)
				if resident!="bobo" or focused_label=="bobo":world_label(at+label_offset,npc.name,resident)
		# D16 solo hotpot photo: the cook sits in beside the shared table for the picture only.
		if photograph_mode and photo_guest=="milu" and table_cell!=Vector2i(-1,-1) and table_cell.y==y:
			var guest_at:=screen(Vector2(table_cell)+Vector2(-0.35,0.75)).round()
			person_sprite(guest_at,Color(World.Village.NPCS.milu.color),"milu",Vector2i.DOWN,0.0,false,false,true)
		if not resident_at_station.is_empty() and resident_at_station.cell.y==y:
			var at:=screen(Vector2(resident_at_station.cell)+Vector2(0.5,0.72)).round()
			StationLifeArt.draw_person(self,at,region_id(),elapsed,reduced_motion)
			var resident_focus:="station_resident:"+region_id()
			if focused_label==resident_focus:world_label(at+Vector2(0,-47),resident_at_station.name,resident_focus)
		# T066：可直接拜訪的居民，位置由各自的故事與區域狀態決定。
		for walk_id:String in visiting_residents:
			var walk_cell:Vector2i=visiting_residents[walk_id]
			if walk_cell.y!=y:continue
			var walk_foot:=screen(Vector2(walk_cell)+Vector2(0.5,0.7))
			if diandian_sitting and walk_id=="diandian" and character_art:
				character_art.draw_seated(self,walk_foot,false,walk_id)
			else:
				person_sprite(walk_foot,Color("e8d9c4"),walk_id,Vector2i.DOWN,0.0,false,false,false,0.0,true)
			world_label(walk_foot+Vector2(0,-47),World.RESIDENT_BOND.name_of(walk_id),walk_id)
		if region_id()==tea_house.REGION:
			if in_tea_house:_draw_tea_house_row(tea_house,y,data.players.get(player_id,{}))
			_draw_tea_house_door_label(tea_house,tea_anchors,y,in_tea_house)
		if region_id()==pottery.REGION:
			if in_pottery:_draw_pottery_row(pottery,y,tea_record)
			_draw_pottery_door_label(pottery,pottery_anchors,y,in_pottery)
		if in_springs:
			if in_inn and y in range(springs.INN_ROOM.position.y,springs.INN_ROOM.end.y):
				for x in range(springs.INN_ROOM.position.x,springs.INN_ROOM.end.x):
					var cell:=Vector2i(x,y)
					var at:=screen(Vector2(cell))
					if cell==springs.INN_EXIT:
						world_label(at+Vector2(16,12),"回到溪畔",springs.INN_PORTAL)
					elif y==springs.INN_ROOM.position.y or y==springs.INN_ROOM.end.y-1 or x in [springs.INN_ROOM.position.x,springs.INN_ROOM.end.x-1]:
						object_sprite(at,"wall")
						if y==springs.INN_ROOM.position.y and x in [62,66,70,72]:object_sprite(at,"window")
					elif springs.INN_FURNITURE.has(cell):
						var kind:String=springs.INN_FURNITURE[cell]
						_draw_inn_furniture(at,kind,cell==springs.INN_RUG_ANCHOR+Vector2i.RIGHT)
						var point:="%s:%s"%[springs.INN_USE,World.key(cell)]
						if focused_label==point:world_label(at+Vector2(16,-14),"休息" if kind==Industry.INN_BED else "坐下",point)
					if INN_DECOR.has(cell):_draw_inn_decor(at,INN_DECOR[cell])
					if INN_ROOM_PROPS.has(cell):_draw_room_prop(at,INN_ROOM_PROPS[cell])
					if cell==Vector2i(61,17):BarkFrameArt.draw(self,at+Vector2(0,6),World.BARK_FRAME.SKETCH)
			if y==springs.INN_FOOTPRINT.end.y-1:
				var origin:=screen(Vector2(springs.INN_FOOTPRINT.position))
				springs.draw_inn(self,origin,elapsed,reduced_motion,springs.entrance_progress(data),elapsed-inn_swept_at)
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
			if not in_inn and springs.crack_survey_open(data):
				var cracks:=int(data.get("own_inn_cracks",0))
				for index in springs.CRACK_SITES.size():
					var spot:Vector2i=springs.CRACK_SITES[index]
					if spot.y!=y:continue
					var mark:Vector2=screen(Vector2(spot)+Vector2(0.5,0.5)).round()+springs.CRACK_MARK_OFFSETS[index]
					var marked:bool=springs.crack_marked(cracks,index)
					var color:=Color("b8dbac") if marked else Color("f9dc97")
					var strokes:=[Vector2(-6,-2),Vector2(-3,2),Vector2(1,1),Vector2(5,-4)] if marked else [Vector2(-6,2),Vector2(-2,-2),Vector2(1,1),Vector2(5,-3)]
					for segment in range(strokes.size()-1):
						draw_line(mark+strokes[segment]+Vector2(0,1),mark+strokes[segment+1]+Vector2(0,1),Color("534d3b"),4.0)
						draw_line(mark+strokes[segment],mark+strokes[segment+1],color,2.0)
					var point:="%s:%d"%[springs.CRACK_ACTION,index]
					if focused_label==point:world_label(mark+Vector2(0,-16),springs.CRACK_NAMES[index],point)
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
			for choice:String in springs.REST_SEATS:
				var join_point:=springs.REST_JOIN+":"+choice
				if focused_label!=join_point or springs.REST_SEATS[choice].y!=y:continue
				var host_name:=""
				for other_id in data.players:
					var other:Dictionary=data.players[other_id]
					if other_id!=player_id and str(other.get(springs.REST_SEAT_KEY,""))==choice:host_name=str(other.get("name",""))
				var join_at:=screen(Vector2(springs.REST_SEATS[choice])+Vector2(1.42,0.66)).round()
				world_label(join_at+Vector2(0,-40),"和%s一起坐"%host_name if not host_name.is_empty() else "一起坐",join_point)
			if solo_companion and rest_cell.y==y:
				var companion:=screen(Vector2(rest_cell)+Vector2(1.42,0.66))
				if character_art:character_art.draw_seated(self,companion,false,"nuannuan")
				else:person_sprite(companion,Color("e8d9c4"),"nuannuan")
			if rest_cell.y==y and focused_label==springs.REST_PHOTO_POINT:
				var photo_at:=screen(springs.rest_spot(own_rest_key)).round()
				world_label(photo_at+Vector2(0,-39),"拍旅舍合照",springs.REST_PHOTO_POINT)
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
				if not World.LIVESTOCK.adopted(data.get("livestock",{}),id):
					LivestockArt.draw_station(self,foot,id,LivestockArt.state_for(record),elapsed,reduced_motion or photograph_mode)
					if focused_label=="livestock:"+id:world_label(foot+Vector2(0,-26),"領養"+animal.name,"livestock:"+id)
					continue
				if id=="sheep":draw_rabbit_basket(foot+Vector2(-30,2))
				var corner:=int(data.get("sheep_comfort_fixtures",0)) if id=="sheep" else 0
				if (corner&1)!=0:draw_sheep_comfort(foot+Vector2(16,-34),0)
				if (corner&2)!=0:draw_sheep_comfort(foot+Vector2(17,-18),1)
				var reaction_age:=elapsed-float(livestock_pet_feedback.get(id,-INF))
				var brushing:bool=id=="sheep" and record.get("last_care","")=="brush"
				var quiet:=reduced_motion or photograph_mode
				var now_time:=float(data.get("time",0.0))
				var step_watch:bool=id=="sheep" and MianmianSheepStep.active(data,now_time)
				var animal_foot:=foot+sheep_shelter.offset(elapsed,quiet) if id=="sheep" else foot
				if step_watch:animal_foot=foot+MianmianSheepStep.offset(data,quiet,now_time)
				if id=="cow":animal_foot+=cow_follow.offset(quiet).round()
				var offset:=Vector2.ZERO if brushing else LivestockArt.reaction_offset(id,reaction_age,int(record.get("bond",0)),quiet)
				if id=="duck":draw_duck(foot,record,reaction_age)
				else:
					var sheep:bool=id=="sheep"
					var walking_frame:=sheep_shelter.walking_frame(elapsed,quiet) if sheep else -1
					if step_watch:walking_frame=int(floorf(elapsed/0.16))%2 if MianmianSheepStep.walking(data,quiet,now_time) else -1
					if id=="cow":walking_frame=cow_follow.walking_frame(quiet)
					if sheep:LivestockArt.draw_station(self,foot,id,LivestockArt.state_for(record),elapsed,quiet)
					var facing_right:bool=sheep and sheep_shelter.walking(elapsed,quiet) and sheep_shelter.facing_right()
					if step_watch:facing_right=MianmianSheepStep.walking(data,quiet,now_time) and now_time-float(data.own_mianmian_step_time)<MianmianSheepStep.WALK_IN
					if id=="cow":facing_right=cow_follow.moving and cow_follow.face_right
					LivestockArt.draw(self,animal_foot,id,LivestockArt.state_for(record),quiet,elapsed,Vector2i(offset),brushing and reaction_age>=0.0 and reaction_age<LivestockArt.PET_SECONDS,walking_frame,true,facing_right,view_zoom())
					if id=="cow":LivestockArt.draw_station(self,foot,id,LivestockArt.state_for(record),elapsed,quiet)
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
			# The resting cat's feet meet the right window sill in the house sprite.
			if data.get("picnic",false):draw_cat_home(house_at+Vector2(65,22))
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
		if cart_gallery and y==clampi(20,from.y,to.y-1):PartyCartArt.draw_cart(self,data)
		if chicks_pen:_draw_lost_chicks(y)
		if stroll_companion.is_finite() and floori(stroll_companion.y)==y:
			var guide:=screen(stroll_companion).round()
			var face:Vector2i=facings.get(player_id,Vector2i.DOWN)
			person_sprite(guide,Color("617a83"),"stroll_guide",face,float(gait.get(player_id,0.0)),not photograph_mode and walking.get(player_id,false))
			StrollArt.draw_carried(self,guide)
			world_label(guide+Vector2(0,-40),"阿燈 · 同行","")
		# T066 N01-3: the 阿榆 co-sitting scene (bench, 阿榆 and seated players) draws as one group in its row.
		if not aru_scene.is_empty() and aru_scene.anchor.y==y:AruRest.draw_scene(self,data,aru_scene)
		for id in data.players:
			if aru_sitters.has(id):continue
			var person:Dictionary=data.players[id]
			var visual_position:Vector2=garden_seating.get(id,display_positions.get(id,Vector2(person.x,person.y)))
			var tea_seated:bool=in_tea_house and person.has(tea_house.SEAT_KEY)
			if tea_seated:
				var tea_chair:=tea_house_seat_cell(person)
				if tea_house.SEAT_FEET.has(tea_chair):visual_position=Vector2(tea_chair)+Vector2(0.5,0.72)
			if floori(visual_position.y)==y:
				var at:=screen(visual_position).round()
				var local:bool=id==player_id
				if in_star_garden and person.get(World.RESIDENT_GOALS.DIANDIAN_SEAT_KEY,false) and character_art:
					draw_low_seated_player(at,person)
					continue
				if tea_seated:
					if character_art:draw_seated_player(at,person)
					else:person_sprite(at,Color("d88f73"),"farmer")
					continue
				var rest_seat:=str(person.get(springs.REST_SEAT_KEY,""))
				var inn_chair:=rest_seat.begins_with(springs.INN_USE+":")
				if in_springs and (not springs.rest_choice(rest_seat).is_empty() or rest_seat==springs.BATH_ACTION or inn_chair):
					if rest_seat==springs.BATH_ACTION:at.y-=22.0
					if inn_chair:at=screen(Vector2(World.cell(rest_seat.get_slice(":",1)))+Vector2(0.5,0.72)).round()
					if character_art:
						if rest_seat==springs.BATH_ACTION:character_art.draw_seated(self,at,bool(person.get("blue_outfit",false)))
						else:draw_seated_player(at,person)
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
				if seat_obj.get("type") in [Industry.HOLLOW_BED,Industry.BAMBOO_LOUNGER]:continue
				if garden_seating.has(id):
					if seat_obj.get("type")==Industry.WOOD_CHAIR:
						var emote:=active_emote(id)
						var since:=Time.get_ticks_msec()-int(emote.get("started",-1000))
						var nod:=0.0 if reduced_motion or photograph_mode or since>=520 else roundf(2.0*sin(PI*float(since)/520.0))
						if character_art:draw_seated_player(at,person,Vector2i.DOWN,nod)
						else:person_sprite(at,Color("d88f73"),"farmer" if local else "guest")
						if not emote.is_empty():
							world_label(at+Vector2(0,-39),str(emote.caption),"",false,true)
							draw_tea_pour_fx(at+Vector2(14,-8),emote)
						continue
					if seat_obj.get("type") in [Industry.MUSHROOM_STOOL,Industry.INDIGO_CUSHION] and character_art:
						draw_low_seated_player(at,person)
						continue
					var direction:=Vector2i.DOWN
					if seat_obj.get("type")==Industry.MUSHROOM_TABLE:
						direction=Vector2i.RIGHT if int(seat.side)%2==0 else Vector2i.LEFT
					elif seat_obj.get("type")==Industry.BAMBOO_TEA_TABLE:
						direction=Industry.TEA_TABLE_FACING[int(seat.side)]
					if character_art:draw_seated_player(at,person,direction)
					else:person_sprite(at,Color("d88f73"),"farmer" if local else "guest")
					continue
				if seat_obj.get("type")==Industry.FOOT_BATH and int(seat.get("side",-1)) in range(Industry.FOOT_BATH_SEATS.size()):
					var offset:Vector2=Industry.FOOT_BATH_SEATS[int(seat.side)]
					if Industry.is_vertical(seat_obj):offset=Vector2(2.0-offset.y,offset.x)
					var place:=screen(Vector2(World.cell(seat.cell))+offset).round()
					if character_art:draw_seated_player(place,person)
					else:person_sprite(place,Color("d88f73"),"farmer" if local else "guest")
					continue
				if World.RESIDENT_GOALS.aru_public_bench(seat_obj) and int(seat.get("side",-1)) in range(World.RESIDENT_GOALS.ARU_PARK_SEAT_X.size()):
					var spot:=Vector2(World.cell(seat.cell))+Vector2(World.RESIDENT_GOALS.ARU_PARK_SEAT_X[int(seat.side)],0.80)
					var sitting_at:=screen(spot).round()
					if character_art:draw_seated_player(sitting_at,person)
					else:person_sprite(sitting_at,Color("d88f73"),"farmer" if local else "guest")
					continue
				if not seat.is_empty() and data.objects.get(seat.get("cell",""),{}).get("type") in World.RESIDENT_GOALS.DOUBLE_BENCHES:
					var bench:=World.cell(seat.cell)
					var offset:=Vector2(World.master_bench_offset(data.objects[seat.cell]))*float(seat.side)
					var sitting_at:=screen(Vector2(bench)+Vector2(0.55,0.81)+offset).round()
					if character_art:draw_seated_player(sitting_at,person)
					else:person_sprite(sitting_at,Color("d88f73"),"farmer" if local else "guest")
					continue
				var shirt:=Color("d88f73") if local else Color.from_hsv([0.55,0.76,0.44][absi(hash(id))%3],0.32,0.77)
				var operation:=farm_feedback.active(id,elapsed)
				var machine_kind:String=operation.get("kind","")
				if machine_kind.is_empty() and local:
					for kind in MACHINES:
						if selected==MACHINES[kind][0] and (int(person.get("inventory",{}).get(kind,0))>0 or (kind==World.PUBLIC_TILLER.ITEM and World.PUBLIC_TILLER.borrowed(person))):
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
				var pose_stage:=World.ORE_ROUTE.LAST if exhibit_cart and ore_cart_push_story else cart_stage
				var cart_pose:=ore_cart_push_pose(pose_stage,visual_position) if mining and local and fishing.is_empty() and tool_plan.is_empty() and not walking.get(id,false) else {}
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
				draw_player_headwear((at+tool_plan.get("lunge",Vector2.ZERO)).round()+CharacterSprites.head_shift(facing,lean),person,facing)
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
				if person.get("stroll_lantern",false):StrollArt.draw_carried(self,at)
				if chicken_feed.actor==id:
					var bucket_x:=-12 if facing==Vector2i.LEFT else 12
					LostChicksArt.draw_bucket(self,at+Vector2(bucket_x,-9))
				elif local and _activity_bucket(person):
					LostChicksArt.draw_bucket(self,at+Vector2(13,4))
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
				var emote:=active_emote(id)
				if not emote.is_empty():
					world_label(at+Vector2(0,-62),str(emote.caption),"")
					draw_tea_pour_fx(at+Vector2(14,-24),emote)
		# Vertical (E/W) edges span this row and sort by their south end, so they follow the row's walkers.
		draw_edge_row(y,from.x,to.x,EdgeGrid.SIDE_W)
	if home:
		# A resident chicken gives the first clearing a living, gentle focal point.
		var chicken_pos:=World.CHICKEN_FEED_FOLLOW.HOME
		var animal:Dictionary=data.get("animal",{})
		var quiet_chicken:=reduced_motion or photograph_mode
		var chicken_at:=Vector2.ZERO
		if chicken_feed.active():chicken_at=screen(chicken_feed.foot(quiet_chicken))
		else:
			if not quiet_chicken:chicken_pos.x+=sin(elapsed*0.5)*0.6
			chicken_at=screen(chicken_pos)
			if not data.get("chicken_feed_follow",false):
				chicken_at+=MianmianApproach.shift(data,player_id,chicken_pos,quiet_chicken,float(data.get("time",0.0)))
		var held:bool=not World.CHICKEN_CUDDLE.holder(data).is_empty()
		if not held:
			chicken(chicken_at)
			chicken_draw_stats.ground+=1
			world_label(chicken_at+Vector2(0,-25),"糯米雞","animal")
		var basket_at:=screen(Vector2(46.5,34.7))
		if animal.has("basket_eggs"):
			var basket:=preload("res://scripts/salt_revisit_art.gd").empty_basket_texture()
			draw_texture(basket,basket_at-Vector2(16,28))
		var loose_egg:=float(animal.get("egg_ready",-1))>=0 and float(data.time)>=float(animal.egg_ready)
		if int(animal.get("basket_eggs",0))>0 or loose_egg:
			var egg_at:=basket_at-Vector2(3,19) if animal.has("basket_eggs") else chicken_at+Vector2(12,0)
			if not character_art or not character_art.draw_egg(self,egg_at+Vector2(3,8)):
				draw_rect(Rect2(egg_at,Vector2(6,8)),Color("fff4d4"))
				draw_rect(Rect2(egg_at+Vector2(1,-2),Vector2(4,11)),Color("fff4d4"))
		if not held and float(data.time)-float(animal.get("last_pet",-30))<3:
			var heart:=chicken_at+Vector2(8,-30)
			draw_rect(Rect2(heart,Vector2(4,4)),Color("d98e87"))
			draw_rect(Rect2(heart+Vector2(5,0),Vector2(4,4)),Color("d98e87"))
			draw_rect(Rect2(heart+Vector2(2,3),Vector2(5,4)),Color("d98e87"))
	var arch_view:=Rect2i(from,to-from).grow(3)
	for arch_key:String in data.get("objects",{}):
		var arch:Dictionary=data.objects[arch_key]
		if arch.get("type") not in Industry.ARCHES or Industry.square_part(arch)!=0:continue
		var tile:=World.cell(arch_key)
		if arch_view.has_point(tile):
			draw_arch(screen(Vector2(tile)),str(arch.type),arch.get("vine_color","pink"),Industry.is_vertical(arch),Color.WHITE,"crown")
	# Local player only; the body is drawn at display_positions, so occlusion uses that.
	var local_drawn:Vector2=display_positions.get(player_id,Vector2.INF)
	for tile:Vector2i in canopies:
		var vertical:=Industry.is_vertical(data.objects[World.key(tile)])
		var alpha:=CoastAwningArt.opacity(tile,vertical,local_drawn,photograph_mode or reduced_motion)
		CoastAwningArt.draw_canopy(self,screen(Vector2(tile)),vertical,Color.WHITE,alpha)
	# T12: the pavilion canopy is drawn after all walkers and fades whenever the local avatar is under
	# or would be hidden behind it (a flat step in photograph / reduced-motion mode).
	for shelter:Vector2i in pavilions:
		var roof_alpha:=PavilionArt.opacity(shelter,local_drawn,photograph_mode or reduced_motion)
		PavilionArt.draw_canopy(self,screen(Vector2(shelter)),Color.WHITE,roof_alpha)
		var focused_part:String=focused_label
		if data.objects.has(focused_part) and str(data.objects[focused_part].get("type",""))==Industry.IMPERFECT_TEA_PAVILION and World.station_anchor(data.objects,World.cell(focused_part))==shelter:
			world_label(screen(Vector2(shelter))+Vector2(48,-6),World.PAVILION.NAME,focused_part)
	var faded_roofs:Dictionary=roof_faded
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
	if not in_inn and not in_tea_house and not in_pottery:draw_weather(size)
	draw_gather_pickups()
	if show_target and not photograph_mode and region_id()==World.REGIONS.HOME and data.has("can_build_public_plot") and selected=="build":
		var plot:=World.PUBLIC_BUILD_PLOT
		var origin:=screen(Vector2(plot.position))
		var tint:=Color("e7d9a4") if data.can_build_public_plot else Color("e89a7d")
		draw_rect(Rect2(origin+Vector2.ONE,Vector2(plot.size*32)-Vector2(2,2)),tint,false,1.0)
		world_label(origin+Vector2(plot.size.x*16,-4),"渡口北側公共地塊" if data.can_build_public_plot else "公共地塊 · 需施工授權","public_build_plot")
	if show_target and not photograph_mode and region_id()==World.REGIONS.HOME and selected=="build":
		var floor_piece:Dictionary=data.ground.get(World.key(target),{})
		var builder:Dictionary=data.players.get(player_id,{})
		if World.ROOM_ENCLOSURE.is_floor_kind(floor_piece.get("type")) and floor_piece.get("owner")==player_id and not builder.is_empty():
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
	if focused_label.begins_with("edge_door:"):
		var edge_key:=focused_label.trim_prefix("edge_door:")
		var door:=EdgeGrid.decode(edge_key)
		if not door.is_empty():
			var midpoint:Vector2=Vector2(door.cell)+(Vector2(0.5,0) if door.side==EdgeGrid.SIDE_N else Vector2(0,0.5))
			var opened:bool=data.get("edges",{}).get(edge_key,{}).get("open",false)
			world_label(screen(midpoint)+Vector2(0,-38),"關木門" if opened else "開木門",focused_label)
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
	var edge_context:=edge_preview_context()
	if not edge_context.is_empty():draw_edge_preview(edge_context)
	if show_target and not photograph_mode and edge_context.is_empty():
		var at:=screen(Vector2(target))
		var blocked:Dictionary={}
		var hand_farm_blocked:=false
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
		if selected in ["hoe","water","seed","harvest"] and hand_farm_wide and region_id()==World.REGIONS.HOME:
			var owner:Dictionary=data.get("players",{}).get(player_id,{})
			var tool:=World.gathering_tool_upgrade(selected,owner.get("inventory",{}))
			if not tool.is_empty():
				var preview:=hand_farm_preview(target,tool)
				hand_farm_blocked=preview.cells.is_empty()
				for offset:Vector2i in World.TILLER.HAND_PATTERNS[tool]:
					var tile:=target+offset
					var tile_key:=World.key(tile)
					var tint:=Color("db9980")
					if tile_key in preview.cells:tint=Color("9fdded") if selected=="water" else Color("b3d894")
					elif preview.skipped.get(tile_key)=="已經澆水":tint=Color("9fadb9")
					elif preview.skipped.get(tile_key) in ["種子不足","還沒成熟"]:tint=Color("e2c26b")
					var tile_at:=screen(Vector2(tile))
					draw_rect(Rect2(tile_at+Vector2.ONE,Vector2(30,30)),Color(tint,0.24))
					draw_rect(Rect2(tile_at+Vector2(2,2),Vector2(28,28)),tint,false,1.0)
		draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),Color(1,0.98,0.78,0.16))
		var outline:=Color("db9980") if hand_farm_blocked else Color("fff4c2")
		if selected=="plant_tree":
			outline=Color("b3d894") if tree_planting_preview(target).is_empty() else Color("db9980")
		draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),outline,false,2.0)
		if selected=="build":
			draw_rect(Rect2(at+Vector2(4,4),Vector2(24,24)),Color(0.9,0.9,0.75,0.22))
			if building=="mine_drill":draw_drill_placement()
			if building=="forester":
				for offset in Forestry.OFFSETS:
					ForestryArt.draw_plot_marker(self,screen(Vector2(target+offset)),Color(1,1,1,0.8))
			if building == Industry.MILL and mill_build_facing >= 0:
				var entrance := screen(Vector2(target + Industry.mill_entrance_offset(mill_build_facing)))
				var front := screen(Vector2(target + Industry.mill_front_offset(mill_build_facing)))
				var lane := Color("f7dc9b") if blocked.is_empty() else Color("d97765")
				draw_rect(Rect2(entrance+Vector2(3,3),Vector2(26,26)),lane,false,2.0)
				draw_line(front+Vector2(16,16),entrance+Vector2(16,16),lane,2.0)
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
func _tea_house_window_xs(room:Rect2i) -> Array:
	return [room.position.x+2,room.position.x+5,room.position.x+9,room.position.x+12]

## Render-only dressing. Vases are anchored to the table cell they appear over.
const TEA_HOUSE_DECOR:={
	Vector2i(60,17):"pot",Vector2i(63,17):"mural",Vector2i(66,17):"chime",
	Vector2i(57,23):"cushion",Vector2i(69,23):"lamp",
	Vector2i(60,22):"table_vase_bluebell",Vector2i(67,22):"table_vase_orange",
}
const INN_DECOR:={
	Vector2i(64,17):"chime",Vector2i(68,17):"towel",Vector2i(71,17):"sign",Vector2i(73,17):"pot",
	Vector2i(74,21):"niche",
	Vector2i(72,22):"table_vase_orange",Vector2i(66,24):"table_vase_herb",
	# Cozy extras (render-only, none of these cells are added to INN_FURNITURE / collision).
	Vector2i(63,17):"inn_frame_hills",Vector2i(69,17):"inn_frame_moon",
	Vector2i(60,21):"niche",
	Vector2i(61,24):"inn_towel_basket",Vector2i(70,23):"inn_towel_basket",
	Vector2i(62,23):"inn_slippers",Vector2i(67,23):"inn_slippers",
	Vector2i(67,17):"inn_wall_shelf",
}

const ROOM_GUEST_BOOK_ART=preload("res://assets/ui-life/book.png")
const ROOM_TEA_PUDDING_ART=preload("res://assets/ui-inventory/tea-pudding.png")
const ROOM_TEA_SERVICE_ART=preload("res://assets/ui-inventory/small-ceramic-tea-set.png")
const ROOM_COTTON_ART=preload("res://assets/ui-inventory/cotton-cloth.png")
const ROOM_POT_ART=preload("res://assets/ui-inventory/flower-pot.png")

# Props hang on a wall or sit on an existing furnishing's footprint.
const INN_ROOM_PROPS:={
	Vector2i(65,17):[POSTCARD_RACK_ART,Rect2(3,0,26,30)],
	Vector2i(64,19):[ROOM_GUEST_BOOK_ART,Rect2(16,-7,17,17)],
	Vector2i(61,19):[ROOM_COTTON_ART,Rect2(27,-7,16,16)],
	Vector2i(66,24):[ROOM_TEA_SERVICE_ART,Rect2(1,-8,20,20)],
	Vector2i(72,22):[ROOM_TEA_PUDDING_ART,Rect2(17,-4,13,13)],
	Vector2i(74,24):[PAPER_TEA_LAMP_ART,Rect2(6,-7,20,23)],
}

func _draw_room_prop(at:Vector2,prop:Array) -> void:
	var rect:Rect2=prop[1]
	draw_texture_rect(prop[0],Rect2(at+rect.position,rect.size),false)

func _draw_inn_mats() -> void:
	for x in [62,67]:
		var at:=screen(Vector2(x,23))
		draw_texture_rect(BRAIDED_RUG_ART,Rect2(at+Vector2(1,12),Vector2(30,23)),false,Color("b6c5ac"))

func _draw_inn_furniture(at:Vector2,kind:String,lounge_table:bool) -> void:
	var appearance:Dictionary={}
	match kind:
		Industry.INN_BED:appearance={"type":kind,"inn_bed_vertical":true}
		Industry.LUGGAGE_RACK:appearance={"items":{"cotton_cloth":1,"wool_cloth":1}}
		World.INN_TEA_TABLE:
			if not lounge_table:appearance={"items":{World.GINGER_TEA:1}}
	object_sprite(at,kind,appearance)
	if kind==Industry.COAST_REGISTER:
		var vase:=MarketItemArt.icon("table_vase_bluebell")
		draw_texture_rect(vase,Rect2(at+Vector2(41,-15),Vector2(20,20)),false)
	elif kind==World.INN_TEA_TABLE and lounge_table:
		draw_tea_set(at+Vector2(3,-4))

## Inn-only cozy props; unknown kinds fall through to the shared room decor.
func _draw_inn_decor(at:Vector2,kind:String) -> void:
	match kind:
		"inn_frame_hills","inn_frame_moon":
			var f:=at+Vector2(0,5)
			draw_texture(preload("res://assets/ui-life/bark-picture-frame.png"),f)
			if kind=="inn_frame_hills":
				draw_rect(Rect2(f+Vector2(6,5),Vector2(20,12)),Color("f1dfae"))
				draw_colored_polygon(PackedVector2Array([f+Vector2(6,17),f+Vector2(13,8),f+Vector2(19,17)]),Color("6f8f62"))
				draw_colored_polygon(PackedVector2Array([f+Vector2(14,17),f+Vector2(21,10),f+Vector2(26,17)]),Color("8aa874"))
				draw_rect(Rect2(f+Vector2(21,6),Vector2(3,3)),Color("e7a45a"))
			else:
				draw_rect(Rect2(f+Vector2(6,5),Vector2(20,12)),Color("37466b"))
				draw_rect(Rect2(f+Vector2(17,7),Vector2(4,4)),Color("f6e7a8"))
				draw_rect(Rect2(f+Vector2(9,8),Vector2(1,1)),Color("f6e7a8"))
				draw_rect(Rect2(f+Vector2(12,12),Vector2(1,1)),Color("f6e7a8"))
				draw_rect(Rect2(f+Vector2(6,15),Vector2(20,2)),Color("2a3a4c"))
		"inn_wall_shelf":
			# Warm plank shelf under the north wall with a folded towel, a tea jar and a candle.
			var s:=at+Vector2(2,4)
			draw_rect(Rect2(s+Vector2(0,14),Vector2(28,4)),Color("8a5a3a"))
			draw_rect(Rect2(s+Vector2(0,14),Vector2(28,1)),Color("b98557"))
			draw_rect(Rect2(s+Vector2(2,18),Vector2(2,3)),Color("5e3b27"))
			draw_rect(Rect2(s+Vector2(24,18),Vector2(2,3)),Color("5e3b27"))
			draw_rect(Rect2(s+Vector2(2,8),Vector2(9,6)),Color("f1e6cf"))
			draw_rect(Rect2(s+Vector2(2,11),Vector2(9,1)),Color("d8c6a4"))
			draw_rect(Rect2(s+Vector2(14,8),Vector2(5,6)),Color("7a9a8c"))
			draw_rect(Rect2(s+Vector2(14,7),Vector2(5,1)),Color("c9a46a"))
			draw_rect(Rect2(s+Vector2(22,9),Vector2(3,5)),Color("f2dfa6"))
			draw_rect(Rect2(s+Vector2(23,6),Vector2(1,3)),Color("f0a850"))
		"inn_towel_basket":
			var b:=at+Vector2(7,12)
			draw_rect(Rect2(b+Vector2(1,12),Vector2(16,2)),Color(0,0,0,0.16))
			draw_rect(Rect2(b+Vector2(1,3),Vector2(15,4)),Color("f4ead3"))
			draw_rect(Rect2(b+Vector2(1,5),Vector2(15,1)),Color("d7c7a2"))
			draw_rect(Rect2(b+Vector2(3,0),Vector2(11,3)),Color("b9d3cf"))
			draw_rect(Rect2(b+Vector2(3,2),Vector2(11,1)),Color("95b6b2"))
			draw_rect(Rect2(b+Vector2(0,7),Vector2(17,6)),Color("c79a5c"))
			for k in range(3):
				draw_rect(Rect2(b+Vector2(0,8+k*2),Vector2(17,1)),Color("8f6636"))
			for k in range(4):
				draw_rect(Rect2(b+Vector2(2+k*4,7),Vector2(1,6)),Color("a67a42"))
		"inn_slippers":
			for dx in [6,16]:
				var p:=at+Vector2(dx,20)
				draw_rect(Rect2(p+Vector2(0,5),Vector2(8,2)),Color(0,0,0,0.14))
				draw_rect(Rect2(p,Vector2(7,6)),Color("a65f4a"))
				draw_rect(Rect2(p+Vector2(1,0),Vector2(5,2)),Color("e8d2a8"))
				draw_rect(Rect2(p+Vector2(0,5),Vector2(7,1)),Color("7a4334"))
		_:_draw_room_decor(at,kind)

func _draw_room_decor(at:Vector2,kind:String,vase_offset:=Vector2(13,-12)) -> void:
	match kind:
		"pot":draw_hanging_pot(at+Vector2(5,12),0.0 if reduced_motion or photograph_mode else roundf(sin(elapsed*1.2+at.x*0.05)))
		"mural":draw_texture(preload("res://assets/ui-inventory/public-mural.png"),at+Vector2(0,2))
		"chime":draw_texture(preload("res://assets/ui-life/ceramic-eave-chime.png"),at+Vector2(0,4))
		"niche":draw_texture(preload("res://assets/ui-life/warm-lamp-niche.png"),at+Vector2(0,-15))
		"towel":draw_texture(preload("res://assets/ui-life/towel-rack.png"),at+Vector2(0,2))
		"sign":draw_texture(HOME_SIGN_ART,at+Vector2(0,8))
		"cushion":draw_texture(INDIGO_CUSHION_ART,at+INDIGO_CUSHION_AT)
		"lamp":draw_texture(PAPER_TEA_LAMP_ART,at+PAPER_TEA_LAMP_AT)
		_:
			if kind.begins_with("table_vase_"):
				var icon:=MarketItemArt.icon(kind)
				if icon!=null:draw_texture_rect(icon,Rect2(at+vase_offset,Vector2(14,14)),false)

## Ground-level warmth for the Maokong tea house: window light, a runner from the door and round rugs.
func _draw_tea_house_floor(house) -> void:
	var room:Rect2i=house.ROOM
	var exit_cell:Vector2i=house.EXIT
	for wx:int in _tea_house_window_xs(room):
		draw_rect(Rect2(screen(Vector2(wx,room.position.y+1)),Vector2(32,64)),Color(1.0,0.86,0.55,0.12))
	var lane:int=exit_cell.y-room.position.y-2
	if lane>0:
		var runner:=Rect2(screen(Vector2(float(exit_cell.x)+0.18,float(room.position.y+2))),Vector2(22,32.0*float(lane)))
		draw_rect(runner,Color("8a4b3c"))
		draw_rect(runner.grow(-3),Color("d9b36c"),false,1.0)
		for mark in range(lane):
			var mid:=runner.position+Vector2(11,16+32*mark)
			draw_colored_polygon(PackedVector2Array([mid-Vector2(0,5),mid+Vector2(5,0),mid+Vector2(0,5),mid-Vector2(5,0)]),Color("e6c27a"))
	for spot:Vector2i in [Vector2i(room.position.x+3,room.position.y+5),Vector2i(room.end.x-5,room.position.y+5)]:
		draw_texture(BRAIDED_RUG_ART,screen(Vector2(spot)))
	# Side-zone woven mats on open floor beside the lounge tables (ground only, never solid).
	for spot:Vector2i in [Vector2i(room.position.x+1,room.position.y+5),Vector2i(room.end.x-2,room.position.y+5)]:
		if not house.blocked(spot):draw_texture_rect(LeafMatArt.TEXTURE,Rect2(screen(Vector2(spot))+Vector2(-4,-3),Vector2(40,40)),false,Color("b7c58b"))
	draw_rect(Rect2(screen(Vector2(exit_cell))+Vector2(3,6),Vector2(26,26)),Color("a8774b"))
	draw_rect(Rect2(screen(Vector2(exit_cell))+Vector2(6,9),Vector2(20,20)),Color("c99a62"),false,1.0)

## Walls, windows and furniture of one tea-house row; seated visitors are drawn by the shared person loop.
func _draw_tea_house_row(house,y:int,own:Dictionary) -> void:
	var room:Rect2i=house.ROOM
	if y<room.position.y or y>=room.end.y:return
	var own_chair:=tea_house_seat_cell(own)
	var windows:Array=_tea_house_window_xs(room)
	for x in range(room.position.x,room.end.x):
		var cell:=Vector2i(x,y)
		var at:=screen(Vector2(cell))
		if cell==house.EXIT:continue
		if y==room.position.y or y==room.end.y-1 or x==room.position.x or x==room.end.x-1:
			object_sprite(at,"wall")
			if y==room.position.y and x in windows:object_sprite(at,"window")
		elif house.FURNITURE.has(cell):
			var kind:String=house.FURNITURE[cell]
			match kind:
				"tea_shelf":draw_tea_cabinet(at,{"type":Industry.TEA_DISPLAY_CABINET,"items":{"tea_leaf":1,"tea_light":1,"tea_deep":1}})
				"tea_counter":
					object_sprite(at,Industry.COAST_REGISTER)
					draw_tea_set(at+Vector2(41,0))
					draw_tea_snack_shelf(at+Vector2(64,0),{Industry.SNACK_VISUAL_FIELD:["garden_cookie","tea_pudding"]})
				"tea_table":
					if cell+Vector2i.RIGHT in house.PART_CELLS:
						object_sprite(at,Industry.BAMBOO_TEA_TABLE)
					else:
						object_sprite(at,World.INN_TEA_TABLE)
						draw_tea_set(at+Vector2(8,-4))
				_:object_sprite(at,kind)
			var point:="%s:%s"%[house.SIT,World.key(cell)]
			if house.SEAT_FEET.has(cell) and focused_label==point and own_chair!=cell:
				world_label(at+Vector2(16,-14),"坐下",point)
		if TEA_HOUSE_DECOR.has(cell):_draw_room_decor(at,TEA_HOUSE_DECOR[cell],Vector2(10,0))
		if TEA_HOUSE_EXTRA.has(cell):_draw_room_extra(at,TEA_HOUSE_EXTRA[cell])
		if TEA_ROOM_PROPS.has(cell):_draw_room_prop(at,TEA_ROOM_PROPS[cell])

## The door prompt sits on the very anchor the action uses (outdoor door, or the inside exit).
func _draw_tea_house_door_label(house,anchors:Dictionary,y:int,inside:bool) -> void:
	if not anchors.has(house.PORTAL):return
	var anchor:Vector2=anchors[house.PORTAL]
	if floori(anchor.y)!=y:return
	world_label(screen(anchor)+Vector2(0,-6),"回到山徑" if inside else "進茶館",house.PORTAL)

## Extra render-only dressing for the tea house and pottery workshop, keyed by world cell and drawn in that
## cell's row pass after furniture. Tabletop entries pair an item ID with its local pixel rectangle.
const TEA_HOUSE_EXTRA:={
	Vector2i(62,17):"sign",Vector2i(64,17):"frame",Vector2i(56,22):"niche",Vector2i(70,22):"niche",
	Vector2i(58,17):"bamboo_blind",Vector2i(68,17):"bamboo_blind",
	Vector2i(56,25):"side_frame",Vector2i(70,25):"niche",
	Vector2i(58,18):["tea_jar",Rect2(6,-21,16,16)],Vector2i(59,18):["tea_worn_jar",Rect2(8,-21,16,16)],
	Vector2i(67,18):["tea_spent_jar",Rect2(6,-21,16,16)],Vector2i(68,18):["tea_jar",Rect2(8,-21,16,16)],
	Vector2i(64,19):["tea_jar",Rect2(8,-12,16,16)],
	Vector2i(59,22):["tea_jar",Rect2(6,3,14,14)],Vector2i(66,22):["tea_worn_jar",Rect2(6,3,14,14)],
}
const TEA_ROOM_PROPS:={
	Vector2i(57,17):[POSTCARD_RACK_ART,Rect2(4,1,24,28)],
	Vector2i(69,17):[BambooCurtainArt.TEXTURE,Rect2(4,3,24,27)],
	Vector2i(58,25):[ROOM_TEA_PUDDING_ART,Rect2(17,-4,14,14)],
	Vector2i(68,25):[ROOM_TEA_PUDDING_ART,Rect2(17,-4,14,14)],
	Vector2i(59,22):[ROOM_TEA_SERVICE_ART,Rect2(19,-3,22,22)],
	Vector2i(66,22):[ROOM_TEA_SERVICE_ART,Rect2(19,-3,22,22)],
}
const POTTERY_EXTRA:={
	Vector2i(59,16):"tool_board",Vector2i(62,16):"sign",Vector2i(52,22):"niche",Vector2i(67,22):"niche",
	Vector2i(53,16):"frame",Vector2i(66,16):"chime",
	Vector2i(55,17):["tea_spent_jar",Rect2(6,-12,17,17)],Vector2i(60,17):["clay",Rect2(6,-11,17,17)],
	Vector2i(64,17):["flower_pot",Rect2(6,-13,18,18)],
	Vector2i(54,22):"glaze_samples",Vector2i(64,22):"unfired_cups",
	Vector2i(52,25):"side_frame",Vector2i(67,25):"niche",
}
const POTTERY_ROOM_PROPS:={
	Vector2i(54,22):[ROOM_POT_ART,Rect2(20,-7,18,18)],
	Vector2i(64,22):[ROOM_TEA_SERVICE_ART,Rect2(20,-7,18,18)],
	Vector2i(56,17):[ROOM_TEA_SERVICE_ART,Rect2(15,-14,19,19)],
	Vector2i(61,17):[ROOM_POT_ART,Rect2(15,-14,19,19)],
	Vector2i(65,17):[ROOM_TEA_SERVICE_ART,Rect2(15,-14,19,19)],
}

func _draw_room_extra(at:Vector2,decor:Variant) -> void:
	if decor is Array:
		var item:String=decor[0]
		var rect:Rect2=decor[1]
		var icon:Texture2D=MarketItemArt.icon(item) if item=="flower_pot" else TeaArt.icon(item)
		if icon!=null:draw_texture_rect(icon,Rect2(at+rect.position,rect.size),false)
		return
	match decor:
		"sign":draw_texture(HOME_SIGN_ART,at+Vector2(0,8))
		"frame":BarkFrameArt.draw(self,at+Vector2(0,3),World.BARK_FRAME.SKETCH)
		"side_frame":BarkFrameArt.draw(self,at+Vector2(0,-9),World.BARK_FRAME.SKETCH)
		"niche","chime","lamp":_draw_room_decor(at,decor)
		"bamboo_blind":
			draw_texture_rect(BambooCurtainArt.TEXTURE,Rect2(at+Vector2(7,14),Vector2(19,14)),false)
		"glaze_samples":
			draw_tea_set(at+Vector2(20,1))
		"unfired_cups":
			draw_tea_set(at+Vector2(20,1),Color("daa788"))
		"tool_board":
			draw_texture(TOOL_BOARD_ART,at+Vector2(-31,3))
			draw_texture_rect(ToolActionFeedback.held_icon("build"),Rect2(at+Vector2(-23,5),Vector2(18,18)),false)
			draw_texture_rect(TeaArt.icon("clay"),Rect2(at+Vector2(8,5),Vector2(18,18)),false)

## Chair cell the person is seated on, or (-1,-1). Accepts "x,y" or "<action>:x,y".
func tea_house_seat_cell(person:Dictionary) -> Vector2i:
	var raw:=str(person.get(World.TEA_HOUSE_INTERIOR.SEAT_KEY,""))
	if not raw.contains(","):return Vector2i(-1,-1)
	return World.cell(raw.get_slice(":",1) if raw.contains(":") else raw)

## ---- 鶯歌合作陶坊（室內）：render-only. Stations, stock, queue and cooldown all come from the tea record. ----
const POTTERY_KILN_ART=preload("res://assets/bakery/clay-kiln.png")
## Room-local decor cells (relative to ROOM.position); each is skipped when furniture or a station owns the cell.
const POTTERY_DECOR:={
	Vector2i(2,1):"pot",Vector2i(7,1):"mural",Vector2i(11,1):"chime",
	Vector2i(1,8):"lamp",Vector2i(14,8):"lamp",
}

func pottery_inside() -> bool:
	var pottery:=World.POTTERY_WORKSHOP_INTERIOR
	return region_id()==pottery.REGION and pottery.inside(data.get("players",{}).get(player_id,{}))

func _pottery_window_xs(room:Rect2i) -> Array:
	return [room.position.x+2,room.position.x+5,room.position.x+9,room.position.x+13]

## Open floor only: inside the walls, not furniture, not a station and not the doorway.
func _pottery_open(pottery,cell:Vector2i) -> bool:
	return pottery.ROOM.has_point(cell) and not pottery.blocked(cell) and not pottery.STATIONS.has(cell) and cell!=pottery.EXIT

func _draw_pottery_ground(at:Vector2,cell:Vector2i) -> void:
	ground_tile(at,"floor")
	draw_rect(Rect2(at,Vector2(32,32)),Color(0.40,0.22,0.13,0.36)) # walnut wash over the shared plank tile
	var hash_value:=absi(cell.x*7127+cell.y*19391)
	if hash_value%7==0:draw_rect(Rect2(at+Vector2(5+hash_value%13,10),Vector2(5,2)),Color(0.80,0.55,0.38,0.5)) # clay dust
	elif hash_value%13==0:draw_rect(Rect2(at+Vector2(8,21),Vector2(3,3)),Color(0.25,0.14,0.09,0.5)) # wood knot

func _draw_pottery_floor(pottery) -> void:
	var room:Rect2i=pottery.ROOM
	for wx:int in _pottery_window_xs(room):
		draw_rect(Rect2(screen(Vector2(wx,room.position.y+1)),Vector2(32,64)),Color(1.0,0.82,0.52,0.10))
	var exit_cell:Vector2i=pottery.EXIT
	var lane_top:int=room.position.y+5
	var runner:=Rect2(screen(Vector2(float(exit_cell.x)+0.18,float(lane_top))),Vector2(22,32.0*float(exit_cell.y-lane_top)))
	draw_rect(runner,Color("94503a"))
	draw_rect(runner.grow(-3),Color("d9a86a"),false,1.0)
	for mark in range(exit_cell.y-lane_top):
		var mid:=runner.position+Vector2(11,16+32*mark)
		draw_colored_polygon(PackedVector2Array([mid-Vector2(0,5),mid+Vector2(5,0),mid+Vector2(0,5),mid-Vector2(5,0)]),Color("e2b676"))
	draw_rect(Rect2(screen(Vector2(exit_cell))+Vector2(3,6),Vector2(26,26)),Color("9b5b3b"))
	draw_rect(Rect2(screen(Vector2(exit_cell))+Vector2(6,9),Vector2(20,20)),Color("c99a62"),false,1.0)
	# Side-zone clay mats on open floor beside the work tables, and a stone wedging pad in front of the clay chest.
	for spot:Vector2i in [Vector2i(room.position.x+1,room.position.y+6),Vector2i(room.end.x-2,room.position.y+6)]:
		if not pottery.blocked(spot):draw_texture_rect(LeafMatArt.TEXTURE,Rect2(screen(Vector2(spot))+Vector2(-4,-3),Vector2(40,40)),false,Color("c98f66"))
	for x in [54,64]:
		var at:=screen(Vector2(x,23))
		draw_texture_rect(BRAIDED_RUG_ART,Rect2(at+Vector2(-3,-11),Vector2(68,48)),false,Color("c4aa8c"))
	var clay:Vector2i=pottery.station_cell("clay")
	if clay.x>=0:
		for offset in [Vector2i.DOWN,Vector2i(1,1)]:
			if not pottery.blocked(clay+offset) and not pottery.STATIONS.has(clay+offset):StoneFloorArt.draw(self,screen(Vector2(clay+offset)),Color("c9a98a"))
	var potter:Vector2i=pottery.station_cell("potter")
	if potter.x>=0:draw_texture(BRAIDED_RUG_ART,screen(Vector2(potter.x-0.5,potter.y+1)),Color("d4a27f"))
	var kiln:Vector2i=pottery.station_cell("kiln")
	if kiln.x<0:return
	for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
		StoneFloorArt.draw(self,screen(Vector2(kiln+offset)),Color("bca287"))

func _draw_pottery_ware(at:Vector2,id:String,extent:float) -> void:
	var ware:=TeaArt.icon(id)
	if ware:draw_texture_rect(ware,Rect2(at,Vector2(extent,extent)),false)

func _draw_pottery_station(at:Vector2,site:String,record:Dictionary) -> void:
	var now:=float(data.get("time",0.0))
	match site:
		"clay":
			draw_stone_workbench(at,false,Color("cfac8d"))
			var restocked:=now>=float(record.get("clay_ready",0))
			TeaArt.draw_status_icon(self,at+Vector2(5,-5),"clay",Color.WHITE if restocked else Color(1,1,1,0.45))
			_draw_pottery_ware(at+Vector2(37,-2),"tea_worn_jar",21.0)
			if restocked and not (reduced_motion or photograph_mode):
				var glint:=fposmod(elapsed*0.8,1.0)
				draw_rect(Rect2((at+Vector2(21,-4-glint*8.0)).round(),Vector2(2,2)),Color(1,0.9,0.7,1.0-glint))
		"potter":
			TeaResidents.draw_resident(self,at+Vector2(26,7),"potter")
			draw_wide_workbench(at+Vector2(0,3),false)
			_draw_pottery_ware(at+Vector2(34,-5),"tea_jar",23.0)
			_draw_pottery_ware(at+Vector2(6,1),"clay",18.0)
		"kiln":
			var kiln_at:=at+Vector2(0,-48)
			draw_texture(POTTERY_KILN_ART,kiln_at)
			var job:Dictionary=record.get("kiln",{})
			if not job.is_empty() and now<float(job.get("ready",0)):
				var still:=reduced_motion or photograph_mode
				var glow:=0.65 if still else 0.56+0.16*sin(elapsed*3.8)
				draw_line(kiln_at+Vector2(24,67),kiln_at+Vector2(39,67),Color(1.0,0.52,0.18,glow),3.0)
				TeaArt.draw_heat(self,kiln_at+Vector2(33,7),true,elapsed,still)
			elif not job.is_empty():
				var ready_icon:=MarketItemArt.icon("flower_pot") if job.get("kind")=="flower_pot" else TeaArt.icon("tea_jar")
				if ready_icon:draw_texture_rect(ready_icon,Rect2(at+Vector2(46,-9),Vector2(25,25)),false)
	var id:="tea:"+site
	world_label(at+Vector2(16,-25 if site=="potter" else -26 if site=="kiln" else -17),tea_site_label(site),id)

func _draw_pottery_furniture(at:Vector2,cell:Vector2i,kind:String) -> void:
	match kind:
		"long_bench":
			draw_texture(GRID_BOOKCASE_WIDE,at+Vector2(1,-9),Color("d8b48d"))
			_draw_pottery_ware(at+Vector2(36,-7),"tea_jar" if cell.x%2==0 else "tea_worn_jar",21.0)
		"table":
			draw_wide_workbench(at,false,Color("e6c49c"))
			_draw_pottery_ware(at+Vector2(3,-1),"tea_jar",20.0)
			_draw_pottery_ware(at+Vector2(33,0),"tea_spent_jar" if cell.x<60 else "clay",21.0)
		_:object_sprite(at,kind)

## Walls, windows, furniture and stations of one workshop row.
func _draw_pottery_row(pottery,y:int,record:Dictionary) -> void:
	var room:Rect2i=pottery.ROOM
	if y<room.position.y or y>=room.end.y:return
	var windows:Array=_pottery_window_xs(room)
	for x in range(room.position.x,room.end.x):
		var cell:=Vector2i(x,y)
		var at:=screen(Vector2(cell))
		if cell==pottery.EXIT:continue
		if y==room.position.y or y==room.end.y-1 or x==room.position.x or x==room.end.x-1:
			object_sprite(at,"wall")
			if y==room.position.y and x in windows:object_sprite(at,"window")
		elif pottery.STATIONS.has(cell):_draw_pottery_station(at,pottery.STATIONS[cell],record)
		elif pottery.FURNITURE.has(cell):_draw_pottery_furniture(at,cell,pottery.FURNITURE[cell])
		var decor:String=POTTERY_DECOR.get(cell-room.position,"")
		if not decor.is_empty() and _pottery_open(pottery,cell):_draw_room_decor(at,decor,Vector2(10,0))
		if POTTERY_EXTRA.has(cell):_draw_room_extra(at,POTTERY_EXTRA[cell])
		if POTTERY_ROOM_PROPS.has(cell):_draw_room_prop(at,POTTERY_ROOM_PROPS[cell])

## Outdoor doorway: a woven mat underfoot, framed by a sign and two jars.
func _draw_pottery_doorway(at:Vector2) -> void:
	draw_texture_rect(LeafMatArt.TEXTURE,Rect2(at+Vector2(-4,-3),Vector2(40,40)),false,Color("cdad85"))
	FurnitureArt.draw_sprite(self,at+Vector2(-34,1),"sign")
	_draw_pottery_ware(at+Vector2(-12,13),"tea_worn_jar",20.0)
	_draw_pottery_ware(at+Vector2(24,13),"tea_jar",20.0)

## The door prompt sits on the very anchor the action uses (outdoor door, or the inside exit).
func _draw_pottery_door_label(pottery,anchors:Dictionary,y:int,inside:bool) -> void:
	if not anchors.has(pottery.PORTAL):return
	var anchor:Vector2=anchors[pottery.PORTAL]
	if floori(anchor.y)!=y:return
	world_label(screen(anchor)+Vector2(0,-6 if inside else -14),"回到鶯歌" if inside else "進陶坊",pottery.PORTAL)

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
		night_lamp_pool=make_lamp_pool(PackedColorArray([Color(1.0,0.82,0.43,0.52),Color(1.0,0.70,0.37,0.23),Color(1.0,0.62,0.30,0.0)]))
	var visible:=Rect2i(from,to-from)
	var objects:Dictionary=data.get("objects",{})
	for key:String in objects:
		var kind:String=objects[key].get("type","")
		if kind not in ["lamp","lantern_post",World.STAR_GARDEN_LAMP,Industry.SPORE_LAMP,Industry.PAPER_TEA_LAMP]:continue
		if kind in Industry.SWITCHABLE_LAMPS and objects[key].get("lamp_off",false):continue
		var cell:=World.cell(key)
		if not visible.has_point(cell):continue
		if kind==Industry.SPORE_LAMP:
			if spore_lamp_pool==null:
				spore_lamp_pool=make_lamp_pool(PackedColorArray([Color(0.67,0.95,0.80,0.70),Color(0.43,0.85,0.71,0.30),Color(0.36,0.72,0.63,0.0)]))
			draw_night_lamp(cell,strength,Vector2(82,50),Color.WHITE,spore_lamp_pool)
		elif kind==World.STAR_GARDEN_LAMP:
			draw_night_lamp(cell,strength,Vector2(60,42),Color(1.0,1.12,1.30,0.82))
		elif kind==Industry.PAPER_TEA_LAMP:
			# Constant warm pool: scaled only by the shared night strength, no time-based term.
			draw_night_lamp(cell,strength,Vector2(66,40),Color(1.0,1.0,1.0,0.88))
		else:
			draw_night_lamp(cell,strength)
	if region_id()==World.REGIONS.HOME:
		for glow:Dictionary in WarmLanternArt.glows(data,visible,elapsed,reduced_motion or photograph_mode):
			draw_night_lamp(glow.cell,strength,glow.size,glow.tint,glow.pool)
	var dock:=World.RESIDENT_GOALS.VOYAGE_LAMP_CELL
	if region_id()==World.REGIONS.HOME and data.get(World.RESIDENT_GOALS.DOCK_LIGHT,false) and visible.has_point(dock):
		draw_night_lamp(dock,strength)

static func make_lamp_pool(colors:PackedColorArray) -> GradientTexture2D:
	var ramp:=Gradient.new()
	ramp.offsets=PackedFloat32Array([0.0,0.42,1.0])
	ramp.colors=colors
	var texture:=GradientTexture2D.new()
	texture.gradient=ramp
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(0.5,0.5)
	texture.fill_to=Vector2(1.0,0.5)
	return texture

func draw_night_lamp(cell:Vector2i,strength:float,pool_size:=Vector2(104,60),tint:=Color.WHITE,pool:GradientTexture2D=null) -> void:
	var center:=screen(Vector2(cell)+Vector2(0.5,0.65))
	tint.a*=strength
	draw_texture_rect(pool if pool else night_lamp_pool,Rect2(center-pool_size/2.0,pool_size),false,tint)

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
	if kind==World.TERRACOTTA_ROOF.KIND:
		preload("res://scripts/terracotta_roof_art.gd").draw_roof(self,at,alpha)
		return
	if kind==World.GREENHOUSE_GLASS.XINGHE_ROOF:
		draw_texture(preload("res://assets/ui-life/xinghe-greenhouse-roof.png"),at+Vector2(0,-8),Color(1,1,1,alpha))
		return
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

func draw_public_mill(at:Vector2)->void:
	var mill:=World.MILL_RESTORATION
	var ready:=mill.repaired(data)
	var art:=BakeryArt.village_mill_texture(0)
	if art!=null:draw_texture(art,at+Vector2(0,-16),Color.WHITE if ready else Color("c1aea0"))
	var running:bool=ready and data.get(mill.BUSY,false)
	if running:
		var quiet:=reduced_motion or photograph_mode
		var look:=BakeryArt.MillFeedback.sample({"valid":true,"working":true},elapsed,quiet)
		for pixel:Dictionary in look.pixels:
			var spot:Rect2=pixel.rect
			spot.position+=at+Vector2(1,43)
			draw_rect(spot,pixel.color)
		if not quiet:
			var rim:=[Vector2(87,77),Vector2(90,81),Vector2(91,87),Vector2(89,93),Vector2(86,98)]
			var glint:Vector2=rim[posmod(floori(elapsed*6.0),rim.size())]
			draw_rect(Rect2(at+glint-Vector2(0,16),Vector2(2,2)),Color("dfaf73"))
	if focused_label==mill.POINT:
		var caption:="渡口磨坊" if ready else "渡口舊磨坊"
		var job:Dictionary=data.get("players",{}).get(player_id,{}).get(mill.JOB,{})
		if not job.is_empty() and float(job.ready)<=float(data.time):caption+=" · 可領成品"
		elif running:caption+=" · 運轉中"
		world_label(at+Vector2(48,-22),caption,mill.POINT)

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
	if reduced_motion or photograph_mode or (tool_feedback.actions.is_empty() and tool_feedback.tails.is_empty()):
		_draw_tree_sprite(at)
		return
	var angle:float=tool_feedback.resource_pose(draw_cell(at),"axe",elapsed,false).angle
	if angle==0.0:
		_draw_tree_sprite(at)
		return
	var pivot:=at+Vector2(16,29)
	var zoom_scale:=Vector2.ONE*view_zoom()
	draw_set_transform((pivot-pivot.rotated(angle))*zoom_scale,angle,zoom_scale)
	_draw_tree_sprite(at)
	draw_set_transform(Vector2.ZERO,0.0,zoom_scale)

## The natural home layout is fixed. Removals and planted trees are snapshot
## layers and are checked before this lookup.
func home_base_resource(cell:Vector2i) -> String:
	if home_base_resources.has(cell):return home_base_resources[cell]
	var resource:=World.base_resource(cell)
	if Rect2i(Vector2i.ZERO,World.SIZE).has_point(cell):
		home_base_resources[cell]=resource
	return resource

func draw_resource_finish(at:Vector2,cell:Vector2i) -> void:
	if village_art==null:return
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
	if village_art:
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
	if reduced_motion or photograph_mode or (tool_feedback.actions.is_empty() and tool_feedback.tails.is_empty()):
		_draw_rock_sprite(at)
		return
	var shift:Vector2=tool_feedback.resource_pose(draw_cell(at),"pick",elapsed,false).shift
	if shift==Vector2.ZERO:
		_draw_rock_sprite(at)
		return
	var zoom_scale:=Vector2.ONE*view_zoom()
	draw_set_transform(shift*zoom_scale,0.0,zoom_scale)
	_draw_rock_sprite(at)
	draw_set_transform(Vector2.ZERO,0.0,zoom_scale)

func _draw_rock_sprite(at:Vector2) -> void:
	if region_id()=="jinguashi" and village_art:
		JinguashiArt.draw_rock_ledge(self,at,village_art,draw_cell(at))
		return
	if village_art:
		village_art.draw_prop(self,at,6)
		return
	draw_rect(Rect2(at+Vector2(2,23),Vector2(28,6)),Color(0.2,0.3,0.3,0.15))
	draw_rect(Rect2(at+Vector2(3,9),Vector2(25,17)),Color("869b98"))
	draw_rect(Rect2(at+Vector2(8,4),Vector2(15,21)),Color("aab9ac"))
	draw_rect(Rect2(at+Vector2(7,8),Vector2(12,7)),Color("c1cbb8"))
	draw_rect(Rect2(at+Vector2(21,15),Vector2(5,8)),Color("758c89"))

func grass(at:Vector2) -> void:
	if village_art:
		village_art.draw_prop(self,at,4 if (draw_cell(at).x+draw_cell(at).y)%3==0 else 7)
		return
	for x in [7,13,20]:
		draw_rect(Rect2(at+Vector2(x,12+x%5),Vector2(4,13)),Color("709c5e"))
		draw_rect(Rect2(at+Vector2(x-3,16),Vector2(4,4)),Color("83af6c"))

func _draw_leaf_mat(at:Vector2,key:String) -> void:
	if data.ground.get(key,{}).get("type")==Industry.LEAF_MAT:ground_tile(at,Industry.LEAF_MAT)

func ground_tile(at:Vector2,kind:String,style:="") -> void:
	if kind==Industry.LEAF_MAT:
		var tile:=draw_cell(at+Vector2(16,16))
		var mat:Dictionary=data.ground[World.key(tile)]
		var offset:Vector2i=Industry.SQUARE_CELLS[Industry.square_part(mat)]
		var anchor:Dictionary=data.ground[World.key(tile-offset)]
		draw_texture_rect_region(LeafMatArt.TEXTURE,Rect2(at,Vector2(32,32)),Rect2(Vector2(offset)*32,Vector2(32,32)),LeafMatArt.tint(anchor.get("leaf_mat_shade","light")))
		return
	if kind==World.ROOM_ENCLOSURE.STONE_FLOOR:
		# C09: same tile in the village and elsewhere; never falls into the 石板路 branch below.
		StoneFloorArt.draw(self,at,build_tint(style))
		return
	if kind=="spring_pebble_path":
		draw_texture_rect_region(preload("res://assets/village-preview/terrain.png"),Rect2(at,Vector2(32,32)),Rect2(96,64,32,32),Color("f3c99c"))
		return
	var tint:=build_tint(style)
	if village_art:
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
	if not farm_feedback.ripened.is_empty() and not (reduced_motion or photograph_mode):
		var ripening:=farm_feedback.ripening_age(World.key(draw_cell(at)),elapsed)
		if ripening>=0.0:draw_crop_ripening(at,ripening)
	if crop.get("owner","")!=player_id:return
	var observation:Dictionary=data.get("own_xinghe_growth",{})
	if not photograph_mode and not observation.is_empty() and observation.region==region_id() and observation.kind==crop.get("kind","") and observation.tile==World.key(draw_cell(at)):
		var peg:=at+Vector2(24,10)
		draw_rect(Rect2(peg+Vector2(4,5),Vector2(3,13)),Color("865932"))
		draw_rect(Rect2(peg,Vector2(11,9)),Color("674732"))
		draw_rect(Rect2(peg+Vector2(1,1),Vector2(9,7)),Color("fff0b6"))
		draw_rect(Rect2(peg+Vector2(3,3),Vector2(5,1)),Color("617844"))
		draw_rect(Rect2(peg+Vector2(3,5),Vector2(3,1)),Color("617844"))
	var definition:Dictionary=World.CROPS.get(crop.get("kind",""),{})
	if definition.is_empty() or float(crop.growth)<float(definition.time):return
	if World.farming_level(data.get("players",{}).get(player_id,{}))>=World.MASTER_FARMING_LEVEL:
		draw_texture(preload("res://assets/bakery/ripe-sparkle.png"),at+Vector2(22,1))

func draw_crop_ripening(at:Vector2,age:float) -> void:
	const SPARKLE=preload("res://assets/bakery/ripe-sparkle.png")
	for index in 2:
		var phase:=(age-float(index)*0.18)/(FarmFeedback.RIPEN_DURATION-0.18)
		if phase<=0.0 or phase>=1.0:continue
		var start:=Vector2(7,-5) if index==0 else Vector2(19,-8)
		var drift:=Vector2(-4,-9) if index==0 else Vector2(4,-8)
		var opacity:=minf(1.0,minf(phase*10.0,(1.0-phase)*2.4))
		draw_texture(SPARKLE,(at+start+drift*phase).round(),Color(1,1,1,opacity))

## 這格作物是否正在等季節（只讀快照；規則在 World.plot_dormant）。
func crop_dormant(tile:Vector2i,crop:Dictionary) -> bool:
	var roof=data.get("roofs",{}).get(World.key(tile),{})
	return World.plot_dormant(crop,roof if roof is Dictionary else {},region_id(),tile,float(data.get("time",0.0)),World.GREENHOUSE_GLASS.covered(data,World.key(tile),greenhouse_memo))

func draw_crop_tile(at:Vector2,crop:Dictionary) -> void:
	var wet:bool=crop.wet
	if village_art:
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
	if kind == Industry.MILL:
		return Industry.mill_cells() if mill_build_facing >= 0 else [Vector2i.ZERO]
	if kind==Industry.WORKBENCH:return Industry.station_cells(kind)
	if kind in Industry.FIXED_SQUARE_STATIONS or kind in Industry.EXPANDABLE_STATIONS or kind in Industry.ORIENTABLE_FOOTPRINTS:
		return Industry.station_cells(kind,kind in [Industry.INN_BED,Industry.BEACH_CHAIR,Industry.BAMBOO_LOUNGER,Industry.GRID_BOOKCASE,Industry.CEDAR_BED])
	if kind in World.RESIDENT_GOALS.DOUBLE_BENCHES:return [Vector2i.ZERO,Vector2i.RIGHT]
	return [Vector2i.ZERO]

func build_placement_blocks(anchor:Vector2i,kind:String) -> Dictionary:
	var blocked:Dictionary={}
	for offset:Vector2i in build_placement_offsets(kind):
		var tile:=anchor+offset
		var key:=World.key(tile)
		if not World.land(tile,region_id()):blocked[tile]="需要陸地"
		elif kind==Industry.IMPERFECT_TEA_PAVILION and not World.essential_cell_reason(data,region_id(),tile).is_empty():blocked[tile]=World.PAVILION.ESSENTIAL_MESSAGE
		elif kind in World.BLUEPRINT_DESIGN.ROOF_KINDS:
			# C16: terracotta may re-tile a thatch roof (the server stays authoritative).
			if data.get("roofs",{}).has(key) and not (kind==World.TERRACOTTA_ROOF.KIND and World.TERRACOTTA_ROOF.replaceable(data.roofs[key],player_id)):blocked[tile]="已有屋頂"
			elif World.TERRACOTTA_ROOF.is_house_roof(kind) and not World.ROOM_ENCLOSURE.is_floor_kind(data.get("ground",{}).get(key,{}).get("type")):blocked[tile]="需先鋪地板"
		elif kind==World.ROOF_FIXTURES.HANGING_POT:
			if not World.ROOF_FIXTURES.supported(data.get("roofs",{}).get(key),player_id):blocked[tile]=World.ROOF_FIXTURES.SUPPORT_MESSAGE
			elif data.get("objects",{}).has(key):blocked[tile]="已有物件"
		elif data.get("crops",{}).has(key):blocked[tile]="已有作物"
		elif data.get("objects",{}).has(key):
			var object:Dictionary=data.objects[key]
			if not (World.ROOM_ENCLOSURE.is_floor_kind(kind) and object.type==Industry.BRAIDED_RUG and object.owner==player_id):blocked[tile]="已有物件"
			elif data.get("ground",{}).has(key):blocked[tile]="已有鋪面"
		elif kind in World.WALL_FIXTURES.KINDS and not World.WALL_FIXTURES.has_support(data.get("objects",{}),tile,player_id,kind,data.get("edges",{})):
			blocked[tile]=World.WALL_FIXTURES.support_message(kind)
		elif kind in World.BLUEPRINT_DESIGN.GROUND_KINDS and data.get("ground",{}).has(key):blocked[tile]="已有鋪面"
	if kind == Industry.MILL and mill_build_facing >= 0:
		var front := anchor + Industry.mill_front_offset(mill_build_facing)
		var outside: Dictionary = data.get("objects", {}).get(World.key(front), {})
		if not World.land(front,region_id()) or (outside.get("type", "") in World.UNDO_SOLID and not Industry.is_folded_passage(outside)):
			blocked[front] = "磨坊入口需要留出通道"
	return blocked

func draw_build_placement_art(at:Vector2) -> void:
	var tint:=Color(Color.WHITE,0.58)
	if Industry.SPRINKLER_CAPACITIES.has(building):
		AutomationArt.draw_sprinkler(self,at,{},0.0,true,building,tint)
	elif building in IndustryArt.DEVICES:
		IndustryArt.draw_device(self,at,building,{},0.0,true,tint)
	else:
		match building:
			Industry.MILL:
				var art := BakeryArt.village_mill_texture(mill_build_facing) if mill_build_facing >= 0 else BakeryArt.mill_texture()
				if art != null:draw_texture(art,at+Vector2(0,-16),tint)
			World.RESIDENT_GOALS.COTTON_SOFA,World.RESIDENT_GOALS.BAMBOO_BENCH:draw_texture(independent_seat_art(building,false),at+independent_seat_offset(building,false),tint)
			"forester":ForestryArt.draw_station(self,at,{},0.0,true,tint)
			Industry.VINE_ARCH,Industry.FOREST_ARCH:draw_arch(at,building,"pink",false,tint)
			Industry.WORKBENCH:draw_wide_workbench(at,false,tint)
			Industry.STONE_WORKBENCH:draw_stone_workbench(at,false,tint)
			Industry.POT_RACK:draw_texture(preload("res://assets/ui-life/copper-flower-rack.png"),at+Vector2(0,-16),tint)
			Industry.NURSERY_BOX:draw_texture(NURSERY_WIDE,at+Vector2(1,0),tint)
			Industry.COAST_FISH_COUNTER:draw_texture(FISH_COUNTER_WIDE,at+Vector2(0,-6),tint)
			Industry.TEA_DISPLAY_CABINET:draw_texture(TEA_CABINET_WIDE,at+TEA_CABINET_WIDE_AT,tint)
			Industry.TEA_SNACK_SHELF:draw_texture(TEA_SNACK_SHELF_ART,at,tint)
			Industry.COAST_AWNING:CoastAwningArt.draw_canopy(self,at,false,tint)
			Industry.IMPERFECT_TEA_PAVILION:
				PavilionArt.draw_base(self,at,tint)
				PavilionArt.draw_canopy(self,at,tint)
			Industry.LEAF_MAT:draw_texture(LeafMatArt.TEXTURE,at,tint)
			Industry.BRAIDED_RUG:draw_texture(BRAIDED_RUG_ART,at,tint)
			Industry.SPORE_LAMP:draw_texture(SPORE_LAMP_ART,at,tint)
			Industry.PAPER_TEA_LAMP:draw_texture(PAPER_TEA_LAMP_ART,at+PAPER_TEA_LAMP_AT,tint)
			Industry.ACORN_CABINET:draw_texture(ACORN_CABINET_ART,at,tint)
			Industry.QUIET_BIRDHOUSE:draw_texture(BirdhouseArt.HOUSE,at+Vector2(0,-14),tint)
			Industry.MUSHROOM_POST:draw_texture(MUSHROOM_POST_ART,at+Vector2(0,-10),tint)
			Industry.LEAF_DESK:draw_texture(LEAF_DESK_WIDE,at+Vector2(0,-16),tint)
			Industry.GRID_BOOKCASE:draw_texture(GRID_BOOKCASE_TALL,at+Vector2(1,-9),tint)
			Industry.HEDGEHOG_BASKET:draw_texture(HEDGEHOG_BASKET_ART,at,tint)
			Industry.MUSHROOM_STOOL:draw_texture_rect(MUSHROOM_STOOL_ART,Rect2(at+Vector2(4,14),Vector2(24,19)),false,tint)
			Industry.WOOD_CHAIR:draw_texture(WOOD_CHAIR_ART,at+Vector2(4,1),tint)
			Industry.INDIGO_CUSHION:draw_texture(INDIGO_CUSHION_ART,at+INDIGO_CUSHION_AT,tint)
			Industry.MUSHROOM_TABLE:draw_mushroom_table(at,{},tint)
			Industry.BAMBOO_TEA_TABLE:draw_bamboo_tea_table(at,{},false,tint)
			Industry.HOLLOW_BED:draw_texture(HOLLOW_BED_ART,at+Vector2(0,-15),tint)
			Industry.CEDAR_BED:draw_texture(CEDAR_BED_LONG,at+Vector2(1,-4),tint)
			Industry.COAST_CART:draw_texture(MARKET_CART_ART,at+Vector2(0,-10),tint)
			Industry.COAST_REGISTER:draw_texture(REGISTER_WIDE,at+Vector2(1,-9),tint)
			Industry.BEACH_CHAIR:draw_texture(BEACH_LONG,at+Vector2(1,-6),tint)
			Industry.RIVERSIDE_SCREEN:draw_texture(RIVERSIDE_WIDE,at+Vector2(1,-16),tint)
			Industry.BAMBOO_LOUNGER:draw_texture(LOUNGER_LONG,at+LOUNGER_AT,tint)
			Industry.SHELL_TABLE:draw_texture(SHELL_TABLE_ART,at+Vector2(-7,-7),tint)
			Industry.ROUNDED_TABLE:draw_texture(ROUNDED_TABLE_WIDE,at+Vector2(1,-4),tint)
			World.RESIDENT_GOALS.COAST_WARDROBE:draw_texture(COAST_BOOTH_ART,at+Vector2(1,-16),tint)
			World.RESIDENT_GOALS.FOREST_WARDROBE:draw_texture(FOREST_WARDROBE_ART,at+Vector2(2,-13),tint)
			World.WALL_FIXTURES.BAMBOO_CURTAIN:BambooCurtainArt.draw(self,at,BambooCurtainArt.OUTDOOR_ALPHA,tint,village_art!=null)
			World.WALL_FIXTURES.WATER_LISTENING_CHIME:WaterChimeArt.draw(self,at,-1.0,true,tint)
			World.WALL_FIXTURES.LIFEBUOY:draw_texture(LIFEBUOY_ART,at+Vector2(4,-30),tint)
			World.WALL_FIXTURES.BARK_FRAME:BarkFrameArt.draw(self,at+Vector2(0,-26),"",tint)
			World.WALL_FIXTURES.HOME_SIGN:draw_texture(HOME_SIGN_ART,at+Vector2(0,-24),tint)
			World.WALL_FIXTURES.TOOL_BOARD:draw_texture(TOOL_BOARD_ART,at+Vector2(1,-27),tint)
			World.POSTCARDS.RACK:draw_texture(POSTCARD_RACK_ART,at+Vector2(0,-12),tint)
			World.OAR_SIGN.KIND:draw_texture(OAR_SIGN_ART,at+Vector2(1,-15),tint)
			World.ROOF_FIXTURES.HANGING_POT:draw_hanging_pot(at,0.0,tint)
			World.GREENHOUSE_GLASS.XINGHE_ROOF,World.TERRACOTTA_ROOF.KIND:roof_sprite(at,0.58,building)
			Industry.CLAY_KILN:draw_texture(preload("res://assets/bakery/clay-kiln.png"),at+Vector2(0,-16),tint)
			Industry.SMELTER:draw_texture(preload("res://assets/industry/small-smelter.png"),at+Vector2(0,-12),tint)
			Industry.KITCHEN_STOVE:draw_kitchen_stove(at,{},tint)
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

func draw_aquarium_fish(at:Vector2,vertical:bool) -> void:
	var still:=reduced_motion or photograph_mode
	var phase:=elapsed*1.6+float(draw_cell(at).x)*0.21
	var center:=Vector2(16,25) if vertical else Vector2(32,6)
	var sweep:=Vector2(3,6) if vertical else Vector2(17,3)
	var motion:=Vector2(sin(phase),cos(phase))*sweep if not still else Vector2.ZERO
	var front:=16 if not still and cos(phase)<0.0 else 0
	draw_texture_rect_region(preload("res://assets/ui-life/aquarium-redfish.png"),Rect2(at+center+motion.round()-Vector2(8,5),Vector2(16,10)),Rect2(front,0,16,10))

func draw_rack_pots(at:Vector2,vertical:bool,pots:Array)->void:
	var slots:=[Vector2(16,17),Vector2(16,31),Vector2(16,46)] if vertical else [Vector2(15,11),Vector2(32,11),Vector2(50,11)]
	for index in mini(slots.size(),pots.size()):
		var flower:String=pots[index]
		if flower.is_empty():continue
		var base:Vector2=at+slots[index]
		if flower!=Industry.POT_RACK_EMPTY:
			var blossom:=MarketItemArt.icon(flower)
			var sway:=0.0 if reduced_motion or photograph_mode else roundf(sin(elapsed*1.4+index*0.9))
			if blossom:draw_texture_rect(blossom,Rect2(base+Vector2(-9+sway,-20),Vector2(18,18)),false)
		draw_texture_rect_region(preload("res://assets/ui-inventory/flower-pot.png"),Rect2(base+Vector2(-7,-8),Vector2(14,8)),Rect2(4,18,24,13))

const HANGING_POT_ART=preload("res://assets/ui-life/hanging-flower-pot.png")
const NURSERY_WIDE=preload("res://assets/ui-life/greenhouse-nursery-box.png")
const NURSERY_TALL=preload("res://assets/ui-life/greenhouse-nursery-box-vertical.png")
const FISH_COUNTER_WIDE=preload("res://assets/ui-life/ice-blue-fish-counter.png")
const FISH_COUNTER_TALL=preload("res://assets/ui-life/ice-blue-fish-counter-vertical.png")
const TEA_CABINET_WIDE=preload("res://assets/ui-life/tea-display-cabinet-wide.png")
const TEA_CABINET_TALL=preload("res://assets/ui-life/tea-display-cabinet-long.png")
## Sprite origin inside the 2x1 / 1x2 footprint, and the centre of each of the three counter-top spaces.
const TEA_CABINET_WIDE_AT:=Vector2(1,-9)
const TEA_CABINET_TALL_AT:=Vector2(1,-5)
const TEA_CABINET_WIDE_SPOTS:=[Vector2(13,9),Vector2(31,9),Vector2(49,9)]
const TEA_CABINET_TALL_SPOTS:=[Vector2(15,11),Vector2(15,25),Vector2(15,39)]
const COAST_BOOTH_ART=preload("res://assets/ui-life/coast-changing-booth.png")
const FOREST_WARDROBE_ART=preload("res://assets/ui-life/forest-wardrobe.png")
const BirdhouseArt=preload("res://scripts/quiet_birdhouse_art.gd")
const MUSHROOM_POST_ART=preload("res://assets/ui-life/mushroom-door-mailbox.png")
const MAIL_ICON=preload("res://scripts/life_ui_shell.gd")
const LEAF_DESK_WIDE=preload("res://assets/ui-life/fallen-leaf-desk.png")
const LEAF_DESK_TALL=preload("res://assets/ui-life/fallen-leaf-desk-vertical.png")
const GRID_BOOKCASE_TALL=preload("res://assets/ui-life/grid-bookcase-long.png")
const GRID_BOOKCASE_WIDE=preload("res://assets/ui-life/grid-bookcase-wide.png")
const ForestArchArt=preload("res://scripts/forest_arch_art.gd")
const BarkFrameArt=preload("res://scripts/bark_frame_art.gd")
const BambooCurtainArt=preload("res://scripts/bamboo_curtain_art.gd")
const WaterChimeArt=preload("res://scripts/water_listening_chime_art.gd")

func ring_water_chime(object_key:String) -> void:
	water_chime_rings[object_key]=elapsed
	queue_redraw()

func water_chime_age(object_key:String) -> float:
	if not water_chime_rings.has(object_key):return -1.0
	var age:=elapsed-float(water_chime_rings[object_key])
	if age>=WaterChimeArt.RING_SECONDS:
		water_chime_rings.erase(object_key)
		return -1.0
	return age
const LIFEBUOY_ART=preload("res://assets/ui-life/wall-lifebuoy.png")
const HOME_SIGN_ART=preload("res://assets/ui-life/handcarved-home-sign.png")
const TOOL_BOARD_ART=preload("res://assets/ui-life/wall-tool-board.png")
const POSTCARD_RACK_ART=preload("res://assets/ui-life/sea-breeze-postcard-rack.png")
const TravelCardArt=preload("res://scripts/travel_postcard_art.gd")
const OAR_SIGN_ART=preload("res://assets/ui-life/wooden-oar-sign.png")
const CoastAwningArt=preload("res://scripts/coast_awning_art.gd")
const PavilionArt=preload("res://scripts/imperfect_tea_pavilion_art.gd")
## Drawn in the ground pass / canopy pass instead of the walker row loop.
const PASS_DRAWN_OBJECTS:=[Industry.COAST_AWNING,Industry.INDIGO_CUSHION,Industry.IMPERFECT_TEA_PAVILION]
const REGISTER_WIDE=preload("res://assets/ui-life/whitewood-register.png")
const REGISTER_LONG=preload("res://assets/ui-life/whitewood-register-vertical.png")
const MUSHROOM_TABLE_ART=preload("res://assets/ui-life/mushroom-cap-table.png")
const BAMBOO_TABLE_WIDE=preload("res://assets/ui-life/bamboo-tea-table-wide.png")
const BAMBOO_TABLE_LONG=preload("res://assets/ui-life/bamboo-tea-table-long.png")
const BAMBOO_TABLE_CUSHION=preload("res://assets/ui-life/bamboo-tea-table-cushion.png")
const HEDGEHOG_BASKET_ART=preload("res://assets/ui-life/hedgehog-nap-basket.png")
const ACORN_CABINET_ART=preload("res://assets/ui-life/acorn-cabinet.png")
const SPORE_LAMP_ART=preload("res://assets/ui-life/spore-nightlight.png")
const PAPER_TEA_LAMP_ART=preload("res://assets/ui-life/paper-tea-lamp.png")
## 26x34 sprite centred in its 32px cell, bottom edge 2px above the tile bottom.
const PAPER_TEA_LAMP_AT:=Vector2(3,-4)
const LeafMatArt=preload("res://scripts/leaf_mat_art.gd")
const BRAIDED_RUG_ART=preload("res://assets/ui-life/braided-round-rug.png")
const INDIGO_CUSHION_ART=preload("res://assets/ui-life/indigo-cushion.png")
const INDIGO_CUSHION_AT:=Vector2(2,5)
const MUSHROOM_STOOL_ART=preload("res://assets/ui-life/mushroom-cap-stool.png")
const WOOD_CHAIR_ART=preload("res://assets/ui-life/low-back-wood-chair.png")
const COTTON_SOFA_WIDE=preload("res://assets/ui-life/cotton-double-sofa-wide.png")
const COTTON_SOFA_LONG=preload("res://assets/ui-life/cotton-double-sofa-long.png")
const BAMBOO_BENCH_WIDE=preload("res://assets/ui-life/bamboo-bench-wide.png")
const BAMBOO_BENCH_LONG=preload("res://assets/ui-life/bamboo-bench-long.png")

## Art for the independent two-seat furniture (cotton sofa, bamboo bench); one sprite per orientation.
func independent_seat_art(kind:String,vertical:bool)->Texture2D:
	if kind==World.RESIDENT_GOALS.BAMBOO_BENCH:return BAMBOO_BENCH_LONG if vertical else BAMBOO_BENCH_WIDE
	return COTTON_SOFA_LONG if vertical else COTTON_SOFA_WIDE

## Top-left offset from the anchor cell so the sprite's feet sit on the bottom edge of its footprint.
func independent_seat_offset(kind:String,vertical:bool)->Vector2:
	if kind==World.RESIDENT_GOALS.BAMBOO_BENCH:return Vector2(1,5) if vertical else Vector2(1,-3)
	return Vector2(1,-6) if vertical else Vector2(1,-9)
const HOLLOW_BED_ART=preload("res://assets/ui-life/tree-hollow-bed.png")
const CEDAR_BED_LONG=preload("res://assets/ui-life/cedar-bed-long.png")
const CEDAR_BED_WIDE=preload("res://assets/ui-life/cedar-bed-wide.png")
const MARKET_CART_ART=preload("res://assets/ui-life/xiaoli-market-cart.png")
const SHELL_TABLE_ART=preload("res://assets/ui-life/shell-round-table.png")
const ROUNDED_TABLE_WIDE=preload("res://assets/ui-life/rounded-wood-table-wide.png")
const ROUNDED_TABLE_LONG=preload("res://assets/ui-life/rounded-wood-table-long.png")
const BEACH_WIDE=preload("res://assets/ui-life/beach-chair-wide.png")
const BEACH_LONG=preload("res://assets/ui-life/beach-chair-long.png")
const BEACH_FOLDED=preload("res://assets/ui-life/beach-chair-folded.png")
## T08 河岸屏風: deployed (wide 62x48 / long 30x78) and folded (18x34) sprites.
const RIVERSIDE_WIDE=preload("res://assets/ui-life/riverside-screen-wide.png")
const RIVERSIDE_LONG=preload("res://assets/ui-life/riverside-screen-long.png")
const RIVERSIDE_FOLDED=preload("res://assets/ui-life/riverside-screen-folded.png")
## T10 竹編躺椅: long 30x64 (1x2) and wide 62x32 (2x1) sprites fill the footprint minus 1px each side.
## The head rests at the top / left end; the lounger art is drawn first, then the sleeping head.
const LOUNGER_LONG=preload("res://assets/ui-life/bamboo-lounger-long.png")
const LOUNGER_WIDE=preload("res://assets/ui-life/bamboo-lounger-wide.png")
const LOUNGER_AT:=Vector2(1,0)
const LOUNGER_HEAD_LONG:=Vector2(16,14)
const LOUNGER_HEAD_WIDE:=Vector2(15,17)

func draw_hanging_pot(at:Vector2,sway:float,tint:=Color.WHITE) -> void:
	var start:=at+Vector2(5,-12)
	# Leave the hook fixed and step the cord and bowl in whole pixels.
	for part in [Vector3(0,6,0),Vector3(6,9,0.5),Vector3(15,19,1)]:
		var source:=Rect2(0,part.x,21,part.y)
		draw_texture_rect_region(HANGING_POT_ART,Rect2(start+Vector2(roundf(sway*part.z),part.x),source.size),source,tint)

func draw_nursery_box(at:Vector2,box:Dictionary) -> void:
	var vertical:=Industry.is_vertical(box)
	var anchor:=draw_cell(at)
	var offset:=Vector2(1,6) if vertical else Vector2(1,0)
	var asset:=NURSERY_TALL if vertical else NURSERY_WIDE
	draw_texture(asset,at+offset)
	if crop_art==null:return
	var slots:Dictionary=box.get(World.NURSERY_BOX.SLOTS,{})
	for slot in World.NURSERY_BOX.SLOT_COUNT:
		var crop:Dictionary=slots.get(str(slot),{})
		if not World.CROPS.has(crop.get("kind","")):continue
		var root_at:=at+offset+Vector2(9+(slot%2)*12,23+(slot>>1)*14) if vertical else at+offset+Vector2(18+(slot%2)*27,14+(slot>>1)*9)
		var tile:=World.NURSERY_BOX.plot_cell(anchor,slot,vertical)
		var dormant:=crop_dormant(tile,crop)
		var sway:=0 if reduced_motion or photograph_mode else CropSprites.breeze_offset(elapsed+float(slot),tile)
		var zoom_scale:=view_zoom()
		draw_set_transform(root_at.round()*zoom_scale,0.0,Vector2.ONE*zoom_scale*0.47)
		crop_art.draw_crop(self,-CropSprites.FOOT,crop,dormant,sway)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*zoom_scale)

func draw_fish_counter(at:Vector2,counter:Dictionary)->void:
	var vertical:=Industry.is_vertical(counter)
	var position:=at+Vector2(0,-6)
	draw_texture(FISH_COUNTER_TALL if vertical else FISH_COUNTER_WIDE,position)
	var displayed:=Industry.counter_fish(counter)
	for index in displayed.size():
		var sprite:=MarketItemArt.icon(displayed[index])
		if sprite==null:continue
		var center:=Vector2(16,9+index*13) if vertical else Vector2(13+index*19,9)
		draw_texture_rect(sprite,Rect2(position+center-Vector2(7,7),Vector2(14,14)),false)
	if not (reduced_motion or photograph_mode):
		var glint:=fposmod(elapsed+float(draw_cell(at).x)*0.41,4.8)
		if glint<0.28:
			var corner:=position+(Vector2(23,12) if vertical else Vector2(44,11))
			draw_rect(Rect2(corner,Vector2(3,1)),Color(0.9,1.0,1.0,1.0-glint/0.28))

## Displayed tea comes straight from the cabinet's real `items`: one icon per occupied space.
func draw_tea_cabinet(at:Vector2,cabinet:Dictionary)->void:
	var vertical:=Industry.is_vertical(cabinet)
	var origin:=at+(TEA_CABINET_TALL_AT if vertical else TEA_CABINET_WIDE_AT)
	draw_texture(TEA_CABINET_TALL if vertical else TEA_CABINET_WIDE,origin)
	var spots:Array=TEA_CABINET_TALL_SPOTS if vertical else TEA_CABINET_WIDE_SPOTS
	var slots:=Industry.tea_cabinet_slots(cabinet.get("items",{}))
	for index in slots.size():
		var sprite:=MarketItemArt.icon(slots[index])
		if sprite==null:continue
		draw_texture_rect(sprite,Rect2(origin+Vector2(spots[index])-Vector2(6,6),Vector2(12,12)),false)

## T11 茶屋點心架: the sprite, then the lead (largest) snack of each tier straight from the real
## `snack_tiers` stock, centred on the two empty cavities of the 32x32 art.
const TEA_SNACK_SHELF_ART=preload("res://assets/ui-life/tea-snack-shelf.png")
const SNACK_TIER_SPOTS:=[Vector2(16,13),Vector2(16,23)]
const SNACK_ICON_SIZE:=Vector2(10,10)

func draw_tea_snack_shelf(at:Vector2,shelf:Dictionary)->void:
	draw_texture(TEA_SNACK_SHELF_ART,at)
	var display:Array=shelf.get(Industry.SNACK_VISUAL_FIELD,[])
	for tier in Industry.SNACK_TIER_NAMES.size():
		var lead:=str(display[tier]) if tier<display.size() else Industry.snack_lead(shelf,tier)
		if lead.is_empty():continue
		var sprite:=MarketItemArt.icon(lead)
		if sprite==null:continue
		draw_texture_rect(sprite,Rect2((at+SNACK_TIER_SPOTS[tier]-SNACK_ICON_SIZE/2.0).round(),SNACK_ICON_SIZE),false)
	var shelf_key:=World.key(draw_cell(at+Vector2(16,16)))
	if focused_label==shelf_key:world_label(at+Vector2(16,-6),"茶屋點心架",shelf_key)

## Cosmetic only: a tiny cup with a thread of tea and steam. Static under reduced motion/photo mode.
func draw_tea_pour_fx(at:Vector2,emote:Dictionary) -> void:
	if emote.get("fx","")!="pour":return
	var still:bool=reduced_motion or photograph_mode
	var t:=0.0 if still else float(Time.get_ticks_msec()-int(emote.get("started",0)))/1000.0
	var cup:=Rect2(at+Vector2(0,10),Vector2(7,5))
	draw_rect(cup,Color("e8d9c0"))
	draw_rect(Rect2(cup.position+Vector2(1,0),Vector2(5,1)),Color("9a6b3c"))
	var drift:=0.0 if still else fmod(t*14.0,9.0)
	for drop in 3:
		var y:=fmod(drift+drop*3.0,9.0)
		draw_rect(Rect2(at+Vector2(3,y-2),Vector2(1,2)),Color("b9854a",0.9-y*0.05))
	if not still:
		var puff:=sin(t*3.0)*1.5
		draw_rect(Rect2(at+Vector2(2+puff,6),Vector2(1,2)),Color(1,1,1,0.45))

func draw_shell_bottle(at:Vector2,item:String) -> void:
	draw_texture_rect(MarketItemArt.icon(item),Rect2(at+Vector2(7,-15),Vector2(18,24)),false)

func draw_wood_table_display(at:Vector2,items:Dictionary) -> void:
	for item:String in items:
		if item in Industry.SHELL_BOTTLES:draw_shell_bottle(at+Vector2(0,3),item)
		elif item in Industry.TABLE_VASE_BLOOMS:draw_table_vase(at+Vector2(0,3),item)
		elif item==Industry.TEA_SET:draw_tea_set(at+Vector2(9,5))
	if focused_label==World.key(draw_cell(at)):world_label(at+Vector2(38,9),"木桌",focused_label,true)

## The tea set icon is a 32x24 (or 32x32) tabletop sprite; draw it at a small fixed size.
func draw_tea_set(at:Vector2,tint:=Color.WHITE) -> void:
	var icon:=MarketItemArt.icon(Industry.TEA_SET)
	if icon!=null:draw_texture_rect(icon,Rect2(at,Vector2(16,12)),false,tint)

func draw_table_vase(at:Vector2,item:String) -> void:
	draw_texture_rect(MarketItemArt.icon(item),Rect2(at+Vector2(0,-18),Vector2(32,32)),false)

func draw_mushroom_table(at:Vector2,items:Dictionary,tint:=Color.WHITE)->void:
	for offset:Vector2 in Industry.MUSHROOM_SEATS:
		draw_texture(MUSHROOM_STOOL_ART,(at+offset*32.0-Vector2(8,9)).round(),tint)
	draw_texture(MUSHROOM_TABLE_ART,at+Vector2(7,12),tint)
	var plates:=[Vector2(19,19),Vector2(33,19),Vector2(19,30),Vector2(33,30)]
	var slot:=0
	for item:String in items:
		var icon:=MarketItemArt.icon(item)
		for portion in mini(int(items[item]),plates.size()-slot):
			if icon:draw_texture_rect(icon,Rect2(at+plates[slot],Vector2(12,12)),false,tint)
			slot+=1

func draw_bamboo_tea_table(at:Vector2,items:Dictionary,vertical:bool,tint:=Color.WHITE,tea_set:=false)->void:
	for offset:Vector2 in Industry.tea_table_seats(vertical):
		draw_texture(BAMBOO_TABLE_CUSHION,(at+offset*32.0-Vector2(9,8)).round(),tint)
	draw_texture(BAMBOO_TABLE_LONG if vertical else BAMBOO_TABLE_WIDE,at+Vector2(2,-4 if vertical else 1),tint)
	# Own flag, so it never takes one of the four meal spots below (they sit on the table's edge row).
	if tea_set:draw_tea_set(at+(Vector2(8,19) if vertical else Vector2(24,15)),tint)
	var spots:=[Vector2(7,8),Vector2(16,8),Vector2(7,33),Vector2(16,33)] if vertical else [Vector2(9,6),Vector2(21,6),Vector2(33,6),Vector2(45,6)]
	var slot:=0
	for item:String in items:
		var icon:=MarketItemArt.icon(item)
		for portion in mini(int(items[item]),spots.size()-slot):
			if icon:draw_texture_rect(icon,Rect2(at+spots[slot],Vector2(12,12)),false,tint)
			slot+=1

func draw_hollow_bed(at:Vector2,key:String)->void:
	var top:=(at+Vector2(0,-15)).round()
	var sleeper:String=occupied_hollow_beds.get(key,"")
	if sleeper.is_empty():
		draw_texture(HOLLOW_BED_ART,top)
	else:
		for section:Rect2 in [Rect2(0,0,17,52),Rect2(17,0,30,52),Rect2(47,0,17,52),Rect2(0,52,64,26)]:
			var edge:=section.size.x==17
			draw_texture_rect_region(HOLLOW_BED_ART,Rect2(top+section.position,section.size),section,Color(1,1,1,0.43) if edge else Color.WHITE)
		if character_art:character_art.draw_sleeping_head(self,top+Vector2(32,29))
	if data.get("objects",{}).has(focused_label) and World.key(World.station_anchor(data.objects,World.cell(focused_label)))==key:
		var title:="起身" if sleeper==player_id else ("有人在休息" if not sleeper.is_empty() else "樹洞小床")
		world_label(at+Vector2(68,35),title,focused_label,true)

## T10 竹編躺椅: lounger art, then (when someone reclines) a plain cotton blanket and the native
## sleeping head so the resting pose reads without a new character sprite. Drawn with the lounger so the
## figure stays under walkers and needs no walking art; the label follows the focused lounger.
func draw_bamboo_lounger(at:Vector2,lounger:Dictionary)->void:
	var vertical:=Industry.is_vertical(lounger)
	var key:=World.key(draw_cell(at))
	var rester:String=occupied_loungers.get(key,"")
	var top:=(at+LOUNGER_AT).round()
	draw_texture(LOUNGER_LONG if vertical else LOUNGER_WIDE,top)
	if not rester.is_empty():
		var head:=LOUNGER_HEAD_LONG if vertical else LOUNGER_HEAD_WIDE
		var blanket:=Rect2(top+Vector2(7,28),Vector2(16,28)) if vertical else Rect2(top+Vector2(30,10),Vector2(26,16))
		draw_rect(blanket,Color("b9cfc7"))
		draw_rect(Rect2(blanket.position,Vector2(blanket.size.x,2)) if vertical else Rect2(blanket.position,Vector2(2,blanket.size.y)),Color("d8e6df"))
		if character_art:character_art.draw_sleeping_head(self,top+head)
	if data.get("objects",{}).has(focused_label) and World.key(World.station_anchor(data.objects,World.cell(focused_label)))==key:
		var title:="起身" if rester==player_id else ("有人在休息" if not rester.is_empty() else "竹編躺椅")
		world_label(at+Vector2(35 if vertical else 67,12),title,focused_label,true)

func draw_arch(at:Vector2,kind:String,color:String,vertical:bool,tint:=Color.WHITE,layer:="all")->void:
	if kind==Industry.FOREST_ARCH:ForestArchArt.draw(self,at,vertical,tint,layer)
	else:VineArchArt.draw(self,at,color,vertical,tint,layer)

const WORKBENCH_WIDE_PATH:="res://assets/ui-life/wood-workbench-wide.png"
const WORKBENCH_TALL_PATH:="res://assets/ui-life/wood-workbench-tall.png"
var _workbench_art:Dictionary={}

## C08: the provided 64x32 / 32x64 worktop texture, or null while it has not been imported yet.
## Loaded lazily and only when the resource exists, so a missing or un-imported file can never
## break the world draw; callers fall back to the existing bench art.
func workbench_texture(vertical:bool) -> Texture2D:
	var path:=WORKBENCH_TALL_PATH if vertical else WORKBENCH_WIDE_PATH
	if not _workbench_art.has(path):
		_workbench_art[path]=load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _workbench_art[path]

func draw_bench_rects(at:Vector2) -> void:
	draw_rect(Rect2(at+Vector2(4,15),Vector2(4,15)),Color("8f6a4c"))
	draw_rect(Rect2(at+Vector2(24,15),Vector2(4,15)),Color("8f6a4c"))
	draw_rect(Rect2(at+Vector2(0,6),Vector2(32,12)),Color("cba16b"))
	draw_rect(Rect2(at+Vector2(5,3),Vector2(11,4)),Color("6b8e85"))
	draw_rect(Rect2(at+Vector2(19,1),Vector2(3,12)),Color("7d6048"))

## C08: the new two-cell 木工台, drawn once from its anchor. Worktop texture when available,
## otherwise the existing bench sprite enlarged to the footprint, otherwise the existing
## programmatic bench drawn on both cells.
func draw_wide_workbench(at:Vector2,vertical:bool,tint:=Color.WHITE) -> void:
	var art:=workbench_texture(vertical)
	if art!=null:
		draw_texture_rect(art,Rect2(at,Vector2(32,64) if vertical else Vector2(64,32)),false,tint)
	elif not FurnitureArt.draw_bench_enlarged(self,at,vertical,tint):
		draw_bench_rects(at)
		draw_bench_rects(at+(Vector2(0,32) if vertical else Vector2(32,0)))

const STONE_WORKBENCH_WIDE_PATH:="res://assets/ui-life/stone-workbench-wide.png"
const STONE_WORKBENCH_TALL_PATH:="res://assets/ui-life/stone-workbench-tall.png"
const STONE_BENCH_TINT:=Color(0.74,0.80,0.86)

## C11: the supplied 64x32 / 32x64 石工台 texture, or null until the file exists/imports. Same lazy,
## never-throwing load as the C08 worktop, sharing its cache.
func stone_workbench_texture(vertical:bool) -> Texture2D:
	var path:=STONE_WORKBENCH_TALL_PATH if vertical else STONE_WORKBENCH_WIDE_PATH
	if not _workbench_art.has(path):
		_workbench_art[path]=load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _workbench_art[path]

func draw_stone_bench_rects(at:Vector2) -> void:
	draw_rect(Rect2(at+Vector2(3,14),Vector2(5,16)),Color("6f7a80"))
	draw_rect(Rect2(at+Vector2(24,14),Vector2(5,16)),Color("6f7a80"))
	draw_rect(Rect2(at+Vector2(0,6),Vector2(32,12)),Color("aab3b6"))
	draw_rect(Rect2(at+Vector2(5,3),Vector2(11,4)),Color("8b9a8c"))
	draw_rect(Rect2(at+Vector2(19,1),Vector2(3,12)),Color("6a5a48"))

## C11: dedicated texture when present; otherwise the existing bench sprite stretched over the
## footprint with a stone tint; otherwise plain stone rectangles on both cells.
func draw_stone_workbench(at:Vector2,vertical:bool,tint:=Color.WHITE) -> void:
	var art:=stone_workbench_texture(vertical)
	if art!=null:
		draw_texture_rect(art,Rect2(at,Vector2(32,64) if vertical else Vector2(64,32)),false,tint)
	elif not FurnitureArt.draw_bench_enlarged(self,at,vertical,tint*STONE_BENCH_TINT):
		draw_stone_bench_rects(at)
		draw_stone_bench_rects(at+(Vector2(0,32) if vertical else Vector2(32,0)))

func object_sprite(at:Vector2,kind:String,object_data:Dictionary={}) -> void:
	if kind==Industry.STONE_WORKBENCH:
		if Industry.square_part(object_data)>0:return
		var stone_vertical:=Industry.is_vertical(object_data)
		draw_stone_workbench(at,stone_vertical,build_tint(str(object_data.get("style",""))))
		var stone_anchor:=draw_cell(at)
		var stone_far:=stone_anchor+(Vector2i.DOWN if stone_vertical else Vector2i.RIGHT)
		if focused_label in [World.key(stone_anchor),World.key(stone_far)]:
			world_label(at+Vector2(16 if stone_vertical else 32,-6),World.BUILD[Industry.STONE_WORKBENCH].name,focused_label)
		return
	if kind==Industry.WORKBENCH and Industry.is_wide_bench(object_data):
		if Industry.square_part(object_data)>0:return
		var bench_vertical:=Industry.is_vertical(object_data)
		draw_wide_workbench(at,bench_vertical,build_tint(str(object_data.get("style",""))))
		var bench_anchor:=draw_cell(at)
		var bench_far:=bench_anchor+(Vector2i.DOWN if bench_vertical else Vector2i.RIGHT)
		if focused_label in [World.key(bench_anchor),World.key(bench_far)]:
			world_label(at+Vector2(16 if bench_vertical else 32,-6),World.BUILD.bench.name,focused_label)
		return
	if kind==Industry.INDIGO_CUSHION:
		# Previews only; the live world draws it in the ground pass, under characters.
		draw_texture(INDIGO_CUSHION_ART,at+INDIGO_CUSHION_AT)
		return
	if kind==Industry.ROUNDED_TABLE:
		var vertical:=Industry.is_vertical(object_data)
		if Industry.square_part(object_data)==0:
			draw_texture(ROUNDED_TABLE_LONG if vertical else ROUNDED_TABLE_WIDE,at+(Vector2(2,-5) if vertical else Vector2(1,-4)))
			var slots:=Industry.rounded_table_slots(object_data.get("items",{}))
			for slot in slots.size():
				var item:String=slots[slot]
				var art:=MarketItemArt.icon(item)
				var center:=at+(Vector2(16,11+slot*27) if vertical else Vector2(17+slot*30,8))
				var side:=26.0 if item in Industry.TABLE_VASE_BLOOMS else 16.0
				var shape:=Vector2(side,side*0.75) if item==Industry.TEA_SET else Vector2.ONE*side
				if art:draw_texture_rect(art,Rect2(center-Vector2(shape.x*0.5,shape.y-6),shape),false)
		var cell_key:=World.key(draw_cell(at))
		if focused_label==cell_key:world_label(at+Vector2(16,-12),"圓角木桌",cell_key)
		return
	if kind==Industry.SHELL_TABLE:
		draw_texture(SHELL_TABLE_ART,at+Vector2(-7,-7))
		var items:Dictionary=object_data.get("items",{})
		if not items.is_empty():
			var item:=str(items.keys()[0])
			if item in Industry.SHELL_BOTTLES:draw_shell_bottle(at,item)
			elif item in Industry.TABLE_VASE_BLOOMS:draw_table_vase(at,item)
			else:
				var icon:=MarketItemArt.icon(item)
				if icon!=null:draw_texture_rect(icon,Rect2(at+Vector2(9,-2),Vector2(14,14)),false)
		if focused_label==World.key(draw_cell(at)):
			var seat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
			world_label(at+Vector2(41,13),"起身" if seat.get("cell")==focused_label else "貝殼圓桌",focused_label,true)
		return
	if kind==Industry.BEACH_CHAIR:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		if object_data.get("beach_chair_folded",false):draw_texture(BEACH_FOLDED,at+Vector2(8,-10))
		else:draw_texture(BEACH_LONG if vertical else BEACH_WIDE,at+Vector2(1,-6))
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			var own_seat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
			var sitting:bool=own_seat.get("cell")==World.key(draw_cell(at))
			world_label(at+Vector2(35 if vertical else 67,12),"起身" if sitting else "折疊沙灘椅",focused_label,true)
		return
	if kind==Industry.BAMBOO_LOUNGER:
		if Industry.square_part(object_data)>0:return
		draw_bamboo_lounger(at,object_data)
		return
	if kind==Industry.RIVERSIDE_SCREEN:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		if Industry.is_folded_screen(object_data):draw_texture(RIVERSIDE_FOLDED,at+(Vector2(7,15) if vertical else Vector2(23,-2)))
		else:draw_texture(RIVERSIDE_LONG if vertical else RIVERSIDE_WIDE,at+(Vector2(1,-14) if vertical else Vector2(1,-16)))
		var anchor:=draw_cell(at)
		if focused_label in [World.key(anchor),World.key(anchor+(Vector2i.DOWN if vertical else Vector2i.RIGHT))]:
			world_label(at+Vector2(16 if vertical else 32,-19),"河岸屏風",focused_label)
		return
	if kind==Industry.MUSHROOM_TABLE:
		if Industry.square_part(object_data)>0:return
		draw_mushroom_table(at,object_data.get("items",{}))
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			world_label(at+Vector2(72,34),"傘帽圓桌",focused_label,true)
		return
	if kind==Industry.BAMBOO_TEA_TABLE:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		draw_bamboo_tea_table(at,object_data.get("items",{}),vertical,Color.WHITE,Industry.has_tea_set(object_data))
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			world_label(at+Vector2(16 if vertical else 32,-17),"低腳竹茶桌",focused_label)
		return
	if kind==Industry.HOLLOW_BED:
		if Industry.square_part(object_data)>0:return
		draw_hollow_bed(at,World.key(draw_cell(at)))
		return
	if kind==Industry.COAST_CART:
		if Industry.square_part(object_data)>0:return
		draw_texture(MARKET_CART_ART,at+Vector2(0,-10))
		var goods:Array=object_data.get("market_cart_goods",[])
		for index in mini(goods.size(),2):
			var icon:=MarketItemArt.icon(str(goods[index]))
			if icon!=null:draw_texture_rect(icon,Rect2(at+Vector2(12+20*index,14),Vector2(13,13)),false)
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			var title:="招牌攤車・營業中" if object_data.get("market_cart_open",false) else "小栗的招牌攤車"
			world_label(at+Vector2(64,33),title,focused_label,true)
		return
	if kind==Industry.COAST_REGISTER:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		draw_texture(REGISTER_LONG if vertical else REGISTER_WIDE,at+Vector2(1,-9))
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			world_label(at+Vector2(16 if vertical else 32,-13),"白木收銀櫃",focused_label)
		return
	if kind==Industry.COAST_AWNING:
		if Industry.square_part(object_data)<=0:
			var vertical:=Industry.is_vertical(object_data)
			CoastAwningArt.draw_shadow(self,at,vertical)
			CoastAwningArt.draw_canopy(self,at,vertical)
		return
	if kind==Industry.IMPERFECT_TEA_PAVILION:
		# Previews only; the live world draws the base and canopy in their own passes.
		if Industry.square_part(object_data)<=0:
			PavilionArt.draw_base(self,at)
			PavilionArt.draw_canopy(self,at)
		return
	if kind==World.OAR_SIGN.KIND:
		draw_texture(OAR_SIGN_ART,at+Vector2(1,-15))
		var rules:=World.OAR_SIGN
		var origin:=draw_cell(at)
		var target:=rules.cell(object_data.get(rules.FIELD))
		if target!=rules.NO_CELL:
			var center:=at+Vector2(16,-4)
			var direction:=Vector2(rules.direction(origin,target)).normalized()
			if direction==Vector2.ZERO:draw_rect(Rect2(center-Vector2.ONE,Vector2(3,3)),Color("fff0cf"))
			else:
				var tip:=(center+direction*5.0).round()
				draw_line((center-direction*5.0).round(),tip,Color("fff0cf"),1.0)
				for sign in [-1,1]:
					var shoulder:=tip-direction*3.0+direction.orthogonal()*float(sign)*3.0
					draw_line(tip,shoulder.round(),Color("fff0cf"),1.0)
		var oar_key:=World.key(origin)
		if focused_label==oar_key:world_label(at+Vector2(33,12),"木槳路標",oar_key,true)
		return
	if kind==World.POSTCARDS.RACK:
		draw_texture(POSTCARD_RACK_ART,at+Vector2(0,-12))
		var postcards:Array=object_data.get(World.POSTCARDS.SLOTS,[])
		for index in postcards.size():
			var art:=TravelCardArt.texture(postcards[index])
			if art==null:continue
			var card_at:=at+Vector2(9,-7+index*9)
			draw_rect(Rect2(card_at-Vector2.ONE,Vector2(16,10)),Color("fff1cc"))
			draw_texture_rect(art,Rect2(card_at,Vector2(14,8)),false)
		return
	if kind==Industry.COAST_FISH_COUNTER:
		if Industry.square_part(object_data)>0:return
		draw_fish_counter(at,object_data)
		return
	if kind==Industry.TEA_DISPLAY_CABINET:
		if Industry.square_part(object_data)>0:return
		draw_tea_cabinet(at,object_data)
		return
	if kind==Industry.NURSERY_BOX:
		if Industry.square_part(object_data)>0:return
		draw_nursery_box(at,object_data)
		return
	if kind==World.ROOF_FIXTURES.HANGING_POT:
		var sway:=0.0 if reduced_motion or photograph_mode else sin(elapsed*2.1+at.x*0.023)*1.6
		draw_hanging_pot(at,sway)
		return
	if kind in Industry.ARCHES:
		var vertical:=Industry.is_vertical(object_data)
		var part:=Industry.square_part(object_data)
		if vertical and part==2:
			var anchor:=draw_cell(at)-Vector2i(0,2)
			var base:Dictionary=data.get("objects",{}).get(World.key(anchor),{})
			draw_arch(at-Vector2(0,64),kind,base.get("vine_color","pink"),true,Color.WHITE,"posts")
		if part>0:return
		if not vertical:draw_arch(at,kind,object_data.get("vine_color","pink"),false,Color.WHITE,"posts")
		if data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at):
			world_label(at+Vector2(16 if vertical else 48,-54),World.BUILD[kind].name,focused_label)
		return
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
	if kind==Industry.CEDAR_BED:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		draw_texture(CEDAR_BED_LONG if vertical else CEDAR_BED_WIDE,at+Vector2(1,-4 if vertical else -10))
		var anchor:=draw_cell(at)
		var part:=anchor+(Vector2i.DOWN if vertical else Vector2i.RIGHT)
		if focused_label in [World.key(anchor),World.key(part)]:
			var own:Dictionary=data.get("players",{}).get(player_id,{})
			var caption:="我的休息處" if own.get(Industry.HOME_REST_FIELD)==World.key(anchor) else "原木小床"
			world_label(at+Vector2(16 if vertical else 32,-17),caption,focused_label)
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
			var bound:=str(object_data.get("collector_animal",""))
			var item:String=World.AnimalCollector.pen_first_item(object_data) if bound==World.AnimalCollector.PEN else World.AnimalCollector.item_for(bound)
			var icon:Texture2D=null if item.is_empty() else preload("res://scripts/inventory_item_art.gd").icon(item)
			if icon:draw_texture_rect(icon,Rect2(at+Vector2(8,-22),Vector2(16,16)),false)
		var tile:=World.key(draw_cell(at))
		if focused_label==tile:world_label(at+Vector2(16,-25),"動物收集器",tile)
		return
	if kind==Industry.GRID_BOOKCASE:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		var art:=GRID_BOOKCASE_TALL if vertical else GRID_BOOKCASE_WIDE
		draw_texture(art,at+Vector2(1,-9))
		var anchor:=draw_cell(at)
		var companion:=anchor+(Vector2i.DOWN if vertical else Vector2i.RIGHT)
		if focused_label in [World.key(anchor),World.key(companion)]:
			world_label(at+Vector2(16 if vertical else 32,-19),"格子書櫃",focused_label)
		return
	if kind in Industry.TWO_CELL_STATIONS and kind!=Industry.TOOL_BOARD:
		if Industry.square_part(object_data)>0:return
		var vertical:=Industry.is_vertical(object_data)
		var art:Texture2D
		if kind==Industry.DYE_TABLE:
			art=preload("res://assets/bakery/dye-table-vertical.png") if vertical else preload("res://assets/bakery/dye-table.png")
		elif kind==Industry.FABRIC_SCREEN:
			art=preload("res://assets/ui-life/inn-fabric-screen-vertical.png") if vertical else preload("res://assets/ui-life/inn-fabric-screen.png")
		elif kind==Industry.LUGGAGE_RACK:
			art=preload("res://assets/ui-life/inn-luggage-rack-vertical.png") if vertical else preload("res://assets/ui-life/inn-luggage-rack.png")
		elif kind==Industry.LEAF_DESK:
			art=LEAF_DESK_TALL if vertical else LEAF_DESK_WIDE
		elif kind==Industry.OBSERVATION_DESK:
			art=preload("res://assets/ui-life/crop-observation-desk-vertical.png") if vertical else preload("res://assets/ui-life/crop-observation-desk.png")
		elif kind==Industry.SEED_CABINET:
			art=preload("res://assets/ui-life/seed-specimen-cabinet-vertical.png") if vertical else preload("res://assets/ui-life/seed-specimen-cabinet.png")
		elif kind==Industry.AQUARIUM:
			art=preload("res://assets/ui-life/small-aquarium-vertical.png") if vertical else preload("res://assets/ui-life/small-aquarium.png")
		elif kind==Industry.GLASS_FLOWER_TABLE:
			art=preload("res://assets/ui-life/glass-flower-table-vertical.png") if vertical else preload("res://assets/ui-life/glass-flower-table.png")
		elif kind==Industry.POT_RACK:
			art=preload("res://assets/ui-life/copper-flower-rack-vertical.png") if vertical else preload("res://assets/ui-life/copper-flower-rack.png")
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
		if kind==Industry.SEED_CABINET:
			var samples:Array=object_data.get(Industry.SEED_SAMPLES,[])
			var trays:=[Vector2(11,18),Vector2(11,29),Vector2(11,40)] if vertical else [Vector2(11,-5),Vector2(43,-5),Vector2(20,4)]
			for index in mini(samples.size(),trays.size()):
				var icon:=MarketItemArt.icon(str(samples[index])+"_seed")
				if icon:draw_texture_rect(icon,Rect2(at+trays[index],Vector2(10,10)),false)
		if kind==Industry.AQUARIUM and object_data.get("items",{}).has(Industry.AQUARIUM_FISH):
			draw_aquarium_fish(at,vertical)
		if kind==Industry.POT_RACK:
			draw_rack_pots(at,vertical,object_data.get("rack_pots",[]))
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
	if kind==World.INDUSTRY.KITCHEN_STOVE:
		# Drawn once from the anchor; the other three cells only carry collision / interaction.
		if int(object_data.get(Industry.KITCHEN_STOVE_PART,0))==0:
			draw_kitchen_stove(at,data.get("objects",{}).get(World.key(draw_cell(at)),{}))
			var stove_key:=World.key(draw_cell(at))
			var focus_in_stove:bool=data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at)
			if focused_label==stove_key or focus_in_stove:
				world_label(at+Vector2(32,-19),World.BUILD[kind].name,focused_label)
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
	if kind in World.RESIDENT_GOALS.INDEPENDENT_TWO_SEATS:
		if not object_data.get("bench_end",false):
			var vertical:bool=object_data.get("bench_vertical",false)
			draw_texture(independent_seat_art(kind,vertical),at+independent_seat_offset(kind,vertical))
		var sofa_key:=World.key(draw_cell(at))
		if sofa_key==focused_label:
			if kind==World.RESIDENT_GOALS.BAMBOO_BENCH:
				var anchor:=World.master_bench_anchor(data.objects,World.cell(sofa_key))
				var vertical:bool=data.objects.get(World.key(anchor),{}).get("bench_vertical",false)
				world_label(screen(Vector2(anchor))+Vector2(16 if vertical else 32,-44),"雙人竹長椅",sofa_key)
			else:world_label(at+Vector2(34,12),"棉布沙發",sofa_key,true)
		return
	if kind==World.RESIDENT_GOALS.STONE_BENCH:
		if not object_data.get("bench_end",false):
			var asset:=preload("res://assets/ui-life/spring-stone-bench-vertical.png") if object_data.get("bench_vertical",false) else preload("res://assets/ui-life/spring-stone-bench.png")
			draw_texture(asset,at+Vector2(0,-10))
		return
	if kind==World.WALL_FIXTURES.LIGHT:
		draw_texture(preload("res://assets/ui-life/warm-lamp-niche.png"),at+Vector2(0,-15))
		return
	if kind==World.WALL_FIXTURES.BARK_FRAME:
		BarkFrameArt.draw(self,at+Vector2(0,-26),object_data.get(World.BARK_FRAME.FIELD,""))
		var frame_key:=World.key(draw_cell(at+Vector2(16,16)))
		if focused_label==frame_key:world_label(at+Vector2(36,-6),"樹皮畫框",frame_key,true)
		return
	if kind==World.WALL_FIXTURES.BAMBOO_CURTAIN:
		# Opacity follows the live roof/cutaway state; previews have no faded roofs and draw fully.
		BambooCurtainArt.draw(self,at,BambooCurtainArt.alpha(roof_faded,draw_cell(at)),Color.WHITE,village_art!=null)
		return
	if kind==World.WALL_FIXTURES.WATER_LISTENING_CHIME:
		var chime_key:=World.key(draw_cell(at+Vector2(16,16)))
		WaterChimeArt.draw(self,at,water_chime_age(chime_key),reduced_motion or photograph_mode)
		if focused_label==chime_key:world_label(at+Vector2(16,-22),"聽水風鈴",chime_key)
		return
	if kind==World.WALL_FIXTURES.LIFEBUOY:
		draw_texture(LIFEBUOY_ART,at+Vector2(4,-30))
		return
	if kind==World.WALL_FIXTURES.HOME_SIGN:
		draw_texture(HOME_SIGN_ART,at+Vector2(0,-24))
		var sign_key:=World.key(draw_cell(at+Vector2(16,16)))
		if focused_label==sign_key:world_label(at+Vector2(16,-26),"讀門牌",sign_key)
		return
	if kind==World.WALL_FIXTURES.TOOL_BOARD:
		if Industry.square_part(object_data)==0:
			draw_texture(TOOL_BOARD_ART,at+Vector2(1,-27))
			var tools:Array=object_data.get(World.WALL_FIXTURES.TOOL_BOARD_FIELD,["",""])
			for side in [0,1]:
				var icon:=ToolActionFeedback.held_icon(tools[side])
				if icon:draw_texture_rect(icon,Rect2(at+Vector2(5+32*side,-28),Vector2(22,22)),false)
		var board_key:=World.key(draw_cell(at))
		if focused_label==board_key:world_label(at+Vector2(16,-30),"工具板",board_key)
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
		if Industry.is_mill_extension(object_data):return
		var facing := Industry.mill_facing(object_data) if Industry.is_new_mill(object_data) else -1
		var entry_visible := false
		if facing>=0:
			var person:Dictionary=data.get("players",{}).get(player_id,{})
			var entry:Vector2i=draw_cell(at)+Industry.mill_entrance_offset(facing)
			entry_visible=not person.is_empty() and Vector2i(floori(person.x),floori(person.y))==entry
		var mill_status:Dictionary=BakeryArt.draw_mill_runtime(self,at,object_data,float(data.get("time",0)),elapsed,reduced_motion,facing,entry_visible)
		var mill_key:=World.key(draw_cell(at))
		var focus_on_mill:bool=facing>=0 and data.get("objects",{}).has(focused_label) and World.station_anchor(data.objects,World.cell(focused_label))==draw_cell(at)
		if focused_label==mill_key or focus_on_mill:
			world_label(at+Vector2(48 if facing>=0 else 16,-26),World.BUILD[kind].name+BakeryArt.MillFeedback.caption(mill_status),focused_label)
		return
	if kind in ["water_tank","water_pump","sawmill","charcoal_kiln"]:
		var device_key:=World.key(draw_cell(at))
		var finish_age:=processing_finish_feedback.age(device_key,object_data,elapsed,reduced_motion or photograph_mode)
		IndustryArt.draw_device(self,at,kind,object_data,float(data.get("time",0)),reduced_motion or photograph_mode,Color.WHITE,elapsed,finish_age)
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
	if kind==Industry.QUIET_BIRDHOUSE:
		draw_texture(BirdhouseArt.HOUSE,at+Vector2(0,-14))
		if data.has("time") and not object_data.get("owner","") in ["blueprint_thumbnail","blueprint_preview"]:
			var pose:=BirdhouseArt.pose(draw_cell(at+Vector2(16,16)),float(data.time),elapsed,reduced_motion or photograph_mode)
			if not pose.is_empty():
				draw_texture(BirdhouseArt.texture(pose.frame),(at+Vector2(pose.offset)).round())
		return
	if kind==Industry.MUSHROOM_POST:
		draw_texture(MUSHROOM_POST_ART,at+Vector2(0,-10))
		var mailbox_key:=World.key(draw_cell(at+Vector2(16,16)))
		if not photograph_mode and object_data.get("owner")==player_id and World.MUSHROOM_MAIL.has_pending(data.get("own_mushroom_mail",{})):
			var icon:=MAIL_ICON.icon("letter")
			if icon!=null:draw_texture_rect(icon,Rect2(at+Vector2(21,-6),Vector2(13,13)),false)
		if focused_label==mailbox_key:world_label(at+Vector2(34,2),"蘑菇門邊郵箱",mailbox_key,true)
		return
	if kind=="wood_mailbox":
		draw_texture(preload("res://assets/ui-inventory/wood-mailbox.png"),at+Vector2(0,-12))
		var mailbox_key:=World.key(draw_cell(at))
		if focused_label==mailbox_key:world_label(at+Vector2(16,-26),World.BUILD[kind].name,mailbox_key)
		return
	if kind in World.RESIDENT_GOALS.WARDROBES:
		match kind:
			World.RESIDENT_GOALS.COAST_WARDROBE:draw_texture(COAST_BOOTH_ART,at+Vector2(1,-16))
			World.RESIDENT_GOALS.FOREST_WARDROBE:draw_texture(FOREST_WARDROBE_ART,at+Vector2(2,-13))
			World.RESIDENT_GOALS.INN_WARDROBE:draw_texture(preload("res://assets/ui-inventory/inn-lattice-wardrobe.png"),at+Vector2(0,-13))
			_:draw_texture(preload("res://assets/ui-inventory/guest-wardrobe.png"),at+Vector2(0,-13))
		var wardrobe_key:=World.key(draw_cell(at))
		if focused_label==wardrobe_key:
			var label_height:=29 if kind==World.RESIDENT_GOALS.COAST_WARDROBE else 26
			world_label(at+Vector2(16,-label_height),World.BUILD[kind].name,wardrobe_key)
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
	if kind=="garden_basin":
		draw_texture(preload("res://assets/ui-life/garden-basin.png"),at)
		return
	if kind==Industry.HEDGEHOG_BASKET:
		draw_texture(HEDGEHOG_BASKET_ART,at)
		if draw_cell(at+Vector2(16,16))==hedgehog_nap_cell:
			var breath:=0.0 if reduced_motion or photograph_mode else roundf(0.5+0.5*sin(elapsed*2.2))
			draw_texture(World.Hedgehog.sleep_texture(),(at+Vector2(7,14-breath)).round())
		return
	if kind==Industry.TEA_SNACK_SHELF:
		draw_tea_snack_shelf(at,object_data)
		return
	if kind==Industry.ACORN_CABINET:
		draw_texture(ACORN_CABINET_ART,at)
		var cabinet_key:=World.key(draw_cell(at+Vector2(16,16)))
		if focused_label==cabinet_key:world_label(at+Vector2(16,-14),"橡果收納櫃",cabinet_key)
		return
	if kind==Industry.SPORE_LAMP:
		draw_texture(SPORE_LAMP_ART,at)
		return
	if kind==World.STAR_GARDEN_LAMP:
		draw_texture(preload("res://assets/ui-life/star-garden-lamp.png"),at)
		return
	if kind==Industry.PAPER_TEA_LAMP:
		var tea_off:bool=object_data.get("lamp_off",false)
		# On/off reuses the existing tint dimming; the sprite itself never animates.
		var tea_tint:=build_tint(str(object_data.get("style","")))
		if tea_off:tea_tint*=Color(0.69,0.67,0.65)
		draw_texture(PAPER_TEA_LAMP_ART,at+PAPER_TEA_LAMP_AT,tea_tint)
		var tea_key:=World.key(draw_cell(at))
		if focused_label==tea_key:world_label(at+Vector2(16,-10),"開燈" if tea_off else "關燈",tea_key)
		return
	if kind==Industry.MUSHROOM_STOOL:
		draw_texture_rect(MUSHROOM_STOOL_ART,Rect2(at+Vector2(4,14),Vector2(24,19)),false)
		var stool_key:=World.key(draw_cell(at))
		if stool_key==focused_label:
			var own_pose:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
			world_label(at+Vector2(31,10),"起身" if own_pose.get("cell")==stool_key else "小菇矮凳",stool_key,true)
		return
	if kind==World.RESIDENT_GOALS.GARDEN_CHAIR:
		draw_texture(preload("res://assets/ui-life/copper-garden-chair.png"),at)
		var chair_key:=World.key(draw_cell(at))
		if chair_key==focused_label:
			var own_pose:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
			world_label(at+Vector2(16,-38),"起身" if own_pose.get("cell")==chair_key else World.BUILD[kind].name,chair_key)
		return
	if kind==Industry.WOOD_CHAIR:
		var dye:String=object_data.get("dye","")
		var pigment:Color={"blue_dye":Color(0.66,0.9,1.35),"orange_dye":Color(1.18,0.79,0.54)}.get(dye,Color.WHITE)
		draw_texture(WOOD_CHAIR_ART,at+Vector2(4,1),build_tint(str(object_data.get("style","")))*pigment)
		var chair_key:=World.key(draw_cell(at))
		if chair_key==focused_label:
			var seat:Dictionary=data.players.get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
			world_label(at+Vector2(35,8),"起身" if seat.get("cell")==chair_key else "坐下",chair_key,true)
		return
	if kind=="lamp":
		var is_off:bool=object_data.get("lamp_off",false)
		var tint:=build_tint(str(object_data.get("style","")))
		if is_off:tint*=Color(0.69,0.67,0.65)
		FurnitureArt.draw_sprite(self,at,kind,tint)
		var lamp_key:=World.key(draw_cell(at))
		if focused_label==lamp_key:world_label(at+Vector2(16,-24),"開燈" if is_off else "關燈",lamp_key)
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
		if FurnitureArt.draw_sprite(self,at,kind,build_tint(str(object_data.get("style","")))*palette):
			if kind=="table":draw_wood_table_display(at,object_data.get("items",{}))
			return
	if village_art:
		var obj:Dictionary=data.objects.get(World.key(draw_cell(at)),{})
		if (kind!="door" or not obj.get("open",false)) and FurnitureArt.draw_sprite(self,at,kind,build_tint(str(obj.get("style","")))):
			if kind=="stove":_draw_cooking_feedback(at,obj)
			if kind=="table":draw_wood_table_display(at,object_data.get("items",{}))
			return
	if village_art and kind in ["long_bench","planter"]:
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
		draw_bench_rects(at)
	elif kind=="bed":
		draw_rect(Rect2(at+Vector2(3,0),Vector2(26,31)),Color("9e7955"))
		draw_rect(Rect2(at+Vector2(5,3),Vector2(22,24)),Color("e7dcae"))
		draw_rect(Rect2(at+Vector2(6,12),Vector2(20,15)),Color("ca8c79"))
		draw_rect(Rect2(at+Vector2(8,5),Vector2(16,7)),Color("fff0cd"))
		Art.pixel(self,at,8,11,16,2,Color("dac29b"))
		Art.pixel(self,at,7,14,18,2,Color("e9b79c"))
		Art.pixel(self,at,7,25,18,2,Color("a76e60"))
		for x in [10,16,22]:Art.pixel(self,at,x,20,2,2,Color("e7b89f"))
	elif kind=="table":
		draw_rect(Rect2(at+Vector2(5,13),Vector2(4,17)),Color("8e6949"))
		draw_rect(Rect2(at+Vector2(23,13),Vector2(4,17)),Color("8e6949"))
		draw_rect(Rect2(at+Vector2(1,2),Vector2(30,19)),Color("b68c5c"))
		draw_rect(Rect2(at+Vector2(3,1),Vector2(26,14)),Color("dfbb83"))
		Art.pixel(self,at,4,3,24,1,Color("efd39d"))
		Art.pixel(self,at,6,7,20,1,Color("c79d6a"))
		Art.pixel(self,at,5,12,22,1,Color("c79d6a"))
		Art.pixel(self,at,7,15,18,2,Color("c79d6a"))
		draw_wood_table_display(at,object_data.get("items",{}))
	elif kind=="stove":
		draw_rect(Rect2(at+Vector2(2,1),Vector2(28,28)),Color("909b91"))
		draw_rect(Rect2(at+Vector2(4,4),Vector2(24,8)),Color("b5bbaa"))
		draw_rect(Rect2(at+Vector2(9,15),Vector2(14,13)),Color("5c625a"))
		draw_rect(Rect2(at+Vector2(7,-3),Vector2(18,8)),Color("636f66"))
		var obj:Dictionary=data.objects.get(World.key(draw_cell(at)),{})
		_draw_cooking_feedback(at,obj)

const KITCHEN_STOVE_ART=preload("res://assets/ui-life/public-kitchen-stove.png")

## The two-by-two stove is drawn once from its anchor, including construction previews.
func draw_kitchen_stove(at:Vector2,obj:Dictionary,tint:=Color.WHITE) -> void:
	draw_texture(KITCHEN_STOVE_ART,at,tint)
	if not obj.is_empty():_draw_cooking_feedback(at,obj,true)

func _draw_cooking_feedback(at:Vector2,obj:Dictionary,large:=false) -> void:
	var status:=CookingFeedback.draw(self,at,obj,float(data.get("time",0)),elapsed,reduced_motion or photograph_mode,large)
	if int(status.ready)>0:
		world_label(at+Vector2(32 if large else 16,-18),"料理好了 · %d 鍋待領"%int(status.ready),World.key(draw_cell(at)))

func draw_player_headwear(foot:Vector2,person:Dictionary,facing:=Vector2i.DOWN) -> void:
	if bool(person.get(World.RESIDENT_GOALS.WOOL_HAT_KEY,false)):MianmianHat.draw(self,foot)
	elif bool(person.get(World.RESIDENT_GOALS.COURIER_CAP_KEY,false)):LuoluoCap.draw(self,foot,facing)

func draw_seated_player(foot:Vector2,person:Dictionary,facing:=Vector2i.DOWN,nod:=0.0) -> void:
	character_art.draw_seated(self,foot,bool(person.get("blue_outfit",false)),"",facing,nod,bool(person.get(World.RESIDENT_GOALS.APRON_KEY,false)))
	var head_offset:=CharacterSprites.FOOT.y-CharacterSprites.SEATED_FOOT.y
	draw_player_headwear(foot+Vector2(0,head_offset+nod),person,facing)

func draw_low_seated_player(foot:Vector2,person:Dictionary) -> void:
	character_art.draw_low_seated(self,foot,bool(person.get("blue_outfit",false)),bool(person.get(World.RESIDENT_GOALS.APRON_KEY,false)))
	draw_player_headwear(foot+Vector2(0,CharacterSprites.FOOT.y-CharacterSprites.LOW_SEATED_FOOT.y),person)

func person_sprite(at:Vector2,shirt:Color,style:="guest",facing:=Vector2i.DOWN,phase:=0.0,walking_now:=false,blue_workwear:=false,milu_apron:=false,cart_push:=0.0,resident_idle:=false) -> void:
	character_label_obstacles.append(LabelLayout.body_rect(at))
	if resident_idle and not walking_now:
		var visitor:=screen(display_positions[player_id]) if display_positions.has(player_id) else Vector2.ZERO
		facing=ResidentIdle.facing(style,facing,at,visitor,display_positions.has(player_id),elapsed,reduced_motion or photograph_mode)
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
	var sign:Dictionary=data.get("own_xiaoli_shop",{})
	if village_art:
		village_art.draw_prop(self,at,8)
		if character_art:
			person_sprite(at+Vector2(16,27),Color("b9a66d"),"xiaoli",Vector2i.DOWN,0.0,false,false,false,0.0,true)
			village_art.draw_shop_occluders(self,at)
		CommunityArt.draw_shop_detail(self,at,data)
		if sign.is_empty():world_label(at+Vector2(16,-39),"小栗・渡口小店" if data.get("picnic",false) else ("小栗・種子攤" if character_art else "種子攤"),"shop")
		else:draw_xiaoli_shop_sign(at+Vector2(16,-54),str(sign.name))
		return
	draw_rect(Rect2(at+Vector2(-8,12),Vector2(48,19)),Color("a57b55"))
	draw_rect(Rect2(at+Vector2(-8,9),Vector2(48,6)),Color("d9b17a"))
	draw_rect(Rect2(at+Vector2(-7,-16),Vector2(3,27)),Color("96734c"))
	draw_rect(Rect2(at+Vector2(34,-16),Vector2(3,27)),Color("96734c"))
	person_sprite(at+Vector2(15,11),Color("8faf8c"))
	draw_rect(Rect2(at+Vector2(-9,-27),Vector2(48,11)),Color("db987d"))
	for j in range(4):draw_rect(Rect2(at+Vector2(-9+j*12,-27),Vector2(6,11)),Color("f2dfb9"))
	draw_rect(Rect2(at+Vector2(-2,6),Vector2(10,7)),Color("e7c47f"))
	if sign.is_empty():world_label(at+Vector2(16,-37),"種子攤","shop")
	else:draw_xiaoli_shop_sign(at+Vector2(16,-48),str(sign.name))

func draw_xiaoli_shop_sign(anchor:Vector2,title:String) -> void:
	const SHOP_ART=preload("res://scripts/xiaoli_shop_art.gd")
	var font_size:=11
	var title_width:=ceilf(font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
	var width:=maxf(53,title_width+16)
	var origin:=(anchor-Vector2(width*0.5,0)).round()
	draw_texture_rect(SHOP_ART.sign_texture(),Rect2(origin,Vector2(width,21)),false)
	draw_string(font,origin+Vector2(8,14),title,HORIZONTAL_ALIGNMENT_CENTER,width-16,font_size,Color("f9efd6"))
	if focused_label=="shop":world_label(anchor+Vector2(0,-5),"小栗","shop")

func draw_rabbit_basket(at:Vector2) -> void:
	var rabbit:Dictionary=data.get("players",{}).get(player_id,{}).get(World.Rabbit.FIELD,{})
	if rabbit.get("following",false):return
	var basket:=preload("res://scripts/salt_revisit_art.gd").empty_basket_texture()
	draw_texture_rect(basket,Rect2(at+Vector2(-12,-16),Vector2(24,21)),false)
	draw_texture(World.Rabbit.texture(elapsed,reduced_motion,not rabbit.is_empty()),at+Vector2(-7,-17))

func draw_cat_home(at:Vector2) -> void:
	var cat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.Cat.FIELD,{})
	if not cat.get("following",false):draw_cat(at.round(),cat,true)
	if focused_label=="companion_cat":world_label(at+Vector2(0,-18),World.Cat.NAME,"companion_cat")

func draw_cat(at:Vector2,cat:Dictionary,own:=false) -> void:
	var age:=float(data.get("time",0))-float(cat.get("last_pet",-30))
	var reacting:=age>=0.0 and age<1.35
	if reacting and cat.get("last_play")=="yarn":
		var travel:=0.0 if reduced_motion else sin(age/1.35*PI)
		var sewn:=MianmianToyArt.choice(data) if own else ""
		if sewn.is_empty():draw_texture(World.Cat.yarn_texture(),(at+Vector2(8+travel*15,-5)).round())
		else:draw_texture(MianmianToyArt.texture(sewn),(at+Vector2(-18+travel*4,-8)).round())
		at.x+=roundf(travel*10)
	draw_texture(World.Cat.texture(reacting and cat.get("last_play")=="pet"),at-Vector2(8,12))

func draw_duck(station:Vector2,record:Dictionary,reaction_age:float) -> void:
	var art=World.LIVESTOCK.Duck
	for offset:Vector2 in [Vector2(1.1,-0.35),Vector2(2.8,0.15),Vector2(1.13,1.75),Vector2(2.85,1.7)]:
		var reeds_at:=screen(Vector2(art.SITE)+offset).round()
		draw_texture(art.reed_texture(),reeds_at-Vector2(5,6))
	var quiet:=reduced_motion or photograph_mode
	var penned:bool=record.get("managed_pen",false)
	var swim:Vector2=art.swim_position(float(data.time),quiet)
	var meal:Dictionary=art.feed_pose(duck_feed_origin,Vector2(art.SITE)+Vector2(0.5,0.9),swim,elapsed-duck_feed_started,penned,quiet)
	var swimming:bool=meal.is_empty() and not penned and reaction_age>=LivestockArt.PET_SECONDS
	var foot:=station
	if not meal.is_empty():
		foot=screen(meal.position).round()
		draw_texture(art.dish_texture(),station+Vector2(5,1))
	elif swimming:
		foot=screen(swim).round()
		draw_rect(Rect2(foot+Vector2(-12,-2),Vector2(8,1)),Color("9ed5cc"))
		draw_rect(Rect2(foot+Vector2(-17,1),Vector2(12,1)),Color("57aec0"))
	else:
		LivestockArt.draw_pet_heart(self,foot,reaction_age,quiet)
	var bird:Texture2D=art.feeding_texture(bool(meal.get("peck",false)),bool(meal.get("flip",false)))
	draw_texture(bird,foot-Vector2(9,9))
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
	if status in ["visiting","visited"] and hedgehog_nap_cell==World.Hedgehog.NO_BASKET:
		var nibble:=status=="visiting" and not reduced_motion and fposmod(elapsed,1.2)>0.8
		draw_texture(World.Hedgehog.texture(nibble),at+Vector2(-22,-7))
	if focused_label==World.Hedgehog.POINT:
		world_label(at+Vector2(0,-18),"刺蝟食盤" if status in ["empty","waiting"] or hedgehog_nap_cell!=World.Hedgehog.NO_BASKET else World.Hedgehog.NAME,World.Hedgehog.POINT)

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
		"dog":
			draw_texture(World.Dog.texture(pet.get("last_play")=="toy"),foot-Vector2(10,12))
			var sewn:=MianmianToyArt.choice(data) if id==player_id and pet.get("last_play")=="toy" else ""
			if not sewn.is_empty():draw_texture(MianmianToyArt.texture(sewn),foot+Vector2(-26,-8))
		"cat":draw_cat(foot,pet,id==player_id)
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

const INTERACTIVE_OBJECTS:=[World.WALL_FIXTURES.BARK_FRAME,World.WALL_FIXTURES.HOME_SIGN,World.WALL_FIXTURES.TOOL_BOARD,"chest","private_chest","supply_box",Industry.ACORN_CABINET,Industry.TEA_SNACK_SHELF,"bench","bed",Industry.CEDAR_BED,"inn_quilt_bed","inn_stone_footbath","door","stove","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_pump","sawmill","charcoal_kiln","forester","conveyor","waterworks","mine_drill","mill","seed_maker","loom","glass_furnace","small_smelter",Industry.KITCHEN_STOVE,"clay_kiln","dye_table","assembly_table","animal_collector","sketch_easel","guest_wardrobe","inn_lattice_wardrobe",World.RESIDENT_GOALS.COAST_WARDROBE,World.RESIDENT_GOALS.FOREST_WARDROBE,"wood_mailbox",Industry.MUSHROOM_POST,"rope_rack",World.POSTCARDS.RACK,World.OAR_SIGN.KIND,"fish_display","author_sign","author_shelf","expedition_tent","diversion_gate","water_tower","water_share_plaque","mine_lantern","tea_ware","salt_basket","long_bench","master_bench","spring_stone_bench",World.RESIDENT_GOALS.COTTON_SOFA,World.RESIDENT_GOALS.BAMBOO_BENCH,"sign","festival_memorial_bell","keepsake_lingpopo_memorial","ceramic_eave_chime","shell_chime","inn_welcome_sign","inn_tea_table","inn_luggage_rack","crop_observation_desk",Industry.LEAF_DESK,World.RESIDENT_GOALS.GARDEN_CHAIR,Industry.MUSHROOM_STOOL,Industry.WOOD_CHAIR,Industry.INDIGO_CUSHION,Industry.SEED_CABINET,Industry.AQUARIUM,Industry.VINE_ARCH,Industry.POT_RACK,Industry.NURSERY_BOX,Industry.COAST_FISH_COUNTER,Industry.COAST_REGISTER,Industry.COAST_CART,Industry.HOLLOW_BED,Industry.MUSHROOM_TABLE,Industry.BAMBOO_TEA_TABLE,Industry.TEA_DISPLAY_CABINET,Industry.BEACH_CHAIR,Industry.RIVERSIDE_SCREEN,Industry.BAMBOO_LOUNGER,Industry.SHELL_TABLE,Industry.ROUNDED_TABLE,Industry.GRID_BOOKCASE,"table",Industry.STONE_WORKBENCH]

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
	var own_seat:Dictionary=data.get("players",{}).get(player_id,{}).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
	var seat_key:String=own_seat.get("cell","")
	if data.get("objects",{}).get(seat_key,{}).get("type")==Industry.INDIGO_CUSHION:return seat_key
	if LeafMatArt.own_mat_cell(data,player_id).x>=0:return "leaf_mat"
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
		var house:=World.TEA_HOUSE_INTERIOR
		var house_points:Dictionary={}
		var inside_house:bool=region_id()==house.REGION and house.inside(visitor)
		if region_id()==house.REGION:house.points(data,visitor,house_points)
		var pottery:=World.POTTERY_WORKSHOP_INTERIOR
		var pottery_points:Dictionary={}
		var inside_pottery:bool=pottery_inside()
		if region_id()==pottery.REGION:pottery.points(visitor,pottery_points)
		for gate in World.TRANSIT.points(region_id()):
			if inside_house or inside_pottery:break
			var stop:Dictionary=World.TRANSIT.points(region_id())[gate]
			var distance:=position.distance_to(Vector2(stop.cell)+Vector2(0.5,0.5))
			if distance<=radius:
				radius=distance
				closest="transit:"+str(gate)
		var tea_sites:Dictionary={} if inside_house or inside_pottery else tea_points(region_id(),data)
		for cell:Vector2i in tea_sites:
			var distance:=position.distance_to(Vector2(cell)+Vector2(0.5,0.5))
			if distance<radius:
				radius=distance
				closest="tea:"+tea_sites[cell]
		for house_point:String in house_points:
			var distance:=position.distance_to(house_points[house_point])
			if distance<radius:
				radius=distance
				closest=house_point
		# Workshop door and indoor stations; the door only counts within its own reach (same as the action).
		for pottery_point:String in pottery_points:
			var distance:=position.distance_to(pottery_points[pottery_point])
			if pottery_point==pottery.PORTAL and distance>pottery.REACH:continue
			if distance<radius:
				radius=distance
				closest=pottery_point
		var resident:Dictionary=World.STATION_LIFE.RESIDENTS.get(region_id(),{})
		if not inside_house and not inside_pottery:
			if not resident.is_empty():
				var distance:=position.distance_to(Vector2(resident.cell)+Vector2(0.5,0.5))
				if distance<=radius:
					radius=distance
					closest="station_resident:"+region_id()
			var crops:=World.crop_detail_points(data,player_id,position,region_id())
			for point:String in crops:
				var distance:=position.distance_to(crops[point])
				if distance<radius:
					radius=distance
					closest=point
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
	if home and data.get(World.MILL_RESTORATION.SITE_VISIBLE,false):
		points[World.MILL_RESTORATION.POINT]=Vector2(World.MILL_RESTORATION.DOOR)+Vector2(0.5,0.5)
	points.merge(PartyCartArt.points(data))
	points.merge(StrollArt.points(data))
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
		points[OreRouteArt.POINT]=Vector2(OreRouteSelect.cart_point_cell(data))+Vector2(0.5,0.5)
	if depth>0:
		var survey_point:Vector2i=World.MINE_SURVEY.POINTS[depth]
		if not data.objects.has(World.key(survey_point)) and not ShyUI.spores_moving(data) and not GuardianUI.trial_active(data):
			points["mine_survey"]=Vector2(survey_point)+Vector2(0.5,0.5)
		var stations:Dictionary={"up":World.MINES.UP,"down":World.MINES.DOWN,"rest":World.MINES.REST,"service":World.MINES.SERVICE}
		for station in stations:
			if station!="down" or depth<World.MINES.MAX_DEPTH:points["mine_site:"+station]=Vector2(stations[station])+Vector2(0.5,0.5)
		if depth>World.MINES.SHALLOW_DEPTH:points["mine_site:lift"]=Vector2(World.MINES.LIFT)+Vector2(0.5,0.5)
		var mud_phase:=int(data.players.get(player_id,{}).get("mud_alcove",0))
		if depth==1 and mud_phase<2:
			var mud_cell:=World.MINES.MUD_GATE if mud_phase==0 else World.MINES.MUD_REWARD
			points["mine_mud"]=Vector2(mud_cell)+Vector2(0.5,0.5)
		points.merge(GuardianUI.points(data,data.players.get(player_id,{}),region_id(),int(data.get("mine_depths",{}).get("unlocked",1))))
		points.merge(ShyUI.points(data,data.players.get(player_id,{}),region_id(),int(data.get("mine_depths",{}).get("unlocked",1))))
		points.merge(World.PORTER.interaction_points(data,data.players.get(player_id,{})))
		points.merge(World.MEADOW_ADVENTURE.interaction_points(data,data.players.get(player_id,{})))
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
	var forest_tree:=World.forest_mushroom_tree(data,pos)
	if forest_tree!=World.FOREST_MUSHROOM.NO_TREE:
		points[World.FOREST_MUSHROOM.SURVEY_POINT]=Vector2(forest_tree)+Vector2(0.5,0.5)
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
	if home:points.merge(BeachTreasureArt.points(data))
	if home and data.get("wangan_star_walk",false):
		points[World.WANGAN_COAST.STAR_SAND_POINT]=Vector2(World.WANGAN_COAST.STAR_SAND)+Vector2(0.5,0.5)
		points[World.WANGAN_COAST.DOCK_ORDERS_POINT]=Vector2(World.WANGAN_COAST.DOCK_ORDERS)+Vector2(0.5,0.5)
		points[World.WANGAN_COAST.SALT_PARCEL_POINT]=Vector2(World.WANGAN_COAST.SALT_PARCEL)+Vector2(0.5,0.5)
	elif home:points[World.WANGAN_COAST.STAR_REPAIR_POINT]=Vector2(World.WANGAN_COAST.STAR_REPAIR)+Vector2(0.5,0.5)
	for walk_id:String in World.RESIDENT_BOND.WALK_UP:
		var walk_spot:Array=World.bond_place(data,walk_id)
		if str(walk_spot[0])==region_id() and World.RESIDENT_BOND.present(data,walk_id):points[walk_id]=Vector2(walk_spot[1])+Vector2(0.5,0.5)
	if region_id()==World.WARM_SPRINGS.REGION:
		points[World.WARM_SPRINGS.BATH_ACTION]=Vector2(World.WARM_SPRINGS.BATH_ENTRANCE)+Vector2(0.5,0.5)
		points[World.WARM_SPRINGS.INN_POINT]=Vector2(World.WARM_SPRINGS.INN_DOOR)+Vector2(0.5,0.5)
		World.WARM_SPRINGS.crack_interactions(data,points,pos)
		if World.WARM_SPRINGS.in_inn(data.players.get(player_id,{})):World.WARM_SPRINGS.room_interactions(points)
		World.WARM_SPRINGS.rest_interactions(data,points,pos,player_id)
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
	# T064 公用耕田機的農機架，緊接在紀念品交換攤之後（與 main.gd 相同）。
	if home:points.merge(PublicTillerUI.points(data))
	# 第 40 章地方記憶展，緊接在紀念品交換攤之後（與 main.gd 相同）。
	if home and MemoryExhibitUI.stand_shown(data):points[MemoryExhibitUI.POINT]=Vector2(MemoryExhibitUI.stand_cell(data))+Vector2(0.5,0.5)
	# 春日花園日：未蓋章的三個花站，緊接在地方記憶展之後（與 main.gd 相同）。
	if home:points.merge(SpringGardenArt.points(data))
	# 暖燈夜：three lantern stations (lighting / celebrated only); main.gd must keep this order.
	if home:points.merge(WarmLanternArt.points(data))
	if home:points.merge(CookingRelayArt.points(data))
	if home:points.merge(LostChicksArt.points(data))
	for key in data.objects:
		var object:Dictionary=data.objects[key]
		if object.type in INTERACTIVE_OBJECTS or (object.type in Industry.SWITCHABLE_LAMPS and object.get("owner")==player_id):
			points[key]=Vector2(World.cell(key))+Vector2(0.5,0.5)
	if home:points["quarry"]=Vector2(54.5,25.5)
	if home:points["copper"]=Vector2(World.COPPER_CELL)+Vector2(0.5,0.5)
	points.merge(World.crop_detail_points(data,player_id,pos,region_id()))
	if home:points.merge(World.edge_door_points(data,pos))
	var closest:=""
	var distance:=3.2
	for key in points:
		var candidate:=pos.distance_to(points[key])
		if candidate<distance:
			distance=candidate
			closest=key
	var found:String=OreRouteSelect.preferred_interaction(data,pos,closest,points) if mining else closest
	# T12: same fallback as main._interact; the open pavilion never hides another point.
	return found if not found.is_empty() else World.PAVILION.focus(data.objects,pos)

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
	var display:Dictionary=data.get("market_plaza",{})
	if not display.is_empty():
		MarketDecorArt.draw(self,rect.position,display.style,alpha)
	elif data.get("picnic",false) and not own_market_cart_open and own.has("decor"):
		MarketDecorArt.draw(self,rect.position,own.decor,alpha)
	if region_id()=="home":
		SeaBreezeFairArt.draw(self,rect.position,data.get("own_sea_breeze_fair",{}),elapsed,reduced_motion or photograph_mode,alpha)
	# T071 攤位布置：本人擺上攤位的每種貨在櫃檯檯面擺一張小牌子（今日主題的牌子外框是橘色）。
	for tag:Dictionary in market_shelf_tags(cell):
		var box:Rect2=tag.rect
		draw_rect(box,Color(0.90,0.50,0.16,alpha) if tag.themed else Color(0.22,0.18,0.14,alpha))
		draw_rect(box.grow(-1),Color(1.0,0.95,0.82,alpha))
		var goods:=MarketItemArt.icon(str(tag.item))
		if goods:draw_texture_rect(goods,box.grow(-1),false,Color(1,1,1,alpha))
	var title:="市集攤位" if display.is_empty() else "%s的攤位"%display.name
	var summer:Dictionary=data.get("own_summer_market",{})
	var fair_running:=SeaBreezeFairArt.shows(data.get("own_sea_breeze_fair",{}))
	if fair_running:title="市集攤位・海風試吃"
	if summer.get("in_season",false):
		if not fair_running:title+="・夏季試吃"
		var sign:=Rect2(rect.position+Vector2(3,7),Vector2(16,18))
		draw_rect(sign.grow(1),Color(0.22,0.18,0.14,alpha))
		draw_rect(sign,Color(0.98,0.85,0.53,alpha))
		var skewer:=MarketItemArt.icon("rainbow_skewer")
		if skewer:draw_texture_rect(skewer,sign.grow(-1),false,Color(1,1,1,alpha))
	if (display.is_empty() or display.vendor==player_id) and int(own.get("till",0))>0:
		title+="・可領營收"
		var coin:=MarketItemArt.icon("coins")
		if coin:draw_texture_rect(coin,Rect2(rect.position+Vector2(rect.size.x-18,2),Vector2(16,16)),false,Color(1,1,1,alpha))
	elif display.is_empty() and bool(own.get("open",false)) and not own_market_cart_open:title+="・營業中"
	world_label(at+Vector2(16,-36),title,"market")

## Market sign art uses the visible vendor's product kinds. The store menu
## and a vendor's own signs still use their private stock counts.
func market_shelf_tags(cell:Vector2i) -> Array:
	var own:Variant=data.get("own_market",{})
	if not own is Dictionary or cell==MarketStall.NO_CELL:return []
	var display:Dictionary=data.get("market_plaza",{})
	if not display.is_empty() and str(display.vendor)!=player_id:
		var visible_goods:Dictionary={}
		for item:String in display.goods:visible_goods[item]=1
		own={"unlocked":true,"theme":MarketStall.theme_of(MarketStall.day(float(data.time))),"stock":visible_goods}
	elif own_market_cart_open:return []
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
	var plaza:=MarketStall.active_cell(data)
	var own:Variant=data.get("own_market",{})
	if not own is Dictionary:return []
	var stops:Array[Vector2i]=active_market_carts.duplicate()
	if plaza!=MarketStall.NO_CELL and int(own.get("stalls_today",0))>stops.size():stops.push_front(plaza)
	if stops.is_empty():return []
	var result:=[]
	var cart_spots:=[Vector2(-0.4,2.1),Vector2(2.5,2.1),Vector2(0.9,2.7)]
	var planned:=MarketVisitors.plan(own,float(data.get("time",0.0)))
	for index in planned.size():
		var destination:Vector2i=stops[index%stops.size()]
		var guest:Dictionary=planned[index]
		var entry:=guest.duplicate()
		var offset:Vector2=guest.offset if destination==plaza else cart_spots[int(guest.slot)]
		entry["position"]=Vector2(destination)+offset
		if destination!=plaza:
			var tile:=Vector2i(entry.position.floor())
			var river:bool=tile.x in [55,56] and not (World.STONE_WORKSHOP.bridge_open(data) and tile.y in [29,30,31])
			if not World.land(tile) or river or World.WANGAN_COAST.STAR_POOL.has_point(tile) or data.objects.has(World.key(tile)):continue
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

func active_emote(actor:String)->Dictionary:
	var emote:Dictionary=player_emotes.get(actor,{})
	return emote if int(emote.get("until",0))>Time.get_ticks_msec() and emote.get("region")==region_id() else {}

func _draw_guardian_strike(run:Dictionary)->void:
	var trial:=World.GUARDIAN_TRIAL
	var bounds:Array=run.bounds
	var danger:=Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2]),float(bounds[3])).grow(trial.FOOT_MARGIN).intersection(trial.ARENA)
	var impact:bool=run.phase==trial.Phase.IMPACT
	var ink:=Color("#f7bb85") if not impact else Color("#ffe3a4")
	for y in range(floori(danger.position.y),ceili(danger.end.y)):
		for x in range(floori(danger.position.x),ceili(danger.end.x)):
			var tile:=Vector2i(x,y)
			if not World.land(tile,Guardian.REGION):continue
			var part:=danger.intersection(Rect2(Vector2(tile),Vector2.ONE))
			var px:=Rect2(screen(part.position).round(),(part.size*TILE).round())
			draw_rect(px,Color(ink,0.42 if impact else 0.24))
			var mark:=px.get_center().round()
			if px.size.x>=9.0 and px.size.y>=9.0:
				var span:=Vector2(4,-4) if int(run.attack)==0 else Vector2(4,4)
				draw_line(mark-span,mark+span,ink,2.0)
			if is_equal_approx(part.position.x,danger.position.x):draw_line(px.position,Vector2(px.position.x,px.end.y),ink,2.0)
			if is_equal_approx(part.end.x,danger.end.x):draw_line(Vector2(px.end.x,px.position.y),px.end,ink,2.0)
			if is_equal_approx(part.position.y,danger.position.y):draw_line(px.position,Vector2(px.end.x,px.position.y),ink,2.0)
			if is_equal_approx(part.end.y,danger.end.y):draw_line(Vector2(px.position.x,px.end.y),px.end,ink,2.0)

func _draw_meadow_ring(radius:float,edge:Color,fill_alpha:float)->void:
	var center:=screen(World.MEADOW.FACE)
	var outline:=PackedVector2Array()
	for index in 32:
		outline.append((center+Vector2.from_angle(TAU*float(index)/32.0)*radius).round())
	if fill_alpha>0.0:draw_colored_polygon(outline,Color(edge,fill_alpha))
	outline.append(outline[0])
	draw_polyline(outline,Color("#513028",edge.a),5.0)
	draw_polyline(outline,edge,2.0)

func world_label(anchor:Vector2,title:String,id:String,side:=false,fixed_position:=false) -> void:
	if photograph_mode:return
	world_labels.append({"anchor":anchor.round(),"title":title,"id":id,"side":side,"fixed_position":fixed_position})

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
## plus a harvested-crop icon travelling from soil to basket (fixed with reduced motion).
func draw_tool_target(tool_plan:Dictionary,foot:Vector2) -> void:
	var record:Dictionary=tool_plan.record
	var cell:Vector2i=record.to if record.tool=="move_object" else record.cell
	var cell_at:=screen(Vector2(cell))
	var impact:=ToolActionFeedback.soil_impact(record.tool,tool_plan.progress,tool_plan.reduced)
	if record.tool=="seed":
		for contact in ToolActionFeedback.seed_contacts(tool_plan.progress,tool_plan.reduced):
			var center:Vector2=cell_at+contact.center
			for side in [-1.0,1.0]:
				draw_rect(Rect2(center+Vector2(side*contact.spread,-contact.lift),Vector2(2,1)),contact.color)
	elif not impact.is_empty():
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
			var center:=ToolActionFeedback.harvest_center(cell_at,foot,tool_plan,tool_plan.progress)
			draw_texture_rect(crop_icon,Rect2((center-Vector2.ONE*size/2.0).round(),Vector2.ONE*size),false,Color(1,1,1,tool_plan.alpha))
	if record.tool=="move_object":
		draw_rect(Rect2(cell_at+Vector2(3,3),Vector2(26,26)),Color(1,0.96,0.78,0.6),false,1.0)
	for particle:Dictionary in tool_plan.particles:
		draw_rect(Rect2(cell_at+particle.pos,particle.size),particle.color)
		tool_draw_stats.particles+=1

func draw_gather_pickups()->void:
	if photograph_mode:return
	var now:=float(data.get("time",0.0))+interpolation_clock
	var bounds:=Rect2(Vector2.ZERO,get_viewport_rect().size).grow(30)
	var own_position:Vector2=display_positions.get(player_id,Vector2.INF)
	for tile:String in data.get("gather_drops",{}):
		var cell:=World.cell(tile)
		var center:=screen(Vector2(cell))+Vector2(16,24)
		if not bounds.has_point(center):continue
		var drop:Dictionary=data.gather_drops[tile]
		var items:Array=drop.items.keys()
		var seconds_left:=ceili(float(drop.get("public_at",0.0))-now)
		if seconds_left>0 and now>=float(drop.ready_at) and own_position.distance_squared_to(Vector2(cell)+Vector2(0.5,0.5))<=4.0:
			world_label(center+Vector2(0,-30),"保留中 · %d 秒"%seconds_left,"gather-reservation:"+tile)
		var phase:=clampf(1.0-(float(drop.ready_at)-now)/World.GATHER_DROP_DELAY,0.0,1.0)
		for index in items.size():
			var offset:=gather_icon_offset(index,items.size())
			var height:=0.0 if reduced_motion else sin(phase*PI)*16.0+8.0*(1.0-phase)
			var amount:=int(drop.items[items[index]]) if phase>=1.0 else 0
			draw_gather_icon(items[index],center+offset*(0.4+phase*0.6),height,1.0,amount,items.size()>1)
	for record:Dictionary in tool_feedback.pickups.values():
		if not display_positions.has(record.actor):continue
		var cell_at:=screen(Vector2(record.cell))+Vector2(16,24)
		var collector:=screen(display_positions[record.actor])+Vector2(0,-7)
		var items:Array=record.items
		for index in items.size():
			var origin:=cell_at+gather_icon_offset(index,items.size())
			var age:=elapsed-float(record.started)-index*0.025
			if record.get("collected",false):
				if reduced_motion or age<0.0 or age>=0.32:continue
				var pull:=smoothstep(0.0,0.32,age)
				draw_gather_icon(items[index],origin.lerp(collector,pull),sin(pull*PI)*10.0,1.0-pull*pull)
			else:
				var pose:=ToolActionFeedback.pickup_pose(age,origin,collector,reduced_motion)
				if not pose.is_empty():draw_gather_icon(items[index],pose.position,pose.height,pose.alpha)

func gather_icon_offset(index:int,count:int) -> Vector2:
	var row:=floori(index/3.0)
	var row_size:=mini(3,count-row*3)
	var rows:=ceili(count/3.0)
	return Vector2((index%3-(row_size-1)*0.5)*27,(row-(rows-1)*0.5)*28)

func draw_gather_icon(item:String,at:Vector2,height:float,alpha:float,amount:=0,mixed:=false) -> void:
	var icon:=MarketItemArt.icon(item)
	if icon==null:return
	draw_rect(Rect2((at-Vector2(6,1)).round(),Vector2(12,4)),Color(0.09,0.14,0.09,alpha*0.40))
	var center:=(at-Vector2(0,8+height)).round()
	draw_texture_rect(icon,Rect2(center-Vector2(11,11),Vector2(22,22)),false,Color(1,1,1,alpha))
	if amount>1 or (mixed and amount>0):
		var label:="×%d"%amount
		var zoom:=view_zoom()
		var font_size:=maxi(10,roundi(10.0*label_text_scale*zoom))
		var label_width:=ceilf(font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
		var chip_width:=label_width+4*zoom
		var corner:=((center+Vector2(8,4))*zoom).round()
		if mixed:corner=(center*zoom+Vector2(-chip_width*0.5,7*zoom)).round()
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(corner,Vector2(chip_width,ceilf(font.get_height(font_size))+2*zoom)),Color("3d3025"))
		draw_string(font,corner+Vector2(2*zoom,zoom+font.get_ascent(font_size)),label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff6de"))
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*zoom)

func compact_farm_prompt() -> bool:
	return (show_target and (hand_farm_wide or selected in ["till_area","seed_area","harvest_area"])) or not farm_feedback.active(player_id,elapsed).is_empty()

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
			if Industry.is_stove(str(data.get("objects",{}).get(entry.id,{}).get("type",""))):
				obstacles=placed.duplicate()
				obstacles.append(CookingFeedback.display_bounds(screen(Vector2(World.cell(entry.id))).round()))
			elif data.get("objects",{}).get(entry.id,{}).get("type","")==World.OAR_SIGN.KIND:
				obstacles=placed.duplicate()
				var top:=screen(Vector2(World.cell(entry.id))).round()+Vector2(1,-15)
				obstacles.append(Rect2(top,OAR_SIGN_ART.get_size()))
			elif entry.id==PublicTillerUI.POINT:
				# Keep the rack art visible: the prompt steps off it.
				obstacles=placed.duplicate()
				var rack:=PublicTillerUI.points(data)
				if rack.has(PublicTillerUI.POINT):
					obstacles.append(PublicTillerUI.rack_rect(screen(Vector2(rack[PublicTillerUI.POINT]-Vector2(0.5,0.5))).round()))
			elif entry.id==MemoryExhibitUI.POINT and SouvenirUI.booth_shown(data):
				obstacles=placed.duplicate()
				obstacles.append(SouvenirUI.booth_rect(self,SouvenirUI.booth_cell(data)))
			elif entry.id=="salt:heritage":
				obstacles=placed.duplicate()
				obstacles.append(SaltWorldArt.heritage_sign_rect(screen(Vector2.ZERO)))
			elif entry.id.begins_with(GuardianUI.POINT):
				# Keep the statue and all three bell stands visible: the prompt steps off them.
				obstacles=placed.duplicate()
				obstacles.append(GuardianArt.sprite_rect(screen(Vector2(Guardian.GUARDIAN)).round()+Vector2(16,30)))
				for stand in Guardian.BELLS.size():
					obstacles.append(GuardianArt.bell_bounds(screen(Vector2(Guardian.BELLS[stand])).round()+Vector2(16,30),stand==guardian_lit_bell))
			elif entry.id==ShyUI.POINT:
				# Keep the mushroom, its ring and the ready marker visible: the prompt steps off them.
				obstacles=placed.duplicate()
				obstacles.append(ShyArt.ring_rect(screen(Vector2(Shy.MUSHROOM)).round()+ShyUI.FOOT_OFFSET))
			elif entry.id==ShowcaseUI.POINT:
				obstacles=placed.duplicate()
				for tile in ShowcaseUI.pieces(data):
					obstacles.append(Rect2(screen(Vector2(World.cell(str(tile)))),Vector2(32,32)))
			elif entry.id.begins_with(WarmLanternArt.POINT_PREFIX):
				# Keep the lantern itself visible: the prompt steps off the statue.
				obstacles=placed.duplicate()
				var lantern:Dictionary=WarmLanternArt.stations().get(entry.id.get_slice(":",1),{})
				if not lantern.is_empty():obstacles.append(WarmLanternArt.lamp_rect(screen(Vector2(lantern.cell))))
			elif entry.id==BeachTreasureArt.SIGN_POINT or entry.id.begins_with(BeachTreasureArt.POINT_PREFIX):
				# Keep the sign / sand patch art visible: the label steps off it.
				obstacles=placed.duplicate()
				obstacles.append(BeachTreasureArt.art_rect(screen(Vector2.ZERO),entry.id))
			elif entry.id.begins_with(SpringGardenArt.POINT_PREFIX):
				obstacles=placed.duplicate()
				var station:=SpringGardenArt.cell_of(entry.id.get_slice(":",1))
				obstacles.append(Rect2(screen(Vector2(station)),Vector2(32,32)))
			elif entry.id.begins_with(WarmLanternArt.POINT_PREFIX):
				obstacles=placed.duplicate()
				var lantern:Vector2i=World.WARM_LANTERN_NIGHT.STATIONS[entry.id.get_slice(":",1)].cell
				obstacles.append(WarmLanternArt.lamp_rect(screen(Vector2(lantern))))
			var keep_centered:bool=entry.id in ["harvest:sign",ShowcaseUI.POINT,MemoryExhibitUI.POINT]
			if active and data.get("objects",{}).get(entry.id,{}).get("type","")=="mill":keep_centered=true
			if not active and (entry.id=="" or World.Village.NPCS.has(entry.id)):keep_centered=true
			if not active and (not viewport.has_point(anchor) or not viewport.intersects(box)):continue
			if not active and hidden_under_card(box):continue
			if active:
				# The focused prompt steps around the local body, its name tag and HUD,
				# staying as close to its target as possible and never being dropped.
				box=LabelLayout.place(box,anchor,obstacles,area,keep_centered).rect
			elif entry.get("fixed_position",false):box=LabelLayout.clamp_into(box,area)
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
	var objects:Dictionary=data.get("objects",{})
	var focused_object:Dictionary=objects.get(focused_label,{})
	if focused_object.get("type","")=="mill":
		# Interaction can focus an extension tile of the village mill.
		var anchor:=World.station_anchor(objects,World.cell(focused_label))
		var facing:=Industry.mill_facing(focused_object) if Industry.is_new_mill(focused_object) else -1
		list.append(BakeryArt.mill_label_bounds(screen(Vector2(anchor)).round(),facing))
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
