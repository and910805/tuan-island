extends RefCounted

const LIMIT := 3
const MISSING := "-"

static func canonical(path:String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path()

static func manifest_path(member_path:String) -> String:
	return canonical(member_path)+".admission-retention.json"

static func hex(value:Variant,length:int) -> bool:
	return value is String and value.length()==length and value.is_valid_hex_number(false) and value==value.to_lower()

static func linked(path:String) -> bool:
	var cursor:=path
	while not cursor.get_file().is_empty():
		var directory:=cursor.get_base_dir()
		var parent:=DirAccess.open(directory)
		if parent==null or parent.is_link(cursor.get_file()):return true
		cursor=directory
	return false

static func pending(member:String) -> bool:
	var path:=member+".admission-wal"
	return linked(path) or FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

static func archive_path(target:String,id:String) -> String:
	return target+".admission-previous-"+id

static func safe_targets(targets:Array[String],manifest:String,member:String) -> bool:
	var known:={}
	for path in targets+[manifest,member+".admission-wal"]:
		var key:String=path.to_lower() if OS.get_name()=="Windows" else path
		if not path.is_absolute_path() or known.has(key) or linked(path):return false
		known[key]=true
	return true

static func save_manifest(path:String,data:Dictionary) -> bool:
	var stage:=path+".stage-"+Crypto.new().generate_random_bytes(12).hex_encode()
	var file:=FileAccess.open(stage,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error:=file.get_error()
	file.close()
	if error==OK and DirAccess.rename_absolute(stage,path)==OK:return true
	DirAccess.remove_absolute(stage)
	return false

static func valid_entry(entry:Variant) -> bool:
	if not entry is Dictionary or entry.size()!=2 or not hex(entry.get("id"),32):return false
	var hashes:Variant=entry.get("hashes")
	if not hashes is Array or hashes.size()!=3:return false
	for hash_value in hashes:
		if hash_value!=MISSING and not hex(hash_value,64):return false
	return true

static func verify_bundle(entry:Dictionary,targets:Array[String],allow_missing:bool) -> bool:
	for index in targets.size():
		var path:=archive_path(targets[index],entry.id)
		if linked(path) or DirAccess.dir_exists_absolute(path):return false
		var exists:=FileAccess.file_exists(path)
		var expected:String=entry.hashes[index]
		if expected==MISSING:
			if exists:return false
		elif not exists:
			if not allow_missing:return false
		elif FileAccess.get_sha256(path)!=expected:return false
	return true

static func record_completed(world_path:String,member_path:String,record:Dictionary) -> Dictionary:
	var failed:={"ok":false,"cleaned":0,"retained":0}
	if world_path.is_empty() or member_path.is_empty():return failed
	var world:=canonical(world_path)
	var member:=canonical(member_path)
	var manifest:=manifest_path(member)
	var targets:Array[String]=[world,world+".bak",member]
	if not safe_targets(targets,manifest,member) or pending(member):return failed
	if record.get("world_path")!=world or record.get("member_path")!=member:return failed
	if not record.get("world") is String or not record.get("members") is String:return failed
	if FileAccess.get_sha256(world)!=record.world.sha256_text() or FileAccess.get_sha256(world+".bak")!=record.world.sha256_text() or FileAccess.get_sha256(member)!=record.members.sha256_text():return failed
	var prior:Variant=record.get("before")
	if not prior is Array or prior.size()!=3:return failed
	var hashes:=[]
	for item in prior:
		if not item is Dictionary:return failed
		hashes.append(item.get("hash"))
	var entry:={"id":record.get("transaction"),"hashes":hashes}
	if not valid_entry(entry) or not verify_bundle(entry,targets,false):return failed
	var state:={"version":1,"world_path":world,"member_path":member,"bundles":[],"pruning":[]}
	if FileAccess.file_exists(manifest):
		var file:=FileAccess.open(manifest,FileAccess.READ)
		if file==null or file.get_length()>65536:return failed
		var parser:=JSON.new()
		if parser.parse(file.get_as_text())!=OK:return failed
		var loaded:Variant=parser.data
		if not loaded is Dictionary or loaded.size()!=5 or loaded.get("version")!=1 or loaded.get("world_path")!=world or loaded.get("member_path")!=member:return failed
		if not loaded.get("bundles") is Array or loaded.bundles.size()>LIMIT or not loaded.get("pruning") is Array:return failed
		state=loaded
	var known:={}
	for bundle in state.bundles+state.pruning:
		if not valid_entry(bundle) or known.has(bundle.id):return failed
		known[bundle.id]=bundle
	if known.has(entry.id):
		if not state.bundles.has(entry):return failed
	else:
		state.bundles.append(entry)
	while state.bundles.size()>LIMIT:
		state.pruning.append(state.bundles.pop_front())
	for bundle in state.bundles:
		if not verify_bundle(bundle,targets,false):return failed
	for bundle in state.pruning:
		if not verify_bundle(bundle,targets,true):return failed
	if pending(member) or not save_manifest(manifest,state):return failed
	var cleaned:=0
	for bundle in state.pruning:
		if pending(member) or not verify_bundle(bundle,targets,true):return {"ok":false,"cleaned":cleaned,"retained":state.bundles.size()}
		for index in targets.size():
			if bundle.hashes[index]==MISSING:continue
			var path:=archive_path(targets[index],bundle.id)
			if FileAccess.file_exists(path) and DirAccess.remove_absolute(path)!=OK:
				return {"ok":false,"cleaned":cleaned,"retained":state.bundles.size()}
		cleaned+=1
	state.pruning.clear()
	if cleaned>0 and not save_manifest(manifest,state):
		return {"ok":false,"cleaned":cleaned,"retained":state.bundles.size()}
	return {"ok":true,"cleaned":cleaned,"retained":state.bundles.size()}
