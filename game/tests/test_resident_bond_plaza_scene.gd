extends SceneTree
## T066 第五批居民好感（洛洛、鈴婆婆）native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/居民好感預覽第五批 (or --capture-dir=), named
## <w>x<h>_<step>.png. Same harness as test_resident_bond_coast_scene.gd.
##
## Standing cells are NEVER hard-coded: they come from World.bond_place(state,id)
## and Bond.POST_CELLS / Bond.BELL_CELLS at runtime (another worker may tune them).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * app.village_art_preview=true is set by the test itself;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    max-stage preset's talk_day/gift_day 0 are valid past days;
##  * state.picnic written directly (false for the first plaza shot and for each
##    <id>_world_before_picnic shot, true otherwise);
##  * state.festival_story_open written directly (true only for the two festival
##    shots, then false again) — the festival is NOT opened through the board;
##  * player.bonds is erased before each viewport size;
##  * backpack written directly: every item giftable to the resident set to 0, then
##    洛洛: bread 2, roasted_sweet_potato 1 (liked); 鈴婆婆: carrot_soup 2,
##    baked_potato 1 (liked); both: radish 2 (ordinary), wood 5;
##  * the player is teleported by writing region/x/y: plaza shots at the midpoint
##    between the two residents; world shots ~1.2 tiles beside the resident (first
##    free side whose focus is the resident) so the player sprite does not cover
##    them; for the E key 0.9 tile from the cell (first free side N/S/W/E whose focus
##    is the resident);
##  * fallback: a player-owned `wall` written on the first candidate cell; all
##    occupied: `wall`s on every candidate cell (removed after);
##  * max-stage preset: player.bonds.<id>={"points":24,"talk_day":0,"gift_day":0}.
## REALLY EXERCISED (buttons pressed by emitting `pressed`, real Session.perform path):
##  * app._interact() opens the bond dialogue; BondTalk, BondGift, BondGift_<liked>,
##    BondEvents, the journal's ResidentMemories bookmark.
## SHOTS (per size, 19): plaza_before_picnic, plaza_after_picnic (overview between
##  the two; at 1024×640 洛洛 can fall under the bottom HUD, so the sprite pixel check
##  is done on the per-resident pair instead), luoluo_world_before_picnic,
##  luoluo_world, luoluo_dialogue, luoluo_gift, luoluo_events_stage4,
##  lingpopo_world_before_picnic, lingpopo_world, lingpopo_dialogue, lingpopo_gift, lingpopo_events_stage4, memories_plaza,
##  luoluo_world_fallback, luoluo_world_all_occupied, lingpopo_world_fallback,
##  lingpopo_world_all_occupied, plaza_festival, lingpopo_world_festival; plus
##  <id>_events_stage4_tab1 (認識 tab). The tabbed events page must need NO outer
##  scrolling at every tab (hard check).
## NOT CHECKED BY PIXELS: whether the tint makes 洛洛/鈴婆婆 distinguishable from
##  阿榆/米露 (they reuse those frames) — judged by eye from the screenshots only.
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const NEW:=["luoluo","lingpopo"]
const STOCK:={"luoluo":{"bread":2,"roasted_sweet_potato":1},"lingpopo":{"carrot_soup":2,"baked_potato":1}}
const LIKED_GIFT:={"luoluo":"bread","lingpopo":"carrot_soup"}
const SIDES:=[Vector2(0.5,-0.4),Vector2(0.5,1.4),Vector2(-0.4,0.5),Vector2(1.4,0.5)]
const BESIDE:=[Vector2(1.7,0.9),Vector2(-0.7,0.9),Vector2(0.5,1.9),Vector2(1.7,0.1),Vector2(-0.7,0.1)]
var app
var w
var id:String=""
var rid:String="luoluo"
var path:String=""
var checks:=0
var failures:=0
var output:=""
var tag:=""
var finished:=false
var shots:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("RESIDENT_BOND_PLAZA_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
	quit(1 if failures>0 or checks==0 else 0)

func settle()->void:
	for i in range(6):await process_frame
	if app.has_method("_layout_preview"):app._layout_preview()
	await process_frame

func hide_toast()->void:
	if app.toast!=null and is_instance_valid(app.toast):
		var toast_label:Label=app.toast
		toast_label.hide()

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
			var c:=image.get_pixel(int((gx+0.5)*image.get_width()/24.0),int((gy+0.5)*image.get_height()/16.0))
			seen[c.to_html(false)]=true
	return seen.size()

func shot(step:String)->Image:
	var file_name:="%s_%s"%[tag,step]
	hide_toast()
	await create_timer(0.2).timeout  # modal fade-in (LifeShell.reveal) is 0.16 s
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var file:=output.path_join(file_name+".png")
	check(image!=null and not image.is_empty() and image.get_width()>0 and image.get_height()>0,"non-empty native image "+file_name)
	if image==null or image.is_empty():return image
	check(image.get_size()==root.size,"Screenshot has the viewport size %s (%s)"%[str(root.size),file_name])
	var variety:=colour_variety(image)
	check(variety>=12,"Screenshot is not blank or flat (%d colours on the grid) %s"%[variety,file_name])
	check(image.save_png(file)==OK,"native screenshot saved "+file_name)
	check(FileAccess.file_exists(file),"screenshot file exists "+file_name)
	var handle:=FileAccess.open(file,FileAccess.READ)
	var length:int=0
	if handle!=null:
		length=handle.get_length()
		handle.close()
	check(length>0,"screenshot file is not empty "+file_name)
	shots+=1
	print("RESIDENT_BOND_PLAZA_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
	return image

func differ(a:Image,b:Image,label:String)->void:
	check(a!=null and b!=null and a.get_data()!=b.get_data(),"Screenshots differ: "+label)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func inside_modal(c:Control)->bool:
	return c!=null and is_instance_valid(app.modal) and (app.modal as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect())

func control(control_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(control_name,true,false) as Control

func find_button(prefix:String)->Button:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Button",true,false):
		var b:=node as Button
		if b!=null and b.is_visible_in_tree() and b.text.begins_with(prefix):return b
	return null

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func has_texts(wanted:Array,label:String)->void:
	var all:=texts()
	for t in wanted:check(all.contains(str(t)),"Visible text '%s' (%s)"%[t,label])

func layout_meta()->String:
	if not is_instance_valid(app.modal):return ""
	return str((app.modal as Node).get_meta("life_modal_layout",""))

func modal_fits(label:String)->bool:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Modal open: "+label)
	if not ok:return false
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Modal fits viewport: "+label)
	return true

func ancestor_scroll(c:Control)->ScrollContainer:
	if c==null:return null
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer:return parent as ScrollContainer
		parent=parent.get_parent()
	return null

func reach(c:Control,label:String)->bool:
	if c==null:return false
	if visible(c) and inside_modal(c):return true
	var scroll:=ancestor_scroll(c)
	if scroll==null:return false
	scroll.ensure_control_visible(c)
	await settle()
	var ok:=visible(c) and inside_modal(c)
	if ok:print("NOTE %s: %s is reachable only after scrolling the modal"%[label,c.name])
	return ok

func scroll_top()->void:
	if not is_instance_valid(app.modal):return
	for node in (app.modal as Node).find_children("*","ScrollContainer",true,false):(node as ScrollContainer).scroll_vertical=0
	await settle()

func needs_scroll()->bool:
	var scroll:=control("ModalScroll") as ScrollContainer
	if scroll==null:return false
	var bar:=scroll.get_v_scroll_bar()
	return bar.max_value>bar.page+1.0

func text_fits(b:Button)->bool:
	return b!=null and b.size.x+0.5>=b.get_minimum_size().x and b.size.y+0.5>=b.get_minimum_size().y

func on_view_now(names:Array,label:String)->void:
	for control_name in names:
		var c:=control(str(control_name))
		check(c!=null and visible(c) and inside_modal(c),"%s fully on view inside the card without scrolling (%s)"%[control_name,label])
		if c is Button:check(text_fits(c as Button),"%s text not cut (%s)"%[control_name,label])

func labels_whole(label:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Modal open for label check: "+label)
		return
	var scrolled:=0
	var bad:=PackedStringArray()
	var seen:=0
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l==null or not l.is_visible_in_tree() or l.text.strip_edges().is_empty():continue
		seen+=1
		if not (visible(l) and inside_modal(l)):
			var scroll:=ancestor_scroll(l)
			if scroll!=null:
				scroll.ensure_control_visible(l)
				await settle()
				scrolled+=1
		var whole:=visible(l) and inside_modal(l) and l.get_visible_line_count()>=l.get_line_count() and l.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING
		if not whole:bad.append(l.text.left(24).replace("\n"," "))
	check(seen>0,"Modal has labels ("+label+")")
	check(bad.is_empty(),"Labels not cut (%s): %s"%[label," | ".join(bad)])
	if scrolled>0:print("NOTE %s: %d label(s) reachable only after scrolling the modal"%[label,scrolled])
	await scroll_top()

func home()->String:
	return World.REGIONS.HOME

func place_of(resident:String)->Vector2i:
	return World.bond_place(app.session.snapshot,resident)[1]

func place()->Vector2i:
	return place_of(rid)

func candidates()->Array:
	return Bond.POST_CELLS if rid=="luoluo" else Bond.BELL_CELLS

func stand(at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=home()
	person.x=at.x;person.y=at.y
	await refresh()

func standable(tile:Vector2i)->bool:
	if str(w._region)!=home():return World.land(tile)
	return World.land(tile) and not w.blocked(tile)

## First free spot (cell + offset) from which the view focuses the resident.
func stand_focused(cell:Vector2i,offsets:Array,label:String)->bool:
	for off:Vector2 in offsets:
		var at:Vector2=Vector2(cell)+off
		if not standable(Vector2i(at.floor())):continue
		await stand(at)
		if str(app.view.focused_label)==rid:
			if off!=offsets[0]:print("NOTE %s: %s first spot not usable, standing at offset %s"%[label,npc(),str(off)])
			return true
	check(false,"Some free spot next to %s %s focuses %s (%s)"%[npc(),str(cell),rid,label])
	return false

## Plaza overview spot: between the two residents, nudged to a free tile.
func plaza_spot()->Vector2:
	var mid:=(Vector2(place_of("luoluo"))+Vector2(place_of("lingpopo")))/2.0+Vector2(0.5,0.5)
	for off:Vector2 in [Vector2.ZERO,Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1),Vector2(1,1)]:
		if standable(Vector2i((mid+off).floor())):return mid+off
	return mid

func press(control_name:String)->bool:
	var button:=control(control_name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+control_name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await settle()
	return true

func close()->void:
	app._close_modal()
	await settle()

func bond()->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(rid,{})
	return found if found is Dictionary else {}

func bag_count(item:String)->int:
	return int(w.state.players[id].inventory.get(item,0))

func npc()->String:
	return Bond.name_of(rid)

func dialogue_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and control("BondSummary")!=null and texts().contains("和%s聊聊"%npc())

func events_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and texts().contains("%s的關係事件"%npc()) and control("BondSummary")==null

func open_by_interact(label:String)->bool:
	await close()
	await stand_focused(place(),SIDES,label)
	app._interact()
	await settle()
	var ok:=dialogue_open()
	check(ok,"E next to %s opens 和%s聊聊 (%s)"%[npc(),npc(),label])
	return ok

func stock_bag()->void:
	var inv:Dictionary=w.state.players[id].inventory
	for item in inv.keys():
		if Bond.giftable(rid,str(item)):inv[item]=0
	for item in STOCK[rid]:inv[item]=int(STOCK[rid][item])
	inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

func set_walls(cells:Array,on:bool)->void:
	for cell:Vector2i in cells:
		if on:w.state.objects[World.key(cell)]={"type":"wall","owner":id,"items":{}}  # PRESET wall
		else:w.state.objects.erase(World.key(cell))

# ------------------------------------------------------------ world view --

func to_pixels(world_point:Vector2)->Vector2:
	return app.view.get_global_transform_with_canvas()*(app.view.screen(world_point)*float(app.view.view_zoom()))

func view_to_pixels(rect:Rect2)->Rect2:
	var zoom:float=float(app.view.view_zoom())
	var xf:Transform2D=app.view.get_global_transform_with_canvas()
	var a:Vector2=xf*(rect.position*zoom)
	var b:Vector2=xf*(rect.end*zoom)
	return Rect2(a,b-a)

## Resident sprite box: 32×48 (×zoom) above the foot.
func sprite_box(cell:Vector2i)->Rect2i:
	var foot:=to_pixels(Vector2(cell)+Vector2(0.5,0.7))
	var zoom:float=float(app.view.view_zoom())*app.view.get_global_transform_with_canvas().get_scale().x
	var size:=Vector2(32,48)*zoom
	return Rect2i(Vector2i((foot-Vector2(size.x/2.0,size.y)).round()),Vector2i(size.round()))

func box_difference(a:Image,b:Image,box:Rect2i)->float:
	if a==null or b==null or a.get_size()!=b.get_size():return 0.0
	box=box.intersection(Rect2i(Vector2i.ZERO,a.get_size()))
	if box.size.x<=0 or box.size.y<=0:return 0.0
	var changed:=0
	for x in range(box.position.x,box.end.x):
		for y in range(box.position.y,box.end.y):
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.12:changed+=1
	return float(changed)/float(box.size.x*box.size.y)

func box_variety(image:Image,box:Rect2i)->int:
	if image==null:return 0
	box=box.intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	var seen:={}
	for x in range(box.position.x,box.end.x,2):
		for y in range(box.position.y,box.end.y,2):seen[image.get_pixel(x,y).to_html(false)]=true
	return seen.size()

## No fixed tree/rock (and no planted tree/object) on the resident's cell or the
## cell below, whose sprites are drawn after the resident and would cover him/her.
func not_covered(cell:Vector2i,label:String)->void:
	for p:Vector2i in [cell,cell+Vector2i.DOWN]:
		var fixed:=World.base_resource(p,home())
		var removed:bool=w.state.get("removed",{}).has(World.key(p))
		check(removed or fixed not in ["tree","rock"],"No fixed %s on %s covering %s (%s)"%[fixed,str(p),npc(),label])
		check(not w.state.get("forest",{}).has(World.key(p)),"No planted tree on %s covering %s (%s)"%[str(p),npc(),label])
		if p!=cell:check(not w.state.get("objects",{}).has(World.key(p)),"No object on %s covering %s (%s)"%[str(p),npc(),label])
	check(World.land(cell,home()),"%s stands on land at %s (%s)"%[npc(),str(cell),label])
	check(cell!=World.Festival.TREE_CELL and cell+Vector2i.DOWN!=World.Festival.TREE_CELL,"%s is not on/above the wind-chime tree cell (%s)"%[npc(),label])

func placements()->Array:
	var zoom:float=app.view.view_zoom()
	return app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))

func entry_for(list:Array,resident:String)->Dictionary:
	for entry:Dictionary in list:
		if str(entry.id)==resident:return entry
	return {}

## Small HUD panels (task card etc.) in screen pixels; full-screen layers skipped.
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

## Report every label of the scene and overlaps of the new residents' labels and
## sprites with other labels and with HUD panels.
func scene_report(label:String)->void:
	var list:=placements()
	var parts:=PackedStringArray()
	for entry:Dictionary in list:parts.append("%s%s@%s"%["*" if entry.active else "",entry.title,str(view_to_pixels(entry.rect))])
	print("NOTE %s: labels (screen px, * = focused): %s"%[label,", ".join(parts)])
	var panels:=hud_panels()
	var hud_parts:=PackedStringArray()
	for panel:Dictionary in panels:hud_parts.append("%s@%s"%[panel.name,str(panel.rect)])
	print("NOTE %s: HUD panels: %s"%[label,", ".join(hud_parts)])
	for resident:String in NEW:
		var mine:=entry_for(list,resident)
		var cell:=place_of(resident)
		var box:=sprite_box(cell)
		if not Rect2i(Vector2i.ZERO,root.size).encloses(box):
			print("NOTE %s: %s is not wholly on screen (sprite box %s), label present=%s"%[label,Bond.name_of(resident),str(box),str(not mine.is_empty())])
			continue
		check(not mine.is_empty(),"%s has a name label while on screen (%s)"%[Bond.name_of(resident),label])
		if mine.is_empty():continue
		check(str(mine.title)==Bond.name_of(resident),"%s's label reads %s (%s): %s"%[resident,Bond.name_of(resident),label,str(mine.title)])
		var mine_rect:Rect2=mine.rect
		var pixels:=view_to_pixels(mine_rect)
		for entry:Dictionary in list:
			if entry==mine:continue
			check(not mine_rect.intersects(entry.rect),"「%s」 label does not overlap 「%s」 (%s) %s vs %s"%[Bond.name_of(resident),entry.title,label,str(mine.rect),str(entry.rect)])
		for panel:Dictionary in panels:
			if pixels.intersects(panel.rect):print("NOTE %s: OVERLAP 「%s」 label %s with HUD %s %s"%[label,Bond.name_of(resident),str(pixels),panel.name,str(panel.rect)])
			if Rect2(box).intersects(panel.rect):print("NOTE %s: OVERLAP %s sprite %s with HUD %s %s"%[label,Bond.name_of(resident),str(box),panel.name,str(panel.rect)])

## The focus label is placed, on screen and does not overlap other labels or HUD;
## the sprite box is inside the viewport.
func world_label_ok(label:String,cell:Vector2i)->void:
	check(str(app.view.focused_label)==rid,"World focus is %s (%s): %s"%[npc(),label,str(app.view.focused_label)])
	var list:=placements()
	var mine:=entry_for(list,rid)
	check(not mine.is_empty() and str(mine.get("title",""))==npc() and bool(mine.get("active",false)),"Active world label 「%s」 placed (%s): %s"%[npc(),label,str(mine)])
	if mine.is_empty():return
	var box:Rect2=mine.rect
	var on_screen:=Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/float(app.view.view_zoom()))
	check(on_screen.encloses(box),"「%s」 label inside the viewport (%s) %s"%[npc(),label,str(box)])
	var anchor:Vector2=app.view.screen(Vector2(cell)+Vector2(0.5,0.7))+Vector2(0,-47)
	var gap:=box.get_center().distance_to(anchor)
	print("NOTE %s: %s label centre is %.0f view px from its head anchor %s"%[label,npc(),gap,str(anchor)])
	# The focused label steps around the local player's body and name tag; when the
	# player stands within one tile (E-key spot) a larger step is expected.
	var person:Dictionary=w.state.players[id]
	var crowded:=Vector2(float(person.x),float(person.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<1.0
	var limit:=64.0 if crowded else 40.0
	if crowded:print("NOTE %s: player stands within 1 tile of %s, label step limit %.0f view px"%[label,npc(),limit])
	check(gap<=limit,"「%s」 label stays next to the resident's head (%.0f view px from the anchor) (%s)"%[npc(),gap,label])
	for panel:Dictionary in hud_panels():
		check(not view_to_pixels(box).intersects(panel.rect),"Focused 「%s」 label clear of HUD %s (%s) %s vs %s"%[npc(),panel.name,label,str(view_to_pixels(box)),str(panel.rect)])
	var foot:=to_pixels(Vector2(cell)+Vector2(0.5,0.7))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(foot),"%s's foot is on screen (%s) %s"%[npc(),label,str(foot)])
	var sprite:=sprite_box(cell)
	check(Rect2i(Vector2i.ZERO,root.size).encloses(sprite),"%s's whole sprite box is inside the viewport (%s) %s"%[npc(),label,str(sprite)])
	for panel:Dictionary in hud_panels():
		check(not Rect2(sprite).intersects(panel.rect),"%s's sprite clear of HUD %s (%s) %s vs %s"%[npc(),panel.name,label,str(sprite),str(panel.rect)])
	scene_report(label)

## Where the neighbouring landmarks are relative to the resident (tiles, pixels).
func neighbours_report(label:String)->void:
	var cell:=place()
	var things:={"出貨箱":World.SHIPPING.cell_for(app.session.snapshot),"公告板":Vector2i(40,29),"小栗攤":Vector2i(43,29),
		"風鈴樹":World.Festival.TREE_CELL,"阿榆":Village.resident_cell(app.session.snapshot,"aru"),"米露":Village.resident_cell(app.session.snapshot,"milu")}
	var parts:=PackedStringArray()
	for thing:String in things:
		var at:Vector2i=things[thing]
		parts.append("%s%s d=%.1f px=%s"%[thing,str(at),Vector2(cell).distance_to(Vector2(at)),str(to_pixels(Vector2(at)+Vector2(0.5,0.7)).round())])
	print("NOTE %s: %s at %s; neighbours: %s"%[label,npc(),str(cell),", ".join(parts)])

# --------------------------------------------------------------- flows --

## Bond page, gift page (real talk + liked gift), then the stage-4 events page.
func pages_flow()->void:
	var step:="%s dialogue stage 0 %s"%[rid,tag]
	if not await open_by_interact(step):return
	modal_fits(step)
	on_view_now(["BondSummary","BondTalk","BondGift","BondEvents"],step)
	check(control("BondSiteBack")==null,"No BondSiteBack for %s (%s)"%[npc(),step])
	has_texts(["和%s聊聊"%npc(),"%s・%s"%[npc(),Bond.LOCAL_PLACES[rid]],"%s喜歡：%s"%[npc(),Bond.LIKE_TEXT[rid]],"好感・尚未認識  0／1","聊聊近況","送禮物","關係事件  0／4"],step)
	print("NOTE %s: bond dialogue needs scrolling=%s"%[step,str(needs_scroll())])
	await shot(rid+"_dialogue")
	await labels_whole(step)
	await press("BondTalk")
	check(int(bond().get("stage",0))==1 and bool(bond().get("talked_today",false)),"Talk reaches 認識 (%s %s)"%[rid,tag])
	step="%s gift %s"%[rid,tag]
	if not await open_by_interact(step):return
	var talk:=control("BondTalk") as Button
	check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk shows disabled 今天聊過了 (%s)"%step)
	var gift_pressed:bool=await press("BondGift")
	if gift_pressed and modal_fits(step):
		check(texts().contains("送給%s的禮物"%npc()),"Gift page title (%s)"%step)
		var names:Array=["BondGiftList","BondGift_radish"]
		for item in STOCK[rid]:names.append("BondGift_"+item)
		on_view_now(names,step)
		check(control("BondGift_wood")==null,"wood not offered (%s)"%step)
		for item in STOCK[rid]:
			var b:=control("BondGift_"+item) as Button
			check(b!=null and b.text.begins_with("喜歡・"),"%s marked 喜歡・ (%s)"%[item,step])
		var radish:=control("BondGift_radish") as Button
		check(radish!=null and not radish.text.begins_with("喜歡・"),"radish not marked liked (%s)"%step)
		var back:=find_button("回到%s身邊"%npc())
		check(back!=null and visible(back) and inside_modal(back) and text_fits(back),"回到%s身邊 on view (%s)"%[npc(),step])
		var scroll:=control("ModalScroll") as ScrollContainer
		if scroll!=null:check(not scroll.get_v_scroll_bar().visible,"Gift page needs no scrolling (%s)"%step)
		await shot(rid+"_gift")
		await labels_whole(step)
		var liked:String=LIKED_GIFT[rid]
		var held:=bag_count(liked)
		await press("BondGift_"+liked)
		check(bag_count(liked)==held-1,"Gift removes one %s (%s)"%[liked,step])
		check(int(bond().get("points",0))==Bond.TALK_POINTS+Bond.LIKED_POINTS,"Talk + liked gift = %d points (%s)"%[Bond.TALK_POINTS+Bond.LIKED_POINTS,step])
	# Stage-4 events page (preset), opened from the bond dialogue.
	var person:Dictionary=w.state.players[id]
	var bonds:Dictionary=person.get("bonds",{})
	bonds[rid]={"points":Bond.LIMIT,"talk_day":0,"gift_day":0}  # PRESET stage 4
	person.bonds=bonds
	await refresh()
	check(int(bond().get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 (%s %s)"%[rid,tag])
	step="%s events stage 4 %s"%[rid,tag]
	var events_pressed:=false
	if await open_by_interact(step):events_pressed=await press("BondEvents")
	if events_pressed:
		check(events_open(),"Events page opens (%s)"%step)
		if modal_fits(step):
			has_texts(["%s的關係事件"%npc(),"四階事件都已展開","返回居民回憶","%s・%s"%[str(Bond.STAGES[3]),str(Bond.EVENTS[rid][3].title)]],step)
			check(not texts().contains("尚未展開"),"No locked card (%s)"%step)
			var back:=control("BondEventsBack") as Button
			check(back!=null and back.text=="返回居民回憶" and visible(back) and inside_modal(back),"BondEventsBack reads 返回居民回憶 on view (%s)"%step)
			check(not needs_scroll(),"Stage-4 events page needs no scrolling (%s)"%step)
			tab_page_fits(step)
			tab_card(rid,4,3,step)
			var img_four:Image=await shot(rid+"_events_stage4")
			await event_tabs(rid,4,step)
			# Non-default tab capture: 認識.
			if await press_tab(0,step):
				tab_card(rid,4,0,step+" tab 1")
				var img_one:Image=await shot(rid+"_events_stage4_tab1")
				differ(img_four,img_one,"stage-4 tab 4 vs tab 1 (%s)"%step)
	await close()

## Resident in the plaza (focused), then the bond pages.
func resident_flow(plaza:Image)->void:
	stock_bag()
	await close()
	var cell:=place()
	check(cell==candidates()[0],"%s is on the first candidate %s %s"%[npc(),str(candidates()[0]),tag])
	await stand_focused(cell,BESIDE,"world "+rid+" "+tag)
	var person:Dictionary=w.state.players[id]
	var spot:=Vector2(float(person.x),float(person.y))
	# Same spot with picnic=false (PRESET) for a pixel comparison of the sprite box.
	w.state.picnic=false
	await refresh()
	await stand(spot)
	check(str(app.view.focused_label)!=rid and entry_for(placements(),rid).is_empty(),"No %s focus or label beside her/his cell before the picnic %s: %s"%[npc(),tag,str(app.view.focused_label)])
	var before:Image=await shot(rid+"_world_before_picnic")
	w.state.picnic=true
	await refresh()
	await stand(spot)
	not_covered(cell,"world %s %s"%[rid,tag])
	var image:Image=await shot(rid+"_world")
	# Label checks read the same settled frame the screenshot shows.
	world_label_ok("world %s %s"%[rid,tag],cell)
	neighbours_report("world %s %s"%[rid,tag])
	differ(plaza,image,"plaza vs %s world %s"%[rid,tag])
	var box:=sprite_box(cell)
	var diff:=box_difference(before,image,box)
	print("NOTE world %s %s: sprite box %s changed %.0f%% vs before the picnic, variety %d"%[rid,tag,str(box),diff*100.0,box_variety(image,box)])
	check(diff>=0.15,"%s is drawn at her/his cell (%.0f%% of the sprite box changed after the picnic) %s"%[npc(),diff*100.0,tag])
	await pages_flow()

## First candidate walled, then every candidate walled.
func fallback_flow()->void:
	await close()
	var cells:=candidates()
	set_walls([cells[0]],true)
	await refresh()
	var moved:=place()
	check(moved==cells[1] and World.bond_place(w.state,rid)[1]==cells[1],"Wall on %s moves %s to %s (snapshot and server) %s: %s"%[str(cells[0]),npc(),str(cells[1]),tag,str(moved)])
	await stand_focused(moved,BESIDE,"world fallback %s %s"%[rid,tag])
	not_covered(moved,"world fallback %s %s"%[rid,tag])
	var fallback:Image=await shot(rid+"_world_fallback")
	world_label_ok("world fallback %s %s"%[rid,tag],moved)
	print("NOTE world fallback %s %s: sprite box %s variety %d"%[rid,tag,str(sprite_box(moved)),box_variety(fallback,sprite_box(moved))])
	# E at the fallback cell opens the page.
	if await open_by_interact("fallback E %s %s"%[rid,tag]):check(dialogue_open(),"Fallback dialogue for %s %s"%[npc(),tag])
	await close()
	set_walls([cells[0]],false)
	# Every candidate occupied: the resident stays on the first cell (on top of a wall).
	set_walls(cells,true)
	await refresh()
	check(place()==cells[0] and World.bond_place(w.state,rid)[1]==cells[0],"All %d candidates walled: %s stays on %s (snapshot and server) %s"%[cells.size(),npc(),str(cells[0]),tag])
	# World shot from a "beside" spot (the E-key spot can put the player's body in
	# front of her/his legs when the north side is walled); the E-key sides are the
	# fallback when the walls leave no beside spot (洛洛: east side focuses `animal`).
	await stand_focused(cells[0],BESIDE+SIDES,"world all occupied %s %s"%[rid,tag])
	var crowded:Image=await shot(rid+"_world_all_occupied")
	world_label_ok("world all occupied %s %s"%[rid,tag],cells[0])
	differ(fallback,crowded,"world fallback vs all occupied %s %s"%[rid,tag])
	if await open_by_interact("all occupied E %s %s"%[rid,tag]):check(dialogue_open(),"All-occupied dialogue for %s %s"%[npc(),tag])
	await close()
	set_walls(cells,false)
	await refresh()
	check(place()==cells[0],"Removing the walls keeps %s on %s %s"%[npc(),str(cells[0]),tag])

func memories_flow()->void:
	await close()
	app._journal("xinghe")
	await settle()
	var bookmark:=control("ResidentMemories")
	await reach(bookmark,"memories "+tag)
	if not await press("ResidentMemories"):return
	var step:="memories plaza "+tag
	check(is_instance_valid(app.modal) and texts().contains("居民回憶") and find_button("返回島民手帳")!=null,"ResidentMemories opens 居民回憶 (%s)"%step)
	if not modal_fits(step):return
	for resident:String in NEW:
		var b:=control("BondEvents_"+resident) as Button
		check(b!=null and b.text=="%s的關係事件  4／4"%Bond.name_of(resident),"居民回憶 lists %s at 4／4 (%s): %s"%[Bond.name_of(resident),step,b.text if b else "?"])
		var shown:bool=await reach(b,step)
		check(shown and text_fits(b),"BondEvents_%s reachable and not cut (%s)"%[resident,step])
	await scroll_top()
	print("NOTE %s: memories page needs scrolling=%s"%[step,str(needs_scroll())])
	await shot("memories_plaza")
	await labels_whole(step)
	await close()

func festival_flow(plaza:Image)->void:
	await close()
	w.state.festival_story_open=true  # PRESET: festival-open look, not earned
	await refresh()
	check(bool(app.view.data.get("festival_story_open",false)),"Festival-open flag reaches the renderer "+tag)
	for resident:String in NEW:
		var cell:=place_of(resident)
		check(not World.Festival.VISITORS.has(cell) and cell not in Village.FESTIVAL_SPOTS.values(),"%s's cell %s is not a festival visitor/resident spot %s"%[Bond.name_of(resident),str(cell),tag])
		var near:=PackedStringArray()
		for v:Vector2i in World.Festival.VISITORS:
			if Vector2(v).distance_to(Vector2(cell))<=1.5:near.append("%s%s"%[World.Festival.VISITORS[v],str(v)])
		for r:String in Village.FESTIVAL_SPOTS:
			if Vector2(Village.FESTIVAL_SPOTS[r]).distance_to(Vector2(cell))<=1.5:near.append("%s%s"%[r,str(Village.FESTIVAL_SPOTS[r])])
		print("NOTE festival %s: %s at %s, festival figures within 1.5 tiles: %s"%[tag,Bond.name_of(resident),str(cell),", ".join(near)])
	await stand(plaza_spot())
	var image:Image=await shot("plaza_festival")
	scene_report("plaza festival "+tag)
	differ(plaza,image,"plaza vs festival plaza "+tag)
	rid="lingpopo"
	await stand_focused(place(),BESIDE,"world festival lingpopo "+tag)
	await shot("lingpopo_world_festival")
	world_label_ok("world festival lingpopo "+tag,place())
	w.state.festival_story_open=false
	await refresh()

func size_flow()->void:
	var person:Dictionary=w.state.players[id]
	person.erase("bonds")  # PRESET: fresh relationships
	for resident:String in NEW:
		rid=resident
		set_walls(candidates(),false)
	w.state.festival_story_open=false
	await close()
	# 0. Before the picnic: nobody at either cell, no focus, no label.
	w.state.picnic=false  # PRESET
	await refresh()
	var spot:=plaza_spot()
	await stand(spot)
	var list:=placements()
	for resident:String in NEW:
		check(not Bond.present(app.session.snapshot,resident),"%s absent before the picnic %s"%[Bond.name_of(resident),tag])
		check(entry_for(list,resident).is_empty(),"No 「%s」 label before the picnic %s"%[Bond.name_of(resident),tag])
		check(str(app.view.focused_label)!=resident,"No %s focus before the picnic %s"%[Bond.name_of(resident),tag])
		rid=resident
		for off:Vector2 in SIDES:
			await stand(Vector2(place())+off)
			check(str(app.view.focused_label)!=resident,"No %s focus at offset %s before the picnic %s: %s"%[Bond.name_of(resident),str(off),tag,str(app.view.focused_label)])
	await stand(spot)
	var before:Image=await shot("plaza_before_picnic")
	# 1. After the picnic, same spot: both drawn with labels.
	w.state.picnic=true  # PRESET
	await refresh()
	await stand(spot)
	var plaza:Image=await shot("plaza_after_picnic")
	scene_report("plaza after picnic "+tag)
	for resident:String in NEW:
		var box:=sprite_box(place_of(resident))
		var diff:=box_difference(before,plaza,box)
		var under_hud:=PackedStringArray()
		for panel:Dictionary in hud_panels():
			if Rect2(box).intersects(panel.rect):under_hud.append(str(panel.name))
		print("NOTE plaza %s: %s sprite box %s changed %.0f%% after the picnic (variety %d, under HUD: %s)"%[tag,Bond.name_of(resident),str(box),diff*100.0,box_variety(plaza,box),", ".join(under_hud)])
		# The overview camera is a test choice; a box under the HUD is only noted here
		# and checked properly in the per-resident before/after pair below.
		if under_hud.is_empty() and Rect2i(Vector2i.ZERO,root.size).encloses(box):
			check(diff>=0.15,"%s is drawn at her/his cell in the overview (%.0f%% of the sprite box changed after the picnic) %s"%[Bond.name_of(resident),diff*100.0,tag])
	# 2. Each resident: world shot + pages.
	for resident:String in NEW:
		rid=resident
		await resident_flow(plaza)
	await memories_flow()
	# 3. Fallback / all occupied.
	for resident:String in NEW:
		rid=resident
		await fallback_flow()
	# 4. Festival-open look.
	await festival_flow(plaza)

# ------------------------------------------------- T066 tabbed events page --
## The 關係事件 page shows one stage at a time: BondEventsBack + BondEventsSummary,
## four toggle tabs BondEventTab_0..3, one BondEventCard and the footer hint.
## HARD rule at every tab: no outer scrolling, every Label/Button fully on view
## inside the modal and not cut; the selected stage's title and lines (or the
## locked 「尚未展開（好感 N）」 line) sit fully inside the card.
const EVENTS_FOOTER:="聊天、送禮和完成委託都會增加好感。好感不會因為沒上線而下降，朋友的進度也不影響你。"

## Focus + press one stage tab (emitting `pressed`).
func press_tab(index:int,label:String)->bool:
	var tab:=control("BondEventTab_%d"%index) as Button
	check(tab!=null and not tab.disabled,"BondEventTab_%d enabled (%s)"%[index,label])
	if tab==null or tab.disabled:return false
	tab.grab_focus()
	await create_timer(0.12).timeout
	tab.pressed.emit()
	await settle()
	return true

func tab_find_label(text:String)->Label:
	if not is_instance_valid(app.modal):return null
	for node in (app.modal as Node).find_children("*","Label",true,false):
		var l:=node as Label
		if l!=null and l.is_visible_in_tree() and l.text==text:return l
	return null

func tab_not_cut(l:Label)->bool:
	if l==null or l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.size.y+0.5<l.get_combined_minimum_size().y:return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func tab_button_not_cut(b:Button)->bool:
	if b==null or b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x and b.size.y+0.5>=b.get_combined_minimum_size().y

## No outer scrolling; every Label/Button on the page fully on view and not cut.
func tab_page_fits(label:String)->void:
	var ok:=is_instance_valid(app.modal)
	check(ok,"Events modal open (%s)"%label)
	if not ok:return
	check(root.get_visible_rect().encloses((app.modal as Control).get_global_rect()),"Events modal fits the viewport (%s)"%label)
	check(str((app.modal as Node).get_meta("life_modal_layout",""))=="community_board","Events modal keeps the community_board layout (%s)"%label)
	var scroll:=control("ModalScroll") as ScrollContainer
	check(scroll!=null and scroll.get_child_count()>0,"Events modal has its ModalScroll body (%s)"%label)
	if scroll==null or scroll.get_child_count()==0:return
	var content:=scroll.get_child(0) as Control
	var need:float=content.get_combined_minimum_size().y
	var bar:=scroll.get_v_scroll_bar()
	print("RESIDENT_BOND_DIAG events-fit %s content=%.0f view=%.0f spare=%.0f"%[label,need,scroll.size.y,scroll.size.y-need])
	check(need<=scroll.size.y+0.5 and not bar.visible and scroll.scroll_vertical==0,"Events page needs no outer scrolling (%s) content=%.0f view=%.0f"%[label,need,scroll.size.y])
	check(tab_find_label(EVENTS_FOOTER)!=null,"Events footer hint shown (%s)"%label)
	for node in (app.modal as Node).find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree():continue
		if c is Label:
			check(visible(c) and inside_modal(c),"Caption fully on view inside the modal: %s (%s)"%[(c as Label).text,label])
			check(tab_not_cut(c as Label),"Caption not cut or ellipsized: %s (%s)"%[(c as Label).text,label])
		elif c is Button:
			check(visible(c) and inside_modal(c),"Button fully on view inside the modal: %s (%s)"%[c.name,label])
			check(tab_button_not_cut(c as Button),"Button caption not cut: %s (%s)"%[c.name,label])

## Tabs reflect the selection; the card holds exactly the selected stage.
func tab_card(resident:String,stage:int,index:int,label:String)->void:
	var card:=control("BondEventCard")
	check(card!=null and visible(card) and inside_modal(card),"BondEventCard fully on view (%s)"%label)
	for i in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%i) as Button
		check(tab!=null and tab.toggle_mode and tab.button_pressed==(i==index),"BondEventTab_%d %s (%s)"%[i,"selected" if i==index else "not selected",label])
		if tab==null:continue
		check(not tab.disabled and tab.focus_mode==Control.FOCUS_ALL,"BondEventTab_%d enabled and focusable (%s)"%[i,label])
		check(tab.text.ends_with(str(Bond.STAGES[i])) and tab.text.begins_with("✓" if i<stage else "○"),"BondEventTab_%d reads %s with its marker (%s): %s"%[i,Bond.STAGES[i],label,tab.text])
	var event:Dictionary=Bond.EVENTS[resident][index]
	var wanted:Array=[]
	if index<stage:
		wanted.append("%s・%s"%[str(Bond.STAGES[index]),str(event.title)])
		for t in event.lines:wanted.append(str(t))
	else:wanted.append("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[index]),int(Bond.THRESHOLDS[index])])
	for text:String in wanted:
		var l:=tab_find_label(text)
		check(l!=null and card!=null and card.is_ancestor_of(l),"BondEventCard shows 「%s」 (%s)"%[text,label])
		if l==null or card==null:continue
		check(visible(l) and card.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and tab_not_cut(l),"「%s」 fully readable inside BondEventCard (%s)"%[text,label])
	var shown:=0
	if card!=null:
		for node in card.find_children("*","Label",true,false):
			if (node as Control).is_visible_in_tree():shown+=1
	check(shown==wanted.size(),"BondEventCard holds only stage %d (%s): %d labels, want %d"%[index+1,label,shown,wanted.size()])
	for j in range(Bond.STAGES.size()):
		if j==index:continue
		var other:Dictionary=Bond.EVENTS[resident][j]
		check(tab_find_label("%s・%s"%[str(Bond.STAGES[j]),str(other.title)])==null and tab_find_label("%s・尚未展開（好感 %d）"%[str(Bond.STAGES[j]),int(Bond.THRESHOLDS[j])])==null,"Stage %d is not on the page while tab %d is open (%s)"%[j+1,index+1,label])
	var back:=control("BondEventsBack") as Button
	check(back!=null and visible(back) and inside_modal(back),"BondEventsBack on view (%s)"%label)

## Default tab = newest unlocked stage (stage 1 when none); then every tab is
## focused and pressed (emitting `pressed`), and re-checked.
func event_tabs(resident:String,stage:int,label:String)->void:
	var first:=clampi(stage-1,0,Bond.STAGES.size()-1)
	tab_page_fits("default tab %s"%label)
	tab_card(resident,stage,first,"default tab %s"%label)
	for index in range(Bond.STAGES.size()):
		var tab:=control("BondEventTab_%d"%index) as Button
		check(tab!=null,"BondEventTab_%d exists (%s)"%[index,label])
		if tab==null:continue
		tab.grab_focus()
		await create_timer(0.12).timeout
		tab.pressed.emit()
		await settle()
		check(is_instance_valid(tab) and root.gui_get_focus_owner()==tab,"Focus stays on BondEventTab_%d after pressing it (%s)"%[index,label])
		tab_page_fits("tab %d %s"%[index+1,label])
		tab_card(resident,stage,index,"tab %d %s"%[index+1,label])
	for index in range(Bond.STAGES.size()-1):
		var a:=control("BondEventTab_%d"%index)
		var b:=control("BondEventTab_%d"%(index+1))
		check(a!=null and b!=null and a.find_valid_focus_neighbor(SIDE_RIGHT)==b,"Right from BondEventTab_%d reaches the next tab (%s)"%[index,label])

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/居民好感預覽第五批").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("bond-plaza-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"廣場旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	print("NOTE candidates at run time: POST_CELLS=%s BELL_CELLS=%s"%[str(Bond.POST_CELLS),str(Bond.BELL_CELLS)])
	var started:=Time.get_ticks_msec()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
		print("NOTE size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	check(shots>=38,"19 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
