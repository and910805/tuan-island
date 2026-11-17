extends SceneTree
## T066「一起做的事」UI test (headless, 1024×640 and 1280×800). Same harness as
## test_resident_bond_local_ui.gd: main.tscn with app.village_art_preview=true set by
## the test itself and an in-process host session.
##
## Covers: the 關係事件 page entry (BondGoalCount, BondGoalOpen ○／✓, absent on locked
## and goal-less tabs, updated on tab switch, focus links tabs ↔ BondGoalOpen ↔ back,
## card/tabs unchanged), the goal page bond_goal(app,id,stage) for a pure deliver goal
## (米露 1), options+items (波波 2), per-option cost (米露 3), free-order steps+items
## (阿榆 2), fixed-order steps (鈴婆婆 2), options only (洛洛 3): reason priority,
## BondGoalDo disabled/enabled and its tooltip, cost rows (red when short, changing
## with the option), completion through the real BondGoalDo press, the done page;
## the not-standing reason; in-place refresh on a new snapshot; Esc, BondGoalBack and
## initial focus; and a layout sweep of ALL 28 goals in open and done state.
## Batch 2 (needs／前提): the BondGoalNeeds block (one BondGoalNeed_<id> line per need,
## "✓ 要先：…" when met, "○ 要先：…" in the warning colour when not, placed before
## BondGoalCost, absent on done pages and on goals without needs); reason priority
## (need before item shortage, 星禾 3); in-place refresh when a need becomes met
## (阿榆 1 own_bed, 洛洛 2 known_three counting 0→3, 棉棉 4 fair_weather, 小栗 3
## market_round, 鈴婆婆 4 festival_done) each completed through BondGoalDo; a sweep of
## every goal-with-needs in the "need unmet" state; and another player's snapshot
## (built by the real Session._send_snapshot) carrying only that player's needs rows.
## Batch 3 (紀念小物): the 12 keepsake goals (KEEPSAKE_GOALS) — catalog (name = the goal's
## keepsake, World.NAMES has the kit, the inventory panel's static use_for/value_for text);
## own snapshot "keepsake" entries ({"kind","item","name","claimed"}, only on those 12);
## the done page: BondGoalKeepsake row (32×32 icon + BondGoalKeepsakeText) instead of
## the old 「紀念：…（收在手帳裡，沒有其他用途）」 line, claimed for all 12 and the old line
## for the other 16 in the done sweep; completing a keepsake goal through the real
## 一起完成 press gives the kit (bag +1, toast tail, record) and reopening shows claimed;
## the unclaimed (done before batch 3) page for 阿榆 1 (家園), 波波 1 (金瓜石), 星禾 2
## (蘭陽), 暖暖 1 (礁溪): 「還沒領」, BondGoalClaim disabled with 「…才能領取。」 away,
## enabled beside, really pressed → server → bag +1, same goal page rebuilt as claimed,
## no second claim; the OTHER snapshot carries no bond_keepsakes.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (talk_day/gift_day 0 are past days),
##    and later by further whole days (Village.DAY) until Weather.rains(day,"home") is
##    true or false as a flow needs (fair_weather);
##  * state.picnic is written true (洛洛／鈴婆婆／棉棉 present);
##  * a second player OTHER is added with World.add_player (never connected); for the
##    privacy check Session.peers is swapped to {1:OTHER, 2:host} for one direct
##    Session._send_snapshot(1) call, then restored and the host snapshot re-sent;
##  * needs prerequisites are written directly on the server world (restored at the end):
##      own_bed       {"type":"bed","owner":<host token>,"items":{}} written into the
##                    HOME objects layer at a free cell >=3 tiles from spawn and >=4 from
##                    every home resident cell (removed again = every own bed erased);
##      glass_crafted player.greenhouse_glass_crafted = true／false;
##      market_round  player.market = MarketStall.fresh() with open_day = yesterday and a
##                    schema-shaped report for yesterday (0 visitors, 1 stall, nothing
##                    sold); unmet = MarketStall.fresh() (empty report);
##      festival_done state.festival.round = 1／0 with active = false;
##      known_three   via player.bonds (unmet: every resident except 洛洛 at points 0,
##                    then 1 point each for 阿榆、米露、波波、小栗 one by one);
##      fair_weather  via world time (above);
##  * player.bonds is written directly: every resident {points 24} (好友), except the
##    events flow where 米露 gets points 6 (熟悉) and the known_three cases;
##  * player.bond_goals is erased before each flow, and written directly (every goal
##    done, choice = last option) for the done-state layout sweep and the ✓ entry check;
##  * player.bond_keepsakes is erased together with bond_goals (set_done; the save schema
##    only allows keepsakes of done goals) and written directly: all 12 claimed for the
##    done sweep, keepsake_bobo for the privacy check; the 補領 flows write a done record
##    WITHOUT bond_keepsakes (= a goal finished before batch 3);
##  * the backpack is written directly: every item any goal uses is set to 0, then the
##    amounts each flow needs (sometimes one short first, then topped up — the top-up
##    is a preset followed by a snapshot, which also exercises the in-place refresh);
##  * the player is teleported by writing region/x/y: 0.9 tile south of the resident's
##    World.bond_place cell ("standing"), or 12/8 tiles away in the same region ("far");
##  * the events page is opened with a DIRECT Tasks.bond_events(app,id[,tab]) call and
##    the layout sweep opens goal pages with a DIRECT Tasks.bond_goal(app,id,stage).
## REALLY PRESSED (emitting `pressed` on the real buttons):
##  * BondEventTab_n, BondGoalOpen, BondGoalOption_<id>, BondGoalStep_n,
##    BondGoalStepsReset, BondGoalBack, BondGoalDo and BondGoalClaim — BondGoalDo and
##    BondGoalClaim go through the real Session.perform("resident_goal" /
##    "resident_keepsake") -> World -> snapshot trip; the inventory, the world record
##    (player.bond_goals / bond_keepsakes) and snapshot.resident_goals are then read back;
##  * Esc is sent as an InputEventKey to app._input.
## DIRECT (not a press): after claiming, a second Tasks.do_goal_claim(app) call and a
## second app.session.perform(CLAIM_ACTION) request (both must change nothing).
## NOT SIMULATED: mouse clicks and arrow/Tab key presses — focus order is checked with
## focus_mode, grab_focus and find_next/prev_valid_focus only.
## NOT ASSERTED (printed as NOTE): 點點 2 in star_garden is completed through the real
## button and the server answer is printed (World's angling-reserve gate may reject it).
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const Weather=preload("res://scripts/weather.gd")
const WARN:=Color("9c4b32")
## Second (never connected) player for the privacy check.
const OTHER:="goal-ui-other-traveller"
## Goals per resident after batch 2 (28 in total).
const PER_RESIDENT:={"aru":4,"milu":4,"bobo":4,"chacha":4,"achao":4,"mianmian":4,"xinghe":4,"lingpopo":4,"xiaoli":4,"luoluo":4,"diandian":4,"nuannuan":4}
## Batch 3: the goal (resident -> stage) whose keepsake is a placeable 紀念小物 (12 total).
const KEEPSAKE_GOALS:={"aru":1,"milu":3,"bobo":1,"chacha":2,"achao":1,"mianmian":3,"xinghe":2,"lingpopo":3,"xiaoli":4,"luoluo":4,"diandian":2,"nuannuan":1}
const OLD_KEEPSAKE_TAIL:="（收在手帳裡，沒有其他用途）"
const KIT_MESSAGE:="紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const EVENTS_FOOTER:="聊天、送禮和完成委託都會增加好感。好感不會因為沒上線而下降，朋友的進度也不影響你。"
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var finished:=false
## Originals of the directly written needs prerequisites (restored at the end).
var saved_festival:Dictionary={}
var saved_market:Variant=null
var saved_glass:Variant=null

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("RESIDENT_GOAL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE RESIDENT_GOAL_UI "+message)

# ------------------------------------------------------------- helpers --

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and is_instance_valid(app.modal) and (app.modal as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect())

func not_cut(l:Label)->bool:
	if l==null or l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.size.y+0.5<l.get_combined_minimum_size().y:return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func button_not_cut(b:Button)->bool:
	if b==null or b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x and b.size.y+0.5>=b.get_combined_minimum_size().y

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func find_label(text:String)->Label:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l!=null and l.is_visible_in_tree() and l.text==text:return l
	return null

func first_label(holder:Node)->Label:
	if holder==null:return null
	for node in holder.find_children("*","Label",true,false):return node as Label
	return null

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	await settle()

func clear_toast()->void:
	if app.toast==null or not is_instance_valid(app.toast):return
	var toast_label:Label=app.toast
	toast_label.text=""

func toast_text()->String:
	if app.toast==null or not is_instance_valid(app.toast):return ""
	return str((app.toast as Label).text)

## Emit `pressed` on an enabled button (the same signal a click / Enter sends).
func press_button(b:BaseButton,label:String,wait:=false)->bool:
	check(b!=null and not b.disabled,"Enabled button: "+label)
	if b==null or b.disabled:return false
	clear_toast()
	if wait:await create_timer(0.12).timeout
	b.pressed.emit()
	await settle()
	return true

func press(name:String,wait:=false)->bool:
	return await press_button(control(name) as BaseButton,name,wait)

func close()->void:
	app._close_modal()
	await settle()

func person()->Dictionary:
	return w.state.players[id]

func inventory()->Dictionary:
	return person().inventory

func held(item:String)->int:
	return int(inventory().get(item,0))

func npc(resident:String)->String:
	return Bond.name_of(resident)

func entry_of(resident:String,stage:int)->Dictionary:
	return Goals.goal(resident,stage)

func state_of(resident:String,stage:int)->String:
	return str(Tasks.goal_state(app,resident,stage).get("state",""))

func choice_of(resident:String,stage:int)->String:
	return str(Tasks.goal_state(app,resident,stage).get("choice",""))

func world_done(resident:String)->Dictionary:
	return Goals.done(person(),resident)

func all_goals()->Array:
	var out:Array=[]
	for resident:String in Goals.GOALS:
		for stage:int in Goals.GOALS[resident]:out.append([resident,stage])
	return out

func goal_items()->Array:
	var out:Array=[]
	for pair:Array in all_goals():
		var entry:=entry_of(str(pair[0]),int(pair[1]))
		for item:String in entry.get("items",{}):
			if item not in out:out.append(item)
		for option:Dictionary in entry.get("options",[]):
			for item:String in option.get("items",{}):
				if item not in out:out.append(item)
	return out

