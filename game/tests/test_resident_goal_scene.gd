extends SceneTree
## T066「一起做的事」native render check at 1024×640 and 1280×800 (run WITHOUT --headless).
## Screenshots go to outputs/居民一起做的事預覽 (or --capture-dir=), named <w>x<h>_<step>.png.
## Same harness as test_resident_bond_garden_scene.gd / test_resident_goal_ui.gd: main.tscn with
## app.village_art_preview=true set by the test itself and an in-process host session.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (talk_day/gift_day 0 are past days);
##  * state.picnic is written true (洛洛／鈴婆婆 present);
##  * player.bonds is written directly: in the events/米露 flow 米露 has points 6 (熟悉,
##    every other resident 24); in all later flows every resident has points 24 (好友);
##  * player.bond_goals is erased at the start of every flow group (and of each size);
##  * the backpack is written directly: every item any goal uses is set to 0, then the
##    amounts each flow needs (米露 1: 0 soup, later topped up to 1 by a preset + snapshot);
##  * the player is teleported by writing region/x/y: 0.9 tile south of the resident's
##    World.bond_place cell ("standing"), or 12/8 tiles further ("far", 米露 only); a travel
##    arrival ribbon (TravelArrival), if the region change made one, is removed from the HUD;
##  * the 關係事件 page is opened with a DIRECT Tasks.bond_events(app,id,tab) call;
##  * the toast is hidden before each capture.
##  * batch 2 prerequisites ("needs") are established by DIRECT world-record writes, each undone
##    at the end of its flow (so the second size starts from the same state):
##      - own_bed (阿榆 1): state.objects[World.key(cell)]={"type":"bed","owner":<own token>,
##        "items":{}} written at a free cell 2 tiles south-east of 阿榆's cell (no build action,
##        no wood charged for the bed); erased again at the end of aru1_flow;
##      - known_three (洛洛 2): player.bonds rewritten by set_bonds() with every resident other
##        than 洛洛／阿榆／米露 at points 0 ("目前 2 位"), then 波波 back to 24 ("目前 3 位");
##      - glass_crafted (星禾 3): player.greenhouse_glass_crafted written false, then true;
##        the previous value (or absence) is restored afterwards;
##      - festival_done (鈴婆婆 4): state.festival.round written 1 with active false; the
##        previous festival dictionary is restored afterwards.
## REALLY PRESSED (emitting `pressed` on the real buttons):
##  * BondEventTab_n (events tabs), BondGoalOpen (events -> goal page, open and ✓ done),
##    BondGoalOption_<id>, BondGoalStep_n and BondGoalDo; BondGoalDo for 米露 1, 波波 2 and
##    阿榆 1 goes through the real Session.perform("resident_goal") -> World -> snapshot trip
##    (阿榆 1 therefore also passes the server-side own_bed check), and the resulting done
##    pages are reached again through the real ✓ BondGoalOpen.
## SHOTS per size (33 = 16 + 9 + 8 batch 3, see below). Batch 1 (unchanged, 16): events_milu_open, events_milu_pages,
##  events_milu_locked, goal_milu1_away, goal_milu1_short, goal_milu1_ready, events_milu_done,
##  goal_milu1_done, goal_bobo2_option, goal_bobo2_done, goal_xinghe2_option, goal_aru2_steps,
##  goal_lingpopo2_wrong, goal_lingpopo2_right, goal_lingpopo3_long, goal_luoluo3_option.
##  Batch 2 (9): goal_aru1_nobed, goal_aru1_ready, goal_aru1_done, events_aru_done,
##  goal_xinghe3_need, goal_xinghe3_short, goal_lingpopo4_ready, goal_luoluo2_two,
##  goal_luoluo2_three.
##  Before an option/step press (and before the 阿榆 1 completion / 鈴婆婆 4 festival write) an
##  UNSAVED baseline frame of the same page is grabbed so the later state can be compared
##  against it ("base_*" in the NOTE lines).
## ASSERTS per page: modal inside the viewport, community_board layout, no outer scrolling,
##  every visible label/button inside the modal and not cut; expected nodes present/absent;
##  BondGoalDo disabled/enabled with the reason as tooltip; reason/cost-row warning colour
##  as a theme override AND in the rendered image (warm-red pixels inside the reason label /
##  short cost label, none in the normal-colour task label / enough cost label); states of
##  the same page differ by a measured pixel fraction inside the modal.
##  Batch 2 needs: BondGoalNeeds sits before BondGoalCost; BondGoalNeed_<id> reads
##  「✓ 要先：…」／「○ 要先：…」; an unmet line has the GOAL_WARN override and warm-red pixels,
##  a met line neither; reason order need-before-items (星禾 3) and items once the need is met.
## BATCH 3 (紀念小物, 12 of the 28 goals carry a placeable keepsake "keepsake_<resident>"):
##  PRESET / FIXTURE additionally:
##    - stock() also erases the twelve "keepsake_*_kit" items; set_done() also writes or
##      erases player.bond_keepsakes (so a save always pairs claimed keepsakes with done goals);
##    - 小栗 4 is written done (choice tomorrow) WITH keepsake_xiaoli claimed (done before the
##      session, kit long since placed: no kit in the bag);
##    - 米露 3 is written done (choice carrot_soup) WITHOUT a claim ("done before batch 3");
##    - home flow: all twelve kits are written into the bag (1 each) by a direct write; the
##      player is teleported (x/y write) to tiles south of a free 6×2 block of home tiles
##      that the test looks up itself (nothing placed, no crop/ground/resource, not blocked
##      or protected, and the row south of it also free).
##  REALLY EXERCISED: 阿榆 1's real completion (kit +1, bond_keepsakes, toast sentence); the
##  real BondGoalClaim button (Session.perform("resident_keepsake") -> World -> snapshot ->
##  refresh_bond_goal rebuilds the page as claimed); 家園工坊 opened with app._build_menu(),
##  the real BuildTab3 (生活) and BuildSlot_<kind>_3 buttons; the real InventoryPanel
##  (app._inventory(), 其他 tab, keyboard focus on the kit); the twelve keepsakes placed with
##  the client build path (app.building + app._select_tool("build") + app._use_selected_at
##  -> Session.perform("build")); walking is the server's own World.move_player (what
##  Session runs for movement input), stepped north from the free row through two keepsakes.
##  SHOTS per size (8, prefix 紀念小物_): xiaoli4_claimed, milu3_unclaimed_away,
##  milu3_unclaimed_near, milu3_claimed_after, build_lingpopo, inventory_lingpopo,
##  home_block, home_walkthrough.
##  ASSERTS: done pages show BondGoalKeepsake (inside BondGoalDone) with the claimed /
##  unclaimed text and no 「（收在手帳裡，沒有其他用途）」 line; the 32px icon is drawn
##  (pixels differ from the card paper AND the icon art's opaque pixels are on screen);
##  BondGoalClaim disabled away with BondGoalClaimReason (warning colour, red pixels) and
##  enabled beside 米露; after the real claim: kit +1, record written, page rebuilt claimed;
##  build folio: 生活 tab, title, blurb description fully on view, materials 1／1; backpack:
##  name / description / value lines; home: each of the 12 tiles changes against the same
##  framing before placement and is not a flat colour, all tiles on screen and clear of
##  HUD panels, every keepsake tile can_stand, and the walk really crosses two of them.
## NOT CHECKED: all 28 goals (test_resident_goal_ui.gd sweeps them headless); mianmian 4
##  (fair_weather, depends on the weather table) and xiaoli 3 (market_round) pages; the
##  non-native rules of the needs (resident_goals.gd unit tests); the world view behind the
##  modal shade, including how the directly written bed is drawn; BuildTitle ellipsis for
##  long keepsake names (only NOTEd: the folio trims long titles by design); keepsake art
##  details (the art script's own tests).
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const WARN:=Color("9c4b32")
## Saved screenshots per size: batch 1, batch 2, batch 3 (named, so the total is computed).
const SHOTS_BATCH1:=16
const SHOTS_BATCH2:=9
const KEEPSAKE_SHOTS:=["紀念小物_xiaoli4_claimed","紀念小物_milu3_unclaimed_away","紀念小物_milu3_unclaimed_near","紀念小物_milu3_claimed_after",
	"紀念小物_build_lingpopo","紀念小物_inventory_lingpopo","紀念小物_home_block","紀念小物_home_walkthrough"]
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
## Home keepsake block: 6 columns × 2 rows, searched outward from the open build area
## north-east of the plaza (the souvenir scene test's decoration row is there too).
const BLOCK_COLUMNS:=6
const BLOCK_ROWS:=2
const BLOCK_SEARCH_FROM:=Vector2i(46,21)
const BLOCK_SEARCH_RADIUS:=12
## The column the walk-through goes up (row 0 kind = KEEPSAKE_ORDER[WALK_COLUMN]).
const WALK_COLUMN:=2
## Kind shown in the build folio and backpack captures (longest blurb with a short name).
const FOLIO_KIND:="keepsake_lingpopo"
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var images:={}
var boxes:={}
var heights:={}
var written:=PackedStringArray()

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("RESIDENT_GOAL_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE RESIDENT_GOAL_SCENE "+message)

# ------------------------------------------------------------- helpers --

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):
		var toast_label:Label=app.toast
		toast_label.hide()

func clear_toast()->void:
	if app.toast==null or not is_instance_valid(app.toast):return
	var toast_label:Label=app.toast
	toast_label.text=""

func toast_text()->String:
	if app.toast==null or not is_instance_valid(app.toast):return ""
	return str((app.toast as Label).text)

func drop_ribbon()->void:
	var ribbon:Node=app.hud.get_node_or_null("TravelArrival")
	if ribbon!=null:
		app.hud.remove_child(ribbon)
		ribbon.queue_free()

func refresh()->void:
	app.session._send_snapshot(1)
	await settle()
	drop_ribbon()

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

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func shown(control_name:String)->bool:
	var c:=control(control_name)
	return c!=null and c.is_visible_in_tree()

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

## Emit `pressed` on an enabled button (the same signal a click / Enter sends).
func press_button(b:BaseButton,label:String,wait:=false)->bool:
	check(b!=null and not b.disabled,"Enabled button: %s (%s)"%[label,tag])
	if b==null or b.disabled:return false
	clear_toast()
	if wait:await create_timer(0.12).timeout
	b.pressed.emit()
	await settle()
	return true

func press(control_name:String,wait:=false)->bool:
	return await press_button(control(control_name) as BaseButton,control_name,wait)

func close()->void:
	if is_instance_valid(app.modal):app._close_modal()
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

func goal_items()->Array:
	var out:Array=[]
	for resident:String in Goals.GOALS:
		for stage:int in Goals.GOALS[resident]:
			var entry:=entry_of(resident,stage)
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

