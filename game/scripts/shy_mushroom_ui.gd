extends RefCounted
## 害羞菇 (B2 east nook) client glue. No menu and no inventory item: the normal interact key sends
## `shy_wait` / `shy_claim`, and the ordinary selected watering can sends the usual `water` on the
## mushroom cell. This file only keeps what the host told this player (the quiet-wait anchor from
## the correlated action reply) and turns it into a ring, a label, cues and one spoken-style notice.
##
## Pure helpers (points / label / view_of / clean_record) take plain data so they are testable
## without a scene; the `main` entry points mirror sleepy_stone_guardian_ui.gd.

const Shy=preload("res://scripts/shy_mushroom.gd")
const Spores=preload("res://scripts/shy_spores.gd")
const Audio=preload("res://scripts/shy_mushroom_audio.gd")

const META:="shy_mushroom_ui"
## Interact point id (also the world label id).
const POINT:="mine_shy_mushroom"
## world_view draws the sprite with its FOOT pixel at tile top-left + this (same as the B4 statue).
const FOOT_OFFSET:=Vector2(16,30)
const LABEL_OFFSET:=Vector2(16,-22)
## Real seconds the water-response frame (atlas frame 2) stays up before the open frame.
const RESPOND_SECONDS:=0.9
const READY_NOTICE:="害羞菇安靜下來了。再按一次 {interact}，看牠會不會探頭。"
const CANCEL_NOTICE:="你走開了，害羞菇又縮回帽子下。沒關係，回來再安靜等一下就好。"

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

static func _yes(value) -> bool:
	return value is bool and value

static func clean_record(raw) -> Dictionary:
	var out:=Shy.fresh()
	if not raw is Dictionary:return out
	var stage=raw.get("stage")
	if (stage is int or stage is float) and is_finite(stage):out.stage=clampi(int(stage),0,2)
	out.claimed=_yes(raw.get("claimed")) and int(out.stage)>=2
	return out

static func record_of(snapshot:Dictionary,own_id:String) -> Dictionary:
	var people=snapshot.get("players",{})
	if not people is Dictionary:return Shy.fresh()
	var person=people.get(own_id,{})
	return clean_record(person.get("shy_mushroom") if person is Dictionary else null)

static func available(snapshot:Dictionary) -> bool:
	var depths=snapshot.get("mine_depths",{})
	return _yes(snapshot.get("picnic",false)) and Shy.available(str(snapshot.get("region_id","home")),int(depths.get("unlocked",1)) if depths is Dictionary else 1)

## Interact point: only on an unlocked B2, and only while there is still something to do.
## Once the gift is taken the open mushroom stays as scenery with no prompt.
static func points(state:Dictionary,player:Dictionary,region:String,unlocked:int) -> Dictionary:
	if not _yes(state.get("picnic",false)) or not Shy.available(region,unlocked):return {}
	var record:=clean_record(player.get("shy_mushroom"))
	if _yes(record.claimed):return {}
	if not Shy.open(record) and spores_moving(state):return {}
	return {POINT:Vector2(Shy.MUSHROOM)+Vector2(0.5,0.5)}

static func spores_moving(snapshot:Dictionary)->bool:
	return int(snapshot.get(Spores.VIEW,{}).get("phase",-1)) in [Spores.Phase.WARNING,Spores.Phase.PASSING]

static func spore_label(run:Dictionary)->String:
	match int(run.get("phase",-1)):
		Spores.Phase.WARNING:return "往左避開孢子" if float(run.lane)>46.0 else "往右避開孢子"
		Spores.Phase.PASSING:return "孢子飄過 · %d/2"%(int(run.wave)+1)
		Spores.Phase.FINISHED:return "躲過了 · 看看害羞菇"
		Spores.Phase.MISSED:return "碰到孢子了 · 再試一次"
	return "害羞菇 · 練習躲孢子"

## Whole world-seconds already waited (0..4) for the "n／4" text.
static func seconds_done(progress:float) -> int:
	return clampi(int(floor(clampf(progress,0.0,1.0)*Shy.WAIT_SECONDS+0.0001)),0,int(Shy.WAIT_SECONDS))

## Ring/label state from the host-confirmed anchor. `watch` is {} or {x,y,since}.
static func view_of(record:Dictionary,watch:Dictionary,now:float,responding:bool) -> Dictionary:
	var hidden:=int(record.get("stage",0))<=0
	var progress:=Shy.progress(watch,now) if hidden else 0.0
	return {"watching":hidden and not watch.is_empty(),"progress":progress,"ready":hidden and not watch.is_empty() and progress>=1.0,
		"seconds":seconds_done(progress),"responding":responding and int(record.get("stage",0))>=2}

## Short in-world label. Text carries the same information as the ring and the atlas frame.
static func label(record:Dictionary,view:Dictionary,selected_tool:String="") -> String:
	var stage:=int(record.get("stage",0))
	if stage>=2:return "害羞菇開心地看著你" if _yes(record.get("claimed",false)) else "害羞菇 · 收下小禮物"
	if stage==1:return "探頭了 · 用水壺點牠" if selected_tool=="water" else "探頭了 · 換水壺澆一點水"
	if _yes(view.get("ready",false)):return "牠安靜下來了 · 再按一次"
	if _yes(view.get("watching",false)):return "安靜等待 %d／%d 秒"%[int(view.get("seconds",0)),int(Shy.WAIT_SECONDS)]
	return "害羞菇 · 停下來安靜等"

