extends SceneTree
## T066 第二批居民好感（茶茶、星禾）native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/居民好感預覽第二批 (or --capture-dir=), named
## <step>_<w>x<h>.png. Same harness as test_resident_bond_scene.gd.
## Run in a real window with `-- --profile=isolated-regression --village-art-preview`.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    max-stage preset's talk_day/gift_day 0 are valid past days;
##  * tea_ceramics record for the player = TEA_CERAMICS.FRESH with intro=true
##    (茶茶's host page shows her normal line instead of "先向渡口的小栗收下介紹信");
##  * lanyang_life is left fresh (canal not repaired); greenhouse_reported stays false;
##  * player.bonds is erased before each viewport size;
##  * backpack written directly: every item giftable to 茶茶 or 星禾 set to 0, then
##    tea_leaf 2 (茶茶 liked), radish 2 (common), bluebell_seed 1 (星禾 liked), wood 5;
##  * the player is teleported one tile west of World.bond_place(): maokong next to
##    TEA_CERAMICS.TEA_NPC, then lanyang next to LANYANG_LIFE.SERVICE;
##  * max-stage preset, per resident right before its last capture:
##    player.bonds[<id>]={"points":24,"talk_day":0,"gift_day":0}.
## REALLY EXERCISED (buttons pressed by emitting `pressed`, real Session.perform path):
##  * site pages opened through app._tea_host() / app._gardener_menu();
##  * BondOpen (site -> bond dialogue), BondTalk, BondSiteBack, BondGift,
##    BondGift_<liked item>, BondEvents (dialogue -> events), the journal's
##    ResidentMemories bookmark and the memories page's BondEvents_chacha;
##  * the 星禾 journal page through app._journal("xinghe").
## SHOTS (per size, 14): chacha_site, chacha_dialogue_stage0, chacha_dialogue_talked,
##  chacha_gift, chacha_events_stage1, chacha_events_stage4, xinghe_site,
##  xinghe_dialogue_stage0, xinghe_dialogue_talked, xinghe_gift, xinghe_events_stage1,
##  xinghe_journal, memories_local, xinghe_events_stage4; plus, per resident,
##  <id>_events_stage1_locked (熟悉 tab) and <id>_events_stage4_tab1 (認識 tab).
## Anything that is only reachable after scrolling the modal prints a `NOTE ...` line,
## except the tabbed events page: it must need NO outer scrolling at every tab.
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
const LOCALS:=["chacha","xinghe"]
const LIKED_GIFT:={"chacha":"tea_leaf","xinghe":"bluebell_seed"}
const COMMON_GIFT:="radish"
const NOT_OFFERED:={"chacha":["wood","bluebell_seed"],"xinghe":["wood","tea_leaf"]}
const PLACE_NAMES:={"chacha":"茶茶・貓空合作茶園","xinghe":"星禾・蘭陽水圳木橋旁"}
const BACK_TEXT:={"chacha":"回到茶園","xinghe":"回到水圳手記"}
const EVENTS_BACK:={"chacha":"返回居民回憶","xinghe":"返回島民手帳"}
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var output:=""
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("RESIDENT_BOND_LOCAL_SCENE checks=%d failures=%d"%[checks,failures])
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