# --------------------------------------------------------------- presets --

## PRESET: every bond resident at 好友 unless overridden.
func set_bonds(overrides:Dictionary={})->void:
	var bonds:={}
	for resident:String in Bond.RESIDENTS:
		bonds[resident]={"points":int(overrides.get(resident,Bond.LIMIT)),"talk_day":0,"gift_day":0}
	var p:=person()
	p.bonds=bonds

## PRESET: player.bond_goals (empty = erase). player.bond_keepsakes is always erased with it
## (the save schema only allows keepsakes of done goals); use set_keepsakes() afterwards.
func set_done(goals:Dictionary)->void:
	var p:=person()
	p.erase(Goals.KEEPSAKE_KEY)
	if goals.is_empty():p.erase(Goals.RECORD_KEY)
	else:p[Goals.RECORD_KEY]=goals

## PRESET: player.bond_keepsakes = {kind:true} for the given kinds (empty = erase).
func set_keepsakes(kinds:Array)->void:
	var p:=person()
	if kinds.is_empty():
		p.erase(Goals.KEEPSAKE_KEY)
		return
	var record:={}
	for kind:String in kinds:record[kind]=true
	p[Goals.KEEPSAKE_KEY]=record

## PRESET: all goal items to 0, then the given amounts.
func stock(items:Dictionary)->void:
	var inv:=inventory()
	for item:String in goal_items():inv[item]=0
	for item:String in items:inv[item]=int(items[item])

## PRESET teleport: 0.9 tile south of the resident's cell, or 12/8 tiles away.
func stand(resident:String,far:=false)->void:
	var where:Array=World.bond_place(app.session.snapshot,resident)
	var cell:Vector2i=where[1]
	var p:=person()
	p.region=str(where[0])
	var at:=Vector2(cell)+Vector2(0.5,1.4)
	if far:at+=Vector2(12,8)
	p.x=at.x;p.y=at.y
	await refresh()

## PRESET (known_three unmet): every resident except 洛洛 at points 0.
func strangers()->Dictionary:
	var out:={}
	for resident:String in Bond.RESIDENTS:
		if resident!="luoluo":out[resident]=0
	return out

## A free HOME cell for the bed: no object/crop/tree/ground/roof, >=3 tiles from spawn,
## >=4 tiles from every home resident cell (so no standing spot or resident cell moves).
func bed_cell()->Vector2i:
	var avoid:Array=[]
	for resident:String in Bond.RESIDENTS:
		var place:Array=World.bond_place(w.state,resident)
		if str(place[0])==str(World.REGIONS.HOME):avoid.append(place[1])
	var origin:=Vector2i(World.SPAWN)
	for radius in range(3,16):
		for dy in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				if maxi(absi(dx),absi(dy))!=radius:continue
				var cell:=origin+Vector2i(dx,dy)
				var tile:=World.key(cell)
				var taken:=false
				for layer:String in ["objects","crops","forest","ground","roofs"]:
					var found:Variant=w.home_layer(layer)
					if found is Dictionary and (found as Dictionary).has(tile):taken=true
				if taken:continue
				var near:=false
				for spot:Vector2i in avoid:
					if Vector2(spot).distance_to(Vector2(cell))<4.0:near=true
				if not near:return cell
	return origin+Vector2i(16,16)

## PRESET own_bed: erase every bed owned by this player; with `on`, write one bed in the
## same shape World uses when a bed is placed.
func set_bed(on:bool)->void:
	var objects:Dictionary=w.home_layer("objects")
	for tile:String in objects.keys():
		var obj:Variant=objects[tile]
		if obj is Dictionary and str(obj.get("type",""))=="bed" and str(obj.get("owner",""))==id:objects.erase(tile)
	if on:objects[World.key(bed_cell())]={"type":"bed","owner":id,"items":{}}

## PRESET market_round: a schema-shaped market record with yesterday's report, or fresh().
func set_market(on:bool)->void:
	var market:Dictionary=World.MARKET.fresh()
	if on:
		var yesterday:int=World.MARKET.day(float(w.state.time))-1
		market.open_day=yesterday
		market.report={"day":yesterday,"visitors":0,"stalls":1,"theme":World.MARKET.theme_of(yesterday),"sold":{},"coins":0}
	var p:=person()
	p.market=market

## PRESET for one need (fair_weather is moved with weather(); known_three with set_bonds()).
func set_need(need:String,on:bool)->void:
	match need:
		"tea_chair":
			if on:person()[Goals.TEA_CHAIR_KEY]="wood"
			else:person().erase(Goals.TEA_CHAIR_KEY)
		"shared_garden":
			var state:Dictionary=app.session.world.state
			if on:state[Goals.GARDEN_KEY]=[{"npc":false,"author":app.session.profile.token,"flower":"bluebell"},{"npc":true,"author":"xinghe","flower":"chime_herb"},{"npc":true,"author":"milu","flower":"orange_blossom"}]
			else:state.erase(Goals.GARDEN_KEY)
		"achao_photo":
			if on:person()[Goals.VOYAGE_PHOTO]=true
			else:person().erase(Goals.VOYAGE_PHOTO)
		"achao_voyage":
			if on:
				app.session.world.state.dock_stage=2
				app.session.world.state[Goals.DOCK_LIGHT]=true
				person()[Goals.VOYAGE_DONE]=true
			else:person().erase(Goals.VOYAGE_DONE)
		"aru_park_photo":
			if on:person()[Goals.ARU_PHOTO_KEY]=true
			else:person().erase(Goals.ARU_PHOTO_KEY)
		"aru_rest":
			if on:person()[Goals.ARU_REST_KEY]=float(app.session.world.state.time)
			else:person().erase(Goals.ARU_REST_KEY)
		"sheep_comfort":
			if on:person()[Goals.SHEEP_SHELTER_KEY]=Goals.SHEEP_COMFORT_MASK
			else:person().erase(Goals.SHEEP_SHELTER_KEY)
		"tea_setup":
			if on:person()[Goals.TEA_SETUP_KEY]="horizontal"
			else:person().erase(Goals.TEA_SETUP_KEY)
		"public_mural":
			if on:w.state[Goals.MURAL_KEY]={"author":id,"author_name":person().name,"subjects":["aru","milu","xiaoli"],"signatures":{}}
			else:w.state.erase(Goals.MURAL_KEY)
		"painting_invites":
			if on:person()[Goals.PAINT_INVITES_KEY]=["aru","milu","xiaoli"]
			else:person().erase(Goals.PAINT_INVITES_KEY)
		"growth_record":
			if on:person()[Goals.GROWTH_LOG_KEY]={"radish":true}
			else:person().erase(Goals.GROWTH_LOG_KEY)
		"address_delivered":
			if on:person()[Goals.ADDRESS_KEY]=Goals.ADDRESS_DELIVERED
			else:person().erase(Goals.ADDRESS_KEY)
		"inn_entrance":
			if on:person()[Goals.INN_CLEAR_KEY]=true
			else:person().erase(Goals.INN_CLEAR_KEY)
		"guest_room":
			if on:person()[Goals.GUEST_ROOM_KEY]=true
			else:person().erase(Goals.GUEST_ROOM_KEY)
		"bell_inspected":
			if on:person()[Goals.BELL_INSPECT_KEY]=Goals.BELL_INSPECT_MASK
			else:person().erase(Goals.BELL_INSPECT_KEY)
		"rest_kit":
			if on:person()[Goals.REST_KIT_KEY]=Goals.REST_KIT_MASK
			else:person().erase(Goals.REST_KIT_KEY)
		"recipe_pages":
			if on:person()[Goals.RECIPE_PAGE_KEY]=Goals.RECIPE_PAGE_MASK
			else:person().erase(Goals.RECIPE_PAGE_KEY)
		"route_marks":
			if on:person()[Goals.ROUTE_KEY]=Goals.ROUTE_MASK
			else:person().erase(Goals.ROUTE_KEY)
		"crop_sketches":
			if on:person()[Goals.SKETCH_KEY]={"radish":true,"lettuce":true,"wheat":true}
			else:person().erase(Goals.SKETCH_KEY)
		"shared_meal":
			if on:person().resident_participation={"shared_meal":true}
			else:person().erase("resident_participation")
		"crop_sold","seed_after_sale":
			if on:person()[Goals.CROP_TRADE_KEY]=Goals.SEED_BOUGHT
			elif need=="seed_after_sale":person()[Goals.CROP_TRADE_KEY]=Goals.CROP_SOLD
			else:person().erase(Goals.CROP_TRADE_KEY)
		"chicken_fed":
			if on:person()[Goals.CHICKEN_FED_KEY]=maxf(0.0,float(w.state.time)-Goals.CHICKEN_APPROACH_SECONDS)
			else:person().erase(Goals.CHICKEN_FED_KEY)
		"own_bed":set_bed(on)
		"glass_crafted":
			var p:=person()
			p.greenhouse_glass_crafted=on
		"market_round":set_market(on)
		"festival_done":
			w.state.festival.round=1 if on else 0
			w.state.festival.active=false
		"known_three":set_bonds({} if on else strangers())

## PRESET world time: whole days forward until home rain matches `rainy`, then a snapshot.
func weather(rainy:bool)->void:
	for i in range(8):
		if Weather.rains(Weather.day_index(float(w.state.time)),"home")==rainy:break
		w.state.time=float(w.state.time)+Village.DAY
	check(Weather.rains(Weather.day_index(float(w.state.time)),"home")==rainy,"Found a %s home day"%("rainy" if rainy else "dry"))
	await refresh()

## PRESET: every needs prerequisite met except `unmet` (bonds are left to the caller;
## set_bonds() at 好友 meets known_three).
func set_needs(unmet:String="")->void:
	for need:String in ["own_bed","glass_crafted","market_round","festival_done","chicken_fed","shared_meal","crop_sketches","route_marks","recipe_pages","rest_kit","bell_inspected","inn_entrance","guest_room","address_delivered","growth_record","painting_invites","public_mural","tea_setup","tea_chair","sheep_comfort","aru_rest","aru_park_photo","achao_voyage","achao_photo","shared_garden"]:set_need(need,need!=unmet)
	set_need(unmet if unmet in ["crop_sold","seed_after_sale"] else "seed_after_sale",unmet not in ["crop_sold","seed_after_sale"])
	if unmet=="known_three":set_need("known_three",false)
	await weather(unmet=="fair_weather")

