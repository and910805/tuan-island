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
const ForestryArt=preload("res://scripts/forestry_art.gd")
const LogisticsArt=preload("res://scripts/logistics_art.gd")
const TillerArt=preload("res://scripts/tiller_art.gd")
const SeederArt=preload("res://scripts/seeder_art.gd")
const HarvesterArt=preload("res://scripts/harvester_art.gd")
const FarmFeedback=preload("res://scripts/farm_feedback.gd")
const ToolActionFeedback=preload("res://scripts/tool_action_feedback.gd")
const FishingFeedback=preload("res://scripts/fishing_feedback.gd")
const FishingArt=preload("res://scripts/fishing_art.gd")
const BakeryArt=preload("res://scripts/bakery_art.gd")
const FEEDBACK_ICONS:={"radish":3,"lettuce":4,"wheat":5,"radish_seed":6,"lettuce_seed":7,"wheat_seed":8,
	"carrot":18,"potato":19,"tomato":20,"carrot_seed":21,"potato_seed":22,"tomato_seed":23}
const MACHINES:={"tiller":["till_area","last_till"],"seeder":["seed_area","last_seed"],"harvester":["harvest_area","last_harvest"]}
const World=preload("res://scripts/world.gd")
const TILE:=32.0
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
var village_art:RefCounted
var character_art:RefCounted
var crop_art:RefCounted
const STEP_LENGTH:=0.58
var data:Dictionary={}
var player_id:=""
var camera:=Vector2.ZERO
var target:=Vector2i.ZERO
var show_target:=false
var selected:="hoe"
var building:="floor"
var area_drag:=false
var area_start:=Vector2i.ZERO
var font:FontVariation
var elapsed:=0.0
var reduced_motion:=true
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

func update_snapshot(snapshot:Dictionary,id:String) -> void:
	var changed_region:=region_id()!=str(snapshot.get("region_id","home"))
	if changed_region:
		livestock_pet_feedback.clear()
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
		if snapshot.get("players",{}).has(id):
			var person:Dictionary=snapshot.players[id]
			var anchor:=get_viewport_rect().size*0.5+Vector2(0,40) if village_art_preview else Vector2(740,460)
			var scale_value:=1.0 if str(snapshot.get("region_id","")).begins_with("mine_") else zoom
			camera=(Vector2(person.x,person.y)*TILE-anchor/scale_value).round()
	elif region_id().begins_with("mine_"):
		var previous:Dictionary=data.get("mine_depths",{}).get("ready",{}).get(region_id(),{})
		var latest:Dictionary=snapshot.get("mine_depths",{}).get("ready",{}).get(region_id(),{})
		for cell in latest:
			if float(latest[cell])>float(previous.get(cell,0)):mine_feedback[cell]=elapsed
		var previous_freight:String=data.get("mine_freight",{}).get("own_job",{}).get("status","")
		var latest_freight:String=snapshot.get("mine_freight",{}).get("own_job",{}).get("status","")
		if previous_freight=="draft" and latest_freight=="transit":freight_departure=elapsed
	if not changed_region and not data.is_empty() and str(snapshot.get("region_id","home"))=="home":
		var old_animals:Dictionary=data.get("livestock",{})
		var new_animals:Dictionary=snapshot.get("livestock",{})
		for animal_id:String in World.LIVESTOCK.ANIMALS:
			var last_pet:=float(new_animals.get(animal_id,{}).get("last_pet",-1))
			var previous_pet:=float(old_animals.get(animal_id,{}).get("last_pet",-1))
			if last_pet>previous_pet and float(snapshot.get("time",0))-last_pet<=LivestockArt.PET_SECONDS:
				livestock_pet_feedback[animal_id]=elapsed
	farm_feedback.observe(data,snapshot,elapsed)
	tool_feedback.observe(data,snapshot,id,elapsed)
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
		if current.distance_to(goal)>4.0:
			current=goal
			gait.erase(who)
			stride_stop.erase(who)
		starts[who]=current
		goals[who]=goal
		display_positions[who]=current
	for who in display_positions.keys():
		if not data.players.has(who):
			display_positions.erase(who)
			starts.erase(who)
			goals.erase(who)
			facings.erase(who)
			gait.erase(who)
			walking.erase(who)
			stride_stop.erase(who)

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
		var anchor:=get_viewport_rect().size*0.5+Vector2(0,40) if village_art_preview else Vector2(740,460)
		camera=(visual_position*TILE-anchor/view_zoom()).round()
	queue_redraw()

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

