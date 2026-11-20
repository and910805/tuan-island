extends "res://scripts/world.gd"
## TEST-ONLY reference implementation of the 打瞌睡石像 server contract. NOT production
## code and NOT a runnable test: it exists so the *_selfcheck scripts can prove that
## test_sleepy_stone_guardian_world.gd / network_sleepy_stone_guardian.gd are
## satisfiable by a contract-conforming World before the real wiring lands.
## It overrides World._apply for the four guardian actions only and seeds the hum
## from Guardian.phrase(token, round); the real server may seed differently.

const GuardianRules=preload("res://scripts/sleepy_stone_guardian.gd")
const CAPACITY:=1000000000
## Host memory only: token -> bells entered so far in the current phrase.
var guardian_entered:={}

## A refused or rolled-back action (for example a failed save) must not leave the
## half-entered phrase advanced.
func act(token:String,request_id:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	var typed_before:Dictionary=guardian_entered.duplicate(true)
	var result:Dictionary=super.act(token,request_id,action,p,extra)
	if not result.get("ok",false):guardian_entered=typed_before
	return result

func _apply(token:String,action:String,p:Vector2i,extra:String,build_style:String="",mill_facing:int=-1) -> Dictionary:
	if action not in GuardianRules.ACTIONS:return super._apply(token,action,p,extra,build_style,mill_facing)
	var player:Dictionary=state.players[token]
	var bell:=GuardianRules.bell_at(p)
	var aimed:bool=bell>=0 if action=="guardian_ring" else p==GuardianRules.GUARDIAN
	if not extra.is_empty() or not state.get("picnic",false) or not GuardianRules.available(_region,int(state.mine_depths.unlocked)) or not aimed or not GuardianRules.near(Vector2(player.x,player.y),p):
		return fail("請到第四層北側小洞，靠近石像或風鈴。")
	var record:Dictionary=player.get("sleepy_guardian",GuardianRules.fresh())
	var typed:Array=guardian_entered.get(token,[])
	var out:Dictionary
	if action=="guardian_listen":out=GuardianRules.listen(token,record)
	elif action=="guardian_ring":out=GuardianRules.ring(token,record,typed,bell)
	elif action=="guardian_sit":out=GuardianRules.sit(record)
	else:
		out=GuardianRules.claim(record)
		if out.ok and int(player.inventory.get(out.reward.item,0))>CAPACITY-int(out.reward.count):
			out={"ok":false,"message":"背包中的晶砂已達上限，謝禮仍可領取。","record":record,"entered":[],"outcome":"full"}
		elif out.ok:
			give(player.inventory,out.reward.item,int(out.reward.count))
	var view:={"outcome":out.outcome,"round":int(out.record.round),"calm":int(out.record.calm),"claimed":bool(out.record.claimed),"entered":(out.entered as Array).size()}
	if out.has("notes"):view["notes"]=out.notes
	if action=="guardian_ring":view["bell"]=bell
	if out.ok:
		if action!="guardian_listen":
			guardian_entered[token]=out.entered
			if out.record!=record:player["sleepy_guardian"]={"round":int(out.record.round),"calm":int(out.record.calm),"claimed":bool(out.record.claimed)}
	return {"ok":out.ok,"message":out.message,"guardian":view}
