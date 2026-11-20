extends SceneTree
const Retention=preload("res://scripts/admission_retention.gd")
var checks:=0
var failures:=0
var folder:String
var world:String
var members:String

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func write(path:String,value:String)->void:
	FileAccess.open(path,FileAccess.WRITE).store_string(value)

func bundle(n:int)->Dictionary:
	var id:="%032x"%n
	var targets:=[world,world+".bak",members]
	var before:=[]
	for index in targets.size():
		var content:="prior %d %d"%[n,index]
		write(Retention.archive_path(targets[index],id),content)
		before.append({"hash":content.sha256_text()})
	return {"world_path":world,"member_path":members,"transaction":id,"before":before,"world":"current world","members":"current roster"}

func _initialize()->void:
	folder=OS.get_environment("TEMP").path_join("retention-"+Crypto.new().generate_random_bytes(12).hex_encode())
	DirAccess.make_dir_recursive_absolute(folder)
	world=Retention.canonical(folder.path_join("world.json"))
	members=Retention.canonical(folder.path_join("members.json"))
	write(world,"current world")
	write(world+".bak","current world")
	write(members,"current roster")
	var unknown:=Retention.archive_path(world,"%032x"%999)
	write(unknown,"unregistered")
	for n in range(1,9):
		var result:=Retention.record_completed(world,members,bundle(n))
		check(result.ok and result.retained==mini(n,3),"Retention tracks at most three bundles")
		check(result.cleaned==int(n>3),"Retention retires exactly one oldest bundle when full")
	for n in range(1,9):
		for path in [world,world+".bak",members]:
			check(FileAccess.file_exists(Retention.archive_path(path,"%032x"%n))==(n>=6),"Only three newest bundle copies remain")
	check(FileAccess.get_file_as_string(unknown)=="unregistered","Unknown copy remains")
	check(FileAccess.get_file_as_string(world)=="current world" and FileAccess.get_file_as_string(world+".bak")=="current world" and FileAccess.get_file_as_string(members)=="current roster","Current files remain intact")
	var ninth:=bundle(9)
	var manifest:=Retention.manifest_path(members)
	var prior_manifest:=FileAccess.get_file_as_string(manifest)
	write(members+".admission-wal","pending")
	check(not Retention.record_completed(world,members,ninth).ok and FileAccess.get_file_as_string(manifest)==prior_manifest,"Pending WAL blocks changes")
	DirAccess.remove_absolute(members+".admission-wal")
	write(manifest,"invalid")
	check(not Retention.record_completed(world,members,ninth).ok and FileAccess.get_file_as_string(manifest)=="invalid","Tampered manifest remains intact")
	write(manifest,prior_manifest)
	var old:=Retention.archive_path(world,"%032x"%6)
	write(old,"tampered")
	check(not Retention.record_completed(world,members,ninth).ok and FileAccess.get_file_as_string(old)=="tampered" and FileAccess.get_file_as_string(manifest)==prior_manifest,"Archive hash mismatch prevents all deletion")
	write(old,"prior 6 0")
	check(Retention.record_completed(world,members,ninth).ok,"Restoring expected bytes permits cleanup")
	var tenth:=bundle(10)
	tenth.transaction="../unknown"
	check(not Retention.record_completed(world,members,tenth).ok,"Traversal ID denied")
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)
	print("ADMISSION_RETENTION_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