func _draw() -> void:
	if data.is_empty():return
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*view_zoom())
	world_labels.clear()
	focused_label="" if hide_interaction_prompt else interaction_focus()
	var size:=get_viewport_rect().size/view_zoom()
	var home:=region_id()==World.REGIONS.HOME
	var mining:=region_id()=="jinguashi"
	var transit:=TransitArt.NAMES.has(region_id())
	var tea_region:=region_id() in ["maokong","yingge"]
	var flower_region:=region_id()==World.FLOWER_NURSERY.REGION
	var salt_region:=region_id()==World.SALT_PAN.REGION
	var tea_sites:=tea_points(region_id())
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
	draw_rect(Rect2(Vector2.ZERO,size),Color("74b8b0"))
	for y in range(from.y,to.y):
		for x in range(from.x,to.x):
			var p:=Vector2i(x,y)
			var at:=screen(Vector2(p))
			var k:=World.key(p)
			if region_id()==World.REGIONS.Springs.REGION:
				World.REGIONS.Springs.ground(self,at,p)
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
	if salt_region:draw_salt_pans()
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
	var harvest_on:=home and HarvestUI.on_field(data)
	# T071 河岸釣魚會：進行中時用繩索與浮標標出指定水域（地面層之上、人物之下）。
	var fishmeet_on:=home and FishMeetUI.on_field(data)
	if fishmeet_on and FishMeetUI.waters_marked(data):FishMeetUI.draw_waters(self,elapsed,reduced_motion)
	# T071 家園布置題：解鎖後在地面層標出臨時展示地塊（靜態）；道具與告示牌在下面的列排序裡畫。
	var showcase_plot:=home and ShowcaseUI.plot_shown(data)
	var showcase_sign:=home and ShowcaseUI.sign_shown(data)
	var showcase_target:=ShowcaseUI.view_target(self) if focused_label==ShowcaseUI.PLOT_POINT else ShowcaseUI.NO_CELL
	if showcase_plot:ShowcaseUI.draw_plot(self,data,showcase_target)
	# T071 紀念品交換攤：渡口野餐後、使用中的攤位格（暫停時不畫）。
	var souvenir_cell:=SouvenirUI.booth_cell(data) if home else SouvenirUI.NO_CELL
	# 第 40 章風鈴節廣場地方記憶展：風鈴節開幕後、使用中的展台格（暫停時不畫）。
	var exhibit_cell:=MemoryExhibitUI.stand_cell(data) if home else MemoryExhibitUI.NO_CELL
	# 望安開場：小栗留的田（木樁、麻繩與名牌），只給還在第一株作物步驟的本人看；
	# 地面層之上、道具與人物之下，首次出貨後消失。
	if home:WanganUI.draw_plot(self,data,player_id)
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
	var gardener_cell:=lanyang_gardener_cell() if region_id()==World.REGIONS.LANYANG else Vector2i(-1,-1)
	# Draw all tall props and people in row order, keeping feet as sorting origin.
	for y in range(from.y,to.y):
		for x in range(from.x,to.x):
			var p:=Vector2i(x,y)
			var at:=screen(Vector2(p))
			var k:=World.key(p)
			if tea_region:
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
				if planted.mature:tree(at)
				else:sapling(at,float(planted.growth)/World.TREE_TIME)
			elif not data.removed.has(k):
				var resource:String=World.base_resource(p,region_id())
				if resource=="tree":tree(at)
				elif resource=="rock":rock(at)
				elif resource=="grass":grass(at)
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
				continue
			if mining:
				# 第 40 章運礦路線：軌道（地面）→ 裝礦台／卸礦台 → 本人的台車；靠近台車時顯示名牌。
				if p in World.ORE_ROUTE.TRACK:
					if not lanyang_cell_occupied(p): # 舊存檔在軌道格上蓋了東西時不蓋過它（台車照畫）
						OreRouteArt.draw_track(self,at,p)
						if p==World.ORE_ROUTE.STOPS[0]:OreRouteArt.draw_platform(self,at,"load")
						elif p==World.ORE_ROUTE.STOPS[-1]:OreRouteArt.draw_platform(self,at,"unload")
					var cart_stage:int=World.ORE_ROUTE.stage(data)
					if p==World.ORE_ROUTE.cart_cell(cart_stage):
						OreRouteArt.draw_cart(self,at,cart_stage>0,elapsed,reduced_motion)
						if focused_label==OreRouteArt.POINT:world_label(at+Vector2(16,-18),World.ORE_ROUTE.cart_label(data),OreRouteArt.POINT)
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
					if focused_label=="ditch:"+k:world_label(at+Vector2(16,-9),"清理水圳","ditch:"+k)
				if lanyang_life.get("repaired",false) and p in World.HISTORY_MEMORY.OBSERVATIONS:
					var observed:Array=data.get("history_memory",{}).get("own_memory",{}).get("seen",[])
					if k not in observed:
						draw_texture_rect_region(MemoryIcons,Rect2(at+Vector2(4,-6),Vector2(24,24)),Rect2(128,32,32,32))
					if focused_label=="memory:"+k:
						# 第 40 章：準備好的島民在這三格看到回訪的動作（調閘／巡看）。
						var revisit_prompt:=RevisitUI.cell_prompt(data,p)
						world_label(at+Vector2(16,-12),revisit_prompt if not revisit_prompt.is_empty() else "觀察水路","memory:"+k)
				if p==Vector2i(33,28) and data.get("history_memory",{}).get("plaque",false) and not lanyang_cell_occupied(p):
					FurnitureArt.draw_sprite(self,at,"sign")
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
			if p==World.Festival.TREE_CELL:draw_wind_chime_tree(at)
			if data.get("festival_story_open",false) and World.Festival.VISITORS.has(p):
				draw_festival_visitor(at,World.Festival.VISITORS[p])
			if p==Vector2i(40,29):
				board(at)
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
				var ripe:=float(data.get("seaweed_ready",0.0))<=float(data.time)
				var frond:=preload("res://scripts/inventory_item_art.gd").icon("seaweed")
				if frond:draw_texture_rect(frond,Rect2(at+Vector2(4,6),Vector2(24,24)),false,Color.WHITE if ripe else Color(1,1,1,0.35))
				world_label(at+Vector2(16,-4),"海苔 · 斧頭採集" if ripe else "海苔正在生長","shore_seaweed")
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
			var walk_spot:Array=World.bond_place(data,walk_id)
			var walk_cell:Vector2i=walk_spot[1]
			if str(walk_spot[0])!=region_id() or walk_cell.y!=y or not World.RESIDENT_BOND.present(data,walk_id):continue
			var walk_foot:=screen(Vector2(walk_cell)+Vector2(0.5,0.7))
			person_sprite(walk_foot,Color("e8d9c4"),walk_id)
			world_label(walk_foot+Vector2(0,-47),World.RESIDENT_BOND.name_of(walk_id),walk_id)
		if home and data.get("picnic",false):
			for id:String in World.LIVESTOCK.ANIMALS:
				var animal:Dictionary=World.LIVESTOCK.ANIMALS[id]
				if animal.cell.y!=y:continue
				var foot:=screen(Vector2(animal.cell)+Vector2(0.5,0.9)).round()
				var record:Dictionary=data.get("livestock",{}).get(id,{})
				LivestockArt.draw(self,foot,id,LivestockArt.state_for(record),reduced_motion,elapsed)
				if record.has("collector"):
					var equipment:=LivestockArt.collector_texture(int(record.collector),World.LIVESTOCK.COLLECTOR_CAPACITY)
					draw_texture(equipment,foot+Vector2(12,-10))
				if livestock_pet_feedback.has(id):
					LivestockArt.draw_pet_heart(self,foot,elapsed-float(livestock_pet_feedback[id]),reduced_motion)
				if focused_label=="livestock:"+id:
					var caption:String=animal.name
					if record.get("managed_pen",false) and not World.LIVESTOCK.pen_status(data.get("objects",{}),id):
						caption+="・圈舍待修"
					world_label(foot+Vector2(0,-42),caption,"livestock:"+id)
		# T071 客人演出：有攤位開張的世界日，攤位前站著幾位逛市集的客人（純呈現）。
		for guest:Dictionary in guests_today:
			if floori(float(guest.position.y))==y:draw_market_guest(guest)
		for id in data.players:
			var person:Dictionary=data.players[id]
			var visual_position:Vector2=display_positions.get(id,Vector2(person.x,person.y))
			if floori(visual_position.y)==y:
				var at:=screen(visual_position).round()
				var local:bool=id==player_id
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
				if fishing.get("phase","") in ["cast","wait","ready"]:
					var toward:Vector2=fishing.target-visual_position
					if absf(toward.x)>absf(toward.y):facing=Vector2i.RIGHT if toward.x>0 else Vector2i.LEFT
					else:facing=Vector2i.DOWN if toward.y>0 else Vector2i.UP
				# T017 hand-tool action: fishing and farm machines keep priority (one action pose at a time).
				var tool_plan:=tool_action_plan(id) if fishing.is_empty() and operation.is_empty() else {}
				if not tool_plan.is_empty():facing=tool_plan.facing
				if not tool_plan.is_empty() and facing==Vector2i.UP:draw_tool_held(at,tool_plan)
				person_sprite((at+tool_plan.get("lunge",Vector2.ZERO)).round(),shirt,"farmer" if local else "guest",facing,float(gait.get(id,0.0)),bool(walking.get(id,false)),bool(person.get("blue_outfit",false)))
				if not tool_plan.is_empty() and facing!=Vector2i.UP:draw_tool_held(at,tool_plan)
				if not machine_kind.is_empty() and machine_facing!=Vector2i.UP:
					draw_farm_machine(machine_kind,machine_at,machine_facing,working_now)
				if not fishing.is_empty():
					var float_pos:=screen(fishing.target)
					FishingArt.draw(self,at,float_pos,fishing,reduced_motion,elapsed)
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
		if not reduced_motion:chicken_pos.x+=sin(elapsed*0.5)*0.6
		chicken(screen(chicken_pos))
		world_label(screen(chicken_pos)+Vector2(0,-25),"糯米雞","animal")
		var animal:Dictionary=data.get("animal",{})
		if float(animal.get("egg_ready",-1))>=0 and float(data.time)>=float(animal.egg_ready):
			var egg_at:=screen(chicken_pos)+Vector2(12,0)
			if not character_art or not character_art.draw_egg(self,egg_at+Vector2(3,8)):
				draw_rect(Rect2(egg_at,Vector2(6,8)),Color("fff4d4"))
				draw_rect(Rect2(egg_at+Vector2(1,-2),Vector2(4,11)),Color("fff4d4"))
		if float(data.time)-float(animal.get("last_pet",-30))<3:
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
	draw_weather(size)
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
		if not operation.is_empty():draw_farm_feedback(operation)
		elif fishing_feedback.state_for(id,float(data.time),elapsed).is_empty():
			var tool_plan:=tool_action_plan(id)
			if not tool_plan.is_empty():draw_tool_target(tool_plan)
	if show_target:
		var at:=screen(Vector2(target))
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
		draw_rect(Rect2(at+Vector2.ONE,Vector2(30,30)),Color("fff4c2"),false,2.0)
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
	return roofs.has(World.key(cell))