## PRESET: player.bond_goals and player.bond_keepsakes (empty = erase). Both are written
## together so a claimed keepsake is never left without its done goal.
func set_done(goals:Dictionary,keepsakes:Dictionary={})->void:
	var p:=person()
	if goals.is_empty():p.erase(Goals.RECORD_KEY)
	else:p[Goals.RECORD_KEY]=goals
	if keepsakes.is_empty():p.erase(Goals.KEEPSAKE_KEY)
	else:p[Goals.KEEPSAKE_KEY]=keepsakes

## PRESET: all goal items to 0 and the twelve keepsake kits erased, then the given amounts.
func stock(items:Dictionary)->void:
	var inv:=inventory()
	for item:String in goal_items():inv[item]=0
	for item:String in Goals.keepsake_items():inv.erase(item)
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

# ------------------------------------------------------------- capture --

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func region_variety(image:Image,box:Rect2i)->int:
	var r:=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if r.size.x<=0 or r.size.y<=0:return 0
	var seen:={}
	for gx in range(20):
		for gy in range(14):
			var c:Color=image.get_pixel(r.position.x+int((gx+0.5)*r.size.x/20.0),r.position.y+int((gy+0.5)*r.size.y/14.0))
			seen[c.to_html(false)]=true
	return seen.size()

func modal_box()->Rect2i:
	if not is_instance_valid(app.modal):return Rect2i()
	var r:Rect2=(app.modal as Control).get_global_rect()
	return Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.floor()))

func pixel_rect(c:Control)->Rect2i:
	if c==null:return Rect2i()
	var r:Rect2=c.get_global_rect()
	return Rect2i(Vector2i(r.position.floor()),Vector2i(r.size.ceil()))

## Native frame of the current state (toast hidden, modal fade-in over).
func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout  # modal fade-in (LifeShell.reveal) is 0.16 s
	await settle()
	hide_toast()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	if image!=null:image.convert(Image.FORMAT_RGBA8)
	return image

## Unsaved frame kept only for a state-difference comparison.
func baseline(key:String)->void:
	var image:Image=await grab()
	if image==null or image.is_empty():image=Image.create_empty(maxi(root.size.x,1),maxi(root.size.y,1),false,Image.FORMAT_RGBA8)
	images[key]=image
	boxes[key]=modal_box()

## Saved native screenshot + size/variety checks; the image and modal box are kept by step.
func page_shot(step:String)->Image:
	var file_name:="%s_%s"%[tag,step]
	var image:Image=await grab()
	check(image!=null and not image.is_empty(),"non-empty native image "+file_name)
	if image==null or image.is_empty():
		image=Image.create_empty(maxi(root.size.x,1),maxi(root.size.y,1),false,Image.FORMAT_RGBA8)
		images[step]=image
		boxes[step]=modal_box()
		return image
	images[step]=image
	boxes[step]=modal_box()
	heights[step]=float(modal_box().size.y)
	check(image.get_size()==root.size,"Screenshot has the viewport size %s (%s)"%[str(root.size),file_name])
	var variety:=colour_variety(image)
	check(variety>=12,"Screenshot is not blank or flat (%d colours on the grid) %s"%[variety,file_name])
	if is_instance_valid(app.modal):
		var live:=region_variety(image,modal_box())
		# 最空的一頁（米露 1、材料齊）在取樣格上只有 5 種顏色；門檻取 4。
		check(live>=4,"Modal region of %s is not a flat colour (%d colours)"%[file_name,live])
	else:note("%s: world frame, no modal (modal colour check skipped)"%file_name)
	var file:=output.path_join(file_name+".png")
	check(image.save_png(file)==OK,"native screenshot saved "+file_name)
	check(FileAccess.file_exists(file),"screenshot file exists "+file_name)
	var length:int=0
	var handle:=FileAccess.open(file,FileAccess.READ)
	if handle!=null:
		length=handle.get_length()
		handle.close()
	check(length>10000,"screenshot file is not trivially small (%d bytes) %s"%[length,file_name])
	shots+=1
	written.append(file_name+".png")
	note("screenshot %s (%d bytes, modal %s) sha256=%s"%[file,length,str(modal_box()),FileAccess.get_sha256(file)])
	return image

## Fraction of sampled pixels (every 2nd px) inside `box` that differ between two frames.
func region_difference(a:Image,b:Image,box:Rect2i)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 0.0
	var r:=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if r.size.x<=0 or r.size.y<=0:return 0.0
	var changed:=0
	var total:=0
	for x in range(r.position.x,r.end.x,2):
		for y in range(r.position.y,r.end.y,2):
			var p:=a.get_pixel(x,y)
			var q:=b.get_pixel(x,y)
			total+=1
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(maxi(total,1))

## Two kept frames of the same page differ inside the union of their modal boxes.
func differ(a:String,b:String,minimum:float,label:String)->void:
	if not images.has(a) or not images.has(b):
		check(false,"Frames %s and %s both captured (%s %s)"%[a,b,label,tag])
		return
	var ia:Image=images[a]
	var ib:Image=images[b]
	var box_a:Rect2i=boxes[a]
	var box_b:Rect2i=boxes[b]
	var box:=box_a.merge(box_b)
	var fraction:=region_difference(ia,ib,box)
	note("%s %s: %s vs %s differ in %.2f%% of the modal (min %.2f%%)"%[label,tag,a,b,fraction*100.0,minimum*100.0])
	check(fraction>=minimum,"States render differently: %s vs %s %.3f%% >= %.3f%% (%s %s)"%[a,b,fraction*100.0,minimum*100.0,label,tag])

## Solid warm-red pixels (the GOAL_WARN ink 9c4b32) inside a control's rect. The cream paper
## and the dark normal ink both fail this test; only fully covered warning-colour strokes pass.
func red_pixels(image:Image,c:Control)->int:
	if image==null or c==null:return 0
	var r:=pixel_rect(c).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if r.size.x<=0 or r.size.y<=0:return 0
	var count:=0
	for x in range(r.position.x,r.end.x):
		for y in range(r.position.y,r.end.y):
			var q:=image.get_pixel(x,y)
			var lum:=0.299*q.r+0.587*q.g+0.114*q.b
			if q.r>=0.45 and q.r-q.g>=0.18 and q.r-q.b>=0.25 and lum<0.55:count+=1
	return count

func warn_override(l:Label)->bool:
	return l!=null and l.has_theme_color_override("font_color") and l.get_theme_color("font_color")==WARN

## The visible reason is drawn in the warning colour; the task line in the normal colour.
func reason_red(image:Image,label:String)->void:
	var reason:=control("BondGoalReason") as Label
	var task:=control("BondGoalTask") as Label
	check(reason!=null and reason.is_visible_in_tree(),"Reason visible for the colour check (%s %s)"%[label,tag])
	if reason==null or task==null:return
	check(warn_override(reason),"Reason has the warning font colour override (%s %s)"%[label,tag])
	check(not warn_override(task) and task.get_theme_color("font_color")!=WARN,"Task line keeps the normal text colour %s (%s %s)"%[task.get_theme_color("font_color").to_html(false),label,tag])
	var red:=red_pixels(image,reason)
	var plain:=red_pixels(image,task)
	note("%s %s: warning-red pixels reason=%d (rect %s) task=%d (rect %s)"%[label,tag,red,str(pixel_rect(reason)),plain,str(pixel_rect(task))])
	check(red>=6,"Reason is rendered in the warning red (%d red pixels) (%s %s)"%[red,label,tag])
	check(plain<=maxi(3,int(red*0.2)),"Task line is not rendered red (%d vs reason %d) (%s %s)"%[plain,red,label,tag])

## A cost row's amount label is red in the image only when short.
func chip_red(image:Image,item:String,short:bool,label:String)->void:
	var row:=control("BondGoalCost_"+item)
	var amount:=first_label(row)
	check(amount!=null and amount.is_visible_in_tree(),"Cost row %s visible for the colour check (%s %s)"%[item,label,tag])
	if amount==null:return
	var red:=red_pixels(image,amount)
	note("%s %s: cost row %s 「%s」 warning-red pixels=%d (short=%s)"%[label,tag,item,amount.text,red,str(short)])
	if short:
		check(warn_override(amount),"Short cost row %s has the warning colour override (%s %s)"%[item,label,tag])
		check(red>=4,"Short cost row %s is rendered red (%d red pixels) (%s %s)"%[item,red,label,tag])
	else:
		check(not warn_override(amount),"Enough cost row %s has no warning override (%s %s)"%[item,label,tag])
		check(red<=1,"Enough cost row %s is not rendered red (%d red pixels) (%s %s)"%[item,red,label,tag])

## Batch 2: one prerequisite line inside BondGoalNeeds (which sits before BondGoalCost).
## Unmet: 「○ 要先：…」 with the warning override and warm-red pixels; met: 「✓ 要先：…」 neither.
func need_line_ok(image:Image,need_id:String,need_label:String,met:bool,label:String)->void:
	var need_node:=control("BondGoalNeed_"+need_id) as Label
	var want:=("✓ " if met else "○ ")+"要先："+need_label
	check(need_node!=null and need_node.is_visible_in_tree() and need_node.text==want,"Need line reads 「%s」 (%s %s): 「%s」"%[want,label,tag,need_node.text if need_node else "?"])
	if need_node==null:return
	var holder:=control("BondGoalNeeds")
	var cost:=control("BondGoalCost")
	check(holder!=null and holder.is_ancestor_of(need_node),"Need line %s is inside BondGoalNeeds (%s %s)"%[need_id,label,tag])
	check(holder!=null and cost!=null and holder.get_parent()==cost.get_parent() and holder.get_index()<cost.get_index(),"BondGoalNeeds sits before BondGoalCost (%s %s)"%[label,tag])
	var red:=red_pixels(image,need_node)
	note("%s %s: need line %s 「%s」 warning-red pixels=%d (met=%s, rect %s)"%[label,tag,need_id,need_node.text,red,str(met),str(pixel_rect(need_node))])
	if met:
		check(not warn_override(need_node) and need_node.get_theme_color("font_color")!=WARN,"Met need line %s keeps the normal text colour (%s %s)"%[need_id,label,tag])
		check(red<=3,"Met need line %s is not rendered red (%d red pixels) (%s %s)"%[need_id,red,label,tag])
	else:
		check(warn_override(need_node),"Unmet need line %s has the warning colour override (%s %s)"%[need_id,label,tag])
		check(red>=6,"Unmet need line %s is rendered in the warning red (%d red pixels) (%s %s)"%[need_id,red,label,tag])

func need_reason(need_label:String)->String:
	return "要先「%s」。"%need_label

# ------------------------------------------------------------- layout --

