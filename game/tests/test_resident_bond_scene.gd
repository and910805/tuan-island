extends SceneTree
## T066 居民好感 native render check at 1024×640 and 1280×800.
## Screenshots go to outputs/居民好感預覽 (or --capture-dir=), named
## <w>x<h>-<step>.png. Same harness as test_mine_hoist_scene.gd.
## Run in a real window with `-- --profile=isolated-regression --village-art-preview`.
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); the real profile is never used;
##  * world time is moved forward by two whole days (time-of-day kept) so that the
##    stage-4 preset's talk_day/gift_day 0 are valid past days;
##  * picnic / board flags are NOT set; resident stories stay at 0;
##  * player.bonds is erased before each viewport size;
##  * backpack written directly: giftable items already held set to 0, then
##    tea_light 1, radish 2, wood 5;
##  * the player is teleported next to 阿榆 (home);
##  * stage-4 preset: player.bonds = {"aru":{"points":24,"talk_day":0,"gift_day":0}}.
## REALLY EXERCISED:
##  * 阿榆's dialogue through app._interact() (fallback app._resident_menu, reported);
##  * BondTalk, BondGift, BondGift_tea_light and BondEvents are pressed by emitting
##    `pressed` (real Session.perform -> World -> snapshot path);
##  * the journal through app._journal("aru").
## SHOTS (per size): dialogue-before, gift-chooser, dialogue-after (talk + gift,
##  reopened), journal, events-stage1 (default tab 認識), events-stage1-locked
##  (熟悉 tab, 尚未展開), events-stage4 (default tab 好友), events-stage4-tab1 (認識).
## The tabbed events page must need NO outer scrolling at every tab (hard check).
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Bond=preload("res://scripts/resident_bond.gd")
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
	print("RESIDENT_BOND_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
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

func shot(name:String)->Image:
	hide_toast()
	await settle()
	await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	var file:=output.path_join(name+".png")
	check(image!=null and not image.is_empty() and image.get_width()>0 and image.get_height()>0,"non-empty native image "+name)
	if image==null or image.is_empty():return image
	check(image.save_png(file)==OK,"native screenshot saved "+name)
	check(FileAccess.file_exists(file),"screenshot file exists "+name)
	var handle:=FileAccess.open(file,FileAccess.READ)
	var length:int=0
	if handle!=null:
		length=handle.get_length()
		handle.close()
	check(length>0,"screenshot file is not empty "+name)
	print("RESIDENT_BOND_SHOT %s sha256=%s"%[file,FileAccess.get_sha256(file)])
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

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

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

func on_view(names:Array,label:String)->void:
	for name in names:
		var c:=control(str(name))
		check(c!=null and visible(c) and inside_modal(c),"%s fully on view inside the card (%s)"%[name,label])

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x-0.5;person.y=p.y+0.5
	await refresh()

func press(name:String)->bool:
	var button:=control(name) as BaseButton
	check(button!=null and not button.disabled,"Enabled "+name)
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

func bond(resident:String)->Dictionary:
	var all:Variant=app.session.snapshot.get("resident_bonds",{})
	if not all is Dictionary:return {}
	var found:Variant=(all as Dictionary).get(resident,{})
	return found if found is Dictionary else {}

func dialogue_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="resident_dialogue" and control("BondSummary")!=null

func open_dialogue(label:String)->bool:
	app._resident_menu("aru")
	await settle()
	var ok:=dialogue_open()
	check(ok,"阿榆's dialogue opens with bond controls (%s)"%label)
	return ok

func stock_bag()->void:
	var inv:Dictionary=w.state.players[id].inventory
	for item in inv.keys():
		if Bond.giftable("aru",str(item)):inv[item]=0
	inv["tea_light"]=1;inv["radish"]=2;inv["wood"]=5
	app.session._send_snapshot(1)

func open_events(stage:int,label:String)->bool:
	app._journal("aru")
	await settle()
	check(layout_meta()=="resident_journal","Journal opens on 阿榆 (%s)"%label)
	var events:=control("BondEvents") as Button
	check(events!=null and events.text.contains("%d／%d"%[stage,Bond.STAGES.size()]),"BondEvents shows %d／4 (%s)"%[stage,label])
	if events==null:return false
	var scroll:=control("ModalScroll") as ScrollContainer
	if scroll!=null and not visible(events):
		scroll.ensure_control_visible(events)
		await settle()
	check(visible(events) and inside_modal(events),"BondEvents on view in the journal (%s)"%label)
	return await press_button(events,"BondEvents "+label)

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
	if output.is_empty():output=ProjectSettings.globalize_path("res://").path_join("../outputs/居民好感預覽").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	check(DisplayServer.get_name()!="headless","Runs on a native renderer")
	path=OS.get_environment("TEMP").path_join("bond-scene-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"好感旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.time=float(w.state.time)+Village.DAY*2.0  # PRESET: two whole days later
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		var person:Dictionary=w.state.players[id]
		person.erase("bonds")  # PRESET: fresh relationship
		stock_bag()            # PRESET backpack
		await place(World.REGIONS.HOME,Village.NPCS["aru"].cell)
		# 1. Dialogue before talking (real interact key path).
		app._interact()
		await settle()
		check(dialogue_open(),"Interact next to 阿榆 opens his dialogue at "+tag)
		if not dialogue_open():
			if not await open_dialogue(tag):continue
		modal_fits("dialogue before "+tag)
		on_view(["BondSummary","BondTalk","BondGift"],"dialogue before "+tag)
		has_texts(["尚未認識","聊聊近況","送禮物"],"dialogue before "+tag)
		var img_before:Image=await shot("%s-dialogue-before"%tag)
		# Talk through the real button.
		await press("BondTalk")
		check(int(bond("aru").get("stage",0))==1,"Talk reaches 認識 at "+tag)
		# 2. Gift chooser.
		if not await open_dialogue(tag):continue
		if await press("BondGift"):
			if modal_fits("gift chooser "+tag):
				on_view(["BondGiftList","BondGift_tea_light","BondGift_radish"],"gift chooser "+tag)
				check(control("BondGift_wood")==null,"Wood not offered at "+tag)
				has_texts(["喜歡・"],"gift chooser "+tag)
				await shot("%s-gift-chooser"%tag)
				var tea_before:=int(w.state.players[id].inventory.get("tea_light",0))
				await press("BondGift_tea_light")
				check(int(w.state.players[id].inventory.get("tea_light",0))==tea_before-1,"Gift removes one tea_light at "+tag)
		# 3. Dialogue after talk + gift, reopened.
		if await open_dialogue("after "+tag):
			modal_fits("dialogue after "+tag)
			on_view(["BondSummary","BondTalk","BondGift"],"dialogue after "+tag)
			var talk:=control("BondTalk") as Button
			check(talk!=null and talk.disabled and talk.text=="今天聊過了","BondTalk shows 今天聊過了 at "+tag)
			has_texts(["好感・認識"],"dialogue after "+tag)
			var img_after:Image=await shot("%s-dialogue-after"%tag)
			differ(img_before,img_after,"dialogue before vs after at "+tag)
			app._close_modal();await settle()
		# 4. Journal with 關係事件, then the stage-1 events modal.
		app._journal("aru")
		await settle()
		if modal_fits("journal "+tag):
			var events:=control("BondEvents") as Button
			var scroll:=control("ModalScroll") as ScrollContainer
			if events!=null and scroll!=null and not visible(events):
				scroll.ensure_control_visible(events)
				await settle()
			check(events!=null and visible(events),"BondEvents on view in the journal at "+tag)
			await shot("%s-journal"%tag)
		app._close_modal();await settle()
		if await open_events(1,"stage 1 "+tag):
			if modal_fits("events stage 1 "+tag):
				has_texts(["阿榆的關係事件","%s・%s"%[str(Bond.STAGES[0]),str(Bond.EVENTS["aru"][0].title)]],"events stage 1 "+tag)
				check(find_button("返回島民手帳")!=null and visible(find_button("返回島民手帳")),"返回島民手帳 on view at "+tag)
				tab_page_fits("events stage 1 "+tag)
				tab_card("aru",1,0,"events stage 1 "+tag)
				await shot("%s-events-stage1"%tag)
				# A locked tab: 熟悉 shows 尚未展開 with its threshold.
				if await press_tab(1,"events stage 1 "+tag):
					tab_page_fits("events stage 1 locked tab "+tag)
					tab_card("aru",1,1,"events stage 1 locked tab "+tag)
					has_texts(["尚未展開"],"events stage 1 locked tab "+tag)
					await shot("%s-events-stage1-locked"%tag)
		app._close_modal();await settle()
		# 5. Stage-4 preset.
		person=w.state.players[id]
		person.bonds={"aru":{"points":24,"talk_day":0,"gift_day":0}}  # PRESET
		await refresh()
		check(int(bond("aru").get("stage",0))==Bond.STAGES.size(),"Preset reaches 好友 at "+tag)
		if await open_events(Bond.STAGES.size(),"stage 4 "+tag):
			if modal_fits("events stage 4 "+tag):
				has_texts(["%s・%s"%[str(Bond.STAGES[3]),str(Bond.EVENTS["aru"][3].title)]],"events stage 4 "+tag)
				check(not texts().contains("尚未展開"),"No locked card at stage 4 ("+tag+")")
				tab_page_fits("events stage 4 "+tag)
				tab_card("aru",4,3,"events stage 4 "+tag)
				var img_four:Image=await shot("%s-events-stage4"%tag)
				await event_tabs("aru",4,"events stage 4 "+tag)
				# Non-default tab capture: 認識.
				if await press_tab(0,"events stage 4 "+tag):
					tab_card("aru",4,0,"events stage 4 tab 1 "+tag)
					var img_one:Image=await shot("%s-events-stage4-tab1"%tag)
					differ(img_four,img_one,"stage-4 tab 4 vs tab 1 at "+tag)
		app._close_modal();await settle()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
