extends SceneTree
const Session=preload("res://scripts/session.gd")
class FaultStore extends "res://scripts/admission_store.gd":
	func checkpoint(stage:String)->bool:
		return stage!="afterworld"
func _initialize()->void:
	run.call_deferred()
func run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	var server:=Session.new()
	island.add_child(server)
	if server.configure_identity(data.api,data.world,FileAccess.get_file_as_string(data.key),data.roster,data.owner,true,null,data.save)!=OK:
		quit(1)
		return
	if server.configure_directory(data.address,"蜜糖島","生活",true)!=OK:
		quit(1)
		return
	server.admission_store=FaultStore.new()
	if server.host(int(data.port),"",data.save,"","127.0.0.1",true,"websocket")!=OK:quit(1)
