extends SceneTree
## T066 N02-3 米露〈不是同一道湯〉: the small tasting, end to end through the real UI and the real cooking pipeline.
## Native Windows graphical render suite (screenshots are skipped when headless; headless is reported in the pass line).
## Optional user arg: --capture-dir=DIR  (PNG evidence: ready / tasting / done / reduced motion, at 1024x640 and 1280x800).
##
## Matrix: dish (soup, carrot_soup) x size (1024x640, 1280x800); every cell is its own isolated save and its own app.
## Every cell runs the live flow and a second, legacy flow (a goal finished before keepsakes existed).
##
## Contract assumed (Codex adjusts names locally if the UI differs; see the final report):
##  * story page Tasks.bond_goal(app,"milu",3) offers BondGoalOption_soup / BondGoalOption_carrot_soup and BondGoalDo;
##  * after the authoritative success the panel "MiluTasting" opens with art "MiluTastingScene" (its `dish` is the picked dish),
##    a label "MiluTastingDish" carrying the real recipe name, an optional button "MiluTastingReplay" (never with reduced
##    motion; the art is then already settled) and a button "MiluTastingBack";
##  * the completed story page (BondGoalDone) has a button "MiluTastingMemory" that reopens the panel with the SAVED dish,
##    and its back returns to that page; the island journal has "MiluTastingBookmark" once the event is done (absent before);
##  * no rule, cost, economy or save field changes: opening any of it moves no item, coin, object or progress.
## Soup is made only by the existing actions: `build` stove, `queue_cook`, `claim_cook`; the real BondGoalDo
## then pays exactly two. Fixture writes: friendship points, picnic flag, top-ups of wood / stone / radish / carrot only
## if the bag is short, and (legacy flow only) the done record WITHOUT bond_keepsakes. Nothing writes a finished soup.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Bond:=World.RESIDENT_BOND
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

const RESIDENT:="milu"
const STAGE:=3
const PANEL:="MiluTasting"
const SCENE:="MiluTastingScene"
const DISH_LABEL:="MiluTastingDish"
const REPLAY:="MiluTastingReplay"
const BACK:="MiluTastingBack"
const MEMORY:="MiluTastingMemory"
const BOOKMARK:="MiluTastingBookmark"
const DISHES:=["soup","forest_mushroom_soup","carrot_soup"]
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
const SPOT:=Vector2i(38,34)
const PLACE_CELLS:=[Vector2i(42,34),Vector2i(43,36),Vector2i(44,34),Vector2i(41,37),Vector2i(45,36)]
const SETTLE_SECONDS:=3.1
## Independent copies of the published numbers: the test fails if the game's rules drift.
const RULES:={
	"soup":{"name":"熱蘿蔔湯","ingredients":{"radish":2},"time":10.0,"yield":2},
	"forest_mushroom_soup":{"name":"森林菇湯","ingredients":{"star_mushroom":2,"chime_herb":1},"time":60.0,"yield":2},
	"carrot_soup":{"name":"胡蘿蔔濃湯","ingredients":{"carrot":2},"time":15.0,"yield":2},
}
const STOVE_COST:={"wood":12,"stone":15}
const KITCHEN_COST:={"wood":12,"stone":20,"clay":5}

var app
var world:World
var token:String
var person:Dictionary
var path:String
var checks:=0
var failures:=0
var serial:=0
var captured:Array=[]

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func rates_clear() -> void:
	app.session.rates[1].clear()

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	rates_clear()
	app.session._send_snapshot(1)

func node(id:String) -> Node:
	if not is_instance_valid(app.modal):return null
	return app.modal if str(app.modal.name)==id else app.modal.find_child(id,true,false)

func button(id:String) -> Button:
	return node(id) as Button

func settle() -> void:
	for i in 3:await process_frame

func wait_for(id:String,frames:=90) -> Node:
	for i in frames:
		if node(id)!=null:break
		await process_frame
	await settle()
	return node(id)

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:
		rates_clear()
		target.pressed.emit()
	await settle()

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)
		captured.append(file_name)

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

