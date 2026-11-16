extends SceneTree
## 第 40 章「茶陶上桌」native render check of the tea set on the 風鈴渡口 shared table, at
## 1024×640 and 1280×800. Run non-headless:
##   --script res://tests/test_tea_service_scene.gd -- --profile=isolated-regression
## Screenshots go to outputs/茶陶上桌預覽 (or --capture-dir=), named <w>x<h>_<step>.png;
## probe_*.png (once) are 4× offscreen draws of community_art.draw_table.
##
## Art is runtime-painted, no new PNGs: community_art.draw_tea_set (a walnut side stand
## against the table's left end with the red-brown tray, the ivory/indigo teapot and six
## 4×4 cups seen from above — a cream rim ring around a 2×2 tea surface; palette from
## tea_revisit_art.gd plus the TEA_* surface colours), drawn by draw_table's trailing
## `tea` argument from world_view's table block.
##
## PRESET / FIXTURE (not human play, nothing here goes through a player action):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.board / state.picnic / state.community (table cell, hotpot and watermelon
##    rounds) written directly;
##  * state.table_warmer written / erased directly;
##  * state.tea_service written / erased directly (placed, light / deep rounds, a
##    finished round, a cold round, and for the page shots a light 4／6 round lent and
##    sipped by me and a cold deep round lent by "tea-lender-fixture"; every round carries
##    "day" — today's world day (TeaService.today(state)) for fresh / finished rounds,
##    today−1 for the cold one; "claimed" and the fixture lender use made-up tokens that
##    are NOT world players — the record would not pass tea_service.valid, which is never
##    called here);
##  * state.time written directly for the cold checks: moved forward a whole number of
##    days (same time of day, the next sunny day of the cycle) so a round dated the day
##    before is cold, then restored. Fresh / cold / finished comparison shots of the cold
##    step are all taken at that same later time;
##  * page shots only: state.tea_revisit (茶罐大單) is WRITTEN as a completed record or
##    erased, and my bag's tea_ware_kit / tea_light / tea_deep are WRITTEN; both are put
##    back to their earlier values after the page step. The world art does not depend on
##    either;
##  * the local player is teleported by writing x/y; app.view.reduced_motion set directly;
##  * the 渡口的共餐桌 page is opened by calling app._community_menu() (the same
##    CommunityUI.open the interact key reaches at the table; no key event is sent) and
##    closed with app._close_modal().
## REALLY EXERCISED: Session._send_snapshot → snapshot.tea_service public shape (incl. the
##  recipient's lender_own / sipped_own) → the real world_view table block
##  (TeaService.current_round on the snapshot, incl. its time) →
##  community_art.draw_table(...,tea) on the native renderer, the focused 「community」
##  label text from world_view.world_label_placements, and the real community_ui page
##  (build + refresh from that snapshot, main._layout_preview) on the native renderer.
## NOT EXERCISED: place / brew / sip / take actions, keyboard / gamepad input on the page,
##  tea_service rules, a day actually passing in the running world (time is written).
##
## SHOTS per size (13 + 9 crops + 4 pages = 26): none, placed, light6, light2, deep6,
##  finished, fresh_later, cold, finished_later, light6_motion, all_without, all_with,
##  focus; crops crop_none / crop_placed / crop_light6 / crop_light2 / crop_deep6 /
##  crop_finished / crop_cold / crop_light6_motion / crop_all_with; pages page_placeable /
##  page_locked / page_sipped4 / page_cold → 26 per size.
##  Probes (once, 4×): probe_old, probe_tea, probe_all_tea, probe_cold, probe_states
##  → 57 in total.
## READABILITY (probe, 1×): the mean colour of the 24 cup-surface pixels (6 cups ×
##  TEA_SURFACE) is measured for never brewed / fresh light / fresh deep / cold light /
##  cold deep / drunk (light and deep), and every pair must be ≥ MIN_SURFACE_DISTANCE apart
##  (Euclidean RGB distance on the 0–1 channel values of the rendered image), and every
##  surface ≥ MIN_SURFACE_DISTANCE from the cream rim.
## Comparison shots use reduced motion (static steam wisp, no community feedback
## animation); light6_motion is the only motion-on screenshot (the cold motion-on
## frames are grabbed, not saved).
const World=preload("res://scripts/world.gd")
const TeaService=preload("res://scripts/tea_service.gd")
const Art=preload("res://scripts/community_art.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const CommunityUI=preload("res://scripts/community_ui.gd")
const TeaArt=preload("res://scripts/tea_revisit_art.gd")
const TABLE:=Vector2i(39,30)
## Minimum Euclidean RGB distance (0–1 channels) between the mean cup-surface colours of
## any two tea states, and between any surface and the cream rim.
const MIN_SURFACE_DISTANCE:=0.18
## The tea card's controls checked on every page shot (hidden ones are skipped, except
## TeaChip / TeaStatus, which must always be shown).
const TEA_CARD_IDS:=["TeaChip","TeaStatus","TeaPlace","TeaBrew_light","TeaBrew_deep","TeaSip","TeaTake","TeaReason"]
## Fixture lender token for the cold page (NOT a world player).
const FIXTURE_LENDER:="tea-lender-fixture"
## West of the table: the table is focused (same spot as test_table_warmer_scene).
const FOCUS_SPOT:=Vector2(38.0,31.5)
## South-east viewing spot: table, tea stand and plaza in view, player clear of them.
const VIEW_SPOT:=Vector2(41.2,31.7)
## Dish art regions relative to the table cell origin (community_art.draw_table with a
## hotpot round and a watermelon platter: soup icon 18×18 at (2,1), bowls along y 18..20,
## watermelon 13×11 at (17,5)); the warmer slab is Art.WARMER_RECT.
const HOTPOT_BOX:=Rect2(2,1,18,18)
const BOWLS_BOX:=Rect2(3,17,27,5)
const MELON_BOX:=Rect2(17,5,13,11)
## Where the teapot steam wisp can appear (above the knob at x -21, incl. its ±1 px
## drift), relative to the table cell origin; the knob itself (y 3..4) is outside.
const STEAM_BOX:=Rect2(-25,-8,9,11)
## Offscreen probe: viewport size and where the table cell origin sits in it.
const PROBE_SIZE:=Vector2i(72,64)
const PROBE_ORIGIN:=Vector2(30,22)
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0
var probe_view:SubViewport
var probe_node:Node2D
var probe_variant:=""

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("TEA_SERVICE_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):(app.toast as Label).hide()

func refresh()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	hide_toast()
	await settle()

func colour_variety(image:Image)->int:
	var seen:={}
	for gx in range(24):
		for gy in range(16):
			seen[image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0)).to_html(false)]=true
	return seen.size()