# ------------------------------------------------------------- layout --

## No outer scrolling; every visible Label/Button fully on view inside the modal, not cut.
func page_fits(label:String)->void:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Modal open (%s)"%label)
	if not ok:return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Modal fits the viewport (%s)"%label)
	check(str((app.modal as Node).get_meta("life_modal_layout",""))=="community_board","Modal keeps the community_board layout (%s)"%label)
	var scroll:=control("ModalScroll") as ScrollContainer
	check(scroll!=null and scroll.get_child_count()>0,"Modal has its ModalScroll body (%s)"%label)
	if scroll==null or scroll.get_child_count()==0:return
	var content:=scroll.get_child(0) as Control
	var need:float=content.get_combined_minimum_size().y
	var bar:=scroll.get_v_scroll_bar()
	print("RESIDENT_GOAL_DIAG fit %s content=%.0f view=%.0f spare=%.0f"%[label,need,scroll.size.y,scroll.size.y-need])
	check(need<=scroll.size.y+0.5 and not bar.visible and scroll.scroll_vertical==0,"Page needs no outer scrolling (%s) content=%.0f view=%.0f"%[label,need,scroll.size.y])
	for node in (app.modal as Node).find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree():continue
		if c is Label:
			check(visible(c) and inside_modal(c),"Caption fully on view inside the modal: %s (%s)"%[(c as Label).text,label])
			check(not_cut(c as Label),"Caption not cut or ellipsized: %s (%s)"%[(c as Label).text,label])
		elif c is Button:
			check(visible(c) and inside_modal(c),"Button fully on view inside the modal: %s (%s)"%[c.name,label])
			check(button_not_cut(c as Button),"Button caption not cut: %s %s (%s)"%[c.name,(c as Button).text,label])

# ------------------------------------------------------------ events page --

func open_events(resident:String,tab:=-1)->bool:
	await close()
	Tasks.bond_events(app,resident,tab)
	await settle()
	var ok:=is_instance_valid(app.modal) and find_label("%s的關係事件"%npc(resident))!=null and control("BondEventCard")!=null
	check(ok,"%s的關係事件 opens"%npc(resident))
	return ok

func count_text(resident:String)->String:
	var finished_count:=0
	for stage:int in Goals.GOALS[resident]:
		if state_of(resident,stage)=="done":finished_count+=1
	return "一起做的事 %d／%d"%[finished_count,Goals.GOALS[resident].size()]

## The selected tab, the card (only that stage) and the goal entry for it.
func events_tab_ok(resident:String,index:int,label:String)->void:
	var stage:=int(Bond.stage(person(),resident))
	page_fits("events %s tab %d %s"%[resident,index+1,label])
	check(find_label(EVENTS_FOOTER)!=null,"Events footer still shown (%s)"%label)
	var count:=control("BondGoalCount") as Label
	check(count!=null and count.text==count_text(resident),"BondGoalCount reads %s (%s): %s"%[count_text(resident),label,count.text if count else "?"])
	for i in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%i) as Button
		check(tab!=null and tab.toggle_mode and tab.button_pressed==(i==index) and not tab.disabled,"BondEventTab_%d %s (%s)"%[i,"selected" if i==index else "not selected",label])
	var card:=control("BondEventCard")
	var lines:Array=Bond.EVENTS[resident][index].lines
	var wanted:int=1+(lines.size() if index<stage else 0)
	var shown:=0
	if card!=null:
		for node in card.find_children("*","Label",true,false):
			if (node as Control).is_visible_in_tree():shown+=1
	check(shown==wanted,"BondEventCard holds only stage %d (%s): %d labels, want %d"%[index+1,label,shown,wanted])
	var goal_stage:=index+1
	var state:=state_of(resident,goal_stage)
	var open:=control("BondGoalOpen") as Button
	var expect:=Goals.has_goal(resident,goal_stage) and state in ["open","done"]
	check((open!=null)==expect,"BondGoalOpen %s on tab %d of %s (state %s) (%s)"%["present" if expect else "absent",index+1,resident,state,label])
	if open==null or not expect:return
	var title:=str(entry_of(resident,goal_stage).title)
	var text:=("✓ " if state=="done" else "○ ")+"一起做的事・"+title
	check(open.text==text,"BondGoalOpen reads %s (%s): %s"%[text,label,open.text])
	check(card!=null and open.get_global_rect().position.y>=card.get_global_rect().end.y-0.5,"BondGoalOpen sits under the card (%s)"%label)
	var tab_now:=control("BondEventTab_%d"%index) as Button
	var back:=control("BondEventsBack") as Button
	check(tab_now!=null and tab_now.find_valid_focus_neighbor(SIDE_BOTTOM)==open,"Down from the selected tab reaches BondGoalOpen (%s)"%label)
	check(open.find_valid_focus_neighbor(SIDE_TOP)==tab_now,"Up from BondGoalOpen reaches the selected tab (%s)"%label)
	check(back!=null and open.find_valid_focus_neighbor(SIDE_BOTTOM)==back,"Down from BondGoalOpen reaches BondEventsBack (%s)"%label)

func press_tab(index:int,label:String)->void:
	var tab:=control("BondEventTab_%d"%index) as Button
	check(tab!=null,"BondEventTab_%d exists (%s)"%[index,label])
	if tab==null:return
	tab.grab_focus()
	tab.pressed.emit()
	await settle()
	check(root.gui_get_focus_owner()==tab,"Focus stays on BondEventTab_%d (%s)"%[index,label])

func events_flow(label:String)->void:
	set_bonds({"milu":6})  # 熟悉: goal 1 open, goal 3 locked
	set_done({})
	await stand("milu")
	check(int(Bond.stage(person(),"milu"))==2,"米露 preset is at 熟悉 (%s)"%label)
	if not await open_events("milu"):return
	# Default tab = 熟悉 (stage 2 has no goal).
	events_tab_ok("milu",1,"default "+label)
	for index in [0,1,2,3,0]:
		await press_tab(index,"milu "+label)
		events_tab_ok("milu",index,"milu pressed "+label)
	# The ✓ marker after the goal is done (preset), count 1／2.
	set_done({"milu":{"1":""}})
	await refresh()
	if await open_events("milu",0):
		events_tab_ok("milu",0,"milu done "+label)
		var open:=control("BondGoalOpen") as Button
		check(open!=null and open.text.begins_with("✓ "),"Done goal shows ✓ (%s)"%label)
	# 阿榆 at 好友: 認識 (stage 1, batch 2) and 熟悉 (stage 2) have goals; 0／4.
	set_bonds()
	set_done({})
	await refresh()
	if await open_events("aru"):
		var aru_count:=control("BondGoalCount") as Label
		check(aru_count!=null and aru_count.text=="一起做的事 0／4","阿榆 counter reads 一起做的事 0／4 (%s): %s"%[label,aru_count.text if aru_count else "?"])
		events_tab_ok("aru",3,"aru default "+label)
		for index in [1,0,2,1]:
			await press_tab(index,"aru "+label)
			events_tab_ok("aru",index,"aru pressed "+label)
	await close()

# ------------------------------------------------------------- goal page --

func goal_open(resident:String,stage:int)->bool:
	if not is_instance_valid(app.modal):return false
	var title:=control("BondGoalTitle") as Label
	return find_label("和%s一起做的事"%npc(resident))!=null and title!=null and title.text=="%s・%s"%[Bond.stage_name(stage),str(entry_of(resident,stage).title)]

## Real path: events page on the goal's tab, then BondGoalOpen.
func open_goal(resident:String,stage:int,label:String)->bool:
	if not await open_events(resident,stage-1):return false
	var open:=control("BondGoalOpen") as Button
	check(open!=null,"BondGoalOpen offered for %s %d (%s)"%[resident,stage,label])
	if open==null:return false
	if not await press_button(open,"BondGoalOpen %s %d %s"%[resident,stage,label]):return false
	var ok:=goal_open(resident,stage)
	check(ok,"BondGoalOpen opens 和%s一起做的事 on %s・%s (%s)"%[npc(resident),Bond.stage_name(stage),str(entry_of(resident,stage).title),label])
	return ok

func reason_text()->String:
	var reason:=control("BondGoalReason") as Label
	if reason==null or not reason.is_visible_in_tree():return ""
	return reason.text

## Reason label, Do state and tooltip agree.
func reason_is(expected:String,label:String)->void:
	var reason:=control("BondGoalReason") as Label
	var finish_button:=control("BondGoalDo") as Button
	check(reason_text()==expected,"Reason reads 「%s」 (%s): 「%s」"%[expected,label,reason_text()])
	if reason!=null and not expected.is_empty():
		check(reason.has_theme_color_override("font_color") and reason.get_theme_color("font_color")==WARN,"Reason is in the warning colour (%s)"%label)
	check(finish_button!=null and finish_button.disabled==(not expected.is_empty()),"BondGoalDo %s (%s)"%["disabled" if not expected.is_empty() else "enabled",label])
	if finish_button!=null:check(finish_button.tooltip_text==expected,"BondGoalDo tooltip is the reason (%s): %s"%[label,finish_button.tooltip_text])

## Cost rows: exactly the given items, text 名稱 持有／需要, red only when short.
func cost_is(rows:Dictionary,label:String)->void:
	var box:=control("BondGoalCost")
	var shown:=PackedStringArray()
	if box!=null and box.is_visible_in_tree():
		for child in box.get_children():
			if (child as Control).is_visible_in_tree():shown.append(str(child.name))
	check(shown.size()==rows.size(),"Cost rows %s (%s): %s"%[str(rows.keys()),label,", ".join(shown)])
	for item:String in rows:
		var row:=control("BondGoalCost_"+item)
		var text_label:=first_label(row)
		var have:=held(item)
		var want:=int(rows[item])
		var text:="%s %d／%d"%[str(World.NAMES[item]),have,want]
		check(text_label!=null and text_label.text==text,"Cost row reads %s (%s): %s"%[text,label,text_label.text if text_label else "?"])
		if text_label==null:continue
		var red:=text_label.has_theme_color_override("font_color") and text_label.get_theme_color("font_color")==WARN
		check(red==(have<want),"Cost row %s %s (%s)"%[item,"red when short" if have<want else "not red when enough",label])

## The server's label for a need of this player (known_three carries 「（目前 n 位）」).
func need_label(need:String)->String:
	return Goals.need_label(need,w.state,id)