func count(item:String) -> int:
	return int(person.inventory.get(item,0))

func goal_done() -> bool:
	return Goals.done(person,RESIDENT).has(STAGE)

func picked() -> String:
	return str(Goals.done(person,RESIDENT).get(STAGE,""))

func other(dish:String) -> String:
	return "carrot_soup" if dish=="soup" else "soup"

func objects_of(kind:String) -> Array:
	var out:Array=[]
	for key:Variant in world.state.objects:
		var item:Variant=world.state.objects[key]
		if item is Dictionary and str(item.get("type",""))==kind:out.append(key)
	return out

func snapshot_state() -> Dictionary:
	return {"inv":person.inventory.duplicate(true),"objects":world.state.objects.duplicate(true),"goals":person.get(Goals.RECORD_KEY,{}).duplicate(true),"keeps":person.get(Goals.KEEPSAKE_KEY,{}).duplicate(true),"coins":int(person.get("coins",0)),"bonds":person.get("bonds",{}).duplicate(true)}

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

func open_story(tag:="") -> void:
	app._close_modal()
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(node("BondGoalTitle")!=null,"Story page is open "+tag)

## The tasting panel: real recipe name, the picked dish on the art, one way back, and a replay only while motion is allowed.
func check_panel(tag:String,dish:String,reduced:bool) -> void:
	var page:=node(PANEL)
	expect(page!=null and page.is_visible_in_tree(),"The tasting panel is open ("+tag+")")
	if page==null:return
	var art:=node(SCENE) as Control
	expect(art!=null and art.is_visible_in_tree(),"The panel carries the tasting art ("+tag+")")
	if art!=null:
		var box:=art.get_global_rect()
		expect(box.size.x>=319.0 and box.size.y>=143.0,"The art is big enough to read ("+tag+")")
		expect(str(art.get("dish"))==dish,"The art shows the picked dish ("+tag+")")
		expect(bool(art.get("reduced_motion"))==reduced,"The art follows the reduced motion setting ("+tag+")")
	var label:=node(DISH_LABEL) as Label
	var recipe:Dictionary=World.RECIPES[dish]
	var other_recipe:Dictionary=World.RECIPES[other(dish)]
	expect(label!=null and label.is_visible_in_tree(),"The dish label is visible ("+tag+")")
	if label!=null:
		expect(label.text.contains(str(recipe.name)),"The label carries the real dish name %s ("%str(recipe.name)+tag+")")
		expect(not label.text.contains(str(other_recipe.name)),"The label does not name the other dish ("+tag+")")
	var text:=visible_text(page)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{") and not text.contains(dish),"No raw placeholders or ids ("+tag+")")
	var back:=button(BACK)
	expect(back!=null and back.is_visible_in_tree() and not back.disabled,"One enabled way back ("+tag+")")
	if back!=null:
		var rect:=back.get_global_rect()
		expect(rect.size.x>=44.0 and rect.size.y>=32.0,"Comfortable back target ("+tag+")")
	var replay:=button(REPLAY)
	if reduced:
		expect(replay==null,"Reduced motion offers no replay ("+tag+")")
		expect(art!=null and not art.is_processing() and bool(art.call("is_finished")),"Reduced motion shows the settled art at once ("+tag+")")
	elif replay!=null:
		expect(replay.is_visible_in_tree() and not replay.disabled,"Replay is usable when offered ("+tag+")")
	expect(button("BondGoalDo")==null and button("BondGoalClaim")==null,"The panel offers no payment or claim ("+tag+")")
	check_fit(tag)

func check_recipe_rule(dish:String) -> void:
	var rule:Dictionary=RULES[dish]
	var recipe:Dictionary=World.RECIPES[dish]
	expect(str(recipe.name)==str(rule.name) and recipe.ingredients==rule.ingredients and float(recipe.time)==float(rule.time) and int(recipe.yield)==int(rule.yield),"Recipe unchanged: "+dish)
	for item:String in STOVE_COST:expect(int(World.BUILD.stove.get(item,0))==int(STOVE_COST[item]),"Stove cost unchanged: "+item)
	expect(World.stove_recipes("stove").has(dish)==(dish!=World.FOREST_MUSHROOM.DISH),"Forest soup keeps its existing stove requirement")
	expect(World.stove_recipes(World.KITCHEN_STOVE.KIND).has(dish),"The kitchen stove supports the soup "+dish)
	var entry:Dictionary=Goals.goal(RESIDENT,STAGE)
	expect(not entry.has("needs") and not entry.has("items") and entry.options.size()==DISHES.size(),"Event offers all three dishes")
	expect(Goals.option(entry,dish).get("items",{})=={dish:2},"The chosen branch costs exactly two bowls")
	var kind:=Goals.keepsake_kind(RESIDENT,STAGE)
	expect(kind=="keepsake_milu" and World.BUILD.has(kind) and int(World.BUILD[kind].get(Goals.keepsake_item(kind),0))==1,"The keepsake is a one-kit decoration")

func top_up(item:String,amount:int) -> void:
	if count(item)<amount:person.inventory[item]=amount

func fresh_files() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func boot(size:Vector2i,fresh:bool) -> bool:
	root.size=size
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if app.session.host(0,"小試吃島民",path)!=OK:return false
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players.get(token,{})
	if person.is_empty():return false
	person.region=World.REGIONS.HOME
	if fresh:
		world.state.picnic=true
		person.bonds={RESIDENT:{"points":int(Bond.THRESHOLDS[2]),"talk_day":-1,"gift_day":-1}}
		for dish:String in DISHES:person.inventory.erase(dish)
		person.erase(Goals.RECORD_KEY)
		person.erase(Goals.KEEPSAKE_KEY)
	await settle()
	return true

func shutdown_app() -> void:
	app._close_modal()
	expect(app.session.shutdown(),"Save and close the island")
	app.sound.close()
	app.queue_free()
	await settle()

func finish_run() -> void:
	if is_instance_valid(app):
		app.sound.close()
		app.queue_free()
	await settle()
	fresh_files()

## Place the keepsake kit through the existing build action, then take it back through the existing remove action.
func check_placeable(tag:String) -> void:
	var kind:=Goals.keepsake_kind(RESIDENT,STAGE)
	var kit:=Goals.keepsake_item(kind)
	var before:=count(kit)
	expect(before>=1,"The kit is in the bag before placing ("+tag+")")
	var placed:=Vector2i(-1,-1)
	for cell:Vector2i in PLACE_CELLS:
		stand(cell+Vector2i(0,1))
		rates_clear()
		app._perform_build_action("build",cell,kind)
		await settle()
		if count(kit)==before-1:
			placed=cell
			break
	expect(placed.x>=0 and objects_of(kind).size()==1,"The kit is placeable at a free cell ("+tag+")")
	if placed.x<0:return
	serial+=1
	expect(world.act(token,"tasting-remove-%d"%serial,"remove",placed,"").ok and count(kit)==before and objects_of(kind).is_empty(),"Taking it down returns the kit ("+tag+")")

func run_live(dish:String,size:Vector2i) -> void:
	var tag:="%s %dx%d"%[dish,size.x,size.y]
	path="user://milu-tasting-%d-%s-%d.json"%[OS.get_process_id(),dish,size.x]
	fresh_files()
	if not await boot(size,true):
		expect(false,"Isolated island starts ("+tag+")")
		return
	check_recipe_rule(dish)
	var milu:Vector2i=World.bond_place(world.state,RESIDENT)[1]
	var kind:=Goals.keepsake_kind(RESIDENT,STAGE)
	var kit:=Goals.keepsake_item(kind)
	var kit_before:=count(kit)
	var rule:Dictionary=RULES[dish]

	# ---- Locked: nothing to choose, nothing to remember.
	person.bonds={}
	stand(milu)
	Tasks.bond_goal(app,RESIDENT,STAGE)
	await settle()
	expect(button("BondGoalDo")==null and button("BondGoalOption_"+dish)==null and button(MEMORY)==null and node(PANEL)==null,"Locked event offers no choice, no payment and no memory ("+tag+")")
	person.bonds={RESIDENT:{"points":int(Bond.THRESHOLDS[2]),"talk_day":-1,"gift_day":-1}}
	stand(milu)
	expect(Bond.stage(person,RESIDENT)>=STAGE,"Fixture friendship reaches the third stage ("+tag+")")

	# ---- Open with an empty bag: both branches are listed, payment is closed, no memory or bookmark yet.
	await open_story("open "+tag)
	for option:String in DISHES:
		expect(button("BondGoalOption_"+option)!=null,"The option is a real button: "+option)
	var serve:=button("BondGoalDo")
	expect(serve!=null and serve.disabled,"Serving is closed without bowls ("+tag+")")
	expect(node("BondGoalDone")==null and button(MEMORY)==null,"No memory button while the event is open ("+tag+")")
	var refused:Dictionary=world.act(token,"tasting-empty","resident_goal",milu,"%s:%d:%s:"%[RESIDENT,STAGE,dish])
	expect(not refused.ok and not goal_done() and not person.has(Goals.RECORD_KEY),"No bowls means no progress ("+tag+")")
	app._close_modal()
	Tasks.journal(app)
	await settle()
	expect(button(BOOKMARK)==null,"No bookmark before the event is done ("+tag+")")
	app._close_modal()

	# ---- Build the stove with the normal action, queue and claim exactly the picked dish through the real pipeline.
	var forest:=dish==World.FOREST_MUSHROOM.DISH
	var stove_kind:=World.KITCHEN_STOVE.KIND if forest else "stove"
	var cost:=KITCHEN_COST if forest else STOVE_COST
	if forest:
		world.state.board=true
		person[World.FOREST_MUSHROOM.KEY]=World.FOREST_MUSHROOM.STAGE_DONE
	for item:String in cost:top_up(item,int(cost[item]))
	for item:String in rule.ingredients:top_up(item,int(rule.ingredients[item]))
	app.session._send_snapshot(1)
	stand(SPOT+Vector2i(0,2 if forest else 1))
	var before_build:Dictionary=person.inventory.duplicate()
	app._close_modal()
	rates_clear()
	app._perform_build_action("build",SPOT,stove_kind)
	await settle()
	var footprint:=World.KITCHEN_STOVE.CELLS.size() if forest else 1
	expect(objects_of(stove_kind).size()==footprint and world.state.objects.get(World.key(SPOT),{}).get("type")==stove_kind,"A matching stove is built ("+tag+")")
	for item:String in cost:
		expect(count(item)==int(before_build[item])-int(cost[item]),"Building pays the cost of "+item)
	var before_cooking:Dictionary=person.inventory.duplicate()
	rates_clear()
	app.session.perform("queue_cook",SPOT,dish)
	await settle()
	for ingredient:String in rule.ingredients:
		expect(count(ingredient)==int(before_cooking[ingredient])-int(rule.ingredients[ingredient]),"Queueing consumes "+ingredient)
	expect(count(dish)==0,"Queueing gives nothing yet ("+tag+")")
	rates_clear()
	app.session.perform("claim_cook",SPOT)
	await settle()
	expect(count(dish)==0,"Claiming too early hands over nothing ("+tag+")")
	expect(world.step(float(rule.time)+0.5,true,false),"World time passes ("+tag+")")
	app.session._send_snapshot(1)
	rates_clear()
	app.session.perform("claim_cook",SPOT)
	await settle()
	expect(count(dish)==2 and count(other(dish))==0,"Claiming physically puts exactly two %s in the bag (%s)"%[dish,tag])
	expect(not goal_done() and Goals.completed(person)==0,"Cooking alone completes nothing ("+tag+")")

	# ---- The real choice UI: the other branch cannot be served, the picked one can.
	stand(milu)
	await open_story("with bowls "+tag)
	serve=button("BondGoalDo")
	expect(serve!=null and serve.disabled,"Serving waits for a branch ("+tag+")")
	await press("BondGoalOption_"+other(dish))
	serve=button("BondGoalDo")
	expect(serve!=null and serve.disabled,"The branch without bowls cannot be served ("+tag+")")
	await press("BondGoalOption_"+dish)
	serve=button("BondGoalDo")
	expect(serve!=null and not serve.disabled,"The picked branch is ready ("+tag+")")
	check_fit("ready "+tag)
	await capture("01-ready-%s-%dx%d.png"%[dish,size.x,size.y])

	# ---- Serve through the real button; the success panel arrives only after the authoritative result.
	var before:=snapshot_state()
	await press("BondGoalDo")
	var page:Node=await wait_for(PANEL)
	expect(page!=null,"The tasting panel opens after success ("+tag+")")
	expect(goal_done() and picked()==dish,"The picked branch is saved ("+tag+")")
	var row:Dictionary=app.session.snapshot.resident_goals[RESIDENT][str(STAGE)]
	expect(str(row.state)=="done" and str(row.choice)==dish,"The snapshot reports the picked branch ("+tag+")")
	expect(count(dish)==0 and count(other(dish))==0,"Exactly two bowls were paid ("+tag+")")
	expect(int(person.coins)==int(before.coins),"No coins move ("+tag+")")
	expect(Goals.done(person,RESIDENT).size()==1,"Only this event is recorded ("+tag+")")
	expect(count(kit)==kit_before+1 and Goals.keepsake_claimed(person,kind),"The keepsake kit is obtained once ("+tag+")")
	expect(bool(row.keepsake.claimed) and str(row.keepsake.item)==kit,"The snapshot marks the keepsake claimed ("+tag+")")
	check_panel("success "+tag,dish,false)
	var scene:=node(SCENE) as Control
	if scene!=null:
		expect(scene.is_processing() and not bool(scene.call("is_finished")),"The first tasting plays ("+tag+")")
		await capture("02-tasting-playing-%s-%dx%d.png"%[dish,size.x,size.y])
		await create_timer(SETTLE_SECONDS).timeout
		expect(not scene.is_processing() and bool(scene.call("is_finished")),"The tasting settles ("+tag+")")
		await capture("03-tasting-settled-%s-%dx%d.png"%[dish,size.x,size.y])
		if button(REPLAY)!=null:
			await press(REPLAY)
			expect(scene.is_processing() and not bool(scene.call("is_finished")),"Replay plays the tasting again ("+tag+")")
	await press(BACK)
	expect(node(PANEL)==null,"Back leaves the tasting panel ("+tag+")")

	# ---- No repeat, and the keepsake kit really is a placeable decoration.
	var after_one:=snapshot_state()
	rates_clear()
	var again:Dictionary=world.act(token,"tasting-repeat","resident_goal",milu,"%s:%d:%s:"%[RESIDENT,STAGE,dish])
	expect(not again.ok and snapshot_state()==after_one,"The event cannot be served twice ("+tag+")")
	await open_story("after success "+tag)
	expect(node("BondGoalDone")!=null and button("BondGoalDo")==null and node(PANEL)==null,"Reopening shows the done page and no automatic panel ("+tag+")")
	expect(button("BondGoalClaim")==null and count(kit)==kit_before+1,"Nothing is left to claim ("+tag+")")
	var claim_again:Dictionary=world.act(token,"tasting-claim-again","resident_keepsake",milu,"%s:%d"%[RESIDENT,STAGE])
	expect(not claim_again.ok and count(kit)==kit_before+1,"The keepsake is not given twice ("+tag+")")
	await check_placeable(tag)
	stand(milu)

	# ---- Completed page: memory button, panel, and back.
	var done_state:=snapshot_state()
	await open_story("done "+tag)
	var memory:=button(MEMORY)
	expect(memory!=null and memory.is_visible_in_tree() and not memory.disabled,"The done page shows an enabled memory button ("+tag+")")
	check_fit("done story "+tag)
	await capture("04-done-%s-%dx%d.png"%[dish,size.x,size.y])
	await press(MEMORY)
	check_panel("memory "+tag,dish,false)
	await create_timer(SETTLE_SECONDS).timeout
	await capture("05-memory-%s-%dx%d.png"%[dish,size.x,size.y])
	await press("MiluTastingRecipes")
	expect(node("MiluTastingFolio")!=null,"Completing the story unlocks the recipe folio ("+tag+")")
	for item:String in ["salt_grilled_fish","corn_chowder","pumpkin_pie"]:
		expect(node("MiluTastingRecipe_"+item)!=null,"The folio contains "+item)
	check_fit("recipe folio "+tag)
	if forest:await capture("08-intermediate-recipes-%dx%d.png"%[size.x,size.y])
	await press("MiluTastingFolioBack")
	await press(BACK)
	expect(node(PANEL)==null and node("BondGoalDone")!=null,"Back returns to the completed event ("+tag+")")
	expect(snapshot_state()==done_state,"Reopening the memory changes nothing ("+tag+")")

	# ---- Journal bookmark.
	app._close_modal()
	Tasks.journal(app)
	await settle()
	var bookmark:=button(BOOKMARK)
	expect(bookmark!=null and bookmark.is_visible_in_tree() and not bookmark.disabled,"The journal offers the tasting bookmark ("+tag+")")
	await press(BOOKMARK)
	check_panel("journal "+tag,dish,false)
	await press(BACK)
	expect(node(PANEL)==null and button(BOOKMARK)!=null,"Back returns to the journal ("+tag+")")
	expect(snapshot_state()==done_state,"The journal route changes nothing ("+tag+")")

	# ---- Reduced motion: settled art, no replay.
	app._close_modal()
	app.sound.reduced_motion=true
	await open_story("reduced "+tag)
	await press(MEMORY)
	check_panel("reduced memory "+tag,dish,true)
	await capture("06-reduced-%s-%dx%d.png"%[dish,size.x,size.y])
	await press(BACK)
	app._close_modal()
	Tasks.journal(app)
	await settle()
	await press(BOOKMARK)
	check_panel("reduced journal "+tag,dish,true)
	await press(BACK)
	app._close_modal()
	app.sound.reduced_motion=false

	# ---- Save and reload: branch, kit and memory survive.
	await shutdown_app()
	if not await boot(size,false):
		expect(false,"Reopen the saved island ("+tag+")")
		return
	expect(goal_done() and picked()==dish and count(kit)==kit_before+1 and Goals.keepsake_claimed(person,kind),"Branch, kit and claim survive the reload ("+tag+")")
	expect(count(dish)==0,"The paid bowls stay paid after the reload ("+tag+")")
	stand(milu)
	done_state=snapshot_state()
	await open_story("reloaded "+tag)
	await press(MEMORY)
	check_panel("reloaded "+tag,dish,false)
	await press(BACK)
	expect(snapshot_state()==done_state,"Reading after reload changes nothing ("+tag+")")
	check_recipe_rule(dish)
	await finish_run()

## A goal finished before keepsakes existed: the done record is there, bond_keepsakes is not.
func run_legacy(dish:String,size:Vector2i) -> void:
	var tag:="legacy %s %dx%d"%[dish,size.x,size.y]
	path="user://milu-tasting-legacy-%d-%s-%d.json"%[OS.get_process_id(),dish,size.x]
	fresh_files()
	if not await boot(size,true):
		expect(false,"Isolated island starts ("+tag+")")
		return
	var milu:Vector2i=World.bond_place(world.state,RESIDENT)[1]
	var kind:=Goals.keepsake_kind(RESIDENT,STAGE)
	var kit:=Goals.keepsake_item(kind)
	person[Goals.RECORD_KEY]={RESIDENT:{str(STAGE):dish}}
	person.erase(Goals.KEEPSAKE_KEY)
	person.inventory.erase(kit)
	stand(milu)
	expect(goal_done() and picked()==dish and not Goals.keepsake_claimed(person,kind) and count(kit)==0,"Legacy fixture: done, unclaimed, no kit ("+tag+")")
	var row:Dictionary=app.session.snapshot.resident_goals[RESIDENT][str(STAGE)]
	expect(str(row.choice)==dish and not bool(row.keepsake.claimed),"The snapshot reports a done, unclaimed keepsake ("+tag+")")

	# Away from Milu the claim is closed; beside her it works once.
	stand(SPOT)
	await open_story("legacy away "+tag)
	var claim:=button("BondGoalClaim")
	expect(claim!=null and claim.disabled,"The claim is closed away from Milu ("+tag+")")
	var away:Dictionary=world.act(token,"tasting-legacy-away","resident_keepsake",milu,"%s:%d"%[RESIDENT,STAGE])
	expect(not away.ok and count(kit)==0 and not Goals.keepsake_claimed(person,kind),"The server also refuses it from afar ("+tag+")")
	stand(milu)
	await open_story("legacy beside "+tag)
	claim=button("BondGoalClaim")
	expect(claim!=null and not claim.disabled,"The claim opens beside Milu ("+tag+")")
	var memory:=button(MEMORY)
	expect(memory!=null and memory.is_visible_in_tree() and not memory.disabled and button("BondGoalDo")==null,"The legacy done page still offers the memory ("+tag+")")
	check_fit("legacy done "+tag)
	await capture("07-legacy-unclaimed-%s-%dx%d.png"%[dish,size.x,size.y])
	var bag_before:Dictionary=person.inventory.duplicate(true)
	await press("BondGoalClaim")
	for i in 90:
		if count(kit)>0:break
		await process_frame
	await settle()
	expect(count(kit)==1 and Goals.keepsake_claimed(person,kind),"The legacy claim gives the kit once ("+tag+")")
	var delta:=0
	for item:String in person.inventory:
		if int(person.inventory[item])!=int(bag_before.get(item,0)):delta+=1
	expect(delta==1 and picked()==dish,"The claim changes only the kit and keeps the saved branch ("+tag+")")
	expect(button("BondGoalClaim")==null and button(MEMORY)!=null,"The page rebuilds as claimed and keeps its memory ("+tag+")")
	var repeat:Dictionary=world.act(token,"tasting-legacy-again","resident_keepsake",milu,"%s:%d"%[RESIDENT,STAGE])
	expect(not repeat.ok and count(kit)==1,"The legacy claim cannot repeat ("+tag+")")
	await check_placeable(tag)
	stand(milu)

	# The memory plays the SAVED branch for a legacy record too.
	await open_story("legacy memory "+tag)
	var state_now:=snapshot_state()
	await press(MEMORY)
	check_panel("legacy memory "+tag,dish,false)
	await press(BACK)
	expect(node("BondGoalDone")!=null and snapshot_state()==state_now,"Legacy memory returns and changes nothing ("+tag+")")
	app._close_modal()
	app.sound.reduced_motion=true
	Tasks.journal(app)
	await settle()
	await press(BOOKMARK)
	check_panel("legacy reduced journal "+tag,dish,true)
	await press(BACK)
	app._close_modal()
	app.sound.reduced_motion=false
	await finish_run()

func run() -> void:
	var native:=DisplayServer.get_name()!="headless"
	for dish:String in DISHES:
		for size:Vector2i in SIZES:
			await run_live(dish,size)
			if dish!=World.FOREST_MUSHROOM.DISH:await run_legacy(dish,size)
	var wants_capture:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):wants_capture=true
	if native and wants_capture:
		var ready:=0
		var done:=0
		for file_name:String in captured:
			if file_name.begins_with("01-ready-"):ready+=1
			if file_name.begins_with("04-done-"):done+=1
		expect(ready==DISHES.size()*SIZES.size() and done==DISHES.size()*SIZES.size(),"Ready and done are captured for every dish and size")
	await create_timer(0.15).timeout
	print("MILU_TASTING_UI_TESTS checks=%d failures=%d render=%s"%[checks,failures,"native" if native else "headless"])
	if failures==0:print("MILU_TASTING_UI_PASS")
	quit(int(failures>0))