## No outer scrolling; every visible Label/Button fully on view inside the modal, not cut.
func page_fits(label:String)->void:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Modal open (%s)"%label)
	if not ok:return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Modal fits the viewport (%s) %s"%[label,str((app.modal as Control).get_global_rect())])
	check(str((app.modal as Node).get_meta("life_modal_layout",""))=="community_board","Modal keeps the community_board layout (%s)"%label)
	var scroll:=control("ModalScroll") as ScrollContainer
	check(scroll!=null and scroll.get_child_count()>0,"Modal has its ModalScroll body (%s)"%label)
	if scroll==null or scroll.get_child_count()==0:return
	var content:=scroll.get_child(0) as Control
	var need:float=content.get_combined_minimum_size().y
	var bar:=scroll.get_v_scroll_bar()
	print("RESIDENT_GOAL_SCENE_DIAG fit %s content=%.0f view=%.0f spare=%.0f"%[label,need,scroll.size.y,scroll.size.y-need])
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

func nodes_ok(present:Array,absent:Array,label:String)->void:
	for control_name in present:check(shown(str(control_name)),"%s present and visible (%s %s)"%[control_name,label,tag])
	for control_name in absent:check(not shown(str(control_name)),"%s absent (%s %s)"%[control_name,label,tag])

# ------------------------------------------------------------ events page --

func open_events(resident:String,tab:=-1)->bool:
	await close()
	Tasks.bond_events(app,resident,tab)
	await settle()
	var ok:=is_instance_valid(app.modal) and find_label("%s的關係事件"%npc(resident))!=null and control("BondEventCard")!=null
	check(ok,"%s的關係事件 opens (%s)"%[npc(resident),tag])
	return ok

func count_text(resident:String)->String:
	var done_count:=0
	for stage:int in Goals.GOALS[resident]:
		if state_of(resident,stage)=="done":done_count+=1
	return "一起做的事 %d／%d"%[done_count,Goals.GOALS[resident].size()]

func press_tab(index:int,label:String)->bool:
	var tab:=control("BondEventTab_%d"%index) as Button
	check(tab!=null and not tab.disabled,"BondEventTab_%d enabled (%s %s)"%[index,label,tag])
	if tab==null or tab.disabled:return false
	tab.grab_focus()
	tab.pressed.emit()
	await settle()
	return true

## Selected tab, count header, and BondGoalOpen present (○／✓) or absent.
func events_ok(resident:String,index:int,want_open:bool,label:String)->void:
	page_fits("events %s tab %d %s %s"%[resident,index+1,label,tag])
	nodes_ok(["BondGoalCount","BondEventCard","BondEventTabs","BondEventsBack"],[],label)
	var count:=control("BondGoalCount") as Label
	check(count!=null and count.text==count_text(resident),"BondGoalCount reads %s (%s %s): %s"%[count_text(resident),label,tag,count.text if count else "?"])
	for i in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%i) as Button
		check(tab!=null and tab.button_pressed==(i==index),"BondEventTab_%d %s (%s %s)"%[i,"selected" if i==index else "not selected",label,tag])
	var open:=control("BondGoalOpen") as Button
	var slot:=control("BondGoalSlot")
	if want_open:
		var state:=state_of(resident,index+1)
		var text:=("✓ " if state=="done" else "○ ")+"一起做的事・"+str(entry_of(resident,index+1).title)
		check(open!=null and open.is_visible_in_tree() and open.text==text,"BondGoalOpen reads %s (%s %s): %s"%[text,label,tag,open.text if open else "?"])
		check(slot!=null and slot.visible,"BondGoalSlot shown (%s %s)"%[label,tag])
		check(open!=null and visible(open) and inside_modal(open) and button_not_cut(open),"BondGoalOpen fully on view, not cut (%s %s)"%[label,tag])
	else:
		check(open==null,"No BondGoalOpen on this tab (%s %s)"%[label,tag])
		check(slot==null or not slot.visible,"BondGoalSlot hidden (%s %s)"%[label,tag])

# ------------------------------------------------------------- goal page --

func goal_open(resident:String,stage:int)->bool:
	if not is_instance_valid(app.modal):return false
	var title:=control("BondGoalTitle") as Label
	return find_label("和%s一起做的事"%npc(resident))!=null and title!=null and title.text=="%s・%s"%[Bond.stage_name(stage),str(entry_of(resident,stage).title)]

## Real path: events page on the goal's tab, then BondGoalOpen.
func open_goal(resident:String,stage:int,label:String)->bool:
	if not await open_events(resident,stage-1):return false
	var open:=control("BondGoalOpen") as Button
	check(open!=null,"BondGoalOpen offered for %s %d (%s %s)"%[resident,stage,label,tag])
	if open==null:return false
	if not await press_button(open,"BondGoalOpen %s %d %s"%[resident,stage,label]):return false
	var ok:=goal_open(resident,stage)
	check(ok,"BondGoalOpen opens 和%s一起做的事 (%s %s)"%[npc(resident),label,tag])
	return ok

func reason_text()->String:
	var reason:=control("BondGoalReason") as Label
	if reason==null or not reason.is_visible_in_tree():return ""
	return reason.text

func reason_is(expected:String,label:String)->void:
	var finish_button:=control("BondGoalDo") as Button
	check(reason_text()==expected,"Reason reads 「%s」 (%s %s): 「%s」"%[expected,label,tag,reason_text()])
	check(shown("BondGoalReason")==(not expected.is_empty()),"BondGoalReason %s (%s %s)"%["visible" if not expected.is_empty() else "hidden",label,tag])
	check(finish_button!=null and finish_button.is_visible_in_tree() and finish_button.disabled==(not expected.is_empty()),"BondGoalDo %s (%s %s)"%["disabled" if not expected.is_empty() else "enabled",label,tag])
	if finish_button!=null:check(finish_button.tooltip_text==expected,"BondGoalDo tooltip is the reason (%s %s): %s"%[label,tag,finish_button.tooltip_text])

## Cost rows: exactly the given items, text 名稱 持有／需要, warning colour only when short.
func cost_is(rows:Dictionary,label:String)->void:
	var box:=control("BondGoalCost")
	var listed:=PackedStringArray()
	if box!=null and box.is_visible_in_tree():
		for child in box.get_children():
			if (child as Control).is_visible_in_tree():listed.append(str(child.name))
	check(listed.size()==rows.size(),"Cost rows %s (%s %s): %s"%[str(rows.keys()),label,tag,", ".join(listed)])
	check(shown("BondGoalCost")==(not rows.is_empty()),"BondGoalCost %s (%s %s)"%["visible" if not rows.is_empty() else "hidden",label,tag])
	for item:String in rows:
		var text_label:=first_label(control("BondGoalCost_"+item))
		var have:=held(item)
		var want:=int(rows[item])
		var text:="%s %d／%d"%[str(World.NAMES[item]),have,want]
		check(text_label!=null and text_label.text==text,"Cost row reads %s (%s %s): %s"%[text,label,tag,text_label.text if text_label else "?"])

func short_text(item:String,want:int)->String:
	return "還差%s %d／%d。"%[str(World.NAMES[item]),held(item),want]

func away_text(resident:String)->String:
	var where:String=str(Bond.LOCAL_PLACES[resident]) if Bond.LOCAL_PLACES.has(resident) else World.REGIONS.label(str(World.bond_place(app.session.snapshot,resident)[0]))
	return "要站在%s身邊（%s）才能一起做。"%[npc(resident),where]

## Open-state page: nodes for the goal's kind, reason/Do, cost rows, fit.
func open_page_ok(resident:String,stage:int,reason:String,rows:Dictionary,label:String)->void:
	var entry:=entry_of(resident,stage)
	check(goal_open(resident,stage),"Goal page %s %d open (%s %s)"%[resident,stage,label,tag])
	var present:Array=["BondGoalTitle","BondGoalTask","BondGoalActions","BondGoalDo","BondGoalBack"]
	var absent:Array=["BondGoalDone"]
	for pair:Array in [["options","BondGoalOptions"],["steps","BondGoalSteps"],["steps","BondGoalStepsReset"],["needs","BondGoalNeeds"]]:
		if entry.has(str(pair[0])):present.append(pair[1])
		else:absent.append(pair[1])
	if entry.has("steps"):
		for i in range(Goals.STEP_COUNT):present.append("BondGoalStep_%d"%i)
	if entry.has("options"):
		for option:Dictionary in entry.options:present.append("BondGoalOption_"+str(option.id))
	for need_id in entry.get("needs",[]):present.append("BondGoalNeed_"+str(need_id))
	nodes_ok(present,absent,label)
	var task:=control("BondGoalTask") as Label
	check(task!=null and task.text==str(entry.task),"BondGoalTask shows the task (%s %s)"%[label,tag])
	var finish_button:=control("BondGoalDo") as Button
	check(finish_button!=null and finish_button.text=="一起完成","BondGoalDo reads 一起完成 (%s %s)"%[label,tag])
	var back:=control("BondGoalBack") as Button
	check(back!=null and back.text=="回到關係事件","BondGoalBack reads 回到關係事件 (%s %s)"%[label,tag])
	reason_is(reason,label)
	cost_is(rows,label)
	page_fits("open %s %d %s %s"%[resident,stage,label,tag])

## Done-state page reached through the real ✓ BondGoalOpen. Goals without a keepsake keep the
## journal line 「紀念：…（收在手帳裡，沒有其他用途）」; the twelve keepsake goals show the
## BondGoalKeepsake row instead (claimed / unclaimed from the own snapshot, cross-checked
## against the server record) and, while unclaimed, the BondGoalClaim button.
func done_page_ok(resident:String,stage:int,label:String)->void:
	var entry:=entry_of(resident,stage)
	var kind:=Goals.keepsake_kind(resident,stage)
	check(goal_open(resident,stage),"Done page %s %d open (%s %s)"%[resident,stage,label,tag])
	var present:Array=["BondGoalTitle","BondGoalTask","BondGoalDone","BondGoalActions","BondGoalBack"]
	var absent:Array=["BondGoalOptions","BondGoalSteps","BondGoalStepsReset","BondGoalNeeds","BondGoalCost","BondGoalReason","BondGoalDo"]
	var claimed:=true
	if kind.is_empty():
		absent.append_array(["BondGoalKeepsake","BondGoalClaim","BondGoalClaimReason"])
	else:
		var keep:=Tasks.goal_keepsake(app,resident,stage)
		claimed=bool(keep.get("claimed",false))
		check(str(keep.get("kind",""))==kind and str(keep.get("item",""))==Goals.keepsake_item(kind) and str(keep.get("name",""))==str(Goals.KEEPSAKES[kind].name),"Snapshot carries keepsake %s for %s %d (%s %s): %s"%[kind,resident,stage,label,tag,str(keep)])
		check(claimed==Goals.keepsake_claimed(person(),kind),"Snapshot claimed=%s matches the server record (%s %s)"%[str(claimed),label,tag])
		present.append("BondGoalKeepsake")
		if claimed:absent.append_array(["BondGoalClaim","BondGoalClaimReason"])
		else:present.append("BondGoalClaim")
	nodes_ok(present,absent,label)
	var done:=control("BondGoalDone")
	var wanted:Array=["✓ 已經一起完成"]
	for quote in entry.quote:wanted.append("「%s」"%str(quote))
	var picked:=Goals.option(entry,choice_of(resident,stage))
	if not picked.is_empty():wanted.append("當時選的是：%s"%str(picked.label))
	if resident=="aru" and stage==2:wanted.append("紀念：%s。師父的長椅已加入家園工坊。"%str(entry.keepsake))
	elif kind.is_empty():wanted.append("紀念：%s（收在手帳裡，沒有其他用途）"%str(entry.keepsake))
	for text:String in wanted:
		var l:=find_label(text)
		check(l!=null and done!=null and done.is_ancestor_of(l),"Done page shows 「%s」 (%s %s)"%[text,label,tag])
	if picked.is_empty():check(not texts().contains("當時選的是"),"No 當時選的是 line without options (%s %s)"%[label,tag])
	if not kind.is_empty():keepsake_line_ok(kind,claimed,label)
	page_fits("done %s %d %s %s"%[resident,stage,label,tag])

