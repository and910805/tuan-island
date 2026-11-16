extends SceneTree
const Guard=preload("res://scripts/world_write_guard.gd")
var checks:=0
var failures:=0
func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize()->void:
	var folder:=OS.get_environment("TEMP").path_join("guard-"+Crypto.new().generate_random_bytes(10).hex_encode())
	DirAccess.make_dir_recursive_absolute(folder)
	var first:=folder.path_join("a-world.json")
	var second:=folder.path_join("b-members.json")
	var one:=Guard.new()
	var two:=Guard.new()
	expect(one.acquire([first])==OK and one.is_held(),"Acquire real native lock")
	expect(two.acquire([first])==ERR_ALREADY_IN_USE and not two.is_held(),"Separate guard cannot acquire same resource")
	expect(two.acquire([folder.path_join("./a-world.json")])==ERR_ALREADY_IN_USE,"Canonical alias contends")
	if OS.get_name()=="Windows":
		expect(two.acquire([first.to_upper()])==ERR_ALREADY_IN_USE,"Windows case alias contends")
	expect(two.acquire([second])==OK and two.is_held(),"Independent resources coexist")
	one.release()
	expect(one.acquire([first,second])==ERR_ALREADY_IN_USE and not one.is_held(),"Failure on second lock rolls back first")
	var probe:=Guard.new()
	expect(probe.acquire([first])==OK,"First lock is reusable after rollback")
	probe.release()
	two.release()
	expect(one.acquire([first,second])==OK and one.is_held(),"Both resources are reusable")
	one.release()
	for name in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	print("WORLD_WRITE_GUARD_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
