extends SceneTree
const Session=preload("res://scripts/session.gd")
var session:Node
var done:=false
var failures:=0
var role:="alpha"
var barrier:=""
func _initialize() -> void:call_deferred("run")
func expect(value:bool,message:String) -> void:
	if not value:failures+=1;push_error("FAIL "+message)
func run() -> void:
	var parent:=Node2D.new();parent.name="Island";root.add_child(parent)
	session=Session.new();parent.add_child(session)
	var address:="127.0.0.1"
	var tls:TLSOptions=null
	for arg in OS.get_cmdline_user_args():
		if arg.contains("network-beta-test"):role="beta"
		if arg.begins_with("--address="):address=arg.trim_prefix("--address=")
		if arg.begins_with("--barrier="):barrier=arg.trim_prefix("--barrier=")
		if arg.begins_with("--ca="):
			var certificate:=X509Certificate.new()
			if certificate.load(arg.trim_prefix("--ca="))!=OK:quit(1);return
			tls=TLSOptions.client(certificate)
	if barrier.is_empty():quit(1);return
	session.connected_world.connect(exercise)
	session.join(address,28551,"接力甲" if role=="alpha" else "接力乙","integration-key",tls)
	await create_timer(12).timeout
	if not done:push_error("FESTIVAL_NETWORK_TIMEOUT");quit(1)
func exercise() -> void:
	await create_timer(0.3).timeout
	expect(session.snapshot.festival.collected==11 and session.snapshot.festival.active,"both clients see same final bell before race")
	expect(not JSON.stringify(session.snapshot.festival).contains("network-alpha-test"),"participant token never sent to clients")
	var file:=FileAccess.open(barrier+"-"+role+".ready",FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string("ready");file.close()
	while not (FileAccess.file_exists(barrier+"-alpha.ready") and FileAccess.file_exists(barrier+"-beta.ready")):
		await create_timer(0.01).timeout
	session.perform("festival_collect",Vector2i(41,30),"1:11")
	await create_timer(0.6).timeout
	expect(not session.snapshot.festival.active and session.snapshot.festival.collected==12,"contested final bell finishes once")
	var contribution:int=session.snapshot.festival.contributors[session.own_id].count
	var coins:int=session.snapshot.players[session.own_id].coins
	expect(coins==120+20+2*contribution,"contributor reward exactly matches authoritative count")
	session.perform("festival_collect",Vector2i(41,30),"1:11")
	await create_timer(0.3).timeout
	expect(session.snapshot.players[session.own_id].coins==coins,"retry cannot duplicate party reward")
	done=true
	print("FESTIVAL_NETWORK_TEST role=%s failures=%d coins=%d"%[role,failures,coins])
	session.shutdown();quit(0 if failures==0 else 1)