func need_reason(need:String)->String:
	return "要先「%s」。"%need_label(need)

## One BondGoalNeed_<id> line inside a visible BondGoalNeeds: ✓／○ text, warn only when unmet.
func need_line_is(need:String,met:bool,label:String)->void:
	var box:=control("BondGoalNeeds")
	check(box!=null and box.is_visible_in_tree(),"BondGoalNeeds shown (%s)"%label)
	var row:=control("BondGoalNeed_"+need) as Label
	var text:=("✓ " if met else "○ ")+"要先：%s"%need_label(need)
	check(row!=null and box!=null and box.is_ancestor_of(row) and row.is_visible_in_tree() and row.text==text,"Need line reads %s (%s): %s"%[text,label,row.text if row else "?"])
	if row==null:return
	var warn:=row.has_theme_color_override("font_color") and row.get_theme_color("font_color")==WARN
	check(warn==(not met),"Need line %s %s (%s)"%[need,"in the warning colour when unmet" if not met else "not warn-coloured when met",label])

## BondGoalNeeds is placed before BondGoalCost in the same body.
func needs_before_cost(label:String)->void:
	var box:=control("BondGoalNeeds")
	var cost:=control("BondGoalCost")
	check(box!=null and cost!=null and box.get_parent()==cost.get_parent() and box.get_index()<cost.get_index(),"BondGoalNeeds sits before BondGoalCost (%s)"%label)

func short_text(item:String,want:int)->String:
	return "還差%s %d／%d。"%[str(World.NAMES[item]),held(item),want]

func place_of(resident:String)->String:
	return str(Bond.LOCAL_PLACES[resident]) if Bond.LOCAL_PLACES.has(resident) else str(World.REGIONS.label(str(World.bond_place(app.session.snapshot,resident)[0])))

func away_text(resident:String)->String:
	return "要站在%s身邊（%s）才能一起做。"%[npc(resident),place_of(resident)]

## Batch 3: the 補領 button's away reason.
func claim_away_text(resident:String)->String:
	return "要站在%s身邊（%s）才能領取。"%[npc(resident),place_of(resident)]

func keepsake_name(kind:String)->String:
	return str(Goals.KEEPSAKES[kind].name)

func claimed_text(kind:String)->String:
	return "紀念小物：%s（已放進背包；按 %s 打開家園工坊，在「生活」頁可以擺到家園）"%[keepsake_name(kind),str(app.binding_label("build_menu"))]

func unclaimed_text(kind:String)->String:
	return "紀念小物：%s（還沒領）"%keepsake_name(kind)

## The keepsake entry of a resident_goals summary row ({} when missing).
func keepsake_in(goals:Variant,resident:String,stage:int)->Dictionary:
	if not goals is Dictionary:return {}
	var own:Variant=(goals as Dictionary).get(resident)
	if not own is Dictionary:return {}
	var row:Variant=(own as Dictionary).get(str(stage))
	if not row is Dictionary:return {}
	var found:Variant=(row as Dictionary).get("keepsake")
	return found if found is Dictionary else {}

## Own snapshot: exactly the 12 keepsake goals carry "keepsake" {"kind","item","name","claimed"}.
func snapshot_keepsakes_ok(claimed:bool,label:String)->void:
	var ours:Variant=app.session.snapshot.get("resident_goals")
	var with_keepsake:=0
	for pair:Array in all_goals():
		var resident:=str(pair[0])
		var stage:=int(pair[1])
		var kind:=Goals.keepsake_kind(resident,stage)
		var found:Variant=Tasks.goal_state(app,resident,stage).get("keepsake")
		if kind.is_empty():
			check(found==null,"No keepsake entry on %s %d (%s)"%[resident,stage,label])
			continue
		with_keepsake+=1
		var entry:=keepsake_in(ours,resident,stage)
		var ok:bool=str(entry.get("kind",""))==kind and str(entry.get("item",""))==Goals.keepsake_item(kind) and str(entry.get("name",""))==keepsake_name(kind) and entry.get("claimed")==claimed and entry.size()==4
		check(ok,"Snapshot keepsake of %s %d is {%s, claimed %s} (%s): %s"%[resident,stage,kind,str(claimed),label,str(entry)])
	check(with_keepsake==17,"Seventeen snapshot rows carry a keepsake (%s): %d"%[label,with_keepsake])

## Done page keepsake part. Keepsake goal: BondGoalKeepsake row (32×32 icon + text) inside
## BondGoalDone and no old 紀念 line; claimed → no claim controls; unclaimed → BondGoalClaim
## in BondGoalActions. Other goals: the old 紀念 line and none of the batch 3 nodes.
func keepsake_done_ok(resident:String,stage:int,claimed:bool,label:String)->void:
	var entry:=entry_of(resident,stage)
	var kind:=Goals.keepsake_kind(resident,stage)
	var done:=control("BondGoalDone")
	var old:="紀念：%s%s"%[str(entry.keepsake),"" if resident=="milu" and stage==2 else OLD_KEEPSAKE_TAIL]
	if kind.is_empty():
		if resident=="aru" and stage==2:old="紀念：%s。師父的長椅已加入家園工坊。"%entry.keepsake
		var old_line:=find_label("已解鎖休息站便攜箱圖樣。到工作台用木板 4、纖維 2 製作，再從建造目錄放置。" if resident=="bobo" and stage==3 else old)
		if resident=="lingpopo" and stage<=2:
			var history:=control("LingpopoHistoryPage") as Button
			check(history!=null and done!=null and done.is_ancestor_of(history) and history.text=="閱讀"+str(entry.keepsake),"Done page opens the correct history page (%s)"%label)
		elif resident=="nuannuan" and stage==3:
			var wardrobe:=control("NuannuanGuestWardrobePattern") as Button
			check(wardrobe!=null and done!=null and done.is_ancestor_of(wardrobe),"Done page links to the guest wardrobe (%s)"%label)
		else:
			check(old_line!=null and done!=null and done.is_ancestor_of(old_line),"Done page keeps 「%s」 (%s)"%[old,label])
		for name:String in ["BondGoalKeepsake","BondGoalKeepsakeText","BondGoalClaim","BondGoalClaimReason"]:
			check(control(name)==null,"No %s without a keepsake (%s)"%[name,label])
		return
	check(not texts().contains(OLD_KEEPSAKE_TAIL),"Old 紀念 line replaced by the keepsake row (%s)"%label)
	var row:=control("BondGoalKeepsake")
	check(row!=null and done!=null and done.is_ancestor_of(row) and row.is_visible_in_tree(),"BondGoalKeepsake row inside BondGoalDone (%s)"%label)
	var icon:TextureRect=null
	if row!=null:
		for child in row.get_children():
			if child is TextureRect:
				icon=child as TextureRect
				break
	check(icon!=null and icon.texture!=null,"Keepsake icon has a texture (%s)"%label)
	if icon!=null and icon.texture!=null:
		check(icon.texture.get_size()==Vector2(32,32),"Keepsake icon texture is 32×32 (%s): %s"%[label,str(icon.texture.get_size())])
		check(icon.custom_minimum_size==Vector2(32,32) and absf(icon.size.x-32.0)<=0.5,"Keepsake icon shown at 32 px (%s): %s"%[label,str(icon.size)])
		check(visible(icon) and inside_modal(icon),"Keepsake icon fully on view inside the modal (%s)"%label)
	var text:=control("BondGoalKeepsakeText") as Label
	var want:=claimed_text(kind) if claimed else unclaimed_text(kind)
	check(text!=null and row!=null and row.is_ancestor_of(text) and text.is_visible_in_tree() and text.text==want,"Keepsake text reads 「%s」 (%s): %s"%[want,label,text.text if text else "?"])
	if text!=null:check(not_cut(text),"Keepsake text not cut (%s)"%label)
	var claim:=control("BondGoalClaim") as Button
	if claimed:
		check(claim==null,"No BondGoalClaim once claimed (%s)"%label)
		check(control("BondGoalClaimReason")==null,"No BondGoalClaimReason once claimed (%s)"%label)
	else:
		check(text!=null and text.text.contains("還沒領"),"Unclaimed text says 還沒領 (%s)"%label)
		var actions:=control("BondGoalActions")
		check(claim!=null and claim.text=="領取紀念小物" and actions!=null and actions.is_ancestor_of(claim) and claim.is_visible_in_tree(),"BondGoalClaim 領取紀念小物 in BondGoalActions (%s)"%label)
		check(control("BondGoalClaimReason")!=null,"BondGoalClaimReason present while unclaimed (%s)"%label)

func no_open_controls(label:String)->void:
	for name in ["BondGoalOptions","BondGoalSteps","BondGoalNeeds","BondGoalDo","BondGoalCost","BondGoalReason"]:
		check(control(name)==null,"Done page has no %s (%s)"%[name,label])

## Press BondGoalDo for real and check charge + world + snapshot.
## Batch 3: a keepsake goal also adds 1 "<kind>_kit" (every other kit unchanged).
func complete(resident:String,stage:int,spent:Dictionary,choice:String,label:String)->void:
	var kind:=Goals.keepsake_kind(resident,stage)
	var kit:=Goals.keepsake_item(kind) if not kind.is_empty() else ""
	var before:={}
	for item:String in goal_items():before[item]=held(item)
	for item:String in Goals.keepsake_items():before[item]=held(item)
	var title:=str(entry_of(resident,stage).title)
	if not await press("BondGoalDo",true):return
	check(not is_instance_valid(app.modal),"BondGoalDo closes the page (%s)"%label)
	check(toast_text().contains(title) and toast_text().contains(str(entry_of(resident,stage).keepsake)),"Toast tells 〈%s〉 is done (%s): %s"%[title,label,toast_text()])
	for item:String in before:
		var delta:=-int(spent.get(item,0))+(1 if item==kit else 0)
		check(held(item)==int(before[item])+delta,"%s changes by %d (%s): %d -> %d"%[item,delta,label,int(before[item]),held(item)])
	if kind.is_empty():
		check(not toast_text().contains(KIT_MESSAGE),"No 紀念小物 line for a goal without one (%s)"%label)
		check(not person().has(Goals.KEEPSAKE_KEY),"No keepsake record written (%s)"%label)
	else:
		check(toast_text().contains(KIT_MESSAGE),"Toast says the 紀念小物 went into the bag (%s): %s"%[label,toast_text()])
		check(Goals.keepsake_claimed(person(),kind),"World records %s claimed (%s)"%[kind,label])
		check(Tasks.goal_keepsake(app,resident,stage).get("claimed")==true,"Snapshot says %s claimed (%s): %s"%[kind,label,str(Tasks.goal_keepsake(app,resident,stage))])
	check(world_done(resident).get(stage,"?")==choice,"World records %s %d with choice 「%s」 (%s): %s"%[resident,stage,choice,label,str(world_done(resident))])
	check(state_of(resident,stage)=="done" and choice_of(resident,stage)==choice,"Snapshot says done with choice 「%s」 (%s): %s"%[choice,label,str(Tasks.goal_state(app,resident,stage))])