func save_image(image:Image,step:String)->void:
	var file:=output.path_join("%s_%s.png"%[tag,step] if not tag.is_empty() else "%s.png"%step)
	check(image.save_png(file)==OK,"native screenshot saved %s"%file.get_file())
	shots+=1
	print("TEA_SERVICE_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])

func shot(step:String)->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	check(image!=null and not image.is_empty(),"non-empty native image %s_%s"%[tag,step])
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size (%s_%s)"%[tag,step])
	check(colour_variety(image)>=12,"Screenshot is not blank (%s_%s)"%[tag,step])
	save_image(image,step)
	return image

func grab()->Image:
	hide_toast()
	await create_timer(0.2).timeout
	await settle()
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func person()->Dictionary:
	return w.state.players[id]

func stand(at:Vector2)->void:
	var p:Dictionary=person()
	p.region=World.REGIONS.HOME
	p.x=at.x;p.y=at.y
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	v.stride_stop.erase(me)
	v.facings[me]=Vector2i.DOWN
	await settle()

# ------------------------------------------------------------- world view --

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

func pixel_box(rect:Rect2)->Rect2i:
	var r:=view_to_pixels(rect)
	return Rect2i(Vector2i(r.position.round()),Vector2i(r.size.round()))

## Screen pixels per view pixel (the world zoom as rendered).
func px_scale()->float:
	return maxf(1.0,view_to_pixels(Rect2(0,0,10,10)).size.x/10.0)

func changed_pixels(a:Image,b:Image,box:Rect2i)->int:
	if a==null or b==null or a.get_size()!=b.get_size():return -1
	box=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if box.size.x<=0 or box.size.y<=0:return -1
	var changed:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return changed

func box_difference(a:Image,b:Image,box:Rect2i)->float:
	box=box.intersection(Rect2i(Vector2i.ZERO,a.get_size() if a!=null else Vector2i.ZERO))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	return float(maxi(0,changed_pixels(a,b,box)))/float(box.size.x*box.size.y)

func table_origin()->Vector2:
	return app.view.screen(Vector2(TABLE))

func cell_rect(local:Rect2)->Rect2:
	return Rect2(table_origin()+local.position,local.size)

func tea_box()->Rect2i:
	return pixel_box(cell_rect(Art.TEA_RECT))

## 3× crop around the table and the tea stand for review.
func save_crop(image:Image,step:String)->void:
	var box:=pixel_box(Rect2(table_origin()+Vector2(-40,-40),Vector2(96,80))).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if box.size.x<=0 or box.size.y<=0:return
	var crop:=image.get_region(box)
	crop.resize(box.size.x*3,box.size.y*3,Image.INTERPOLATE_NEAREST)
	save_image(crop,step)

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func table_label_title()->String:
	for entry:Dictionary in placements():
		if str(entry.id)=="community":return str(entry.title)
	return ""

## The tea stand is on screen and no world label sits on it (VIEW_SPOT shots).
func stand_clear(label:String)->void:
	var r:=view_to_pixels(cell_rect(Art.TEA_RECT))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(r),"Whole tea stand on screen (%s) %s"%[label,str(r)])
	var inner:=cell_rect(Rect2(Art.TEA_RECT.position+Vector2(0,6),Art.TEA_RECT.size-Vector2(0,6))).grow(-1.0)
	for entry:Dictionary in placements():
		check(not (entry.rect as Rect2).intersects(inner),"Label 「%s」 not over the tea stand (%s) %s vs %s"%[entry.title,label,str(entry.rect),str(inner)])

# ------------------------------------------------------------------ state --

## Server-shaped round record; `day` < 0 means today's world day (fresh tea).
func tea_round(style:String,left:int,day:int=-1)->Dictionary:
	var claimed:={}
	for i in range(TeaService.CUPS-left):claimed["tea-guest-%d"%i]=true  # FIXTURE tokens
	var brewed:int=day if day>=0 else TeaService.today(w.state)
	return {"lender":id,"round":{"style":style,"portions":left,"claimed":claimed,"day":brewed}}

## Whole days to add to state.time so the new day is a sunny one (same time of day).
func sunny_days_ahead()->int:
	var base:float=World.WEATHER.day_index(w.state.get("time",0.0))
	for k in range(1,8):
		if World.WEATHER.outdoor_id(base+float(k))=="sunny":return k
	return 1

## PRESET: move world time forward to a later sunny day; returns the old time.
func advance_days()->float:
	var saved:float=float(w.state.get("time",0.0))
	w.state.time=saved+float(sunny_days_ahead())*World.WEATHER.DAY_SECONDS  # PRESET
	return saved

func view_round()->Dictionary:
	return TeaService.current_round(app.view.data)

func set_tea(record:Dictionary)->void:
	if record.is_empty():w.state.erase(TeaService.STATE_KEY)  # PRESET
	else:w.state[TeaService.STATE_KEY]=record.duplicate(true)  # PRESET
	await refresh()

