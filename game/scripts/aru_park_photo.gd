extends RefCounted

## T066 N01-4 有人坐的地方：公共長椅地塊的「預覽 → 確認」拍照流程。
##
##  * open(app,reopen)：關閉選單，用世界畫面拍一張只框住長椅與木燈的靜態照片（不含 HUD），
##    然後開預覽（AruParkPhotoPreview／AruParkPhotoConfirm／AruParkPhotoCancel）。
##    預覽階段不寫任何檔案，也不送任何伺服器請求。
##  * 確認：先把照片寫成暫存檔（確認磁碟可寫），再送 ARU_PARK_PHOTO。只有等到
##    session.action_completed 帶回「同一個序號 + 同一個動作」且 ok，才把暫存檔換成正式相簿檔。
##    伺服器拒絕、逾時、取消、磁碟失敗時，原本的好相簿原封不動。
##  * 正式檔名沿用 LifeTasks.aru_photo_path（由呼叫端傳入），舊存檔與木框相簿照常讀得到。
##
## capture_plot() 是可重用的「乾淨快照」：暫停世界鏡頭更新、固定 16:10 取景、隱藏整層 UI，
## 抓一格實際繪製的畫面，然後在所有路徑上把鏡頭／縮放／拍照模式／UI 還原。

const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS

const FLOW_NAME:="AruParkPhotoFlow"
const BUSY_META:="aru_park_photo_busy"
const PREVIEW_META:="aru_park_photo_preview"
const ACK_TIMEOUT_MS:=10000
const SNAPSHOT_ZOOM:=4.0
const ASPECT:=1.6
const MAX_WIDTH:=1280
const PREVIEW_SIZE:=Vector2(352,220)
const PENDING_SUFFIX:=".pending.png"
const BACKUP_SUFFIX:=".previous"

static func recover_album(path:String) -> void:
	var backup:=path+BACKUP_SUFFIX
	if not FileAccess.file_exists(path) and FileAccess.file_exists(backup):
		DirAccess.rename_absolute(backup,path)

## 長椅與木燈兩格的中心（世界像素），稍微往下留一點地面。
static func plot_center(tile:float) -> Vector2:
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for kind:String in Goals.ARU_PARK_SLOTS:
		var cell:Vector2=Vector2(Goals.ARU_PARK_SLOTS[kind])
		low=Vector2(minf(low.x,cell.x),minf(low.y,cell.y))
		high=Vector2(maxf(high.x,cell.x),maxf(high.y,cell.y))
	return ((low+high+Vector2.ONE)*0.5+Vector2(0,0.3))*tile

static func crop_frame(image:Image) -> Image:
	var size:=image.get_size()
	var width:=mini(size.x,int(floor(float(size.y)*ASPECT)))
	var height:=int(round(float(width)/ASPECT))
	var cropped:=image.get_region(Rect2i((size.x-width)/2,(size.y-height)/2,width,height))
	if cropped.get_width()>MAX_WIDTH:cropped.resize(MAX_WIDTH,int(round(MAX_WIDTH/ASPECT)),Image.INTERPOLATE_BILINEAR)
	return cropped

static func _restore(app,keep:Dictionary) -> void:
	var view=app.view
	if is_instance_valid(view):
		view.camera=keep.camera
		view.camera_frame=keep.frame
		view.zoom=keep.zoom
		view.photograph_mode=keep.photo
		view.set_process(keep.processing)
		view.queue_redraw()
	if is_instance_valid(app.ui):app.ui.visible=keep.ui
	if is_instance_valid(app.hud):app.hud.visible=keep.hud
	if is_instance_valid(app.toast):app.toast.visible=keep.toast
	app.remove_meta(BUSY_META)

## 實際世界畫面的 16:10 快照（長椅＋木燈置中、沒有 HUD）；失敗回傳 null。
static func capture_plot(app) -> Image:
	if DisplayServer.get_name()=="headless":return null
	var view=app.view
	if not is_instance_valid(view) or not is_instance_valid(app.ui) or app.has_meta(BUSY_META):return null
	if view.region_id()!=World.REGIONS.HOME:return null
	app.set_meta(BUSY_META,true)
	var keep:={"camera":view.camera,"frame":view.camera_frame,"zoom":view.zoom,"photo":view.photograph_mode,
		"processing":view.is_processing(),"ui":app.ui.visible,"hud":app.hud.visible,"toast":app.toast.visible}
	app.ui.visible=false
	view.set_process(false)
	view.photograph_mode=true
	view.zoom=SNAPSHOT_ZOOM
	var target:Vector2=(plot_center(view.TILE)-view.get_viewport_rect().size/SNAPSHOT_ZOOM*0.5).round()
	var image:Image=null
	for attempt in 3:
		view.camera=target
		view.queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(view):break
		if view.camera==target: # nothing moved the camera while the frame was drawn
			var raw:Image=app.get_viewport().get_texture().get_image()
			if raw!=null and not raw.is_empty():image=crop_frame(raw)
			break
	_restore(app,keep)
	return image

static func open(app,path:String,reopen:Callable) -> void:
	if app.has_meta(BUSY_META):return
	var old:Node=app.get_node_or_null(FLOW_NAME)
	if old!=null:old.free()
	app._close_modal()
	var image:=await capture_plot(app)
	if image==null:
		app._notice("現在拍不到照片，請站在公共長椅地塊旁再試一次。",false)
		reopen.call()
		return
	if is_instance_valid(app.modal) or app.get_node_or_null(FLOW_NAME)!=null:return # something else took the screen meanwhile
	var flow:=Flow.new()
	flow.name=FLOW_NAME
	flow.app=app
	flow.path=path
	flow.image=image
	flow.reopen=reopen
	app.add_child(flow)
	flow.show_preview()

