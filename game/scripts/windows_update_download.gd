extends Node

signal transfer_progress(percent:int)

const Checker=preload("res://scripts/version_update_checker.gd")
const Stage=preload("res://scripts/windows_update_stage.gd")
const MAX_REDIRECTS:=4

var request:HTTPRequest
var partial_path:=""
var expected_bytes:=0
var previous_percent:=-1

func fetch(archive:Dictionary,tls:TLSOptions=null,root:String=Stage.INSTALL_ROOT)->Dictionary:
	if is_instance_valid(request):return Stage.failed("更新已在下載中。")
	var url:String=archive.get("url","")
	expected_bytes=int(archive.get("bytes",0))
	if not Checker.valid_https_url(url) or expected_bytes<1 or expected_bytes>2000000000:
		return Stage.failed("無法使用這份更新的下載資訊。")
	var base:=ProjectSettings.globalize_path(root)
	if DirAccess.make_dir_recursive_absolute(base)!=OK:return Stage.failed("無法建立更新資料夾。")
	var id:=Crypto.new().generate_random_bytes(12).hex_encode()
	if id.is_empty():return Stage.failed("無法建立下載檔案。")
	partial_path=base.path_join(".download-"+id+".part")
	request=HTTPRequest.new()
	request.use_threads=true
	request.timeout=600
	request.max_redirects=0
	request.accept_gzip=false
	request.body_size_limit=expected_bytes
	request.download_file=partial_path
	if tls!=null:request.set_tls_options(tls)
	add_child(request)
	for hop in range(MAX_REDIRECTS+1):
		if request.request(url)!=OK:break
		var response:Array=await request.request_completed
		if response[0]==HTTPRequest.RESULT_SUCCESS and response[1]==200:
			var prepared:=Stage.prepare(partial_path,archive,root)
			finish_download()
			return prepared
		if response[0]!=HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:break
		url=redirect_url(url,response[2])
		if url.is_empty():break
	finish_download()
	return Stage.failed("下載未完成，請重試或從下載頁取得 ZIP。")

static func redirect_url(source:String,headers:PackedStringArray)->String:
	for header in headers:
		if not header.to_lower().begins_with("location:"):continue
		var next:=header.substr(9).strip_edges()
		if next.begins_with("//"):
			next="https:"+next
		elif next.begins_with("/"):
			next="https://"+source.get_slice("/",2).get_slice("?",0)+next
		return next if Checker.valid_https_url(next,true) else ""
	return ""

func _process(_delta:float)->void:
	if not is_instance_valid(request):return
	var percent:=clampi(int(request.get_downloaded_bytes()*100.0/expected_bytes),0,100)
	if percent==previous_percent:return
	previous_percent=percent
	transfer_progress.emit(percent)

func finish_download()->void:
	if is_instance_valid(request):
		request.queue_free()
		request=null
	remove_partial()
	previous_percent=-1

func remove_partial()->void:
	if not partial_path.is_empty() and FileAccess.file_exists(partial_path):
		DirAccess.remove_absolute(partial_path)
	partial_path=""

func _exit_tree()->void:
	if is_instance_valid(request):request.cancel_request()
	remove_partial()