func set_dishes(on:bool)->void:
	if on:
		w.state.community={"table":World.COMMUNITY.cell_key(TABLE),"hotpot":{"portions":6,"claimed":{},"total":6},"watermelon":{"portions":4,"claimed":{}}}  # PRESET
		w.state.table_warmer={"installed":true}  # PRESET
	else:
		w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}  # PRESET
		w.state.erase("table_warmer")  # PRESET
	await refresh()

func snapshot_tea()->Dictionary:
	var found:Variant=app.view.data.get(TeaService.STATE_KEY,{})
	return found if found is Dictionary else {}

# ------------------------------------------------------------------ flows --

func size_flow()->void:
	if is_instance_valid(app.modal):app._close_modal()
	app.view.reduced_motion=true
	await set_dishes(false)
	await set_tea({})
	await stand(VIEW_SPOT)
	var s:=px_scale()
	var cup_px:=s*s
	print("NOTE %s: %.1f screen px per view px, tea box %s"%[tag,s,str(tea_box())])
	# 1. No set: the baseline.
	check(snapshot_tea().is_empty(),"No tea_service in the snapshot (%s)"%tag)
	var none:Image=await shot("none")
	save_crop(none,"crop_none")
	stand_clear("none "+tag)
	# 2. Placed, never brewed.
	await set_tea({"lender":id})
	check(snapshot_tea().get("placed")==true and not snapshot_tea().has("round") and not snapshot_tea().has("lender"),"Snapshot carries the placed set, no token (%s): %s"%[tag,str(snapshot_tea())])
	var placed_img:Image=await shot("placed")
	save_crop(placed_img,"crop_placed")
	stand_clear("placed "+tag)
	var drawn:=box_difference(none,placed_img,tea_box())
	print("NOTE %s: tea box changed %.0f%% when placed"%[tag,drawn*100.0])
	check(drawn>=0.25,"Tea stand drawn when placed (%.0f%% of the tea box) %s"%[drawn*100.0,tag])
	# 3. Light round, six cups.
	await set_tea(tea_round("light",6))
	var today:int=TeaService.today(w.state)
	check(snapshot_tea().get("round")=={"style":"light","portions":6,"day":today},"Snapshot round light 6, day %d (%s): %s"%[today,tag,str(snapshot_tea())])
	check(view_round()=={"style":"light","portions":6,"day":today,"left":6,"cold":false},"Fresh round drinkable in the view snapshot (%s): %s"%[tag,str(view_round())])
	var light6:Image=await shot("light6")
	save_crop(light6,"crop_light6")
	# 4. Light round, two cups left.
	await set_tea(tea_round("light",2))
	var light2:Image=await shot("light2")
	save_crop(light2,"crop_light2")
	# 5. Deep round, six cups.
	await set_tea(tea_round("deep",6))
	var deep6:Image=await shot("deep6")
	save_crop(deep6,"crop_deep6")
	# 6. Finished light round.
	await set_tea(tea_round("light",0))
	var done:Image=await shot("finished")
	save_crop(done,"crop_finished")
	var box:=tea_box()
	var served:=changed_pixels(placed_img,light6,box)
	var six_two:=changed_pixels(light6,light2,box)
	var light_deep:=changed_pixels(light6,deep6,box)
	var done_served:=changed_pixels(light6,done,box)
	var done_empty:=changed_pixels(placed_img,done,box)
	print("NOTE %s changed px: empty→light6 %d, light6→light2 %d, light6→deep6 %d, light6→finished %d, empty→finished %d"%[tag,served,six_two,light_deep,done_served,done_empty])
	# Six cups × 4 surface pixels (+ the steam wisp); four cups change for 6→2 (16 px);
	# finished turns all 24 surface pixels from tea to clean inside + dreg; never brewed →
	# finished differs in the six dreg dots only.
	check(served>=int(20.0*cup_px),"Served round differs from the empty set (%d px) %s"%[served,tag])
	check(six_two>=int(12.0*cup_px),"Six cups differ from two cups (%d px) %s"%[six_two,tag])
	check(light_deep>=int(20.0*cup_px),"Light tea differs from deep tea (%d px) %s"%[light_deep,tag])
	check(done_served>=int(20.0*cup_px),"Finished round differs from a served one (%d px) %s"%[done_served,tag])
	check(done_empty>=int(4.0*cup_px),"Finished cups (dregs) differ from never-brewed cups (%d px) %s"%[done_empty,tag])
	check(box_difference(none,done,box)>=0.25,"Set still drawn after the round is finished (%s)"%tag)
	# 6b. Cold (yesterday's) tea. PRESET: world time moved forward whole days; fresh, cold
	# and finished are all shot at that same later time (same light / tint in the box).
	var saved_time:float=advance_days()
	var later:int=TeaService.today(w.state)
	await set_tea(tea_round("light",6,later))
	check(not view_round().get("cold",true) and int(view_round().get("portions",0))==6,"Round brewed today is fresh at the later time (%s): %s"%[tag,str(view_round())])
	var fresh_later:Image=await shot("fresh_later")
	await set_tea(tea_round("light",6,later-1))
	check(snapshot_tea().get("round")=={"style":"light","portions":6,"day":later-1},"Snapshot keeps yesterday's six cups (%s): %s"%[tag,str(snapshot_tea())])
	check(view_round()=={"style":"light","portions":0,"day":later-1,"left":6,"cold":true},"Yesterday's round is cold: 0 drinkable, 6 left (%s): %s"%[tag,str(view_round())])
	var cold:Image=await shot("cold")
	save_crop(cold,"crop_cold")
	stand_clear("cold "+tag)
	await set_tea(tea_round("light",0,later))
	var done_later:Image=await shot("finished_later")
	var steam_box:=pixel_box(cell_rect(STEAM_BOX))
	var cold_fresh:=changed_pixels(fresh_later,cold,box)
	var cold_done:=changed_pixels(done_later,cold,box)
	var cold_cups:=changed_pixels(fresh_later,cold,box)-changed_pixels(fresh_later,cold,steam_box)
	print("NOTE %s changed px at the later time: fresh→cold %d (cups %d, steam %d), finished→cold %d"%[tag,cold_fresh,cold_cups,changed_pixels(fresh_later,cold,steam_box),cold_done])
	# Six cups × 4 surface pixels change colour (fresh→cold), or go from dregs to tea (finished→cold).
	check(cold_cups>=int(18.0*cup_px),"Cold cups differ from fresh cups (%d px outside the steam zone) %s"%[cold_cups,tag])
	check(cold_done>=int(18.0*cup_px),"Cold cups differ from a finished round (%d px) %s"%[cold_done,tag])
	check(changed_pixels(done_later,cold,steam_box)==0,"Cold set has no static steam wisp (same steam zone as finished) %s"%tag)
	check(box_difference(none,cold,box)>=0.25,"Set drawn when the tea is cold (%s)"%tag)
	# Motion on: no steam animation for cold tea (steam zone identical across two frames).
	await set_tea(tea_round("light",6,later-1))
	app.view.reduced_motion=false
	var cold_a:Image=await grab()
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var cold_b:Image=root.get_texture().get_image()
	check(changed_pixels(cold_a,cold_b,steam_box)==0,"Cold tea: no steam animation with motion on (%d px changed) %s"%[changed_pixels(cold_a,cold_b,steam_box),tag])
	check(changed_pixels(cold,cold_a,steam_box)==0,"Cold tea: motion-on steam zone same as the reduced-motion shot (%s)"%tag)
	print("NOTE %s: motion-on cold tea box changed %d px over 0.7 s"%[tag,changed_pixels(cold_a,cold_b,box)])
	app.view.reduced_motion=true
	w.state.time=saved_time  # PRESET restore
	await set_tea({})
	check(TeaService.today(w.state)<later,"World time restored after the cold step (%s)"%tag)
	# Reduced motion: static across two times (light round, steam is a still wisp).
	await set_tea(tea_round("light",6))
	var still_a:Image=await grab()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var still_b:Image=root.get_texture().get_image()
	check(changed_pixels(still_a,still_b,box)==0,"Tea set static with reduced motion (%d px changed) %s"%[changed_pixels(still_a,still_b,box),tag])
	check(box_difference(light6,still_a,box)<=0.01,"Same reduced-motion frame as the light6 shot (%s)"%tag)
	# Motion on: the set is still drawn (the wisp rises; NOTE only).
	app.view.reduced_motion=false
	var moving:Image=await shot("light6_motion")
	save_crop(moving,"crop_light6_motion")
	check(box_difference(none,moving,box)>=0.25,"Tea stand drawn with motion on (%s)"%tag)
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	print("NOTE %s: motion-on tea box changed %d px over 0.7 s (steam)"%[tag,changed_pixels(moving,root.get_texture().get_image(),box)])
	app.view.reduced_motion=true
	# 7. Everything on the table: hotpot (warm six), watermelon, warmer, then the tea set.
	await set_tea({})
	await set_dishes(true)
	var without:Image=await shot("all_without")
	await set_tea(tea_round("deep",6))
	var all_with:Image=await shot("all_with")
	save_crop(all_with,"crop_all_with")
	stand_clear("all "+tag)
	check(box_difference(none,without,pixel_box(cell_rect(HOTPOT_BOX)))>=0.08,"Hotpot drawn in its box (%s)"%tag)
	check(box_difference(none,without,pixel_box(cell_rect(MELON_BOX)))>=0.08,"Watermelon drawn in its box (%s)"%tag)
	check(box_difference(none,without,pixel_box(cell_rect(Art.WARMER_RECT)))>=0.3,"Warmer drawn in its box (%s)"%tag)
	for entry:Array in [["hotpot",HOTPOT_BOX],["bowls",BOWLS_BOX],["watermelon",MELON_BOX],["warmer",Art.WARMER_RECT]]:
		var n:=changed_pixels(without,all_with,pixel_box(cell_rect(entry[1])))
		check(n==0,"Tea set leaves the %s art uncovered (%d px changed) %s"%[entry[0],n,tag])
	check(box_difference(without,all_with,box)>=0.25,"Tea stand drawn next to the full table (%s)"%tag)
	# Focused: the table label lists the tea count.
	await stand(FOCUS_SPOT)
	check(str(app.view.interaction_focus())=="community","Table focused from the west (%s): %s"%[tag,str(app.view.interaction_focus())])
	await shot("focus")
	var title:=table_label_title()
	check(title.contains("火鍋 6") and title.contains("西瓜 4") and title.contains("茶 6"),"Focused label lists 火鍋 / 西瓜 / 茶 6 (%s): 「%s」"%[tag,title])
	await set_tea(tea_round("light",2))
	title=table_label_title()
	check(title.contains("茶 2"),"Focused label shows 茶 2 (%s): 「%s」"%[tag,title])
	# Cold tea (PRESET time forward, round dated the day before): no 茶 count.
	var focus_saved:float=advance_days()
	await set_tea(tea_round("deep",6,TeaService.today(w.state)-1))
	title=table_label_title()
	check(view_round().get("cold")==true and str(app.view.interaction_focus())=="community","Cold round with the table focused (%s): %s"%[tag,str(view_round())])
	check(title.contains("火鍋 6") and title.contains("西瓜 4") and not title.contains("茶"),"Cold tea drops 茶 from the label (%s): 「%s」"%[tag,title])
	w.state.time=focus_saved  # PRESET restore
	await set_tea(tea_round("light",2))
	check(table_label_title().contains("茶 2"),"Back to today's time: 茶 2 again (%s): 「%s」"%[tag,table_label_title()])
	await set_tea(tea_round("light",0))
	title=table_label_title()
	check(not title.contains("茶"),"Finished round drops 茶 from the label (%s): 「%s」"%[tag,title])
	await set_dishes(false)
	await set_tea({"lender":id})
	title=table_label_title()
	check(title=="渡口餐桌","Empty set keeps the plain table label (%s): 「%s」"%[tag,title])
	# Back to nothing: the scene is identical to the first baseline in the tea box.
	await set_tea({})
	await stand(VIEW_SPOT)
	var again:Image=await grab()
	check(box_difference(none,again,box)<=0.01,"Removing the set restores the baseline (%s)"%tag)