func shot(file_name:String)->Image:
	hide_toast()
	await create_timer(0.2).timeout  # modal fade-in (LifeShell.reveal) is 0.16 s
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var file:=output.path_join(file_name+".png")
	check(image!=null and not image.is_empty() and image.get_width()>0 and image.get_height()>0,"non-empty native image "+file_name)
	if image==null or image.is_empty():return image
	check(image.save_png(file)==OK,"native screenshot saved "+file_name)
	check(FileAccess.file_exists(file),"screenshot file exists "+file_name)
	var handle:=FileAccess.open(file,FileAccess.READ)
	var length:int=0
	if handle!=null:
		length=handle.get_length()
		handle.close()
	check(length>0,"screenshot file is not empty "+file_name)
	print("RESIDENT_BOND_LOCAL_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
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

## Visible Label + Button texts inside the current modal.
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

## Fully on view inside the card; if it is only reachable by scrolling the
## modal, scroll to it, re-check and print a NOTE instead of loosening the check.
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

func text_fits(b:Button)->bool:
	return b!=null and b.size.x+0.5>=b.get_minimum_size().x and b.size.y+0.5>=b.get_minimum_size().y

func on_view(names:Array,label:String)->void:
	for control_name in names:
		var c:=control(str(control_name))
		var ok:bool=await reach(c,label)
		check(ok,"%s fully on view inside the card (%s)"%[control_name,label])
		if ok and c is Button:check(text_fits(c as Button),"%s text not cut (%s)"%[control_name,label])

## Every visible, non-empty label in the modal is inside the card, not hidden by
## the scroll viewport (after scrolling to it if needed) and shows all its lines.
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
		var whole:=visible(l) and inside_modal(l) and l.get_visible_line_count()>=l.get_line_count()
		if not whole:bad.append(l.text.left(24).replace("\n"," "))
	check(seen>0,"Modal has labels ("+label+")")
	check(bad.is_empty(),"Labels not cut (%s): %s"%[label," | ".join(bad)])
	if scrolled>0:print("NOTE %s: %d label(s) reachable only after scrolling the modal"%[label,scrolled])

## BondOpen keeps clear of every other control in its row, and the row stays in the card.
func row_clear(c:Control,label:String)->void:
	check(c!=null and c.get_parent() is Container,"BondOpen sits in a container row ("+label+")")
	if c==null:return
	var rect:=c.get_global_rect()
	var neighbours:=0
	for node in c.get_parent().get_children():
		var other:=node as Control
		if other==null or other==c or not other.is_visible_in_tree():continue
		neighbours+=1
		check(not rect.intersects(other.get_global_rect()),"BondOpen does not overlap %s (%s)"%[other.name,label])
		check(inside_modal(other),"Row neighbour %s inside the card (%s)"%[other.name,label])
	check(neighbours>0,"BondOpen has row neighbours ("+label+")")

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x-0.5;person.y=p.y+0.5
	await refresh()

func press(control_name:String)->bool:
	var button:=control(control_name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+control_name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await settle()
	return true

func bond(resident:String)->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(resident,{})
	return found if found is Dictionary else {}

func bag_count(item:String)->int:
	return int(w.state.players[id].inventory.get(item,0))

func site_open(resident:String)->bool:
	if not is_instance_valid(app.modal):return false
	var modal_node:=app.modal as Node
	if resident=="chacha":return layout_meta()=="tea_ceramics" and str(modal_node.get_meta("tea_site",""))=="host"
	return layout_meta()=="lanyang_garden" and str(modal_node.get_meta("garden_mode",""))=="canal"

func open_site(resident:String)->bool:
	if resident=="chacha":app._tea_host()
	else:app._gardener_menu()
	await settle()
	return site_open(resident)

func dialogue_open(resident:String)->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and control("BondSummary")!=null and control("BondSiteBack")!=null and texts().contains("和%s聊聊"%Bond.name_of(resident))

func events_open(resident:String)->bool:
	return is_instance_valid(app.modal) and layout_meta()=="community_board" and texts().contains("%s的關係事件"%Bond.name_of(resident)) and control("BondSummary")==null

## Site page -> real BondOpen press. Falls back to app._resident_bond_menu (reported).
func open_dialogue(resident:String,label:String)->bool:
	var site_ok:bool=await open_site(resident)
	check(site_ok,"%s site page opens (%s)"%[resident,label])
	if site_ok:await press("BondOpen")
	var ok:=dialogue_open(resident)
	check(ok,"BondOpen opens %s's bond dialogue (%s)"%[resident,label])
	if not ok:
		app._resident_bond_menu(resident)
		await settle()
		ok=dialogue_open(resident)
	return ok

func stock_bag()->void:
	var inv:Dictionary=w.state.players[id].inventory
	for item in inv.keys():
		for resident in LOCALS:
			if Bond.giftable(str(resident),str(item)):inv[item]=0
	inv["tea_leaf"]=2;inv["radish"]=2;inv["bluebell_seed"]=1;inv["wood"]=5
	app.session._send_snapshot(1)

func preset_tea_intro()->void:
	var tea_players:Dictionary=w.state.tea_ceramics.players
	var record:Dictionary=(World.TEA_CERAMICS.FRESH as Dictionary).duplicate(true)
	record["intro"]=true
	tea_players[id]=record

## Before anyone is met, 居民回憶 lists no local resident button.
func memories_hidden_at_stage0(tag:String)->void:
	app._journal("xinghe")
	await settle()
	check(layout_meta()=="resident_journal","Journal opens on 星禾 at stage 0 "+tag)
	if await press("ResidentMemories"):
		check(control("BondEvents_chacha")==null and control("BondEvents_xinghe")==null,"居民回憶 hides local bond buttons at stage 0 "+tag)
	app._close_modal();await settle()

func resident_flow(resident:String,tag:String)->void:
	var who:=Bond.name_of(resident)
	var spot:Array=World.bond_place(w.state,resident)
	if resident=="chacha":
		check(str(spot[0])==World.TEA_CERAMICS.MAOKONG and spot[1]==World.TEA_CERAMICS.TEA_NPC,"茶茶 stands at the tea host cell")
	else:
		check(str(spot[0])==World.REGIONS.LANYANG and spot[1]==World.LANYANG_LIFE.SERVICE,"星禾 stands at the canal service cell")
	await place(str(spot[0]),spot[1])
	check(str(app.session.snapshot.get("region_id",""))==str(spot[0]),"Player preset into %s at %s"%[spot[0],tag])
	var step:="%s site %s"%[resident,tag]
	# 1. Site page with BondOpen.
	var site_ok:bool=await open_site(resident)
	check(site_ok,"Site page opens: "+step)
	if site_ok:
		modal_fits(step)
		await on_view(["BondOpen"],step)
		var open_button:=control("BondOpen") as Button
		check(open_button!=null and open_button.text=="和%s聊聊"%who and not open_button.disabled,"BondOpen reads 和%s聊聊 and is enabled (%s)"%[who,step])
		row_clear(open_button,step)
		if resident=="chacha":await on_view(["TeaJournal","TeaResidentPortrait"],step)
		await shot("%s_site_%s"%[resident,tag])
		await labels_whole(step)
	# 2. Bond dialogue at stage 0 (opened with the real BondOpen press).
	step="%s dialogue stage 0 %s"%[resident,tag]
	if not await open_dialogue(resident,step):return
	modal_fits(step)
	check(int(bond(resident).get("stage",-1))==0,"Stage 0 before talking: "+step)
	await on_view(["BondSummary","BondTalk","BondGift","BondEvents","BondSiteBack"],step)
	has_texts(["和%s聊聊"%who,str(PLACE_NAMES[resident]),"尚未認識","聊聊近況","送禮物","關係事件  0／4",str(BACK_TEXT[resident])],step)
	var img_before:Image=await shot("%s_dialogue_stage0_%s"%[resident,tag])
	await labels_whole(step)
	# 3. Talk through the real button, then reopen.
	await press("BondTalk")
	check(int(bond(resident).get("stage",0))==1,"Talk reaches 認識 (%s %s)"%[resident,tag])
	check(bool(bond(resident).get("talked_today",false)),"Talk marked for today (%s %s)"%[resident,tag])
	step="%s dialogue after talk %s"%[resident,tag]
	if await open_dialogue(resident,step):
		modal_fits(step)
		await on_view(["BondSummary","BondTalk","BondGift","BondEvents","BondSiteBack"],step)
		var talk:=control("BondTalk") as Button
		check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk shows disabled 今天聊過了 ("+step+")")
		has_texts(["好感・認識","關係事件  1／4"],step)
		var img_after:Image=await shot("%s_dialogue_talked_%s"%[resident,tag])
		differ(img_before,img_after,"%s dialogue before vs after talk at %s"%[resident,tag])
		await labels_whole(step)
		await press("BondSiteBack")
		check(site_open(resident),"BondSiteBack returns to the site page ("+step+")")
	# 4. Gift chooser with one liked and one common gift.
	step="%s gift %s"%[resident,tag]
	var liked:String=LIKED_GIFT[resident]
	if await open_dialogue(resident,step):
		if await press("BondGift"):
			if modal_fits(step):
				check(texts().contains("送給%s的禮物"%who),"Gift page title ("+step+")")
				await on_view(["BondGiftList","BondGift_"+liked,"BondGift_"+COMMON_GIFT],step)
				for item in NOT_OFFERED[resident]:check(control("BondGift_"+str(item))==null,"%s not offered (%s)"%[item,step])
				var liked_button:=control("BondGift_"+liked) as Button
				var common_button:=control("BondGift_"+COMMON_GIFT) as Button
				check(liked_button!=null and liked_button.text.begins_with("喜歡・"),"Liked gift marked 喜歡・ ("+step+")")
				check(common_button!=null and not common_button.text.begins_with("喜歡・"),"Common gift not marked liked ("+step+")")
				await shot("%s_gift_%s"%[resident,tag])
				await labels_whole(step)
				var held:=bag_count(liked)
				await press("BondGift_"+liked)
				check(bag_count(liked)==held-1,"Gift removes one %s (%s)"%[liked,step])
				check(int(bond(resident).get("points",0))==Bond.TALK_POINTS+Bond.LIKED_POINTS,"Talk + liked gift = %d points (%s)"%[Bond.TALK_POINTS+Bond.LIKED_POINTS,step])
				check(bool(bond(resident).get("gifted_today",false)),"Gift marked for today ("+step+")")
	# 5. Events page at stage 1 (dialogue -> BondEvents).
	step="%s events stage 1 %s"%[resident,tag]
	if await open_dialogue(resident,step):
		if await press("BondEvents"):
			check(events_open(resident),"Events page opens ("+step+")")
			if modal_fits(step):
				has_texts(["%s的關係事件"%who,"%s・%s"%[str(Bond.STAGES[0]),str(Bond.EVENTS[resident][0].title)]],step)
				var back:=control("BondEventsBack") as Button
				check(back!=null and back.text==str(EVENTS_BACK[resident]) and visible(back) and inside_modal(back),"BondEventsBack reads %s on view without scrolling (%s)"%[EVENTS_BACK[resident],step])
				tab_page_fits(step)
				tab_card(resident,1,0,step)
				await shot("%s_events_stage1_%s"%[resident,tag])
				# Locked tab 熟悉: 尚未展開 with its threshold.
				if await press_tab(1,step):
					tab_page_fits(step+" locked tab")
					tab_card(resident,1,1,step+" locked tab")
					has_texts(["尚未展開"],step+" locked tab")
					await shot("%s_events_stage1_locked_%s"%[resident,tag])
	app._close_modal();await settle()

func events_max(resident:String,tag:String)->void:
	var who:=Bond.name_of(resident)
	var person:Dictionary=w.state.players[id]
	var bonds:Dictionary=person.get("bonds",{})
	bonds[resident]={"points":Bond.LIMIT,"talk_day":0,"gift_day":0}  # PRESET
	person.bonds=bonds
	await refresh()
	check(int(bond(resident).get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 (%s %s)"%[resident,tag])
	var step:="%s events stage 4 %s"%[resident,tag]
	if await open_dialogue(resident,step):
		var events:=control("BondEvents") as Button
		check(events!=null and events.text.contains("%d／%d"%[Bond.STAGES.size(),Bond.STAGES.size()]),"BondEvents shows 4／4 ("+step+")")
		if await press("BondEvents"):
			check(events_open(resident),"Events page opens ("+step+")")
			if modal_fits(step):
				has_texts(["%s的關係事件"%who,"四階事件都已展開","%s・%s"%[str(Bond.STAGES[3]),str(Bond.EVENTS[resident][3].title)]],step)
				check(not texts().contains("尚未展開"),"No locked card ("+step+")")
				tab_page_fits(step)
				tab_card(resident,4,3,step)
				var img_four:Image=await shot("%s_events_stage4_%s"%[resident,tag])
				await event_tabs(resident,4,step)
				# Non-default tab capture: 認識.
				if await press_tab(0,step):
					tab_card(resident,4,0,step+" tab 1")
					var img_one:Image=await shot("%s_events_stage4_tab1_%s"%[resident,tag])
					differ(img_four,img_one,"stage-4 tab 4 vs tab 1 (%s)"%step)
	app._close_modal();await settle()

## 星禾 journal page (BondEvents), then 居民回憶 with both local buttons.
func journal_and_memories(tag:String)->void:
	var step:="xinghe journal "+tag
	app._journal("xinghe")
	await settle()
	if modal_fits(step):
		check(layout_meta()=="resident_journal","Journal layout ("+step+")")
		var bookmark:=control("XingheBookmark") as Button
		check(bookmark!=null and bookmark.button_pressed,"星禾 bookmark selected ("+step+")")
		var events:=control("BondEvents") as Button
		check(events!=null and events.text.contains("1／%d"%Bond.STAGES.size()),"Journal BondEvents shows 1／4 ("+step+")")
		await on_view(["BondEvents"],step)
		has_texts(["星禾・照顧水圳與幼苗的人"],step)
		await shot("xinghe_journal_"+tag)
		await labels_whole(step)
		var memories_ok:bool=await reach(control("ResidentMemories"),step)
		check(memories_ok,"ResidentMemories bookmark on view ("+step+")")
	step="memories local "+tag
	if await press("ResidentMemories"):
		if modal_fits(step):
			check(layout_meta()=="community_board","Memories layout ("+step+")")
			await on_view(["BondEvents_chacha","BondEvents_xinghe"],step)
			has_texts(["居民回憶","茶茶的關係事件  4／4","星禾的關係事件  1／4"],step)
			var chacha_button:=control("BondEvents_chacha")
			var xinghe_button:=control("BondEvents_xinghe")
			check(chacha_button!=null and xinghe_button!=null and not chacha_button.get_global_rect().intersects(xinghe_button.get_global_rect()),"Local memory buttons do not overlap ("+step+")")
			await shot("memories_local_"+tag)
			await labels_whole(step)
			if await press("BondEvents_chacha"):
				check(events_open("chacha") and find_button("返回居民回憶")!=null,"BondEvents_chacha opens 茶茶's events with 返回居民回憶 ("+step+")")
	app._close_modal();await settle()

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
	create_timer(170.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 170 s")
		finish())
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/居民好感預覽第二批").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("bond-local-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"好感旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	preset_tea_intro()  # PRESET: tea chapter introduction received
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		var person:Dictionary=w.state.players[id]
		person.erase("bonds")  # PRESET: fresh relationships
		stock_bag()            # PRESET backpack
		var first:Array=World.bond_place(w.state,"chacha")
		await place(str(first[0]),first[1])
		await memories_hidden_at_stage0(tag)
		await resident_flow("chacha",tag)
		await events_max("chacha",tag)
		await resident_flow("xinghe",tag)
		await journal_and_memories(tag)
		await events_max("xinghe",tag)
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