## Reopen through BondGoalOpen (now ✓) and read the done page.
func done_page_ok(resident:String,stage:int,label:String)->void:
	if not await open_events(resident,stage-1):return
	var open:=control("BondGoalOpen") as Button
	check(open!=null and open.text.begins_with("✓ "),"BondGoalOpen shows ✓ after completion (%s)"%label)
	if not await press_button(open,"BondGoalOpen done "+label):return
	check(goal_open(resident,stage),"Done page opens (%s)"%label)
	var entry:=entry_of(resident,stage)
	var done:=control("BondGoalDone")
	check(done!=null and done.is_visible_in_tree(),"BondGoalDone shown (%s)"%label)
	var wanted:Array=["✓ 已經一起完成"]
	for quote in entry.quote:wanted.append("「%s」"%str(quote))
	var picked:=Goals.option(entry,choice_of(resident,stage))
	if not picked.is_empty():wanted.append("當時選的是：%s"%str(picked.label))
	for text:String in wanted:
		var l:=find_label(text)
		check(l!=null and done!=null and done.is_ancestor_of(l),"Done page shows 「%s」 (%s)"%[text,label])
	if picked.is_empty():check(not texts().contains("當時選的是"),"No 當時選的是 line without options (%s)"%label)
	# 紀念: old line for the 16 goals without a 紀念小物; claimed keepsake row for the 12.
	keepsake_done_ok(resident,stage,true,label)
	no_open_controls(label)
	page_fits("done %s %d %s"%[resident,stage,label])
	check(root.gui_get_focus_owner()==control("BondGoalBack"),"Done page focuses BondGoalBack (%s)"%label)
	await close()

func common_open_ok(resident:String,stage:int,label:String)->void:
	var entry:=entry_of(resident,stage)
	var task:=control("BondGoalTask") as Label
	check(task!=null and task.text==str(entry.task) and task.autowrap_mode!=TextServer.AUTOWRAP_OFF,"BondGoalTask shows the task, wrapped (%s)"%label)
	check((control("BondGoalOptions")!=null)==entry.has("options"),"BondGoalOptions only with options (%s)"%label)
	check((control("BondGoalSteps")!=null)==entry.has("steps"),"BondGoalSteps only with steps (%s)"%label)
	check((control("BondGoalNeeds")!=null)==entry.has("needs"),"BondGoalNeeds only with needs (%s)"%label)
	if entry.has("needs"):
		needs_before_cost(label)
		var box:=control("BondGoalNeeds")
		var shown:=0
		if box!=null:
			for child in box.get_children():
				if (child as Control).is_visible_in_tree():shown+=1
		check(shown==(entry.needs as Array).size(),"One need line per need (%s): %d"%[label,shown])
	check(control("BondGoalDone")==null,"Open page has no BondGoalDone (%s)"%label)
	var back:=control("BondGoalBack") as Button
	check(back!=null and back.text=="回到關係事件","BondGoalBack reads 回到關係事件 (%s)"%label)
	var finish_button:=control("BondGoalDo") as Button
	check(finish_button!=null and finish_button.text==("敲響風鈴" if resident=="lingpopo" and stage==4 else "一起完成"),"BondGoalDo labels the action (%s)"%label)
	if entry.has("options"):
		for option:Dictionary in entry.options:
			var b:=control("BondGoalOption_"+str(option.id)) as Button
			var text:=str(option.label)
			var own:Dictionary=option.get("items",{})
			if not own.is_empty():text+="（%s）"%Tasks.goal_items_text(own)
			check(b!=null and b.toggle_mode and b.text==text,"Option %s reads %s (%s): %s"%[str(option.id),text,label,b.text if b else "?"])
			check(b!=null and not b.button_pressed,"Option %s not preselected (%s)"%[str(option.id),label])
	if entry.has("steps"):
		for i in range(Goals.STEP_COUNT):
			var step:=control("BondGoalStep_%d"%i) as Button
			check(step!=null and step.text==str(entry.steps[i]) and not step.disabled,"Step %d reads %s, enabled (%s)"%[i,str(entry.steps[i]),label])
		var reset:=control("BondGoalStepsReset") as Button
		check(reset!=null and reset.text=="重來","BondGoalStepsReset reads 重來 (%s)"%label)

func option_pressed_only(entry:Dictionary,chosen:String,label:String)->void:
	for option:Dictionary in entry.options:
		var b:=control("BondGoalOption_"+str(option.id)) as Button
		check(b!=null and b.button_pressed==(str(option.id)==chosen),"Option %s %s (%s)"%[str(option.id),"pressed" if str(option.id)==chosen else "not pressed",label])

# ---------------------------------------------------------------- flows --

## 米露 1: pure deliver. Far first (standing reason wins), then short, then ready.
func milu_deliver_flow(label:String)->void:
	set_bonds();set_done({});stock({})
	await stand("milu",true)
	if not await open_goal("milu",1,"milu1 far "+label):return
	common_open_ok("milu",1,"milu1 "+label)
	reason_is(away_text("milu"),"milu1 far "+label)
	cost_is({"soup":1},"milu1 far "+label)
	page_fits("milu1 far "+label)
	check(root.gui_get_focus_owner()==control("BondGoalBack"),"Nothing actionable: focus on BondGoalBack (milu1 %s)"%label)
	# Walk over (preset teleport + snapshot): the open page refreshes in place.
	await stand("milu")
	check(goal_open("milu",1),"Page stays open across the snapshot (milu1 %s)"%label)
	reason_is(short_text("soup",1),"milu1 short "+label)
	stock({"soup":1})
	await refresh()
	cost_is({"soup":1},"milu1 stocked "+label)
	reason_is("","milu1 ready "+label)
	await complete("milu",1,{"soup":1},"","milu1 "+label)
	await done_page_ok("milu",1,"milu1 "+label)

## 波波 2 (金瓜石): options + base items.
func bobo_options_flow(label:String)->void:
	set_bonds();set_done({});stock({"copper_joint":2,"plank":1})
	await stand("bobo")
	if not await open_goal("bobo",2,"bobo2 "+label):return
	var entry:=entry_of("bobo",2)
	common_open_ok("bobo",2,"bobo2 "+label)
	check(root.gui_get_focus_owner()==control("BondGoalOption_entrance"),"First option has focus (bobo2 %s)"%label)
	reason_is("先選一個做法。","bobo2 no option "+label)
	cost_is({"copper_joint":2,"plank":2},"bobo2 no option "+label)
	page_fits("bobo2 "+label)
	if not await press("BondGoalOption_siding"):return
	option_pressed_only(entry,"siding","bobo2 siding "+label)
	reason_is(short_text("plank",2),"bobo2 short plank "+label)
	if not await press("BondGoalOption_shed"):return
	option_pressed_only(entry,"shed","bobo2 shed "+label)
	if not await press("BondGoalOption_siding"):return
	stock({"copper_joint":2,"plank":2})
	await refresh()
	option_pressed_only(entry,"siding","bobo2 kept after snapshot "+label)
	reason_is("","bobo2 ready "+label)
	await complete("bobo",2,{"copper_joint":2,"plank":2},"siding","bobo2 "+label)
	await done_page_ok("bobo",2,"bobo2 "+label)

## 米露 3: each option carries its own cost.
func milu_cost_flow(label:String)->void:
	set_bonds();set_done({});stock({"soup":2,"carrot_soup":1})
	await stand("milu")
	if not await open_goal("milu",3,"milu3 "+label):return
	common_open_ok("milu",3,"milu3 "+label)
	cost_is({},"milu3 no option "+label)
	reason_is("先選一個做法。","milu3 no option "+label)
	if not await press("BondGoalOption_carrot_soup"):return
	cost_is({"carrot_soup":2},"milu3 carrot "+label)
	reason_is(short_text("carrot_soup",2),"milu3 carrot "+label)
	page_fits("milu3 carrot "+label)
	if not await press("BondGoalOption_soup"):return
	cost_is({"soup":2},"milu3 soup "+label)
	check(control("BondGoalCost_carrot_soup")==null or not control("BondGoalCost_carrot_soup").is_visible_in_tree(),"Carrot soup row gone after switching (milu3 %s)"%label)
	reason_is("","milu3 soup "+label)
	await complete("milu",3,{"soup":2},"soup","milu3 "+label)
	await done_page_ok("milu",3,"milu3 "+label)

## 阿榆 2: free-order steps + items, with 重來.
func aru_steps_flow(label:String)->void:
	set_bonds();set_done({});stock({"hardwood":4})
	await stand("aru")
	if not await open_goal("aru",2,"aru2 "+label):return
	var entry:=entry_of("aru",2)
	common_open_ok("aru",2,"aru2 "+label)
	check(root.gui_get_focus_owner()==control("BondGoalStep_0"),"First step has focus (aru2 %s)"%label)
	reason_is("三個步驟都要做過一次。","aru2 no steps "+label)
	cost_is({"hardwood":4},"aru2 "+label)
	page_fits("aru2 "+label)
	if not await press("BondGoalStep_2"):return
	if not await press("BondGoalStep_0"):return
	var s2:=control("BondGoalStep_2") as Button
	var s0:=control("BondGoalStep_0") as Button
	check(s2!=null and s2.text=="1. "+str(entry.steps[2]) and s2.disabled,"Step 2 marked 1. and disabled (aru2 %s)"%label)
	check(s0!=null and s0.text=="2. "+str(entry.steps[0]) and s0.disabled,"Step 0 marked 2. and disabled (aru2 %s)"%label)
	reason_is("三個步驟都要做過一次。","aru2 two steps "+label)
	if not await press("BondGoalStepsReset"):return
	for i in range(Goals.STEP_COUNT):
		var step:=control("BondGoalStep_%d"%i) as Button
		check(step!=null and step.text==str(entry.steps[i]) and not step.disabled,"重來 clears step %d (aru2 %s)"%[i,label])
	for i in [1,2,0]:
		if not await press("BondGoalStep_%d"%i):return
	reason_is("","aru2 ready "+label)
	check(root.gui_get_focus_owner()==control("BondGoalDo"),"After the third step focus moves to BondGoalDo (aru2 %s)"%label)
	page_fits("aru2 ready "+label)
	await complete("aru",2,{"hardwood":4},"","aru2 "+label)
	await done_page_ok("aru",2,"aru2 "+label)

