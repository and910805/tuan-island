extends "res://tests/test_external_cuddle_server.gd"
const CowCare=World.COW_CARE
const SITE:=Vector2i(48,35)
const ONE:="r21-network-one"
const TWO:="r21-network-two"
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	print("EXPORTED_COW_CLIENTS checks=%d exit=%d"%[checks,code])
	quit(code)
func run()->void:
	var port:=int(OS.get_environment("TUAN_R21_PORT"))
	var key:=OS.get_environment("GAME_CLIENT_ROOM_KEY")
	var address:="ws://127.0.0.1:%d"%port
	var first:=make_session("CowExternalOne",ONE)
	if not check(first.join(address,port,"照料者",key)==OK and await wait_for(func():return not first.own_id.is_empty()),"Admitted to actual Linux export"):return
	if OS.get_environment("TUAN_R21_MODE")=="reload":
		if not check(CowCare.active_actor(first.snapshot).is_empty() and first.snapshot.livestock.cow.bond==1,"Restart preserves bond without old follow"):return
		if not check(first.own_id==ONE.sha256_text().left(16) and first.snapshot.players.has(first.own_id),"Original public identity reconnects; offline profiles are checked in saved world"):return
		if not check(is_equal_approx(float(first.snapshot.livestock.cow.last_pet),float(OS.get_environment("TUAN_R21_LAST_PET"))) and float(first.snapshot.time)>=float(OS.get_environment("TUAN_R21_SAVED_TIME")),"Restart retains original care timestamp and saved clock"):return
		finish(0)
		return
	var second:=make_session("CowExternalTwo",TWO)
	if not check(second.join(address,port,"旁觀者",key)==OK and await wait_for(func():return not second.own_id.is_empty()),"Second client admitted"):return
	var before:Dictionary=first.snapshot.players[first.own_id].inventory.duplicate(true)
	first.perform("livestock_pet",SITE,"cow")
	second.perform("livestock_pet",SITE,"cow")
	if not check(await wait_for(func():return notices[first].size()>0 and notices[second].size()>0),"Both care requests return"):return
	if not check(int(notices[first].back().ok)+int(notices[second].back().ok)==1,"Exactly one simultaneous pet succeeds"):return
	if not check(await wait_for(func():return not CowCare.active_actor(first.snapshot).is_empty() and CowCare.active_actor(first.snapshot)==CowCare.active_actor(second.snapshot)),"Both clients see one care target"):return
	if not check(int(first.snapshot.livestock.cow.bond)==1,"Exactly one bond, no duplicate reward"):return
	for client in [first,second]:
		if not check(not JSON.stringify(client.snapshot).contains(ONE) and not JSON.stringify(client.snapshot).contains(TWO),"Wire contains no original profile tokens"):return
	var winner=first if CowCare.active_actor(first.snapshot)==first.own_id else second
	var old_y:float=winner.snapshot.players[winner.own_id].y
	winner.input_direction(Vector2.DOWN)
	await create_timer(0.15).timeout
	winner.input_direction(Vector2.ZERO)
	if not check(await wait_for(func():return float(winner.snapshot.players[winner.own_id].y)>old_y),"Real input still moves through Linux collision rules"):return
	if not check(await wait_for(func():return CowCare.active_actor(first.snapshot).is_empty() and CowCare.active_actor(second.snapshot).is_empty(),22.0),"Actual eighteen-second server timer expires for both clients"):return
	if not check(first.snapshot.players[first.own_id].inventory==before and int(first.snapshot.livestock.cow.bond)==1,"Timeout does not change materials or bond"):return
	if not check(not await action(first,"livestock_pet",SITE,"cow"),"Care animation expiry does not bypass thirty-second cooldown"):return
	finish(0)
