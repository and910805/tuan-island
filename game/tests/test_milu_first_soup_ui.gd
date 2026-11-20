extends SceneTree
## T066 N02-1 米露〈忘記吃飯的人〉: the illustrated 熱蘿蔔湯 recipe note, end to end through the real UI and the real cooking pipeline.
## Native Windows graphical smoke test (screenshots are skipped when headless).
## Optional user arg: --capture-dir=DIR  (PNG evidence at 1024x640 and 1280x800).
##
## Contract assumed (Codex adjusts names locally if the UI differs; see the final report):
##  * story page Tasks.bond_goal(app,"milu",1) has a Button "MiluFirstSoupEntry" while the event is open AND done, never while locked;
##  * the entry opens a note node "MiluFirstSoup" with an illustration node "MiluFirstSoupArt", the real recipe
##    (name, ingredients, seconds, yield read from World.RECIPES.soup) and the small-stove and public-kitchen introductions;
##  * while the event is open the note gives beginner help: radish x2, wait, claim (visible text);
##  * buttons open the existing stove builder or reachable stove, open the public kitchen page, and return to the story;
##  * the island journal has a Button "MiluFirstSoupBookmark" that reopens the note once the event is done
##    (absent or disabled before that);
##  * no rule, cost, economy or save field changes: opening anything here moves no item, coin, object or progress.
## The soup is made only by the existing actions: `build` stove, `queue_cook` / `claim_cook` (and the old `cook` on a plain stove in a
## second isolated world), then the existing BondGoalDo button serves one bowl. Fixture writes: friendship points, picnic flag,
## and top-ups of radish / wood / stone only if the bag is short. Nothing writes soup, stove, goal or recipe state.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Bond:=World.RESIDENT_BOND
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

const RESIDENT:="milu"
const STAGE:=1
const ENTRY:="MiluFirstSoupEntry"
const PAGE:="MiluFirstSoup"
const ART:="MiluFirstSoupArt"
const STOVE_BTN:="MiluFirstSoupBuildStove"
const KITCHEN_BTN:="MiluFirstSoupKitchenPage"
const BACK_BTN:="MiluFirstSoupBack"
const BOOKMARK:="MiluFirstSoupBookmark"
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
const SPOT:=Vector2i(38,34)
## Independent copies of the published numbers: the test fails if the game's rules drift.
const SOUP_RULE:={"name":"熱蘿蔔湯","ingredients":{"radish":2},"time":10.0,"yield":2}
const STOVE_COST:={"wood":12,"stone":15}

var app
var world:World
var token:String
var person:Dictionary
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func node(id:String) -> Node:
	if not is_instance_valid(app.modal):return null
	return app.modal if str(app.modal.name)==id else app.modal.find_child(id,true,false)

func button(id:String) -> Button:
	return node(id) as Button

func settle() -> void:
	for i in 3:await process_frame

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:target.pressed.emit()
	await settle()

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func resize(size:Vector2i) -> void:
	root.size=size
	await settle()

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in root_node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree() and not (candidate as Label).text.strip_edges().is_empty():lines.append((candidate as Label).text)
	for candidate:Node in root_node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree() and not (candidate as RichTextLabel).get_parsed_text().strip_edges().is_empty():lines.append((candidate as RichTextLabel).get_parsed_text())
	for candidate:Node in root_node.find_children("*","Button",true,false):
		if (candidate as Button).is_visible_in_tree() and not (candidate as Button).text.strip_edges().is_empty():lines.append((candidate as Button).text)
	return "\n".join(lines)

func goal_done() -> bool:
	return Goals.done(person,RESIDENT).has(STAGE)

func soup() -> int:
	return int(person.inventory.get("soup",0))

func radish() -> int:
	return int(person.inventory.get("radish",0))

func stove_cells(w:World) -> Array:
	var out:=[]
	for key:Variant in w.state.objects:
		var item:Variant=w.state.objects[key]
		if item is Dictionary and str(item.get("type",""))=="stove":out.append(key)
	return out