# ------------------------------------------------------------------- page --

func page_open()->bool:
	return CommunityUI.is_open(app) and str((app.modal as Node).get_meta("life_modal_layout",""))==CommunityUI.LAYOUT

func page_node(node_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(node_name,true,false) as Control

func page_shown(node_name:String)->bool:
	var c:=page_node(node_name)
	return c!=null and c.is_visible_in_tree()

func page_text(node_name:String)->String:
	var l:=page_node(node_name) as Label
	return l.text if l!=null else ""

## Opens 渡口的共餐桌 the way the interact key does at the table (main._community_menu →
## CommunityUI.open) and lets the deferred layout settle.
func open_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	app._community_menu()
	await settle()
	await settle()

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()
	check(not is_instance_valid(app.modal),"Page closed (%s)"%tag)

## Screenshot pixels of a control (canvas → viewport → window transform).
func screen_rect(c:Control)->Rect2i:
	var xf:Transform2D=root.get_final_transform()*c.get_global_transform_with_canvas()
	var a:Vector2=xf*Vector2.ZERO
	var b:Vector2=xf*c.size
	return Rect2i(Vector2i(a.round()),Vector2i((b-a).round()))

## Modal open, tea card controls inside the panel / the scroll area / the viewport, no
## clipped label or button caption in the card, the card's pixels are not blank.
func page_checks(state:String,image:Image)->void:
	var label:="%s %s"%[state,tag]
	check(page_open(),"渡口的共餐桌 page open (%s)"%label)
	if not page_open():return
	var modal:Control=app.modal
	var panel_rect:=modal.get_global_rect().grow(0.5)
	var view_rect:=root.get_visible_rect().grow(0.5)
	check(view_rect.encloses(modal.get_global_rect()),"Page panel inside the viewport (%s) %s"%[label,str(modal.get_global_rect())])
	var outer:=page_node("ModalScroll") as ScrollContainer
	var card:=page_node("TeaCard")
	check(card!=null and card.is_visible_in_tree(),"茶陶上桌 card shown (%s)"%label)
	if card==null:return
	check(panel_rect.encloses(card.get_global_rect()) and view_rect.encloses(card.get_global_rect()),"茶陶上桌 card inside the panel and the viewport (%s) %s"%[label,str(card.get_global_rect())])
	for node_name:String in TEA_CARD_IDS:
		var c:=page_node(node_name)
		var required:=node_name=="TeaChip" or node_name=="TeaStatus"
		if c==null or not c.is_visible_in_tree():
			if required:check(false,"%s shown (%s)"%[node_name,label])
			continue
		var r:=c.get_global_rect()
		check(panel_rect.encloses(r),"%s inside the page panel (%s) %s vs %s"%[node_name,label,str(r),str(modal.get_global_rect())])
		check(view_rect.encloses(r),"%s inside the viewport (%s) %s"%[node_name,label,str(r)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(r),"%s inside the visible scroll area (%s) %s"%[node_name,label,str(r)])
	for node in card.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		var need:=l.get_combined_minimum_size()
		var whole:=need.x<=l.size.x+0.5 and need.y<=l.size.y+0.5 and l.get_visible_line_count()>=l.get_line_count() and not l.clip_text and l.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING
		check(whole,"Label not clipped: %s 「%s」 (%s) min=%s size=%s lines %d/%d"%[l.name,l.text,label,str(need),str(l.size),l.get_visible_line_count(),l.get_line_count()])
	for node in card.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(b.size.x+0.5>=b.get_combined_minimum_size().x and not b.clip_text,"Button caption whole: %s 「%s」 (%s)"%[b.name,b.text,label])
	if image==null or image.is_empty():return
	var box:=screen_rect(card).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	check(box.size.x>=100 and box.size.y>=40,"Card region on the screenshot (%s) %s"%[label,str(box)])
	if box.size.x<=0 or box.size.y<=0:return
	var seen:={}
	var dark:=0
	var total:=0
	for x in range(box.position.x,box.end.x,2):
		for y in range(box.position.y,box.end.y,2):
			var p:=image.get_pixel(x,y)
			seen[p.to_html(false)]=true
			total+=1
			if p.get_luminance()<0.45:dark+=1
	var ink:=float(dark)/float(maxi(1,total))
	print("NOTE page %s: card %s, %d colours, %.1f%% dark pixels"%[label,str(box),seen.size(),ink*100.0])
	check(seen.size()>=16 and ink>=0.005,"Card pixels not blank (%s): %d colours, %.1f%% ink"%[label,seen.size(),ink*100.0])

func set_revisit(done:bool)->void:
	if done:w.state.tea_revisit={"jars":{"tea_returned_jar":3,"tea_worn_jar":3},"filled":{"light":3,"deep":3},"day":1,"completed":true,"done_day":1,"claimed":{}}  # PRESET
	else:w.state.erase("tea_revisit")  # PRESET

func set_bag(values:Dictionary)->void:
	var bag:Dictionary=person().inventory
	for item:String in values:
		if int(values[item])>0:bag[item]=int(values[item])  # PRESET
		else:bag.erase(item)  # PRESET

## Native shots of the 渡口的共餐桌 page with the 茶陶上桌 card in four states.
func page_flow()->void:
	app.view.reduced_motion=true
	var bag:Dictionary=person().inventory
	var saved_bag:={}
	for item in ["tea_ware_kit","tea_light","tea_deep"]:
		if bag.has(item):saved_bag[item]=bag[item]
	var saved_revisit:Variant=w.state.get("tea_revisit")
	await set_dishes(false)
	# (a) Revisit done, kit in the bag, nothing on the table: 擺上茶陶組 enabled.
	set_revisit(true)
	set_bag({"tea_ware_kit":1,"tea_light":0,"tea_deep":0})
	await set_tea({})
	await open_page()
	check(page_shown("TeaPlace") and not (page_node("TeaPlace") as Button).disabled and not page_shown("TeaReason"),"Placeable: 擺上茶陶組 enabled, no reason (%s)"%tag)
	check(page_text("TeaChip")==CommunityUI.TEA_CHIP_NONE,"Placeable chip 未擺上 (%s): %s"%[tag,page_text("TeaChip")])
	var shot_placeable:Image=await shot("page_placeable")
	page_checks("placeable",shot_placeable)
	await close_page()
	# (b) Revisit not done: 擺上茶陶組 disabled, NOT_DONE reason visible.
	set_revisit(false)
	await refresh()
	await open_page()
	check(page_shown("TeaPlace") and (page_node("TeaPlace") as Button).disabled,"Locked: 擺上茶陶組 disabled (%s)"%tag)
	check(page_shown("TeaReason") and page_text("TeaReason")==TeaService.NOT_DONE,"Locked reason visible (%s): %s"%[tag,page_text("TeaReason")])
	var shot_locked:Image=await shot("page_locked")
	page_checks("locked",shot_locked)
	await close_page()
	# (c) Light 4／6, I lent the set and sipped; warmer not installed (tallest page).
	set_revisit(true)
	set_bag({"tea_ware_kit":0,"tea_light":1,"tea_deep":0})
	var today:int=TeaService.today(w.state)
	await set_tea({"lender":id,"round":{"style":"light","portions":4,"claimed":{id:true,"tea-guest-0":true},"day":today}})
	await open_page()
	check(not w.state.has("table_warmer") and page_shown("WarmerMaterials") and page_shown("WarmerSource"),"Sipped page: 保溫底座 not installed, its materials shown (%s)"%tag)
	check(page_text("TeaChip")=="淺焙茶 4／6 杯","Sipped page chip 淺焙茶 4／6 杯 (%s): %s"%[tag,page_text("TeaChip")])
	check(page_shown("TeaTake") and page_shown("TeaSip") and (page_node("TeaSip") as Button).disabled,"Sipped page: lender sees 收回, 喝一杯 disabled (%s)"%tag)
	check(page_shown("TeaReason") and page_text("TeaReason").contains(TeaService.SIPPED) and page_text("TeaReason").contains(TeaService.TEA_LEFT),"Sipped page reasons (%s): %s"%[tag,page_text("TeaReason")])
	var shot_sipped:Image=await shot("page_sipped4")
	page_checks("sipped4",shot_sipped)
	await close_page()
	# (d) Cold deep tea lent by someone else; one 淺焙茶 in my bag. PRESET time forward.
	var saved_time:float=advance_days()
	var later:int=TeaService.today(w.state)
	await set_tea({"lender":FIXTURE_LENDER,"round":{"style":"deep","portions":5,"claimed":{"tea-guest-0":true},"day":later-1}})
	await open_page()
	check(view_round().get("cold")==true,"Cold page: snapshot round is cold (%s): %s"%[tag,str(view_round())])
	check(page_text("TeaChip")==CommunityUI.TEA_CHIP_COLD,"Cold page chip 茶涼了 (%s): %s"%[tag,page_text("TeaChip")])
	check(not page_shown("TeaTake") and not page_shown("TeaPlace"),"Cold page: no 收回 / 擺上 for a non-lender (%s)"%tag)
	check(page_shown("TeaBrew_light") and not (page_node("TeaBrew_light") as Button).disabled and (page_node("TeaSip") as Button).disabled,"Cold page: 泡淺焙茶 enabled, 喝一杯 disabled (%s)"%tag)
	check(page_shown("TeaReason") and page_text("TeaReason").contains(TeaService.COLD),"Cold page reason (%s): %s"%[tag,page_text("TeaReason")])
	var shot_cold:Image=await shot("page_cold")
	page_checks("cold",shot_cold)
	await close_page()
	# Restore: time, tea record, revisit record, bag; back to the plain scene.
	w.state.time=saved_time  # PRESET restore
	if saved_revisit is Dictionary:w.state.tea_revisit=(saved_revisit as Dictionary).duplicate(true)  # PRESET restore
	else:w.state.erase("tea_revisit")  # PRESET restore
	for item in ["tea_ware_kit","tea_light","tea_deep"]:
		if saved_bag.has(item):bag[item]=saved_bag[item]  # PRESET restore
		else:bag.erase(item)  # PRESET restore
	await set_tea({})
	check(TeaService.today(w.state)<later and not is_instance_valid(app.modal) and not w.state.has(TeaService.STATE_KEY),"Page step restored time, table and modal (%s)"%tag)

# ----------------------------------------------------------------- probes --

func draw_probe()->void:
	var at:=PROBE_ORIGIN
	match probe_variant:
		"old4":Art.draw_table(probe_node,at,1.0,true)
		"new4":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{})
		"old_all":Art.draw_table(probe_node,at,1.0,true,{},{},6,4,true)
		"new_all":Art.draw_table(probe_node,at,1.0,true,{},{},6,4,true,{})
		"tea_all":Art.draw_table(probe_node,at,1.0,true,{},{},6,4,true,tea_round("deep",6))
		"tea_light":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,tea_round("light",6))
		"tea_client":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"round":{"style":"light","portions":6,"day":1}})
		# Plain views (the shape world_view passes after current_round).
		"view_placed":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true})
		"view_fresh":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"style":"light","left":6,"cold":false})
		"view_cold":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"style":"light","left":6,"cold":true})
		"view_cold_motion":Art.draw_table(probe_node,at,2.3,false,{},{},0,0,false,{"placed":true,"style":"light","left":6,"cold":true})
		"view_done":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"style":"light","left":0,"cold":false})
		"view_deep":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"style":"deep","left":6,"cold":false})
		"view_cold_deep":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"style":"deep","left":6,"cold":true})
		"view_done_deep":Art.draw_table(probe_node,at,1.0,true,{},{},0,0,false,{"placed":true,"style":"deep","left":0,"cold":false})

