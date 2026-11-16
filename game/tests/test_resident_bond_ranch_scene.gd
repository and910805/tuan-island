extends SceneTree
## T066 第三批居民好感（棉棉）native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/居民好感預覽第三批 (or --capture-dir=), named
## <w>x<h>_<step>.png. Same harness as test_resident_bond_local_scene.gd.
## Run in a real window with `-- --profile=isolated-regression`.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    max-stage preset's talk_day/gift_day 0 are valid past days;
##  * state.picnic written directly (false for the first world shot, then true);
##  * player.bonds is erased before each viewport size;
##  * backpack written directly: every item giftable to 棉棉 set to 0, then feed 2,
##    wool 1, wool_cloth 1 (liked), radish 2 (common), wood 5;
##  * the player is teleported 0.9 tile north of 棉棉's cell;
##  * fallback: a player-owned `wall` written to state.objects["49,33"] (removed after);
##    she moves to 48,33 (batch 4: 51,33 was dropped because the fixed tree at 51,34
##    hid her lower body);
##  * all occupied: player-owned `wall`s written on all four RANCH_CELLS (removed
##    after); she stays on 49,33; the player stands 0.9 tile north of her;
##  * max-stage preset: player.bonds.mianmian={"points":24,"talk_day":0,"gift_day":0}.
## REALLY EXERCISED (buttons pressed by emitting `pressed`, real Session.perform path):
##  * app._interact() opens the bond dialogue; BondTalk, BondGift, BondGift_feed,
##    BondEvents, 「返回居民回憶」, the journal's ResidentMemories bookmark and
##    BondEvents_mianmian.
## SHOTS (per size, 11): world_before_picnic, world_ranch, dialogue_stage0,
##  dialogue_talked, gift, events_stage1, memories_ranch, events_stage4,
##  feed_station, world_fallback, world_all_occupied; plus events_stage1_locked
##  (熟悉 tab) and events_stage4_tab1 (認識 tab). The tabbed events page must need
##  NO outer scrolling at every tab (hard check).
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const ID:="mianmian"
const DEFAULT_CELL:=Vector2i(49,33)
const FALLBACK_CELL:=Vector2i(48,33)
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

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("RESIDENT_BOND_RANCH_SCENE checks=%d failures=%d shots=%d"%[checks,failures,shots])
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