func snapshot_state() -> Dictionary:
	return {"inv":person.inventory.duplicate(true),"objects":world.state.objects.duplicate(true),"goals":person.get(Goals.RECORD_KEY,{}).duplicate(true),"coins":int(person.get("coins",0)),"bonds":person.get("bonds",{}).duplicate(true)}

## Same fit rule the other story pages use: nothing clipped, squeezed or off screen.
func check_fit(tag:String) -> void:
	expect(is_instance_valid(app.modal),"A page is open ("+tag+")")
	if not is_instance_valid(app.modal):return
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(screen.encloses(app.modal.get_global_rect()),"Panel stays inside the window ("+tag+")")
	var scroll:=node("ModalScroll") as ScrollContainer
	if scroll!=null:
		expect(not scroll.get_h_scroll_bar().visible,"No sideways scrolling ("+tag+")")
		expect(not scroll.get_v_scroll_bar().visible,"No vertical clipping or scrolling ("+tag+")")
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if not label.is_visible_in_tree() or label.text.strip_edges().is_empty():continue
		expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(12)])
		expect(label.get_visible_line_count()>=label.get_line_count(),"Text is not truncated (%s): %s"%[tag,label.text.left(12)])
		expect(screen.encloses(label.get_global_rect()),"Text is on screen (%s): %s"%[tag,label.text.left(12)])
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		var target:=candidate as Button
		if not target.is_visible_in_tree():continue
		expect(target.size.x+1.0>=target.get_combined_minimum_size().x and target.size.y+1.0>=target.get_combined_minimum_size().y,"Button is not squeezed (%s): %s"%[tag,str(target.name)])
		expect(screen.encloses(target.get_global_rect()),"Button is on screen (%s): %s"%[tag,str(target.name)])

func entry_present() -> bool:
	return button(ENTRY)!=null

func open_story(tag:="") -> void:
	app._close_modal()
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(node("BondGoalTitle")!=null,"Story page is open "+tag)

## The note must show the REAL recipe (read from the game's own table, which is also pinned to the published numbers).
func check_note(tag:String,beginner:bool) -> void:
	var page:=node(PAGE)
	expect(page!=null and page.is_visible_in_tree(),"The recipe note is open ("+tag+")")
	if page==null:return
	var art:=node(ART) as Control
	expect(art!=null and art.is_visible_in_tree(),"The note carries an illustration ("+tag+")")
	if art!=null:
		var box:=art.get_global_rect()
		expect(box.size.x>=160.0 and box.size.y>=80.0,"The illustration is big enough to read ("+tag+")")
	var text:=visible_text(page)
	var recipe:Dictionary=World.RECIPES.soup
	expect(text.contains(str(recipe.name)),"Note names the dish: "+str(recipe.name)+" ("+tag+")")
	for item:String in recipe.ingredients:
		expect(text.contains(str(World.NAMES.get(item,item))),"Note names the ingredient "+item+" ("+tag+")")
		expect(text.contains(str(int(recipe.ingredients[item]))),"Note shows the amount ("+tag+")")
	expect(text.contains("%d"%int(recipe.time)),"Note shows the cooking seconds ("+tag+")")
	expect(text.contains(str(int(recipe.yield))),"Note shows the yield ("+tag+")")
	expect(text.contains(str(World.BUILD.stove.name)),"Note introduces the 小石灶 ("+tag+")")
	expect(text.contains("公共廚房"),"Note introduces the 公共廚房 ("+tag+")")
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders ("+tag+")")
	if beginner:
		expect(text.contains("等") and text.contains("領"),"Beginner help says wait, then claim ("+tag+")")
	else:
		expect(not text.contains("要交"),"The completed note no longer asks for delivery ("+tag+")")
	var stove_button:=button(STOVE_BTN)
	if stove_button==null:stove_button=button("MiluFirstSoupUseStove")
	var kitchen_button:=button(KITCHEN_BTN)
	var back:=button(BACK_BTN)
	for pair:Array in [[stove_button,STOVE_BTN],[kitchen_button,KITCHEN_BTN],[back,BACK_BTN]]:
		var target:=pair[0] as Button
		expect(target!=null and target.is_visible_in_tree() and not target.disabled,"Enabled direct route: "+str(pair[1])+" ("+tag+")")
		if target!=null:
			var rect:=target.get_global_rect()
			expect(rect.size.x>=44.0 and rect.size.y>=32.0,"Comfortable target %s (%s)"%[pair[1],tag])
	expect(button("BondGoalClaim")==null,"The note offers no claim or payment ("+tag+")")
	check_fit(tag)

