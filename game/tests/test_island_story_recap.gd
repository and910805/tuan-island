extends SceneTree
const Recap=preload("res://scripts/island_story_recap.gd")
const Transit=preload("res://scripts/transit.gd")
var checks:=0
var failures:=0

func expect(value:bool,message:String)->void:
	checks+=1
	if not value:
		failures+=1
		push_error(message)

func ids(recap:Dictionary)->Array:
	return recap.entries.map(func(e):return e.id)

func entry(recap:Dictionary,id:String)->Dictionary:
	for e in recap.entries:
		if e.id==id:return e
	return {}

func tea_state(extra:Dictionary)->Dictionary:
	var s:={"board":true,"picnic":true,"chapter_one":{"shipped":true,"watered":true,"harvests":{},"starter_claims":{}}}
	s.merge(extra,true)
	return s

func boat_labels(s:Dictionary)->Array:
	var tea:=Transit.tea_unlocked(s)
	var result:=[]
	for option in Transit.options("home",Transit.fresh(),true,"ferry",tea,false,false,false,Transit.boat_open(s)):
		if option.mode=="合作小船":result.append(option.label)
	return result

func no_latin(text:String)->bool:
	var regex:=RegEx.create_from_string("[A-Za-z_]")
	return regex.search(text)==null

func _initialize()->void:
	# Legacy / malformed inputs never crash and fall back to the start of the chapter.
	for legacy in [{},null,[],{"dock_stage":"2","festival_story_open":"yes","festival_story":[]},{"festival_story":{"projects":"x","lights":null}}]:
		var r:=Recap.build(legacy)
		expect(r.entries.is_empty(),"Legacy input %s shows no finished dock stages"%str(legacy))
		expect(r.next_step==Recap.PENDING_PIER,"Legacy input %s points to the dock board"%str(legacy))
		expect(not r.has_news and r.marker==0 and not r.can_replay,"Legacy input %s has no news"%str(legacy))

	# JSON reload turns ints into floats.
	var pier:={"dock_stage":1.0}
	var r1:=Recap.build(pier)
	expect(ids(r1)==["dock_pier"],"Stage 1 recaps only the pier")
	expect(entry(r1,"dock_pier").new and r1.has_news,"Player without marker sees pier as new")
	expect(r1.headline.contains(Recap.PIER_TITLE),"Headline names the pier")
	expect(r1.next_step==Recap.PENDING_BOAT,"Stage 1 asks for the boat")
	expect(not Recap.build(pier,1).has_news,"Seen stage 1 marker suppresses news")
	expect(not Recap.build(pier,1.0).has_news,"Float marker from JSON is accepted")
	expect(Recap.build(pier,"bad").has_news,"Invalid marker treated as never seen")

	# Out-of-range stage clamps.
	expect(Recap.read_progress({"dock_stage":9}).dock_stage==2,"Out-of-range dock stage clamps to 2")
	expect(Recap.read_progress({"dock_stage":-3}).dock_stage==0,"Negative dock stage clamps to 0")

	# Boat ready, tea chapter not done: only the warm springs route, matching transit.
	var boat:={"dock_stage":2,"festival_story":{"opened":false,"projects":3,"meal":false,"lights":1,"boat_ready":true}}
	var r2:=Recap.build(boat,1)
	var routes:Array=Recap.read_progress(boat).destinations.map(func(d):return d.label)
	expect(routes==boat_labels(boat),"Boat destinations match transit options without tea: %s vs %s"%[routes,boat_labels(boat)])
	expect(routes==[Transit.STATIONS[Transit.Springs.REGION].name],"Only warm springs before tea chapter")
	expect(ids(r2)==["dock_pier","dock_boat","boat_routes"],"Stage 2 lists pier, boat, routes")
	expect(not entry(r2,"dock_pier").new and entry(r2,"dock_boat").new,"Only the boat is new since stage 1")
	expect(entry(r2,"boat_routes").body.contains(Recap.PENDING_BAMBOO),"Routes mention pending bamboo valley")
	expect(r2.next_step.begins_with(Recap.PENDING_FESTIVAL) and r2.next_step.contains("1／2") and r2.next_step.contains("待準備"),"Next step shows festival preparation: %s"%r2.next_step)
	expect(r2.marker==2,"Marker for boat without tea is 2")

	# Tea chapter complete: bamboo valley joins; seeing only the stage still flags routes.
	var full:=tea_state({"dock_stage":2})
	var routes_full:Array=Recap.read_progress(full).destinations.map(func(d):return d.label)
	expect(routes_full==boat_labels(full) and routes_full.size()==2,"Both boat routes match transit after tea: %s"%[routes_full])
	var r3:=Recap.build(full,2)
	expect(r3.marker==2|Recap.BIT_BAMBOO,"Marker sets bamboo bit")
	var fresh_ids:=[]
	for e in r3.entries:
		if e.new:fresh_ids.append(e.id)
	expect(fresh_ids==["boat_routes"],"Only the new route is news after seeing stage 2: %s"%[fresh_ids])
	expect(not Recap.build(full,r3.marker).has_news,"Seeing the full marker clears news")

	# Festival opened via world state.
	var opened:=tea_state({"dock_stage":2,"festival_story_open":true})
	var before:=var_to_bytes(opened)
	var r4:=Recap.build(opened,2|Recap.BIT_BAMBOO)
	expect(var_to_bytes(opened)==before,"Build does not mutate the snapshot")
	expect(ids(r4)==["dock_pier","dock_boat","boat_routes","festival_opening","festival_replay"],"Opened festival recap order")
	expect(entry(r4,"festival_opening").new and not entry(r4,"festival_replay").new,"Opening is news, replay is a standing action")
	expect(entry(r4,"festival_replay").action=="festival_story" and r4.can_replay,"Replay entry opens the festival memory")
	expect(r4.next_step==Recap.DONE_ALL,"Finished chapter next step")
	var almanac:Script=load("res://scripts/life_ui_almanac.gd")
	expect(almanac!=null and Recap.REPLAY_SCENES==(almanac.get_script_constant_map().get("FESTIVAL_SCENES",[]) as Array).size(),"Replay scene count matches the festival memory")
	expect(var_to_bytes(Recap.build(opened,2))==var_to_bytes(Recap.build(opened,2)),"Recap is deterministic")

	# Legacy client snapshot: no dock_stage, only the festival view.
	var client_opened:={"festival_story":{"opened":true}}
	var p5:=Recap.read_progress(client_opened)
	expect(p5.dock_stage==2 and p5.festival_opened,"Opened festival view implies finished dock")
	expect(Recap.read_progress({"festival_story":{"boat_ready":true}}).dock_stage==2,"Boat-ready view implies finished dock")
	expect(Recap.read_progress({"festival_story_open":true,"dock_stage":0}).dock_stage==2,"Opening repairs impossible legacy stage")

	# Player-facing text is Traditional Chinese only.
	for e in r4.entries+r2.entries:
		expect(no_latin(e.title) and no_latin(e.body),"Entry %s is player-facing Chinese"%e.id)
	for text in [r1.headline,r2.next_step,r4.headline,Recap.build({}).headline,Recap.PENDING_PIER,Recap.PENDING_BOAT,Recap.DONE_ALL]:
		expect(no_latin(text),"Text is player-facing Chinese: %s"%text)

	print("ISLAND_STORY_RECAP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