func probe(variant:String)->Image:
	probe_variant=variant
	probe_node.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image:=probe_view.get_texture().get_image()
	if image!=null and image.is_compressed():image.decompress()
	return image

func save_probe(image:Image,step:String)->void:
	if image==null or image.is_empty():return
	var big:=image.duplicate() as Image
	big.resize(image.get_width()*4,image.get_height()*4,Image.INTERPOLATE_NEAREST)
	var keep:=tag
	tag=""
	save_image(big,step)
	tag=keep

func probe_box(local:Rect2)->Rect2i:
	return Rect2i(Vector2i((PROBE_ORIGIN+local.position).floor()),Vector2i(local.size))

## Mean colour of the given per-cup offsets over all six cups of a 1× probe image.
func cup_mean(image:Image,offsets:Array)->Color:
	var sum:=Vector3.ZERO
	var count:=0
	for slot:Vector2 in Art.TEA_CUPS:
		for offset:Vector2 in offsets:
			var at:=Vector2i((PROBE_ORIGIN.floor()+slot+offset))
			var c:=image.get_pixel(at.x,at.y)
			sum+=Vector3(c.r,c.g,c.b)
			count+=1
	if count==0:return Color.BLACK
	return Color(sum.x/count,sum.y/count,sum.z/count)

func colour_distance(a:Color,b:Color)->float:
	return Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()

