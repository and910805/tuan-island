extends SceneTree

const Main=preload("res://scripts/main.gd")
const Checker=preload("res://scripts/version_update_checker.gd")
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

func run() -> void:
	check(Checker.version_is_older("0.50-dev","0.51"),"Development build compares lower than next release")
	check(not Checker.version_is_older("0.51","0.50"),"Newer client is not outdated")
	check(not Checker.version_is_older("0.50","0.50.0"),"Equivalent versions compare equal")
	check(Checker.version_parts("bad").is_empty(),"Malformed version rejected")
	check(Checker.valid_https_url("https://updates.example.test/manifest.json"),"HTTPS manifest accepted")
	check(not Checker.valid_https_url("http://updates.example.test/manifest.json"),"Plain HTTP manifest rejected")
	check(not Checker.valid_https_url("https://user@updates.example.test/manifest.json"),"URL user information rejected")
	var update:=Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.51","download_url":"https://updates.example.test/game"},"0.50-dev")
	check(update.get("required",false) and update.get("latest_version")=="0.52","Outdated client gets required update record")
	var optional:=Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.49","download_url":"https://updates.example.test/game"},"0.50-dev")
	check(not optional.get("required",true) and optional.get("latest_version")=="0.52","Supported client gets optional update record")
	check(Checker.interpret_manifest({"latest_version":"0.52","minimum_version":"0.49","download_url":"http://updates.example.test/game"},"0.50-dev").is_empty(),"Insecure download URL rejected")
	check(Checker.interpret_manifest({"latest_version":"0.49","minimum_version":"0.40","download_url":"https://updates.example.test/game"},"0.50-dev").is_empty(),"No notice when client is current")
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
	app.queue_free()
	await process_frame
	print("VERSION_UPDATE_TEST checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
