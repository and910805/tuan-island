extends SceneTree
## 玉米濃湯 (corn_chowder) — third shared dish on the 渡口的共餐桌 page (community_ui.gd),
## headless at 1024×640 and 1280×800. Same harness as test_table_warmer_ui.gd /
## test_tea_service_ui.gd: real Session host, real snapshot round trips.
##
## PRESET / FIXTURE (written directly, not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true is
##    set here (the runner may also pass --village-art-preview);
##  * state.board=true, state.picnic=true and state.community={"table":"39,30"};
##    state.table_warmer, state.tea_service and state.tea_revisit are ERASED before each
##    size (un-installed 保溫底座 card with materials / source rows, 茶陶上桌 card with
##    the red NOT_DONE reason line); state.table_warmer={"installed":true} is WRITTEN once
##    per size for the installed focus-neighbour check, then erased again;
##  * BAGS ARE WRITTEN DIRECTLY: corn_chowder / trout_hotpot / watermelon_platter /
##    warmer materials for the local player and corn_chowder for the fixture islander;
##    no cooking is played here;
##  * one fixture islander "chowder-guest" is added with World.add_player and placed by
##    writing x/y beside the table; its serve / claim go through World.act (the real
##    rules, but not through a client);
##  * the local player is teleported by writing region/x/y (no walking) to TABLE_SPOT;
##  * session rate buckets / action_clock are cleared between my own actions.
## REALLY EXERCISED (local player):
##  * the fresh host's 望安 arrival card is closed by a first real KEY_E;
##  * KEY_E through root.push_input opens the page; KEY_ESCAPE closes it; KEY_UP / DOWN
##    move focus between the watermelon row, the chowder row and 加裝保溫底座;
##  * DishMain_chowder / DishMain_hotpot / DishMain_watermelon presses grab focus and
##    emit `pressed`; every action is a real Session.perform -> World -> snapshot ->
##    main._state_changed -> in-place page update.
## NOT COVERED HERE: world pixels / the world table label (濃湯 N); gamepad input; the
## non-preview layout; a second real client (the fixture islander has no page, so the
## "other player" direction is checked as: the islander serves and claims, my page shows
## 領一份 enabled and never 你已領過, and the public snapshot carries no claimed list).
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/community_ui.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const Tea=preload("res://scripts/tea_service.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const TABLE:=Vector2i(39,30)
const TABLE_SPOT:=Vector2(39.5,31.6)
const GUEST_SPOT:=Vector2(40.3,31.6)
const GUEST:="chowder-guest"
const CHOWDER:="corn_chowder"
const SERVE_TIP:="端上四份玉米濃湯"
const SHORT_TIP:="需要 4 份玉米濃湯才能上桌"
const CLAIM_TIP:="從桌上領一份玉米濃湯"
const CLAIMED_TIP:="這一輪你已經領過了"
const HOTPOT_FULL:="雪點鱒魚火鍋 · 剩 4 / 4 份"
const MELON_FULL:="夏日西瓜盤 · 剩 4 / 4 份"
var app
var w
var id:=""
var path:=""
var checks:=0
var failures:=0
var presets:=0
var finished:=false
var request:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("NOTE CORN_CHOWDER_UI presets=%d (direct state writes marked # PRESET)"%presets)
	print("CORN_CHOWDER_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE CORN_CHOWDER_UI "+message)

# ------------------------------------------------------------------ helpers --

func control(node_name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(node_name,true,false) as Control

func button(node_name:String)->Button:
	return control(node_name) as Button

func label_text(node_name:String)->String:
	var l:=control(node_name) as Label
	return l.text if l!=null else ""

func shown(node_name:String)->bool:
	var c:=control(node_name)
	return c!=null and c.is_visible_in_tree()

func page_open()->bool:
	return is_instance_valid(app.modal) and str((app.modal as Node).get_meta("life_modal_layout",""))==UI.LAYOUT

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func not_cut(l:Label)->bool:
	if l==null:return false
	if l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func button_not_cut(b:Button)->bool:
	if b==null:return false
	if b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x

func rect_info(c:Control)->String:
	var modal_rect:="none"
	if is_instance_valid(app.modal):modal_rect=str((app.modal as Control).get_global_rect())
	return "modal=%s control=%s"%[modal_rect,str(c.get_global_rect()) if c!=null else "null"]

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	if app.view!=null and app.view.has_method("_process"):app.view._process(0.0)
	app._refresh_hud()
	await settle()

func person()->Dictionary:
	return w.state.players[id]

func bag()->Dictionary:
	return person().inventory

func held(item:String)->int:
	return int(bag().get(item,0))

func snap()->Dictionary:
	return app.session.snapshot

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focused_name()->String:
	var focus_owner:=root.gui_get_focus_owner()
	return str(focus_owner.name) if focus_owner!=null else "none"

func stand(at:Vector2,region:String=World.REGIONS.HOME)->void:
	var p:Dictionary=person()
	p.region=region  # PRESET
	p.x=at.x;p.y=at.y  # PRESET
	presets+=1
	await refresh()
	var v=app.view
	var me:String=app.session.own_id
	if v.goals.has(me):
		v.starts[me]=v.goals[me]
		v.display_positions[me]=v.goals[me]
	await settle()

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

func interact_key()->void:
	app.session.rates[1].clear()
	await key(KEY_E)
	await refresh()

func press(node_name:String,label:String)->bool:
	var b:=button(node_name)
	check(b!=null and not b.disabled and b.is_visible_in_tree(),"Enabled %s (%s)"%[node_name,label])
	if b==null or b.disabled:return false
	app.action_clock=0
	app.session.rates[1].clear()
	b.grab_focus()
	await create_timer(0.05).timeout
	b.pressed.emit()
	await settle()
	await refresh()
	return true

func close_page()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func set_bag(values:Dictionary)->void:
	for item:String in values:bag()[item]=int(values[item])  # PRESET
	presets+=1
	await refresh()

## The fixture islander acts through World.act (real rules); must succeed.
func guest_act(action:String)->bool:
	request+=1
	var p:Dictionary=w.state.players[GUEST]
	p.region=World.REGIONS.HOME  # PRESET
	p.x=GUEST_SPOT.x;p.y=GUEST_SPOT.y  # PRESET (beside the table)
	presets+=1
	var result:Dictionary=w.act(GUEST,"chowder-ui-fixture-%d"%request,action,TABLE,"")
	check(bool(result.get("ok",false)),"Fixture %s %s: %s"%[GUEST,action,str(result.get("message",""))])
	return bool(result.get("ok",false))

## Server-side chowder round ({} when none).
func chowder_state()->Dictionary:
	var community:Variant=w.state.get("community",{})
	if not community is Dictionary:return {}
	var meal:Variant=(community as Dictionary).get("chowder",{})
	return meal if meal is Dictionary else {}

## Client snapshot chowder round ({} when none).
func chowder_snap()->Dictionary:
	var community:Variant=snap().get("community",{})
	if not community is Dictionary:return {}
	var meal:Variant=(community as Dictionary).get("chowder",{})
	return meal if meal is Dictionary else {}

## DishText_chowder must equal CommunityUI.portion_text for the current snapshot.
func text_matches(label:String)->void:
	var want:String=UI.portion_text("chowder",chowder_snap(),held(CHOWDER))
	check(label_text("DishText_chowder")==want,"DishText_chowder equals portion_text 「%s」 (%s): %s"%[want,label,label_text("DishText_chowder")])

func expect_chowder(caption:String,enabled:bool,tip:String,text:String,label:String)->void:
	var b:=button("DishMain_chowder")
	check(b!=null and b.is_visible_in_tree(),"DishMain_chowder shown (%s)"%label)
	if b==null:return
	check(b.text==caption,"DishMain_chowder caption 「%s」 (%s): %s"%[caption,label,b.text])
	check(b.disabled!=enabled,"DishMain_chowder %s (%s)"%["enabled" if enabled else "disabled",label])
	check(b.tooltip_text==tip,"DishMain_chowder tooltip 「%s」 (%s): %s"%[tip,label,b.tooltip_text])
	check(label_text("DishText_chowder")==text,"DishText_chowder 「%s」 (%s): %s"%[text,label,label_text("DishText_chowder")])
	text_matches(label)

func node_ids()->Dictionary:
	var out:Dictionary={}
	out["modal"]=(app.modal as Object).get_instance_id() if is_instance_valid(app.modal) else 0
	for node_name:String in ["CommunityServings","Dish_hotpot","Dish_watermelon","Dish_chowder","DishIcon_chowder","DishText_chowder","DishMain_chowder","DishMain_hotpot","DishMain_watermelon","WarmerCard","TeaCard"]:
		var c:=control(node_name)
		out[node_name]=c.get_instance_id() if c!=null else 0
	return out

## Everything on the page except the chowder row (and the footer reply).
func others(skip:Array=[])->Dictionary:
	var out:Dictionary={}
	var labels:Array=["DishText_hotpot","DishText_watermelon","WarmerStatus","WarmerRule","WarmerReason","WarmerSource","TeaChip","TeaStatus","TeaNote","TeaReason"]
	for item:String in Warmer.COST_ORDER:labels.append("WarmerMat_"+item)
	for node_name:String in labels:
		if skip.has(node_name):continue
		out[node_name]="%s|%s"%[label_text(node_name),str(shown(node_name))]
	for node_name:String in ["DishMain_hotpot","DishMain_watermelon","HotpotWarm","WarmerInstall","TeaPlace","TeaBrew_light","TeaBrew_deep","TeaSip","TeaTake"]:
		if skip.has(node_name):continue
		var b:=button(node_name)
		out[node_name]=("%s|%s|%s|%s"%[b.text,str(b.disabled),b.tooltip_text,str(shown(node_name))]) if b!=null else "missing"
	return out

func diff(a:Dictionary,b:Dictionary)->String:
	var out:=PackedStringArray()
	for k in a:
		if str(a[k])!=str(b.get(k,"<none>")):out.append("%s: %s -> %s"%[str(k),str(a[k]),str(b.get(k,"<none>"))])
	return "; ".join(out)

func neighbor(b:Control,node_path:NodePath)->String:
	if b==null or node_path.is_empty():return "none"
	var n:Node=b.get_node_or_null(node_path)
	return str(n.name) if n!=null else "none"

func row_index(node_name:String)->int:
	var rows:Array=UI.focus_rows(app)
	for r in rows.size():
		var row:Array=rows[r]
		for b:Button in row:
			if str(b.name)==node_name:return r
	return -1

func preferred_name()->String:
	var b:Button=UI.preferred(app)
	return str(b.name) if b!=null else "none"

func image_of(tex:Texture2D)->Image:
	if tex==null:return null
	var image:Image=null
	if tex is AtlasTexture:
		var atlas:=tex as AtlasTexture
		if atlas.atlas==null:return null
		var whole:Image=atlas.atlas.get_image()
		if whole==null:return null
		if whole.is_compressed():whole.decompress()
		image=whole.get_region(Rect2i(atlas.region))
	else:
		image=tex.get_image()
	if image==null:return null
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	return image

## Number of differing pixels (any channel off by more than 8/255); -1 if unreadable.
func pixel_difference(a:Image,b:Image)->int:
	if a==null or b==null:return -1
	if a.get_size()!=b.get_size():return a.get_width()*a.get_height()
	var count:=0
	for y in a.get_height():
		for x in a.get_width():
			var ca:=a.get_pixel(x,y)
			var cb:=b.get_pixel(x,y)
			if absf(ca.r-cb.r)>0.03 or absf(ca.g-cb.g)>0.03 or absf(ca.b-cb.b)>0.03 or absf(ca.a-cb.a)>0.03:count+=1
	return count

# ---------------------------------------------------------------- structure --

func structure_ok(label:String)->void:
	var servings:=control("CommunityServings")
	check(servings!=null and servings.is_visible_in_tree(),"CommunityServings shown (%s)"%label)
	if servings==null:return
	var order:=PackedStringArray()
	# 火鍋自己一列；西瓜盤與玉米濃湯並排在 DishPair 裡。
	for child in servings.get_children():
		if str(child.name).begins_with("Dish_"):order.append(str(child.name))
		if str(child.name)=="DishPair":
			for inner in child.get_children():order.append("DishPair/"+str(inner.name))
	check(order==PackedStringArray(["Dish_hotpot","DishPair/Dish_watermelon","DishPair/Dish_chowder"]),"Hotpot row, then watermelon and chowder side by side (%s): %s"%[label,", ".join(order)])
	check(UI.DISH_ORDER==["hotpot","watermelon","chowder"],"DISH_ORDER is hotpot, watermelon, chowder: %s"%str(UI.DISH_ORDER))
	check(str(World.COMMUNITY.DISHES.get("chowder",""))==CHOWDER,"COMMUNITY.DISHES.chowder is corn_chowder")
	for dish:String in ["hotpot","watermelon","chowder"]:
		var row:=control("Dish_"+dish)
		check(row!=null and servings.is_ancestor_of(row),"Dish_%s inside CommunityServings (%s)"%[dish,label])
		for part:String in ["DishIcon_","DishText_","DishMain_"]:
			var c:=control(part+dish)
			check(c!=null and row!=null and row.is_ancestor_of(c),"%s%s inside its row (%s)"%[part,dish,label])
	var icon:=control("DishIcon_chowder") as TextureRect
	check(icon!=null and icon.is_visible_in_tree(),"DishIcon_chowder shown (%s)"%label)
	if icon==null:return
	var tex:Texture2D=icon.texture
	check(tex!=null and tex.get_size()==Vector2(32,32),"Chowder icon is a 32×32 picture (%s): %s"%[label,str(tex.get_size()) if tex!=null else "null"])
	if tex==null:return
	check(tex==Items.icon(CHOWDER),"Chowder row shows Items.icon(\"corn_chowder\") (%s)"%label)
	check(icon.custom_minimum_size==Vector2(32,32),"Chowder icon slot is 32px (%s): %s"%[label,str(icon.custom_minimum_size)])
	var mine:=image_of(tex)
	check(mine!=null,"Chowder icon image readable (%s)"%label)
	for other:String in ["salad","soup","carrot_soup"]:
		var other_tex:Texture2D=Items.icon(other)
		check(other_tex!=tex,"Chowder icon is not the %s texture (%s)"%[other,label])
		var theirs:=image_of(other_tex)
		if theirs==null:
			note("icon(\"%s\") image unreadable headless; compared by reference only (%s)"%[other,label])
			continue
		var changed:=pixel_difference(mine,theirs)
		check(changed>=64,"Chowder icon differs pixel-wise from icon(\"%s\") (%s): %d pixels differ"%[other,label,changed])

# ------------------------------------------------------------------- layout --

## Page inside the viewport, no outer scrolling, every visible label / button / icon
## inside the page and whole, three dish rows whole and non-overlapping.
func layout_ok(label:String)->void:
	if not page_open():
		check(false,"Page open for layout: "+label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Page fits the viewport (%s) %s"%[label,rect_info(null)])
	var outer:=control("ModalScroll") as ScrollContainer
	check(outer!=null,"Outer scroll container found (%s)"%label)
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer page needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
		var content:=control("ModalContent")
		check(content!=null,"ModalContent found (%s)"%label)
		if content!=null:check(content.get_combined_minimum_size().y<=outer.size.y+1.0,"Content min height fits the scroll area (%s): %.0f <= %.0f"%[label,content.get_combined_minimum_size().y,outer.size.y])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the page (%s) %s"%[c.name,label,rect_info(c)])
		if outer!=null and outer.is_ancestor_of(c):check(outer.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the visible scroll area (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the page (%s)"%label)
	# Dish rows: each row as wide as its content, its controls inside it, rows stacked.
	var previous_bottom:=-INF
	for dish:String in UI.DISH_ORDER:
		var row:=control("Dish_"+dish)
		check(row!=null and row.is_visible_in_tree(),"Dish_%s shown (%s)"%[dish,label])
		if row==null:continue
		check(row.get_combined_minimum_size().x<=row.size.x+0.5,"Dish_%s not wider than the page (%s): %.0f > %.0f"%[dish,label,row.get_combined_minimum_size().x,row.size.x])
		if dish=="chowder":
			# Side by side with the watermelon row: same line, to its right, no overlap.
			var melon_row:=control("Dish_watermelon")
			if melon_row!=null:
				check(absf(row.get_global_rect().position.y-melon_row.get_global_rect().position.y)<=0.5 and row.get_global_rect().position.x>=melon_row.get_global_rect().end.x-0.5,"Dish_chowder on the watermelon line, to its right (%s): %s vs %s"%[label,str(row.get_global_rect()),str(melon_row.get_global_rect())])
		else:
			check(row.get_global_rect().position.y>=previous_bottom-0.5,"Dish_%s below the previous dish row (%s)"%[dish,label])
			previous_bottom=row.get_global_rect().end.y
		for part:String in ["DishIcon_","DishText_","DishMain_"]:
			var c:=control(part+dish)
			if c!=null and c.is_visible_in_tree():check(row.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s%s inside its row (%s) %s"%[part,dish,label,rect_info(c)])
		var text:=control("DishText_"+dish) as Label
		if text!=null:check(not_cut(text),"DishText_%s whole (%s): %s"%[dish,label,text.text])
	# The three main buttons: inside the modal, no overlap with each other or any dish text.
	var mains:Array=[]
	var dish_texts:Array=[]
	for dish:String in UI.DISH_ORDER:
		var b:=control("DishMain_"+dish)
		var t:=control("DishText_"+dish)
		check(b!=null and b.is_visible_in_tree(),"DishMain_%s shown (%s)"%[dish,label])
		if b!=null:
			check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"DishMain_%s inside the modal (%s) %s"%[dish,label,rect_info(b)])
			mains.append(b)
		if t!=null:dish_texts.append(t)
	for i in mains.size():
		var a:Control=mains[i]
		var ra:=a.get_global_rect().grow(-0.5)
		for j in range(i+1,mains.size()):
			var b:Control=mains[j]
			check(not ra.intersects(b.get_global_rect().grow(-0.5)),"%s does not overlap %s (%s) %s / %s"%[a.name,b.name,label,str(a.get_global_rect()),str(b.get_global_rect())])
		for t:Control in dish_texts:
			check(not ra.intersects(t.get_global_rect().grow(-0.5)),"%s does not overlap %s (%s) %s / %s"%[a.name,t.name,label,str(a.get_global_rect()),str(t.get_global_rect())])
	var warm:=control("HotpotWarm")
	if warm!=null and warm.is_visible_in_tree():
		for m:Control in mains:
			if m.name!="DishMain_hotpot":continue
			check(not m.get_global_rect().grow(-0.5).intersects(warm.get_global_rect().grow(-0.5)),"HotpotWarm does not overlap DishMain_hotpot (%s)"%label)
	# Cards still below the dishes, in order.
	var servings:=control("CommunityServings")
	var warmer:=control("WarmerCard")
	var tea:=control("TeaCard")
	check(warmer!=null and warmer.is_visible_in_tree(),"保溫底座 card shown (%s)"%label)
	check(tea!=null and tea.is_visible_in_tree(),"茶陶上桌 card shown (%s)"%label)
	if servings!=null and warmer!=null:check(servings.get_global_rect().end.y<=warmer.get_global_rect().position.y+0.5,"Dishes sit above the 保溫底座 card (%s)"%label)
	if warmer!=null and tea!=null:check(warmer.get_global_rect().end.y<=tea.get_global_rect().position.y+0.5,"茶陶上桌 card below the 保溫底座 card (%s)"%label)
	for route in ["渡口來信","生活訂單","風鈴接力","公共廚房"]:
		var found:=false
		for node in modal.find_children("*","Button",true,false):
			if (node as Button).text==route and (node as Control).is_visible_in_tree():found=true
		check(found,"Route %s still on the page (%s)"%[route,label])

func focus_ok(label:String)->void:
	var focus_owner:=root.gui_get_focus_owner()
	check(focus_owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(focus_owner) and focus_owner is BaseButton and focus_owner.is_visible_in_tree(),"Keyboard focus is on a visible button inside the page (%s): %s"%[label,focused_name()])

func expect_focus(node_name:String,label:String)->void:
	check(focused_name()==node_name,"Focus on %s (%s): %s"%[node_name,label,focused_name()])

## focus_rows has the chowder row between watermelon and the next row; neighbours match.
func neighbours_ok(below:String,label:String)->void:
	var melon:=row_index("DishMain_watermelon")
	var chowder:=row_index("DishMain_chowder")
	var after_row:=row_index(below)
	# 西瓜盤與玉米濃湯同一列（左、右）；上一列是火鍋列，下一列是 below 所在的列。
	check(melon>=1 and chowder==melon,"focus_rows: chowder shares the watermelon row (%s): %d / %d"%[label,melon,chowder])
	check(after_row==chowder+1,"focus_rows: %s row right after the chowder row (%s): %d / %d"%[below,label,chowder,after_row])
	var rows:Array=UI.focus_rows(app)
	if chowder<1 or chowder+1>=rows.size():return
	var row:Array=rows[chowder]
	check(row.size()==2 and str((row[0] as Button).name)=="DishMain_watermelon" and str((row[1] as Button).name)=="DishMain_chowder","Row is watermelon then chowder (%s)"%label)
	var above:Array=rows[chowder-1]
	var under:Array=rows[chowder+1]
	var want_top:String=str((above[mini(1,above.size()-1)] as Button).name)
	var want_bottom:String=str((under[mini(1,under.size()-1)] as Button).name)
	var b:=control("DishMain_chowder")
	if b==null:
		check(false,"DishMain_chowder found for neighbours (%s)"%label)
		return
	check(str((above[0] as Button).name)=="DishMain_hotpot","Row above is the hotpot row (%s)"%label)
	check(neighbor(b,b.focus_neighbor_top)==want_top,"DishMain_chowder up -> %s (%s): %s"%[want_top,label,neighbor(b,b.focus_neighbor_top)])
	check(neighbor(b,b.focus_neighbor_bottom)==want_bottom,"DishMain_chowder down -> %s (%s): %s"%[want_bottom,label,neighbor(b,b.focus_neighbor_bottom)])
	check(neighbor(b,b.focus_neighbor_left)=="DishMain_watermelon" and neighbor(b,b.focus_neighbor_right)=="DishMain_watermelon","DishMain_chowder left / right -> DishMain_watermelon (%s)"%label)
	var melon_b:=control("DishMain_watermelon")
	if melon_b!=null:
		check(neighbor(melon_b,melon_b.focus_neighbor_right)=="DishMain_chowder","DishMain_watermelon right -> DishMain_chowder (%s): %s"%[label,neighbor(melon_b,melon_b.focus_neighbor_right)])
		check(neighbor(melon_b,melon_b.focus_neighbor_bottom)==below,"DishMain_watermelon down -> %s (%s): %s"%[below,label,neighbor(melon_b,melon_b.focus_neighbor_bottom)])
	var below_b:=control(below)
	if below_b!=null:check(neighbor(below_b,below_b.focus_neighbor_top)=="DishMain_watermelon","%s up -> DishMain_watermelon (%s): %s"%[below,label,neighbor(below_b,below_b.focus_neighbor_top)])

# --------------------------------------------------------------------- flows --

func reset()->void:
	await close_page()
	w.state.erase("table_warmer")  # PRESET: un-installed 保溫底座
	w.state.erase(Tea.STATE_KEY)  # PRESET
	w.state.erase("tea_revisit")  # PRESET: revisit not done -> red NOT_DONE reason
	w.state.community={"table":World.COMMUNITY.cell_key(TABLE)}  # PRESET
	for item in [CHOWDER,"trout_hotpot","watermelon_platter","warm_stone","copper_joint","stone","tea_ware_kit","tea_light","tea_deep"]:bag()[item]=0  # PRESET
	(w.state.players[GUEST].inventory as Dictionary)[CHOWDER]=0  # PRESET
	presets+=6
	await refresh()

func size_flow(label:String)->void:
	await reset()
	check(World.COMMUNITY.table_cell(snap())==TABLE,"Table at (39,30) (%s)"%label)
	await stand(TABLE_SPOT)
	check(str(app.view.interaction_focus())=="community","Standing south of the table focuses it (%s): %s"%[label,str(app.view.interaction_focus())])
	# ---- A: nothing in the bag.
	await interact_key()
	check(page_open(),"E at the table opens 渡口的共餐桌 (%s): %s"%[label,texts().left(60).replace("\n"," | ")])
	if not page_open():return
	structure_ok(label)
	expect_chowder(UI.PLAIN_SERVE,false,SHORT_TIP,"玉米濃湯 · 還沒上桌・背包 0 份","bag 0 "+label)
	check(shown("WarmerMaterials") and shown("WarmerSource") and shown("WarmerReason"),"Un-installed 保溫底座 card shows materials, source and reason (%s)"%label)
	check(shown("TeaReason") and label_text("TeaReason")==Tea.NOT_DONE,"茶陶上桌 card shows the red NOT_DONE reason (%s): %s"%[label,label_text("TeaReason")])
	neighbours_ok("WarmerInstall","bag 0 "+label)
	check(preferred_name()=="Route_letter","preferred() falls to the routes with no enabled table action (%s): %s"%[label,preferred_name()])
	focus_ok("bag 0 "+label)
	layout_ok("bag 0 "+label)
	# ---- B: three in the bag, still short (updated in place).
	var first_ids:=node_ids()
	await set_bag({CHOWDER:3})
	expect_chowder(UI.PLAIN_SERVE,false,SHORT_TIP,"玉米濃湯 · 還沒上桌・背包 3 份","bag 3 "+label)
	check(node_ids()==first_ids,"Page updated in place for the bag change (%s): %s"%[label,diff(first_ids,node_ids())])
	# ---- C: four in the bag (PRESET); enabled; preferred() picks it.
	await set_bag({CHOWDER:4})
	expect_chowder(UI.PLAIN_SERVE,true,SERVE_TIP,"玉米濃湯 · 還沒上桌・背包 4 份","bag 4 "+label)
	check(preferred_name()=="DishMain_chowder","preferred() is DishMain_chowder when it is the only enabled table action (%s): %s"%[label,preferred_name()])
	layout_ok("bag 4 "+label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	await interact_key()
	check(page_open(),"Page reopens (%s)"%label)
	if not page_open():return
	expect_focus("DishMain_chowder","Focus starts on the chowder 上桌四份 "+label)
	var ids_before:=node_ids()
	var rest_before:=others()
	# ---- D: serve through the real button.
	if await press("DishMain_chowder","serve chowder "+label):
		check(chowder_state()=={"portions":4,"claimed":{}},"Server has a 4-portion chowder round (%s): %s"%[label,str(chowder_state())])
		check(held(CHOWDER)==0,"Four chowders left the bag (%s): %d"%[label,held(CHOWDER)])
		check(int(chowder_snap().get("portions",0))==4 and not chowder_snap().has("claimed") and chowder_snap().get("claimed_own",true)==false,"Snapshot: 4 portions, no claimed list, claimed_own false (%s): %s"%[label,str(chowder_snap())])
		check(page_open() and feedback().contains("玉米濃湯上桌了"),"Page stays open with the server reply (%s): %s"%[label,feedback()])
		expect_chowder(UI.CLAIM,true,CLAIM_TIP,"玉米濃湯 · 剩 4 / 4 份","served "+label)
		expect_focus("DishMain_chowder","Focus stays on the same button, now 領一份 "+label)
		check(preferred_name()=="DishMain_chowder","preferred() is the chowder 領一份 (%s): %s"%[label,preferred_name()])
		check(node_ids()==ids_before,"Modal not rebuilt by the serve (%s): %s"%[label,diff(ids_before,node_ids())])
		var rest_after:=others()
		check(rest_after==rest_before,"Serving chowder changes nothing else on the page (%s): %s"%[label,diff(rest_before,rest_after)])
		layout_ok("chowder served "+label)
	# ---- E: claim through the real button.
	rest_before=others()
	if await press("DishMain_chowder","claim chowder "+label):
		check(held(CHOWDER)==1,"Claim puts one chowder in the bag (%s): %d"%[label,held(CHOWDER)])
		check(int(chowder_state().get("portions",0))==3 and (chowder_state().get("claimed",{}) as Dictionary).has(id),"Server: 3 left, I am in claimed (%s): %s"%[label,str(chowder_state())])
		check(chowder_snap().get("claimed_own",false)==true and not chowder_snap().has("claimed"),"Snapshot: claimed_own true, no claimed list (%s): %s"%[label,str(chowder_snap())])
		check(feedback().contains("已領取一份玉米濃湯"),"Claim reply shown (%s): %s"%[label,feedback()])
		expect_chowder(UI.CLAIM,false,CLAIMED_TIP,"玉米濃湯 · 剩 3 / 4 份・你已領過","claimed "+label)
		expect_focus("DishMain_chowder","Focus stays on the now-disabled 領一份 "+label)
		focus_ok("claimed "+label)
		check(node_ids()==ids_before,"Modal not rebuilt by the claim (%s): %s"%[label,diff(ids_before,node_ids())])
		var rest_after:=others()
		check(rest_after==rest_before,"Claiming chowder changes nothing else on the page (%s): %s"%[label,diff(rest_before,rest_after)])
		check(preferred_name()=="Route_letter","preferred() leaves the claimed chowder (%s): %s"%[label,preferred_name()])
		layout_ok("chowder claimed "+label)
	# ---- F: all three dishes on the table; the other rows do not touch the chowder row.
	await set_bag({"trout_hotpot":4,"watermelon_platter":4,"warm_stone":2,"copper_joint":1,"stone":4})
	var chowder_line:=label_text("DishText_chowder")
	var chowder_button:="%s|%s"%[button("DishMain_chowder").text if button("DishMain_chowder")!=null else "missing",str(button("DishMain_chowder").disabled) if button("DishMain_chowder")!=null else "missing"]
	if await press("DishMain_hotpot","serve hotpot "+label):
		check(label_text("DishText_hotpot")==HOTPOT_FULL,"Hotpot row shows its own count (%s): %s"%[label,label_text("DishText_hotpot")])
		check(label_text("DishText_chowder")==chowder_line,"Hotpot serve leaves the chowder row (%s): %s"%[label,label_text("DishText_chowder")])
	if await press("DishMain_watermelon","serve watermelon "+label):
		check(label_text("DishText_watermelon")==MELON_FULL,"Watermelon row shows its own count (%s): %s"%[label,label_text("DishText_watermelon")])
		check(label_text("DishText_chowder")==chowder_line,"Watermelon serve leaves the chowder row (%s): %s"%[label,label_text("DishText_chowder")])
	var after_button:="%s|%s"%[button("DishMain_chowder").text if button("DishMain_chowder")!=null else "missing",str(button("DishMain_chowder").disabled) if button("DishMain_chowder")!=null else "missing"]
	check(after_button==chowder_button,"Chowder button untouched by the other dishes (%s): %s -> %s"%[label,chowder_button,after_button])
	check(label_text("DishText_hotpot")==HOTPOT_FULL and label_text("DishText_watermelon")==MELON_FULL and label_text("DishText_chowder")=="玉米濃湯 · 剩 3 / 4 份・你已領過","All three rows show their own counts (%s): %s / %s / %s"%[label,label_text("DishText_hotpot"),label_text("DishText_watermelon"),label_text("DishText_chowder")])
	text_matches("three dishes "+label)
	check(node_ids()==ids_before,"Modal still not rebuilt with three dishes (%s): %s"%[label,diff(ids_before,node_ids())])
	# Tallest state: un-installed card with materials, source and reason; tea red reason; three dishes.
	check(shown("WarmerMaterials") and shown("WarmerSource") and shown("WarmerReason") and label_text("WarmerReason")==Warmer.SHORT%"暖岩片 4、銅接頭 1","Tallest: 保溫底座 materials, source and shortfall shown (%s): %s"%[label,label_text("WarmerReason")])
	check(shown("TeaReason") and label_text("TeaReason")==Tea.NOT_DONE,"Tallest: tea red reason shown (%s)"%label)
	layout_ok("tallest: three dishes, un-installed warmer, tea reason "+label)
	neighbours_ok("WarmerInstall","three dishes "+label)
	# Real arrow keys around the chowder row.
	var chowder_b:=button("DishMain_chowder")
	if chowder_b!=null:
		chowder_b.grab_focus();await settle()
		await key(KEY_LEFT)
		expect_focus("DishMain_watermelon","KEY_LEFT from chowder to watermelon "+label)
		await key(KEY_RIGHT)
		expect_focus("DishMain_chowder","KEY_RIGHT back to chowder "+label)
		await key(KEY_DOWN)
		expect_focus("WarmerInstall","KEY_DOWN from the chowder row to 加裝保溫底座 "+label)
		await key(KEY_UP)
		expect_focus("DishMain_watermelon","KEY_UP from 加裝保溫底座 to the watermelon / chowder row "+label)
	# Claiming the watermelon leaves the chowder row alone.
	var rest_chowder:="%s|%s"%[label_text("DishText_chowder"),after_button]
	if await press("DishMain_watermelon","claim watermelon "+label):
		var b:=button("DishMain_chowder")
		var now:="%s|%s"%[label_text("DishText_chowder"),("%s|%s"%[b.text,str(b.disabled)]) if b!=null else "missing|missing"]
		check(now==rest_chowder,"Watermelon claim leaves the chowder row (%s): %s -> %s"%[label,rest_chowder,now])
	# Installed 保溫底座: chowder's down neighbour moves to the next row (PRESET install).
	w.state.table_warmer={"installed":true}  # PRESET
	presets+=1
	await refresh()
	check(not shown("WarmerInstall"),"加裝保溫底座 hidden once installed (%s)"%label)
	neighbours_ok("Route_letter","installed "+label)
	layout_ok("installed, three dishes "+label)
	w.state.erase("table_warmer")  # PRESET
	presets+=1
	await refresh()
	check(shown("WarmerInstall"),"加裝保溫底座 back after the un-install (%s)"%label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)
	# ---- G: another islander serves; my page offers 領一份 and never borrows their claim.
	w.state.community.erase("chowder")  # PRESET: clear my round
	presets+=1
	(w.state.players[GUEST].inventory as Dictionary)[CHOWDER]=4  # PRESET
	presets+=1
	var mine_held:=held(CHOWDER)
	await interact_key()
	check(page_open(),"Page opens before the islander serves (%s)"%label)
	if not page_open():return
	expect_chowder(UI.PLAIN_SERVE,false,SHORT_TIP,"玉米濃湯 · 還沒上桌・背包 %d 份"%mine_held,"before the islander serves "+label)
	var guest_ids:=node_ids()
	guest_act("serve_chowder")
	await refresh()
	check(chowder_state()=={"portions":4,"claimed":{}},"Islander served a round of four (%s): %s"%[label,str(chowder_state())])
	check(page_open() and node_ids()==guest_ids,"Page updated in place by the islander's serve (%s): %s"%[label,diff(guest_ids,node_ids())])
	expect_chowder(UI.CLAIM,true,CLAIM_TIP,"玉米濃湯 · 剩 4 / 4 份","islander served "+label)
	guest_act("claim_chowder")
	await refresh()
	check(not chowder_snap().has("claimed") and chowder_snap().get("claimed_own",true)==false,"Snapshot hides the islander's claim, claimed_own false for me (%s): %s"%[label,str(chowder_snap())])
	expect_chowder(UI.CLAIM,true,CLAIM_TIP,"玉米濃湯 · 剩 3 / 4 份","islander claimed "+label)
	check(not label_text("DishText_chowder").contains("你已領過"),"The islander's claim does not show as mine (%s)"%label)
	layout_ok("islander's round "+label)
	if await press("DishMain_chowder","claim islander's round "+label):
		check(held(CHOWDER)==mine_held+1,"My claim adds one chowder (%s): %d"%[label,held(CHOWDER)])
		var claimed:Dictionary=chowder_state().get("claimed",{})
		check(int(chowder_state().get("portions",0))==2 and claimed.has(id) and claimed.has(GUEST) and claimed.size()==2,"Server: 2 left, both of us claimed (%s): %s"%[label,str(chowder_state())])
		expect_chowder(UI.CLAIM,false,CLAIMED_TIP,"玉米濃湯 · 剩 2 / 4 份・你已領過","both claimed "+label)
	await key(KEY_ESCAPE)
	check(not page_open(),"Esc closes the page (%s)"%label)

func run()->void:
	create_timer(240.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 240 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("corn-chowder-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.bindings.load_preferences(path+".bindings")
	if app.session.host(0,"濃湯旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	w.state.board=true  # PRESET
	w.state.picnic=true  # PRESET
	w.add_player(GUEST,"濃湯客")  # FIXTURE islander
	presets+=3
	await refresh()
	if WanganUI.card_open(app):
		await key(KEY_E)
		check(not WanganUI.card_open(app),"First E closes the arrival card")
	check(str(World.NAMES.get(CHOWDER,""))=="玉米濃湯","World.NAMES corn_chowder is 玉米濃湯")
	check(World.COMMUNITY.ACTIONS.has("serve_chowder") and World.COMMUNITY.ACTIONS.has("claim_chowder"),"serve_chowder / claim_chowder are community actions")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await size_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock",".bindings"]:DirAccess.remove_absolute(path+suffix)
	finish()