func check_recipe_rule() -> void:
	var recipe:Dictionary=World.RECIPES.soup
	expect(str(recipe.name)==SOUP_RULE.name and recipe.ingredients==SOUP_RULE.ingredients and float(recipe.time)==SOUP_RULE.time and int(recipe.yield)==SOUP_RULE.yield,"Soup recipe unchanged")
	for item:String in STOVE_COST:expect(int(World.BUILD.stove.get(item,0))==int(STOVE_COST[item]),"Stove cost unchanged: "+item)
	expect(World.stove_recipes("stove").has("soup"),"The small stove cooks the soup")
	expect(not Goals.goal(RESIDENT,STAGE).has("needs") and Goals.goal(RESIDENT,STAGE).items=={"soup":1},"Event still costs exactly one soup")

func perform(action:String,cell:Vector2i,extra:="") -> void:
	app.session.rates[1].clear()
	app.session.perform(action,cell,extra)
	await settle()

func direct(w:World,tok:String,action:String,cell:Vector2i,extra:="") -> Dictionary:
	serial+=1
	return w.act(tok,"milu-soup-%d"%serial,action,cell,extra)

func top_up(w:World,tok:String,item:String,amount:int) -> void:
	var inv:Dictionary=w.state.players[tok].inventory
	if int(inv.get(item,0))<amount:inv[item]=amount

## Old flow in an isolated world: a plain stove with the legacy `cook` job and no public kitchen at all.
func old_stove_flow() -> void:
	var old:=World.new()
	old.add_player("old-stove","老灶島民")
	var owner:Dictionary=old.state.players["old-stove"]
	old.state.picnic=true
	owner.bonds={RESIDENT:{"points":int(Bond.THRESHOLDS[0]),"talk_day":-1,"gift_day":-1}}
	owner.region=World.REGIONS.HOME
	expect(not old.state.has("public_kitchen") or str(old.state.public_kitchen.get("stove","")).is_empty(),"Old world has no public kitchen")
	owner.inventory.erase("soup")
	for item:String in STOVE_COST:top_up(old,"old-stove",item,int(STOVE_COST[item]))
	top_up(old,"old-stove","radish",2)
	owner.x=SPOT.x+0.5
	owner.y=SPOT.y+1.5
	var missing:=direct(old,"old-stove","cook",SPOT,"soup")
	expect(not missing.ok and owner.inventory.get("soup",0)==0 and stove_cells(old).is_empty(),"Old world: no stove means no soup and no progress")
	expect(direct(old,"old-stove","build",SPOT,"stove").ok and stove_cells(old).size()==1,"Old world: the stove is built by the normal action")
	var radish_before:=int(owner.inventory.radish)
	expect(direct(old,"old-stove","cook",SPOT,"soup").ok and int(owner.inventory.radish)==radish_before-2,"Old stove cooks through the legacy job and takes 2 radish")
	expect(not direct(old,"old-stove","claim_cook",SPOT).ok,"Old stove does not hand over before the time")
	expect(old.step(float(World.RECIPES.soup.time)+0.5,true,false),"Old world time passes")
	expect(direct(old,"old-stove","claim_cook",SPOT).ok and int(owner.inventory.get("soup",0))==2,"Old stove hands over exactly 2 soups")
	var milu:Vector2i=World.bond_place(old.state,RESIDENT)[1]
	owner.x=milu.x+0.5
	owner.y=milu.y+0.5
	expect(direct(old,"old-stove",Goals.ACTION,milu,"%s:%d::"%[RESIDENT,STAGE]).ok and int(owner.inventory.get("soup",0))==1 and Goals.done(owner,RESIDENT).has(STAGE),"Old world: one soup finishes the event and one is left")

