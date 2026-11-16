extends Node

signal update_available(info:Dictionary)

const VERSION_PATTERN:="^(\\d+)\\.(\\d+)(?:\\.(\\d+))?(?:[-+][0-9A-Za-z.-]+)?$"

static func valid_https_url(value:String) -> bool:
	if value.is_empty() or value.contains("\\") or value.contains("?") or value.contains("#"):
		return false
	for character in value:
		if character.unicode_at(0)<=32 or character.unicode_at(0)==127:return false
	var parts:=value.split("://",true,1)
	if parts.size()!=2 or parts[0]!="https":return false
	var authority:=parts[1].get_slice("/",0)
	return not authority.is_empty() and not authority.contains("@") and not authority.contains("%")

static func version_parts(value:String) -> PackedInt32Array:
	var expression:=RegEx.new()
	if expression.compile(VERSION_PATTERN)!=OK:return PackedInt32Array()
	var found:=expression.search(value)
	if found==null:return PackedInt32Array()
	var patch:=0 if found.get_string(3).is_empty() else int(found.get_string(3))
	return PackedInt32Array([int(found.get_string(1)),int(found.get_string(2)),patch])

static func version_is_older(current:String,required:String) -> bool:
	var have:=version_parts(current)
	var need:=version_parts(required)
	if have.size()!=3 or need.size()!=3:return false
	for i in range(3):
		if have[i]<need[i]:return true
		if have[i]>need[i]:return false
	return false

static func interpret_manifest(value:Variant,current_version:String) -> Dictionary:
	if not value is Dictionary:return {}
	var latest:=str(value.get("latest_version",""))
	var minimum:=str(value.get("minimum_version",""))
	var download:=str(value.get("download_url",""))
	if version_parts(latest).size()!=3 or version_parts(minimum).size()!=3 or not valid_https_url(download):return {}
	if not version_is_older(current_version,latest):return {}
	return {
		"current_version":current_version,
		"latest_version":latest,
		"minimum_version":minimum,
		"download_url":download,
		"required":version_is_older(current_version,minimum)
	}

func check(manifest_url:String,current_version:String) -> void:
	if not valid_https_url(manifest_url) or version_parts(current_version).size()!=3:return
	var request:=HTTPRequest.new()
	request.timeout=8.0
	request.max_redirects=0
	request.body_size_limit=16384
	add_child(request)
	if request.request(manifest_url,[],HTTPClient.METHOD_GET)!=OK:
		request.queue_free()
		return
	var result:Array=await request.request_completed
	request.queue_free()
	if result[0]!=HTTPRequest.RESULT_SUCCESS or result[1]!=200:return
	var value:Variant=JSON.parse_string(result[3].get_string_from_utf8())
	var info:=interpret_manifest(value,current_version)
	if not info.is_empty():update_available.emit(info)
