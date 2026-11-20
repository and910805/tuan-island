extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Store=preload("res://scripts/admission_store.gd")
class FaultStore extends "res://scripts/admission_store.gd":
	var stop:=""
	func checkpoint(stage:String) -> bool:
		return stage!=stop

var checks:=0
var failures:=0
var folder:String
var world_path:String
var roster_path:String

func expect(condition:bool,message:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func open_session() -> Node:
	var server:=Session.new()
	root.add_child(server)
	var error:=server.configure_identity("http://127.0.0.1:8142","test-island","test-secret",roster_path,"owner",true,null,world_path)
	expect(error==OK,"Identity configuration and any pending recovery succeed")
	server.world=World.new()
	expect(server.world.load_world(world_path),"World opens after membership recovery")
	return server

func run() -> void:
	folder=OS.get_environment("TEMP").path_join("tuan-admission-"+Crypto.new().generate_random_bytes(12).hex_encode())
	DirAccess.make_dir_recursive_absolute(folder)
	world_path=folder.path_join("world.json")
	roster_path=folder.path_join("roster.json")
	var server:=open_session()
	var owner:String=server.membership.read("owner").character
	server.world.add_player(owner,"島主")
	server.world.state.players[owner].coins=271
	server.world.state.objects["40,40"]={"type":"chest","owner":owner,"items":{}}
	expect(server.world.save(),"Owner baseline is persisted")
	var invitation:Dictionary=server.membership.rotate("owner")
	var code:String=invitation.code
	var baseline_world:=FileAccess.get_file_as_bytes(world_path)
	var baseline_members:=FileAccess.get_file_as_bytes(roster_path)
	var draft:={"account_id":"guest","display_name":"訪島人"}
	var denied:Dictionary=server.commit_identity_admission(2,draft,"")
	expect(not denied.ok and denied.code=="INVITE_INVALID","Guest without invite has no admission")
	var fault:=FaultStore.new()
	server.admission_store=fault
	expect(server.multiplayer.is_server(),"Frozen tick exercises a server authority")
	fault.stop="prejournal"
	denied=server.commit_identity_admission(2,draft,code)
	expect(not denied.ok and denied.code=="SAVE_FAILED" and server.accepting,"Precommit failure remains retryable")
	expect(FileAccess.get_file_as_bytes(world_path)==baseline_world and FileAccess.get_file_as_bytes(roster_path)==baseline_members,"Precommit failure leaves both files unchanged")
	expect(not Store.has_pending(roster_path) and not server.membership.has_member("guest"),"No journal or live guest seat before commit")
	fault.stop="afterworld"
	denied=server.commit_identity_admission(2,draft,code)
	expect(not denied.ok and denied.code=="RECOVERING" and not server.accepting,"Decided write failure freezes admission")
	expect(Store.has_pending(roster_path) and not server.membership.has_member("guest") and server.world.state.players.size()==1,"Pending journal never exposes partial live state")
	expect(server.peers.is_empty(),"Commit failure never attaches a peer")
	var committed_world:=FileAccess.get_file_as_bytes(world_path)
	expect(committed_world!=baseline_world and FileAccess.get_file_as_bytes(roster_path)==baseline_members,"After-world checkpoint reproduces split files")
	server.save_clock=10.0
	server.directory_address="ws://127.0.0.1:8143"
	server.directory_dirty=true
	server.directory_clock=12.0
	server.identities[8]={"account_id":"owner","expires":Time.get_unix_time_from_system()+30}
	server.peers[8]=owner
	server.sequences[8]=0
	expect(not server.identity_allows_play(8),"Frozen admission denies otherwise current identity")
	server._action(8,1,"hoe",Vector2i(41,40),"")
	expect(server.sequences[8]==0,"Frozen gameplay leaves the request sequence untouched")
	server._physics_process(1.0)
	expect(server.save_clock==10.0 and FileAccess.get_file_as_bytes(world_path)==committed_world,"Frozen tick does not step or overwrite recovery state")
	server.tick_directory(1.0)
	server.publish_directory()
	expect(server.directory_clock==12.0 and server.directory_request==null and FileAccess.get_file_as_bytes(roster_path)==baseline_members,"Frozen publication neither starts a request nor writes roster revision")
	server._peer_left(8)
	expect(not server.peers.has(8) and not server.identities.has(8) and FileAccess.get_file_as_bytes(roster_path)==baseline_members and FileAccess.get_file_as_bytes(world_path)==committed_world,"Frozen peer departure clears live state without touching either save")
	var rejected:=Session.new()
	var api:="http://127.0.0.1:8142"
	expect(rejected.configure_identity(api,"test-island","test-secret",roster_path,"owner",true,null,world_path)==ERR_ALREADY_IN_USE,"Active writer excludes a second recovery attempt")
	expect(server.shutdown() and Store.has_pending(roster_path) and FileAccess.get_file_as_bytes(world_path)==committed_world,"Shutdown preserves the recovery journal and committed world")
	expect(rejected.configure_identity(api,"test-island","test-secret",roster_path,"owner",true)==ERR_INVALID_PARAMETER,"Pending admission requires the world path")
	expect(rejected.configure_identity(api,"test-island","test-secret",roster_path,"owner",true,null,folder.path_join("wrong.json"))==ERR_FILE_CORRUPT,"Pending admission rejects a different world path")
	expect(Store.has_pending(roster_path) and FileAccess.get_file_as_bytes(roster_path)==baseline_members and FileAccess.get_file_as_bytes(world_path)==committed_world and not FileAccess.file_exists(folder.path_join("wrong.json")),"Invalid recovery configuration leaves both originals and journal intact")
	var missing:=folder.path_join("missing-members.json")
	expect(rejected.configure_identity(api,"test-island","test-secret",missing,"owner",true,null,world_path)==ERR_FILE_CORRUPT and not FileAccess.file_exists(missing),"Existing world without roster cannot provision a new mapping")
	rejected.free()
	server.free()
	server=open_session()
	var guest:String=server.membership.read("guest").get("character","")
	expect(not guest.is_empty() and server.world.state.players.has(guest) and not Store.has_pending(roster_path),"Restart recovers guest on both sides")
	expect(server.world.state.players[owner].coins==271 and server.world.state.objects.get("40,40",{}).get("owner")==owner,"Recovery preserves owner money and ownership")
	server.world.state.players[guest].coins=131
	expect(server.world.save(),"Guest progress can be saved after recovery")
	var retry:Dictionary=server.commit_identity_admission(2,draft,"")
	expect(retry.ok and retry.get("character")==guest and server.world.state.players[guest].coins==131,"Retry preserves recovered character and progress")
	for account in ["friend-a","friend-b","friend-c","friend-d","friend-e","friend-f"]:
		var result:Dictionary=server.commit_identity_admission(3,{"account_id":account,"display_name":account},code)
		expect(result.ok,"Admits an available seat")
	baseline_world=FileAccess.get_file_as_bytes(world_path)
	baseline_members=FileAccess.get_file_as_bytes(roster_path)
	denied=server.commit_identity_admission(4,{"account_id":"extra","display_name":"多一位"},code)
	expect(not denied.ok and denied.code=="WORLD_FULL" and server.world.state.players.size()==8,"Ninth member has no seat or character")
	expect(FileAccess.get_file_as_bytes(world_path)==baseline_world and FileAccess.get_file_as_bytes(roster_path)==baseline_members,"Full world does not change either save")
	server.free()
	var main=preload("res://scripts/main.gd").new()
	main.village_art_preview=true
	root.add_child(main)
	main._open_identity()
	main.identity_entry.token="fixture"
	main.identity_entry.joining=true
	var recovery_message:="入島資料等待恢復，島嶼已暫停寫入。請待伺服器重啟後再加入。"
	main._identity_status({"operation":"join","ok":false,"code":"RECOVERING","message":recovery_message})
	main._disconnected()
	await process_frame
	expect(main.identity_entry.status.visible and main.identity_entry.status.text==recovery_message,"Recovery notice stays visible after disconnect")
	expect(not main.identity_entry.joining and main.identity_entry.token=="fixture","Recovery unlocks retry without logging out")
	main.free()
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)
	print("ADMISSION_SESSION_TEST checks=%d failures=%d" % [checks,failures])
	quit(int(failures>0))