## Batch 3: the BondGoalKeepsake row (inside BondGoalDone) reads the claimed / unclaimed text,
## is fully on view and not cut; the old journal-only line is gone.
func keepsake_line_ok(kind:String,claimed:bool,label:String)->void:
	var keep_name:=str(Goals.KEEPSAKES[kind].name)
	var row:=control("BondGoalKeepsake")
	var done:=control("BondGoalDone")
	var text_label:=control("BondGoalKeepsakeText") as Label
	var text:=text_label.text if text_label!=null else "?"
	check(row!=null and done!=null and done.is_ancestor_of(row) and text_label!=null and row.is_ancestor_of(text_label),"BondGoalKeepsakeText sits in BondGoalKeepsake inside BondGoalDone (%s %s)"%[label,tag])
	if claimed:
		var ok:=text.begins_with("紀念小物：%s（已放進背包；按 "%keep_name) and text.ends_with("打開家園工坊，在「生活」頁可以擺到家園）") and not text.contains("{")
		check(ok,"Claimed keepsake line names %s and the key (%s %s): 「%s」"%[keep_name,label,tag,text])
	else:
		check(text=="紀念小物：%s（還沒領）"%keep_name,"Unclaimed keepsake line reads 「紀念小物：%s（還沒領）」 (%s %s): 「%s」"%[keep_name,label,tag,text])
	check(text_label!=null and visible(text_label) and inside_modal(text_label) and not_cut(text_label),"Keepsake line fully on view and not cut (%s %s)"%[label,tag])
	check(not texts().contains("（收在手帳裡，沒有其他用途）"),"No journal-only 紀念 line on a keepsake goal (%s %s)"%[label,tag])

func texture_image(tex:Texture2D)->Image:
	if tex==null:return null
	var img:Image=tex.get_image()
	if img==null or img.is_empty():return null
	if img.is_compressed():img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

## Batch 3: the 32px keepsake icon in BondGoalKeepsake is really drawn: (1) a share of the pixels
## in its rect differ from the card paper (the most common colour on the column 3 px to its
## left), and (2) the icon art's opaque pixels appear on screen in their own colours.
func keepsake_icon_ok(image:Image,label:String)->void:
	var row:=control("BondGoalKeepsake")
	var icon:TextureRect=null
	if row!=null:
		for child in row.get_children():
			if child is TextureRect:
				icon=child as TextureRect
				break
	check(icon!=null and icon.is_visible_in_tree() and icon.texture!=null,"BondGoalKeepsake has a visible icon with a texture (%s %s)"%[label,tag])
	if icon==null or icon.texture==null or image==null:return
	check(visible(icon) and inside_modal(icon),"Keepsake icon fully on view inside the modal (%s %s)"%[label,tag])
	var g:Rect2=icon.get_global_rect()
	check(g.size.x>=31.5 and g.size.y>=31.5,"Keepsake icon is 32px (%s %s): %s"%[label,tag,str(g.size)])
	var r:=pixel_rect(icon).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if r.size.x<=0 or r.size.y<=0:
		check(false,"Keepsake icon rect inside the frame (%s %s)"%[label,tag])
		return
	var counts:={}
	var bx:=maxi(0,r.position.x-3)
	for y in range(r.position.y,r.end.y):
		var html:=image.get_pixel(bx,y).to_html(false)
		counts[html]=int(counts.get(html,0))+1
	var paper_html:=""
	var best:=-1
	for html:String in counts:
		if int(counts[html])>best:
			best=int(counts[html])
			paper_html=html
	var paper:=Color.html(paper_html)
	var inked:=0
	for x in range(r.position.x,r.end.x):
		for y in range(r.position.y,r.end.y):
			var q:=image.get_pixel(x,y)
			if absf(q.r-paper.r)+absf(q.g-paper.g)+absf(q.b-paper.b)>0.12:inked+=1
	var share_inked:=float(inked)/float(maxi(1,r.size.x*r.size.y))
	var art:=texture_image(icon.texture)
	var opaque:=0
	var matched:=0
	if art!=null:
		var scale:=minf(g.size.x/float(art.get_width()),g.size.y/float(art.get_height()))
		var origin:Vector2=g.position+(g.size-Vector2(art.get_size())*scale)/2.0
		for y in range(art.get_height()):
			for x in range(art.get_width()):
				var c:=art.get_pixel(x,y)
				if c.a<0.99:continue
				opaque+=1
				var at:=Vector2i((origin+(Vector2(x,y)+Vector2(0.5,0.5))*scale).floor())
				if at.x<0 or at.y<0 or at.x>=image.get_width() or at.y>=image.get_height():continue
				var q:=image.get_pixel(at.x,at.y)
				if absf(c.r-q.r)+absf(c.g-q.g)+absf(c.b-q.b)<0.15:matched+=1
	var share_art:=float(matched)/maxf(1.0,float(opaque))
	note("%s %s: keepsake icon rect %s paper #%s differs in %.0f%%; art opaque %d, on screen as painted %.0f%%"%[label,tag,str(r),paper_html,share_inked*100.0,opaque,share_art*100.0])
	check(art!=null and opaque>=40,"Keepsake icon art has opaque pixels (%d) (%s %s)"%[opaque,label,tag])
	check(share_inked>=0.08,"Keepsake icon is drawn over the paper (%.0f%% of its rect differ) (%s %s)"%[share_inked*100.0,label,tag])
	check(share_art>=0.6,"Keepsake icon art appears on screen (%.0f%% of opaque pixels) (%s %s)"%[share_art*100.0,label,tag])

## Batch 3: BondGoalClaim + BondGoalClaimReason. Away: disabled, the reason (「…才能領取。」) as
## tooltip and as a warning-coloured, red-rendered line. Beside the resident: enabled, no reason.
func claim_ok(resident:String,near:bool,image:Image,label:String)->void:
	var claim:=control("BondGoalClaim") as Button
	var reason:=control("BondGoalClaimReason") as Label
	var expected:="" if near else away_text(resident).replace("才能一起做。","才能領取。")
	check(claim!=null and claim.is_visible_in_tree() and claim.text=="領取紀念小物","BondGoalClaim reads 領取紀念小物 (%s %s)"%[label,tag])
	if claim==null:return
	check(claim.disabled==(not near),"BondGoalClaim %s (%s %s)"%["enabled" if near else "disabled",label,tag])
	check(claim.tooltip_text==expected,"BondGoalClaim tooltip 「%s」 (%s %s): 「%s」"%[expected,label,tag,claim.tooltip_text])
	check(visible(claim) and inside_modal(claim) and button_not_cut(claim),"BondGoalClaim fully on view, not cut (%s %s)"%[label,tag])
	var shown_reason:=reason!=null and reason.is_visible_in_tree()
	check(shown_reason==(not near),"BondGoalClaimReason %s (%s %s)"%["hidden" if near else "visible",label,tag])
	if near or reason==null:return
	check(reason.text==expected,"BondGoalClaimReason reads 「%s」 (%s %s): 「%s」"%[expected,label,tag,reason.text])
	check(warn_override(reason),"BondGoalClaimReason has the warning colour override (%s %s)"%[label,tag])
	var red:=red_pixels(image,reason)
	note("%s %s: claim reason warning-red pixels=%d (rect %s)"%[label,tag,red,str(pixel_rect(reason))])
	check(red>=6,"BondGoalClaimReason is rendered in the warning red (%d red pixels) (%s %s)"%[red,label,tag])

## Press BondGoalDo for real; the page closes and the snapshot says done.
func complete(resident:String,stage:int,spent:Dictionary,choice:String,label:String)->bool:
	var before:={}
	for item:String in spent:before[item]=held(item)
	var title:=str(entry_of(resident,stage).title)
	var kind:=Goals.keepsake_kind(resident,stage)
	var kit:=Goals.keepsake_item(kind)
	var kits_before:=held(kit) if not kit.is_empty() else 0
	if not await press("BondGoalDo",true):return false
	check(not is_instance_valid(app.modal),"BondGoalDo closes the page (%s %s)"%[label,tag])
	check(toast_text().contains(title),"Toast tells 〈%s〉 is done (%s %s): %s"%[title,label,tag,toast_text()])
	for item:String in spent:
		check(held(item)==int(before[item])-int(spent[item]),"%s charged %d (%s %s)"%[item,int(spent[item]),label,tag])
	# Batch 3: a keepsake goal also hands over its kit and records the claim.
	if kind.is_empty():
		check(not toast_text().contains("紀念小物"),"No keepsake sentence for a goal without one (%s %s): %s"%[label,tag,toast_text()])
	else:
		check(held(kit)==kits_before+1,"%s +1 in the bag (%d -> %d) (%s %s)"%[kit,kits_before,held(kit),label,tag])
		check(Goals.keepsake_claimed(person(),kind),"player.bond_keepsakes.%s written (%s %s)"%[kind,label,tag])
		check(bool(Tasks.goal_keepsake(app,resident,stage).get("claimed",false)),"Snapshot marks %s claimed (%s %s)"%[kind,label,tag])
		check(toast_text().contains("紀念小物也放進背包了，在家園工坊的「生活」頁可以擺到家園。"),"Toast adds the keepsake sentence (%s %s): %s"%[label,tag,toast_text()])
	var ok:=state_of(resident,stage)=="done" and choice_of(resident,stage)==choice
	check(ok,"Snapshot says %s %d done with choice 「%s」 (%s %s): %s"%[resident,stage,choice,label,tag,str(Tasks.goal_state(app,resident,stage))])
	return ok

func reopen_done(resident:String,stage:int,label:String)->bool:
	if not await open_events(resident,stage-1):return false
	var open:=control("BondGoalOpen") as Button
	check(open!=null and open.text.begins_with("✓ "),"BondGoalOpen shows ✓ after completion (%s %s)"%[label,tag])
	if open==null:return false
	if not await press_button(open,"BondGoalOpen done "+label):return false
	return goal_open(resident,stage)

# ---------------------------------------------------------------- flows --