## 鈴婆婆 2: fixed order (△ ○ □ = steps 1,0,2).
func lingpopo_order_flow(label:String)->void:
	set_bonds();set_done({});stock({})
	await stand("lingpopo")
	if not await open_goal("lingpopo",2,"lingpopo2 "+label):return
	var entry:=entry_of("lingpopo",2)
	common_open_ok("lingpopo",2,"lingpopo2 "+label)
	cost_is({},"lingpopo2 "+label)
	for i in [0,1,2]:
		if not await press("BondGoalStep_%d"%i):return
	reason_is("順序不太對，再看一次圖示。","lingpopo2 wrong order "+label)
	for i in range(Goals.STEP_COUNT):
		var step:=control("BondGoalStep_%d"%i) as Button
		check(step!=null and step.text==str(entry.steps[i]) and not step.disabled,"Wrong order clears step %d (lingpopo2 %s)"%[i,label])
	page_fits("lingpopo2 wrong order "+label)
	var order:Array=entry.order
	for i in order:
		if not await press("BondGoalStep_%d"%int(i)):return
	reason_is("","lingpopo2 right order "+label)
	await complete("lingpopo",2,{},"","lingpopo2 "+label)
	await done_page_ok("lingpopo",2,"lingpopo2 "+label)

## 洛洛 3: options only, no cost.
func luoluo_options_flow(label:String)->void:
	set_bonds();set_done({});stock({})
	await stand("luoluo")
	if not await open_goal("luoluo",3,"luoluo3 "+label):return
	common_open_ok("luoluo",3,"luoluo3 "+label)
	cost_is({},"luoluo3 "+label)
	reason_is("先選一個做法。","luoluo3 "+label)
	if not await press("BondGoalOption_letter"):return
	reason_is("","luoluo3 letter "+label)
	await complete("luoluo",3,{},"letter","luoluo3 "+label)
	await done_page_ok("luoluo",3,"luoluo3 "+label)

## 阿榆 1: own_bed unmet → bed written → same page updates in place (✓, reason moves on
## to the wood shortage) → wood topped up → completed through BondGoalDo.
func aru_bed_flow(label:String)->void:
	set_bonds();set_done({});stock({"wood":9})
	await set_needs("own_bed")
	await stand("aru")
	if not await open_goal("aru",1,"aru1 "+label):return
	common_open_ok("aru",1,"aru1 "+label)
	need_line_is("own_bed",false,"aru1 no bed "+label)
	reason_is(need_reason("own_bed"),"aru1 no bed "+label)
	check(reason_text()=="要先「家園裡有一張你放的小床」。","Bed reason wording (aru1 %s): %s"%[label,reason_text()])
	cost_is({"wood":10},"aru1 no bed "+label)
	page_fits("aru1 no bed "+label)
	var page_modal:Variant=app.modal
	set_bed(true)
	await refresh()
	check(is_instance_valid(app.modal) and app.modal==page_modal and goal_open("aru",1),"Same page stays open after the bed snapshot (aru1 %s)"%label)
	check(need_met_in(Tasks.goal_needs(app,"aru",1),"own_bed")==1,"Snapshot says own_bed met (aru1 %s)"%label)
	need_line_is("own_bed",true,"aru1 bed "+label)
	reason_is(short_text("wood",10),"aru1 bed short "+label)
	page_fits("aru1 bed "+label)
	stock({"wood":10})
	await refresh()
	reason_is("","aru1 ready "+label)
	await complete("aru",1,{"wood":10},"","aru1 "+label)
	await done_page_ok("aru",1,"aru1 "+label)
	set_bed(false)

## 洛洛 2: known_three counts 0 → 3 (label 「（目前 n 位）」, capped at 3), no items.
func luoluo_known_flow(label:String)->void:
	set_done({});stock({})
	await set_needs("known_three")
	await stand("luoluo")
	if not await open_goal("luoluo",2,"luoluo2 "+label):return
	common_open_ok("luoluo",2,"luoluo2 "+label)
	cost_is({},"luoluo2 "+label)
	check(need_label("known_three")=="認識洛洛以外的三位居民（目前 0 位）","Label counts 0 (luoluo2 %s): %s"%[label,need_label("known_three")])
	need_line_is("known_three",false,"luoluo2 0 "+label)
	reason_is(need_reason("known_three"),"luoluo2 0 "+label)
	page_fits("luoluo2 0 "+label)
	var page_modal:Variant=app.modal
	var bonds:=strangers()
	var count:=0
	for resident:String in ["aru","milu","bobo","xiaoli"]:
		bonds[resident]=Bond.THRESHOLDS[0]
		count+=1
		set_bonds(bonds)
		await refresh()
		var shown:=mini(count,Goals.KNOWN_NEEDED)
		var tag:="luoluo2 %d %s"%[count,label]
		check(is_instance_valid(app.modal) and app.modal==page_modal and goal_open("luoluo",2),"Same page stays open (%s)"%tag)
		var row:=control("BondGoalNeed_known_three") as Label
		check(row!=null and row.text.contains("（目前 %d 位）"%shown),"Need line shows （目前 %d 位） (%s): %s"%[shown,tag,row.text if row else "?"])
		need_line_is("known_three",count>=Goals.KNOWN_NEEDED,tag)
		reason_is("" if count>=Goals.KNOWN_NEEDED else need_reason("known_three"),tag)
	page_fits("luoluo2 met "+label)
	await complete("luoluo",2,{},"","luoluo2 "+label)
	await done_page_ok("luoluo",2,"luoluo2 "+label)
	set_bonds()

## One need flipped from unmet to met on the open page, then completed (no items):
## 棉棉 4 fair_weather (rainy home day → dry day), 小栗 3 market_round, 鈴婆婆 4 festival_done.
func need_unlock_flow(resident:String,stage:int,need:String,label:String)->void:
	var tag:="%s%d %s"%[resident,stage,label]
	set_bonds();set_done({});stock({})
	await set_needs(need)
	await stand(resident)
	if need=="fair_weather":
		check(Weather.rains(Weather.day_index(float(w.state.time)),"home"),"Home is rainy today (%s)"%tag)
	if not await open_goal(resident,stage,tag):return
	common_open_ok(resident,stage,tag)
	cost_is({},tag)
	need_line_is(need,false,"unmet "+tag)
	reason_is(need_reason(need),"unmet "+tag)
	page_fits("unmet "+tag)
	var page_modal:Variant=app.modal
	if need=="fair_weather":
		await weather(false)
	else:
		set_need(need,true)
		await refresh()
	check(is_instance_valid(app.modal) and app.modal==page_modal and goal_open(resident,stage),"Same page stays open after the need is met (%s)"%tag)
	need_line_is(need,true,"met "+tag)
	reason_is("","met "+tag)
	await complete(resident,stage,{},"",tag)
	await done_page_ok(resident,stage,tag)

## 星禾 3 (蘭陽): glass_crafted unmet AND glass short → the need is the reason; after the
## need is met the item shortage is; then completed.
func xinghe_priority_flow(label:String)->void:
	set_bonds();set_done({});stock({"glass":1,"copper_joint":2})
	await set_needs("glass_crafted")
	await stand("xinghe")
	if not await open_goal("xinghe",3,"xinghe3 "+label):return
	common_open_ok("xinghe",3,"xinghe3 "+label)
	cost_is({"glass":2,"copper_joint":2},"xinghe3 "+label)
	need_line_is("glass_crafted",false,"xinghe3 unmet "+label)
	reason_is(need_reason("glass_crafted"),"xinghe3 need before items "+label)
	page_fits("xinghe3 unmet "+label)
	set_need("glass_crafted",true)
	await refresh()
	need_line_is("glass_crafted",true,"xinghe3 met "+label)
	reason_is(short_text("glass",2),"xinghe3 items after need "+label)
	stock({"glass":2,"copper_joint":2})
	await refresh()
	reason_is("","xinghe3 ready "+label)
	await complete("xinghe",3,{"glass":2,"copper_joint":2},"","xinghe3 "+label)
	await done_page_ok("xinghe",3,"xinghe3 "+label)

## Needs rows of a summary row (empty when missing).
func rows_of(goals:Variant,resident:String,stage:int)->Array:
	if not goals is Dictionary:return []
	var own:Variant=(goals as Dictionary).get(resident)
	if not own is Dictionary:return []
	var row:Variant=(own as Dictionary).get(str(stage))
	if not row is Dictionary:return []
	var found:Variant=(row as Dictionary).get("needs")
	return found if found is Array else []

## 1 met, 0 unmet, -1 no such row.
func need_met_in(rows:Array,need:String)->int:
	for row:Variant in rows:
		if row is Dictionary and str(row.get("id",""))==need:return 1 if row.get("met",false)==true else 0
	return -1

func need_label_in(rows:Array,need:String)->String:
	for row:Variant in rows:
		if row is Dictionary and str(row.get("id",""))==need:return str(row.get("label",""))
	return ""