func run() -> void:
	root.size=SIZES[0]
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	path="user://milu-first-soup-%d.json"%OS.get_process_id()
	if app.session.host(0,"小湯島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	person.region=World.REGIONS.HOME
	world.state.picnic=true
	check_recipe_rule()
	var milu:Vector2i=World.bond_place(world.state,RESIDENT)[1]
	var kit_before:=int(person.inventory.get(Goals.keepsake_item(Goals.keepsake_kind(RESIDENT,STAGE)),0))
	expect(not world.state.get("public_kitchen",{}).get("opened",false),"The public kitchen is not open: this island is played without it")

	# ---- Locked (no friendship): no entry.
	person.bonds={}
	person.inventory.erase("soup")
	stand(milu)
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(not entry_present() and node(PAGE)==null,"No entry while the event is locked")

	# ---- Open (friendship, no soup, no stove): entry, note, direct routes, and no progress.
	person.bonds={RESIDENT:{"points":int(Bond.THRESHOLDS[0]),"talk_day":-1,"gift_day":-1}}
	stand(milu)
	expect(Bond.stage(person,RESIDENT)==STAGE,"Fixture friendship reaches the first stage")
	await open_story("open")
	expect(node("BondGoalDone")==null and entry_present(),"The open event shows the recipe entry")
	var serve:=button("BondGoalDo")
	expect(serve!=null and serve.disabled,"Serving is closed without a soup")
	expect(not world.act(token,"no-soup",Goals.ACTION,milu,"%s:%d::"%[RESIDENT,STAGE]).ok and not goal_done() and not person.has(Goals.RECORD_KEY),"No soup means no progress")
	var untouched:=snapshot_state()
	for size:Vector2i in SIZES:
		var tag:="open %dx%d"%[size.x,size.y]
		await resize(size)
		await open_story(tag)
		check_fit("story "+tag)
		await capture("01-open-entry-%dx%d.png"%[size.x,size.y])
		await press(ENTRY)
		check_note(tag,true)
		await capture("02-open-note-%dx%d.png"%[size.x,size.y])
		expect(snapshot_state()==untouched,"Reading the note moves no item, object, coin or progress ("+tag+")")
		await press(BACK_BTN)
		expect(node("BondGoalTitle")!=null and node(PAGE)==null,"Back returns to the story page ("+tag+")")
		await press(ENTRY)
		await press(STOVE_BTN)
		var folio:=node("BuildFolio")
		expect(folio!=null,"The stove route opens the existing build folio ("+tag+")")
		var title:=node("BuildTitle") as Label
		expect(title!=null and title.text.contains(str(World.BUILD.stove.name)),"The folio is on the 小石灶 ("+tag+")")
		var chosen:=0
		for candidate:Node in app.modal.find_children("BuildSlot_stove_*","Button",true,false):
			if (candidate as Button).button_pressed and (candidate as Button).is_visible_in_tree():chosen+=1
		expect(chosen==1,"Only the stove slot is selected ("+tag+")")
		await capture("03-stove-folio-%dx%d.png"%[size.x,size.y])
		expect(snapshot_state()==untouched,"The stove route builds and spends nothing ("+tag+")")
		await open_story(tag)
		await press(ENTRY)
		await press(KITCHEN_BTN)
		expect(is_instance_valid(app.modal) and (str(app.modal.name)=="PublicKitchenUI" or node("PublicKitchenUI")!=null),"The kitchen route opens the existing public kitchen ("+tag+")")
		check_fit("kitchen "+tag)
		await capture("04-kitchen-%dx%d.png"%[size.x,size.y])
		expect(snapshot_state()==untouched,"Visiting the kitchen changes nothing ("+tag+")")
	expect(not world.state.get("public_kitchen",{}).get("opened",false),"Reading the note did not open the public kitchen")
	await resize(SIZES[0])

	# ---- Missing stove: the real cook action refuses and nothing moves.
	for item:String in STOVE_COST:top_up(world,token,item,int(STOVE_COST[item]))
	top_up(world,token,"radish",2)
	app.session._send_snapshot(1)
	stand(SPOT+Vector2i(0,1))
	var bag_before:Dictionary=person.inventory.duplicate(true)
	expect(stove_cells(world).is_empty(),"No stove stands yet")
	var no_stove:=world.act(token,"no-stove","queue_cook",SPOT,"soup")
	expect(not no_stove.ok and person.inventory==bag_before and stove_cells(world).is_empty(),"Cooking without a stove is refused and spends nothing")

	# ---- Build the stove through the normal action, then queue, wait and claim through the normal pipeline.
	var wood0:=int(person.inventory.wood)
	var stone0:=int(person.inventory.stone)
	app._close_modal()
	app._perform_build_action("build",SPOT,"stove")
	await settle()
	expect(stove_cells(world).size()==1 and int(person.inventory.wood)==wood0-int(STOVE_COST.wood) and int(person.inventory.stone)==stone0-int(STOVE_COST.stone),"A normal stove is built at the normal cost")
	await open_story("beside the new stove")
	await press(ENTRY)
	await press("MiluFirstSoupUseStove")
	expect(is_instance_valid(app.modal) and visible_text(app.modal).contains(str(World.RECIPES.soup.name)),"The nearby stove shortcut opens its actual cooking menu")
	app._close_modal()
	var radish0:=radish()
	await perform("queue_cook",SPOT,"soup")
	expect(radish()==radish0-2 and soup()==0,"Queueing takes exactly 2 radish and gives nothing yet")
	await perform("claim_cook",SPOT)
	expect(soup()==0,"Claiming too early hands over nothing")
	expect(world.step(float(World.RECIPES.soup.time)+0.5,true,false),"World time passes")
	app.session._send_snapshot(1)
	await perform("claim_cook",SPOT)
	expect(soup()==int(World.RECIPES.soup.yield) and soup()==2,"Claiming physically puts 2 soups in the bag")
	expect(not goal_done() and Goals.completed(person)==0,"Cooking alone completes nothing")
	milu=World.bond_place(world.state,RESIDENT)[1]
	stand(milu)
	await open_story("with soup")
	var ready:=button("BondGoalDo")
	expect(ready!=null and not ready.disabled and entry_present(),"With soup the event is ready and the note is still one tap away")
	await capture("05-ready-%dx%d.png"%[root.size.x,root.size.y])

	# ---- Serve exactly one bowl through the existing goal button.
	var before_serve:=snapshot_state()
	await press("BondGoalDo")
	expect(goal_done() and app.session.snapshot.resident_goals[RESIDENT][str(STAGE)].state=="done","The existing goal accepts the soup")
	expect(soup()==1 and int(person.coins)==int(before_serve.coins),"One bowl is served, one stays, no coins move")
	expect(Goals.done(person,RESIDENT).size()==1,"Only the first event is recorded")
	var kit:=Goals.keepsake_item(Goals.keepsake_kind(RESIDENT,STAGE))
	expect(kit.is_empty() or int(person.inventory.get(kit,0))==kit_before,"No new reward item was invented")
	var repopulated:=entry_present()
	if not repopulated:await open_story("after reopen")
	expect(entry_present(),"The entry stays after completion (%s)"%("live" if repopulated else "reopen"))
	expect(not world.act(token,"repeat-serve",Goals.ACTION,milu,"%s:%d::"%[RESIDENT,STAGE]).ok and soup()==1,"The event cannot be served twice")

	# ---- Completed note at both sizes, and from the journal.
	var done_state:=snapshot_state()
	for size:Vector2i in SIZES:
		var tag:="done %dx%d"%[size.x,size.y]
		await resize(size)
		await open_story(tag)
		expect(node("BondGoalDone")!=null and button("BondGoalDo")==null,"Completed story page ("+tag+")")
		var opener:=button(ENTRY)
		expect(opener!=null and opener.is_visible_in_tree() and not opener.disabled,"Completed story shows an enabled entry ("+tag+")")
		check_fit("completed story "+tag)
		await capture("06-done-entry-%dx%d.png"%[size.x,size.y])
		await press(ENTRY)
		check_note(tag,false)
		var scene:=node(ART)
		expect(scene!=null and scene.is_processing(),"The completed vignette starts playing ("+tag+")")
		await create_timer(2.1).timeout
		expect(scene!=null and not scene.is_processing(),"The completed vignette settles ("+tag+")")
		await capture("07-done-note-%dx%d.png"%[size.x,size.y])
		await press("MiluFirstSoupReplay")
		expect(scene!=null and scene.is_processing(),"The replay button starts the animation again ("+tag+")")
		expect(snapshot_state()==done_state,"Reopening the note changes nothing ("+tag+")")
	app._close_modal()
	Tasks.journal(app)
	await settle()
	var bookmark:=button(BOOKMARK)
	expect(bookmark!=null and bookmark.is_visible_in_tree() and not bookmark.disabled,"The journal offers the recipe bookmark after completion")
	await press(BOOKMARK)
	check_note("journal",false)
	expect(snapshot_state()==done_state,"The journal route changes nothing")
	app._close_modal()
	app.sound.reduced_motion=true
	await open_story("reduced motion")
	await press(ENTRY)
	var still:=node(ART)
	expect(still!=null and not still.is_processing() and button("MiluFirstSoupReplay")==null,"Reduced motion renders the settled scene without playing")
	await capture("09-reduced-motion.png")

	# ---- Save and reload: progress, bag and the note all survive.
	app._close_modal()
	expect(app.session.shutdown(),"Save and close the island")
	app.sound.close()
	app.queue_free()
	await settle()
	await resize(SIZES[0])
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	expect(app.session.host(0,"小湯島民",path)==OK,"Reopen the saved island")
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	expect(world.state.players.has(token),"The saved player is found after reopening")
	person=world.state.players.get(token,{})
	if person.is_empty():
		quit(1)
		return
	person.region=World.REGIONS.HOME
	stand(milu)
	expect(goal_done() and soup()==1 and stove_cells(world).size()==1,"Completed event, remaining bowl and stove survive the reload")
	done_state=snapshot_state()
	for size:Vector2i in SIZES:
		var tag:="reloaded %dx%d"%[size.x,size.y]
		await resize(size)
		await open_story(tag)
		expect(entry_present(),"The entry survives the reload ("+tag+")")
		await press(ENTRY)
		check_note(tag,false)
		await capture("08-reloaded-note-%dx%d.png"%[size.x,size.y])
	app._close_modal()
	Tasks.journal(app)
	await settle()
	await press(BOOKMARK)
	check_note("reloaded journal",false)
	expect(snapshot_state()==done_state,"Reading after reload changes nothing")
	check_recipe_rule()
	expect(not world.state.get("public_kitchen",{}).get("opened",false),"The whole flow never needed the public kitchen")

	# ---- The old plain-stove flow, in its own world.
	old_stove_flow()

	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MILU_FIRST_SOUP_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
