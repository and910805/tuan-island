extends SceneTree
## T066 N04-3: Chacha's 〈一場沒有流程的茶會〉 (stage 3) through the real host UI.
## Open the BondGoal beside the tea NPC with 14 points, pick the topics in order 2,0,1 via BondGoalStep_*,
## submit, and let the story open on its own from the host snapshot. The page order must follow the pick order
## (0 今年的茶, 1 山上的天氣, 2 最近學會的事); Next / Previous / Back navigate; the done page's
## ChachaGatheringEntry reopens the story and ChachaPavilionPattern opens the existing folio.
## Also: the bag is untouched, the order survives save + reload, and a legacy completion (no stored topics)
## or a malformed order falls back to one short recollection without inventing an order.
## The built-pavilion E memento is covered by test_imperfect_tea_pavilion; not repeated here.
## Optional user args: --capture-dir=DIR (native only), --size=WxH, --large-text.

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Gathering:=preload("res://scripts/chacha_tea_gathering.gd")

const PICKS:=[2,0,1]
const DIGITS:="201"
const TOPIC_NAMES:=["今年的茶","山上的天氣","最近學會的事"]
## One distinctive phrase per topic page, indexed by topic.
const TOPIC_LINES:=["比去年更像我想的味道","山上的雲說來就來","把『還沒好』說出口"]
const ENDING_QUOTE:="茶涼了，可是大家還在說話。"

var app
var world:World
var token:String
var person:Dictionary
var site:Vector2i
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	return ok

func stand() -> void:
	person.x=site.x+0.5
	person.y=site.y+1.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func node(id:String) -> Node:
	return app.modal.find_child(id,true,false) if is_instance_valid(app.modal) else null

func button(id:String) -> Button:
	return node(id) as Button

func press(id:String) -> void:
	var target:=button(id)
	expect(target!=null and not target.disabled,"Enabled action: "+id)
	if target!=null and not target.disabled:target.pressed.emit()
	await process_frame
	await process_frame

func settle() -> void:
	for _i in 4:await process_frame

## Timed, settled screenshot; native only, and only with --capture-dir=DIR.
func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var folder:String=arg.trim_prefix("--capture-dir=")
		DirAccess.make_dir_recursive_absolute(folder)
		expect(root.get_texture().get_image().save_png(folder.path_join(file_name))==OK,"Capture "+file_name)

## --size=WxH (default 1024x640); malformed or tiny values fall back to the default.
func window_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=640 and wanted.y>=480:return wanted
	return Vector2i(1024,640)

func visible_text(root_node:Node) -> String:
	var lines:PackedStringArray=[]
	for candidate:Node in root_node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree() and not (candidate as Label).text.strip_edges().is_empty():lines.append((candidate as Label).text)
	for candidate:Node in root_node.find_children("*","RichTextLabel",true,false):
		if (candidate as RichTextLabel).is_visible_in_tree() and not (candidate as RichTextLabel).get_parsed_text().strip_edges().is_empty():lines.append((candidate as RichTextLabel).get_parsed_text())
	return "\n".join(lines)

func gathering_open() -> bool:
	return is_instance_valid(app.modal) and app.modal.name=="ChachaGathering" and node("ChachaGatheringPage")!=null

## Topic pages and the ending use separate named headings.
func heading() -> Label:
	var found:=node("ChachaGatheringHeading") as Label
	return found if found!=null else node("ChachaGatheringTopic") as Label

func goal_done() -> bool:
	return Goals.done(person,"chacha").has(3)

func check_on_screen(id:String,tag:String) -> void:
	var target:=button(id)
	if not expect(target!=null and target.is_visible_in_tree(),"%s is visible (%s)"%[id,tag]):return
	var rect:=target.get_global_rect()
	expect(rect.size.x>=44.0 and rect.size.y>=32.0,"%s is a comfortable target (%s)"%[id,tag])
	expect(Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0).encloses(rect),"%s stays on screen (%s)"%[id,tag])

func check_no_leaks(tag:String) -> void:
	var text:=visible_text(app.modal)
	expect(not text.contains("%s") and not text.contains("null") and not text.contains("{"),"No raw placeholders (%s)"%tag)
	for candidate:Node in app.modal.find_children("*","Label",true,false):
		var label:=candidate as Label
		if label.is_visible_in_tree() and not label.text.strip_edges().is_empty():
			expect(label.size.x>1.0 and label.size.y>1.0,"Visible text has a real box (%s): %s"%[tag,label.text.left(16)])