## Another player's snapshot (real Session._send_snapshot with peers {1:OTHER,2:host})
## has OTHER's own needs rows, never the host's, and no host goal/bond/market record.
func privacy_check()->void:
	set_bonds();stock({})
	# PRESET (batch 3): 波波 1 done and its 紀念小物 claimed, so the host HAS a
	# bond_keepsakes record that must not leak (波波 1 has no needs: the rows below are kept).
	set_done({"bobo":{"1":""}})
	set_keepsakes(["keepsake_bobo"])
	await set_needs("")
	await stand("luoluo")  # home, so the host is visible in OTHER's home snapshot
	await close()
	var mine:=id.sha256_text().left(16)
	var ours:Variant=app.session.snapshot.get("resident_goals")
	var saved:Dictionary=(app.session.peers as Dictionary).duplicate()
	app.session.peers={1:OTHER,2:id}
	app.session._send_snapshot(1)
	var theirs:Dictionary=(app.session.snapshot as Dictionary).duplicate(true)
	app.session.peers=saved
	await refresh()
	check(str(app.session.own_id)==mine,"Host snapshot restored after the OTHER snapshot")
	var their_goals:Variant=theirs.get("resident_goals")
	check(their_goals is Dictionary and not (their_goals as Dictionary).is_empty(),"OTHER snapshot carries resident_goals")
	for pair:Array in [["aru",1,"own_bed"],["xinghe",3,"glass_crafted"],["xiaoli",3,"market_round"],["luoluo",2,"known_three"]]:
		var resident:=str(pair[0])
		var stage:=int(pair[1])
		var need:=str(pair[2])
		check(need_met_in(rows_of(ours,resident,stage),need)==1,"Host row %s %d says %s met"%[resident,stage,need])
		check(need_met_in(rows_of(their_goals,resident,stage),need)==0,"OTHER row %s %d says %s unmet (own record, not the host's)"%[resident,stage,need])
	var their_label:=need_label_in(rows_of(their_goals,"luoluo",2),"known_three")
	check(their_label==Goals.need_label("known_three",w.state,OTHER) and their_label!=need_label_in(rows_of(ours,"luoluo",2),"known_three"),"OTHER known_three label is OTHER's own count: %s"%their_label)
	var players:Variant=theirs.get("players")
	var host_row:Variant=players.get(mine) if players is Dictionary else null
	check(host_row is Dictionary,"Host is visible in the OTHER snapshot (privacy check is meaningful)")
	if host_row is Dictionary:
		for key:String in [Goals.RECORD_KEY,Goals.KEEPSAKE_KEY,"bonds","market","resident_goals","needs"]:
			check(not (host_row as Dictionary).has(key),"OTHER snapshot has no host %s"%key)
	check(not str(their_goals).contains(id) and not str(their_goals).contains(mine),"OTHER resident_goals never names the host")
	# Batch 3: the host's claimed keepsake stays in the host's own summary only.
	check(Goals.keepsake_claimed(person(),"keepsake_bobo"),"Host world record has keepsake_bobo (privacy check is meaningful)")
	check(keepsake_in(ours,"bobo",1).get("claimed")==true,"Host snapshot says keepsake_bobo claimed")
	check(keepsake_in(their_goals,"bobo",1).get("claimed")==false,"OTHER snapshot says keepsake_bobo unclaimed (own record): %s"%str(keepsake_in(their_goals,"bobo",1)))
	check(not str(theirs).contains(Goals.KEEPSAKE_KEY),"OTHER snapshot contains no bond_keepsakes anywhere")
	set_done({})
	await refresh()

## Back / Esc / focus.
func navigation_flow(label:String)->void:
	set_bonds();set_done({});stock({})
	await stand("aru")
	if not await open_goal("aru",2,"nav "+label):return
	if await press("BondGoalBack"):
		check(is_instance_valid(app.modal) and find_label("阿榆的關係事件")!=null,"BondGoalBack returns to 阿榆的關係事件 (%s)"%label)
		var tab:=control("BondEventTab_1") as Button
		check(tab!=null and tab.button_pressed,"Back lands on the 熟悉 tab (%s)"%label)
		check(control("BondGoalOpen")!=null,"Back page offers BondGoalOpen again (%s)"%label)
	if not await open_goal("aru",2,"nav esc "+label):return
	var esc:=InputEventKey.new()
	esc.keycode=KEY_ESCAPE;esc.physical_keycode=KEY_ESCAPE;esc.pressed=true
	app._input(esc)
	await settle()
	check(not is_instance_valid(app.modal),"Esc closes the goal page (%s)"%label)

## Every goal, open (and with the last option chosen) and done, at this size.
## Every prerequisite is met first (needs lines read ✓); see needs_sweep for unmet.
func layout_sweep(label:String)->void:
	set_bonds();set_done({});stock({})
	await set_needs("")
	await stand("aru",true)
	check(all_goals().size()==48,"Sweep covers 48 goals (%s)"%label)
	for pair:Array in all_goals():
		var resident:=str(pair[0])
		var stage:=int(pair[1])
		var entry:=entry_of(resident,stage)
		await close()
		Tasks.bond_goal(app,resident,stage)
		await settle()
		check(goal_open(resident,stage),"Goal page opens for %s %d (%s)"%[resident,stage,label])
		check((control("BondGoalNeeds")!=null)==entry.has("needs"),"BondGoalNeeds only with needs (sweep %s %d %s)"%[resident,stage,label])
		for need:String in entry.get("needs",[]):
			need_line_is(need,true,"sweep met %s %d %s"%[resident,stage,label])
		if entry.has("needs"):needs_before_cost("sweep %s %d %s"%[resident,stage,label])
		page_fits("open %s %d %s"%[resident,stage,label])
		var options:Array=entry.get("options",[])
		if not options.is_empty():
			var last:=control("BondGoalOption_"+str(options.back().id)) as Button
			if last!=null:
				last.pressed.emit()
				await settle()
				page_fits("open %s %d option %s %s"%[resident,stage,str(options.back().id),label])
		if entry.has("steps"):
			for i in range(2):
				var step:=control("BondGoalStep_%d"%i) as Button
				if step!=null:step.pressed.emit()
			await settle()
			page_fits("open %s %d two steps %s"%[resident,stage,label])
	var all_done:={}
	for pair:Array in all_goals():
		var resident:=str(pair[0])
		var entry:=entry_of(resident,int(pair[1]))
		var options:Array=entry.get("options",[])
		var own:Dictionary=all_done.get(resident,{})
		own[str(pair[1])]=str(options.back().id) if not options.is_empty() else ""
		all_done[resident]=own
	set_done(all_done)
	set_keepsakes(Goals.KEEPSAKE_ORDER)  # PRESET: all 12 紀念小物 claimed
	await refresh()
	snapshot_keepsakes_ok(true,"all claimed "+label)
	var with_keepsake:=0
	for pair:Array in all_goals():
		var resident:=str(pair[0])
		var stage:=int(pair[1])
		await close()
		Tasks.bond_goal(app,resident,stage)
		await settle()
		check(control("BondGoalDone")!=null,"Done page for %s %d (%s)"%[resident,stage,label])
		no_open_controls("sweep done %s %d %s"%[resident,stage,label])
		keepsake_done_ok(resident,stage,true,"sweep done %s %d %s"%[resident,stage,label])
		if not Goals.keepsake_kind(resident,stage).is_empty():with_keepsake+=1
		page_fits("done %s %d %s"%[resident,stage,label])
	check(with_keepsake==17,"Done sweep shows 17 keepsake rows (%s): %d"%[label,with_keepsake])
	await close()
	set_done({})

## Every goal with needs, standing next to the resident with its items in hand and that
## one need unmet: the need is the reason (text and tooltip), the ○ line is warn-coloured.
func needs_sweep(label:String)->void:
	var swept:=0
	for pair:Array in all_goals():
		var resident:=str(pair[0])
		var stage:=int(pair[1])
		var entry:=entry_of(resident,stage)
		if not entry.has("needs"):continue
		for need:String in entry.needs:
			var tag:="need unmet %s %d %s %s"%[resident,stage,need,label]
			set_bonds();set_done({});stock(Goals.cost(entry,""))
			var dock_before:=int(w.state.get("dock_stage",0))
			if resident=="achao":w.state.dock_stage=1
			await set_needs(need)
			await stand(resident)
			await close()
			Tasks.bond_goal(app,resident,stage)
			await settle()
			check(goal_open(resident,stage),"Goal page opens (%s)"%tag)
			page_fits(tag)
			need_line_is(need,false,tag)
			needs_before_cost(tag)
			reason_is(need_reason(need),tag)
			if resident=="achao":w.state.dock_stage=dock_before
			swept+=1
	check(swept==29,"Twenty-nine prerequisites swept unmet (%s): %d"%[label,swept])
	await close()
	set_bonds()
	await set_needs("")