## Events page states (○ open, no goal, locked goal, ✓ done) and 米露 1 (pure deliver):
## far -> standing short -> stocked -> real BondGoalDo -> ✓ entry -> done page.
func milu_flow()->void:
	set_bonds({"milu":6})  # PRESET 熟悉
	set_done({})
	stock({})
	await stand("milu",true)
	check(int(Bond.stage(person(),"milu"))==2,"米露 preset is at 熟悉 (%s)"%tag)
	if not await open_events("milu",0):return
	events_ok("milu",0,true,"milu open")
	await page_shot("events_milu_open")
	if await press_tab(1,"milu pages"):
		events_ok("milu",1,true,"milu pages")
		check(Goals.has_goal("milu",2) and state_of("milu",2)=="open","米露 recipe page activity opens at 熟悉 (%s)"%tag)
		await page_shot("events_milu_pages")
		differ("events_milu_open","events_milu_pages",0.003,"different open event cards")
	if await press_tab(2,"milu locked"):
		events_ok("milu",2,false,"milu locked")
		check(Goals.has_goal("milu",3) and state_of("milu",3)=="locked","米露 3 exists and is locked (%s)"%tag)
		check(find_label("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[2]),int(Bond.THRESHOLDS[2])])!=null,"Locked card line shown (%s)"%tag)
		await page_shot("events_milu_locked")
		differ("events_milu_pages","events_milu_locked",0.003,"events recipe pages vs locked")
	if not await press_tab(0,"milu back to open"):return
	var open:=control("BondGoalOpen") as Button
	if not await press_button(open,"BondGoalOpen milu 1"):return
	var image:Image
	# Far away: the standing reason wins.
	open_page_ok("milu",1,away_text("milu"),{"soup":1},"milu1 away")
	check(root.gui_get_focus_owner()==control("BondGoalBack"),"Nothing actionable: focus on BondGoalBack (milu1 %s)"%tag)
	image=await page_shot("goal_milu1_away")
	reason_red(image,"milu1 away")
	chip_red(image,"soup",true,"milu1 away")
	# Walk over (preset teleport + snapshot): the open page refreshes in place.
	await stand("milu")
	open_page_ok("milu",1,short_text("soup",1),{"soup":1},"milu1 short")
	image=await page_shot("goal_milu1_short")
	reason_red(image,"milu1 short")
	chip_red(image,"soup",true,"milu1 short")
	differ("goal_milu1_away","goal_milu1_short",0.001,"milu1 away vs short")
	stock({"soup":1})
	await refresh()
	open_page_ok("milu",1,"",{"soup":1},"milu1 ready")
	image=await page_shot("goal_milu1_ready")
	chip_red(image,"soup",false,"milu1 ready")
	differ("goal_milu1_short","goal_milu1_ready",0.003,"milu1 short vs ready")
	if not await complete("milu",1,{"soup":1},"","milu1"):return
	if not await open_events("milu",0):return
	events_ok("milu",0,true,"milu done")
	check(control("BondGoalCount")!=null and (control("BondGoalCount") as Label).text=="一起做的事 1／4","Count reads 1／4 after completion (%s)"%tag)
	var entry_rect:=pixel_rect(control("BondGoalOpen"))
	await page_shot("events_milu_done")
	differ("events_milu_open","events_milu_done",0.0001,"events ○ vs ✓ (whole modal)")
	if images.has("events_milu_open") and images.has("events_milu_done"):
		var marker:=region_difference(images["events_milu_open"],images["events_milu_done"],entry_rect)
		note("events ○ vs ✓ %s: BondGoalOpen rect %s differs in %.2f%%"%[tag,str(entry_rect),marker*100.0])
		check(marker>=0.003,"BondGoalOpen ○ -> ✓ renders differently inside the button (%.2f%%) (%s)"%[marker*100.0,tag])
	if not await press_button(control("BondGoalOpen") as Button,"BondGoalOpen milu 1 done"):return
	done_page_ok("milu",1,"milu1 done")
	await page_shot("goal_milu1_done")
	differ("goal_milu1_ready","goal_milu1_done",0.01,"milu1 ready vs done")
	await close()

## 波波 2: options + items, option chosen, real BondGoalDo, done page with 當時選的是.
func bobo_flow()->void:
	set_bonds();set_done({});stock({"copper_joint":2,"plank":2})
	await stand("bobo")
	if not await open_goal("bobo",2,"bobo2"):return
	open_page_ok("bobo",2,Tasks.GOAL_NEED_OPTION,{"copper_joint":2,"plank":2},"bobo2 no option")
	await baseline("base_bobo2")
	if not await press("BondGoalOption_siding"):return
	var siding:=control("BondGoalOption_siding") as Button
	check(siding!=null and siding.button_pressed,"Option siding pressed (bobo2 %s)"%tag)
	for other in ["entrance","shed"]:
		var b:=control("BondGoalOption_"+str(other)) as Button
		check(b!=null and not b.button_pressed,"Option %s not pressed (bobo2 %s)"%[other,tag])
	open_page_ok("bobo",2,"",{"copper_joint":2,"plank":2},"bobo2 siding")
	var image:Image=await page_shot("goal_bobo2_option")
	chip_red(image,"plank",false,"bobo2 siding")
	differ("base_bobo2","goal_bobo2_option",0.002,"bobo2 no option vs siding")
	if not await complete("bobo",2,{"copper_joint":2,"plank":2},"siding","bobo2"):return
	if not await reopen_done("bobo",2,"bobo2"):return
	done_page_ok("bobo",2,"bobo2 done")
	check(find_label("當時選的是：岔道的側線")!=null,"Done page names the chosen option (bobo2 %s)"%tag)
	await page_shot("goal_bobo2_done")
	differ("goal_bobo2_option","goal_bobo2_done",0.01,"bobo2 option vs done")
	await close()

## 星禾 2: the cost comes from the option; one row enough, one row short.
func xinghe_flow()->void:
	set_bonds();set_done({});stock({"bluebell":2,"chime_herb":1})
	await stand("xinghe")
	if not await open_goal("xinghe",2,"xinghe2"):return
	open_page_ok("xinghe",2,Tasks.GOAL_NEED_OPTION,{},"xinghe2 no option")
	await baseline("base_xinghe2")
	if not await press("BondGoalOption_bluebell_chime"):return
	open_page_ok("xinghe",2,short_text("chime_herb",2),{"bluebell":2,"chime_herb":2},"xinghe2 bluebell_chime")
	var image:Image=await page_shot("goal_xinghe2_option")
	reason_red(image,"xinghe2 bluebell_chime")
	chip_red(image,"chime_herb",true,"xinghe2 bluebell_chime")
	chip_red(image,"bluebell",false,"xinghe2 bluebell_chime")
	differ("base_xinghe2","goal_xinghe2_option",0.003,"xinghe2 no option vs option")
	await close()

## 阿榆 2: free-order steps + items, two steps picked.
func aru_flow()->void:
	set_bonds();set_done({});stock({"hardwood":4})
	await stand("aru")
	if not await open_goal("aru",2,"aru2"):return
	var entry:=entry_of("aru",2)
	open_page_ok("aru",2,Tasks.GOAL_NEED_STEPS,{"hardwood":4},"aru2 no steps")
	await baseline("base_aru2")
	if not await press("BondGoalStep_2"):return
	if not await press("BondGoalStep_0"):return
	var s2:=control("BondGoalStep_2") as Button
	var s0:=control("BondGoalStep_0") as Button
	var s1:=control("BondGoalStep_1") as Button
	check(s2!=null and s2.text=="1. "+str(entry.steps[2]) and s2.disabled,"Step 2 marked 1. and disabled (aru2 %s)"%tag)
	check(s0!=null and s0.text=="2. "+str(entry.steps[0]) and s0.disabled,"Step 0 marked 2. and disabled (aru2 %s)"%tag)
	check(s1!=null and s1.text==str(entry.steps[1]) and not s1.disabled,"Step 1 still open (aru2 %s)"%tag)
	open_page_ok("aru",2,Tasks.GOAL_NEED_STEPS,{"hardwood":4},"aru2 two steps")
	var image:Image=await page_shot("goal_aru2_steps")
	reason_red(image,"aru2 two steps")
	chip_red(image,"hardwood",false,"aru2 two steps")
	differ("base_aru2","goal_aru2_steps",0.002,"aru2 no steps vs two steps")
	await close()

## 鈴婆婆 2 (fixed order) wrong then right; 鈴婆婆 3 (4 options + 2 items, the longest page).
func lingpopo_flow()->void:
	set_bonds();set_done({});stock({})
	await stand("lingpopo")
	if await open_goal("lingpopo",2,"lingpopo2"):
		var entry:=entry_of("lingpopo",2)
		open_page_ok("lingpopo",2,Tasks.GOAL_NEED_STEPS,{},"lingpopo2 no steps")
		await baseline("base_lingpopo2")
		var pressed_all:=true
		for i in [0,1,2]:
			if not await press("BondGoalStep_%d"%i):
				pressed_all=false
				break
		if pressed_all:
			check(Tasks.GOAL_ORDER_WRONG=="順序不太對，再看一次圖示。","Wrong-order text constant (%s)"%tag)
			for i in range(Goals.STEP_COUNT):
				var step:=control("BondGoalStep_%d"%i) as Button
				check(step!=null and step.text==str(entry.steps[i]) and not step.disabled,"Wrong order clears step %d (lingpopo2 %s)"%[i,tag])
			open_page_ok("lingpopo",2,Tasks.GOAL_ORDER_WRONG,{},"lingpopo2 wrong order")
			var image:Image=await page_shot("goal_lingpopo2_wrong")
			reason_red(image,"lingpopo2 wrong order")
			differ("base_lingpopo2","goal_lingpopo2_wrong",0.001,"lingpopo2 no steps vs wrong order")
			var order:Array=entry.order
			var right:=true
			for i in order:
				if not await press("BondGoalStep_%d"%int(i)):
					right=false
					break
			if right:
				for at in range(order.size()):
					var step:=control("BondGoalStep_%d"%int(order[at])) as Button
					check(step!=null and step.text=="%d. %s"%[at+1,str(entry.steps[int(order[at])])] and step.disabled,"Step %d marked %d. (lingpopo2 %s)"%[int(order[at]),at+1,tag])
				open_page_ok("lingpopo",2,"",{},"lingpopo2 right order")
				check(root.gui_get_focus_owner()==control("BondGoalDo"),"After the right order focus moves to BondGoalDo (lingpopo2 %s)"%tag)
				await page_shot("goal_lingpopo2_right")
				differ("goal_lingpopo2_wrong","goal_lingpopo2_right",0.002,"lingpopo2 wrong vs right order")
	await close()
	stock({"copper_ingot":4,"glass":2})
	await refresh()
	if not await open_goal("lingpopo",3,"lingpopo3"):return
	open_page_ok("lingpopo",3,Tasks.GOAL_NEED_OPTION,{"copper_ingot":4,"glass":2},"lingpopo3 no option")
	await baseline("base_lingpopo3")
	if not await press("BondGoalOption_baked_potato"):return
	open_page_ok("lingpopo",3,short_text("baked_potato",1),{"copper_ingot":4,"glass":2,"baked_potato":1},"lingpopo3 baked_potato")
	var image3:Image=await page_shot("goal_lingpopo3_long")
	reason_red(image3,"lingpopo3 baked_potato")
	chip_red(image3,"baked_potato",true,"lingpopo3 baked_potato")
	chip_red(image3,"copper_ingot",false,"lingpopo3 baked_potato")
	differ("base_lingpopo3","goal_lingpopo3_long",0.002,"lingpopo3 no option vs option")
	await close()

## 洛洛 3: options only, no cost; an option makes BondGoalDo enabled.
func luoluo_flow()->void:
	set_bonds();set_done({});stock({})
	await stand("luoluo")
	if not await open_goal("luoluo",3,"luoluo3"):return
	open_page_ok("luoluo",3,Tasks.GOAL_NEED_OPTION,{},"luoluo3 no option")
	await baseline("base_luoluo3")
	if not await press("BondGoalOption_letter"):return
	open_page_ok("luoluo",3,"",{},"luoluo3 letter")
	await page_shot("goal_luoluo3_option")
	differ("base_luoluo3","goal_luoluo3_option",0.002,"luoluo3 no option vs letter")
	await close()

# ------------------------------------------------- batch 2 (needs) flows --

## PRESET (direct write): a bed owned by this player in state.objects at a free cell near
## `near`. Returns the object key so the flow can erase it again.
func place_bed(near:Vector2i)->String:
	var cell:=near+Vector2i(2,2)
	for i in range(64):
		if not w.state.objects.has(World.key(cell)):break
		cell+=Vector2i(1,0)
	var k:=World.key(cell)
	w.state.objects[k]={"type":"bed","owner":id,"items":{}}
	return k

## 阿榆 1 (own_bed + 10 wood): no bed -> bed written -> real BondGoalDo -> ✓ done page ->
## events header count 一起做的事 1／4.
func aru1_flow()->void:
	set_bonds();set_done({});stock({"wood":10})
	await stand("aru")
	var own_bed:=str(Goals.NEEDS["own_bed"])
	check(not Goals.need_met("own_bed",w.state,id),"Fixture starts without an own bed (aru1 %s)"%tag)
	if not await open_events("aru",0):return
	events_ok("aru",0,true,"aru events open")
	check(control("BondGoalCount")!=null and (control("BondGoalCount") as Label).text=="一起做的事 0／4","Count reads 0／4 before completion (aru %s)"%tag)
	await baseline("base_events_aru")
	if not await press_button(control("BondGoalOpen") as Button,"BondGoalOpen aru 1"):return
	check(goal_open("aru",1),"BondGoalOpen opens 和%s一起做的事 (aru1 %s)"%[npc("aru"),tag])
	open_page_ok("aru",1,need_reason(own_bed),{"wood":10},"aru1 no bed")
	var image:Image=await page_shot("goal_aru1_nobed")
	need_line_ok(image,"own_bed",own_bed,false,"aru1 no bed")
	reason_red(image,"aru1 no bed")
	chip_red(image,"wood",false,"aru1 no bed")
	var where:Array=World.bond_place(app.session.snapshot,"aru")
	var bed_key:=place_bed(where[1])
	await refresh()
	check(Goals.need_met("own_bed",w.state,id),"Written bed satisfies own_bed (aru1 %s)"%tag)
	open_page_ok("aru",1,"",{"wood":10},"aru1 ready")
	image=await page_shot("goal_aru1_ready")
	need_line_ok(image,"own_bed",own_bed,true,"aru1 ready")
	chip_red(image,"wood",false,"aru1 ready")
	differ("goal_aru1_nobed","goal_aru1_ready",0.001,"aru1 no bed vs ready")
	if await complete("aru",1,{"wood":10},"","aru1"):
		if await reopen_done("aru",1,"aru1"):
			done_page_ok("aru",1,"aru1 done")
			var done_image:Image=await page_shot("goal_aru1_done")
			keepsake_icon_ok(done_image,"aru1 done")
			differ("goal_aru1_ready","goal_aru1_done",0.01,"aru1 ready vs done")
		if await open_events("aru",0):
			events_ok("aru",0,true,"aru events done")
			check(control("BondGoalCount")!=null and (control("BondGoalCount") as Label).text=="一起做的事 1／4","Count reads 1／4 after completion (aru %s)"%tag)
			await page_shot("events_aru_done")
			differ("base_events_aru","events_aru_done",0.0001,"aru events 0／4 vs 1／4 (whole modal)")
	w.state.objects.erase(bed_key)  # undo the PRESET bed
	await close()

## 星禾 3 (glass_crafted + 2 glass + 2 copper joints): need unmet with items present (the
## reason is the need), then need met with glass short (the reason is the shortage).
func xinghe3_flow()->void:
	set_bonds();set_done({});stock({"glass":2,"copper_joint":2})
	var p:=person()
	var had_flag:=p.has("greenhouse_glass_crafted")
	var old_flag:Variant=p.get("greenhouse_glass_crafted")
	p.greenhouse_glass_crafted=false  # PRESET: never fired glass
	await stand("xinghe")
	var crafted:=str(Goals.NEEDS["glass_crafted"])
	if await open_goal("xinghe",3,"xinghe3"):
		open_page_ok("xinghe",3,need_reason(crafted),{"glass":2,"copper_joint":2},"xinghe3 need")
		var image:Image=await page_shot("goal_xinghe3_need")
		need_line_ok(image,"glass_crafted",crafted,false,"xinghe3 need")
		reason_red(image,"xinghe3 need")
		chip_red(image,"glass",false,"xinghe3 need")
		chip_red(image,"copper_joint",false,"xinghe3 need")
		p.greenhouse_glass_crafted=true  # PRESET: fired glass once
		stock({"glass":1,"copper_joint":2})
		await refresh()
		open_page_ok("xinghe",3,short_text("glass",2),{"glass":2,"copper_joint":2},"xinghe3 short")
		image=await page_shot("goal_xinghe3_short")
		need_line_ok(image,"glass_crafted",crafted,true,"xinghe3 short")
		reason_red(image,"xinghe3 short")
		chip_red(image,"glass",true,"xinghe3 short")
		chip_red(image,"copper_joint",false,"xinghe3 short")
		differ("goal_xinghe3_need","goal_xinghe3_short",0.001,"xinghe3 need vs short")
	if had_flag:p.greenhouse_glass_crafted=old_flag
	else:p.erase("greenhouse_glass_crafted")
	await close()

## 鈴婆婆 4 (festival_done, nothing to deliver): unmet baseline, festival round written,
## the open page refreshes in place to ready.
func lingpopo4_flow()->void:
	set_bonds();set_done({});stock({})
	var old_festival:Variant=w.state.get("festival")
	var saved:Variant=old_festival.duplicate(true) if old_festival is Dictionary else null
	var festival:Dictionary={}
	if old_festival is Dictionary:festival=old_festival
	festival["round"]=0;festival["active"]=false  # PRESET: no relay finished yet
	w.state.festival=festival
	await stand("lingpopo")
	var relay:=str(Goals.NEEDS["festival_done"])
	if await open_goal("lingpopo",4,"lingpopo4"):
		open_page_ok("lingpopo",4,need_reason(relay),{},"lingpopo4 need")
		await baseline("base_lingpopo4")
		if images.has("base_lingpopo4"):
			var base:Image=images["base_lingpopo4"]
			need_line_ok(base,"festival_done",relay,false,"lingpopo4 need")
			reason_red(base,"lingpopo4 need")
		festival["round"]=1;festival["active"]=false  # PRESET: one relay finished
		await refresh()
		open_page_ok("lingpopo",4,"",{},"lingpopo4 ready")
		var image:Image=await page_shot("goal_lingpopo4_ready")
		need_line_ok(image,"festival_done",relay,true,"lingpopo4 ready")
		differ("base_lingpopo4","goal_lingpopo4_ready",0.001,"lingpopo4 need vs ready")
	if saved!=null:w.state.festival=saved
	await close()

## 洛洛 2 (known_three): two residents known besides 洛洛 -> a third one -> can finish.
func luoluo2_flow()->void:
	var strangers:={}
	for resident:String in Bond.RESIDENTS:
		if resident not in ["luoluo","aru","milu","bobo"]:strangers[resident]=0
	var two:=strangers.duplicate()
	two["bobo"]=0
	set_bonds(two);set_done({});stock({})  # PRESET: only 阿榆／米露 known besides 洛洛
	await stand("luoluo")
	check(Goals.known_count(person(),"luoluo")==2,"Preset knows two residents besides 洛洛 (%s): %d"%[tag,Goals.known_count(person(),"luoluo")])
	var base_text:=str(Goals.NEEDS["known_three"])
	var two_text:=base_text+"（目前 2 位）"
	var three_text:=base_text+"（目前 3 位）"
	if not await open_goal("luoluo",2,"luoluo2"):return
	open_page_ok("luoluo",2,need_reason(two_text),{},"luoluo2 two")
	var image:Image=await page_shot("goal_luoluo2_two")
	need_line_ok(image,"known_three",two_text,false,"luoluo2 two")
	reason_red(image,"luoluo2 two")
	set_bonds(strangers)  # PRESET: 波波 back at 好友 -> three known
	await refresh()
	check(Goals.known_count(person(),"luoluo")==3,"Preset knows three residents besides 洛洛 (%s)"%tag)
	open_page_ok("luoluo",2,"",{},"luoluo2 three")
	image=await page_shot("goal_luoluo2_three")
	need_line_ok(image,"known_three",three_text,true,"luoluo2 three")
	differ("goal_luoluo2_two","goal_luoluo2_three",0.001,"luoluo2 two vs three known")
	await close()

# ------------------------------------------------ batch 3 (紀念小物) flows --

## (a) 小栗 4 done with the keepsake already claimed (PRESET): quote + 當時選的是 + keepsake row.
func keepsake_claimed_flow()->void:
	set_bonds()
	set_done({"xiaoli":{"4":"tomorrow"}},{"keepsake_xiaoli":true})  # PRESET: done and claimed earlier
	stock({})
	await refresh()
	if await reopen_done("xiaoli",4,"xiaoli4 claimed"):
		done_page_ok("xiaoli",4,"xiaoli4 claimed")
		check(find_label("當時選的是：明天也在")!=null,"Done page names the chosen option (xiaoli4 %s)"%tag)
		var image:Image=await page_shot("紀念小物_xiaoli4_claimed")
		keepsake_icon_ok(image,"xiaoli4 claimed")
	await close()

## (b)+(c) 米露 3 done before batch 3 and never claimed (PRESET): away -> claim disabled with the
## reason; teleported beside 米露 -> the page refreshes in place, claim enabled; the real
## BondGoalClaim press -> server claim -> the page is rebuilt as claimed.
func keepsake_claim_flow()->void:
	set_bonds()
	set_done({"milu":{"3":"carrot_soup"}})  # PRESET: done before batch 3, nothing claimed
	stock({})
	var kind:="keepsake_milu"
	var kit:=Goals.keepsake_item(kind)
	await stand("milu",true)
	if not await reopen_done("milu",3,"milu3 unclaimed"):
		await close()
		return
	done_page_ok("milu",3,"milu3 away")
	var image:Image=await page_shot("紀念小物_milu3_unclaimed_away")
	keepsake_icon_ok(image,"milu3 away")
	claim_ok("milu",false,image,"milu3 away")
	await stand("milu")
	check(goal_open("milu",3),"Done page stays open after walking over (milu3 %s)"%tag)
	done_page_ok("milu",3,"milu3 near")
	image=await page_shot("紀念小物_milu3_unclaimed_near")
	claim_ok("milu",true,image,"milu3 near")
	differ("紀念小物_milu3_unclaimed_away","紀念小物_milu3_unclaimed_near",0.001,"milu3 claim away vs near")
	check(held(kit)==0 and not Goals.keepsake_claimed(person(),kind),"No %s and no claim before pressing (milu3 %s)"%[kit,tag])
	if app.session.rates.has(1):(app.session.rates[1] as Array).clear()
	if await press("BondGoalClaim",true):
		await refresh()
		check(goal_open("milu",3),"The page stays open after the claim (milu3 %s)"%tag)
		check(held(kit)==1,"%s in the bag after the claim (%d) (milu3 %s)"%[kit,held(kit),tag])
		check(Goals.keepsake_claimed(person(),kind),"player.bond_keepsakes.%s written by the claim (milu3 %s)"%[kind,tag])
		check(toast_text().contains("已放進背包"),"Claim toast says the keepsake is in the bag (milu3 %s): %s"%[tag,toast_text()])
		done_page_ok("milu",3,"milu3 claimed")
		image=await page_shot("紀念小物_milu3_claimed_after")
		keepsake_icon_ok(image,"milu3 claimed")
		differ("紀念小物_milu3_unclaimed_near","紀念小物_milu3_claimed_after",0.002,"milu3 unclaimed vs claimed")
	await close()

# ---------------------------------------------------- batch 3 home helpers --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

func cell_rect(cell:Vector2i)->Rect2:
	return Rect2(app.view.screen(Vector2(cell)),Vector2(32,32))

func hud_panels()->Array:
	var result:=[]
	if not is_instance_valid(app.hud) or not (app.hud as CanvasItem).is_visible_in_tree():return result
	var area:=Vector2(root.size).x*Vector2(root.size).y
	for child in (app.hud as Node).get_children():
		var c:=child as Control
		if c==null or not c.is_visible_in_tree() or c.size.x<=0 or c.size.y<=0:continue
		if c.size.x*c.size.y>area*0.5:continue
		result.append({"name":str(c.name),"rect":c.get_global_rect()})
	return result

## Fraction of all pixels inside `box` that differ between two frames.
func tile_difference(a:Image,b:Image,box:Rect2i)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 0.0
	var r:=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if r.size.x<=0 or r.size.y<=0:return 0.0
	var changed:=0
	for x in range(r.position.x,r.end.x):
		for y in range(r.position.y,r.end.y):
			var p:=a.get_pixel(x,y)
			var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(maxi(1,r.size.x*r.size.y))

## Distinct colours inside `box` (every pixel).
func tile_variety(image:Image,box:Rect2i)->int:
	var r:=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var seen:={}
	for x in range(r.position.x,r.end.x):
		for y in range(r.position.y,r.end.y):
			seen[image.get_pixel(x,y).to_html(false)]=true
	return seen.size()

## Snapshot + HUD + view refresh, then the local player's display snapped to its position
## (no walk-in tween), facing down.
func snap_view()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	await settle()
	drop_ribbon()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	await settle()

## PRESET teleport at home (direct x/y write).
func stand_at(at:Vector2)->void:
	var p:=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await snap_view()

## A home tile a keepsake can go on and the player can stand on today.
func free_cell(c:Vector2i)->bool:
	if not w.is_land(c) or w.water(c) or w.protected(c) or w.blocked(c) or w.resource(c)!="":return false
	var k:=World.key(c)
	return not w.state.objects.has(k) and not w.state.crops.has(k) and not w.state.ground.has(k) and not w.state.roofs.has(k)

## The block's cells and the row south of it (standing / walk-start row) are all free and at
## least 3 tiles from every home resident's spot (their sprites / name tags stay off the tiles).
func block_free(origin:Vector2i,avoid:Array)->bool:
	for j in range(BLOCK_ROWS+1):
		for i in range(BLOCK_COLUMNS):
			var c:=origin+Vector2i(i,j)
			for spot:Vector2i in avoid:
				if maxi(absi(c.x-spot.x),absi(c.y-spot.y))<=2:return false
			if not free_cell(c):return false
	return true

## Nearest free 6×2 block (Chebyshev rings around BLOCK_SEARCH_FROM); (-1,-1) if none.
func find_block()->Vector2i:
	var avoid:Array=[]
	for resident:String in Bond.RESIDENTS:
		var where:Array=World.bond_place(app.session.snapshot,resident)
		if str(where[0])==World.REGIONS.HOME:avoid.append(where[1])
	for r in range(BLOCK_SEARCH_RADIUS+1):
		for dy in range(-r,r+1):
			for dx in range(-r,r+1):
				if maxi(absi(dx),absi(dy))!=r:continue
				var origin:=BLOCK_SEARCH_FROM+Vector2i(dx,dy)
				if block_free(origin,avoid):return origin
	return Vector2i(-1,-1)

func block_cell(origin:Vector2i,index:int)->Vector2i:
	var row:=0 if index<BLOCK_COLUMNS else 1
	return origin+Vector2i(index%BLOCK_COLUMNS,row)

func label_fits(l:Label)->bool:
	if l==null:return false
	var font:Font=l.get_theme_font("font")
	var font_size:int=l.get_theme_font_size("font_size")
	return font.get_string_size(l.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x<=l.size.x+1.0

# ------------------------------------------------- batch 3 folio / backpack --

## (e) 家園工坊 → 「生活」 (BuildTab3) → BuildSlot_<FOLIO_KIND>_3: recipe card with title,
## materials 1／1, the keepsake description fully on view.
func keepsake_folio_flow()->void:
	await close()
	var kind:=FOLIO_KIND
	var keep:Dictionary=Goals.KEEPSAKES[kind]
	var kit:=Goals.keepsake_item(kind)
	app._build_menu()
	await settle()
	check(is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))=="build_folio","家園工坊 opens as the build folio (%s)"%tag)
	if not is_instance_valid(app.modal):return
	if not await press("BuildTab3"):
		await close()
		return
	var tab:=control("BuildTab3") as Button
	check(tab!=null and tab.text=="生活","BuildTab3 is 「生活」 (%s): %s"%[tag,tab.text if tab else "?"])
	var slot:=control("BuildSlot_%s_3"%kind) as Button
	check(slot!=null and slot.is_visible_in_tree(),"「生活」 lists %s (%s)"%[kind,tag])
	if slot==null:
		await close()
		return
	var shelf:Node=slot.get_parent()
	while shelf!=null and not shelf is ScrollContainer:shelf=shelf.get_parent()
	if shelf!=null:(shelf as ScrollContainer).ensure_control_visible(slot)
	await settle()
	if not await press_button(slot,"BuildSlot_%s_3"%kind):
		await close()
		return
	slot.grab_focus()
	await settle()
	check(visible(slot),"Selected slot fully on view in the shelf (%s)"%tag)
	var modal_rect:=(app.modal as Control).get_global_rect()
	check(root.get_visible_rect().encloses(modal_rect),"Build folio fits the viewport (%s) %s"%[tag,str(modal_rect)])
	var title:=control("BuildTitle") as Label
	check(title!=null and title.text==str(World.BUILD[kind]["name"]),"BuildTitle reads %s (%s): %s"%[str(World.BUILD[kind]["name"]),tag,title.text if title else "?"])
	var description:=control("BuildDescription") as Label
	var want:="和%s一起做的事的紀念。%s不擋路，拆除會收回背包。"%[npc(str(keep.resident)),str(keep.blurb)]
	check(description!=null and description.text==want,"BuildDescription is the keepsake blurb (%s): 「%s」"%[tag,description.text if description else "?"])
	check(description!=null and visible(description) and inside_modal(description) and description.get_visible_line_count()>=description.get_line_count(),"BuildDescription fully on view, no scrolling needed (%s)"%tag)
	var place:=control("BuildPlace") as Button
	check(place!=null and place.is_visible_in_tree() and not place.disabled and place.text=="選擇配方","BuildPlace reads 選擇配方 with one kit held (%s): %s"%[tag,place.text if place else "?"])
	check(place!=null and visible(place) and button_not_cut(place),"BuildPlace fully on view (%s)"%tag)
	var status:=control("BuildStatus") as Label
	check(status!=null and status.text=="材料齊全 · 點地面放置","BuildStatus reads 材料齊全 (%s): %s"%[tag,status.text if status else "?"])
	var materials:=control("BuildMaterials")
	var kit_row:=false
	var count_row:=false
	if materials!=null:
		for node in materials.find_children("*","Label",true,false):
			var l:=node as Label
			if not l.is_visible_in_tree():continue
			if l.text==str(World.NAMES[kit]):kit_row=true
			if l.text=="1／1":count_row=true
	check(kit_row and count_row,"Material row %s 1／1 shown (%s)"%[str(World.NAMES[kit]),tag])
	note("build folio %s: BuildTitle 「%s」 fits=%s (width %.0f)"%[tag,title.text if title else "?",str(label_fits(title)),title.size.x if title else 0.0])
	await page_shot("紀念小物_build_lingpopo")
	# Title widths for all twelve (NOTE only: the folio trims long titles with an ellipsis).
	var trimmed:=PackedStringArray()
	for other:String in Goals.KEEPSAKE_ORDER:
		var other_slot:=control("BuildSlot_%s_3"%other) as Button
		check(other_slot!=null,"「生活」 lists %s (%s)"%[other,tag])
		if other_slot==null:continue
		other_slot.pressed.emit()
		await process_frame
		await process_frame
		var t:=control("BuildTitle") as Label
		# Keepsake titles wrap onto at most two lines: every line must be visible.
		if t!=null and not (label_fits(t) or (t.autowrap_mode!=TextServer.AUTOWRAP_OFF and not t.clip_text and t.get_line_count()<=2 and t.get_visible_line_count()==t.get_line_count())):trimmed.append(t.text)
	check(trimmed.is_empty(),"All twelve keepsake titles fit BuildTitle without an ellipsis (%s): %s"%[tag,", ".join(trimmed)])
	await close()
	app._select_tool("hoe")

## (f) The real backpack, 其他 tab, keyboard focus on the FOLIO_KIND kit: name, description
## (blurb + where to place it) and the value line, all fully on view.
func keepsake_inventory_flow()->void:
	await close()
	var kind:=FOLIO_KIND
	var keep:Dictionary=Goals.KEEPSAKES[kind]
	var kit:=Goals.keepsake_item(kind)
	app._inventory()
	await settle()
	check(app.modal is InventoryPanel,"Backpack opens (%s)"%tag)
	if not app.modal is InventoryPanel:
		await close()
		return
	var panel=app.modal
	panel.select_category(4)
	var slot=panel.slots.get(kit)
	check(slot!=null,"Backpack has a slot for %s (%s)"%[kit,tag])
	if slot==null:
		await close()
		return
	(slot as Control).grab_focus()
	await settle()
	check(str(panel.selected_id)==kit,"%s selected by focus (%s): %s"%[kit,tag,str(panel.selected_id)])
	check(slot.visible and int(slot.count)==1,"%s slot shown with 1 (%s)"%[kit,tag])
	var detail_name:Label=panel.detail_name
	var detail_use:Label=panel.detail_use
	var detail_value:Label=panel.detail_value
	check(detail_name.text==str(World.NAMES[kit]),"Detail name %s (%s): %s"%[str(World.NAMES[kit]),tag,detail_name.text])
	check(detail_use.text.begins_with(str(keep.blurb)) and detail_use.text.contains("打開家園工坊，在「生活」分頁選它擺到家園。不擋路，拆除會收回背包。"),"Detail description is the blurb + how to place it (%s): 「%s」"%[tag,detail_use.text])
	check(detail_value.text=="和%s一起做的事的紀念小物 · 不能出售或交易"%npc(str(keep.resident)),"Detail value line (%s): 「%s」"%[tag,detail_value.text])
	for l:Label in [detail_name,detail_use,detail_value]:
		check(visible(l) and inside_modal(l) and l.get_visible_line_count()>=l.get_line_count(),"Backpack detail line whole on view: 「%s」 (%s)"%[l.text,tag])
	var modal_rect:=(app.modal as Control).get_global_rect()
	check(root.get_visible_rect().encloses(modal_rect),"Backpack fits the viewport (%s) %s"%[tag,str(modal_rect)])
	var image:Image=await page_shot("紀念小物_inventory_lingpopo")
	var detail_icon:TextureRect=panel.detail_icon
	var icon_variety:=region_variety(image,pixel_rect(detail_icon))
	note("backpack %s: detail icon rect %s colours %d"%[tag,str(pixel_rect(detail_icon)),icon_variety])
	check(detail_icon.texture!=null and icon_variety>=4,"Backpack detail icon drawn (%d colours) (%s)"%[icon_variety,tag])
	await close()

# ----------------------------------------------------- batch 3 home block --

## (d) Twelve keepsakes placed with real build actions in a 6×2 block, the home captured with
## no modal, then a real server-side walk north through two of them.
func keepsake_home_flow()->void:
	await close()
	set_bonds();set_done({});stock({})
	var origin:=find_block()
	note("keepsake block %s: origin %s"%[tag,str(origin)])
	check(origin.x>=0,"A free 6×2 home block (plus the row south of it) exists near %s (%s)"%[str(BLOCK_SEARCH_FROM),tag])
	if origin.x<0:return
	var inv:=inventory()
	for kind:String in Goals.KEEPSAKE_ORDER:inv[Goals.keepsake_item(kind)]=1  # PRESET: all twelve kits in the bag
	var view_spot:=Vector2(float(origin.x)+BLOCK_COLUMNS*0.5,float(origin.y+BLOCK_ROWS)+2.5)
	await stand_at(view_spot)
	await keepsake_folio_flow()
	await keepsake_inventory_flow()
	await close()
	# Same framing before placing: the empty block.
	app._select_tool("hoe")
	app.target=origin+Vector2i(-2,BLOCK_ROWS)
	await stand_at(view_spot)
	var empty_img:Image=await grab()
	var cells:={}
	for index in range(Goals.KEEPSAKE_ORDER.size()):cells[str(Goals.KEEPSAKE_ORDER[index])]=block_cell(origin,index)
	for column in range(BLOCK_COLUMNS):
		# PRESET teleport onto the free row south of the block: both cells of the column are in reach.
		var p:=person()
		p.region=World.REGIONS.HOME
		p.x=float(origin.x+column)+0.5;p.y=float(origin.y+BLOCK_ROWS)+0.5
		await refresh()
		for kind:String in Goals.KEEPSAKE_ORDER:
			var cell:Vector2i=cells[kind]
			if cell.x!=origin.x+column:continue
			app.building=kind
			app.building_style=""
			app._select_tool("build")
			app.action_clock=0
			if app.session.rates.has(1):(app.session.rates[1] as Array).clear()
			app._use_selected_at(cell)
			await refresh()
			var obj:Variant=w.state.objects.get(World.key(cell),{})
			var placed:=obj is Dictionary and str((obj as Dictionary).get("type",""))==kind and str((obj as Dictionary).get("owner",""))==id
			check(placed,"%s placed at %s by the build action (%s): %s"%[kind,str(cell),tag,toast_text()])
			check(not is_instance_valid(app.modal),"No confirmation modal after placing %s (%s)"%[kind,tag])
	app._select_tool("hoe")
	app.target=origin+Vector2i(-2,BLOCK_ROWS)
	for kind:String in Goals.KEEPSAKE_ORDER:
		check(held(Goals.keepsake_item(kind))==0,"%s spent by the placement (%s): %d"%[Goals.keepsake_item(kind),tag,held(Goals.keepsake_item(kind))])
	await stand_at(view_spot)
	check(not is_instance_valid(app.modal),"Home captured with no modal open (%s)"%tag)
	var block_img:Image=await page_shot("紀念小物_home_block")
	var screen_rect:=Rect2(Vector2.ZERO,Vector2(root.size))
	var panels:=hud_panels()
	var least:=1.0
	for kind:String in Goals.KEEPSAKE_ORDER:
		var cell:Vector2i=cells[kind]
		var px:=view_to_pixels(cell_rect(cell))
		check(screen_rect.encloses(px),"%s tile on screen (%s) %s"%[kind,tag,str(px)])
		for panel:Dictionary in panels:check(not px.intersects(panel.rect),"%s tile clear of HUD %s (%s)"%[kind,str(panel.name),tag])
		var box:=pixel_box(cell_rect(cell))
		var changed:=tile_difference(empty_img,block_img,box)
		var variety:=tile_variety(block_img,box)
		least=minf(least,changed)
		note("home block %s: %s at %s box %s changed %.0f%% colours %d"%[tag,kind,str(cell),str(box),changed*100.0,variety])
		check(changed>=0.10,"%s drawn on its tile (%.0f%% of the tile changed vs the empty frame) (%s)"%[kind,changed*100.0,tag])
		check(variety>=3,"%s tile is not a flat colour (%d colours) (%s)"%[kind,variety,tag])
		check(w.can_stand(Vector2(cell)+Vector2(0.5,0.5)),"%s tile can be stood on (walk-through) (%s)"%[kind,tag])
	note("home block %s: least tile change %.0f%%"%[tag,least*100.0])
	# Walk north (server movement) from the free row through row 1 and into row 0 of one column.
	var lane:=origin.x+WALK_COLUMN
	var start:=Vector2(float(lane)+0.5,float(origin.y+BLOCK_ROWS)+0.5)
	var goal_y:=float(origin.y)+0.5
	var walker:=person()
	walker.region=World.REGIONS.HOME
	walker.x=start.x;walker.y=start.y  # PRESET teleport to the walk start
	for i in range(40):
		if float(person().y)<=goal_y+0.001:break
		w.move_player(id,Vector2(0,-1),0.05)
	var crossed:=float(person().y)<=goal_y+0.001 and absf(float(person().x)-start.x)<0.001
	check(crossed,"Player walks north through %s and %s (%s): at (%.2f,%.2f), goal y %.2f"%[str(Goals.KEEPSAKE_ORDER[WALK_COLUMN+BLOCK_COLUMNS]),str(Goals.KEEPSAKE_ORDER[WALK_COLUMN]),tag,float(person().x),float(person().y),goal_y])
	await snap_view()
	await page_shot("紀念小物_home_walkthrough")
	# Undo the placement so the next size starts from the same state.
	for kind:String in Goals.KEEPSAKE_ORDER:w.state.objects.erase(World.key(cells[kind]))
	stock({})
	await refresh()

func heights_note()->void:
	var parts:=PackedStringArray()
	var tallest:=""
	var top:=0.0
	for step:String in heights:
		var h:float=float(heights[step])
		parts.append("%s=%.0f"%[step,h])
		if step.begins_with("goal_") and h>top:
			top=h
			tallest=step
	note("modal heights %s: %s; tallest goal page %s"%[tag,", ".join(parts),tallest])

# ---------------------------------------------------------------- run --

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	var started:=Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/居民一起做的事預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("goal-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"一起做的事旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	w.state.picnic=true  # PRESET: 洛洛／鈴婆婆 present
	check(Goals.total()==48,"Forty-eight goals (%d)"%Goals.total())
	for size:Vector2i in SIZES:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		images.clear()
		boxes.clear()
		heights.clear()
		var shots_before:=shots
		await close()
		await milu_flow()
		await bobo_flow()
		await xinghe_flow()
		await aru_flow()
		await lingpopo_flow()
		await luoluo_flow()
		# Batch 2 (needs): after the batch 1 shots so those stay comparable.
		await aru1_flow()
		await xinghe3_flow()
		await lingpopo4_flow()
		await luoluo2_flow()
		# Batch 3 (紀念小物): after batches 1–2 so those shots stay comparable.
		await keepsake_claimed_flow()
		await keepsake_claim_flow()
		await keepsake_home_flow()
		await close()
		app._select_tool("hoe")
		heights_note()
		for step:String in KEEPSAKE_SHOTS:
			check(written.has("%s_%s.png"%[tag,step]),"Batch 3 screenshot written: %s_%s.png"%[tag,step])
		note("size %s: %d screenshots; done at %.1f s"%[tag,shots-shots_before,(Time.get_ticks_msec()-started)/1000.0])
	var per_size:=SHOTS_BATCH1+SHOTS_BATCH2+KEEPSAKE_SHOTS.size()
	check(shots==per_size*SIZES.size(),"%d screenshots per size (%d batch 1 + %d batch 2 + %d batch 3) × %d sizes (%d)"%[per_size,SHOTS_BATCH1,SHOTS_BATCH2,KEEPSAKE_SHOTS.size(),SIZES.size(),shots])
	note("images written (%d) to %s: %s"%[written.size(),output,", ".join(written)])
	images.clear()
	set_done({})
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	note("finished at %.1f s"%[(Time.get_ticks_msec()-started)/1000.0])
	finish()