## Page `page` (0..2) must show the topic picked at that position, nothing of the other topics, and correct nav state.
func check_topic_page(page:int,tag:String) -> void:
	var topic:int=PICKS[page]
	var head:=heading()
	if expect(head!=null and head.is_visible_in_tree(),"Topic label is visible on page %d (%s)"%[page+1,tag]):
		var want:="%s〈%s〉　%d／3"%[Gathering.ORDINALS[page],TOPIC_NAMES[topic],page+1]
		expect(head.text==want,"Page %d follows the pick order: wanted '%s', got '%s' (%s)"%[page+1,want,head.text,tag])
	var text:=visible_text(app.modal)
	expect(text.contains(TOPIC_LINES[topic]),"Page %d speaks topic %d (%s)"%[page+1,topic,tag])
	for other in 3:
		if other!=topic:expect(not text.contains(TOPIC_LINES[other]),"Page %d does not show topic %d (%s)"%[page+1,other,tag])
	expect(node("ChachaGatheringBeat")!=null and node("ChachaGatheringRecollection")==null,"A topic page shows one beat, not the legacy recollection (%s)"%tag)
	var previous:=button("ChachaGatheringPrevious")
	var next:=button("ChachaGatheringNext")
	expect(previous!=null and previous.visible and previous.disabled==(page==0),"Previous is %s on page %d (%s)"%["off" if page==0 else "on",page+1,tag])
	expect(next!=null and next.visible and not next.disabled,"Next is on at page %d (%s)"%[page+1,tag])
	check_no_leaks("page %d %s"%[page+1,tag])

func check_ending(tag:String) -> void:
	var head:=heading()
	expect(head!=null and head.text=="茶會的最後","Last page is the ending (%s)"%tag)
	expect(node("ChachaGatheringQuote")!=null and visible_text(app.modal).contains(ENDING_QUOTE),"Ending shows the trust-stage quote (%s)"%tag)
	expect(node("ChachaGatheringBeat")==null,"Ending shows no topic beat (%s)"%tag)
	var next:=button("ChachaGatheringNext")
	var previous:=button("ChachaGatheringPrevious")
	expect(next!=null and next.disabled and previous!=null and not previous.disabled,"Ending: Next off, Previous on (%s)"%tag)
	expect(button("ChachaGatheringPreview")!=null,"Ending offers the pavilion pattern preview (%s)"%tag)
	check_no_leaks("ending "+tag)

func check_chrome(tag:String) -> void:
	expect(gathering_open() and node("ChachaGatheringArt")!=null,"Gathering page with artwork is open (%s)"%tag)
	var art:=node("ChachaGatheringArt") as Control
	if art!=null:expect(art.is_visible_in_tree() and art.get_global_rect().size.x>1.0 and art.get_global_rect().size.y>1.0,"Artwork has a real box (%s)"%tag)
	check_on_screen("ChachaGatheringNext",tag)
	check_on_screen("ChachaGatheringPrevious",tag)
	check_on_screen("ChachaGatheringBack",tag)

