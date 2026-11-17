extends SceneTree

const Main=preload("res://scripts/main.gd")
const Checker=preload("res://scripts/version_update_checker.gd")
const Transfer=preload("res://scripts/windows_update_download.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func check(ok:bool,description:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr(description)

func has_text(node:Node,wanted:String) -> bool:
	if node is Label and (node as Label).text.contains(wanted):return true
	if node is Button and (node as Button).text==wanted:return true
	for child in node.get_children():
		if has_text(child,wanted):return true
	return false

func verify_signed_manifest() -> void:
	var crypto:=Crypto.new()
	var signing_key:=crypto.generate_rsa(2048)
	var public_key:=CryptoKey.new()
	check(public_key.load_from_string(signing_key.save_to_string(true),true)==OK,"Can load the release public key")
	var payload:=JSON.stringify({"latest_version":"0.52","minimum_version":"0.51","download_url":"https://updates.example.test/game","windows_archive_bytes":4,"windows_archive_sha256":"test".sha256_text()}).to_utf8_buffer()
	var hash_context:=HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(payload)
	var signature:=crypto.sign(HashingContext.HASH_SHA256,hash_context.finish(),signing_key)
	var envelope:={"algorithm":"rsa-sha256","payload":Marshalls.raw_to_base64(payload),"signature":Marshalls.raw_to_base64(signature)}
	var wire:=JSON.stringify(envelope).to_utf8_buffer()
	var verified:=Checker.verify_manifest(wire,public_key,"0.50")
	check(verified.get("required",false),"Valid signature allows the update")
	check(verified.get("archive",{}).get("sha256","")=="test".sha256_text(),"Archive details are taken from signed bytes")
	check(Checker.verify_manifest(wire,null,"0.50").is_empty(),"Missing trust anchor prevents update")
	check(Checker.verify_manifest(payload,public_key,"0.50").is_empty(),"Unsigned response never produces an update")
	var tampered:=payload.get_string_from_utf8().replace("0.52","0.99").to_utf8_buffer()
	envelope.payload=Marshalls.raw_to_base64(tampered)
	check(Checker.verify_manifest(JSON.stringify(envelope).to_utf8_buffer(),public_key,"0.50").is_empty(),"Changed signed bytes fail verification")
	var other:=CryptoKey.new()
	other.load_from_string(crypto.generate_rsa(2048).save_to_string(true),true)
	check(Checker.verify_manifest(wire,other,"0.50").is_empty(),"An unrelated release key cannot verify the envelope")

func run() -> void:
	verify_signed_manifest()
	check(Transfer.redirect_url("https://updates.example.test?first=1",PackedStringArray(["Location: /bundle.zip?second=2"]))=="https://updates.example.test/bundle.zip?second=2","HTTPS relative download redirect preserves the destination query")
	check(Transfer.redirect_url("https://updates.example.test/entry",PackedStringArray(["Location: http://updates.example.test/bundle.zip"])).is_empty(),"Download cannot downgrade to HTTP")
	check(Checker.version_is_older("0.50-dev","0.51"),"Development build compares lower than next release")
	check(not Checker.version_is_older("0.51","0.50"),"Newer client is not outdated")
	check(not Checker.version_is_older("0.50","0.50.0"),"Equivalent versions compare equal")
	var r10:=Checker.packaged_version("0.50-dev",10)
	var r11:=Checker.packaged_version("0.50-dev",11.0)
	check(r10=="0.50.10-dev" and r11=="0.50.11-dev" and Checker.version_is_older(r10,r11),"Development packages sort by build")
	check(Checker.version_is_older("0.50-dev",r11) and Checker.version_is_older(r11,"0.51"),"Legacy development and next minor release keep their order")
	check(Checker.packaged_version("0.50.4",11)=="0.50.4","Stable patch numbers are left intact")
	var newer_build:={"latest_version":r11,"minimum_version":r10,"download_url":"https://updates.example.test/game"}
	check(Checker.interpret_manifest(newer_build,r10).get("latest_version")==r11,"An earlier build gets the update")
	check(Checker.interpret_manifest(newer_build,r11).is_empty(),"The latest build does not get its own update")
	check(Checker.version_parts("bad").is_empty(),"Malformed version rejected")
	check(Checker.version_parts("0.4294967296").is_empty(),"Oversized component cannot wrap into a valid release")
	check(Checker.valid_https_url("https://updates.example.test/manifest.json"),"HTTPS manifest accepted")
	check(not Checker.valid_https_url("http://updates.example.test/manifest.json"),"Plain HTTP manifest rejected")
	check(not Checker.valid_https_url("https://user@updates.example.test/manifest.json"),"URL user information rejected")
	var update:=Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.51","download_url":"https://updates.example.test/game"},"0.50-dev")
	check(update.get("required",false) and update.get("latest_version")=="0.52","Outdated client gets required update record")
	var optional:=Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.49","download_url":"https://updates.example.test/game"},"0.50-dev")
	check(not optional.get("required",true) and optional.get("latest_version")=="0.52","Supported client gets optional update record")
	check(Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.49","download_url":"http://updates.example.test/game"},"0.50-dev").is_empty(),"Insecure download URL rejected")
	check(Checker.interpret_manifest({"latest_version":"0.49","minimum_version":"0.40","download_url":"https://updates.example.test/game"},"0.50-dev").is_empty(),"No notice when client is current")
	check(Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.53","download_url":"https://updates.example.test/game"},"0.50-dev").is_empty(),"A channel cannot require a version it does not offer")
	check(Checker.valid_https_url(str(ProjectSettings.get_setting("application/config/update_url",""))),"The old-protocol prompt has an HTTPS downloads fallback")
	var app:=Main.new()
	root.add_child(app)
	for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=extent
		await process_frame
		app._show_version_update(update)
		await process_frame
		var dialog:Control=app.version_update_dialog
		check(is_instance_valid(dialog) and Rect2(Vector2.ZERO,Vector2(extent)).encloses(dialog.get_global_rect()),"Startup update prompt fits %s" % extent)
		check(has_text(dialog,"需要更新遊戲") and has_text(dialog,"前往下載新版"),"Required update prompt explains and offers download")
		dialog.queue_free()
		app.version_update_dialog=null
	var archive_path:=OS.get_temp_dir().path_join("tuan-update-fixture-%d.zip"%OS.get_process_id())
	var file:=FileAccess.open(archive_path,FileAccess.WRITE)
	file.store_string("test")
	file.close()
	var archive:={"bytes":4,"sha256":"test".sha256_text()}
	check(Checker.verify_archive(archive_path,archive),"Signed byte count and SHA-256 match")
	check(not Checker.verify_archive(archive_path,{"bytes":5,"sha256":archive.sha256}),"Incorrect length rejected")
	check(not Checker.verify_archive(archive_path,{"bytes":4,"sha256":"fake".sha256_text()}),"Same length but different content rejected")
	update.archive=archive
	app._show_version_update(update)
	await process_frame
	var picker:=app.version_update_dialog.get_node("UpdateArchivePicker") as FileDialog
	picker.file_selected.emit(archive_path)
	check(has_text(app.version_update_dialog,"驗證通過"),"Verified ZIP result is visible")
	file=FileAccess.open(archive_path,FileAccess.WRITE)
	file.store_string("fake")
	file.close()
	picker.file_selected.emit(archive_path)
	check(has_text(app.version_update_dialog,"驗證失敗"),"Rejected ZIP result is visible")
	DirAccess.remove_absolute(archive_path)
	app.queue_free()
	await process_frame
	print("VERSION_UPDATE_TEST checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