func draw_weather(size:Vector2) -> void:
	var info:Dictionary=weather_info()
	if info.is_empty():return
	var shade:Color=WeatherArt.tint(info)
	if shade.a>0.0:draw_rect(Rect2(Vector2.ZERO,size),shade)
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
	var tint:=build_tint(style)
	if village_art and (region_id()!=World.REGIONS.HOME or VillagePreview.contains(draw_cell(at))):
		village_art.draw_tile(self,at,10 if kind=="floor" else 11,build_tint(style))
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
	if crop_art:
		crop_art.draw_crop(self,at,crop,crop_dormant(draw_cell(at),crop))
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

func object_sprite(at:Vector2,kind:String,object_data:Dictionary={}) -> void:
	if kind=="conveyor":
		LogisticsArt.draw_belt(self,at,object_data,float(data.get("time",0)),reduced_motion)
		var cargo:Dictionary=object_data.get("items",{})
		if not cargo.is_empty():
			var icon:Texture2D=load("res://scripts/inventory_item_art.gd").icon(str(cargo.keys()[0]))
			if icon:draw_texture_rect(icon,Rect2(at+Vector2(8,8),Vector2(16,16)),false)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:
			var direction:String=["↑","→","↓","←"][int(object_data.get("dir",1))]
			var caption:="輸送帶 %s · %s"%[direction,World.NAMES.get(object_data.get("filter","wood"),"")]
			if not object_data.get("enabled",false):caption+=" · 已停止"
			world_label(at+Vector2(16,-12),caption,device_key)
		return
	if kind=="forester":
		ForestryArt.draw_station(self,at,object_data,float(data.get("time",0)),reduced_motion)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:
			var caption:="林務工作站 · 已停止"
			if object_data.get("enabled",false):
				caption="林務工作站 · 燃料 %d／8"%int(object_data.get("fuel",0))
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
		var supplied:bool=int(info.get("water",0))>0 and int(info.get("connected_tanks",0))>0
		IndustryArt.draw_pipe(self,at,mask,supplied,float(data.get("time",0)),reduced_motion)
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
			world_label(at+Vector2(16,-26),"水塔 · 水 %d／%d · %s"%[int(object_data.get("water",0)),Industry.TOWER_CAPACITY,Industry.tower_enabled_name(object_data.get("enabled",false)==true)],tower_key)
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
		var art:=preload("res://assets/bakery/seed-maker.png")
		draw_texture(art,at+Vector2(0,-16))
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:world_label(at+Vector2(16,-20),World.BUILD[kind].name,device_key)
		return
	if kind=="glass_furnace":
		# Pale firebrick recolour of the kiln cell with a glass-green melt
		# (generated dedicated 32x48 art still pending).
		preload("res://scripts/glass_furnace_art.gd").draw(self,at,object_data,float(data.get("time",0)),reduced_motion)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:world_label(at+Vector2(16,-20),World.BUILD[kind].name,device_key)
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
		IndustryArt.draw_device(self,at,kind,object_data,float(data.get("time",0)),reduced_motion)
		var device_key:=World.key(draw_cell(at))
		if focused_label==device_key:
			var caption:String=World.BUILD[kind].name
			if kind=="water_tank":caption+=" · 水 %d／48"%int(object_data.get("water",0))
			elif object_data.has("job"):
				caption+=" · 可領取" if float(object_data.job.ready)<=float(data.get("time",0)) else " · 加工中"
			world_label(at+Vector2(16,-26),caption,device_key)
		return
	if Industry.SPRINKLER_CAPACITIES.has(kind):
		AutomationArt.draw_sprinkler(self,at,object_data,float(data.get("time",0)),reduced_motion,kind=="medium_sprinkler")
		var object_key:=World.key(draw_cell(at))
		if focused_label==object_key:
			world_label(at+Vector2(16,-22),"%s · 水 %d／%d"%[World.BUILD[kind].name,object_data.get("water",0),Industry.SPRINKLER_CAPACITIES[kind]],object_key)
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
	var status:=CookingFeedback.draw(self,at,obj,float(data.get("time",0)),elapsed,reduced_motion)
	if int(status.ready)>0:
		world_label(at+Vector2(16,-18),"料理好了 · %d 鍋待領"%int(status.ready),World.key(draw_cell(at)))

