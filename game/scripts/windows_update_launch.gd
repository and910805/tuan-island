extends RefCounted

const Stage=preload("res://scripts/windows_update_stage.gd")
const Checker=preload("res://scripts/version_update_checker.gd")
const STARTUP_TIMEOUT:=12.0
const ACTIVE_RELEASE:="active-release.json"

static func ready_directory(folder:String,root:String)->bool:
	var clean:=folder.replace("\\","/").simplify_path()
	var expected:=ProjectSettings.globalize_path(root).replace("\\","/").simplify_path()
	var name:=clean.get_file()
	return clean.get_base_dir().to_lower()==expected.to_lower() and name.begins_with("ready-") and valid_nonce(name.trim_prefix("ready-"))

static func valid_nonce(nonce:String)->bool:
	return nonce.length()==24 and nonce.is_valid_hex_number(false)

static func accept_startup(nonce:String,root:String=Stage.INSTALL_ROOT)->bool:
	var executable:=OS.get_executable_path()
	var folder:=executable.get_base_dir()
	if executable.get_file()!=Stage.GAME_EXE or not ready_directory(folder,root) or not valid_nonce(nonce):
		return false
	var marker:=FileAccess.open(marker_path(folder,nonce),FileAccess.WRITE)
	if marker==null or not marker.store_string(nonce):return false
	marker.flush()
	return marker.get_error()==OK

static func launch(tree:SceneTree,prepared:Dictionary,root:String=Stage.INSTALL_ROOT,timeout:float=STARTUP_TIMEOUT,commit:Callable=Callable())->bool:
	if OS.get_name()!="Windows":return false
	var directory:String=prepared.get("directory","")
	if not ready_directory(directory,root):return false
	var hashes:Dictionary=prepared.get("hashes",{})
	for name in [Stage.GAME_EXE,Stage.STORAGE_DLL]:
		var expected:String=hashes.get(name,"")
		if expected.is_empty() or FileAccess.get_sha256(directory.path_join(name))!=expected:return false
	var nonce:=Crypto.new().generate_random_bytes(12).hex_encode()
	if not valid_nonce(nonce):return false
	var marker:=marker_path(directory,nonce)
	var pid:=OS.create_process(directory.path_join(Stage.GAME_EXE),["--","--update-startup="+nonce])
	if pid<=0:return false
	var deadline:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<deadline and OS.is_process_running(pid):
		if acknowledged(marker,nonce):
			if not commit.is_valid() or commit.call():return true
			break
		await tree.create_timer(0.1).timeout
	if OS.is_process_running(pid):
		if acknowledged(marker,nonce) and (not commit.is_valid() or commit.call()):return true
		OS.kill(pid)
	if FileAccess.file_exists(marker):DirAccess.remove_absolute(marker)
	return false

static func remember(prepared:Dictionary,signed_manifest:String,public_key:CryptoKey,current_version:String,root:String=Stage.INSTALL_ROOT)->bool:
	var directory:String=prepared.get("directory","")
	if not ready_directory(directory,root):return false
	var verified:=Checker.verify_manifest(signed_manifest.to_utf8_buffer(),public_key,current_version)
	if not verified.has("binary_hashes") or verified.binary_hashes!=prepared.get("hashes",{}):return false
	var marker:=directory.path_join(ACTIVE_RELEASE)
	if FileAccess.file_exists(marker):return FileAccess.get_file_as_string(marker)==signed_manifest
	var temporary:=marker+"."+Crypto.new().generate_random_bytes(12).hex_encode()
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:return false
	var written:=file.store_string(signed_manifest)
	file.flush()
	var flushed:=file.get_error()==OK
	file.close()
	if written and flushed and DirAccess.rename_absolute(temporary,marker)==OK:return true
	DirAccess.remove_absolute(temporary)
	return false

static func remembered(public_key:CryptoKey,current_version:String,root:String=Stage.INSTALL_ROOT)->Array[Dictionary]:
	var candidates:Array[Dictionary]=[]
	if public_key==null:return candidates
	var base:=ProjectSettings.globalize_path(root)
	var directory:=DirAccess.open(base)
	if directory==null:return candidates
	for name in directory.get_directories():
		var folder:=base.path_join(name)
		if not ready_directory(folder,root):continue
		if folder.replace("\\","/").to_lower()==OS.get_executable_path().get_base_dir().replace("\\","/").to_lower():continue
		var file:=FileAccess.open(folder.path_join(ACTIVE_RELEASE),FileAccess.READ)
		if file==null or file.get_length()>Checker.MAX_MANIFEST_BYTES:continue
		var verified:=Checker.verify_manifest(file.get_buffer(file.get_length()),public_key,current_version)
		if verified.has("binary_hashes"):
			candidates.append({"directory":folder,"hashes":verified.binary_hashes,"version":verified.latest_version})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return Checker.version_is_older(b.version,a.version))
	return candidates

static func marker_path(directory:String,nonce:String)->String:
	return directory.path_join("startup-"+nonce+".ack")

static func acknowledged(marker:String,nonce:String)->bool:
	if not FileAccess.file_exists(marker) or FileAccess.get_file_as_string(marker)!=nonce:return false
	DirAccess.remove_absolute(marker)
	return true
