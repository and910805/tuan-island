extends RefCounted

const Checker=preload("res://scripts/version_update_checker.gd")
const GAME_EXE:="TuanIsland.exe"
const STORAGE_DLL:="island_world_lock.dll"
const INSTALL_ROOT:="user://windows-updates"

static func prepare(source:String,archive:Dictionary,root:String=INSTALL_ROOT)->Dictionary:
	var base:=ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(base)!=OK:
		return failed("無法建立更新資料夾。")
	var id:=Crypto.new().generate_random_bytes(12).hex_encode()
	if id.is_empty():return failed("無法建立更新資料夾。")
	var temporary:=base.path_join(".stage-"+id)
	if DirAccess.make_dir_absolute(temporary)!=OK:
		return failed("無法建立更新資料夾。")
	var copied:=temporary.path_join("package.zip")
	var result:=failed("封包與已驗簽的清單不符。")
	if copy_package(source,copied,int(archive.get("bytes",-1))) and Checker.verify_archive(copied,archive):
		if unpack_client(copied,temporary) and DirAccess.remove_absolute(copied)==OK:
			var binary_hashes:={}
			for filename in [GAME_EXE,STORAGE_DLL]:
				binary_hashes[filename]=FileAccess.get_sha256(temporary.path_join(filename))
			var ready:=base.path_join("ready-"+id)
			if DirAccess.rename_absolute(temporary,ready)==OK:
				return {"ok":true,"directory":ready,"hashes":binary_hashes}
			result=failed("無法保存準備好的更新。")
		else:
			result=failed("更新封包缺少完整的遊戲程式或存檔元件。")
	for name in ["package.zip",GAME_EXE,STORAGE_DLL]:
		var path:=temporary.path_join(name)
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(temporary)
	return result

static func copy_package(source:String,target:String,remaining:int)->bool:
	var input:=FileAccess.open(source,FileAccess.READ)
	if input==null or remaining<1 or input.get_length()!=remaining:return false
	var output:=FileAccess.open(target,FileAccess.WRITE)
	if output==null:return false
	while remaining>0:
		var length:=mini(remaining,1048576)
		var chunk:=input.get_buffer(length)
		if chunk.size()!=length or not output.store_buffer(chunk):return false
		remaining-=length
	output.flush()
	return output.get_error()==OK and input.get_buffer(1).is_empty()

static func unpack_client(package:String,folder:String)->bool:
	var zip:=ZIPReader.new()
	if zip.open(package)!=OK:return false
	var executable:=""
	var members:=zip.get_files()
	for entry in members:
		if entry.get_file() not in [GAME_EXE,"糰糰島.exe"]:continue
		if not executable.is_empty():
			zip.close()
			return false
		executable=entry
	if executable.is_empty():
		zip.close()
		return false
	var library:=executable.get_base_dir().path_join(STORAGE_DLL)
	var ok:=library in members and write_binary(zip.read_file(executable),folder.path_join(GAME_EXE))
	if ok:ok=write_binary(zip.read_file(library),folder.path_join(STORAGE_DLL))
	zip.close()
	return ok

static func write_binary(data:PackedByteArray,path:String)->bool:
	if data.size()<2 or data[0]!=0x4d or data[1]!=0x5a:return false
	var output:=FileAccess.open(path,FileAccess.WRITE)
	if output==null or not output.store_buffer(data):return false
	output.flush()
	return output.get_error()==OK

static func failed(message:String)->Dictionary:
	return {"ok":false,"message":message}
