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
	var parent:=Node2D.new()
	parent.name="Island"
	root.add_child(parent)
	session=Session.new()
	parent.add_child(session)
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
	if barrier.is_empty():push_error("An isolated --barrier path is required");quit(1);return
	session.connected_world.connect(exercise)
	session.join(address,28551,"測試甲" if role=="alpha" else "測試乙","integration-key",tls)
	await create_timer(12).timeout
	if not done:push_error("LIFE_NETWORK_TIMEOUT");quit(1)
func exercise() -> void:
	await create_timer(0.6).timeout
	var s:Dictionary=session.snapshot
	var box:Dictionary=s.objects["38,32"]
	if role=="alpha":expect(box.items.get("wood",0)==7,"owner sees private contents")
	else:expect(box.items.is_empty() and box.get("locked",false),"other client never receives private contents")
	expect(s.objects["38,33"].has("job"),"unclaimed fixture available before coordinated race")
	if not s.objects["38,33"].has("job"):quit(1);return
	expect(s.objects["38,33"].job.owner!="network-alpha-test","cooking job does not reveal identity token")
	# A test-only filesystem barrier ensures both processes inspect the initial
	# fixture before either claims it; no artificial ordering inside the server.
	var ready_file:=FileAccess.open(barrier+"-"+role+".ready",FileAccess.WRITE)
	if ready_file==null:push_error("Cannot create test barrier");quit(1);return
	ready_file.store_string("ready");ready_file.close()
	while not (FileAccess.file_exists(barrier+"-alpha.ready") and FileAccess.file_exists(barrier+"-beta.ready")):
		await create_timer(0.01).timeout
	session.perform("claim_cook",Vector2i(38,33))
	if role=="beta":session.perform("withdraw",Vector2i(38,32),"wood")
	await create_timer(0.5).timeout
	s=session.snapshot
	expect(not s.objects["38,33"].has("job"),"both clients see claimed job disappear")
	var own:Dictionary=s.players[session.own_id]
	expect(int(own.inventory.get("bread",0)) in [0,1],"no duplicate dish")
	expect(own.inventory.wood==12,"forbidden withdrawal does not mutate inventory")
	done=true
	print("LIFE_NETWORK_TEST role=%s failures=%d bread=%d"%[role,failures,own.inventory.get("bread",0)])
	session.shutdown()
	quit(0 if failures==0 else 1)
