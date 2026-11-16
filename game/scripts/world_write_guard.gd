extends RefCounted

# Every supported server acquires OS-backed locks before reading or migrating
# world/member files. The stable sidecars must never be deleted while in use.
var handles: Array[Object] = []
var resources: Array[String] = []

static func canonical(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path()

func acquire(paths: Array[String]) -> Error:
	var requested: Array[String] = []
	for path in paths:
		if path.is_empty():return ERR_INVALID_PARAMETER
		var target := canonical(path)
		if OS.get_name()=="Windows":target=target.to_lower()
		if not requested.has(target):requested.append(target)
	requested.sort()
	if requested.is_empty():return ERR_INVALID_PARAMETER
	if not handles.is_empty():
		for path in requested:
			if not resources.has(path):return ERR_ALREADY_IN_USE
		return OK if is_held() else ERR_CANT_OPEN
	if not ClassDB.class_exists("IslandFileLock") and FileAccess.file_exists("res://addons/world_lock/world_lock.gdextension"):
		GDExtensionManager.load_extension("res://addons/world_lock/world_lock.gdextension")
	if not ClassDB.class_exists("IslandFileLock"):return ERR_UNAVAILABLE
	for target in requested:
		var handle: Object = ClassDB.instantiate("IslandFileLock")
		if handle == null:
			release()
			return ERR_UNAVAILABLE
		var status: int = handle.call("acquire",target+".writer-lock")
		if status != OK:
			handle.call("release")
			release()
			return status as Error
		handles.append(handle)
	resources=requested
	return OK

func is_held() -> bool:
	if handles.is_empty():return false
	for handle in handles:
		if not is_instance_valid(handle) or not handle.call("is_held"):return false
	return true

func release() -> void:
	for handle in handles:
		if is_instance_valid(handle):handle.call("release")
	handles.clear()
	resources.clear()
