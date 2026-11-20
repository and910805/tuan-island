extends SceneTree
const Checker=preload("res://scripts/version_update_checker.gd")
const RELEASE_PREFIX:="https://github.com/and910805/tuan-island/releases/download/"
const OLDEST_VERSION:="0.0.0"
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()

# Optional deployment verification: --expected-version=X or --expected-version X (after "--").
func expected_version()->String:
	var args:=OS.get_cmdline_user_args()
	for i in range(args.size()):
		var arg:String=args[i]
		if arg.begins_with("--expected-version="):return arg.trim_prefix("--expected-version=")
		if arg=="--expected-version":return args[i+1] if i+1<args.size() else "<missing>"
	return ""

# Release naming convention for "A.B.N-dev" is tag "vA.B-dev-rN", asset "TuanIslandWindows-A.B-dev-rN.zip".
func expected_archive_url(latest:String)->String:
	var parts:=Checker.version_parts(latest)
	if parts.size()!=3 or not latest.ends_with("-dev") or latest.count(".")!=2:return ""
	var label:="%d.%d-dev-r%d"%[parts[0],parts[1],parts[2]]
	return "%sv%s/TuanIslandWindows-%s.zip"%[RELEASE_PREFIX,label,label]

func reencode(wire:PackedByteArray,field:String,bit_index:int)->PackedByteArray:
	var envelope:=JSON.new()
	if envelope.parse(wire.get_string_from_utf8())!=OK or not envelope.data is Dictionary:return PackedByteArray()
	var signed:Dictionary=envelope.data.duplicate()
	var raw:=Marshalls.base64_to_raw(str(signed.get(field,"")))
	if raw.is_empty():return PackedByteArray()
	raw[bit_index%raw.size()]=raw[bit_index%raw.size()]^1
	signed[field]=Marshalls.raw_to_base64(raw)
	return JSON.stringify(signed).to_utf8_buffer()

func run()->void:
	var key:=Checker.installed_public_key()
	expect(key!=null and key.is_public_only(),"Pinned public key loads; no private key in resource")
	var url:=str(ProjectSettings.get_setting("application/config/update_manifest_url",""))
	expect(url=="https://raw.githubusercontent.com/and910805/tuan-island/update-feed/windows-manifest.json","Configured exact public HTTPS feed")
	var wanted:=expected_version()
	var request:=HTTPRequest.new()
	request.timeout=15.0
	request.max_redirects=0
	request.body_size_limit=Checker.MAX_MANIFEST_BYTES
	root.add_child(request)
	var started:=request.request(url)==OK
	expect(started,"Start real public HTTPS request")
	if not started:
		print("PUBLIC_UPDATE_FEED checks=%d failures=%d"%[checks,failures])
		quit(1)
		return
	var result:Array=await request.request_completed
	expect(result[0]==HTTPRequest.RESULT_SUCCESS and result[1]==200,"Public feed responds directly without redirect")
	var verified:=""
	if result[0]==HTTPRequest.RESULT_SUCCESS and result[1]==200 and key!=null:
		var wire:PackedByteArray=result[3]
		# Signature is checked inside verify_manifest before any payload field is trusted;
		# the oldest possible build makes the signed latest version observable.
		var info:=Checker.verify_manifest(wire,key,OLDEST_VERSION)
		expect(not info.is_empty(),"Signed feed authenticates and offers a published version")
		if not info.is_empty():
			var latest:String=info.get("latest_version","")
			var minimum:String=info.get("minimum_version","")
			verified=latest
			expect(Checker.version_parts(latest).size()==3 and Checker.version_parts(minimum).size()==3,"Signed latest and minimum versions are valid")
			expect(not Checker.version_is_older(latest,minimum),"Signed latest is not older than signed minimum")
			if not wanted.is_empty():
				expect(latest==wanted,"Signed latest equals expected deployed version %s"%wanted)
			var archive:Dictionary=info.get("archive",{})
			var archive_url:String=archive.get("url","")
			expect(Checker.valid_https_url(archive_url) and archive_url.begins_with(RELEASE_PREFIX) and archive_url.ends_with(".zip"),"Signed ZIP is an HTTPS public release artifact")
			expect(archive_url==expected_archive_url(latest),"Signed ZIP names exact versioned artifact for published latest")
			expect(Checker.valid_https_url(str(info.get("download_url",""))),"Signed download URL is HTTPS")
			expect(int(archive.get("bytes",0))>0 and Checker.valid_checksum(archive.get("sha256","")),"Signed ZIP length and SHA-256 are present")
			var hashes:Dictionary=info.get("binary_hashes",{})
			expect(hashes.size()==2 and hashes.has("TuanIsland.exe") and hashes.has("island_world_lock.dll"),"Both game and storage DLL hashes are signed")
			for name in hashes:
				expect(Checker.valid_checksum(hashes[name]),"Valid signed SHA-256 for %s"%name)
			expect(Checker.verify_manifest(wire,key,latest).is_empty(),"Current published build gets no repeated update prompt")
			expect(Checker.verify_manifest(wire,key,minimum).get("required",false)==false,"Minimum supported build is not forced to update")
			var bad_payload:=reencode(wire,"payload",0)
			var bad_signature:=reencode(wire,"signature",0)
			expect(not bad_payload.is_empty() and Checker.verify_manifest(bad_payload,key,OLDEST_VERSION).is_empty(),"One-bit payload change fails signature")
			expect(not bad_signature.is_empty() and Checker.verify_manifest(bad_signature,key,OLDEST_VERSION).is_empty(),"One-bit signature change is rejected")
			var crypto:=Crypto.new()
			var other:=CryptoKey.new()
			other.load_from_string(crypto.generate_rsa(2048).save_to_string(true),true)
			expect(Checker.verify_manifest(wire,other,OLDEST_VERSION).is_empty(),"Different key rejects public feed")
	request.queue_free()
	if failures==0 and not verified.is_empty():print("PUBLIC_UPDATE_FEED verified_version=%s"%verified)
	print("PUBLIC_UPDATE_FEED checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
