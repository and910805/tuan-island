extends Node

signal update_available(info:Dictionary)

const VERSION_PATTERN:="^([0-9]{1,9})\\.([0-9]{1,9})(?:\\.([0-9]{1,9}))?(?:[-+][0-9A-Za-z.-]+)?$"
const MAX_MANIFEST_BYTES := 16384
const PUBLIC_KEY_PATH := "res://update-release-public.pem"

static func valid_https_url(value:String,allow_query:=false) -> bool:
	if value.is_empty() or value.contains("\\") or (not allow_query and value.contains("?")) or value.contains("#"):
		return false
	for character in value:
		if character.unicode_at(0)<=32 or character.unicode_at(0)==127:return false
	var parts:=value.split("://",true,1)
	if parts.size()!=2 or parts[0]!="https":return false
	var authority:=parts[1].get_slice("/",0).get_slice("?",0)
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

static func packaged_version(version:String,build:Variant) -> String:
	# Existing clients compare the numeric patch field and ignore suffixes.
	if not version.ends_with("-dev") or version.count(".")!=1 or version_parts(version).size()!=3:
		return version
	if not (build is int or build is float) or not is_finite(float(build)) or build<1 or build>999999 or build!=floorf(float(build)):
		return version
	return "%s.%d-dev"%[version.trim_suffix("-dev"),int(build)]

static func interpret_manifest(value:Variant,current_version:String) -> Dictionary:
	if not value is Dictionary:return {}
	var latest:=str(value.get("latest_version",""))
	var minimum:=str(value.get("minimum_version",""))
	var download:=str(value.get("download_url",""))
	if version_parts(latest).size()!=3 or version_parts(minimum).size()!=3 or not valid_https_url(download):return {}
	if version_is_older(latest,minimum):return {}
	if not version_is_older(current_version,latest):return {}
	return {
		"current_version":current_version,
		"latest_version":latest,
		"minimum_version":minimum,
		"download_url":download,
		"required":version_is_older(current_version,minimum)
	}

static func verify_manifest(body:PackedByteArray,public_key:CryptoKey,current_version:String)->Dictionary:
	if public_key==null or not public_key.is_public_only() or body.size()>MAX_MANIFEST_BYTES:return {}
	var envelope:=JSON.new()
	if envelope.parse(body.get_string_from_utf8())!=OK or not envelope.data is Dictionary:return {}
	var signed:Dictionary=envelope.data
	if signed.get("algorithm")!="rsa-sha256" or not signed.get("payload") is String or not signed.get("signature") is String:return {}
	var payload:=Marshalls.base64_to_raw(signed.payload)
	var signature:=Marshalls.base64_to_raw(signed.signature)
	if payload.is_empty() or signature.is_empty():return {}
	var hash_context:=HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(payload)
	if not Crypto.new().verify(HashingContext.HASH_SHA256,hash_context.finish(),signature,public_key):return {}
	var manifest:=JSON.new()
	if manifest.parse(payload.get_string_from_utf8())!=OK:return {}
	var info:=interpret_manifest(manifest.data,current_version)
	if info.is_empty():return info
	var archive:=archive_details(manifest.data)
	if not archive.is_empty():info.archive=archive
	var hashes:=binary_hashes(manifest.data)
	if not hashes.is_empty():
		info.binary_hashes=hashes
		info.signed_manifest=body.get_string_from_utf8()
	return info

static func binary_hashes(value:Dictionary)->Dictionary:
	var hashes:Variant=value.get("windows_binary_sha256")
	if not hashes is Dictionary or hashes.size()!=2:return {}
	var result:={}
	for filename in ["TuanIsland.exe","island_world_lock.dll"]:
		var checksum:Variant=hashes.get(filename)
		if not valid_checksum(checksum):return {}
		result[filename]=checksum.to_lower()
	return result

static func valid_checksum(checksum:Variant)->bool:
	return checksum is String and checksum.length()==64 and checksum.is_valid_hex_number(false)

static func archive_details(value:Dictionary)->Dictionary:
	var length:Variant=value.get("windows_archive_bytes")
	var checksum:Variant=value.get("windows_archive_sha256")
	if not (length is float or length is int) or not is_finite(float(length)) or length<1 or length>9007199254740991 or floorf(float(length))!=float(length):return {}
	if not valid_checksum(checksum):return {}
	var result:={"bytes":int(length),"sha256":checksum.to_lower()}
	var url:Variant=value.get("windows_archive_url","")
	if url is String and valid_https_url(url):result.url=url
	return result

static func verify_archive(path:String,archive:Dictionary)->bool:
	var expected:String=archive.get("sha256","")
	var remaining:=int(archive.get("bytes",-1))
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or remaining<1 or expected.is_empty() or file.get_length()!=remaining:return false
	var digest:=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	while remaining>0:
		var size:=mini(remaining,1048576)
		var chunk:=file.get_buffer(size)
		if chunk.size()!=size:return false
		digest.update(chunk)
		remaining-=size
	return file.get_buffer(1).is_empty() and digest.finish().hex_encode()==expected

static func installed_public_key()->CryptoKey:
	if not FileAccess.file_exists(PUBLIC_KEY_PATH):return null
	var key:=CryptoKey.new()
	return key if key.load(PUBLIC_KEY_PATH,true)==OK else null

func check(manifest_url:String,current_version:String) -> void:
	if not valid_https_url(manifest_url) or version_parts(current_version).size()!=3:return
	var key:=installed_public_key()
	if key==null:return
	var request:=HTTPRequest.new()
	request.timeout=8.0
	request.max_redirects=0
	request.body_size_limit=MAX_MANIFEST_BYTES
	add_child(request)
	if request.request(manifest_url,[],HTTPClient.METHOD_GET)!=OK:
		request.queue_free()
		return
	var result:Array=await request.request_completed
	request.queue_free()
	if result[0]!=HTTPRequest.RESULT_SUCCESS or result[1]!=200:return
	var info:=verify_manifest(result[3],key,current_version)
	if not info.is_empty():update_available.emit(info)