class Flow extends Node:
	var app
	var path:=""
	var image:Image
	var reopen:Callable
	var stage:="preview" # preview → saving → waiting → (done)
	var sequence:=0
	var started:=0
	var preview:TextureRect
	var confirm:Button
	var cancel:Button
	var status:Label

	func pending_path() -> String:
		return path+PENDING_SUFFIX

	func show_preview() -> void:
		var body:VBoxContainer=app._open_modal("替公共長椅留影")
		app.modal.set_meta("life_modal_layout","keepsake_paper")
		app.modal.set_meta(PREVIEW_META,true)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",14)
		body.add_child(row)
		preview=TextureRect.new()
		preview.name="AruParkPhotoPreview"
		preview.texture=ImageTexture.create_from_image(image)
		preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		preview.custom_minimum_size=PREVIEW_SIZE
		row.add_child(preview)
		var side:=VBoxContainer.new()
		side.add_theme_constant_override("separation",8)
		side.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		side.custom_minimum_size.x=230
		row.add_child(side)
		status=app.label("確認取景後，將照片收進渡口相簿。",15)
		status.name="AruParkPhotoStatus"
		status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		side.add_child(status)
		confirm=app.button("留下這張照片",_confirm)
		confirm.name="AruParkPhotoConfirm"
		side.add_child(confirm)
		cancel=app.button("取消",_cancel)
		cancel.name="AruParkPhotoCancel"
		side.add_child(cancel)
		confirm.grab_focus.call_deferred()
		app._layout_preview.call_deferred()

	func _say(text:String) -> void:
		if is_instance_valid(status):status.text=text

	func _controls(enabled:bool) -> void:
		if is_instance_valid(confirm):confirm.disabled=not enabled
		if is_instance_valid(cancel):cancel.disabled=not enabled

	func _preview_open() -> bool:
		return is_instance_valid(preview) and is_instance_valid(app.modal) and app.modal.has_meta(PREVIEW_META) and app.modal.is_ancestor_of(preview)

	func _cancel() -> void:
		if stage!="preview":return
		var again:=reopen
		stage="done"
		app._close_modal()
		queue_free()
		again.call()

	func _drop_pending() -> void:
		if FileAccess.file_exists(pending_path()):DirAccess.remove_absolute(pending_path())

	func _readable(file:String) -> bool:
		var check:=Image.load_from_file(file)
		return check!=null and not check.is_empty() and check.get_size()==image.get_size()

	func _confirm() -> void:
		if stage!="preview":return
		stage="saving"
		_controls(false)
		_drop_pending()
		if image.save_png(pending_path())!=OK or not _readable(pending_path()):
			_drop_pending()
			_refused("照片無法儲存，請再試一次。")
			return
		_say("正在向島上確認…")
		var predicted:int=int(app.session.counter)+1
		sequence=predicted
		started=Time.get_ticks_msec()
		stage="waiting"
		if not app.session.action_completed.is_connected(_on_completed):app.session.action_completed.connect(_on_completed)
		var sent:int=app.session.perform(Goals.ARU_PARK_PHOTO,Goals.ARU_PARK_VIEW) # a host answers inside this call
		if stage=="waiting" and sent!=predicted:
			_disconnect()
			_drop_pending()
			_refused("現在送不出照片紀錄，請再試一次。")

	func _on_completed(seq:int,action:String,result:Dictionary) -> void:
		if stage!="waiting" or seq!=sequence or action!=Goals.ARU_PARK_PHOTO:return
		_disconnect()
		if not result.get("ok",false):
			_drop_pending()
			var reason:=str(result.get("message",""))
			_refused(reason if not reason.is_empty() else "這次的照片沒有被接受。")
			return
		if not _finalize():
			_drop_pending()
			_refused("照片紀錄已送出，但相簿檔案無法更新；舊相簿沒有變動，請再拍一次。")
			return
		stage="done"
		var show_album:=_preview_open() or not is_instance_valid(app.modal)
		var again:=reopen
		app._notice("相片已留在公共長椅的相簿，可以回來翻看。",true)
		if show_album:again.call()
		queue_free()

	## 暫存檔 → 正式檔。舊相簿先改名備份，換檔失敗就原樣放回去。
	func _finalize() -> bool:
		var backup:=path+BACKUP_SUFFIX
		var had:=FileAccess.file_exists(path)
		if FileAccess.file_exists(backup):
			if not had or DirAccess.remove_absolute(backup)!=OK:return false
		if had and DirAccess.rename_absolute(path,backup)!=OK:return false
		if DirAccess.rename_absolute(pending_path(),path)!=OK:
			if had:DirAccess.rename_absolute(backup,path)
			return false
		if had:DirAccess.remove_absolute(backup)
		return true

	## 沒成功：留在預覽，讓玩家重試或取消；選單已被關掉就只丟通知。
	func _refused(message:String) -> void:
		app._notice(message,false)
		if _preview_open():
			stage="preview"
			_say(message)
			_controls(true)
		else:
			stage="done"
			queue_free()

	func _disconnect() -> void:
		if app and app.session and app.session.action_completed.is_connected(_on_completed):
			app.session.action_completed.disconnect(_on_completed)

	func _process(_delta:float) -> void:
		if stage=="preview" and not _preview_open():
			stage="done" # Esc／離開預覽 = 取消，什麼都沒有寫
			queue_free()
		elif stage=="waiting" and Time.get_ticks_msec()-started>ACK_TIMEOUT_MS:
			_disconnect()
			_drop_pending()
			_refused("還沒收到島上的回應，結果未知。舊相簿沒有變動，可以再試一次。")

	func _exit_tree() -> void:
		_disconnect()
		_drop_pending() # after a successful finalize the pending file no longer exists
