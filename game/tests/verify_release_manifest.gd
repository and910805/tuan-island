extends SceneTree
const Checker=preload("res://scripts/version_update_checker.gd")
func _initialize()->void:
	var path:=OS.get_environment("TUAN_SIGNED_RELEASE_FIXTURE")
	assert(not path.is_empty())
	var key:=Checker.installed_public_key()
	assert(key!=null and key.is_public_only())
	var wire:=FileAccess.get_file_as_bytes(path)
	var info:=Checker.verify_manifest(wire,key,"0.50.20-dev")
	assert(info.get("latest_version","")=="0.50.22-dev" and info.get("required",false))
	assert(info.get("binary_hashes",{}).size()==2)
	assert(Checker.verify_manifest(wire,key,"0.50.22-dev").is_empty())
	print("PINNED_RELEASE_MANIFEST_PASS production public key verifies actual r22 archive, current version ignored")
	quit(0)