func run() -> void:
	var size_tag:="%dx%d"%[window_size().x,window_size().y]
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var large_text:="--large-text" in OS.get_cmdline_user_args()
	if large_text:
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	var tag:=size_tag+("-large" if large_text else "")
	var path:="user://chacha-tea-gathering-%d.json"%OS.get_process_id()
	if app.session.host(0,"茶會島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.time=720.0
	app.sound.reduced_motion=large_text
	# Fixture: 信任 (14 points) opens stage 3 only; nothing else is done.
	person.bonds={"chacha":{"points":14,"talk_day":-1,"gift_day":-1}}
	var place:Array=World.bond_place(world.state,"chacha")
	person.region=str(place[0])
	site=place[1]
	stand()
	expect(World.RESIDENT_BOND.stage(person,"chacha")==3,"Fixture friendship reaches the third stage")
	var entry:Dictionary=Goals.goal("chacha",3)
	expect(entry.get("steps",[])==TOPIC_NAMES and not entry.has("order") and not entry.has("options"),"Fixture knows the three free-order topics")
	expect(Goals.done(person,"chacha").is_empty() and not Gathering.available(app.session.snapshot),"Nothing is done and no story is available yet")
	var bag_before:=var_to_str(person.inventory)

	# Open the goal and pick the topics through the real step buttons.
	Tasks.bond_goal(app,"chacha",3)
	await settle()
	expect(is_instance_valid(app.modal) and node("BondGoalSteps")!=null and not gathering_open(),"The goal page offers the topic steps")
	var finish:=button("BondGoalDo")
	expect(finish!=null and finish.disabled and finish.tooltip_text==Tasks.GOAL_NEED_STEPS,"Submit is gated until all topics are picked")
	for index in 3:
		var step:=button("BondGoalStep_%d"%index)
		expect(step!=null and not step.disabled and step.text.contains(TOPIC_NAMES[index]),"Topic %d is offered by name"%index)
	await capture("01-goal-open-%s.png"%tag)
	for index in PICKS:await press("BondGoalStep_%d"%index)
	expect(button("BondGoalStep_2").text.begins_with("1.") and button("BondGoalStep_0").text.begins_with("2.") and button("BondGoalStep_1").text.begins_with("3."),"The steps are numbered in the order picked (2, 0, 1)")
	finish=button("BondGoalDo")
	expect(finish!=null and not finish.disabled and finish.tooltip_text.is_empty(),"Submit opens once all three are picked")
	await capture("02-goal-picked-%s.png"%tag)

	# Submit; the story opens by itself from the host snapshot.
	await press("BondGoalDo")
	expect(goal_done() and Goals.done(person,"chacha")=={3:""},"The server records only stage 3")
	expect(person.get(Goals.TEA_TOPICS_KEY)==DIGITS and Goals.tea_topic_order(person)==PICKS,"The server stores the picked order %s"%DIGITS)
	expect(var_to_str(person.inventory)==bag_before,"Submitting pays and gives nothing")
	await settle()
	if not gathering_open():
		stand()
		await settle()
	var published:Dictionary=app.session.snapshot.resident_goals.chacha["3"]
	expect(published.state=="done" and str(published.get("topics",""))==DIGITS,"The snapshot publishes the order to its owner")
	expect(Gathering.order(app.session.snapshot)==PICKS,"The reader decodes the published order")
	if not expect(gathering_open(),"The story opens automatically after the host snapshot"):
		await finish_up(path)
		return
	expect(node("BondGoalSteps")==null and button("BondGoalDo")==null,"The goal page is replaced by the story")

	# Page by page, in the picked order.
	var before_view:=var_to_str(person)
	check_chrome(tag)
	expect(node("ChachaGatheringArt").is_animating()!=large_text,"Topic art respects reduced motion")
	check_topic_page(0,tag)
	await capture("03-topic-1-%s.png"%tag)
	await press("ChachaGatheringNext")
	check_topic_page(1,tag)
	await capture("04-topic-2-%s.png"%tag)
	await press("ChachaGatheringNext")
	check_topic_page(2,tag)
	await capture("05-topic-3-%s.png"%tag)
	await press("ChachaGatheringPrevious")
	check_topic_page(1,tag+" back")
	await press("ChachaGatheringNext")
	check_topic_page(2,tag+" again")
	await press("ChachaGatheringNext")
	check_ending(tag)
	check_chrome(tag+" ending")
	await capture("06-ending-%s.png"%tag)
	await press("ChachaGatheringPrevious")
	check_topic_page(2,tag+" from ending")
	await press("ChachaGatheringPrevious")
	await press("ChachaGatheringPrevious")
	check_topic_page(0,tag+" rewound")
	expect(var_to_str(person.inventory)==bag_before and var_to_str(person)==before_view,"Reading the story changes nothing")

	# Back returns to the completed page, which offers the entry and the pattern.
	await press("ChachaGatheringBack")
	expect(not gathering_open() and node("BondGoalDone")!=null and button("BondGoalDo")==null,"Back returns to the completed goal page")
	expect(node("BondGoalSteps")==null and node("BondGoalStepsReset")==null,"The completed page does not offer the topics again")
	var entry_button:=button("ChachaGatheringEntry")
	expect(entry_button!=null and entry_button.is_visible_in_tree() and not entry_button.disabled,"The completed page offers 重看茶會")
	expect(button("ChachaPavilionPattern")!=null and node("BondGoalPavilionUnlock")==null,"The completed page links the pavilion pattern")
	await capture("07-done-%s.png"%tag)

	# Entry reopens at the first page, in the picked order, as often as wanted.
	await press("ChachaGatheringEntry")
	expect(gathering_open(),"The entry reopens the story")
	check_topic_page(0,tag+" reopened")
	await press("ChachaGatheringNext")
	await press("ChachaGatheringBack")
	await press("ChachaGatheringEntry")
	check_topic_page(0,tag+" reopened twice")
	await press("ChachaGatheringBack")

	# The existing pattern button opens the existing folio.
	await press("ChachaPavilionPattern")
	await settle()
	expect(is_instance_valid(app.modal) and node("BuildFolio")!=null,"The pattern opens the existing build folio")
	expect(node("ChachaGatheringEntry")==null and not gathering_open(),"The folio replaces the goal page")
	var folio_title:=node("BuildTitle") as Label
	expect(folio_title!=null and folio_title.text.contains(str(World.BUILD[World.INDUSTRY.IMPERFECT_TEA_PAVILION].name)),"The folio is on 不完美的茶亭")
	await capture("08-folio-%s.png"%tag)
	app._close_modal()
	expect(var_to_str(person.inventory)==bag_before,"The bag is unchanged after the whole walk-through")

	# Persistence: the order is in the save file and survives a reload.
	expect(world.save(),"The world saves")
	var loaded:=World.new()
	if expect(loaded.load_world(path),"The island reloads from disk"):
		var restored:Dictionary=loaded.state.players.get(token,{})
		expect(Goals.done(restored,"chacha").has(3) and Goals.tea_topic_order(restored)==PICKS,"The reloaded player keeps stage 3 and the order")
		var view:Dictionary=Goals.view(restored,loaded.state,token)
		expect(str(view.chacha["3"].get("topics",""))==DIGITS,"The reloaded owner view publishes %s"%DIGITS)
		expect(var_to_str(restored.inventory)==bag_before,"The reloaded bag is unchanged")

	# Legacy: stage 3 done before topics were stored. One short recollection, no invented order.
	person.erase(Goals.TEA_TOPICS_KEY)
	stand()
	await settle()
	var legacy:Dictionary=app.session.snapshot.resident_goals.chacha["3"]
	expect(legacy.state=="done" and not legacy.has("topics") and Gathering.available(app.session.snapshot) and Gathering.order(app.session.snapshot).is_empty(),"A legacy snapshot is done with no order")
	Tasks.bond_goal(app,"chacha",3)
	await settle()
	await press("ChachaGatheringEntry")
	expect(gathering_open(),"A legacy completion still reopens the story")
	expect(node("ChachaGatheringRecollection")!=null and node("ChachaGatheringBeat")==null and node("ChachaGatheringQuote")!=null,"Legacy shows a single recollection and the quote")
	var legacy_previous:=button("ChachaGatheringPrevious")
	var legacy_next:=button("ChachaGatheringNext")
	expect(legacy_previous!=null and not legacy_previous.visible and legacy_next!=null and not legacy_next.visible,"Legacy has no pages to turn")
	var legacy_text:=visible_text(app.modal)
	expect(legacy_text.contains("沒有記下聊的先後") and not legacy_text.contains("先聊〈") and not legacy_text.contains("接著聊〈"),"Legacy does not invent an order")
	check_on_screen("ChachaGatheringBack",tag+" legacy")
	var legacy_scroll:=node("ModalScroll") as ScrollContainer
	expect(legacy_scroll!=null and not legacy_scroll.get_v_scroll_bar().visible,"Legacy recollection and actions all fit")
	check_no_leaks("legacy "+tag)
	await capture("09-legacy-%s.png"%tag)
	await press("ChachaGatheringBack")
	expect(node("BondGoalDone")!=null and button("ChachaGatheringEntry")!=null,"Legacy Back returns to the completed page")
	app._close_modal()
	expect(var_to_str(person.inventory)==bag_before,"The legacy walk-through leaves the bag alone")

	# Malformed stored orders fragment to the same safe fallback; unfinished stages show nothing.
	var good:={"resident_goals":{"chacha":{"3":{"state":"done","choice":"","topics":DIGITS}}}}
	expect(Gathering.order(good)==PICKS,"A well-formed order decodes")
	for bad:Variant in ["","2","20","2011","220","201x","-12","3 1","９０１",7,null,[2,0,1]]:
		var forged:=good.duplicate(true)
		forged.resident_goals.chacha["3"].topics=bad
		expect(Gathering.available(forged) and Gathering.order(forged).is_empty(),"Malformed topics %s fall back safely"%var_to_str(bad))
	for broken:Variant in [{},{"resident_goals":null},{"resident_goals":{"chacha":null}},{"resident_goals":{"chacha":{"3":"done"}}},{"resident_goals":{"chacha":{"3":{"state":"open","topics":DIGITS}}}},{"resident_goals":{"chacha":{"2":{"state":"done"}}}}]:
		expect(not Gathering.available(broken) and Gathering.order(broken).is_empty(),"Unfinished or broken record %s shows no story"%var_to_str(broken))

	await finish_up(path)

func finish_up(path:String) -> void:
	person.region=World.REGIONS.HOME
	world.switch_region(World.REGIONS.HOME)
	expect(app.session.shutdown(),"Save and close the island")
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CHACHA_TEA_GATHERING_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