func person_sprite(at:Vector2,shirt:Color,style:="guest",facing:=Vector2i.DOWN,phase:=0.0,walking_now:=false,blue_workwear:=false) -> void:
	if character_art:
		character_art.draw_person(self,at,shirt,style,facing,phase,walking_now,reduced_motion,blue_workwear)
		return
	Art.person(self,at,Color("648eaa") if blue_workwear else shirt,style,facing,phase,walking_now,reduced_motion)

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
			title=SaltBrineArt.label(World.SALT_BRINE.level(data))
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

const INTERACTIVE_OBJECTS:=["chest","private_chest","supply_box","bench","bed","door","stove","sprinkler","medium_sprinkler","water_tank","water_pump","sawmill","charcoal_kiln","forester","conveyor","waterworks","mine_drill","mill","seed_maker","loom","glass_furnace","fish_display","author_sign","author_shelf","expedition_tent","diversion_gate","water_tower","water_share_plaque","mine_lantern","tea_ware","salt_basket"]

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
		var tea_sites:=tea_points(region_id())
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
	# 既有居民、走近型居民、物件的加入順序與 main.gd 的互動點一致（等距時名牌與互動對象相同）。
	for resident in World.Village.ids_for_region(region_id()):
		if resident=="xiaoli":continue
		var resident_cell:Vector2i=World.Village.resident_cell(data,resident)
		points[resident]=Vector2(resident_cell)+Vector2(0.5,0.5)
	for walk_id:String in World.RESIDENT_BOND.WALK_UP:
		var walk_spot:Array=World.bond_place(data,walk_id)
		if str(walk_spot[0])==region_id() and World.RESIDENT_BOND.present(data,walk_id):points[walk_id]=Vector2(walk_spot[1])+Vector2(0.5,0.5)
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
	return closest