## Which action the interact key sends for this record.
static func interact_action(record:Dictionary) -> String:
	return Shy.CLAIM_ACTION if int(record.get("stage",0))>=2 else Shy.WAIT_ACTION

# ---------------------------------------------------------------------------
# State on main
# ---------------------------------------------------------------------------

static func _state(main) -> Dictionary:
	if not main.has_meta(META):main.set_meta(META,{"watch":{},"respond_at":-1000.0,"ready_told":false})
	return main.get_meta(META)

static func _ticks() -> float:
	return Time.get_ticks_msec()/1000.0

static func _own(main) -> Dictionary:
	var people=main.session.snapshot.get("players",{})
	var person=people.get(main.session.own_id,{}) if people is Dictionary else {}
	return person if person is Dictionary else {}

static func _drop_watch(main,state:Dictionary,tell:bool) -> void:
	if (state.watch as Dictionary).is_empty():return
	state.watch={}
	state.ready_told=false
	if tell and main.has_method("_notice"):main._notice(CANCEL_NOTICE,true)

# ---------------------------------------------------------------------------
# Entry points (called from main.gd)
# ---------------------------------------------------------------------------

## Normal interact key on the mushroom point.
static func interact(main) -> void:
	var snapshot:Dictionary=main.session.snapshot
	if not available(snapshot):return
	var record:=record_of(snapshot,main.session.own_id)
	if snapshot.has(Spores.VIEW) and not Shy.open(record):
		var phase:=int(snapshot[Spores.VIEW].get("phase",-1))
		if phase==Spores.Phase.FINISHED:main.session.perform(Spores.ACTION,Shy.MUSHROOM,Spores.FINISH)
		elif phase in [-1,Spores.Phase.MISSED]:main.session.perform(Spores.ACTION,Shy.MUSHROOM,Spores.ENTER)
		return
	main.session.perform(interact_action(record),Shy.MUSHROOM)

static func observe_spores(main,snapshot:Dictionary)->void:
	if not main.playing or not snapshot.has(Spores.VIEW):return
	var current:Dictionary=snapshot[Spores.VIEW]
	var previous:Dictionary=main.view.data.get(Spores.VIEW,{})
	var phase:=int(current.get("phase",-1))
	if phase==Spores.Phase.WARNING and (previous.get("phase")!=phase or current.wave!=previous.get("wave")):
		Audio.play(main,Shy.CUE_RUSTLE)
		if main.sound.activity_captions:main._caption(spore_label(current),2)
	elif phase!=previous.get("phase"):
		if phase==Spores.Phase.MISSED:
			main._notice("碰到孢子了，靠近害羞菇可以再試一次。",false)
		elif phase==Spores.Phase.FINISHED:
			Audio.play(main,Shy.CUE_PEEK)

## Correlated reply for shy_wait / shy_claim / a `water` routed to the mushroom.
static func handle_result(main,_action:String,result:Dictionary) -> void:
	var reply=result.get("shy")
	if not reply is Dictionary:return
	var state:=_state(main)
	var since:=float(reply.get("since",-1.0))
	if since>=0.0:
		var fresh_start:=str(reply.get("outcome",""))=="start"
		state.watch={"x":float(reply.get("x",0.0)),"y":float(reply.get("y",0.0)),"since":since}
		if fresh_start:state.ready_told=false
	else:
		state.watch={}
		state.ready_told=false
	var outcome:=str(reply.get("outcome",""))
	if outcome=="water":state.respond_at=_ticks()
	var cues:Array=(reply.get("cues",[]) as Array).duplicate() if reply.get("cues") is Array else []
	if outcome=="claim":cues.append(Shy.CUE_OPEN)
	Audio.play_all(main,cues)

## Per snapshot: forget the anchor when the encounter is gone or the host-side wait cannot exist.
static func refresh(main) -> void:
	if not main.has_meta(META):return
	var state:=_state(main)
	var snapshot:Dictionary=main.session.snapshot
	if not available(snapshot) or int(record_of(snapshot,main.session.own_id).stage)>0:_drop_watch(main,state,false)

## Per frame: ring/label state for world_view. Mirrors the host's walk-away rule so the ring
## disappears the moment the wait is really cancelled (the host stays the authority).
static func view_state(main) -> Dictionary:
	if not is_instance_valid(main) or not main.has_meta(META) or main.session==null:return {}
	var state:=_state(main)
	var snapshot:Dictionary=main.session.snapshot
	if not available(snapshot):return {}
	var person:=_own(main)
	if not (state.watch as Dictionary).is_empty() and person.has("x") and person.has("y"):
		if Shy.watch_hold(state.watch,Vector2(float(person.x),float(person.y))).is_empty():_drop_watch(main,state,true)
	var record:=record_of(snapshot,main.session.own_id)
	var view:=view_of(record,state.watch,float(snapshot.get("time",0.0)),_ticks()-float(state.respond_at)<RESPOND_SECONDS)
	if _yes(view.ready) and not state.ready_told:
		state.ready_told=true
		if main.has_method("_notice"):main._notice(main.binding_text(READY_NOTICE) if main.has_method("binding_text") else READY_NOTICE,true)
		Audio.play(main,Shy.CUE_RUSTLE)
	return view