func colour_near(a:Color,b:Color)->bool:
	return absf(a.r-b.r)<=0.02 and absf(a.g-b.g)<=0.02 and absf(a.b-b.b)<=0.02

## Readability: the six cup states differ clearly in their surface colour (and from the rim).
func surface_checks(states:Dictionary)->void:
	var drunk_design:Color=Art.TEA_CUP_CLEAN.lerp(Art.TEA_DREG,0.25)
	var design:Dictionary={"never brewed":Art.TEA_CUP_CLEAN,"fresh light":Art.TEA_LIGHT,"fresh deep":Art.TEA_DEEP,"cold light":Art.TEA_LIGHT_COLD,"cold deep":Art.TEA_DEEP_COLD,"drunk light":drunk_design,"drunk deep":drunk_design}
	var means:={}
	for state:String in states:
		var image:Image=states[state]
		var mean:Color=cup_mean(image,Art.TEA_SURFACE)
		var rim:Color=cup_mean(image,Art.TEA_RIM)
		var want:Color=design[state]
		means[state]=mean
		print("NOTE probe surface %s: mean #%s (design #%s), rim #%s"%[state,mean.to_html(false),want.to_html(false),rim.to_html(false)])
		check(colour_near(mean,want),"Probe: %s surface pixels sampled where designed (#%s vs #%s)"%[state,mean.to_html(false),want.to_html(false)])
		check(colour_near(rim,TeaArt.CREAM),"Probe: %s cups keep the cream rim (#%s)"%[state,rim.to_html(false)])
		var to_rim:float=colour_distance(mean,rim)
		check(to_rim>=MIN_SURFACE_DISTANCE,"Probe: %s surface stands out from the cream rim (%.3f ≥ %.2f)"%[state,to_rim,MIN_SURFACE_DISTANCE])
	var names:Array=states.keys()
	var smallest:float=INF
	for i in range(names.size()):
		for j in range(i+1,names.size()):
			var a:String=names[i]
			var b:String=names[j]
			# Drunk light vs drunk deep: same clean inside and dreg dot by design.
			if a.begins_with("drunk") and b.begins_with("drunk"):continue
			var first:Color=means[a]
			var second:Color=means[b]
			var d:float=colour_distance(first,second)
			smallest=minf(smallest,d)
			print("NOTE probe surface distance %s / %s: %.3f"%[a,b,d])
			check(d>=MIN_SURFACE_DISTANCE,"Probe: %s and %s cup surfaces differ (%.3f ≥ %.2f)"%[a,b,d,MIN_SURFACE_DISTANCE])
	print("NOTE probe smallest surface distance %.3f (minimum %.2f)"%[smallest,MIN_SURFACE_DISTANCE])