static func tea_points(region:String)->Dictionary:
	var tea=World.TEA_CERAMICS
	if region=="yingge":return {tea.POTTER:"potter",tea.CLAY:"clay",tea.KILN:"kiln"}
	if region!="maokong":return {}
	var points:Dictionary={tea.TEA_NPC:"host",tea.ROASTER:"roast",tea.PACKER:"pack"}
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
	var target_cell:Vector2i=record.to if record.tool=="move_object" else record.cell
	var facing:=ToolActionFeedback.facing_toward(record.origin,target_cell,facings.get(id,Vector2i.DOWN))
	var progress:=clampf((elapsed-float(record.started))/ToolActionFeedback.DURATION,0.0,1.0)
	var result:=ToolActionFeedback.plan(record.tool,progress,reduced_motion,facing)
	result.facing=facing
	result.record=record
	return result

## Held tool icon (existing 32px ui-life / inventory pixel art) at the hand, rotated
## around the grip. Reduced motion: fixed pose from the plan, no lunge.
func draw_tool_held(at:Vector2,tool_plan:Dictionary) -> void:
	var icon:=ToolActionFeedback.held_icon(tool_plan.tool,str(tool_plan.record.get("item","")))
	if icon==null:return
	var grip:Vector2=(at+tool_plan.hand+tool_plan.lunge+Vector2(0,tool_plan.lift if tool_plan.tool=="move_object" else 0.0)).round()
	var zoom_scale:=Vector2.ONE*view_zoom()
	draw_set_transform(grip*zoom_scale,float(tool_plan.angle),zoom_scale)
	draw_texture_rect(icon,Rect2(Vector2(-8,-16),Vector2(16,16)),false)
	draw_set_transform(Vector2.ZERO,0.0,zoom_scale)
	tool_draw_stats.held+=1
	if tool_plan.lunge!=Vector2.ZERO:tool_draw_stats.lunge+=1
	tool_draw_stats.angles[snappedf(float(tool_plan.angle),0.01)]=true

