extends "res://tests/test_spring_garden_scene.gd"
## T066 N03-1 acceptance: Bobo's rock story and identification guide.
## Reuses the spring-garden harness (isolated host save, settle/key/press/refresh helpers)
## and drives the real UI: Tasks.bond_goal -> BondGoalDo press -> server-confirmed snapshot.
##
## Covers: locked / insufficient (no story, no entry, no debit); exact 8 stone debit and one
## keepsake kit (no reward duplication); automatic story after the confirmed snapshot; real
## stone-by-stone animation (drawn_count on node BoboRockStoryArt) and its rendered pixels;
## reduced motion shows the final picture at once; skip through BoboRockRead; replay; sample
## switching with BoboRockSource/BoboRockUse; an older already-completed save exposing
## BoboRockGuideEntry on the completed goal page and the Bobo resident page; back/return.
## Runs at 1024x640 and 1280x800. Waits are state based (no fixed sleeps for logic).
## Screenshots/pixel checks need a renderer; under --headless they are skipped and the
## logic/UI checks still run. Pass --capture-dir=<dir> after "--".

const Tasks=preload("res://scripts/life_ui_tasks.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const GUIDE_PATH:="res://scripts/bobo_rock_guide.gd"
const ART_PATH:="res://scripts/bobo_rock_story_art.gd"
const KIT:="keepsake_bobo_kit"
const KEEPSAKE:="keepsake_bobo"
const COST:=8
const FULL:=8
const WAIT_MS:=15000

var native:=true
var guide:Script
var motion_saved:=false
var view_motion_saved:=false

# ---------------------------------------------------------------- generic helpers

func wait_until(condition:Callable,what:String,timeout_ms:=WAIT_MS,pump:=false)->bool:
	var deadline:=Time.get_ticks_msec()+timeout_ms
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		if pump:refresh()
		await process_frame
	return check(condition.call(),"Timed out waiting for "+what)

## A visible node of the open modal, or null.
func node(id:String)->Node:
	var panel:Control=app.modal
	if not is_instance_valid(panel):return null
	var found:CanvasItem=panel if panel.name==id else panel.find_child(id,true,false) as CanvasItem
	return found if found!=null and found.is_visible_in_tree() else null

func art()->Control:
	return node("BoboRockStoryArt") as Control

func drawn()->int:
	var control:=art()
	return int(control.call("drawn_count")) if control!=null and control.has_method("drawn_count") else -1

func story_open()->bool:
	return node("BoboRockStory")!=null and art()!=null

func guide_open()->bool:
	return node("BoboRockGuide")!=null

func text_of(id:String)->String:
	var found:=node(id)
	return str(found.get("text")) if found!=null else ""

func sample_buttons()->Array[Button]:
	var out:Array[Button]=[]
	if not is_instance_valid(app.modal):return out
	for found:Node in app.modal.find_children("BoboRockSample_*","Button",true,false):
		out.append(found as Button)
	return out

func player_dict()->Dictionary:
	return world.state.players[player_id]

func inv()->Dictionary:
	return player_dict().inventory

func close_modal()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func set_motion(reduced:bool)->void:
	app.sound.reduced_motion=reduced
	app.view.reduced_motion=reduced

func capture(shot:String)->void:
	if not native:return
	await super.capture(shot)

func grab()->Image:
	if not native:return null
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func save_shot(image:Image,shot:String)->void:
	if image==null:return
	check(image.save_png(output.path_join(size_tag+"_"+shot+".png"))==OK,"Screenshot saved "+shot)

func crop(image:Image,rect:Rect2)->Image:
	var area:=Rect2i(rect).intersection(Rect2i(Vector2i.ZERO,image.get_size()))
	if area.size.x<=0 or area.size.y<=0:return null
	return image.get_region(area)

func varied(image:Image)->bool:
	if image==null:return false
	var first:=image.get_pixel(0,0)
	for y in range(0,image.get_height(),3):
		for x in range(0,image.get_width(),3):
			if image.get_pixel(x,y)!=first:return true
	return false

func scroll_of(control:Control)->ScrollContainer:
	var up:=control.get_parent()
	while up!=null:
		if up is ScrollContainer:return up
		up=up.get_parent()
	return null

func fit(ids:Array,what:String)->void:
	if not check(is_instance_valid(app.modal),what+": modal is open"):return
	var screen:=root.get_visible_rect()
	check(screen.encloses(app.modal.get_global_rect()),what+": modal fits the window")
	for id:String in ids:
		var control:=node(id) as Control
		if not check(control!=null,what+": has "+id):continue
		var scroll:=scroll_of(control)
		if scroll!=null:
			scroll.ensure_control_visible(control)
			await process_frame
		check(screen.encloses(control.get_global_rect()),what+": "+id+" is reachable inside the window")

func focus_in_modal()->bool:
	var owner:=root.gui_get_focus_owner()
	return owner!=null and is_instance_valid(app.modal) and app.modal.is_ancestor_of(owner)

# ---------------------------------------------------------------- scenario helpers

func frame_site(site:Vector2i)->void:
	refresh()
	preload("res://scripts/travel_ui.gd").dismiss_arrival(app)
	app.view.camera=(Vector2(site)+HALF)*32-Vector2(root.size)/(2.0*app.view.view_zoom())
	app.view.queue_redraw()
	await settle()

func stand_near(site:Vector2i)->void:
	var p:=player_dict()
	var position:=Vector2(site)+HALF
	for offset:Vector2i in [Vector2i.ZERO,Vector2i.DOWN,Vector2i.UP,Vector2i.RIGHT,Vector2i.LEFT]:
		var candidate:=Vector2(site+offset)+HALF
		if world.can_stand(candidate):
			position=candidate
			break
	p.x=position.x
	p.y=position.y
	await frame_site(site)

## Fresh Bobo state next to Bobo: friendship points, stone in the bag, no goal record.
func prepare(points:int,stone:int)->void:
	await close_modal()
	set_motion(false)
	var p:=player_dict()
	p.region=World.REGIONS.JINGUASHI
	p.bonds={"bobo":{"points":points,"talk_day":-1,"gift_day":-1}}
	p.erase(Goals.RECORD_KEY)
	p.erase(Goals.KEEPSAKE_KEY)
	p.inventory.erase(KIT)
	if stone>0:p.inventory["stone"]=stone
	else:p.inventory.erase("stone")
	world.switch_region(p.region)
	await stand_near(World.bond_place(world.state,"bobo")[1])

func guide_available()->bool:
	return bool(guide.call("available",app.session.snapshot))

func goal_done()->bool:
	return str(Tasks.goal_state(app,"bobo",1).get("state",""))=="done"

func settled_idle(frames:=24)->void:
	for index in frames:
		if index%6==0:refresh()
		await process_frame

func no_rock_ui(what:String)->void:
	check(node("BoboRockStory")==null and node("BoboRockGuide")==null,what+": no rock story or guide open")
	check(node("BoboRockGuideEntry")==null,what+": no rock guide entry")

## Wait for a freshly shown story and verify art contract: node name, method, size.
func story_contract(what:String)->bool:
	if not await wait_until(story_open,what+": story and BoboRockStoryArt appear"):return false
	var control:=art()
	check(control.has_method("drawn_count"),what+": art exposes drawn_count()")
	check(control.size.x>=96 and control.size.y>=64,what+": art has a real size %s"%str(control.size))
	check(node("BoboRockRead")!=null and not (node("BoboRockRead") as Button).disabled,what+": BoboRockRead is available during the scene")
	return true

## Follow the real animation: monotonic, one stone at a time, ends on 8; sample pixels midway.
func watch_animation(tag:String)->void:
	var seen:Array[int]=[]
	var last:=-1
	var last_ms:=Time.get_ticks_msec()
	var mid:Image=null
	var deadline:=last_ms+WAIT_MS
	while Time.get_ticks_msec()<deadline and art()!=null:
		var now:=drawn()
		var ms:=Time.get_ticks_msec()
		if last>=0:
			check(now>=last,"%s: stones never disappear (%d->%d)"%[tag,last,now])
			if ms-last_ms<100:check(now-last<=1,"%s: stones are drawn one at a time (%d->%d)"%[tag,last,now])
		if seen.is_empty() or seen.back()!=now:seen.append(now)
		last=now
		last_ms=ms
		if now>=FULL:break
		if native and mid==null and now>=3 and now<=6:
			mid=await grab()
			var after:=drawn()
			if after<1 or after>=FULL:mid=null
			else:save_shot(mid,tag+"-story-mid")
		await process_frame
	check(not seen.is_empty() and seen[0]<FULL and seen[0]<=1,"%s: animation starts near empty (first seen %s)"%[tag,str(seen)])
	check(seen.size()>=3,"%s: several in-between counts rendered %s"%[tag,str(seen)])
	check(not seen.is_empty() and seen.back()==FULL,"%s: animation ends with all 8 stones %s"%[tag,str(seen)])
	if not native:return
	var final_shot:=await grab()
	save_shot(final_shot,tag+"-story-final")
	if not check(mid!=null,"%s: sampled the render mid-animation"%tag) or art()==null:return
	var rect:=art().get_global_rect()
	var mid_crop:=crop(mid,rect)
	var final_crop:=crop(final_shot,rect)
	if check(mid_crop!=null and final_crop!=null,"%s: art rect is on screen"%tag):
		check(varied(final_crop),"%s: final art is drawn, not blank"%tag)
		check(mid_crop.get_data()!=final_crop.get_data(),"%s: rendered pixels change as stones are placed"%tag)

## Samples: names, distinct source/use, switching back, nothing consumed.
func exercise_samples(tag:String)->void:
	var buttons:=sample_buttons()
	if not check(buttons.size()>=6,"%s: at least six BoboRockSample_<id> buttons (%d)"%[tag,buttons.size()]):return
	var before:=inv().duplicate(true)
	var coins:=int(player_dict().coins)
	var order:Array[String]=[]
	for found:Button in buttons:order.append(String(found.name).trim_prefix("BoboRockSample_"))
	var seen:Dictionary={}
	var sequence:Array[String]=order.duplicate()
	sequence.append(order[0])
	for id:String in sequence:
		var sample:=node("BoboRockSample_"+id) as Button
		if not check(sample!=null and not sample.disabled,"%s: sample %s is pressable"%[tag,id]):continue
		var known:String=str(World.NAMES.get(id,""))
		if not known.is_empty():check(sample.text.contains(known),"%s: sample %s keeps the game name %s (\"%s\")"%[tag,id,known,sample.text])
		sample.grab_focus()
		sample.pressed.emit()
		await settle()
		var source:=text_of("BoboRockSource")
		var use:=text_of("BoboRockUse")
		check(not source.is_empty() and not use.is_empty(),"%s: %s shows source and use"%[tag,id])
		var key:=source+"\n"+use
		if seen.has(id):check(seen[id]==key,"%s: returning to %s restores its source/use"%[tag,id])
		else:
			check(not seen.values().has(key),"%s: %s has its own source/use text"%[tag,id])
			seen[id]=key
	check(inv()==before and int(player_dict().coins)==coins,"%s: browsing samples consumes and grants nothing"%tag)

func open_read_page(tag:String)->bool:
	if not await press("BoboRockRead"):return false
	if not await wait_until(guide_open,tag+": guide opens from BoboRockRead"):return false
	check(art()==null and node("BoboRockStory")==null,tag+": reading leaves the story scene")
	return true

# ---------------------------------------------------------------- scenarios

func locked_case()->void:
	await prepare(0,COST)
	var before:=inv().duplicate(true)
	check(not guide_available(),"Locked: guide not available")
	Tasks.bond_goal(app,"bobo",1)
	await settle()
	check(button("BondGoalDo")==null,"Locked: no BondGoalDo")
	no_rock_ui("Locked goal page")
	guide.call("open",app,Callable(),false)
	await settle()
	no_rock_ui("Locked direct open is refused")
	await close_modal()
	Tasks.resident(app,"bobo")
	await settle()
	no_rock_ui("Locked resident page")
	await close_modal()
	check(inv()==before and not goal_done(),"Locked: nothing changed")

func insufficient_case()->void:
	await prepare(1,COST-1)
	var before:=inv().duplicate(true)
	Tasks.bond_goal(app,"bobo",1)
	await settle()
	var finish:=button("BondGoalDo")
	check(finish!=null and finish.disabled,"Short on stone: BondGoalDo is disabled")
	check(not guide_available(),"Short on stone: guide not available")
	no_rock_ui("Short on stone")
	Tasks.do_goal(app)
	guide.call("open",app,Callable(),true)
	await settled_idle()
	check(not goal_done() and inv()==before,"Short on stone: forced attempts debit and reward nothing")
	no_rock_ui("Short on stone after forced attempts")
	await close_modal()

func purchase_case()->void:
	await prepare(1,COST+3)
	var p:=player_dict()
	var opening:=inv().duplicate(true)
	var coins:=int(p.coins)
	Tasks.bond_goal(app,"bobo",1)
	await settle()
	no_rock_ui("Open goal before paying")
	var finish:=button("BondGoalDo")
	if not check(finish!=null and not finish.disabled,"8 stone available: BondGoalDo enabled"):return
	if not await press("BondGoalDo"):return
	if not await wait_until(goal_done,"server-confirmed Bobo 1 snapshot",WAIT_MS,true):return
	# exact debit, one keepsake, nothing else
	var paid:=inv().duplicate(true)
	check(int(paid.get("stone",0))==int(opening.stone)-COST,"Exactly %d stone debited (%d -> %d)"%[COST,opening.stone,paid.get("stone",0)])
	check(int(paid.get(KIT,0))==1 and Goals.keepsake_claimed(p,KEEPSAKE),"Exactly one keepsake kit granted")
	var others:=true
	for item in paid:
		if item!="stone" and item!=KIT and paid[item]!=opening.get(item):others=false
	for item in opening:
		if item!="stone" and not paid.has(item):others=false
	check(others and int(p.coins)==coins,"No other item or coin changed")
	check(Goals.done(p,"bobo")=={1:""},"Only Bobo 1 is recorded as done")
	check(guide_available(),"Done: guide is available")
	# automatic story, once
	if not await story_contract("Auto story"):return
	await fit(["BoboRockStoryArt","BoboRockRead"],"Story page")
	await watch_animation("auto")
	await capture("story-complete-page")
	check(inv()==paid,"Watching the story changes no inventory")
	# read -> guide
	if not await open_read_page("Auto story"):return
	await fit(["BoboRockGuide","BoboRockReplay","BoboRockBack","BoboRockSource","BoboRockUse"],"Guide page")
	check(await wait_until(focus_in_modal,"guide focus inside the modal",3000),"Guide takes keyboard/controller focus")
	await capture("guide")
	await exercise_samples("guide")
	await capture("guide-sample-switched")
	# replay (real animation again), skip with Read half way
	if not await press("BoboRockReplay"):return
	if not await story_contract("Replay"):return
	check(drawn()<FULL,"Replay restarts the animation (%d of %d)"%[drawn(),FULL])
	if not await open_read_page("Skipped replay"):return
	# replay again and watch it finish
	if not await press("BoboRockReplay"):return
	if not await story_contract("Replay 2"):return
	await watch_animation("replay")
	# reduced motion replay: final picture immediately
	if not await open_read_page("Replay 2"):return
	set_motion(true)
	if not await press("BoboRockReplay"):return
	if not await wait_until(story_open,"reduced-motion story"):return
	check(drawn()==FULL,"Reduced motion: all %d stones at first sight (%d)"%[FULL,drawn()])
	for index in 6:await process_frame
	check(drawn()==FULL,"Reduced motion: stays on the final picture")
	if native:
		var still:=await grab()
		save_shot(still,"reduced-motion-story")
		var shot:=crop(still,art().get_global_rect()) if art()!=null else null
		check(shot!=null and varied(shot),"Reduced motion: final picture is rendered")
	set_motion(false)
	if not await open_read_page("Reduced story"):return
	# back leaves the guide; nothing duplicated; story does not return by itself
	if not await press("BoboRockBack"):return
	await settle()
	check(node("BoboRockGuide")==null,"Back leaves the guide")
	await close_modal()
	check(inv()==paid and int(p.coins)==coins,"Story, replay, skip and back never debit or reward again")
	for index in 3:
		refresh()
		await settle()
	check(node("BoboRockStory")==null,"Later snapshots do not reopen the story")
	Tasks.bond_goal(app,"bobo",1)
	await settle()
	check(node("BondGoalDone")!=null and button("BondGoalDo")==null,"Completed page cannot pay again")
	check(node("BoboRockGuideEntry")!=null,"Completed goal page exposes the guide entry after the story")
	await close_modal()

## Older save: Bobo 1 is already done (record only, no kit, no story on load).
func legacy_case()->void:
	await prepare(24,3)
	var p:=player_dict()
	p[Goals.RECORD_KEY]={"bobo":{"1":""}}
	refresh()
	await settled_idle()
	var before:=inv().duplicate(true)
	check(goal_done() and guide_available(),"Older save: snapshot shows Bobo 1 done and the guide is available")
	check(node("BoboRockStory")==null,"Older save: loading does not replay the story")
	for origin:String in ["goal","resident"]:
		if origin=="goal":Tasks.bond_goal(app,"bobo",1)
		else:Tasks.resident(app,"bobo")
		if not await wait_until(func():return node("BoboRockGuideEntry")!=null,"older save %s page shows BoboRockGuideEntry"%origin):
			await close_modal()
			continue
		if origin=="goal":check(node("BondGoalDone")!=null,"Entry sits on the completed goal page")
		await fit(["BoboRockGuideEntry"],"Entry on "+origin)
		await capture("entry-"+origin)
		if not await press("BoboRockGuideEntry"):continue
		if not await wait_until(guide_open,"%s entry opens the guide"%origin):continue
		check(art()==null and node("BoboRockStory")==null,"Entry opens the guide directly, not the scene")
		await fit(["BoboRockGuide","BoboRockReplay","BoboRockBack","BoboRockSource","BoboRockUse"],"Standalone guide from "+origin)
		await exercise_samples("legacy-"+origin)
		# replay then skip, then back to where we came from
		if not await press("BoboRockReplay"):continue
		if not await story_contract("Legacy replay"):continue
		if not await open_read_page("Legacy replay"):continue
		if not await press("BoboRockBack"):continue
		await settle()
		check(node("BoboRockGuide")==null and node("BoboRockStory")==null,"Back closes the guide (%s)"%origin)
		check(node("BoboRockGuideEntry")!=null,"Back returns to the page with the entry (%s)"%origin)
		if origin=="goal":check(node("BondGoalDone")!=null,"Back returns to the completed goal page")
		else:check(node("BondGoalDone")==null,"Back returns to the resident page")
		await close_modal()
	check(inv()==before and not p.inventory.has(KIT),"Older save: guide and story grant or take nothing")

func journey()->void:
	await locked_case()
	await insufficient_case()
	await purchase_case()
	await legacy_case()
	await close_modal()

func run()->void:
	create_timer(300.0).timeout.connect(func():check(false,"Native suite timed out");finish())
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):output=arg.trim_prefix("--capture-dir=")
	if output.is_empty():output=ProjectSettings.globalize_path("res://../work/bobo-rock/native")
	DirAccess.make_dir_recursive_absolute(output)
	native=DisplayServer.get_name()!="headless"
	if not check(ResourceLoader.exists(GUIDE_PATH) and ResourceLoader.exists(ART_PATH),"Feature scripts exist (bobo_rock_guide.gd, bobo_rock_story_art.gd)"):finish();return
	guide=load(GUIDE_PATH)
	path=OS.get_environment("TEMP").path_join("bobo-rock-guide-%d.json"%OS.get_process_id())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	motion_saved=app.sound.reduced_motion
	view_motion_saved=app.view.reduced_motion
	if "--large-text" in OS.get_cmdline_user_args():
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
	if not check(app.session.host(0,"礦石旅人",path)==OK,"Start isolated save"):finish();return
	world=app.session.world
	player_id=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.time=490.0
	app.playing=true
	preload("res://scripts/wangan_opening_ui.gd").dismiss(app)
	for window_size:Vector2i in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=window_size
		size_tag="%dx%d"%[window_size.x,window_size.y]
		await journey()
	finish()

func finish()->void:
	if finished:return
	finished=true
	if is_instance_valid(app):
		app.sound.reduced_motion=motion_saved
		app.view.reduced_motion=view_motion_saved
		if world!=null:
			world.switch_region(World.REGIONS.HOME)
			if check(app.session.shutdown(),"Close and write the isolated world"):
				var readback:=World.new()
				check(readback.load_world(path) and Goals.done(readback.state.players.get(player_id,{}),"bobo").has(1),
					"Bobo's previous completion is readable from disk")
	for suffix:String in ["",".bak",".writer-lock"]:
		if not path.is_empty() and FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BOBO_ROCK_GUIDE mode=%s checks=%d failures=%d"%["native" if native else "headless",checks,failures])
	quit(1 if failures>0 else 0)
