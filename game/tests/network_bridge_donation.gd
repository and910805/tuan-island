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
		if settings.has("restored"):
			var player:Dictionary=snapshot.get("players",{}).get(id,{})
			var inventory:Dictionary=player.get("inventory",{})
			var counts:Dictionary=snapshot.get("donations",{})
			var intact:=id==expected_id and bool(snapshot.get("board",false)) and not player.is_empty()
			intact=intact and int(counts.get("wood",-1))==30 and int(counts.get("stone",-1))==10
			for material in settings.restored:
				intact=intact and int(inventory.get(material,0))==int(settings.restored[material])
			_finish(intact,"restart snapshot preserves the original player's materials and the completed bridge")
			return
		if id!=expected_id or bool(snapshot.get("board",true)):
			_finish(false,"unexpected initial world or owner id=%s token=%s board=%s"%[id,str(settings.token),str(snapshot.get("board","missing"))])
			return
		started=true
		FileAccess.open(str(settings.ready),FileAccess.WRITE).store_string("ready")
		await _wait_for_start()
		return
	if not submitted or not bool(snapshot.get("board",false)) or receipt==null:return
	var donations:Dictionary=snapshot.get("donations",{})
	var events:Array=snapshot.get("events",[])
	var players:Dictionary=snapshot.get("players",{})
	var valid:=int(donations.get("wood",-1))==30 and int(donations.get("stone",-1))==10 and players.size()==4
	var own_inventory:Dictionary=players.get(id,{}).get("inventory",{})
	var share:Dictionary=settings.expected[settings.token]
	var surplus:bool=settings.get("surplus",false)
	var wood:=int(share.wood)-(30 if receipt else 0) if surplus else 0
	var stone:=int(share.stone)-(10 if receipt else 0) if surplus else 0
	valid=valid and (surplus or receipt==true)
	valid=valid and int(own_inventory.get("wood",0))==wood and int(own_inventory.get("stone",0))==stone
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
	if submitted:
		if _message.begins_with("公告板修好了") or _message.begins_with("材料已捐入") or _message.begins_with("公告板已修好"):receipt=ok
		else:_finish(false,"unexpected donation response: "+_message)

func _finish(ok:bool,detail:String)->void:
	if finished:return
	finished=true
	var file:=FileAccess.open(str(settings.result),FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"ok":ok,"accepted":receipt,"token":str(settings.token),"detail":detail}))
		file.close()
	if ok and settings.has("exit"):
		for _i in range(500):
			if FileAccess.file_exists(str(settings.exit)):break
			await create_timer(0.02).timeout
	if session and is_instance_valid(session):session.shutdown()
	print("BRIDGE_DONATION_CLIENT token=%s ok=%s %s"%[str(settings.token),str(ok),detail])
	quit(0 if ok else 1)
