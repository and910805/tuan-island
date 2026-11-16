extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const BOARD:=Vector2i(40,29)
var session:Session
var settings:Dictionary
var started:=false
var submitted:=false
var receipt:Variant=null
var finished:=false

func _initialize()->void:
	call_deferred("run")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()<1:
		printerr("No fixture argument; user args: ",args)
		quit(2)
		return
	print("BRIDGE_CLIENT_START args=%s"%str(args))
	settings=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if args.size()>1 and args[1]=="seed":
		var world:=World.new()
		world.save_path=str(settings.world)
		for token in settings.shares:
			world.add_player(token,token)
			var person:Dictionary=world.state.players[token]
			person.x=40.5
			person.y=31.5
			person.inventory.wood=int(settings.shares[token].wood)
			person.inventory.stone=int(settings.shares[token].stone)
		world.state.donations={"wood":0,"stone":0}
		world.state.board=false
		var saved:=world.save()
		quit(0 if saved else 1)
		return
	session=Session.new()
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	island.add_child(session)
	session.profile.token=str(settings.token)
	session.notice.connect(_on_notice)
	session.changed.connect(_on_changed)
	var status:=session.join("ws://127.0.0.1:%d"%int(settings.port),0,str(settings.token),"bridge-test")
	if status!=OK:
		printerr("Client websocket connection could not start: ",status)
		quit(1)
		return
	await create_timer(20.0).timeout
	if not finished:
		printerr("Client timed out token=%s started=%s submitted=%s receipt=%s"%[str(settings.get("token")),str(started),str(submitted),str(receipt)])
		quit(1)

func _on_changed(snapshot:Dictionary,id:String)->void:
	if finished:return
	if not started:
		var expected_id:=str(settings.token).sha256_text().left(16)
		if id!=expected_id or bool(snapshot.get("board",true)):
			_finish(false,"unexpected initial world or owner id=%s token=%s board=%s"%[id,str(settings.token),str(snapshot.get("board","missing"))])
			return
		started=true
		FileAccess.open(str(settings.ready),FileAccess.WRITE).store_string("ready")
		await _wait_for_start()
		return
	if not submitted or not bool(snapshot.get("board",false)) or receipt!=true:return
	var donations:Dictionary=snapshot.get("donations",{})
	var events:Array=snapshot.get("events",[])
	var players:Dictionary=snapshot.get("players",{})
	var valid:=int(donations.get("wood",-1))==30 and int(donations.get("stone",-1))==10 and players.size()==4
	var own_inventory:Dictionary=players.get(id,{}).get("inventory",{})
	valid=valid and int(own_inventory.get("wood",-1))==0 and int(own_inventory.get("stone",-1))==0
	_finish(valid,"board=%s donations=%s visible_events=%d players=%d"%[str(snapshot.get("board")),JSON.stringify(donations),events.size(),players.size()])

func _wait_for_start()->void:
	for _i in range(500):
		if FileAccess.file_exists(str(settings.go)):
			var action_id:=session.perform("donate",BOARD)
			submitted=action_id>0
			return
		await create_timer(0.02).timeout
	_finish(false,"timed out waiting for four-client barrier")

func _on_notice(_message:String,ok:bool)->void:
	print("BRIDGE_CLIENT_NOTICE ok=%s %s"%[str(ok),_message])
	if submitted:receipt=ok

func _finish(ok:bool,detail:String)->void:
	if finished:return
	finished=true
	var file:=FileAccess.open(str(settings.result),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify({"ok":ok,"token":str(settings.token),"detail":detail}))
	if session and is_instance_valid(session):session.shutdown()
	print("BRIDGE_DONATION_CLIENT token=%s ok=%s %s"%[str(settings.token),str(ok),detail])
	quit(0 if ok else 1)