## Side-by-side TEA_RECT crops of the probe states for review (1×; save_probe scales 4×).
func state_strip(images:Array)->Image:
	var box:=probe_box(Art.TEA_RECT)
	var strip:=Image.create_empty(images.size()*(box.size.x+2),box.size.y,false,Image.FORMAT_RGBA8)
	strip.fill(Color("1c2a2a"))
	for i in range(images.size()):
		var image:Image=images[i]
		var copy:=image.duplicate() as Image
		copy.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(copy,box,Vector2i(i*(box.size.x+2),0))
	return strip

## Offscreen draws of draw_table: the default (no tea) path is byte-identical to the
## call without the new argument; the tea set never touches the dish / warmer pixels.
func probe_flow()->void:
	probe_view=SubViewport.new()
	probe_view.size=PROBE_SIZE
	probe_view.transparent_bg=false
	probe_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	probe_view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	probe_node=Node2D.new()
	probe_node.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	probe_node.draw.connect(draw_probe)
	probe_view.add_child(probe_node)
	root.add_child(probe_view)
	await process_frame
	var old4:Image=await probe("old4")
	var new4:Image=await probe("new4")
	var old_all:Image=await probe("old_all")
	var new_all:Image=await probe("new_all")
	var tea_all:Image=await probe("tea_all")
	var tea_light:Image=await probe("tea_light")
	var tea_client:Image=await probe("tea_client")
	check(old4!=null and not old4.is_empty() and old4.get_size()==PROBE_SIZE,"Probe renders")
	if old4==null or old4.is_empty():return
	check(old4.get_data()==new4.get_data(),"4-arg draw_table identical with tea={} (byte compare)")
	check(old_all.get_data()==new_all.get_data(),"Full draw_table identical with tea={} (byte compare)")
	var whole:=Rect2i(Vector2i.ZERO,PROBE_SIZE)
	check(changed_pixels(old4,old_all,whole)>100,"Probe shows the dishes and warmer (sanity)")
	var tea_px:=changed_pixels(old_all,tea_all,probe_box(Art.TEA_RECT))
	check(tea_px>=200,"Probe tea set drawn (%d px)"%tea_px)
	check(changed_pixels(old_all,tea_all,whole)==tea_px,"Probe: the tea set changes nothing outside TEA_RECT")
	for entry:Array in [["hotpot",HOTPOT_BOX],["bowls",BOWLS_BOX],["watermelon",MELON_BOX],["warmer",Art.WARMER_RECT],["table",Rect2(2,-16,30,48)]]:
		check(changed_pixels(old_all,tea_all,probe_box(entry[1]))==0,"Probe: %s pixels untouched by the tea set"%entry[0])
	check(tea_light.get_data()==tea_client.get_data(),"Server-shaped and client-shaped tea records draw the same")
	# Plain views: fresh draws exactly like the record; cold = same cups, dull colour, no steam.
	var view_placed:Image=await probe("view_placed")
	var view_fresh:Image=await probe("view_fresh")
	var view_cold:Image=await probe("view_cold")
	var view_cold_motion:Image=await probe("view_cold_motion")
	var view_done:Image=await probe("view_done")
	check(view_fresh.get_data()==tea_light.get_data(),"Plain fresh view draws the same as the round record")
	var tea_area:=probe_box(Art.TEA_RECT)
	var steam_area:=probe_box(STEAM_BOX)
	var cold_vs_fresh:=changed_pixels(view_fresh,view_cold,tea_area)
	var cold_vs_done:=changed_pixels(view_done,view_cold,tea_area)
	print("NOTE probe changed px: fresh→cold %d, finished→cold %d, placed→cold %d"%[cold_vs_fresh,cold_vs_done,changed_pixels(view_placed,view_cold,tea_area)])
	check(changed_pixels(view_fresh,view_cold,whole)==cold_vs_fresh,"Probe: cold tea changes nothing outside TEA_RECT")
	check(cold_vs_fresh-changed_pixels(view_fresh,view_cold,steam_area)>=24,"Probe: all 24 cold tea surface pixels differ from fresh (%d)"%cold_vs_fresh)
	check(changed_pixels(view_fresh,view_cold,steam_area)>0,"Probe: the fresh steam wisp is gone when cold")
	check(cold_vs_done>=24,"Probe: cold cups differ from a finished round (%d)"%cold_vs_done)
	check(changed_pixels(view_placed,view_cold,steam_area)==0 and changed_pixels(view_cold,view_cold_motion,steam_area)==0,"Probe: no steam over cold tea, reduced or motion on")
	# Readability: mean surface colour per state, pairwise distances.
	var view_deep:Image=await probe("view_deep")
	var view_cold_deep:Image=await probe("view_cold_deep")
	var view_done_deep:Image=await probe("view_done_deep")
	check(changed_pixels(view_placed,view_deep,whole)==changed_pixels(view_placed,view_deep,tea_area),"Probe: deep tea changes nothing outside TEA_RECT")
	check(changed_pixels(view_deep,view_cold_deep,steam_area)>0 and changed_pixels(view_placed,view_cold_deep,steam_area)==0,"Probe: deep tea steams when fresh, not when cold")
	check(changed_pixels(view_placed,view_done,steam_area)==0 and changed_pixels(view_placed,view_done_deep,steam_area)==0,"Probe: no steam over a finished round")
	surface_checks({"never brewed":view_placed,"fresh light":view_fresh,"fresh deep":view_deep,"cold light":view_cold,"cold deep":view_cold_deep,"drunk light":view_done,"drunk deep":view_done_deep})
	save_probe(old_all,"probe_old")
	save_probe(tea_light,"probe_tea")
	save_probe(tea_all,"probe_all_tea")
	save_probe(view_cold,"probe_cold")
	# never brewed | fresh light | fresh deep | cold light | cold deep | finished light
	save_probe(state_strip([view_placed,view_fresh,view_deep,view_cold,view_cold_deep,view_done]),"probe_states")
	probe_view.queue_free()
	await process_frame

func run()->void:
	# The runner kills the suite at 120 s; report a failure (with the summary line) before that.
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/茶陶上桌預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("tea-service-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"茶陶旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	# The fresh host shows the 望安 arrival card over the top of the plaza; close it
	# directly (a player closes it with E / Esc; covered in test_table_warmer_ui).
	WanganUI.dismiss(app)
	await probe_flow()
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		await page_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=57,"26 screenshots per size plus 5 probes (%d)"%shots)
	w.state.erase(TeaService.STATE_KEY)  # PRESET cleanup before the final save
	w.state.erase("table_warmer")
	w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