## Target-cell feedback: short procedural chips/drops/dust (none with reduced motion)
## plus a harvested-crop icon rising from the plot (fixed with reduced motion).
func draw_tool_target(tool_plan:Dictionary) -> void:
	var record:Dictionary=tool_plan.record
	var cell:Vector2i=record.to if record.tool=="move_object" else record.cell
	var cell_at:=screen(Vector2(cell))
	if record.tool=="harvest" and not str(record.item).is_empty():
		var crop_icon:=MarketItemArt.icon(str(record.item))
		if crop_icon:draw_texture_rect(crop_icon,Rect2(cell_at+Vector2(9,4+tool_plan.lift),Vector2(14,14)),false,Color(1,1,1,tool_plan.alpha))
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
	var font_size:=18 if view_zoom()==1.0 else 14
	var height:=font_size+4
	var placed:Array[Rect2]=[]
	var result:Array[Dictionary]=[]
	var compact:=compact_farm_prompt()
	var obstacles:=label_obstacles(compact,font_size)
	# Farm prompts historically also pushed passive labels off the plots/body.
	if compact:placed.append_array(obstacles)
	var area:=LabelLayout.safe_area(viewport)
	for active in [true,false]:
		for entry in world_labels:
			if (entry.id!="" and entry.id==focused_label)!=active:continue
			if not active and display_positions.has(player_id):
				var local_foot:=screen(display_positions[player_id])
				if Vector2(entry.anchor).distance_to(local_foot)>160.0:continue
				if entry.id=="" and Vector2(entry.anchor).distance_to(local_foot+Vector2(0,-40))<2.0:continue
			if compact and not active and (data.get("objects",{}).has(entry.id) or entry.id==""):continue
			var title:String=farm_label_title(entry) if compact and active else entry.title
			var key_width:float=interaction_badge_width() if active else 0.0
			var width:float=ceilf(font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)+8+(key_width+3 if active else 0)
			var anchor:Vector2=entry.anchor
			var at:=Vector2(anchor.x if entry.side else roundf(anchor.x-width/2.0),anchor.y-height)
			var box:=Rect2(at,Vector2(width,height))
			if not active and (not viewport.has_point(anchor) or not viewport.intersects(box)):continue
			if not active and hidden_under_card(box):continue
			if active:
				# The focused prompt steps around the local body, its name tag and HUD,
				# staying as close to its target as possible and never being dropped.
				var blockers:Array[Rect2]=[]
				blockers.append_array(obstacles)
				for other in placed:
					if not blockers.has(other):blockers.append(other)
				box=LabelLayout.place(box,anchor,blockers,area).rect
			elif compact:
				# Secondary labels during farm work only show if they fit cleanly.
				var spot:=LabelLayout.place(box,anchor,placed,viewport)
				if not spot.clear:continue
				box=spot.rect
			else:
				for other in placed:
					if box.grow(2).intersects(other):box.position.x=other.end.x+3
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
func label_obstacles(compact:bool,font_size:int) -> Array[Rect2]:
	var list:Array[Rect2]=[]
	var scale_value:=view_zoom()
	for rect in label_avoid_rects:list.append(Rect2(rect.position/scale_value,rect.size/scale_value))
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
				var width:=ceilf(font.get_string_size(str(entry.title),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)+8
				list.append(Rect2(Vector2(roundf(tag_anchor.x-width/2.0),tag_anchor.y-font_size-4),Vector2(width,font_size+4)))
				break
	return list

func interaction_badge_width() -> float:
	return maxf(13,ceilf(font.get_string_size(interaction_key_label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x)+6)

func draw_world_labels() -> void:
	var scale_value:=view_zoom()
	var font_size:=roundi((18 if scale_value==1.0 else 14)*scale_value)
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
			draw_string_outline(font,pos,entry.title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color("35402d"))
			draw_string(font,pos,entry.title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff6de"))
		if entry.active:
			var key_width:=interaction_badge_width()*scale_value
			var key_pos:=(box.position+Vector2(box.size.x-key_width-2*scale_value,(box.size.y-13*scale_value)/2.0)).round()
			draw_rect(Rect2(key_pos,Vector2(key_width,13*scale_value)),Color("526744"))
			draw_string(font,key_pos+Vector2(3,10)*scale_value,interaction_key_label,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(10*scale_value),Color("fff6de"))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE*scale_value)
