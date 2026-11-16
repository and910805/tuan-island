extends RefCounted
## Shared fixture for the staged apprentice fix tests. Uses only API present
## on BOTH the production baseline and the patched salt_pan.gd so the
## reproduction suite can run unchanged against either.

const SP=preload("res://scripts/salt_pan.gd")
const FN=preload("res://scripts/flower_nursery.gd")
const DAY:=1440.0
const LATE:="fix-late-joiner-token"
const TENTH:="fix-tenth-player-token"
const ELEVENTH:="fix-eleventh-player-token"
const TWELFTH:="fix-twelfth-player-token"
const OUTSIDER:="fix-outsider-no-record-token"

static func owners() -> Array:
	var out:=[]
	for i in 8:out.append("fix-owner-%d-token"%i)
	return out

static func person() -> Dictionary:
	return {"name":"t","region":"beimen","inventory":{},"coins":500,"travel_book":{"visited":{"home":true,"beimen":true},"legacy_pass":false},"x":1.0,"y":1.0}

static func objs(s:Dictionary) -> Dictionary:
	return s.regions.beimen.objects

static func act(s:Dictionary,token:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	var region:="home" if action in SP.HOME_ACTIONS else "beimen"
	return SP.apply(s,token,action,region,p,extra,objs(s),float(s.time))

static func tick(s:Dictionary,t1:float) -> Dictionary:
	var r:=SP.step(s,float(s.time),t1,objs(s))
	if r.ok:s.time=t1
	return r

static func bag(s:Dictionary,token:String) -> Dictionary:
	return s.players[token].inventory

static func pan_cell(i:int) -> Vector2i:
	return SP.pan_rect(i).position+Vector2i(1,1)

## 8 private owners hold every lot; LATE/TENTH/ELEVENTH/TWELFTH have raked once
## by hand and own nothing. OUTSIDER finished chapter 3 but has no salt record.
static func saturated() -> Dictionary:
	var tokens:Array=owners()+[LATE,TENTH,ELEVENTH,TWELFTH]
	var players:={}
	var flowers:={}
	for token in tokens+[OUTSIDER]:
		players[token]=person()
		var done:Dictionary=FN.FRESH.duplicate(true)
		done.letter=true
		done.complete=true
		flowers[token]=done
	players[OUTSIDER].region="home"
	var fn:=FN.fresh()
	fn.players=flowers
	var regions:={"beimen":{"crops":{},"objects":{},"ground":{},"roofs":{},"forest":{},"removed":{},"damage":{},"next_network_check":0.0,"next_logistics_check":0.0}}
	var s:={"time":0.0,"players":players,"flower_nursery":fn,"salt_pan":SP.fresh(),"events":[],"objects":{},"regions":regions}
	for token in tokens:
		act(s,token,"salt_letter",SP.XIAOLI_HOME)
		act(s,token,"salt_intro",SP.SALT_WORKER)
	s.time=50.0
	bag(s,LATE).merge({"plank":18,"resin":3,"stone":12},true)
	for g in 3:
		for item in ["plank","resin","stone"]:act(s,LATE,"salt_gate_give",Vector2i(8,SP.GATE_ROWS[g]+1),item)
	s.time=7.0*DAY
	for token in tokens:s.salt_pan.players[token].raked=1
	var own:=owners()
	for lot in 8:act(s,own[lot],"salt_claim",pan_cell(lot*2))
	return s

## Total of one kit across every place it may legally live (inventories,
## installed on private lots / the apprentice station, and the escrow if the
## running salt module has one).
static func kit_total(s:Dictionary,kit:String) -> int:
	var part:="wheel" if kit=="salt_wheel_kit" else "rake"
	var n:=0
	for p in s.players.values():n+=int(p.inventory.get(kit,0))
	for lot in s.salt_pan.lots:n+=1 if lot[part] else 0
	n+=1 if s.salt_pan.apprentice[part] else 0
	var escrow=s.salt_pan.get("kit_box",{})
	for box in escrow.values():n+=int(box.get(kit,0))
	return n

static func salt_total(s:Dictionary) -> int:
	var n:=0
	for p in s.players.values():n+=int(p.inventory.get("sea_salt",0))
	for v in s.salt_pan.coop_box.values():n+=int(v)
	for o in objs(s).values():n+=int(o.get("items",{}).get("sea_salt",0))
	return n
