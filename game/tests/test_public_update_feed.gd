extends SceneTree
const Checker=preload("res://scripts/version_update_checker.gd")
var checks:=0
var failures:=0
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var key:=Checker.installed_public_key()
	expect(key!=null and key.is_public_only(),"Pinned public key loads; no private key in resource")
	var url:=str(ProjectSettings.get_setting("application/config/update_manifest_url",""))
	expect(url=="https://raw.githubusercontent.com/and910805/tuan-island/update-feed/windows-manifest.json","Configured exact public HTTPS feed")
	var request:=HTTPRequest.new()
	request.timeout=15.0
	request.max_redirects=0
	request.body_size_limit=Checker.MAX_MANIFEST_BYTES
	root.add_child(request)
	expect(request.request(url)==OK,"Start real public HTTPS request")
	var result:Array=await request.request_completed
	expect(result[0]==HTTPRequest.RESULT_SUCCESS and result[1]==200,"Public feed responds directly without redirect")
	if result[0]==HTTPRequest.RESULT_SUCCESS and result[1]==200 and key!=null:
		var wire:PackedByteArray=result[3]
		var info:=Checker.verify_manifest(wire,key,"0.50.20-dev")
		expect(not info.is_empty() and info.get("required",false),"Older supported checker verifies signed required update")
		expect(info.get("latest_version","")=="0.50.22-dev","Feed offers actual r22 package")
		expect(info.get("archive",{}).get("url","")=="https://github.com/and910805/tuan-island/releases/download/v0.50-dev-r22/TuanIslandWindows-0.50-dev-r22.zip","Signed ZIP names exact versioned public artifact")
		expect(info.get("binary_hashes",{}).size()==2,"Both game and storage DLL hashes are signed")
		expect(Checker.verify_manifest(wire,key,"0.50.22-dev").is_empty(),"Current build gets no repeated update prompt")
		var changed:=wire.duplicate()
		changed[changed.size()/2]=changed[changed.size()/2]^1
		expect(Checker.verify_manifest(changed,key,"0.50.20-dev").is_empty(),"Modified public response cannot authorize an update")
		var crypto:=Crypto.new()
		var other:=CryptoKey.new()
		other.load_from_string(crypto.generate_rsa(2048).save_to_string(true),true)
		expect(Checker.verify_manifest(wire,other,"0.50.20-dev").is_empty(),"Different key rejects public feed")
	request.queue_free()
	print("PUBLIC_UPDATE_FEED checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