## Distinct colours on a coarse grid: a blank or flat frame has very few.
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
	print("RESIDENT_BOND_RANCH_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
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

func text_fits(b:Button)->bool:
	return b!=null and b.size.x+0.5>=b.get_minimum_size().x and b.size.y+0.5>=b.get_minimum_size().y

## Strict: on view without scrolling.
func on_view_now(names:Array,label:String)->void:
	for control_name in names:
		var c:=control(str(control_name))
		check(c!=null and visible(c) and inside_modal(c),"%s fully on view inside the card without scrolling (%s)"%[control_name,label])
		if c is Button:check(text_fits(c as Button),"%s text not cut (%s)"%[control_name,label])

func on_view(names:Array,label:String)->void:
	for control_name in names:
		var c:=control(str(control_name))
		var ok:bool=await reach(c,label)
		check(ok,"%s fully on view inside the card (%s)"%[control_name,label])
		if ok and c is Button:check(text_fits(c as Button),"%s text not cut (%s)"%[control_name,label])

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

func stand(at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=at.x;person.y=at.y
	await refresh()

func near(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(0.5,-0.4)

## For world shots: 1.25 tiles west-south-west of her (she stays the closest point,
## the player sprite does not cover her, and the camera frames the cow/sheep row).
func beside(cell:Vector2i)->Vector2:
	return Vector2(cell)+Vector2(-0.7,0.9)

func ranch()->Vector2i:
	return World.bond_place(app.session.snapshot,ID)[1]

func press(control_name:String)->bool:
	var button:=control(control_name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+control_name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await settle()
	return true

func press_button(b:BaseButton,label:String)->bool:
	check(b!=null and not b.disabled,"Enabled button: "+label)
	if b==null or b.disabled:return false
	await create_timer(0.12).timeout
	b.pressed.emit()
	await settle()
	return true

func close()->void:
	app._close_modal()
	await settle()

func bond()->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(ID,{})
	return found if found is Dictionary else {}

func bag_count(item:String)->int:
	return int(w.state.players[id].inventory.get(item,0))

func npc()->String:
	return Bond.name_of(ID)

func dialogue_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and control("BondSummary")!=null and texts().contains("和%s聊聊"%npc())

func events_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and texts().contains("%s的關係事件"%npc()) and control("BondSummary")==null

func open_by_interact(label:String,cell:Vector2i=Vector2i(-1,-1))->bool:
	if cell==Vector2i(-1,-1):cell=ranch()
	await close()
	await stand(near(cell))
	app._interact()
	await settle()
	var ok:=dialogue_open()
	check(ok,"E next to 棉棉 opens 和棉棉聊聊 ("+label+")")
	return ok

func stock_bag()->void:
	var inv:Dictionary=w.state.players[id].inventory
	for item in inv.keys():
		if Bond.giftable(ID,str(item)):inv[item]=0
	inv["feed"]=2;inv["wool"]=1;inv["wool_cloth"]=1;inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

# ------------------------------------------------------------ world view --

## Screen-space (viewport pixel) position of a world point.
## WorldView draws screen() coordinates scaled by view_zoom() (same space as
## world_label_placements), so the zoom is applied before the canvas transform.
func to_pixels(world_point:Vector2)->Vector2:
	return app.view.get_global_transform_with_canvas()*(app.view.screen(world_point)*float(app.view.view_zoom()))

## 棉棉's sprite box: 32×48 (×zoom) above her foot.
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

## The focus label 「棉棉」 is placed, on screen and does not overlap other labels.
func world_label_ok(label:String,cell:Vector2i)->void:
	check(str(app.view.focused_label)==ID,"World focus is 棉棉 (%s): %s"%[label,str(app.view.focused_label)])
	var zoom:float=app.view.view_zoom()
	var placements:Array=app.view.world_label_placements(Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom))
	var mine:Dictionary={}
	for entry:Dictionary in placements:
		if str(entry.id)==ID:mine=entry
	check(not mine.is_empty() and str(mine.get("title",""))=="棉棉" and bool(mine.get("active",false)),"Active world label 「棉棉」 placed (%s): %s"%[label,str(mine)])
	if mine.is_empty():return
	var box:Rect2=mine.rect
	var on_screen:=Rect2(Vector2.ZERO,app.view.get_viewport_rect().size/zoom)
	check(on_screen.encloses(box),"「棉棉」 label inside the viewport (%s) %s"%[label,str(box)])
	var others:=PackedStringArray()
	for entry:Dictionary in placements:
		if entry==mine:continue
		others.append("%s@%s"%[entry.title,str(entry.rect)])
		check(not box.intersects(entry.rect),"「棉棉」 label does not overlap 「%s」 (%s) %s vs %s"%[entry.title,label,str(box),str(entry.rect)])
	print("NOTE %s: 棉棉 label %s, other labels: %s"%[label,str(box),", ".join(others)])
	var foot:=to_pixels(Vector2(cell)+Vector2(0.5,0.7))
	check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(foot),"棉棉's foot is on screen (%s) %s"%[label,str(foot)])

# --------------------------------------------------------------- flows --

func size_flow()->void:
	var person:Dictionary=w.state.players[id]
	person.erase("bonds")  # PRESET: fresh relationship
	w.state.objects.erase(World.key(DEFAULT_CELL))
	stock_bag()
	# 0. Before the picnic: nobody at the ranch cell.
	await close()
	w.state.picnic=false
	await stand(beside(DEFAULT_CELL))
	check(str(app.view.focused_label)!=ID,"No 棉棉 focus before the picnic "+tag)
	var before:Image=await shot("world_before_picnic")
	# 1. World view after the picnic.
	w.state.picnic=true
	await stand(beside(DEFAULT_CELL))
	for animal_id:String in World.LIVESTOCK.ANIMALS:
		var station:=to_pixels(Vector2(World.LIVESTOCK.ANIMALS[animal_id].cell)+Vector2(0.5,0.9))
		check(Rect2(Vector2.ZERO,Vector2(root.size)).has_point(station),"%s station foot on screen next to 棉棉 (%s) %s"%[animal_id,tag,str(station)])
		print("NOTE world ranch %s: %s foot at %s"%[tag,animal_id,str(station)])
	check(ranch()==DEFAULT_CELL,"棉棉 stands at 49,33 "+tag)
	world_label_ok("world ranch "+tag,DEFAULT_CELL)
	var ranch_image:Image=await shot("world_ranch")
	var box:=sprite_box(DEFAULT_CELL)
	var diff:=box_difference(before,ranch_image,box)
	print("NOTE world ranch %s: 棉棉 sprite box %s changed %.0f%% vs before picnic"%[tag,str(box),diff*100.0])
	check(diff>=0.15,"棉棉 is drawn at her cell (%.0f%% of the sprite box changed after the picnic) %s"%[diff*100.0,tag])
	# 2. Bond dialogue at stage 0 via the real interaction.
	var step:="dialogue stage 0 "+tag
	if not await open_by_interact(step):return
	modal_fits(step)
	on_view_now(["BondSummary","BondTalk","BondGift","BondEvents"],step)
	check(control("BondSiteBack")==null,"No BondSiteBack for 棉棉 ("+step+")")
	has_texts(["和棉棉聊聊","%s・%s"%[npc(),Bond.LOCAL_PLACES[ID]],"%s喜歡：%s"%[npc(),Bond.LIKE_TEXT[ID]],"好感・尚未認識  0／1","聊聊近況","送禮物","關係事件  0／4"],step)
	var img_before:Image=await shot("dialogue_stage0")
	await labels_whole(step)
	# 3. Talk, then reopen.
	await press("BondTalk")
	check(int(bond().get("stage",0))==1 and bool(bond().get("talked_today",false)),"Talk reaches 認識 "+tag)
	step="dialogue after talk "+tag
	if await open_by_interact(step):
		modal_fits(step)
		on_view_now(["BondSummary","BondTalk","BondGift","BondEvents"],step)
		var talk:=control("BondTalk") as Button
		check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk shows disabled 今天聊過了 ("+step+")")
		has_texts(["好感・認識  1／6","關係事件  1／4"],step)
		var img_after:Image=await shot("dialogue_talked")
		differ(img_before,img_after,"dialogue before vs after talk "+tag)
		await labels_whole(step)
	# 4. Gift chooser.
	step="gift "+tag
	var gift_pressed:=false
	if dialogue_open():gift_pressed=await press("BondGift")
	if gift_pressed:
		if modal_fits(step):
			check(texts().contains("送給棉棉的禮物"),"Gift page title ("+step+")")
			on_view_now(["BondGiftList","BondGift_feed","BondGift_wool","BondGift_wool_cloth","BondGift_radish"],step)
			check(control("BondGift_wood")==null,"wood not offered ("+step+")")
			for item in ["feed","wool","wool_cloth"]:
				var b:=control("BondGift_"+item) as Button
				check(b!=null and b.text.begins_with("喜歡・"),"%s marked 喜歡・ (%s)"%[item,step])
			var radish:=control("BondGift_radish") as Button
			check(radish!=null and not radish.text.begins_with("喜歡・"),"radish not marked liked ("+step+")")
			var back:=find_button("回到棉棉身邊")
			check(back!=null and visible(back) and inside_modal(back) and text_fits(back),"回到棉棉身邊 on view ("+step+")")
			await shot("gift")
			await labels_whole(step)
			var held:=bag_count("feed")
			await press("BondGift_feed")
			check(bag_count("feed")==held-1,"Gift removes one feed ("+step+")")
			check(int(bond().get("points",0))==Bond.TALK_POINTS+Bond.LIKED_POINTS,"Talk + liked gift = %d points (%s)"%[Bond.TALK_POINTS+Bond.LIKED_POINTS,step])
	# 5. Events page at stage 1, then 返回居民回憶.
	step="events stage 1 "+tag
	var events_pressed:=false
	if await open_by_interact(step):events_pressed=await press("BondEvents")
	if events_pressed:
		check(events_open(),"Events page opens ("+step+")")
		if modal_fits(step):
			has_texts(["棉棉的關係事件","%s・%s"%[str(Bond.STAGES[0]),str(Bond.EVENTS[ID][0].title)]],step)
			var back:=control("BondEventsBack") as Button
			check(back!=null and back.text=="返回居民回憶" and visible(back) and inside_modal(back),"BondEventsBack reads 返回居民回憶 on view without scrolling ("+step+")")
			tab_page_fits(step)
			tab_card(ID,1,0,step)
			await shot("events_stage1")
			# Locked tab 熟悉: 尚未展開 with its threshold.
			if await press_tab(1,step):
				tab_page_fits(step+" locked tab")
				tab_card(ID,1,1,step+" locked tab")
				has_texts(["尚未展開"],step+" locked tab")
				await shot("events_stage1_locked")
			if await press_button(find_button("返回居民回憶"),"返回居民回憶 "+step):
				step="memories ranch "+tag
				check(is_instance_valid(app.modal) and texts().contains("居民回憶") and find_button("返回島民手帳")!=null,"返回居民回憶 opens 居民回憶 ("+step+")")
				if modal_fits(step):
					await on_view(["BondEvents_mianmian"],step)
					has_texts(["棉棉的關係事件  1／4"],step)
					await shot("memories_ranch")
					await labels_whole(step)
	# 6. Stage-4 events (preset), opened through the journal bookmark.
	person.bonds={ID:{"points":Bond.LIMIT,"talk_day":0,"gift_day":0}}  # PRESET stage 4
	await refresh()
	check(int(bond().get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 "+tag)
	step="events stage 4 "+tag
	await close()
	app._journal("xinghe")
	await settle()
	var bookmark:=control("ResidentMemories")
	await reach(bookmark,step)
	var memories_pressed:bool=await press("ResidentMemories")
	var max_pressed:=false
	if memories_pressed:max_pressed=await press("BondEvents_mianmian")
	if max_pressed:
		check(events_open(),"Events page opens ("+step+")")
		if modal_fits(step):
			has_texts(["棉棉的關係事件","四階事件都已展開","%s・%s"%[str(Bond.STAGES[3]),str(Bond.EVENTS[ID][3].title)]],step)
			check(not texts().contains("尚未展開"),"No locked card ("+step+")")
			tab_page_fits(step)
			tab_card(ID,4,3,step)
			var img_four:Image=await shot("events_stage4")
			await event_tabs(ID,4,step)
			# Non-default tab capture: 認識.
			if await press_tab(0,step):
				tab_card(ID,4,0,step+" tab 1")
				var img_one:Image=await shot("events_stage4_tab1")
				differ(img_four,img_one,"stage-4 tab 4 vs tab 1 ("+step+")")
	# 7. Feed station still opens when the player stands at the cow.
	await close()
	var cow:Dictionary=World.LIVESTOCK.ANIMALS["cow"]
	await stand(Vector2(cow.cell)+Vector2(0.5,0.8))
	app._interact()
	await settle()
	step="feed station "+tag
	check(layout_meta()=="livestock_card" and texts().contains("%s的飼料站"%str(cow.name)),"E at the cow opens its feed station ("+step+")")
	if modal_fits(step):await shot("feed_station")
	# 8. Fallback cell.
	await close()
	w.state.objects[World.key(DEFAULT_CELL)]={"type":"wall","owner":id,"items":{}}  # PRESET wall
	await stand(beside(FALLBACK_CELL))
	check(ranch()==FALLBACK_CELL,"Wall on 49,33 moves 棉棉 to 48,33 "+tag)
	check(World.bond_place(w.state,ID)[1]==FALLBACK_CELL,"Server agrees on the fallback cell "+tag)
	world_label_ok("world fallback "+tag,FALLBACK_CELL)
	var fallback:Image=await shot("world_fallback")
	differ(ranch_image,fallback,"world ranch vs fallback "+tag)
	var moved_box:=sprite_box(FALLBACK_CELL)
	print("NOTE world fallback %s: 棉棉 sprite box %s"%[tag,str(moved_box)])
	w.state.objects.erase(World.key(DEFAULT_CELL))
	await refresh()
	# 9. Every candidate occupied: she stays on the first cell.
	await close()
	for cell:Vector2i in Bond.RANCH_CELLS:
		w.state.objects[World.key(cell)]={"type":"wall","owner":id,"items":{}}  # PRESET walls
	await stand(near(DEFAULT_CELL))
	check(ranch()==DEFAULT_CELL and World.bond_place(w.state,ID)[1]==DEFAULT_CELL,"All four candidates walled: 棉棉 stays on 49,33 (snapshot and server) "+tag)
	world_label_ok("world all occupied "+tag,DEFAULT_CELL)
	var crowded:Image=await shot("world_all_occupied")
	differ(fallback,crowded,"world fallback vs all occupied "+tag)
	print("NOTE world all occupied %s: 棉棉 sprite box %s"%[tag,str(sprite_box(DEFAULT_CELL))])
	for cell:Vector2i in Bond.RANCH_CELLS:w.state.objects.erase(World.key(cell))
	await refresh()
	check(ranch()==DEFAULT_CELL,"Removing the walls keeps 棉棉 on 49,33 "+tag)

## No fixed tree or rock on the fallback cell or directly below it (the base map
## draws those over/in front of her). 51,34 is the tree that retired 51,33.
func fixed_scenery_ok()->void:
	check(World.base_resource(Vector2i(51,34))=="tree","Probe: base_resource reports the fixed tree at 51,34 that hid her at 51,33")
	for cell:Vector2i in [FALLBACK_CELL,FALLBACK_CELL+Vector2i.DOWN]:
		var found:=World.base_resource(cell)
		check(found!="tree" and found!="rock","No fixed tree/rock at %s (fallback cell or the cell below it): '%s'"%[str(cell),found])

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
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/居民好感預覽第三批").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("bond-ranch-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"牧場旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	fixed_scenery_ok()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		tag="%dx%d"%[size.x,size.y]
		await size_flow()
	check(shots>=18,"At least 9 screenshots per size (%d)"%shots)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