## Batch 3 補領: a keepsake goal finished before batch 3. PRESET: the done record is
## written directly WITHOUT player.bond_keepsakes. Far → BondGoalClaim disabled with the
## reason; beside → enabled; the real BondGoalClaim press goes through
## Session.perform(CLAIM_ACTION) → World → snapshot and the open page is rebuilt as claimed.
func claim_flow(resident:String,stage:int,label:String)->void:
	var tag:="claim %s%d %s"%[resident,stage,label]
	var entry:=entry_of(resident,stage)
	var kind:=Goals.keepsake_kind(resident,stage)
	check(not kind.is_empty(),"%s %d has a 紀念小物 (%s)"%[resident,stage,tag])
	if kind.is_empty():return
	var kit:=Goals.keepsake_item(kind)
	var options:Array=entry.get("options",[])
	var choice:=""
	if not options.is_empty():
		var last:Dictionary=options.back()
		choice=str(last.id)
	set_bonds();stock({})
	set_done({resident:{str(stage):choice}})  # PRESET: done before batch 3, nothing claimed
	await stand(resident,true)  # PRESET teleport: far
	check(not Goals.keepsake_claimed(person(),kind),"Preset: %s not claimed yet (%s)"%[kind,tag])
	check(Tasks.goal_keepsake(app,resident,stage).get("claimed")==false,"Snapshot says %s unclaimed (%s)"%[kind,tag])
	if not await open_goal(resident,stage,tag):return
	check(control("BondGoalDone")!=null,"Done page shown (%s)"%tag)
	keepsake_done_ok(resident,stage,false,"far "+tag)
	no_open_controls("far "+tag)
	var claim:=control("BondGoalClaim") as Button
	var reason:=control("BondGoalClaimReason") as Label
	var away:=claim_away_text(resident)
	check(claim!=null and claim.disabled,"BondGoalClaim disabled away from %s (%s)"%[npc(resident),tag])
	check(claim!=null and claim.tooltip_text==away,"BondGoalClaim tooltip is the reason (%s): %s"%[tag,claim.tooltip_text if claim else "?"])
	check(reason!=null and reason.is_visible_in_tree() and reason.text==away and reason.text.contains("才能領取"),"Claim reason reads 「%s」 (%s): %s"%[away,tag,reason.text if reason else "?"])
	if reason!=null:check(reason.has_theme_color_override("font_color") and reason.get_theme_color("font_color")==WARN,"Claim reason in the warning colour (%s)"%tag)
	page_fits("unclaimed far "+tag)
	check(root.gui_get_focus_owner()==control("BondGoalBack"),"Away: focus on BondGoalBack (%s)"%tag)
	# Walk over (PRESET teleport + snapshot): the same page refreshes in place.
	var page_modal:Variant=app.modal
	await stand(resident)
	check(is_instance_valid(app.modal) and app.modal==page_modal and goal_open(resident,stage),"Same page stays open after walking over (%s)"%tag)
	claim=control("BondGoalClaim") as Button
	reason=control("BondGoalClaimReason") as Label
	check(claim!=null and not claim.disabled and claim.tooltip_text.is_empty(),"BondGoalClaim enabled beside %s (%s)"%[npc(resident),tag])
	check(reason==null or not reason.is_visible_in_tree(),"Claim reason hidden beside %s (%s)"%[npc(resident),tag])
	keepsake_done_ok(resident,stage,false,"beside "+tag)
	page_fits("unclaimed beside "+tag)
	# Focus order: both focusable, Tab order Claim → Back (checked via find_*_valid_focus;
	# no key presses are simulated).
	var back:=control("BondGoalBack") as Button
	check(claim!=null and claim.focus_mode==Control.FOCUS_ALL and back!=null and back.focus_mode==Control.FOCUS_ALL,"BondGoalClaim and BondGoalBack both focusable (%s)"%tag)
	if claim!=null and back!=null:
		claim.grab_focus()
		await process_frame
		check(root.gui_get_focus_owner()==claim,"BondGoalClaim takes focus (%s)"%tag)
		check(claim.find_next_valid_focus()==back,"Next focus after BondGoalClaim is BondGoalBack (%s)"%tag)
		check(back.find_prev_valid_focus()==claim,"Previous focus before BondGoalBack is BondGoalClaim (%s)"%tag)
	var before:={}
	for item:String in Goals.keepsake_items():before[item]=held(item)
	var record_before:=world_done(resident)
	if not await press("BondGoalClaim",true):return
	for item:String in before:
		var delta:=1 if item==kit else 0
		check(held(item)==int(before[item])+delta,"%s changes by %d after claiming (%s): %d -> %d"%[item,delta,tag,int(before[item]),held(item)])
	check(Goals.keepsake_claimed(person(),kind),"World records %s claimed (%s)"%[kind,tag])
	check(world_done(resident)==record_before,"Claiming leaves the done record alone (%s)"%tag)
	check(Tasks.goal_keepsake(app,resident,stage).get("claimed")==true,"Snapshot says %s claimed (%s)"%[kind,tag])
	check(toast_text().contains(keepsake_name(kind)),"Toast names 「%s」 (%s): %s"%[keepsake_name(kind),tag,toast_text()])
	check(is_instance_valid(app.modal) and goal_open(resident,stage) and control("BondGoalDone")!=null,"Page stays open on the same done goal after claiming (%s)"%tag)
	keepsake_done_ok(resident,stage,true,"claimed "+tag)
	var focus:=root.gui_get_focus_owner()
	var focus_ok:=focus!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(focus) and focus.is_visible_in_tree() and focus.focus_mode!=Control.FOCUS_NONE
	if focus_ok and focus is BaseButton:focus_ok=not (focus as BaseButton).disabled
	check(focus_ok,"Focus lands on a valid control after the rebuild (%s): %s"%[tag,str(focus.name) if focus else "none"])
	page_fits("claimed "+tag)
	# Pressing again is impossible: no button; a DIRECT Tasks.do_goal_claim call and a DIRECT
	# server request both change nothing.
	check(control("BondGoalClaim")==null,"No BondGoalClaim to press again (%s)"%tag)
	Tasks.do_goal_claim(app)
	await settle()
	check(held(kit)==int(before[kit])+1,"Direct do_goal_claim on a claimed page sends nothing (%s): %d"%[tag,held(kit)])
	clear_toast()
	var cell:Vector2i=World.bond_place(app.session.snapshot,resident)[1]
	app.session.perform(Goals.CLAIM_ACTION,cell,"%s:%d"%[resident,stage])
	await settle()
	check(held(kit)==int(before[kit])+1,"Server refuses a second claim (%s): %d"%[tag,held(kit)])
	note("second claim request %s answered: %s"%[tag,toast_text()])
	check(is_instance_valid(app.modal) and goal_open(resident,stage) and control("BondGoalClaim")==null,"Page unchanged after the refused request (%s)"%tag)
	await close()
	set_done({})

## Batch 3 catalog: 12 kinds on the expected goals, names = the goal's keepsake, kit names,
## and the inventory panel's static description/value text for every kit.
func keepsake_catalog_checks()->void:
	check(Goals.KEEPSAKES.size()==17 and Goals.KEEPSAKE_ORDER.size()==17,"Seventeen 紀念小物")
	var with_keepsake:=0
	for pair:Array in all_goals():
		var resident:=str(pair[0])
		var stage:=int(pair[1])
		var kind:=Goals.keepsake_kind(resident,stage)
		var expected:=int(KEEPSAKE_GOALS.get(resident,-1))==stage or (resident in ["aru","achao","xinghe","lingpopo","nuannuan"] and stage==4)
		check((not kind.is_empty())==expected,"%s %d %s a 紀念小物: %s"%[resident,stage,"has" if expected else "has no",kind])
		if kind.is_empty():continue
		with_keepsake+=1
		var kit:=Goals.keepsake_item(kind)
		check(kind==("keepsake_aru_bird" if resident=="aru" and stage==4 else ("keepsake_achao_oar" if resident=="achao" and stage==4 else ("keepsake_xinghe_sign" if resident=="xinghe" and stage==4 else ("keepsake_lingpopo_memorial" if resident=="lingpopo" and stage==4 else ("keepsake_nuannuan_room" if resident=="nuannuan" and stage==4 else "keepsake_"+resident))))) and kit==kind+"_kit","Kind/item naming %s / %s"%[kind,kit])
		check(keepsake_name(kind)==str(entry_of(resident,stage).keepsake),"%s name is the goal's keepsake: %s"%[kind,keepsake_name(kind)])
		check(World.NAMES.has(kit),"Item name exists: "+kit)
		var blurb:=str(Goals.KEEPSAKES[kind].blurb)
		var use:=str(InventoryPanel.use_for(kit))
		check(use.begins_with(blurb) and use.contains("按 B 打開家園工坊") and use.contains("「生活」") and use.contains("擺到家園"),"Inventory description of %s: %s"%[kit,use])
		var value:=str(InventoryPanel.value_for(kit))
		var want:="和%s一起做的事的紀念小物 · 不能出售或交易"%npc(resident)
		check(value==want,"Inventory value text of %s reads %s: %s"%[kit,want,value])
	check(with_keepsake==17 and all_goals().size()-with_keepsake==31,"17 goals with a 紀念小物, 31 without: %d"%with_keepsake)

## 點點 2 in star_garden: printed only (see header).
func garden_note(label:String)->void:
	set_bonds();set_done({});stock({})
	await stand("diandian")
	if not await open_goal("diandian",2,"diandian2 "+label):return
	if not await press("BondGoalOption_cup"):return
	reason_is("","diandian2 client ready "+label)
	if not await press("BondGoalDo",true):return
	note("diandian 2 from star_garden (%s): done=%s toast=%s"%[label,str(state_of("diandian",2)=="done"),toast_text()])
	set_done({})
	await refresh()

# ---------------------------------------------------------------- run --

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("goal-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"一起做的事旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	w.state.picnic=true  # PRESET: 洛洛／鈴婆婆／棉棉 present
	w.add_player(OTHER,"另一位旅人")  # FIXTURE: second, never connected player
	saved_festival=(w.state.festival as Dictionary).duplicate(true)
	saved_market=person().get("market")
	saved_glass=person().get("greenhouse_glass_crafted")
	if saved_market is Dictionary:saved_market=(saved_market as Dictionary).duplicate(true)
	check(Goals.total()==48,"Forty-eight goals")
	for resident:String in PER_RESIDENT:
		check(Goals.GOALS.has(resident) and (Goals.GOALS[resident] as Dictionary).size()==int(PER_RESIDENT[resident]),"%s has %d goals"%[resident,int(PER_RESIDENT[resident])])
	check(PER_RESIDENT.size()==Goals.GOALS.size(),"Every goal resident counted")
	var with_needs:=0
	for pair:Array in all_goals():
		var entry:=entry_of(str(pair[0]),int(pair[1]))
		if entry.has("needs"):
			with_needs+=1
			for need:String in entry.needs:check(Goals.NEEDS.has(need),"Need %s is known (%s %d)"%[need,str(pair[0]),int(pair[1])])
	check(with_needs==28,"Twenty-eight goals have needs: %d"%with_needs)
	for item:String in goal_items():check(World.NAMES.has(item),"Item name exists: "+item)
	keepsake_catalog_checks()
	set_done({})  # PRESET: fresh save, nothing done or claimed
	await refresh()
	snapshot_keepsakes_ok(false,"fresh")
	await privacy_check()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await events_flow(tag)
		await milu_deliver_flow(tag)
		await bobo_options_flow(tag)
		await milu_cost_flow(tag)
		await aru_steps_flow(tag)
		await lingpopo_order_flow(tag)
		await luoluo_options_flow(tag)
		await aru_bed_flow(tag)
		await luoluo_known_flow(tag)
		await need_unlock_flow("mianmian",4,"fair_weather",tag)
		await need_unlock_flow("xiaoli",3,"market_round",tag)
		await need_unlock_flow("lingpopo",4,"festival_done",tag)
		await xinghe_priority_flow(tag)
		await navigation_flow(tag)
		await layout_sweep(tag)
		await needs_sweep(tag)
		# Batch 3 補領 in four regions: 家園, 金瓜石, 蘭陽, 礁溪.
		for pair:Array in [["aru",1],["bobo",1],["xinghe",2],["nuannuan",1]]:
			await claim_flow(str(pair[0]),int(pair[1]),tag)
		await garden_note(tag)
		await close()
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	# Restore the directly written needs prerequisites before the host saves on shutdown.
	set_bed(false)
	w.state.festival=saved_festival
	var p:=person()
	if saved_market is Dictionary:p.market=saved_market
	else:p.erase("market")
	if saved_glass==null:p.erase("greenhouse_glass_crafted")
	else:p.greenhouse_glass_crafted=saved_glass
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
