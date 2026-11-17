extends Node2D

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Festival=preload("res://scripts/festival.gd")
const Collections=preload("res://scripts/collections.gd")
const SoftAudio=preload("res://scripts/soft_audio.gd")
const View=preload("res://scripts/world_view.gd")
const IslandMap=preload("res://scripts/island_map.gd")
const LifeTheme=preload("res://scripts/life_ui_theme.gd")
const LifePanels=preload("res://scripts/life_ui_panels.gd")
const LifeTasks=preload("res://scripts/life_ui_tasks.gd")
const ChapterUI=preload("res://scripts/chapter_ui.gd")
const TeaUI=preload("res://scripts/tea_ceramics_ui.gd")
const FlowerUI=preload("res://scripts/flower_nursery_ui.gd")
const SaltUI=preload("res://scripts/salt_pan_ui.gd")
const SaltArt=preload("res://scripts/salt_art.gd")
const TeaGuidance=preload("res://scripts/tea_guidance.gd")
const LanyangUI=preload("res://scripts/lanyang_ui.gd")
const HistoryUI=preload("res://scripts/history_ui.gd")
const RevisitUI=preload("res://scripts/lanyang_revisit_ui.gd")
const GateUI=preload("res://scripts/diversion_gate_ui.gd")
const TowerUI=preload("res://scripts/water_tower_ui.gd")
const JgRevisitUI=preload("res://scripts/jinguashi_revisit_ui.gd")
const TeaRevisitUI=preload("res://scripts/tea_revisit_ui.gd")
const SaltRevisitUI=preload("res://scripts/salt_revisit_ui.gd")
const SaltBrineUI=preload("res://scripts/salt_brine_ui.gd")
const GoldPanUI=preload("res://scripts/gold_panning_ui.gd")
const OreRouteUI=preload("res://scripts/ore_route_ui.gd")
const MineUI=preload("res://scripts/mine_ui.gd")
const MineSurveyUI=preload("res://scripts/mine_survey_ui.gd")
const FreightUI=preload("res://scripts/freight_ui.gd")
const AutoFreightUI=preload("res://scripts/auto_freight_ui.gd")
const BoboSortUI=preload("res://scripts/bobo_sort_ui.gd")
const TravelUI=preload("res://scripts/travel_ui.gd")
const StationLifeUI=preload("res://scripts/station_life_ui.gd")
const WaterworksUI=preload("res://scripts/waterworks_ui.gd")
const MineDrillUI=preload("res://scripts/mine_drill_ui.gd")
const CookingQueueUI=preload("res://scripts/cooking_queue_ui.gd")
const CommunityUI=preload("res://scripts/community_ui.gd")
const InventoryPanel=preload("res://scripts/inventory_panel.gd")
const ShippingPanel=preload("res://scripts/shipping_panel.gd")
const MarketUI=preload("res://scripts/market_stall_ui.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const FishMeetUI=preload("res://scripts/fishing_meet_ui.gd")
const ShowcaseUI=preload("res://scripts/showcase_ui.gd")
const SouvenirUI=preload("res://scripts/souvenir_exchange_ui.gd")
const MemoryExhibitUI=preload("res://scripts/memory_exhibit_ui.gd")
const LifeShell=preload("res://scripts/life_ui_shell.gd")
const WanganOpening=preload("res://scripts/wangan_opening.gd")
const WanganUI=preload("res://scripts/wangan_opening_ui.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const WeatherForecast=preload("res://scripts/weather_forecast.gd")
const LifeHome=preload("res://scripts/life_ui_home.gd")
const IdentityEntry=preload("res://scripts/identity_entry.gd")
const VersionUpdateChecker=preload("res://scripts/version_update_checker.gd")
const WindowsUpdateStage=preload("res://scripts/windows_update_stage.gd")
const WindowsUpdateLaunch=preload("res://scripts/windows_update_launch.gd")
const WindowsUpdateDownload=preload("res://scripts/windows_update_download.gd")
const LifeAlmanac=preload("res://scripts/life_ui_almanac.gd")
const AutomationUI=preload("res://scripts/automation_ui.gd")
const IndustryUI=preload("res://scripts/industry_ui.gd")
const ForestryUI=preload("res://scripts/forestry_ui.gd")
const LogisticsUI=preload("res://scripts/logistics_ui.gd")
const InputBindings=preload("res://scripts/input_bindings.gd")
const InputBindingsPanel=preload("res://scripts/input_bindings_panel.gd")
const BuildThumbnail=preload("res://scripts/pixel_build_thumbnail.gd")
const InventoryItemArt=preload("res://scripts/inventory_item_art.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
const ConstructionUndoUI=preload("res://scripts/construction_undo_ui.gd")
const BlueprintController=preload("res://scripts/blueprint_controller.gd")
const BlueprintUI=preload("res://scripts/blueprint_ui.gd")
const BlueprintPreview=preload("res://scripts/blueprint_preview.gd")
const BLUEPRINT_MAX_SPAN:=16
const BLUEPRINT_LOCAL_MODES:=["capture","placing"]
const BLUEPRINT_SENT_MODES:=["submitting","unknown"]
const TEXT_SCALE_FACTORS:=[0.9,1.0,1.12,1.25]
const TOOL_ACTIONS:=["hoe","seed","water","harvest","axe","pick","build","remove","fish","plant_tree","till_area","seed_area","harvest_area","move_object"]
## Build actions that may add/remove automatic roofs; every other action is forwarded untouched.
const ROOF_QUOTE_ACTIONS:=["build","remove","build_area"]
## Loaded lazily so the client still runs (forwarding every action) if the preview script is absent.
const AUTO_ROOF_PREVIEW_PATH:="res://scripts/auto_roof_preview.gd"
var bindings=InputBindings.new()
var bindings_panel:Control
var session:Node
var view:Node2D
var ui:CanvasLayer
var menu:Control
var identity_entry:Control
var island_passport:Dictionary={}
var passport_feedback:Label
var passport_code:LineEdit
var hud:Control
var modal:PanelContainer
var map_view:Control
var toast:Label
var activity_caption:Label
var region_subtitle:Label
var activity_caption_time:=0.0
var activity_caption_priority:=0
var objective:Label
var inventory_label:Label
var status_label:Label
var selected_label:Label
var name_input:LineEdit
var address_input:LineEdit
var key_input:LineEdit
var port_input:LineEdit
var toast_time:=0.0
var selected:="hoe"
var crop:="radish"
var building:="floor"
var building_style:=""
var controller_sticks:Dictionary={}
var controller_device:=-1
var controller_protected:=false
var controller_aim:=false
var controller_navigation:=false
var mute_emotes:=false
var mute_chat:=false
var return_news_pending:=false
var return_news_snapshot_received:=false
var island_messages:Array[String]=[]
var controller_offset:=Vector2i.DOWN
const CONTROLLER_TOOLS:=["hoe","seed","water","harvest","axe","pick","build","remove","fish","move_object"]
const CONTROLLER_AIM_DIRECTIONS:={JOY_BUTTON_DPAD_UP:Vector2i.UP,JOY_BUTTON_DPAD_DOWN:Vector2i.DOWN,
	JOY_BUTTON_DPAD_LEFT:Vector2i.LEFT,JOY_BUTTON_DPAD_RIGHT:Vector2i.RIGHT}
var target:=Vector2i.ZERO
var playing:=false
var voyage_return:Button
var voyage_photo:Button
var voyage_active:=false
var tool_buttons:Array[Button]=[]
var input_clock:=0.0
var action_clock:=0.0
const GATHER_MOUSE:=-2
const GATHER_NONE:=-1
const GATHER_INTERVAL:=0.36
var gather_hold:Dictionary={}
var ui_clock:=0.0
var test_seconds:=0.0
var local_mode:=false
var area_drag:=false
var area_start:=Vector2i.ZERO
var moving_object:=false
var move_from:=Vector2i.ZERO
## Object or script exposing quote(snapshot,actor,action,at,extra); null loads AUTO_ROOF_PREVIEW_PATH.
var auto_roof_preview:Variant=null
var sound:Node
var fishing_audio:=preload("res://scripts/fishing_audio.gd").new()
# The finished illustrated life-sim UI is the shipped default. Keep the older
# prototype presentation available only for explicit compatibility checks.
var village_art_preview := not "--classic-ui" in OS.get_cmdline_user_args() or OS.has_feature("village_art_preview")
var preview_controls: Array[Control] = []
var preview_tracker: PanelContainer
var life_panels=LifePanels.new()
var undo_ui=ConstructionUndoUI.new()
var automation_ui=AutomationUI.new()
var industry_ui=IndustryUI.new()
var forestry_ui=ForestryUI.new()
var logistics_ui=LogisticsUI.new()
var modal_shade:ColorRect
var modal_feedback:Label
var settings_path:="user://settings.cfg"
var preview_toolbar:PanelContainer
var preview_top:HBoxContainer
var coin_label:Label
var inventory_hidden_controls:Array[Control]=[]
var version_checker:Node
var version_update_dialog:Control
var room_update_dialog:Control
var font_scale_refresh_pending:=false
## Blueprint client: controller owns data/state, overlay draws on the map,
## strip is the non-modal construction side panel. Client-only (not headless).
var blueprints:Node
var blueprint_overlay:Node2D
var blueprint_strip:Control
## Capture rectangle drag, kept apart from the ordinary area_drag build flow.
var capture_drag:=false
var capture_start:=Vector2i.ZERO
## Stable world scope for joins without an identity world ID: address/port only,
## never the room key, ticket or invite.
var blueprint_join_scope:=""

func _ready() -> void:
	Input.joy_connection_changed.connect(_controller_connection_changed)
	get_tree().auto_accept_quit=false
	# Beimen panel art (阿曬 portrait, pan previews); null keeps SaltUI's plain plate.
	SaltUI.art_provider=Callable(SaltArt,"panel_art")
	session=Session.new()
	add_child(session)
	session.changed.connect(_state_changed)
	session.emote_received.connect(_show_emote)
	session.chat_received.connect(_receive_island_chat)
	session.island_note_result.connect(func(sequence:int,success:bool):LifeTasks.finish_island_note(self,sequence,success))
	session.notice.connect(_notice)
	session.action_completed.connect(_action_completed)
	session.connected_world.connect(_entered)
	session.disconnected_world.connect(_disconnected)
	var args:=OS.get_cmdline_user_args()
	if "--server" in args:
		if not _configure_identity_server():
			push_error("封測世界身分設定不完整或無法載入。")
			get_tree().quit(1)
			return
		var port:=int(server_setting("port","PORT","28417"))
		var save_file:=server_setting("save","GAME_SAVE_PATH","user://world-server.json")
		var err:int=session.host(port,"",save_file,server_setting("room-key","GAME_ROOM_KEY",""),server_setting("bind","GAME_BIND","127.0.0.1"),true,server_setting("transport","GAME_TRANSPORT","enet"),false,server_setting("mode","GAME_WORLD_MODE",""))
		if err==OK:
			var release:=_release_metadata()
			print("SERVER_BUILD version=%s build=%d protocol=%d"%[release.get("version","unknown"),int(release.get("build",0)),Session.PROTOCOL])
		if err!=OK:get_tree().quit(1)
		test_seconds=float(arg_value("quit-after","0"))
		return
	if village_art_preview:
		# Use actual pixels so ordinary resized windows match the responsive UI,
		# instead of scaling a 1280x800 canvas to fractional pixel sizes.
		get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
		get_window().min_size=Vector2i(1024,640)
	sound=SoftAudio.new()
	add_child(sound)
	settings_path=arg_value("settings",settings_path)
	sound.load_preferences(settings_path)
	sound.set_title()
	bindings.load_preferences(arg_value("bindings","user://input-bindings.cfg"))
	view=View.new()
	if village_art_preview:view.village_art_preview=true
	add_child(view)
	view.reduced_motion=sound.reduced_motion
	view.zoom=float(sound.preferred_zoom)
	view.fixed_area_camera=sound.fixed_area_camera
	view.label_text_scale=font_scale_factor()
	view.interaction_key_label=binding_label("interact")
	ui=CanvasLayer.new()
	add_child(ui)
	get_tree().node_added.connect(_font_scale_node_added)
	_make_menu()
	menu.visibility_changed.connect(_focus_title.call_deferred)
	if not Input.get_connected_joypads().is_empty():
		controller_navigation=true
		_focus_title.call_deferred()
	toast.add_theme_font_override("font",preload("res://scripts/island_type.gd").regular())
	if not village_art_preview:
		var identity_button:=button("封測島嶼",_open_identity)
		menu.add_child(identity_button)
		identity_button.position=Vector2(32,24)
	if session.has_signal("identity_status"):
		session.connect("identity_status",_identity_status)
	_make_hud()
	_make_blueprints()
	if village_art_preview:get_viewport().size_changed.connect(_layout_preview)
	else:get_viewport().size_changed.connect(_layout_blueprint_strip)
	port_input.text=arg_value("port","28417")
	if OS.get_name()=="Windows" and not OS.has_feature("editor") and args.is_empty():
		_resume_installed_update.call_deferred()
	else:
		_start_version_check()
	var startup_nonce:=arg_value("update-startup","")
	if not startup_nonce.is_empty() and "--local" not in args and "--join" not in args:
		_confirm_update_startup(startup_nonce)
	if "--local" in args: _host(false,arg_value("mode","life"))
	if "--join" in args:
		address_input.text=arg_value("address","127.0.0.1")
		port_input.text=arg_value("port","28417")
		# Automated local launch may supply its test room key without putting a
		# secret on the command line or saving it in the player's preferences.
		if OS.has_environment("GAME_CLIENT_ROOM_KEY"):key_input.text=OS.get_environment("GAME_CLIENT_ROOM_KEY")
		_join()
	if arg_value("capture","")!="":_capture_frame()

func _confirm_update_startup(nonce:String)->void:
	await get_tree().process_frame
	if is_instance_valid(menu) and menu.visible:
		WindowsUpdateLaunch.accept_startup(nonce)

func _start_version_check() -> void:
	var manifest_url:=str(ProjectSettings.get_setting("application/config/update_manifest_url","")).strip_edges()
	if manifest_url.is_empty():return
	var current_version:=_release_update_version()
	if VersionUpdateChecker.version_parts(current_version).size()!=3:return
	version_checker=VersionUpdateChecker.new()
	add_child(version_checker)
	version_checker.update_available.connect(_show_version_update)
	version_checker.check.call_deferred(manifest_url,current_version)

func _release_version()->String:
	return str(_release_metadata().get("version",""))

func _release_update_version()->String:
	var release:=_release_metadata()
	return VersionUpdateChecker.packaged_version(str(release.get("version","")),release.get("build"))

func _release_metadata()->Dictionary:
	var release_file:=FileAccess.open("res://release.json",FileAccess.READ)
	if release_file==null:return {}
	var release:Variant=JSON.parse_string(release_file.get_as_text())
	return release if release is Dictionary else {}

func title_build_label()->Label:
	var release:=_release_metadata()
	var version:=str(release.get("version","")).strip_edges()
	var build:Variant=release.get("build")
	var text:="版本 "+version if not version.is_empty() else "開發版本"
	if (build is int or build is float) and is_finite(float(build)) and build>=1 and build<=999999 and build==floorf(float(build)):
		text+=" r%d"%int(build)
	var badge:=label(text,14)
	badge.name="TitleBuild"
	badge.add_theme_color_override("font_color",Color("4a5e48"))
	return badge

func _resume_installed_update()->void:
	var key:=VersionUpdateChecker.installed_public_key()
	var candidates:=WindowsUpdateLaunch.remembered(key,_release_update_version())
	if not candidates.is_empty():
		menu.hide()
		for candidate in candidates:
			if await WindowsUpdateLaunch.launch(get_tree(),candidate):
				_quit()
				return
		menu.show()
		_notice("已保留可用的遊戲版本。",false)
	_start_version_check()

func _show_version_update(info:Dictionary) -> void:
	if not is_instance_valid(ui):return
	if is_instance_valid(version_update_dialog):version_update_dialog.queue_free()
	var overlay:=Control.new()
	overlay.name="VersionUpdateOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_STOP
	overlay.theme=menu.theme if is_instance_valid(menu) else theme()
	ui.add_child(overlay)
	var shade:=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0.07,0.12,0.10,0.70)
	overlay.add_child(shade)
	var panel:=PanelContainer.new()
	var archive:Dictionary=info.get("archive",{})
	var half_height:=150 if archive.is_empty() else 195
	panel.name="VersionUpdatePanel"
	panel.anchor_left=0.5
	panel.anchor_top=0.5
	panel.anchor_right=0.5
	panel.anchor_bottom=0.5
	panel.offset_left=-245
	panel.offset_top=-half_height
	panel.offset_right=245
	panel.offset_bottom=half_height
	panel.add_theme_stylebox_override("panel",LifeTheme.badge_style())
	overlay.add_child(panel)
	var content:=VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	panel.add_child(content)
	var required:bool=info.get("required",false)
	content.add_child(label("需要更新遊戲" if required else "糰糰島有新版本",25))
	var details:=label("目前版本 %s\n最新版本 %s%s" % [info.get("current_version",""),info.get("latest_version",""),"\n此版本已停止支援，請更新後再連線。" if required else "\n更新後即可體驗最新內容。"],16)
	details.custom_minimum_size.y=76
	content.add_child(details)
	var download:=button("前往下載新版",func():
		var error:=OS.shell_open(str(info.get("download_url","")))
		if error!=OK:_notice("無法開啟下載頁，請稍後從官方公告取得新版。",false)
	)
	content.add_child(download)
	var dismiss:=button("稍後再說",func():overlay.queue_free();version_update_dialog=null)
	if not archive.is_empty():
		var status:=label("",15)
		status.name="UpdateArchiveStatus"
		var actions:=HBoxContainer.new()
		actions.add_theme_constant_override("separation",8)
		content.add_child(actions)
		content.add_child(status)
		var picker:=FileDialog.new()
		picker.name="UpdateArchivePicker"
		picker.title="選取已下載的《糰糰島》更新封包"
		picker.access=FileDialog.ACCESS_FILESYSTEM
		picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
		picker.filters=PackedStringArray(["*.zip ; Windows 更新封包"])
		overlay.add_child(picker)
		var staged_folder:=button("開啟新版資料夾",func():
			OS.shell_open(str(overlay.get_meta("prepared_update","")))
		)
		staged_folder.hide()
		content.add_child(staged_folder)
		var launch_new:=Button.new()
		launch_new.text="啟動新版"
		launch_new.custom_minimum_size.y=42
		launch_new.hide()
		content.add_child(launch_new)
		launch_new.pressed.connect(func():
			if not menu.visible or session.world!=null or not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
				status.text="請先回到主選單，再啟動新版。"
				return
			launch_new.disabled=true
			dismiss.disabled=true
			status.text="正在等待新版啟動…"
			var prepared:Dictionary=overlay.get_meta("prepared_release")
			var persist:=func()->bool:
				return WindowsUpdateLaunch.remember(prepared,info.signed_manifest,VersionUpdateChecker.installed_public_key(),_release_update_version())
			var ok:=await WindowsUpdateLaunch.launch(get_tree(),prepared,WindowsUpdateStage.INSTALL_ROOT,WindowsUpdateLaunch.STARTUP_TIMEOUT,persist)
			if ok:
				_quit()
				return
			if not is_instance_valid(overlay):return
			launch_new.disabled=false
			dismiss.disabled=false
			status.text="新版未能啟動，原版本可以繼續遊玩。"
		)
		var validate:=button("驗證下載的 ZIP",func():
			picker.set_meta("prepare_update",false)
			picker.popup_centered_ratio(0.7)
		)
		actions.add_child(validate)
		var prepare:=button("準備新版",func():
			picker.set_meta("prepare_update",true)
			picker.popup_centered_ratio(0.7)
		)
		actions.add_child(prepare)
		var apply_prepared:=func(result:Dictionary):
			if not result.ok:
				status.text=str(result.message)
				return
			overlay.set_meta("prepared_update",result.directory)
			overlay.set_meta("prepared_release",result)
			staged_folder.show()
			var signed_binaries_match:bool=info.has("signed_manifest") and info.get("binary_hashes",{})==result.hashes
			launch_new.visible=OS.get_name()=="Windows" and signed_binaries_match
			prepare.disabled=true
			status.text="新版已準備好。" if signed_binaries_match else "封包已驗證，但缺少相符的執行檔簽章資料。"
		if OS.get_name()=="Windows" and archive.has("url"):
			var transfer:=WindowsUpdateDownload.new()
			overlay.add_child(transfer)
			transfer.transfer_progress.connect(func(percent:int):status.text="正在下載新版 %d%%"%percent)
			var fetch:=Button.new()
			fetch.text="在遊戲內下載"
			fetch.custom_minimum_size.y=42
			content.add_child(fetch)
			content.move_child(fetch,actions.get_index())
			fetch.pressed.connect(func():
				fetch.disabled=true
				dismiss.disabled=true
				validate.disabled=true
				prepare.disabled=true
				status.text="正在連接下載站…"
				var result:=await transfer.fetch(archive)
				if not is_instance_valid(overlay):return
				fetch.disabled=result.ok
				dismiss.disabled=false
				validate.disabled=false
				prepare.disabled=result.ok
				apply_prepared.call(result)
			)
		picker.file_selected.connect(func(path:String):
			if picker.get_meta("prepare_update",false):
				apply_prepared.call(WindowsUpdateStage.prepare(path,archive))
				return
			var valid:=VersionUpdateChecker.verify_archive(path,archive)
			status.text="驗證通過，檔案符合發行清單。" if valid else "驗證失敗，請從下載頁重新取得。"
		)
	content.add_child(dismiss)
	version_update_dialog=overlay

func _configure_identity_server() -> bool:
	var public_address:=server_setting("public-address","GAME_PUBLIC_ADDRESS","")
	var world_name:=server_setting("world-name","GAME_WORLD_NAME","")
	var directory_requested:=not public_address.is_empty() or not world_name.is_empty()
	for argument in OS.get_cmdline_user_args():
		directory_requested=directory_requested or argument in ["--public-address","--world-name"] or argument.begins_with("--public-address=") or argument.begins_with("--world-name=")
	var configuration:=[server_setting("identity-api","GAME_IDENTITY_API",""),server_setting("world-id","WORLD_ID",""),server_setting("identity-server-key-file","IDENTITY_SERVER_KEY_FILE",""),server_setting("members","MEMBERS_PATH",""),server_setting("owner-account","OWNER_ACCOUNT","")]
	var requested:=false
	for item in configuration:
		requested=requested or not str(item).is_empty()
	for argument in OS.get_cmdline_user_args():
		for flag in ["--identity-api","--world-id","--identity-server-key-file","--members","--owner-account"]:
			requested=requested or argument==flag or argument.begins_with(flag+"=")
	if not requested:return not directory_requested
	for item in configuration:
		if str(item).strip_edges().is_empty():return false
	var key_file:=FileAccess.open(configuration[2],FileAccess.READ)
	if key_file==null or key_file.get_length()>1024:return false
	var secret:=key_file.get_as_text().strip_edges()
	if secret.is_empty():return false
	var loopback:="--identity-test-loopback" in OS.get_cmdline_user_args()
	var world_path:=server_setting("save","GAME_SAVE_PATH","user://world-server.json")
	if session.call("configure_identity",configuration[0],configuration[1],secret,configuration[3],configuration[4],loopback,null,world_path)!=OK:return false
	if not directory_requested:return true
	if public_address.strip_edges().is_empty() or world_name.strip_edges().is_empty():return false
	return session.has_method("configure_directory") and session.call("configure_directory",public_address,world_name,"生活",loopback)==OK

func font_scale_factor() -> float:
	return TEXT_SCALE_FACTORS[clampi(sound.preferred_text_scale,0,TEXT_SCALE_FACTORS.size()-1)] if sound!=null else 1.0

func scaled_font_size(size_value:int) -> int:
	return maxi(10,roundi(float(size_value)*font_scale_factor()))

func _font_scale_node_added(node:Node) -> void:
	if not node is Control or not is_instance_valid(ui) or (node!=ui and not ui.is_ancestor_of(node)) or font_scale_refresh_pending:return
	font_scale_refresh_pending=true
	call_deferred("_apply_font_scale_tree")

func _apply_font_scale_tree() -> void:
	font_scale_refresh_pending=false
	if not is_instance_valid(ui):return
	var factor:=font_scale_factor()
	if is_instance_valid(view):view.label_text_scale=factor
	_apply_font_scale_node(ui,factor,{})
	_layout_preview.call_deferred()

func _apply_font_scale_node(node:Node,factor:float,themes:Dictionary) -> void:
	if node is Control:
		var control:=node as Control
		var local_theme:=control.theme
		if local_theme!=null and not themes.has(local_theme.get_instance_id()):
			themes[local_theme.get_instance_id()]=true
			var base:=int(local_theme.get_meta("font_scale_base",0))
			if base<=0 and local_theme.default_font_size>0:
				base=roundi(float(local_theme.default_font_size)/factor)
				local_theme.set_meta("font_scale_base",base)
			if base>0:local_theme.default_font_size=maxi(10,roundi(base*factor))
		if control.has_theme_font_size_override("font_size"):
			var current:=control.get_theme_font_size("font_size")
			var base_size:=int(control.get_meta("font_scale_base",0))
			var previous:=int(control.get_meta("font_scale_applied",-1))
			if base_size<=0 or current!=previous:base_size=current
			control.set_meta("font_scale_base",base_size)
			var applied:=maxi(10,roundi(float(base_size)*factor))
			control.set_meta("font_scale_applied",applied)
			control.add_theme_font_size_override("font_size",applied)
	for child:Node in node.get_children():_apply_font_scale_node(child,factor,themes)

func _open_identity() -> void:
	if not is_instance_valid(identity_entry):
		identity_entry=IdentityEntry.new()
		menu.add_child(identity_entry)
		identity_entry.setup(self)
	identity_entry.open()

func _identity_status(result:Dictionary) -> void:
	match result.get("operation"):
		"membership":
			if result.get("ok",false):
				island_passport=result
				if is_instance_valid(modal) and modal.has_meta("island_passport"):
					var code := passport_code.text if is_instance_valid(passport_code) else ""
					var concealed := not is_instance_valid(passport_code) or passport_code.secret
					_passport_menu()
					if is_instance_valid(passport_code):
						passport_code.text=code
						passport_code.secret=concealed
		"admin_change","kick_member","block_member","public_builder":
			if is_instance_valid(passport_feedback):
				if not result.get("ok",false):
					passport_feedback.text="操作未完成。請確認成員狀態與權限。"
				elif result.operation=="kick_member":
					passport_feedback.text="已請這位成員離開本次連線。"
				elif result.operation=="block_member":
					passport_feedback.text="已封鎖入島。" if result.enabled else "已解除入島封鎖。"
				elif result.operation=="public_builder":
					passport_feedback.text="已授予公共地塊施工權。" if result.enabled else "已收回公共地塊施工權。"
				else:
					passport_feedback.text="管理員權限已更新。"
		"rotate","revoke":
			if is_instance_valid(passport_feedback):
				var success:bool=result.get("ok",false)
				passport_feedback.text=("已更新邀請，有效一小時。" if result.operation=="rotate" else "已撤銷邀請。") if success else "無法保存邀請變更，請稍後重試。"
				if success and not result.get("synced",true):
					passport_feedback.text="等待世界目錄同步…"
				if success and is_instance_valid(passport_code):
					passport_code.text=result.get("code","")
					passport_code.secret=true
	if not is_instance_valid(identity_entry):return
	if result.get("operation")=="join" or (identity_entry.joining and result.get("operation")=="membership"):
		identity_entry.join_result(result.get("ok",false),result.get("message","已連入島嶼。"),str(result.get("code","")))

func _capture_frame() -> void:
	var capture_size:=arg_value("capture-size","").split("x")
	if capture_size.size()==2:
		var extent:=Vector2i(int(capture_size[0]),int(capture_size[1]))
		if extent.x>=800 and extent.y>=600:
			get_window().content_scale_size=extent
			get_window().size=extent
	await get_tree().create_timer(clampf(float(arg_value("capture-delay","1")),1.0,15.0)).timeout
	match arg_value("capture-panel",""):
		"identity":_open_identity()
		"build":_build_menu()
		"blueprints":_blueprint_menu()
		"inventory":_inventory()
		"help":_help()
		"workshop-guide":_workshop_guide(int(arg_value("capture-lesson","0")))
		"shop":_shop()
		"shipping":_shipping_menu()
		"chapter":_chapter_menu()
		"community":_community_menu()
		"animal":_animal_menu()
		"livestock":LifeAlmanac.livestock_menu(self,arg_value("capture-animal","sheep"))
		"map":_map_menu()
		"journal":_journal(arg_value("capture-resident",""))
		"resident":_resident_menu("aru")
		"xiaoli":_resident_menu("xiaoli")
		"festival":_festival_menu()
		"collection":_collection_menu()
		"settings":_settings_menu()
		"bindings":_bindings_menu()
		"pause":_pause_menu()
		"board":_board()
		"seeds":_seed_menu()
		"orders":_orders_menu()
		"cook":_cook_menu(Vector2i(42,32))
		"workbench":automation_ui.workbench(self,World.cell(arg_value("capture-cell","40,33")))
		"sprinkler":automation_ui.sprinkler(self,World.cell(arg_value("capture-cell","43,34")))
		"copper":automation_ui.copper(self)
		"industry":industry_ui.device(self,World.cell(arg_value("capture-cell","42,36")))
		"forestry":forestry_ui.device(self,World.cell(arg_value("capture-cell","36,39")))
		"logistics":logistics_ui.device(self,World.cell(arg_value("capture-cell","39,37")))
		"tiller":_select_tool("till_area")
		"seeder":_select_tool("seed_area")
		"harvester":_select_tool("harvest_area")
		"clean":
			_close_modal()
			hud.hide()
			toast.hide()
		"quests":
			if village_art_preview and is_instance_valid(preview_tracker):preview_tracker.show()
	if modal is InventoryPanel:
		await get_tree().process_frame
		await get_tree().process_frame
		modal.select_category(clampi(int(arg_value("capture-category","0")),0,4))
		var item:=arg_value("capture-item","")
		if not item.is_empty() and modal.slots.has(item):
			modal.select_item(item)
			modal.slots[item].grab_focus()
		modal.layout_for(get_viewport().get_visible_rect().size)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	if arg_value("capture-panel","") in ["tiller","seeder","harvester"]:
		view.target=World.cell(arg_value("capture-cell","42,36"))
		view.show_target=true
		view.selected={"tiller":"till_area","seeder":"seed_area","harvester":"harvest_area"}[arg_value("capture-panel","")]
		view.queue_redraw()
	if arg_value("capture-action","")!="":
		await _capture_farm_sequence()
		return
	await RenderingServer.frame_post_draw
	var picture:=get_viewport().get_texture().get_image()
	picture.save_png(arg_value("capture",""))
	print("CAPTURE_SAVED")
	if "--capture-exit" in OS.get_cmdline_user_args():_quit()

func _capture_farm_sequence() -> void:
	# Opt-in local QA recording: execute the same authoritative action as a click.
	var action:=arg_value("capture-action","")
	var loopback_qa:bool="--capture-loopback" in OS.get_cmdline_user_args() and address_input.text.strip_edges()=="ws://127.0.0.1:%d"%int(port_input.text)
	if not (local_mode or loopback_qa) or not playing or action not in ["till_area","seed_area","harvest_area","hoe","seed","water","harvest","livestock_brush","chicken_hug","observe_weather"]:
		push_error("Farm sequence requires a local farm action")
		get_tree().quit(1)
		return
	var destination:=arg_value("capture","")
	var directory:=destination.get_basename()+".frames"
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	var before:Dictionary=session.snapshot.duplicate(true)
	if action in ["livestock_brush","chicken_hug"]:
		var button_name:="SheepBrush" if action=="livestock_brush" else "ChickenHug"
		var brush:=modal.find_child(button_name,true,false) as Button if is_instance_valid(modal) else null
		if brush==null or brush.disabled:
			push_error("Local capture requires the available care button: "+button_name)
			get_tree().quit(1)
			return
		get_viewport().get_texture().get_image().save_png(destination.get_basename()+"-before.png")
		brush.pressed.emit()
	else:
		if modal:_close_modal()
		if action in ["hoe","seed","water","harvest"]:
			selected=action
			view.selected=action
		if action!="observe_weather":session.perform(action,World.cell(arg_value("capture-cell","42,36")),crop if action in ["seed_area","seed"] else "")
	var records:Array=[]
	var started:=Time.get_ticks_msec()
	for index in range(clampi(int(arg_value("capture-frames","36")),12,80)):
		if action=="chicken_hug" and index==int(arg_value("capture-release-frame","-1")):_interact()
		await RenderingServer.frame_post_draw
		var picture:=get_viewport().get_texture().get_image()
		var filename:="%03d.png"%index
		if picture.save_png(directory.path_join(filename))!=OK:
			get_tree().quit(1)
			return
		if index==6:picture.save_png(destination)
		var shelter_at:Vector2=view.sheep_shelter.offset(view.elapsed,view.reduced_motion or view.photograph_mode)
		records.append({"file":filename,"ms":Time.get_ticks_msec()-started,"camera":view.camera,
			"shelter_offset":[shelter_at.x,shelter_at.y],"chickens":view.chicken_draw_stats.duplicate(),
			"tool_hint_visible":selected_label.visible,
			"tool_pose":view.tool_action_plan(session.own_id),"animal_feedback":view.livestock_pet_feedback.duplicate(true),
			"feedback":view.farm_feedback.active(session.own_id,view.elapsed).duplicate(true)})
		await get_tree().create_timer(0.05).timeout
	var evidence:=FileAccess.open(directory.path_join("sequence.json"),FileAccess.WRITE)
	if evidence==null:
		get_tree().quit(1)
		return
	evidence.store_string(JSON.stringify({"action":action,"reduced_motion":view.reduced_motion,"before":before,"after":session.snapshot,"frames":records}))
	evidence.close()
	print("CAPTURE_SAVED FARM_SEQUENCE frames=%d"%records.size())
	if "--capture-exit" in OS.get_cmdline_user_args():_quit()

func arg_value(name:String,fallback:String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"+name+"="):return arg.trim_prefix("--"+name+"=")
	return fallback

func server_setting(name:String,environment:String,fallback:String) -> String:
	var value:=OS.get_environment(environment)
	return arg_value(name,value if not value.is_empty() else fallback)

func binding_label(action:String) -> String:
	return bindings.label(action)

func binding_text(text:String) -> String:
	text=text.replace("{movement}",movement_hint())
	for action in InputBindings.DEFAULTS:text=text.replace("{"+action+"}",binding_label(action))
	return text

func movement_hint() -> String:
	return "/".join([binding_label("move_up"),binding_label("move_left"),binding_label("move_down"),binding_label("move_right")])

func _bindings_menu() -> void:
	var controls:=InputBindingsPanel.new()
	controls.setup(self)
	bindings_panel=controls

func _bindings_changed() -> void:
	view.interaction_key_label=binding_label("interact")
	if village_art_preview:LifeShell.refresh_binding_hints(self)
	else:_refresh_bound_controls(hud)
	_refresh_bound_controls(menu)
	_select_tool(selected,true)
	_refresh_hud()

func bound_button(title:String,action:String,callback:Callable) -> Button:
	var control:=button(title+"  "+binding_label(action),callback)
	control.set_meta("binding_caption",title)
	control.set_meta("binding_action",action)
	return control

func _refresh_bound_controls(parent:Node) -> void:
	for child in parent.get_children():
		if child.has_meta("binding_template"):child.text=binding_text(child.get_meta("binding_template"))
		if child is Button and child.has_meta("binding_action"):
			child.text=String(child.get_meta("binding_caption"))+"  "+binding_label(child.get_meta("binding_action"))
		_refresh_bound_controls(child)

func _world_keyboard_allowed() -> bool:
	if voyage_active:return false
	if not playing or modal!=null or (menu and menu.visible):return false
	var focus:=get_viewport().gui_get_focus_owner()
	return not (focus is LineEdit or focus is TextEdit)

func movement_direction() -> Vector2:
	if controller_protected or not _world_keyboard_allowed():return Vector2.ZERO
	var keyboard:=Vector2(float(bindings.pressed("move_right"))-float(bindings.pressed("move_left")),
		float(bindings.pressed("move_down"))-float(bindings.pressed("move_up")))
	if keyboard!=Vector2.ZERO:return keyboard
	var strongest:=Vector2.ZERO
	for stick:Vector2 in controller_sticks.values():
		if stick.length_squared()>strongest.length_squared():strongest=stick
	var magnitude:=strongest.length()
	if magnitude<=0.22:return Vector2.ZERO
	return strongest/magnitude*remap(minf(magnitude,1.0),0.22,1.0,0.0,1.0)

func _controller_connection_changed(device:int,connected:bool) -> void:
	if not connected:
		if gather_hold.get("device",GATHER_NONE)==device:gather_hold.clear()
		var stick:Vector2=controller_sticks.get(device,Vector2.ZERO)
		controller_sticks.erase(device)
		var was_active:=device==controller_device
		if was_active:
			controller_device=-1
			controller_navigation=false
			if controller_aim:area_drag=false
			controller_aim=false
		if playing and (was_active or stick.length()>0.22):
			var remaining:=movement_direction()
			if not local_mode and remaining.is_zero_approx():
				controller_protected=true
				session.perform("controller_hold",Vector2i.ZERO)
			session.input_direction(remaining)
			_notice("手把已斷線，角色留在原地。可用手把或鍵盤滑鼠繼續。" if controller_protected else "手把已斷線。可重新連接手把，或用鍵盤滑鼠繼續。",false)
	elif not playing:
		controller_navigation=true
		_focus_title.call_deferred()

func _focus_title() -> void:
	if not playing and is_instance_valid(menu) and menu.is_visible_in_tree():_focus_controller_menu(menu)

func area_modifier_held(event:InputEventWithModifiers) -> bool:
	match int(bindings.keys.get("area_modifier",KEY_NONE)):
		KEY_SHIFT:return event.shift_pressed
		KEY_CTRL:return event.ctrl_pressed
		KEY_ALT:return event.alt_pressed
	return false

func _cancel_navigation() -> void:
	if LifeTasks.achao_return_if_sailing(self):return
	if is_instance_valid(bindings_panel) and bindings_panel.cancel_capture():return
	if capture_drag:
		capture_drag=false
		_notice("已取消這次框選，仍在框選模式；再按 Esc 離開。",true)
		return
	if area_drag or moving_object:
		area_drag=false;moving_object=false;_select_tool(selected)
	elif modal and undo_ui.cancel_confirmation():pass
	elif modal and modal.has_meta("return_to_travel_ticket"):
		var return_to_ticket:Callable=modal.get_meta("return_to_travel_ticket")
		return_to_ticket.call()
	elif modal:_close_modal()
	elif _blueprint_mode() in BLUEPRINT_LOCAL_MODES:
		# Only unsubmitted capture/placing is cancelled; sent work stays pending.
		var word:="框選" if _blueprint_mode()=="capture" else "放置"
		if blueprints.cancel():_notice("已取消藍圖%s，沒有施工也沒有扣除材料。"%word,true)
	elif WanganUI.dismiss(self):pass # 望安下船卡：Esc 先收起卡片，再按一次才開選單。
	elif TravelUI.dismiss_arrival(self):pass
	else:_pause_menu()

func _display_notice(message:String) -> String:
	# Translate exact legacy server messages before expanding client placeholders.
	# A user's chosen key must never be mistaken for another action's default key.
	var messages:={
		"這種種子用完了，按 C 換種子或到攤位購買":"這種種子用完了，按 {seeds} 換種子或到攤位購買",
		"風鈴接力開始！跟著金色風鈴靠近按 E，共同收集 12 次。沒有失敗倒數。":"風鈴接力開始！跟著金色風鈴靠近按 {interact}，共同收集 12 次。沒有失敗倒數。",
		"走到金色風鈴身邊，再按 E 接住":"走到金色風鈴身邊，再按 {interact} 接住",
		"魚竿已經放好了，等魚咬鉤後按空白鍵":"魚竿已經放好了，咬鉤後%s收竿"%_fishing_reel_hint(),
		"魚竿放好了。等提示出現，再按空白鍵收竿":"魚竿放好了。咬鉤後%s收竿"%_fishing_reel_hint(),
		"買到一棵樹苗，按 C 選樹苗，再點空地種下":"買到一棵樹苗，按 {seeds} 選樹苗，再點空地種下",
		"完成居民委託就能取得這張圖樣，按 J 查看故事":"完成居民委託就能取得這張圖樣，按 {journal} 查看故事"}
	return binding_text(messages.get(message,message))

func theme() -> Theme:
	var t:=Theme.new()
	t.default_font=preload("res://scripts/island_type.gd").regular()
	t.default_font_size=scaled_font_size(17)
	t.set_meta("font_scale_base",17)
	t.set_color("font_color","Label",Color("334b3c"))
	t.set_color("font_color","Button",Color("3d5543"))
	t.set_color("font_hover_color","Button",Color("2b4838"))
	t.set_color("font_pressed_color","Button",Color("fff1cf"))
	t.set_stylebox("normal","Button",box(Color("f5e8cb"),Color("d5c6a1"),7))
	t.set_stylebox("hover","Button",box(Color("e9dbb5"),Color("8d9e72"),7))
	t.set_stylebox("pressed","Button",box(Color("66876b"),Color("4e7058"),7))
	t.set_stylebox("focus","Button",box(Color(0,0,0,0),Color("6b8b67"),7,2))
	t.set_stylebox("normal","LineEdit",box(Color("fff6df"),Color("cabb94"),5))
	t.set_stylebox("focus","LineEdit",box(Color("fff6df"),Color("78936b"),5,2))
	t.set_color("font_color","LineEdit",Color("344b3b"))
	t.set_color("caret_color","LineEdit",Color("344b3b"))
	t.set_color("font_placeholder_color","LineEdit",Color("7b846b"))
	return LifeTheme.apply(t) if village_art_preview else t

func box(color:Color,border:Color,radius:int=10,width:int=1) -> StyleBoxFlat:
	var b:=StyleBoxFlat.new()
	b.bg_color=color
	b.border_color=border
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.content_margin_left=16
	b.content_margin_right=16
	b.content_margin_top=12
	b.content_margin_bottom=12
	return b

func panel(parent:Node,rect:Rect2) -> PanelContainer:
	var p:=PanelContainer.new()
	p.position=rect.position
	p.size=rect.size
	p.add_theme_stylebox_override("panel",LifeTheme.panel_style() if village_art_preview else box(Color("fff1d8"),Color("c7bb94"),12))
	parent.add_child(p)
	return p

func label(text:String,size_value:int=17) -> Label:
	var l:=Label.new()
	l.text=binding_text(text)
	if text.contains("{"):l.set_meta("binding_template",text)
	var scaled_size:=scaled_font_size(size_value)
	l.add_theme_font_size_override("font_size",scaled_size)
	l.set_meta("font_scale_base",size_value)
	l.set_meta("font_scale_applied",scaled_size)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return l

func button(text:String,callback:Callable) -> Button:
	var b:=Button.new()
	b.text=binding_text(text)
	if text.contains("{"):b.set_meta("binding_template",text)
	b.custom_minimum_size=Vector2(0,42)
	b.pressed.connect(callback)
	return b

func _make_menu() -> void:
	if village_art_preview:LifeHome.make_menu(self);return
	menu=Control.new()
	menu.theme=theme()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var bg:=ColorRect.new()
	bg.color=Color("a7c78e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	# Decorative blocks echo a pixel island without relying on external assets.
	for i in range(18):
		var tile:=ColorRect.new()
		tile.position=Vector2(70+(i*173)%1150,40+(i*137)%700)
		tile.size=Vector2(24+(i%3)*16,24+(i%3)*16)
		tile.color=Color("90b581") if i%2==0 else Color("b8d298")
		menu.add_child(tile)
	var p:=panel(menu,Rect2(340,50,600,700))
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",12)
	p.add_child(col)
	col.add_child(label("TUAN TUAN ISLAND",14))
	col.add_child(label("糰糰島",48))
	col.add_child(label("一起種一片田，慢慢蓋一個家。",22))
	col.add_child(label("Windows 可玩原型 · 固定俯視角 · 多人連線",14))
	col.add_child(title_build_label())
	col.add_child(HSeparator.new())
	var row:=HBoxContainer.new()
	col.add_child(row)
	var name_label:=label("島民名字",16)
	name_label.custom_minimum_size.x=90
	name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	row.add_child(name_label)
	name_input=LineEdit.new()
	name_input.text="小糰"
	name_input.max_length=12
	name_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(name_input)
	var solo:=button("住進自己的小島  ·  本機保存",func():_host(false))
	solo.name="TitleSolo"
	col.add_child(solo)
	col.add_child(button("開啟朋友房間  ·  區域網路",func():_host(true)))
	col.add_child(label("朋友房間需由這台電腦持續開啟；雲端部署尚未設定。",13))
	var connection:=HBoxContainer.new()
	col.add_child(connection)
	address_input=LineEdit.new()
	address_input.text="127.0.0.1"
	address_input.placeholder_text="伺服器位址，或完整 wss:// 網址"
	address_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	connection.add_child(address_input)
	port_input=LineEdit.new()
	port_input.text="28417"
	port_input.custom_minimum_size.x=90
	connection.add_child(port_input)
	key_input=LineEdit.new()
	key_input.placeholder_text="朋友房間密碼（開房時也使用此欄）"
	key_input.secret=true
	col.add_child(key_input)
	col.add_child(button("加入朋友的小島",_join))
	col.add_child(label("{movement} 移動  ·  左鍵使用工具  ·  {interact} 互動\n工具鍵可自訂  ·  {build_menu} 建造  ·  {inventory} 背包  ·  Esc 選單",15))
	col.add_child(label("作物以 75–150 秒成熟供測試；關閉世界會暫停生長。\n原型不含正式帳號服務，僅供自己的電腦或可信任區網測試。",13))
	toast=label("歡迎來到島上。先替自己取個名字吧。",16)
	toast.position=Vector2(270,755)
	toast.size=Vector2(740,40)
	toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color",Color("fff3d7"))
	ui.add_child(toast)

func _make_hud() -> void:
	activity_caption=label("",17)
	activity_caption.name="ActivityCaption"
	activity_caption.add_theme_font_override("font",preload("res://scripts/island_type.gd").regular())
	activity_caption.size=Vector2(400,32)
	activity_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	activity_caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	activity_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	activity_caption.add_theme_stylebox_override("normal",LifeTheme.badge_style())
	activity_caption.add_theme_color_override("font_color",Color("314c3b"))
	activity_caption.hide()
	ui.add_child(activity_caption)
	hud=Control.new()
	hud.theme=theme()
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.visible=false
	ui.add_child(hud)
	voyage_return=button("返回碼頭 · Esc",func():LifeTasks.achao_return_if_sailing(self))
	voyage_return.name="VoyageReturn"
	ui.add_child(voyage_return)
	voyage_return.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	voyage_return.offset_left=-100
	voyage_return.offset_right=100
	voyage_return.offset_top=-63
	voyage_return.offset_bottom=-18
	voyage_return.hide()
	voyage_photo=button("拍船上合照",LifeTasks.achao_take_photo.bind(self))
	voyage_photo.name="VoyagePhoto"
	ui.add_child(voyage_photo)
	voyage_photo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	voyage_photo.offset_left=-100
	voyage_photo.offset_right=100
	voyage_photo.offset_top=-113
	voyage_photo.offset_bottom=-68
	voyage_photo.hide()
	if village_art_preview:
		LifeShell.make_hud(self)
		_select_tool("hoe")
		_layout_preview.call_deferred()
		return
	var toolbar: PanelContainer
	if village_art_preview:
		toolbar=_make_preview_hud()
	else:
		toolbar=_make_standard_hud()
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",4 if village_art_preview else 6)
	toolbar.add_child(col)
	selected_label=label("",14)
	col.add_child(selected_label)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",5)
	col.add_child(row)
	var names:=["{hoe} 鋤頭","{seed} 種子","{water} 澆水","{harvest} 採收","{axe} 斧頭","{pick} 十字鎬","{build} 建造","{remove} 拆除"]
	var actions:=["hoe","seed","water","harvest","axe","pick","build","remove"]
	for i in range(names.size()):
		var action:String=actions[i]
		var b:=button(names[i],func():_select_tool(action))
		if village_art_preview:
			b.custom_minimum_size.y=44
			b.add_theme_font_size_override("font_size",15)
		b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		b.toggle_mode=true
		row.add_child(b)
		tool_buttons.append(b)
	_select_tool("hoe")
	if village_art_preview:_layout_preview.call_deferred()

func _make_standard_hud() -> PanelContainer:
	var title_panel:=panel(hud,Rect2(22,18,280,78))
	var title_col:=VBoxContainer.new()
	title_panel.add_child(title_col)
	var location_title:=label("風鈴渡口",22)
	location_title.name="RegionTitle"
	title_col.add_child(location_title)
	status_label=label("世界剛剛甦醒",13)
	title_col.add_child(status_label)
	var objectives:=panel(hud,Rect2(22,112,260,210))
	var objective_col:=VBoxContainer.new()
	objective_col.add_theme_constant_override("separation",10)
	objectives.add_child(objective_col)
	objective_col.add_child(label("今天，讓小島多一點改變",18))
	objective=label("",15)
	objective_col.add_child(objective)
	objective_col.add_child(button("看看操作與玩法",_help))
	var inv:=panel(hud,Rect2(22,338,260,220))
	var inv_col:=VBoxContainer.new()
	inv.add_child(inv_col)
	inv_col.add_child(label("隨身口袋",18))
	inventory_label=label("",15)
	inv_col.add_child(inventory_label)
	inv_col.add_child(button("打開背包  {inventory}",_inventory))
	var top:=HBoxContainer.new()
	top.position=Vector2(880,22)
	top.size=Vector2(380,48)
	hud.add_child(top)
	top.add_child(button("釣魚 {fish}",func():_select_tool("fish")))
	top.add_child(button("建造  {build_menu}",_build_menu))
	top.add_child(button("選單  Esc",_pause_menu))
	return panel(hud,Rect2(310,684,948,96))

func _make_preview_hud() -> PanelContainer:
	var location:=panel(hud,Rect2(18,16,234,70))
	var location_content:=VBoxContainer.new()
	location.add_child(location_content)
	var location_title:=label("風鈴渡口",17)
	location_title.name="RegionTitle"
	location_content.add_child(location_title)
	status_label=label("",13)
	location_content.add_child(status_label)
	var tracker:=panel(hud,Rect2(18,146,268,0))
	preview_tracker=tracker
	var tracker_content:=VBoxContainer.new()
	tracker.add_child(tracker_content)
	objective=label("",14)
	tracker_content.add_child(objective)
	tracker_content.add_child(button("共同工程",_board))
	tracker_content.add_child(button("居民手帳 {journal}",_journal))
	tracker_content.add_child(button("操作與玩法",_help))
	tracker.hide()
	var toggle:=button("任務追蹤",func():tracker.visible=not tracker.visible)
	toggle.position=Vector2(18,94)
	toggle.size=Vector2(128,44)
	toggle.custom_minimum_size.y=44
	hud.add_child(toggle)
	var top:=HBoxContainer.new()
	preview_top=top
	top.add_theme_constant_override("separation",6)
	hud.add_child(top)
	coin_label=label("鈴幣 120",16)
	coin_label.custom_minimum_size.x=100
	coin_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	coin_label.add_theme_stylebox_override("normal",LifeTheme.compact_style())
	top.add_child(coin_label)
	for entry in [["背包 {inventory}",_inventory],["建造 {build_menu}",_build_menu],["手帳 {journal}",_journal],["選單 Esc",_pause_menu]]:
		var b:=button(entry[0],entry[1])
		b.custom_minimum_size=Vector2(102,44)
		top.add_child(b)
	var toolbar:=panel(hud,Rect2(190,694,900,90))
	preview_toolbar=toolbar
	preview_controls.append_array([location,toggle,tracker,toolbar,top])
	return toolbar

func _layout_preview() -> void:
	_layout_blueprint_strip()
	if not village_art_preview or not is_instance_valid(preview_toolbar):return
	var bounds:=get_viewport().get_visible_rect().size
	LifeShell.layout_hud(self,bounds)
	WanganUI.layout(self,bounds)
	if playing:
		var toast_right:float=bounds.x
		if is_instance_valid(blueprint_strip) and (_blueprint_mode()!="idle" or blueprints.busy()) and modal==null:
			toast_right=blueprint_strip.position.x-16.0
		var toast_width:float=minf(740.0,maxf(240.0,toast_right-32.0))
		toast.size=Vector2(toast_width,maxf(36,toast.get_minimum_size().y))
		toast.position=Vector2((toast_right-toast_width)/2,bounds.y-160-toast.size.y)
	if is_instance_valid(modal):
		if modal is InventoryPanel or modal is ShippingPanel:
			modal.layout_for(bounds)
			return
		modal.size=Vector2(minf(860,bounds.x-48),minf(620,bounds.y-96))
		modal.position=(bounds-modal.size)/2
		if modal.get_meta("catalog",false):
			modal.size=Vector2(minf(920,bounds.x-48),minf(620,bounds.y-64))
			modal.position=(bounds-modal.size)/2
		if modal.get_meta("shop_catalog",false) or modal.get_meta("short_catalog",false):
			modal.size=Vector2(minf(920,bounds.x-48),minf(500,bounds.y-64))
			modal.position=(bounds-modal.size)/2
		match str(modal.get_meta("life_modal_layout","")):
			"livestock_card":
				modal.size=Vector2(minf(510,bounds.x-48),minf(470 if modal.has_meta("sheep_brushing") else 415,bounds.y-48))
				modal.position=Vector2(bounds.x-modal.size.x-24,bounds.y-modal.size.y-24)
			"build_folio":
				modal.size=Vector2(minf(920,bounds.x-40),minf(590,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"hoist_letter":
				modal.size=Vector2(minf(860,bounds.x-48),minf(592,bounds.y-40))
				modal.position=(bounds-modal.size)/2
			"blueprint_folio":
				_fit_blueprint_folio(bounds)
			"cooking_queue":
				CookingQueueUI.layout(self,bounds)
			"market_stall":
				MarketUI.layout(self,bounds)
			"harvest_relay":
				HarvestUI.layout(self,bounds)
			"fishing_meet":
				FishMeetUI.layout(self,bounds)
			"showcase":
				ShowcaseUI.layout(self,bounds)
			"souvenir_exchange":
				SouvenirUI.layout(self,bounds)
			"memory_exhibit":
				MemoryExhibitUI.layout(self,bounds)
			"lanyang_revisit":
				RevisitUI.layout(self,bounds)
			"diversion_gate","water_share_plaque":
				GateUI.layout(self,bounds)
			"water_tower":
				TowerUI.layout(self,bounds)
			"jinguashi_revisit","mine_lantern":
				JgRevisitUI.layout(self,bounds)
			"tea_revisit","tea_ware":
				TeaRevisitUI.layout(self,bounds)
			"salt_revisit","salt_basket":
				SaltRevisitUI.layout(self,bounds)
			"salt_brine":
				SaltBrineUI.layout(self,bounds)
			"gold_panning":
				GoldPanUI.layout(self,bounds)
			"ore_route":
				OreRouteUI.layout(self,bounds)
			"mine_drill":
				modal.size=Vector2(minf(440,bounds.x-48),minf(590,bounds.y-48))
				modal.position=Vector2(bounds.x-modal.size.x-24,(bounds.y-modal.size.y)/2)
			"waterworks":
				modal.size=Vector2(minf(900,bounds.x-48),minf(570,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"keepsake_paper":
				modal.size=Vector2(minf(690,bounds.x-48),minf(420,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"welcome_sign_read", "welcome_sign_edit":
				var height:=460.0 if modal.get_meta("life_modal_layout")=="welcome_sign_edit" else 310.0
				modal.size=Vector2(minf(520,bounds.x-48),minf(height,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"inn_tea_table", "inn_wardrobe":
				modal.size=Vector2(minf(520,bounds.x-48),minf(360,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"station_dialogue":
				modal.size=Vector2(minf(900,bounds.x-48),minf(320,bounds.y-48))
				modal.position=Vector2((bounds.x-modal.size.x)/2,bounds.y-modal.size.y-24)
			"station_memory":
				modal.size=Vector2(minf(820,bounds.x-48),minf(510,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"history_memory":
				var mining_history:bool=modal.get_meta("history_mode","")=="jinguashi"
				modal.size=Vector2(minf(670 if mining_history else 860,bounds.x-48),minf(510 if mining_history else 580,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"lanyang_garden":
				var clearing:bool=modal.get_meta("garden_mode","")=="clear"
				modal.size=Vector2(minf(640 if clearing else 780,bounds.x-48),minf(410 if clearing else 500,bounds.y-48))
				modal.position=(bounds-modal.size)/2
				if clearing:modal.position.y=bounds.y-modal.size.y-24
			"mine_station":
				# T067: entry lists hoist landings and deep service/lift cards carry zone notes.
				# T067 table warmer: the rest card also lists the floor's extra finds.
				var mine_tall:bool=str(modal.get_meta("mine_site","")) in ["service","entry","lift","rest"]
				modal.size=Vector2(minf(480,bounds.x-48),minf(592 if mine_tall else 420,bounds.y-48))
				modal.position=Vector2(bounds.x-modal.size.x-24,bounds.y-modal.size.y-28)
			"mine_survey":
				var observing:bool=modal.get_meta("survey_observe")
				# T067: the journal index lists fifteen floors (three columns of five).
				modal.size=Vector2(minf(480 if observing else 600,bounds.x-48),minf(320 if observing else 460,bounds.y-48))
				modal.position=(bounds-modal.size)/2
				if observing:modal.position.y=bounds.y-modal.size.y-24
			"auto_freight":
				modal.size=Vector2(minf(820,bounds.x-48),minf(510,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"mine_freight":
				modal.size=Vector2(minf(780,bounds.x-48),minf(400 if modal.get_meta("freight_summary",false) else 550,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"bobo_sort":
				modal.size=Vector2(minf(700,bounds.x-48),minf(float(modal.get_meta("sort_height",480)),bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"travel_map":
				modal.size=Vector2(minf(880,bounds.x-48),minf(580,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"community_table":
				# T067: the table page also carries the 保溫底座 card; sized to its content.
				CommunityUI.layout(self,bounds)
			"public_kitchen":
				preload("res://scripts/public_kitchen_ui.gd").layout(self,bounds)
			"chapter_letter":
				modal.size=Vector2(minf(700,bounds.x-48),minf(540,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"house_check":
				modal.size=Vector2(minf(640,bounds.x-48),minf(560,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"roof_confirm":
				modal.size=Vector2(minf(600,bounds.x-48),minf(float(modal.get_meta("roof_height",360)),bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"flower_nursery":FlowerUI.layout(self,bounds)
			"salt_pan":SaltUI.layout(self,bounds)
			"tea_ceramics":
				var tea_height:float=modal.get_meta("tea_height",360.0)
				var tea_width:float=modal.get_meta("tea_width",540.0)
				modal.size=Vector2(minf(tea_width,bounds.x-48),minf(tea_height,bounds.y-48))
				modal.position=(bounds-modal.size)/2
				if modal.get_meta("tea_dialogue",false):modal.position.y=bounds.y-modal.size.y-28
			"island_map":
				modal.size=Vector2(minf(700,bounds.x-48),minf(592,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"controller_shortcuts":
				modal.size=Vector2(minf(600.0,bounds.x-48.0),minf(334.0,bounds.y-48.0))
				modal.position=((bounds-modal.size)*0.5).floor()
			"pause_drawer":
				modal.size=Vector2(390,minf(600,bounds.y-48))
				modal.position=Vector2(bounds.x-modal.size.x-24,(bounds.y-modal.size.y)/2)
			"resident_dialogue":
				var dialogue_height:=376.0+320.0*maxf(0.0,font_scale_factor()-1.0)
				modal.size=Vector2(minf(900,bounds.x-48),minf(dialogue_height,bounds.y-80))
				modal.position=Vector2((bounds.x-modal.size.x)/2,bounds.y-modal.size.y-24)
			"community_board":
				modal.size=Vector2(minf(760,bounds.x-48),minf(560,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"return_news", "night_rest":
				modal.size=Vector2(minf(530,bounds.x-48),minf(350,bounds.y-64))
				modal.position=((bounds-modal.size)/2).floor()
			"orders_board":
				# T055 cards add a status line and accept/cancel next to delivery.
				modal.size=Vector2(minf(780,bounds.x-48),minf(540,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"trade_review":
				modal.size=Vector2(minf(660,bounds.x-48),minf(410,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"trade_editor":
				modal.size=Vector2(minf(660,bounds.x-48),minf(540,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"settings":
				modal.size=Vector2(minf(600,bounds.x-48),minf(560,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"automation_workbench":
				modal.size=Vector2(minf(900,bounds.x-48),minf(520,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"industry_device":
				modal.size=Vector2(minf(520,bounds.x-48),minf(370,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"workshop_guide":
				modal.size=Vector2(minf(940,bounds.x-48),minf(570,bounds.y-48))
				modal.position=(bounds-modal.size)/2
			"forestry_device":
				modal.size=Vector2(minf(820,bounds.x-48),minf(560,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"logistics_device":
				modal.size=Vector2(minf(820,bounds.x-48),minf(490,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"logistics_processor":
				modal.size=Vector2(minf(650,bounds.x-48),minf(540,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"automation_device":
				modal.size=Vector2(minf(640,bounds.x-48),minf(450,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"automation_copper":
				modal.size=Vector2(minf(640,bounds.x-48),minf(410,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"resident_journal":
				modal.size=Vector2(minf(900,bounds.x-48),minf(580,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"collection_almanac":
				modal.size=Vector2(minf(860,bounds.x-48),minf(470,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"shop_catalog","short_catalog":
				modal.size=Vector2(minf(920,bounds.x-48),minf(500,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"festival_locked":
				modal.size=Vector2(minf(540,bounds.x-48),minf(330,bounds.y-64))
				modal.position=(bounds-modal.size)/2
			"festival_card":
				var has_food:=modal.find_child("FestivalChowder",true,false)!=null
				modal.size=Vector2(minf(700 if has_food else 620,bounds.x-48),minf(590 if has_food else 480,bounds.y-32))
				modal.position=(bounds-modal.size)/2
			"animal_card":
				modal.size=Vector2(minf(620,bounds.x-48),minf(480,bounds.y-64))
				modal.position=(bounds-modal.size)/2

func _world_pointer_allowed(point:Vector2) -> bool:
	if modal!=null:return false
	if is_instance_valid(blueprint_strip) and blueprint_strip.is_visible_in_tree() and blueprint_strip.get_global_rect().has_point(point):return false
	if not village_art_preview:return point.x>300 and point.y>90 and point.y<620
	if not get_viewport().get_visible_rect().has_point(point):return false
	for control in preview_controls:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point):return false
	return true

func _host(lan:bool,mode:="life") -> void:
	var port:=int(port_input.text)
	if port<1024 or port>65535:_notice("連接埠請填 1024 到 65535。",false);return
	if lan and key_input.text.length()<4:_notice("朋友房間請先填至少四個字的密碼。",false);return
	local_mode=not lan
	blueprint_join_scope=""
	var profile_path:="user://world-friends" if lan else "user://world-local"
	if mode=="adventure":profile_path+="-adventure"
	var path:=arg_value("save",profile_path+".json")
	session.host(port,name_input.text,path,key_input.text if lan else "","0.0.0.0" if lan else "127.0.0.1",false,"enet",not lan,mode)

func _join() -> void:
	var port:=int(port_input.text)
	if port<1024 or port>65535 or address_input.text.strip_edges().is_empty():_notice("請填有效的位址與連接埠。",false);return
	local_mode=false
	_notice("正在連進朋友的小島…",true)
	blueprint_join_scope=_blueprint_address_scope(address_input.text,port)
	var err:int=session.join(address_input.text.strip_edges(),port,name_input.text,key_input.text)
	if err!=OK:_notice("無法建立連線，請檢查位址。",false)

func _entered() -> void:
	playing=true
	if sound:sound.set_world(session.snapshot,session.own_id)
	# Scope must be read before join_result clears the identity world being joined.
	_blueprint_setup()
	if is_instance_valid(identity_entry) and identity_entry.joining:identity_entry.join_result(true,"已連入島嶼。")
	menu.hide()
	hud.show()
	toast.position=Vector2(248,654) if village_art_preview else Vector2(335,628)
	toast.size=Vector2(784,36) if village_art_preview else Vector2(880,44)
	toast.add_theme_color_override("font_color",Color("314c3b"))
	if village_art_preview:
		toast.add_theme_stylebox_override("normal",LifeTheme.badge_style())
		toast.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		_layout_preview()
	var next:Dictionary=World.CHAPTER_ONE.next_step(session.snapshot)
	if str(session.snapshot.get("region_id","home"))=="lanyang":
		_notice("歡迎回到蘭陽田區。沿水圳耕作，M 可查看回程路口。",true)
	elif str(session.snapshot.get("region_id","home"))=="jinguashi":
		_notice("歡迎回到金瓜石。帶強化石鎬採礦，回候車路口可免費返家。",true)
	elif str(session.snapshot.get("region_id","home")).begins_with("mine_"):
		_notice("回到礦道了。留意體力，休息站可補水，上行出口能原路返家。",true)
	elif str(session.snapshot.get("region_id","home")) in World.TRANSIT.LOCAL:
		var arrival_region:=str(session.snapshot.region_id)
		_notice("歡迎回到%s。%s"%[World.REGIONS.label(arrival_region),TravelUI.NOTES[arrival_region]],true)
	elif WanganOpening.is_new_arrival(session.snapshot,session.own_id):
		# 望安開場：剛下船的新島民看到下船卡（取代一般提示），左上角接著帶路。
		WanganUI.show_arrival(self)
	else:
		var crop_step:Dictionary=World.CHAPTER_ONE.first_crop_step(session.snapshot,session.own_id)
		var return_hint:String=str(crop_step.get("text",next.action)).replace("\n","，")
		_notice("歡迎回來！"+return_hint+"。",true)
	get_viewport().gui_release_focus()
	return_news_pending=true
	if return_news_snapshot_received:_offer_return_news(session.snapshot)

func _offer_return_news(snapshot:Dictionary) -> void:
	if not return_news_pending or not snapshot.has("island_news"):return
	return_news_pending=false
	if not snapshot.island_news.get("returning",false) or modal!=null or voyage_active or WanganUI.card_open(self):return
	if LifeTasks.has_return_news(snapshot):LifeTasks.return_news(self,snapshot)

func _disconnected() -> void:
	playing=false
	gather_hold.clear()
	return_news_pending=false
	return_news_snapshot_received=false
	session.local_paused=false
	controller_protected=false
	activity_caption_time=0.0
	if activity_caption:activity_caption.hide()
	# The controller observes the Session itself (unknown on disconnect) and keeps
	# any pending record; Main only drops the local drag and refreshes the picture.
	capture_drag=false
	fishing_audio.reset()
	if sound:
		sound.stop_cues()
		sound.set_title()
	island_passport.clear()
	if is_instance_valid(identity_entry) and identity_entry.joining:
		identity_entry.join_result(false,"無法連上這座島，請確認地址或稍後重試。")
	if view:
		view.farm_feedback.reset()
		view.tool_feedback.reset() # T017：重連後第一份快照只當基準，不重播舊的工具動作。
		view.fishing_feedback.reset()
	WanganUI.dismiss(self)
	if hud:hud.hide()
	voyage_active=false
	if voyage_return:voyage_return.hide()
	if voyage_photo:voyage_photo.hide()
	if menu:menu.show()
	_blueprint_sync()
	if toast:
		toast.position=Vector2(270,755)
		toast.size=Vector2(740,40)
		toast.add_theme_color_override("font_color",Color("fff3d7"))
		if village_art_preview:
			toast.remove_theme_stylebox_override("normal")
			toast.vertical_alignment=VERTICAL_ALIGNMENT_TOP
	_close_modal()

func _sync_voyage_controls() -> void:
	voyage_return.visible=voyage_active
	var bond:Dictionary=session.snapshot.get("resident_bonds",{}).get("achao",{})
	voyage_photo.visible=voyage_active and int(bond.get("stage",0))>=4

func _state_changed(snapshot:Dictionary,id:String) -> void:
	if snapshot.has("island_news"):return_news_snapshot_received=true
	var ballot_id:=int(snapshot.get("night_vote",{}).get("id",0))
	var old_ballot:=int(view.data.get("night_vote",{}).get("id",0)) if view else 0
	if playing and modal==null and ballot_id>0 and ballot_id!=old_ballot:
		_notice("有人提議休息到清晨。開啟遊戲選單即可投票。",true)
	_refresh_night_vote(snapshot)
	var previous_trade:Dictionary=view.data.get("own_trade",{}) if view else {}
	var origin:=str(view.data.get("region_id","")) if view and not view.data.is_empty() else ""
	var destination:=str(snapshot.get("region_id","home"))
	if sound and playing:
		var settled:bool=sound.music.world_region==destination
		sound.set_world(snapshot,id)
		if settled and view:sound.music.play_milestone(SoftAudio.Music.milestone_for(view.data,snapshot))
	if view and playing and sound.activity_captions:
		var finished:=SoftAudio.completed_batch(view.data,snapshot,id)
		if not finished.is_empty():_caption("%s完工，可以領取成品。"%finished,1)
	if view and not view.data.is_empty() and str(view.data.get("region_id","home"))!=str(snapshot.get("region_id","home")):
		gather_hold.clear()
		activity_caption_time=0.0
		island_messages.clear()
		_close_modal()
		area_drag=false
		capture_drag=false
		moving_object=false
		target=Vector2i.ZERO
		get_viewport().gui_release_focus()
	if view:
		if playing and village_art_preview and origin==World.REGIONS.HOME and destination==origin:
			var previous_crop_step:Dictionary=World.CHAPTER_ONE.first_crop_step(view.data,id)
			var next_crop_step:Dictionary=World.CHAPTER_ONE.first_crop_step(snapshot,id)
			if previous_crop_step.get("id")!=next_crop_step.get("id"):
				# Pair the next hint with the confirmed field change in the next frame.
				ui_clock=0.2
		var previous_push:float=view.ore_cart_push_started
		var fresh_tools:Array=view.update_snapshot(snapshot,id)
		if sound and playing:
			if is_finite(view.ore_cart_push_started) and previous_push!=view.ore_cart_push_started:
				sound.play_cart_roll(view.ore_cart_travel_seconds(World.ORE_ROUTE.stage(snapshot)))
			var listener:Dictionary=snapshot.get("players",{}).get(id,{})
			if not listener.is_empty():
				sound.play_nearby_tools(fresh_tools,view.tool_feedback.actions,id,Vector2(listener.x,listener.y))
				if id in fresh_tools and view.tool_feedback.actions[id].tool=="harvest":_caption("採收完成，作物已收入背包。",1)
	if playing and is_instance_valid(voyage_return):
		var sailing:bool=snapshot.get("players",{}).get(id,{}).get("at_sea",false)
		if sailing!=voyage_active:
			voyage_active=sailing
			_sync_voyage_controls()
			hud.visible=not sailing
			if sailing:_close_modal()
		if sailing:toast.hide()
	var incoming_trade:Dictionary=snapshot.get("own_trade",{})
	if playing and not incoming_trade.is_empty() and incoming_trade.get("id")!=previous_trade.get("id") and incoming_trade.get("incoming",false):
		_notice("收到島民交換邀請。可在遊戲選單開啟「島民交換」，或按手把 View。",true)
	_blueprint_sync()
	LifeTasks.refresh_island_notes(self)
	LifeTasks.refresh_board_projects(self,snapshot)
	if is_instance_valid(modal) and modal.has_meta("island_passport"):
		var plot_status:=modal.find_child("PublicBuildPlotStatus",true,false) as Label
		if plot_status:plot_status.text=_public_build_plot_status(snapshot)
	if is_instance_valid(modal) and modal.has_meta("dock_project_status"):
		if modal.get_meta("dock_project_status")!=LifeTasks.dock_project_status(snapshot):
			LifeTasks.dock_project(self,modal.get_meta("dock_project_from_news",false))
	if is_instance_valid(modal) and modal.has_meta("festival_opening"):
		if modal.get_meta("festival_opening")!=[snapshot.get("festival_story",{}),snapshot.get("can_start_large_projects",true)]:
			LifeAlmanac.festival_story(self,modal.get_meta("festival_from_journal",false))
	preload("res://scripts/trade_ui.gd").refresh(self,snapshot)
	if playing and selected=="fish" and is_instance_valid(selected_label):
		var angler:Dictionary=snapshot.get("players",{}).get(id,{})
		if not angler.is_empty():_refresh_fishing_hint(snapshot,angler)
	for cue:String in fishing_audio.update(snapshot,id):
		if sound and playing:
			sound.play_cue(cue)
			if cue=="fish_bite":
				var cast:Dictionary=snapshot.get("players",{}).get(id,{}).get("fishing",{})
				_caption("魚咬鉤了！%s%s。"%[_fishing_reel_hint(),"對準魚影" if cast.has("band") else "收竿"],2)
			if cue=="fish_catch":_caption("釣到了！魚已收入背包。",2)
	if is_instance_valid(map_view):map_view.update_world(snapshot,id)
	if modal is ShippingPanel:modal.refresh(snapshot,id)
	MarketUI.refresh(self)
	HarvestUI.refresh(self)
	FishMeetUI.refresh(self)
	ShowcaseUI.refresh(self)
	SouvenirUI.refresh(self)
	MemoryExhibitUI.refresh(self)
	CommunityUI.refresh(self)
	undo_ui.observe(snapshot)
	undo_ui.refresh()
	ChapterUI.refresh(self)
	_add_tea_chapter_link()
	FlowerUI.chapter_link(self)
	SaltUI.chapter_link(self)
	_add_greenhouse_chapter_link()
	_add_hoist_chapter_link()
	_refresh_hoist_letter()
	TeaUI.refresh(self)
	FlowerUI.refresh(self)
	SaltUI.refresh(self)
	LanyangUI.refresh(self)
	HistoryUI.refresh(self)
	RevisitUI.refresh(self)
	JgRevisitUI.refresh(self)
	TeaRevisitUI.refresh(self)
	SaltRevisitUI.refresh(self)
	SaltBrineUI.refresh(self)
	GoldPanUI.refresh(self)
	OreRouteUI.refresh(self)
	GateUI.refresh(self)
	TowerUI.refresh(self)
	MineUI.refresh(self)
	MineSurveyUI.refresh(self)
	FreightUI.refresh(self)
	AutoFreightUI.refresh(self)
	BoboSortUI.refresh(self)
	TravelUI.refresh(self)
	StationLifeUI.refresh(self)
	WaterworksUI.refresh(self)
	MineDrillUI.refresh(self)
	CookingQueueUI.refresh(self)
	LifeShell.refresh_location(self,snapshot,snapshot.get("players",{}).get(id,{}))
	if not origin.is_empty() and origin!=destination:
		WanganUI.dismiss(self)
		TravelUI.arrived(self,origin,destination)
	if playing:_offer_return_news(snapshot)

func _action_completed(sequence:int,action:String,result:Dictionary) -> void:
	if action=="night_vote" and is_instance_valid(modal) and int(modal.get_meta("night_vote_pending",0))==sequence:
		modal.set_meta("night_vote_pending",0)
		_refresh_night_vote(session.snapshot)
		if modal.get_meta("night_vote_closing",false):
			if modal.get_meta("night_vote_cancelling",false) and session.snapshot.get("night_vote",{}).get("mine",false):
				modal.set_meta("night_vote_closing",false)
			else:_close_modal()
	if not gather_hold.is_empty() and sequence==gather_hold.pending and action==gather_hold.tool:
		if result.get("ok",false) and result.get("gather_continue",false):
			gather_hold.pending=0
		else:gather_hold.clear()
	if sound and playing and result.get("ok",false):
		var cue:=SoftAudio.action_cue(action,str(result.get("animal","")))
		if not cue.is_empty():sound.defer_action(cue)
	if action=="undo_build":undo_ui.complete(result)
	if action=="ship" and modal is ShippingPanel and modal.pending_sequence==sequence:
		modal.complete(result)

func _notice(message:String,success:bool) -> void:
	if not success and not playing and message==session.VERSION_MISMATCH_NOTICE:
		if not is_instance_valid(room_update_dialog):
			room_update_dialog=IdentityEntry.make_update_prompt(ui,self)
	message=_display_notice(message)
	print(("OK " if success else "NOTICE ")+message)
	if sound and playing:
		var kind:="notice" if not success else "action"
		if success and (message.contains("收成") or message.contains("完成") or message.contains("風鈴") or message.contains("獲得")):kind="reward"
		if success and (message.begins_with("叮——紀念鐘") or message.contains("完成了〈不用等風來〉")):kind="memorial_bell"
		if success and message.begins_with("叮——簷下陶風鈴"):kind="ceramic_chime"
		if success and message.begins_with("叮——潮紋貝殼"):kind="shell_chime"
		if success and message.begins_with("風鈴鹿垂下頭"):kind="shell_chime"
		if success:sound.defer_action(kind)
		else:sound.play_cue(kind)
	if toast:
		toast.text=message
		toast_time=6.0
		if village_art_preview:
			toast.visible=modal==null
			_layout_preview.call_deferred()
			if modal is InventoryPanel:modal.show_notice(message,success)
			if is_instance_valid(modal_feedback):
				modal_feedback.text=message
				modal_feedback.add_theme_color_override("font_color",Color("3e664b") if success else Color("9c4b32"))

func _caption(message:String,priority:int) -> void:
	if not is_instance_valid(activity_caption) or not sound.activity_captions:return
	if activity_caption_time>0.0 and priority<activity_caption_priority:return
	activity_caption.text=binding_text(message)
	activity_caption_priority=priority
	activity_caption_time=3.8
	_update_activity_caption(0.0)

func _update_activity_caption(dt:float) -> void:
	if not is_instance_valid(activity_caption):return
	activity_caption_time=maxf(0.0,activity_caption_time-dt)
	activity_caption.visible=playing and sound.activity_captions and activity_caption_time>0.0 and modal==null and not voyage_active
	if not activity_caption.visible:return
	var caption_width:=minf(toast.size.x,400.0)
	activity_caption.size.x=caption_width
	activity_caption.size.y=maxf(32,activity_caption.get_minimum_size().y)
	activity_caption.position=Vector2(toast.position.x+(toast.size.x-activity_caption.size.x)*0.5,toast.position.y-activity_caption.size.y-6.0)

func _process(dt:float) -> void:
	if test_seconds>0:
		test_seconds-=dt
		if test_seconds<=0:get_tree().quit(0 if session.shutdown() else 2)
	if not playing:return
	_update_activity_caption(dt)
	_update_world_label_obstacles()
	toast_time-=dt
	if toast_time<=0:
		toast.text=binding_text("{movement} 移動  ·  滑鼠指向地面使用工具  ·  靠近公告板或攤位按 {interact}")
		if village_art_preview:toast.hide()
	ui_clock+=dt
	if ui_clock>0.2:
		ui_clock=0
		_refresh_hud()
	var d:=movement_direction()
	input_clock+=dt
	if input_clock>=0.05:
		input_clock=0
		session.input_direction(d)
	var mouse:=get_viewport().get_mouse_position()
	target=_controller_target() if controller_aim else view.to_cell(mouse)
	if arg_value("capture-panel","") in ["tiller","seeder","harvester"]:target=World.cell(arg_value("capture-cell","42,36"))
	view.target=target
	view.show_target=_world_keyboard_allowed() if controller_aim else _world_pointer_allowed(mouse)
	if arg_value("capture-panel","") in ["tiller","seeder","harvester"] and modal==null:view.show_target=true
	view.selected=selected
	view.seed_kind=crop
	view.building=building
	view.placement_style=building_style
	view.area_drag=area_drag
	view.area_start=area_start
	_blueprint_process(mouse)
	action_clock=maxf(0,action_clock-dt)
	_update_gather_hold(dt,mouse)

func _update_world_label_obstacles() -> void:
	if not is_instance_valid(view):return
	var workshop_panel_open:bool=is_instance_valid(modal) and modal.is_visible_in_tree() and str(modal.get_meta("life_modal_layout","")) in ["forestry_device","automation_workbench","processing_queue","industry_device","automation_device","logistics_device","workshop_guide","livestock_card"]
	view.hide_interaction_prompt=workshop_panel_open or modal is InventoryPanel or SaltUI.suppress_world_prompts(self) or TowerUI.is_open(self) or GateUI.is_open(self)
	var regions:Array[Rect2]=[]
	if is_instance_valid(hud) and hud.is_visible_in_tree():
		for child in hud.get_children():
			if child is Control and child.is_visible_in_tree() and child.size.x>0 and child.size.y>0:
				regions.append(child.get_global_rect())
	view.label_avoid_rects=regions
	var hide:Array[Rect2]=[]
	var arrival:=WanganUI.card(self)
	if arrival!=null and arrival.is_visible_in_tree():hide.append(arrival.get_global_rect())
	view.label_hide_rects=hide

func _fishing_reel_hint() -> String:
	return "按手把 X " if controller_navigation else "點浮標或按 {fish_catch} "

func _refresh_fishing_hint(snapshot:Dictionary,angler:Dictionary) -> void:
	var cast:Dictionary=angler.get("fishing",{})
	var now:=float(snapshot.time)
	var hint:String
	if not cast.is_empty():
		if now<float(cast.ready):
			hint="魚竿已放好…稍等魚咬鉤。移動會收回魚竿。"
		elif cast.has("band") and World.FishingTracking.progress(cast,now)<World.FishingTracking.DURATION:
			hint=_fishing_reel_hint()+"對準魚影，讓魚影留在亮帶內。"
		else:
			hint="魚咬鉤了！"+_fishing_reel_hint()+"收竿。"
	else:
		var water_edge:="靠近河岸，點水面拋竿。"
		if snapshot.get("region_id","home")=="home":
			var position:=Vector2(angler.x,angler.y)
			if World.WANGAN_COAST.star_shore(Vector2i(position.floor())):
				water_edge="站在石圈外，點潮池水面釣金邊蝦。"
			elif World.WANGAN_COAST.VISITOR_AREA.has_point(position):
				water_edge="沿南岸棧道走到底，點外海水面拋竿。"
		if controller_navigation:water_edge="用十字鍵瞄準水面，按 X 拋竿。"
		hint="釣魚（%s） · %s"%["標準" if sound.standard_fishing else "輕鬆",water_edge]
	hint=binding_text(hint)
	if selected_label.text!=hint:selected_label.text=hint

func _refresh_hud() -> void:
	_update_world_label_obstacles.call_deferred()
	var s:Dictionary=session.snapshot
	if not s.has("players") or not s.players.has(session.own_id):return
	var p:Dictionary=s.players[session.own_id]
	var inv:Dictionary=p.inventory
	var highland_hint:=World.WARM_SPRINGS.highland_hint(s,p)
	if is_instance_valid(region_subtitle):
		region_subtitle.text=highland_hint if not highland_hint.is_empty() else "慢慢來，島上的日子還很長"
	WanganUI.refresh(self)
	automation_ui.refresh(self)
	industry_ui.refresh(self)
	forestry_ui.refresh(self)
	logistics_ui.refresh(self)
	undo_ui.refresh()
	if village_art_preview:
		coin_label.text="鈴幣 %d"%p.coins
		life_panels.refresh(self)
		ChapterUI.refresh(self)
		_add_tea_chapter_link()
		FlowerUI.chapter_link(self)
		SaltUI.chapter_link(self)
		_add_greenhouse_chapter_link()
		_add_hoist_chapter_link()
		TeaUI.refresh(self)
		FlowerUI.refresh(self)
		SaltUI.refresh(self)
		if modal is InventoryPanel:modal.refresh(s,session.own_id)
	var weather_text:String=WeatherArt.label(WeatherArt.current(s))
	status_label.text="%s · %s · 第 %d 日 · %d / %d 位島民"%[World.WEATHER.season_label(float(s.time)),weather_text,1+int(s.time)/1440,int(s.get("room_population",s.players.size())),int(s.get("room_capacity",4))]
	if not village_art_preview and not highland_hint.is_empty():status_label.text+="\n"+highland_hint
	if not village_art_preview:
		inventory_label.text="鈴幣  %d\n木材  %d     石材  %d\n纖維  %d\n種子  蘿蔔 %d / 萵苣 %d / 麥 %d"%[p.coins,inv.get("wood",0),inv.get("stone",0),inv.get("fiber",0),inv.get("radish_seed",0),inv.get("lettuce_seed",0),inv.get("wheat_seed",0)]
	objective.text="① 種下並收成第一株作物 %s\n② 放置一件自己的家具 %s\n③ 一起修好渡口公告板\n木材 %d / 30   石材 %d / 10"%["✓" if p.harvests>0 else "", "✓" if p.builds>0 else "",s.donations.wood,s.donations.stone]
	if s.board:objective.text="河灣橋已經開通！\n帶著朋友往東邊探索。\n\n把收成賣給小栗，\n再替家園添一盞燈吧。"
	if s.board and not s.get("picnic",false):objective.text="河灣橋已經開通！\n再為大家準備一場野餐：\n蘿蔔湯 %d / 2\n麵包 %d / 1\n蓋小石灶，完成後交給公告板。"%[s.picnic_materials.soup,s.picnic_materials.bread]
	if s.get("picnic",false):objective.text="渡口野餐準備好了！\n找阿榆與米露聊聊，\n解鎖長椅、花箱與沙發。\n\n{journal} 看故事，公告板交生活訂單。"
	if s.festival.active:objective.text="風鈴接力  %d / 12\n靠近金色風鈴按 {interact} 接住，\n跟朋友接力完成十二枚。\n\n沒有失敗倒數；{festival} 看活動。"%int(s.festival.collected)
	if selected=="fish":_refresh_fishing_hint(s,p)
	if selected=="build":selected_label.text=_build_tool_hint()
	if selected=="plant_tree":
		var problem:String=view.tree_planting_preview(target) if view.show_target else ""
		selected_label.text="樹苗 ×%d · %s"%[int(inv.get("sapling",0)),"點空地種植，不需澆水" if problem.is_empty() else problem]
	if selected=="till_area":
		if int(inv.get("tiller",0))<1:_select_tool("hoe")
		else:
			var available:int=view.tiller_preview(target).cells.size()
			selected_label.text="耕田機 · 可整地 %d／9 格 · 木炭 %d · 成功施工耗 1 木炭"%[available,int(inv.get("charcoal",0))]
			if int(inv.get("charcoal",0))<1:selected_label.text="耕田機缺少木炭 · 到炭窯製作燃料，或按 {hoe} 使用鋤頭"
	if selected=="seed_area":
		if int(inv.get("seeder",0))<1:_select_tool("hoe")
		else:
			var plan:Dictionary=view.seeder_preview(target)
			selected_label.text="播種機 · %s ×%d · 可播 %d 格 · 木炭 %d · {seeds} 換種子"%[World.CROPS[crop].name,int(inv.get(crop+"_seed",0)),plan.cells.size(),int(inv.get("charcoal",0))]
			if int(inv.get("charcoal",0))<1:selected_label.text="播種機缺少木炭 · 到炭窯製作燃料，或按 {seed} 手動播種"
			elif int(inv.get(crop+"_seed",0))<1:selected_label.text="這種種子用完了 · 按 {seeds} 換種子或到攤位購買"
	if selected=="harvest_area":
		if int(inv.get("harvester",0))<1:_select_tool("harvest")
		else:
			var plan:Dictionary=view.harvester_preview(target)
			var total:=0
			for amount in plan.yields.values():total+=int(amount)
			selected_label.text="收割機 · 成熟 %d／9 格 · 預計 %d 份 · 木炭 %d · 只收自己的作物"%[plan.cells.size(),total,int(inv.get("charcoal",0))]
			if int(inv.get("charcoal",0))<1:selected_label.text="收割機缺少木炭 · 到炭窯製作燃料，或按 {harvest} 手動採收"
	# Water hint follows the calendar day; tea-stop guidance below still overrides it.
	if selected=="water" and not selected_label.get_meta("regional_tool_hint",false):selected_label.text=WeatherForecast.water_hint(s)
	# T048: pointing the watering can or the harvest tool at a crop that is waiting
	# for its season says so (and that nothing is lost while it waits).
	var dormant_hint:=dormant_crop_hint(s,target) if selected in ["water","harvest"] and not selected_label.get_meta("regional_tool_hint",false) else ""
	if dormant_hint!="":
		selected_label.text=dormant_hint
		selected_label.set_meta("dormant_hint",true)
	elif selected_label.get_meta("dormant_hint",false):
		# The harvest text is only written on selection, so put it back once the
		# reticle leaves the dormant crop (the water hint is rewritten every refresh).
		selected_label.remove_meta("dormant_hint")
		if selected=="harvest":_select_tool(selected,true)
	objective.text=binding_text(objective.text)
	selected_label.text=binding_text(selected_label.text)
	if village_art_preview:LifeShell.refresh_hud(self,s,p)
	var current_region:=str(s.get("region_id","home"))
	if (selected!="fish" or current_region!=SaltUI.REGION) and _apply_regional_tool_hint(current_region):
		selected_label.set_meta("regional_tool_hint",true)
	elif selected_label.get_meta("regional_tool_hint",false):
		selected_label.remove_meta("regional_tool_hint")
		if selected!="fish":_select_tool(selected,true)
	if _tea_guidance_active():
		var heading:=hud.find_child("TrackerHeading",true,false) as Button
		if heading:heading.text="茶陶合作手帳  ▾"
		var next:=TeaGuidance.next_step(s,session.own_id)
		if current_region=="home" and not s.get("tea_ceramics",{}).get("own_record",{}).get("intro",false):
			next.text="靠近小栗按 %s，打開茶單收信。"%binding_label("interact")
		elif current_region in ["toucheng","ruifang"]:
			var route:=TravelUI.route_toward(s,session.own_id,str(next.region))
			if not route.is_empty():
				next.text="到%s轉乘\n下一站・%s"%[
					World.TRANSIT.points(current_region)[route.station].label,
					World.TRANSIT.STATIONS[route.selection].name]
		objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		objective.text=str(next.title)+"\n"+str(next.text)
		var button:=hud.find_child("TrackerNext",true,false) as Button
		if button:button.text="查看工作點  →" if str(next.region)==current_region else "查看轉乘  →"
		# 第 40 章：茶陶的下一步不在渡口時，先讓家園這裡還沒做的一次性提示（分流閘、地方記憶展）露出來。
		var memory_hint:=_home_memory_hint()
		if not memory_hint.is_empty():
			if heading:heading.text="渡口的新鮮事  ▾"
			objective.text=str(memory_hint.text)
			if button:button.text="打開地方記憶展  →" if str(memory_hint.kind)=="exhibit" else "茶陶手帳下一步  →"
		# 第 40 章貓空與鶯歌回訪：完成比較的島民在貓空／鶯歌，茶罐大單有「現在就能做」的一步時才
		# 改追蹤大單；否則保留茶陶手帳的下一步（做罐、採茶、烘焙），先備齊空罐與茶。
		var revisit_line:=TeaRevisitUI.tracker_text(s,str(session.own_id))
		if not revisit_line.is_empty():
			if heading:heading.text="貓空與鶯歌回訪  ▾"
			objective.text=revisit_line
			if button:button.text="打開茶罐大單  →"
	# T071 豐收接力：加入進行中的一輪時，任務卡改追蹤這一輪（優先於風鈴接力與茶陶手帳）。
	HarvestUI.refresh_hud(self,s)
	# T071 河岸釣魚會：已加入進行中的一輪時追蹤（豐收接力同時追蹤時以豐收接力為準）。
	FishMeetUI.refresh_hud(self,s)
	# T071 家園布置題：已加入進行中的一輪時追蹤（豐收接力、河岸釣魚會同時追蹤時以它們為準）。
	ShowcaseUI.refresh_hud(self,s)
	var survey_hint:=MineSurveyUI.guidance(s)
	if not survey_hint.is_empty():objective.text+="\n"+binding_text(survey_hint)
	var personal_step:=WanganUI.personal_step(self)
	if not personal_step.is_empty():
		objective.text=WanganUI.tracker_text(self,personal_step)
		var heading:=hud.find_child("TrackerHeading",true,false) as Button
		var button:=hud.find_child("TrackerNext",true,false) as Button
		if heading:heading.text="島民第一課  ▾"
		if button:button.text="查看種田指引  →"
	# The normal tool hint is irrelevant while both hands hold the hen. The
	# actor label explains release, and the existing hint returns unchanged.
	selected_label.visible=_tool_hint_visible()

func _harvest_menu()->void:
	HarvestUI.open(self)

func _harvest_tracking()->bool:
	return HarvestUI.tracking(session.snapshot)

func _harvest_pass()->void:
	HarvestUI.pass_now(self)

func _fishmeet_menu()->void:
	FishMeetUI.open(self)
	LifeTasks.add_achao_route_marker(self,"river")

func _fishmeet_tracking()->bool:
	return FishMeetUI.tracking(session.snapshot)

func _showcase_menu()->void:
	ShowcaseUI.open(self)

func _showcase_tracking()->bool:
	return ShowcaseUI.tracking(session.snapshot)

func _souvenir_menu()->void:
	SouvenirUI.open(self)

func _tea_guidance_active()->bool:
	var s:Dictionary=session.snapshot
	if not s.get("players",{}).has(session.own_id):return false
	if not TeaUI.unlocked(s):return false
	var region:=str(s.get("region_id","home"))
	if region in World.TRANSIT.TEA_STOPS:return true
	if region in ["toucheng","ruifang"]:
		var record:Dictionary=s.get("tea_ceramics",{}).get("own_record",{})
		return record.get("intro",false) and not record.get("comparison_complete",false)
	return region=="home" and not s.get("festival",{}).get("active",false)

## 第 40 章：家園追蹤卡上的一次性提示（kind: "gate"＝分流閘、"exhibit"＝地方記憶展）；沒有時回 {}。
## 茶陶手帳是可重複的循環、永遠有下一步，所以只有它的下一步就在渡口（收信、收款、寄回空罐）時才優先；
## 下一步在貓空或鶯歌時，這裡的提示先顯示，茶陶手帳仍可從追蹤卡按鈕或手帳打開。分流閘先於記憶展。
func _home_memory_hint()->Dictionary:
	if not _tea_guidance_active():return {}
	var s:Dictionary=session.snapshot
	if str(s.get("region_id","home"))!="home":return {}
	if str(TeaGuidance.next_step(s,session.own_id).get("region","home"))=="home":return {}
	var gate_hint:String=RevisitUI.home_hint(s,session.own_id)
	if not gate_hint.is_empty():return {"kind":"gate","text":gate_hint}
	var exhibit_hint:String=MemoryExhibitUI.tracker_text(s)
	if not exhibit_hint.is_empty():return {"kind":"exhibit","text":exhibit_hint}
	return {}

func _tea_next_step()->void:
	if not _tea_guidance_active():return
	var next:=TeaGuidance.next_step(session.snapshot,session.own_id)
	if str(next.region)!=str(session.snapshot.get("region_id","home")):
		TravelUI.open_toward(self,str(next.region))
	else:
		TeaUI.open(self,str(next.site),next.cell)

## 工具列提示：`cell` 上的作物正在等季節時的一行說明；不是休眠作物回 ""。只讀快照。
static func dormant_crop_hint(snapshot:Dictionary,cell:Vector2i) -> String:
	var k:=World.key(cell)
	var plot=snapshot.get("crops",{}).get(k,{})
	if not plot is Dictionary:return ""
	var roof=snapshot.get("roofs",{}).get(k,{})
	if not roof is Dictionary:roof={}
	var region:=str(snapshot.get("region_id",World.REGIONS.HOME))
	if not World.plot_dormant(plot,roof,region,cell,float(snapshot.get("time",0.0))):return ""
	var kind:=str(plot.kind)
	var text:="%s休眠中 · %s季會接著長（進度保留）"%[World.CROPS[kind].name,World.crop_season_text(kind)]
	if int(World.CROPS[kind].get("cycles",1))>1:text+=" · 還能收 %d 次"%int(plot.get("remaining",1))
	return text+" · 蓋溫室玻璃棚可不分季節"

## keep_blueprint: label/binding refreshes re-select the current tool and must not
## cancel a blueprint mode the player is still working in.
func _select_tool(action:String,keep_blueprint:=false) -> void:
	if action!=selected:gather_hold.clear()
	if not keep_blueprint and blueprints!=null:
		var blueprint_mode:=_blueprint_mode()
		if blueprint_mode in BLUEPRINT_SENT_MODES and action in ["build","remove","move_object"]:
			_notice("上一筆藍圖施工仍待確認，請先在藍圖側欄等待或重試確認；確認前不能開始新的施工。",false)
			return
		if blueprint_mode in BLUEPRINT_LOCAL_MODES:
			capture_drag=false
			blueprints.cancel()
	if action=="harvest_area":
		var bag:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{})
		if int(bag.get("harvester",0))<1:
			_notice("先到工作台製作手推收割機，再按 {harvest_area} 使用",false)
			return
	if action=="seed_area":
		var bag:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{})
		if int(bag.get("seeder",0))<1:
			_notice("先到工作台製作手推播種機，再按 {seed_area} 使用",false)
			return
	if action=="till_area":
		var bag:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{})
		if int(bag.get("tiller",0))<1:
			_notice("先到工作台製作手推耕田機，再按 {till_area} 使用",false)
			return
	area_drag=false
	moving_object=false
	selected=action
	var actions:=["hoe","seed","water","harvest","axe","pick","build","remove"]
	for i in range(tool_buttons.size()):tool_buttons[i].set_pressed_no_signal(actions[i]==action)
	var descriptions:={"hoe":"鋤頭：點空地開田", "seed":"播種："+World.CROPS[crop].name+"（按 {seeds} 換種子）", "water":WeatherForecast.water_hint(session.snapshot if session else {}) if action=="water" else "", "harvest":"採收：點成熟作物收入背包", "axe":"斧頭：點附近樹木或雜草", "pick":"十字鎬：點附近岩石", "build":"建造："+World.BUILD[building].name+"（按 {build_menu} 選物件）", "remove":"拆除：退回材料；也能移回自己的樹苗、恢復空農田", "plant_tree":"種樹：點空地種樹苗，約三分鐘長成（不需澆水）"}
	selected_label.text=descriptions.get(action,"釣魚：靠近河岸，點水面拋竿；咬鉤後點浮標或按 {fish_catch} 收竿。")
	if action=="build":selected_label.text=_build_tool_hint()
	if action in ["axe","pick"]:selected_label.text+=" · 可按住連續採集"
	if action=="move_object":selected_label.text="搬家具：先點自己的家具，再點新位置；箱內物品一起搬，Esc 取消。"
	if action=="till_area":selected_label.text="耕田機：點附近空地，一次最多 9 格 · 每次成功施工耗 1 木炭"
	if action=="seed_area":selected_label.text="播種機：點自己的空農田 · 每格 1 種子、每次 1 木炭 · {seeds} 換種子"
	if action=="harvest_area":selected_label.text="收割機：點有權採收的成熟作物 · 一次最多 9 格 · 成功耗 1 木炭"
	if action=="build" and building in ["floor","path","spring_pebble_path","roof"]:selected_label.text+=" · 按住 {area_modifier} 拖曳可成片施工"
	selected_label.text=binding_text(selected_label.text)
	if session:
		_apply_regional_tool_hint(str(session.snapshot.get("region_id","home")))
	get_viewport().gui_release_focus()

func _apply_regional_tool_hint(region:String) -> bool:
	var place:String
	if region==SaltUI.REGION:
		place="鹽田"
	elif region in World.TRANSIT.TEA_STOPS:
		place="公共工坊"
	else:
		return false
	selected_label.text="%s · 靠近工作點按 %s · %s 查看轉乘"%[place,binding_label("interact"),binding_label("map")]
	return true

func _input(event:InputEvent) -> void:
	if not gather_hold.is_empty():
		var device:int=gather_hold.device
		if event is InputEventMouseButton:
			var mouse_released:bool=device==GATHER_MOUSE and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed
			var cancelled:bool=event.button_index==MOUSE_BUTTON_RIGHT and event.pressed
			if mouse_released or cancelled:gather_hold.clear()
		elif event is InputEventJoypadButton and not event.pressed and event.button_index==JOY_BUTTON_X and event.device==device:
			gather_hold.clear()
	if controller_protected and not event.is_echo() and (event.is_pressed() or event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y] and absf(event.axis_value)>0.22):
		if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventMouseButton:
			controller_protected=false
			session.perform("controller_resume",Vector2i.ZERO)
	if event is InputEventKey:
		bindings.observe(event)
		if event.pressed and not event.echo:controller_navigation=false
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if controller_aim and area_drag:area_drag=false
		controller_aim=false
		controller_navigation=false
	elif event is InputEventJoypadButton and event.pressed:
		controller_device=event.device
		controller_navigation=true
		if not playing and is_instance_valid(menu) and menu.visible and get_viewport().gui_get_focus_owner()==null:
			_focus_controller_menu(menu)
			get_viewport().set_input_as_handled()
			if event.button_index==JOY_BUTTON_A:
				var solo:=get_viewport().gui_get_focus_owner() as Button
				if solo!=null and solo.name=="TitleSolo" and not solo.disabled:solo.pressed.emit()
			return
	if event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y]:
		var stick:Vector2=controller_sticks.get(event.device,Vector2.ZERO)
		stick[event.axis]=clampf(event.axis_value,-1.0,1.0)
		controller_sticks[event.device]=stick
		if stick.length()>0.22:
			controller_device=event.device
			controller_navigation=true
	if not playing:return
	if event is InputEventJoypadButton and event.pressed:
		if is_instance_valid(modal) and modal.has_meta("controller_shortcuts") and LifeShell.shortcut_direction(self,event.button_index):
			get_viewport().set_input_as_handled()
			return
		if preload("res://scripts/trade_ui.gd").navigate_editor(self,event.button_index):
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(modal) and modal.has_meta("trade_view") and event.button_index in [JOY_BUTTON_DPAD_LEFT,JOY_BUTTON_DPAD_RIGHT]:
			var field:=get_viewport().gui_get_focus_owner() as LineEdit
			if field!=null and modal.is_ancestor_of(field) and field.has_meta("trade_quantity") and field.get_parent() is SpinBox:
				var quantity:=field.get_parent() as SpinBox
				quantity.value+=quantity.step*(1 if event.button_index==JOY_BUTTON_DPAD_RIGHT else -1)
				get_viewport().set_input_as_handled()
				return
		var resident_controls:bool=is_instance_valid(modal) and (modal.get_meta("life_modal_layout","")=="resident_dialogue" or modal.has_meta("resident_gift_picker"))
		if is_instance_valid(modal) and (resident_controls or modal.has_meta("trade_view") or modal.has_meta("pocket_guide") or modal.get_meta("life_modal_layout","")=="workshop_guide" or modal.find_child("PauseTrade",true,false)!=null or modal.find_child("SaveComfort",true,false)!=null):
			if _controller_menu_direction(event.button_index):
				get_viewport().set_input_as_handled()
				return
		if event.button_index==JOY_BUTTON_A and is_instance_valid(modal):
			var focused:=get_viewport().gui_get_focus_owner() as BaseButton
			if focused!=null and modal.is_ancestor_of(focused) and not focused.disabled and (focused is CheckBox or focused is CheckButton or focused.name in ["BuildPlace","SaveComfort","PauseTrade","PauseComfort","PauseHelp"] or (resident_controls or modal.has_meta("trade_view")) and focused is Button):
				if focused.name=="BuildPlace":controller_aim=true
				if focused.toggle_mode:focused.button_pressed=not focused.button_pressed
				focused.pressed.emit()
				get_viewport().set_input_as_handled()
				return
		if event.button_index==JOY_BUTTON_Y and is_instance_valid(modal):
			var place:=modal.find_child("BuildPlace",true,false) as Button
			if is_instance_valid(place) and not place.disabled:
				place.grab_focus()
				var scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
				if scroll!=null:scroll.ensure_control_visible(place)
				get_viewport().set_input_as_handled()
				return
		if event.button_index==JOY_BUTTON_X and is_instance_valid(modal) and modal.get_meta("life_modal_layout","")=="automation_workbench":
			var craft:=modal.find_child("CraftRecipe",true,false) as Button
			if is_instance_valid(craft) and not craft.disabled:
				craft.grab_focus()
				var scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
				if scroll!=null:scroll.ensure_control_visible(craft)
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and preload("res://scripts/processing_queue_ui.gd").focus_primary(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and TravelUI.focus_departure(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and CommunityUI.focus_dish_action(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and preload("res://scripts/public_kitchen_ui.gd").focus_kitchen_action(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and CookingQueueUI.focus_primary(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and forestry_ui.focus_primary(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and TowerUI.focus_toggle(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and automation_ui.focus_sprinkler_action(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and WaterworksUI.focus_primary(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_X and logistics_ui.focus_primary(self):
			get_viewport().set_input_as_handled()
			return
		if event.button_index in [JOY_BUTTON_B,JOY_BUTTON_START]:
			_cancel_navigation()
			get_viewport().set_input_as_handled()
			return
		if event.button_index==JOY_BUTTON_A and _world_keyboard_allowed():
			if not WanganUI.dismiss(self):_interact()
			get_viewport().set_input_as_handled()
			return
		if _world_keyboard_allowed() and _controller_world_button(event.button_index,event.device):
			get_viewport().set_input_as_handled()
			return
	# The panel reads the binding identity itself (InputBindings.event_key); route the raw event.
	if is_instance_valid(bindings_panel) and bindings_panel.capture_event(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if InputBindings.event_key(event)==KEY_ESCAPE:
			# A focused forecast badge only drops focus; the next Esc opens the menu as before.
			if not (village_art_preview and modal==null and LifeShell.release_forecast_focus(self)):_cancel_navigation()
			get_viewport().set_input_as_handled()
			return
		# Shift+Tab (ui_focus_prev) opens/closes the read-only forecast badge before
		# the Tab-bound inventory sees it; plain Tab and other bindings are unchanged.
		if _forecast_focus_shortcut(event):
			get_viewport().set_input_as_handled()
			return
		# Inventory toggle precedes GUI Tab navigation, while other modal controls retain their keys.
		if bindings.matches("inventory",event):
			if modal is InventoryPanel or (modal and modal.get_meta("input_inventory",false)):_close_modal()
			elif _world_keyboard_allowed():_inventory()
			else:return
			get_viewport().set_input_as_handled()
			return
		if is_instance_valid(map_view) and bindings.matches("map",event):
			_close_modal()
			get_viewport().set_input_as_handled()
			return
	# Blueprint capture drag: same before-GUI release rule, but never build_area.
	if capture_drag and event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_finish_capture_drag(event.position)
		return
	# A drag can end over a UI control; capture its release before GUI consumption.
	if playing and area_drag and not controller_aim and event is InputEventMouseButton and not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		area_drag=false
		get_viewport().set_input_as_handled()
		if not _world_pointer_allowed(event.position):
			_notice("已取消這次成片施工，沒有扣除材料。",true)
			return
		var end:Vector2i=view.to_cell(event.position)
		_perform_build_action("build_area",area_start,"%s|%d|%d"%[building,end.x,end.y])

func _forecast_focus_shortcut(event:InputEventKey) -> bool:
	if not village_art_preview or not event.is_action_pressed("ui_focus_prev",false,true) or not _world_keyboard_allowed():return false
	# A player who rebinds a gameplay action (other than the default inventory) onto Tab keeps Shift+Tab for it.
	for action in bindings.keys:
		if action!="inventory" and bindings.matches(action,event):return false
	return LifeShell.toggle_forecast_focus(self)

func _unhandled_input(event:InputEvent) -> void:
	if not playing:return
	if event is InputEventKey and event.pressed and not event.echo:
		if InputBindings.event_key(event)==KEY_ESCAPE:
			_cancel_navigation()
			get_viewport().set_input_as_handled()
			return
		if voyage_active:
			if bindings.matches("interact",event):LifeTasks.achao_return_if_sailing(self)
			get_viewport().set_input_as_handled()
			return
		if bindings.matches("map",event):
			if is_instance_valid(map_view):_close_modal()
			elif _world_keyboard_allowed():_map_menu()
			return
		if not _world_keyboard_allowed():return
		# 望安下船卡：互動鍵或確認鍵（Enter／Space）收起卡片，這一下不做別的事。
		if WanganUI.card_open(self) and (bindings.matches("interact",event) or event.is_action_pressed("ui_accept")):
			WanganUI.dismiss(self)
			get_viewport().set_input_as_handled()
			return
		# R rotates only while placing with no modal (_world_keyboard_allowed). It
		# shadows a tool bound to R (default move_object) just in that mode, where
		# switching tools would otherwise cancel the placement anyway.
		if _blueprint_mode()=="placing" and _blueprint_rotate_key(event):
			blueprints.rotate()
			get_viewport().set_input_as_handled()
			return
		for action in TOOL_ACTIONS:
			if bindings.matches(action,event):
				_select_tool(action)
				get_viewport().set_input_as_handled()
				return
		if bindings.matches("build_menu",event):_build_menu()
		elif bindings.matches("inventory",event):_inventory()
		elif bindings.matches("interact",event):_interact()
		elif bindings.matches("seeds",event):_seed_menu()
		elif bindings.matches("journal",event):_journal()
		elif bindings.matches("festival",event):_festival_menu()
		elif bindings.matches("collection",event):_collection_menu()
		elif bindings.matches("social",event):_emote_menu()
		elif bindings.matches("zoom",event):
			view.zoom=1.0 if view.zoom==2.0 else 2.0
			_notice("已切換"+("近景，角色與像素更清楚。" if view.zoom==2.0 else "遠景，可以看見更多島嶼。"),true)
		elif bindings.matches("fish_catch",event) and selected=="fish":
			_reel_active_cast()
	if modal:return
	# Clicking the world closes the forecast focus tip; the click still acts normally.
	if village_art_preview and event is InputEventMouseButton and event.pressed:LifeShell.release_forecast_focus(self)
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and _blueprint_world_click(event.position):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if action_clock>0 or not (_world_pointer_allowed(event.position) if village_art_preview else view.show_target):return
		action_clock=0.16
		target=view.to_cell(event.position)
		if selected=="build" and building in ["floor","path","spring_pebble_path","roof"] and area_modifier_held(event):
			area_drag=true;area_start=target
			return
		_use_selected_at(target,GATHER_MOUSE)

func _controller_target() -> Vector2i:
	var person:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{})
	if person.is_empty():return target
	return Vector2i(floori(person.x),floori(person.y))+controller_offset

func _build_tool_hint() -> String:
	var name:String=World.BUILD[building].name
	if is_instance_valid(view) and view.show_target:
		var blocked:Dictionary=view.build_placement_blocks(view.target,building)
		if not blocked.is_empty():
			var reason:String=blocked.values()[0]
			return "%s · %s"%[name,reason] if blocked.size()==1 else "%s · 有 %d 格受阻 · %s"%[name,blocked.size(),reason]
	if controller_navigation:
		return "%s · 十字鍵瞄準 · X 施工 · Y 選物件"%name
	return "建造：%s（按 {build_menu} 選物件）"%name

func _reel_active_cast() -> bool:
	var cast:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{}).get("fishing",{})
	if cast.is_empty():return false
	session.perform("fish_catch",Vector2i(cast.x,cast.y))
	return true

func _controller_world_button(index:int,device:int=GATHER_NONE) -> bool:
	if CONTROLLER_AIM_DIRECTIONS.has(index):
		controller_aim=true
		controller_offset+=CONTROLLER_AIM_DIRECTIONS[index]
		controller_offset=controller_offset.clamp(Vector2i(-2,-2),Vector2i(2,2))
		return true
	match index:
		JOY_BUTTON_X:
			controller_aim=true
			if action_clock<=0.0:
				action_clock=0.16
				if selected=="fish" and _reel_active_cast():return true
				var cell:=_controller_target()
				if area_drag:
					area_drag=false
					_perform_build_action("build_area",area_start,"%s|%d|%d"%[building,cell.x,cell.y])
				else:_use_selected_at(cell,device)
		JOY_BUTTON_RIGHT_STICK:
			if selected!="build" or building not in ["floor","path","spring_pebble_path","roof"]:return false
			controller_aim=true
			area_start=_controller_target()
			area_drag=true
			_notice("十字鍵選擇範圍終點，X 施工，B 取消。",true)
		JOY_BUTTON_Y:_build_menu()
		JOY_BUTTON_LEFT_STICK:LifeShell.controller_shortcuts(self)
		JOY_BUTTON_BACK:
			if session.snapshot.get("own_trade",{}).is_empty():_inventory()
			else:_trade_menu()
		JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER:
			var step:=1 if index==JOY_BUTTON_RIGHT_SHOULDER else -1
			var cycle:=controller_tool_cycle()
			_select_tool(cycle[posmod(cycle.find(selected)+step,cycle.size())])
		_:return false
	return true

## T017：LB/RB 依工具列順序輪替；已擁有的手推農機（工具列顯示的欄位）排在釣竿之後，
## 未擁有的跳過，避免輪到被 _select_tool 拒絕的工具而卡住。只讀快照，不送伺服器。
func controller_tool_cycle() -> Array:
	var cycle:Array=CONTROLLER_TOOLS.duplicate()
	var bag:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{}) if session else {}
	var at:=cycle.find("fish")+1
	for machine in [["till_area","tiller"],["seed_area","seeder"],["harvest_area","harvester"]]:
		if int(bag.get(machine[1],0))>0:
			cycle.insert(at,machine[0])
			at+=1
	return cycle

func _use_selected_at(cell:Vector2i,gather_device:int=GATHER_NONE) -> void:
	if World.CHICKEN_CUDDLE.holder(session.snapshot)==session.own_id and not session.own_id.is_empty():
		_notice(binding_text("雙手正抱著糯米雞，按 {interact} 讓牠回雞圈後再使用工具。"),false)
		return
	target=cell
	# T071 家園布置題：已加入時點選（或手把 X）展示地塊格＝擺上／收起，不使用手上的工具。
	if str(session.snapshot.get("region_id","home"))=="home" and ShowcaseUI.click(self,cell):return
	if selected=="move_object":
		if moving_object:
			session.perform("move_object",move_from,World.key(target));moving_object=false
			_select_tool("move_object")
		else:
			var obj:Dictionary=session.snapshot.objects.get(World.key(target),{})
			if obj.is_empty() or obj.owner!=session.own_id:_notice("先選自己放置的家具。",false);return
			move_from=target;moving_object=true
			selected_label.text="已選取"+World.BUILD[obj.type].name+"；點身邊空地搬過去，Esc 取消。"
		return
	if selected=="fish":
		var person:Dictionary=session.snapshot.players.get(session.own_id,{})
		var cast:Dictionary=person.get("fishing",{})
		if cast.is_empty():session.perform("fish_start",target,"standard" if sound.standard_fishing else "")
		elif target==Vector2i(cast.x,cast.y):session.perform("fish_catch",target)
		return
	if gather_device!=GATHER_NONE and selected in ["axe","pick"] and _world_keyboard_allowed():
		gather_hold={"tool":selected,"cell":cell,"device":gather_device}
		_send_gather_hit()
		return
	_perform_build_action(selected,target,crop if selected in ["seed","seed_area"] else (building if selected=="build" else ""))

func _send_gather_hit() -> void:
	gather_hold.pending=session.counter+1
	gather_hold.timeout=3.0
	gather_hold.delay=GATHER_INTERVAL
	action_clock=0.16
	if session.perform(gather_hold.tool,gather_hold.cell)==0:gather_hold.clear()

func _update_gather_hold(dt:float,mouse:Vector2) -> void:
	if gather_hold.is_empty():return
	var by_mouse:bool=gather_hold.device==GATHER_MOUSE
	var aim:Vector2i=view.to_cell(mouse) if by_mouse else _controller_target()
	if not _world_keyboard_allowed() or controller_protected or aim!=gather_hold.cell or selected!=gather_hold.tool \
		or (by_mouse and (controller_aim or not _world_pointer_allowed(mouse))) or (not by_mouse and not controller_aim):
		gather_hold.clear()
		return
	gather_hold.delay=maxf(0.0,gather_hold.delay-dt)
	if gather_hold.pending!=0:
		gather_hold.timeout-=dt
		if gather_hold.timeout<=0.0:gather_hold.clear()
	elif gather_hold.delay==0.0 and action_clock==0.0:
		_send_gather_hit()

## Single entry for world-click and area-release actions. Build/remove/build_area are
## quoted once (never per frame); only when automatic roofs would be added or removed
## does a confirmation modal appear. Everything else is the original perform call.
func _perform_build_action(action:String,at:Vector2i,extra:String="") -> void:
	if action not in ROOF_QUOTE_ACTIONS:
		session.perform(action,at,extra)
		return
	var quote:=_roof_quote(action,at,extra)
	if action in ["build","build_area"] and not building_style.is_empty():
		extra+="@"+building_style
	if not _roof_quote_affected(quote):
		session.perform(action,at,extra)
		return
	_roof_confirm_menu({"action":action,"at":at,"extra":extra},quote,false)

func _roof_preview_source() -> Variant:
	if auto_roof_preview!=null:return auto_roof_preview
	if not ResourceLoader.exists(AUTO_ROOF_PREVIEW_PATH):return null
	var loaded=load(AUTO_ROOF_PREVIEW_PATH)
	return loaded if loaded is GDScript else null

## Normalized, display-safe view of a quote: counts only, refunds split into the
## local player and an anonymous aggregate of everyone else (no owner IDs kept).
## Returns {} when no preview is available.
func _roof_quote(action:String,at:Vector2i,extra:String) -> Dictionary:
	if action in ["build","build_area"]:extra=extra.get_slice("@",0)
	var source=_roof_preview_source()
	if source==null:return {}
	var raw=source.quote(session.snapshot,str(session.own_id),action,at,extra)
	var result:={"ok":false,"message":"","add":0,"remove":0,"cost":{},"mine":{},"others":{},"other_people":0}
	if typeof(raw)!=TYPE_DICTIONARY:return result
	result.ok=typeof(raw.get("ok"))==TYPE_BOOL and raw.ok
	result.message=str(raw.get("message","")) if typeof(raw.get("message"))==TYPE_STRING else ""
	var plan=raw.get("plan",{})
	if plan is Dictionary:
		for field in ["add","remove"]:
			var part=plan.get(field)
			if part is Dictionary or part is Array:result[field]=part.size()
	result.cost=_roof_counts(raw.get("total_cost",{}))
	var refunds=raw.get("refunds",{})
	if refunds is Dictionary:
		for payer in refunds:
			var back:=_roof_counts(refunds[payer])
			if back.is_empty():continue
			if str(payer)==str(session.own_id):result.mine=_roof_sum(result.mine,back)
			else:
				result.others=_roof_sum(result.others,back)
				result.other_people+=1
	return result

func _roof_quote_affected(quote:Dictionary) -> bool:
	return bool(quote.get("ok",false)) and (int(quote.get("add",0))>0 or int(quote.get("remove",0))>0)

func _roof_counts(source) -> Dictionary:
	var counts:={}
	if not (source is Dictionary):return counts
	for item in source:
		var value=source[item]
		if typeof(item) not in [TYPE_STRING,TYPE_STRING_NAME] or typeof(value) not in [TYPE_INT,TYPE_FLOAT]:continue
		if is_nan(float(value)) or is_inf(float(value)):continue
		var amount:=int(value)
		if amount>0:counts[String(item)]=amount
	return counts

func _roof_sum(a:Dictionary,b:Dictionary) -> Dictionary:
	var total:=a.duplicate()
	for item in b:total[item]=int(total.get(item,0))+int(b[item])
	return total

## Compact pixel confirmation. Confirm re-quotes; if anything visible changed it
## redraws and waits for another click instead of charging a different amount.
func _roof_confirm_menu(request:Dictionary,quote:Dictionary,changed:bool) -> void:
	var col:=_open_modal("自動屋頂確認")
	modal.set_meta("life_modal_layout","roof_confirm")
	modal.set_meta("roof_request",request.duplicate())
	modal.set_meta("roof_quote",quote.duplicate(true))
	var refund_rows:=int(not quote.get("mine",{}).is_empty() or int(quote.get("remove",0))>0)+int(int(quote.get("other_people",0))>0)
	modal.set_meta("roof_height",360+refund_rows*36+(40 if changed else 0))
	if village_art_preview:
		modal.theme=PixelTheme.make(modal.theme if modal.theme else theme())
		modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
		modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var body:=VBoxContainer.new()
	body.name="AutoRoofQuote"
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	col.add_child(body)
	var added:=int(quote.get("add",0))
	var removed:=int(quote.get("remove",0))
	if changed:
		var warn:=label("島上狀態剛變動，下面已更新；請再確認一次。",14)
		warn.name="AutoRoofChanged"
		warn.add_theme_color_override("font_color",Color("a4512f"))
		body.add_child(warn)
	var summary:=HBoxContainer.new()
	summary.name="AutoRoofSummary"
	summary.add_theme_constant_override("separation",10)
	body.add_child(summary)
	var frame:=Control.new()
	frame.name="RoofThumb"
	frame.custom_minimum_size=Vector2(32,48)
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	frame.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	summary.add_child(frame)
	var picture:=BuildThumbnail.new()
	picture.kind="roof"
	frame.add_child(picture)
	var heading:=VBoxContainer.new()
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.alignment=BoxContainer.ALIGNMENT_CENTER
	heading.add_theme_constant_override("separation",2)
	summary.add_child(heading)
	var headline:="這次施工會調整自動屋頂"
	if not bool(quote.get("ok",false)):headline=str(quote.get("message","")) if not str(quote.get("message","")).is_empty() else "暫時無法預估這次施工"
	elif added>0 and removed==0:headline="房間圍好了，會自動蓋上屋頂"
	elif removed>0 and added==0:headline="房間會被打開，自動屋頂將拆除"
	elif added==0 and removed==0:headline="這次不會調整屋頂"
	var title:=label(headline,18)
	title.name="AutoRoofHeadline"
	heading.add_child(title)
	var counts:=label("新增 %d 格  ·  拆除 %d 格"%[added,removed],15)
	counts.name="AutoRoofCounts"
	counts.autowrap_mode=TextServer.AUTOWRAP_OFF
	heading.add_child(counts)
	body.add_child(_roof_items_row("AutoRoofCost","你支付（含屋頂）",quote.get("cost",{})))
	if not quote.get("mine",{}).is_empty() or removed>0:
		body.add_child(_roof_items_row("AutoRoofMine","退回給你",quote.get("mine",{})))
	var others:=int(quote.get("other_people",0))
	if others>0:
		body.add_child(_roof_items_row("AutoRoofOthers","退回其他 %d 位"%others,quote.get("others",{})))
	var recipe:Dictionary=World.BUILD.roof
	var note:=label("新增的自動屋頂由你出資（每格木材 %d、纖維 %d）；拆除時材料退回當初出資的島民。送出後以島上實際狀態結算，材料不足就整筆不施工。"%[int(recipe.get("wood",0)),int(recipe.get("fiber",0))],13)
	note.name="AutoRoofNote"
	note.add_theme_color_override("font_color",Color("5d634a"))
	body.add_child(note)
	var footer:=HBoxContainer.new()
	footer.name="AutoRoofFooter"
	footer.add_theme_constant_override("separation",8)
	body.add_child(footer)
	var cancel:=button("取消",_close_modal)
	cancel.name="RoofCancel"
	cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(cancel)
	var confirm:=button("確認施工",_confirm_roof_quote)
	confirm.name="RoofConfirm"
	confirm.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(confirm)
	if is_instance_valid(modal_feedback):modal_feedback.text="Esc 取消，不會施工也不扣材料"
	cancel.call_deferred("grab_focus")
	_layout_preview.call_deferred()

func _roof_items_row(node_name:String,caption:String,counts) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.name=node_name
	row.add_theme_constant_override("separation",6)
	var title:=label(caption,15)
	title.autowrap_mode=TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal=Control.SIZE_FILL
	title.custom_minimum_size.x=150
	row.add_child(title)
	var items:Array=counts.keys() if counts is Dictionary else []
	items.sort()
	if items.is_empty():
		row.add_child(label("無",15))
		return row
	for item in items:
		var texture:=InventoryItemArt.icon(str(item))
		if texture:
			var icon:=TextureRect.new()
			icon.texture=texture
			icon.custom_minimum_size=Vector2(32,32)
			icon.stretch_mode=TextureRect.STRETCH_KEEP_CENTERED
			icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			icon.tooltip_text=str(World.NAMES.get(item,item))
			row.add_child(icon)
		var amount:=label(("×%d" if texture else str(World.NAMES.get(item,item))+" ×%d")%int(counts[item]),15)
		amount.autowrap_mode=TextServer.AUTOWRAP_OFF
		amount.size_flags_horizontal=Control.SIZE_FILL
		row.add_child(amount)
	return row

func _confirm_roof_quote() -> void:
	if not is_instance_valid(modal) or not modal.has_meta("roof_request"):return
	var request:Dictionary=modal.get_meta("roof_request")
	var shown:Dictionary=modal.get_meta("roof_quote",{})
	var fresh:=_roof_quote(str(request.action),request.at,str(request.extra))
	if fresh!=shown:
		_roof_confirm_menu(request,fresh,true)
		return
	_close_modal()
	session.perform(str(request.action),request.at,str(request.extra))

## --- Blueprint wiring ---------------------------------------------------------

func _make_blueprints() -> void:
	blueprints=BlueprintController.new()
	blueprints.name="Blueprints"
	add_child(blueprints)
	blueprints.changed.connect(_blueprint_changed)
	blueprints.feedback.connect(_notice)
	blueprints.applied.connect(_blueprint_applied)
	blueprint_overlay=BlueprintPreview.new()
	blueprint_overlay.name="BlueprintOverlay"
	blueprint_overlay.village_art_preview=view.village_art_preview
	blueprint_overlay.source_view=view
	blueprint_overlay.controller=blueprints
	add_child(blueprint_overlay)
	# Directly above the world view; the UI CanvasLayer stays on top of both.
	move_child(blueprint_overlay,view.get_index()+1)
	blueprint_strip=BlueprintUI.make_strip(self,blueprints)
	blueprint_strip.name="BlueprintStrip"
	if blueprint_strip.get_parent()==null:hud.add_child(blueprint_strip)
	blueprint_strip.hide()
	_layout_blueprint_strip()

func _blueprint_mode() -> String:
	return str(blueprints.mode) if blueprints!=null else "idle"

func _blueprint_library_path() -> String:
	var override:=arg_value("blueprint-library","")
	if not override.is_empty():return override
	# Per-profile file name from a hash of the token; the token itself never
	# appears in a path.
	return "user://blueprints-%s.json"%str(session.profile.get("token","")).sha256_text().left(16)

## Stable world scope: identity world ID, else the host's absolute save path,
## else the join address/port. Never includes room keys, tickets or invites.
func _blueprint_scope() -> String:
	var world_id:=str(session.identity_world)
	if world_id.is_empty() and is_instance_valid(identity_entry) and identity_entry.joining:
		world_id=str(identity_entry.pending_world_id)
		if not world_id.is_empty():blueprint_join_scope="identity:"+world_id
	if not world_id.is_empty():return "identity:"+world_id
	if session.world!=null and not str(session.world.save_path).is_empty():
		return "host:"+ProjectSettings.globalize_path(str(session.world.save_path)).simplify_path()
	return blueprint_join_scope

func _blueprint_address_scope(address:String,port:int) -> String:
	var text:=address.strip_edges().get_slice("#",0).get_slice("?",0)
	var scheme:=""
	if text.contains("://"):
		scheme=text.get_slice("://",0).to_lower()+"://"
		text=text.get_slice("://",1)
	var authority:=text.get_slice("/",0)
	var path:=text.substr(authority.length()).trim_suffix("/")
	if authority.contains("@"):authority=authority.get_slice("@",authority.count("@"))
	# Host names are case-insensitive; WebSocket route paths are not.
	authority=authority.to_lower()
	# WebSocket URLs carry their own port; the port field is ignored by Session.
	return "join:%s%s%s|%d"%[scheme,authority,path,0 if not scheme.is_empty() else port]

func _blueprint_setup() -> void:
	if blueprints==null:return
	var scope:=_blueprint_scope()
	if scope.is_empty():
		push_warning("Blueprint scope unavailable; blueprint construction disabled for this world.")
		return
	blueprints.setup(session,_blueprint_library_path(),scope)
	_blueprint_sync()

func _blueprint_menu() -> void:
	if blueprints==null or not playing:return
	BlueprintUI.open(self,blueprints)
	if is_instance_valid(modal) and not village_art_preview:
		_fit_blueprint_folio(get_viewport().get_visible_rect().size)
	_layout_preview.call_deferred()

func _fit_blueprint_folio(bounds:Vector2) -> void:
	if not is_instance_valid(modal):return
	modal.size=Vector2(minf(900,bounds.x-48),minf(560,bounds.y-64))
	modal.position=((bounds-modal.size)/2).floor()

func _layout_blueprint_strip() -> void:
	if is_instance_valid(blueprint_strip):
		BlueprintUI.layout_strip(blueprint_strip,get_viewport().get_visible_rect().size)

func _blueprint_changed() -> void:
	var mode:=_blueprint_mode()
	if mode!="capture":capture_drag=false
	if mode!="idle":
		# A blueprint mode replaces any half-finished ordinary drag or move.
		area_drag=false
		moving_object=false
	_blueprint_sync()

func _blueprint_applied(_result:Dictionary) -> void:
	_blueprint_sync()
	_refresh_hud()

## Strip visibility follows controller state; contents are owned by the strip.
func _tool_hint_visible()->bool:
	var holding:bool=not session.own_id.is_empty() and World.CHICKEN_CUDDLE.holder(session.snapshot)==session.own_id
	var blueprint_active:bool=blueprints!=null and playing and modal==null and (_blueprint_mode()!="idle" or blueprints.busy())
	return not holding and not blueprint_active

func _blueprint_sync() -> void:
	if blueprints==null:return
	var mode:=_blueprint_mode()
	var active:bool=playing and modal==null and (mode!="idle" or blueprints.busy())
	if playing and modal==null and is_instance_valid(selected_label):
		selected_label.visible=_tool_hint_visible()
	if is_instance_valid(blueprint_strip) and blueprint_strip.visible!=active:
		blueprint_strip.visible=active
		if active:_layout_blueprint_strip()
		if village_art_preview:_layout_preview.call_deferred()
	if is_instance_valid(blueprint_overlay):
		blueprint_overlay.visible=playing
		blueprint_overlay.queue_redraw()

func _blueprint_process(mouse:Vector2) -> void:
	if blueprints==null:return
	var mode:=_blueprint_mode()
	var over_world:=_world_pointer_allowed(mouse)
	var cell:Vector2i=view.to_cell(mouse)
	if mode=="placing" and not blueprints.locked and over_world and cell!=blueprints.origin:
		blueprints.move_origin(cell)
	if mode!="idle" and mode!="capture":view.show_target=false
	if mode=="capture" and capture_drag:
		blueprint_overlay.capture_rect=_capture_rect(capture_start,cell)
		blueprint_overlay.capture_visible=true
	elif mode=="capture" and over_world:
		blueprint_overlay.capture_rect=Rect2i(cell,Vector2i.ONE)
		blueprint_overlay.capture_visible=true
	else:
		blueprint_overlay.capture_visible=false
	_blueprint_sync()

func _capture_rect(a:Vector2i,b:Vector2i) -> Rect2i:
	var top_left:=Vector2i(mini(a.x,b.x),mini(a.y,b.y))
	return Rect2i(top_left,(a-b).abs()+Vector2i.ONE)

func _blueprint_rotate_key(event:InputEventKey) -> bool:
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:return false
	return event.keycode==KEY_R or (event.keycode==KEY_NONE and event.physical_keycode==KEY_R)

## World left-press while a blueprint mode is active. Returns true when the click
## belongs to the blueprint flow, so no ordinary tool action is submitted.
func _blueprint_world_click(point:Vector2) -> bool:
	var mode:=_blueprint_mode()
	if mode=="idle":return false
	if not _world_pointer_allowed(point):return true
	var cell:Vector2i=view.to_cell(point)
	match mode:
		"capture":
			capture_drag=true
			capture_start=cell
		"placing":
			# Clicking the ground again re-pins there and asks for a fresh quote.
			if blueprints.locked:blueprints.reposition()
			blueprints.pin_origin(cell)
		_:
			if action_clock<=0:
				action_clock=0.6
				_notice("藍圖施工%s，期間不能用工具改動地面；可以移動、開選單或關閉視窗。"%("送出中，等待島上回覆" if mode=="submitting" else "結果未確認，請在側欄重試確認"),false)
	return true

func _finish_capture_drag(point:Vector2) -> void:
	capture_drag=false
	if _blueprint_mode()!="capture":return
	if not _world_pointer_allowed(point):
		_notice("已取消這次框選（放開在介面上），沒有建立藍圖。",true)
		return
	var area:=_capture_rect(capture_start,view.to_cell(point))
	if area.size.x>BLUEPRINT_MAX_SPAN or area.size.y>BLUEPRINT_MAX_SPAN:
		_notice("框選範圍 %d×%d 太大，最多 %d×%d 格；請重新拖曳。"%[area.size.x,area.size.y,BLUEPRINT_MAX_SPAN,BLUEPRINT_MAX_SPAN],false)
		return
	var result:Dictionary=blueprints.capture_area(area,"新藍圖")
	if bool(result.get("ok",false)):
		# Captured but not yet saved: the book asks for a name and shows how many
		# automatic roofs were left out.
		_blueprint_menu()
	elif not str(result.get("reason","")).is_empty():
		_notice(str(result.reason),false)

func _interact() -> void:
	if World.CHICKEN_CUDDLE.holder(session.snapshot)==session.own_id and not session.own_id.is_empty():
		session.perform(World.CHICKEN_CUDDLE.RELEASE,World.CHICKEN_CELL)
		return
	if LifeTasks.achao_return_if_sailing(self):return
	var s:Dictionary=session.snapshot
	if not s.has("players") or not s.players.has(session.own_id):return
	var p:Dictionary=s.players[session.own_id]
	var pos:=Vector2(p.x,p.y)
	var region:=str(s.get("region_id","home"))
	if region==World.MINES.MUD_REGION and World.MINES.mud_engaged(p,float(s.time)):
		_mine_mud_menu(0)
		return
	if region=="home" and s.festival.active:
		var bell:=Festival.target(s.festival)
		if pos.distance_to(Vector2(bell)+Vector2(0.5,0.5))<=1.6:
			session.perform("festival_collect",bell,Festival.ticket(s.festival))
			return
	# T071 家園布置題：已加入進行中的一輪且地塊格在手邊時，互動鍵擺上／收起布置道具。
	if region=="home" and ShowcaseUI.interact(self):return
	if region==World.REGIONS.HOME and selected=="build" and view.show_target and pos.distance_to(Vector2(target)+Vector2(0.5,0.5))<=3.2:
		var floor_piece:Dictionary=s.ground.get(World.key(target),{})
		if floor_piece.get("type")=="floor" and floor_piece.get("owner")==session.own_id:
			_floor_placement_menu(target,floor_piece)
			return
	if region==World.REGIONS.HOME and selected=="remove" and view.show_target and pos.distance_to(Vector2(target)+Vector2(0.5,0.5))<=3.2:
		var furniture:Dictionary=s.objects.get(World.key(target),{})
		if furniture.get("owner")==session.own_id and furniture.get("type") in World.PLOT_PERMISSIONS.SHARED_REMOVAL_FURNITURE and not furniture.get("aru_public",false):
			_furniture_removal_menu(target,furniture)
			return
	var closest:=""
	var dist:=3.2
	var points:Dictionary={}
	if region==World.Fox.REGION:points.merge(World.Fox.points(p))
	points.merge(TeaUI.interaction_points(region,s))
	points.merge(FlowerUI.interaction_points(region))
	points.merge(SaltUI.interaction_points(region))
	# 第 40 章北門儲滷槽（工寮東側）：不在 SaltUI.interaction_points（那份與 salt_world_art.sites() 對應）。
	if region==SaltBrineUI.Brine.REGION:points[SaltBrineUI.POINT]=Vector2(SaltBrineUI.Brine.TANK)+Vector2(0.5,0.5)
	if region=="home":
		points={"board":Vector2(40.5,29.5),"shop":Vector2(43.5,29.5),"animal":Vector2(45.7,33.8),"quarry":Vector2(54.5,25.5),"copper":Vector2(World.COPPER_CELL)+Vector2(0.5,0.5)}
		if LifeTasks.bell_tree_available(s):points["lingpopo_tree"]=Vector2(World.Festival.TREE_CELL)+Vector2(0.5,0.5)
		var shipping_cell:Vector2i=World.SHIPPING.cell_for(s)
		if shipping_cell!=World.SHIPPING.NO_CELL:points["shipping"]=Vector2(shipping_cell)+Vector2(0.5,0.5)
		var table_cell:Vector2i=World.COMMUNITY.table_cell(s)
		if table_cell!=Vector2i(-1,-1):points["community"]=Vector2(table_cell)+Vector2(0.5,0.5)
		if s.get("picnic",false):
			points["companion_cat"]=Vector2(World.Cat.site(s))+Vector2(0.5,0.5)
			points["companion_dog"]=Vector2(World.Dog.SITE)+Vector2(0.5,0.5)
			for animal_id in World.LIVESTOCK.ANIMALS:
				points["livestock:"+animal_id]=Vector2(World.LIVESTOCK.ANIMALS[animal_id].cell)+Vector2(0.5,0.5)
		for resident in Village.ids_for_region(region):
			if resident!="xiaoli":points[resident]=Vector2(Village.resident_cell(s,resident))+Vector2(0.5,0.5)
	# T066：走近即可開好感頁的居民（棉棉、阿潮、暖暖），出現條件與站位由伺服器同一套規則判定。
	for walk_id:String in World.RESIDENT_BOND.WALK_UP:
		var walk_spot:Array=World.bond_place(s,walk_id)
		if str(walk_spot[0])==region and World.RESIDENT_BOND.present(s,walk_id):points[walk_id]=Vector2(walk_spot[1])+Vector2(0.5,0.5)
	if region==World.WARM_SPRINGS.REGION:
		points[World.WARM_SPRINGS.BATH_ACTION]=Vector2(World.WARM_SPRINGS.BATH_ENTRANCE)+Vector2(0.5,0.5)
		points[World.WARM_SPRINGS.INN_POINT]=Vector2(World.WARM_SPRINGS.INN_DOOR)+Vector2(0.5,0.5)
		if World.WARM_SPRINGS.in_inn(p):World.WARM_SPRINGS.room_interactions(points)
	if s.get("region_id","home")==World.REGIONS.HOME:points["aru_park"]=Vector2(World.RESIDENT_GOALS.ARU_PARK_VIEW)+Vector2(0.5,0.5)
	if region=="home":points[World.WANGAN_MEMORY.POINT]=Vector2(World.WANGAN_MEMORY.SITE)+Vector2(0.5,0.5)
	if region=="home" and World.WANGAN_MEMORY.courtyard_available(s):points[World.WANGAN_MEMORY.COURT_POINT]=Vector2(World.WANGAN_MEMORY.COURT_SIGN)+Vector2(0.5,0.5)
	if region=="home":points[World.Hedgehog.POINT]=Vector2(World.Hedgehog.site(s))+Vector2(0.5,0.5)
	if region=="home":points[World.Squirrel.POINT]=Vector2(World.Squirrel.SITE)+Vector2(0.5,0.5)
	if region=="home":points[World.Seal.POINT]=Vector2(World.Seal.SITE)+Vector2(0.5,0.5)
	if region=="home" and World.Deer.present(s):points[World.Deer.POINT]=Vector2(World.Deer.site(s))+Vector2(0.5,0.5)
	if region=="home":points[World.WANGAN_MEMORY.WEIR_POINT]=Vector2(World.WANGAN_MEMORY.WEIR_SITE)+Vector2(0.5,0.5)
	if region=="home":points[World.WANGAN_MEMORY.WEIR_LOOKOUT_POINT]=Vector2(World.WANGAN_MEMORY.WEIR_LOOKOUT)+Vector2(0.5,0.5)
	if region=="home":points[World.SEAWEED_POINT]=Vector2(World.SEAWEED_CELL)+Vector2(0.5,0.5)
	if region=="home":points[World.WANGAN_COAST.SHELL_POINT]=Vector2(World.WANGAN_COAST.SHELL_CELL)+Vector2(0.5,0.5)
	if region=="home" and s.get("wangan_star_walk",false):
		points[World.WANGAN_COAST.STAR_SAND_POINT]=Vector2(World.WANGAN_COAST.STAR_SAND)+Vector2(0.5,0.5)
		points[World.WANGAN_COAST.DOCK_ORDERS_POINT]=Vector2(World.WANGAN_COAST.DOCK_ORDERS)+Vector2(0.5,0.5)
	elif region=="home":points[World.WANGAN_COAST.STAR_REPAIR_POINT]=Vector2(World.WANGAN_COAST.STAR_REPAIR)+Vector2(0.5,0.5)
	# T071：市集攤位（渡口野餐後），排在走近型居民之後、物件之前，與 world_view 相同。
	var market_cell:Vector2i=MarketUI.Market.active_cell(s) if region=="home" else MarketUI.Market.NO_CELL
	if market_cell!=MarketUI.Market.NO_CELL:points["market"]=Vector2(market_cell)+Vector2(0.5,0.5)
	# T071 豐收接力：告示牌、菜箱、三個分類籃，緊接在市集攤位之後（與 world_view 相同）。
	if region=="home" and HarvestUI.on_field(s):
		for site:String in HarvestUI.SITES:points["harvest:"+site]=Vector2(HarvestUI.site_cell(site))+Vector2(0.5,0.5)
	# T071 河岸釣魚會告示牌，緊接在豐收接力之後（與 world_view 相同）。
	if region=="home" and FishMeetUI.on_field(s):points[FishMeetUI.POINT]=Vector2(World.FISH_MEET.SIGN)+Vector2(0.5,0.5)
	# T071 家園布置題告示牌，緊接在河岸釣魚會之後（與 world_view 相同）。
	if region=="home" and ShowcaseUI.sign_shown(s):points[ShowcaseUI.POINT]=Vector2(World.SHOWCASE.SIGN)+Vector2(0.5,0.5)
	# T071 紀念品交換攤，緊接在家園布置題告示牌之後（與 world_view 相同）。
	if region=="home" and SouvenirUI.booth_shown(s):points[SouvenirUI.POINT]=Vector2(SouvenirUI.booth_cell(s))+Vector2(0.5,0.5)
	# 第 40 章風鈴節廣場地方記憶展，緊接在紀念品交換攤之後（與 world_view 相同）。
	if region=="home" and MemoryExhibitUI.stand_shown(s):points[MemoryExhibitUI.POINT]=Vector2(MemoryExhibitUI.stand_cell(s))+Vector2(0.5,0.5)
	if region=="lanyang":points["travel"]=Vector2(World.REGIONS.exit_cell(region))+Vector2(0.5,0.5)
	if World.STATION_LIFE.RESIDENTS.has(region):points["station_resident:"+region]=Vector2(World.STATION_LIFE.RESIDENTS[region].cell)+Vector2(0.5,0.5)
	for station_id in World.TRANSIT.points(region):
		if region=="home" and not s.get("picnic",false):continue
		points["transit:"+station_id]=Vector2(World.TRANSIT.points(region)[station_id].cell)+Vector2(0.5,0.5)
	if region=="lanyang":
		points["gardener"]=Vector2(World.LANYANG_LIFE.SERVICE)+Vector2(0.5,0.5)
		for blockage in World.LANYANG_LIFE.BLOCKAGES:
			if not s.get("lanyang_life",{}).get("cleared",{}).has(World.key(blockage)):points["ditch:"+World.key(blockage)]=Vector2(blockage)+Vector2(0.5,0.5)
		if s.get("lanyang_life",{}).get("repaired",false):
			for site in World.HISTORY_MEMORY.OBSERVATIONS:points["memory:"+World.key(site)]=Vector2(site)+Vector2(0.5,0.5)
	elif region=="jinguashi":
		var workshop:Dictionary=World.BOBO_WORKSHOP.sites(s)
		points["bobo"]=Vector2(workshop.npc)+Vector2(0.5,0.5)
		points["bobo_sort"]=Vector2(workshop.table)+Vector2(0.5,0.5)
		points["mine_site:entry"]=Vector2(World.MINES.ENTRY)+Vector2(0.5,0.5)
		for site in World.JINGUASHI.NODES:points["mine:"+World.key(site)]=Vector2(site)+Vector2(0.5,0.5)
		points[GoldPanUI.POINT]=Vector2(World.GOLD_PANNING.SITE)+Vector2(0.5,0.5) # 第 40 章河邊淘砂金
		points[OreRouteUI.POINT]=Vector2(World.ORE_ROUTE.cart_cell(World.ORE_ROUTE.stage(s)))+Vector2(0.5,0.5) # 第 40 章運礦台車（位置隨階段移動）
	elif region.begins_with("mine_"):
		var survey_point:Vector2i=World.MINE_SURVEY.POINTS[int(region.trim_prefix("mine_"))]
		if not s.objects.has(World.key(survey_point)):points["mine_survey"]=Vector2(survey_point)+Vector2(0.5,0.5)
		for station in {"up":World.MINES.UP,"down":World.MINES.DOWN,"rest":World.MINES.REST,"service":World.MINES.SERVICE}:
			if station=="down" and World.MINES.depth_of(region)>=World.MINES.MAX_DEPTH:continue
			var stations:Dictionary={"up":World.MINES.UP,"down":World.MINES.DOWN,"rest":World.MINES.REST,"service":World.MINES.SERVICE}
			points["mine_site:"+station]=Vector2(stations[station])+Vector2(0.5,0.5)
		if World.MINES.depth_of(region)>World.MINES.SHALLOW_DEPTH:points["mine_site:lift"]=Vector2(World.MINES.LIFT)+Vector2(0.5,0.5)
		if region==World.MINES.MUD_REGION and int(p.get("mud_alcove",0))<2:
			var mud_site:=World.MINES.MUD_GATE if int(p.get("mud_alcove",0))==0 else World.MINES.MUD_REWARD
			points["mine_mud"]=Vector2(mud_site)+Vector2(0.5,0.5)
		for site in World.MINES.NODES:points["extract:"+World.key(site)]=Vector2(site)+Vector2(0.5,0.5)
	for k in s.objects:
		if s.objects[k].type in World.RESIDENT_GOALS.FESTIVAL_BELL_KINDS:points[k]=Vector2(World.cell(k))+Vector2(0.5,0.5)
		if s.objects[k].type==World.WELCOME_SIGN.KIND:points[k]=Vector2(World.cell(k))+Vector2(0.5,0.5)
		if s.objects[k].type==World.INN_TEA_TABLE:points[k]=Vector2(World.cell(k))+Vector2(0.5,0.5)
		if s.objects[k].type==World.INDUSTRY.LUGGAGE_RACK:points[k]=Vector2(World.cell(k))+Vector2(0.5,0.5)
		if s.objects[k].type in ["chest","private_chest","supply_box","bench","bed","inn_quilt_bed","inn_stone_footbath","door","stove","sprinkler","medium_sprinkler","large_sprinkler","water_tank","water_pump","sawmill","charcoal_kiln","forester","conveyor","waterworks","mine_drill","mill","seed_maker","loom","glass_furnace","small_smelter","clay_kiln","dye_table","assembly_table","animal_collector","sketch_easel","guest_wardrobe","inn_lattice_wardrobe","wood_mailbox","rope_rack","fish_display","author_sign","author_shelf","expedition_tent","diversion_gate","water_tower","water_share_plaque","mine_lantern","tea_ware","salt_basket","long_bench","master_bench","spring_stone_bench","sign"]:points[k]=Vector2(World.cell(k))+Vector2(0.5,0.5)
	if region!=World.FLOWER_NURSERY.REGION:
		var sketches:Dictionary=s.get("own_crop_sketches",{})
		var seek_sketches:bool=region==World.REGIONS.HOME and int(s.get("resident_bonds",{}).get("diandian",{}).get("stage",0))>=1 and sketches.size()<World.RESIDENT_GOALS.SKETCH_TARGET
		for plot_key in s.crops:
			var own_plot:bool=s.crops[plot_key].get("owner","")==session.own_id
			var kind:String=s.crops[plot_key].get("kind","")
			var can_sketch:bool=seek_sketches and World.CROPS.has(kind) and not sketches.has(kind)
			if own_plot or can_sketch:
				points["plot:"+plot_key]=Vector2(World.cell(plot_key))+Vector2(0.5,0.5)
	for key in points:
		var distance:=pos.distance_to(points[key])
		if distance<dist:closest=key;dist=distance
	if region==World.ORE_ROUTE.REGION:closest=World.ORE_ROUTE.preferred_interaction(s,pos,closest,points)
	if not closest.is_empty():
		if closest.begins_with("plot:"):
			var plot_key:=closest.trim_prefix("plot:")
			var tile:=World.cell(plot_key)
			var crop:Dictionary=s.crops[plot_key]
			var own_plot:bool=crop.get("owner","")==session.own_id
			var body:=_open_modal("農田")
			if own_plot:
				var last_kind:=str(crop.get("last_harvest_kind",""))
				var fertility:=int(crop.get("fertility",0))
				body.add_child(label("土壤肥力 %d／2 · 上次收成 %s"%[fertility,World.CROPS.get(last_kind,{}).get("name","尚未收成")],16))
				var planted_kind:=str(crop.get("kind",""))
				if not planted_kind.is_empty() and World.harvest_fertility(crop)>=2:
					var ripe:=float(crop.growth)>=float(World.CROPS[planted_kind].time)
					body.add_child(label("這批作物可多收一件優良品。" if ripe else "這批作物成熟後可多收一件優良品。",15))
			if region==World.REGIONS.HOME and int(s.get("resident_bonds",{}).get("diandian",{}).get("stage",0))>=1 and World.CROPS.has(crop.kind):
				var sketches:Dictionary=s.get("own_crop_sketches",{})
				var observed:=sketches.has(crop.kind)
				var done:=sketches.size()>=World.RESIDENT_GOALS.SKETCH_TARGET
				var sketch:=button("已記錄這種作物" if observed else ("三種已畫好，回去找點點" if done else "記下%s的色彩"%World.CROPS[crop.kind].name),func():
					session.perform(World.RESIDENT_GOALS.SKETCH_ACTION,tile)
					_close_modal())
				sketch.name="CropSketch"
				sketch.disabled=observed or done
				body.add_child(sketch)
				body.add_child(label("點點的速寫  %d／%d"%[sketches.size(),World.RESIDENT_GOALS.SKETCH_TARGET],15))
			if not own_plot:return
			LifeTasks.add_growth_observation(self,body,tile,crop)
			if region==World.REGIONS.HOME:
				for setting in [["播種","owner_sow","plot_sow_access","PlotSowAccess"],["澆水","owner_water","plot_water_access","PlotWaterAccess"]]:
					var title:String=setting[0]
					var owner_only:bool=crop.get(setting[1],false)
					var request:String=setting[2]
					var access_row:=HBoxContainer.new()
					body.add_child(access_row)
					var status:=label("手動%s · %s"%[title,"只限田主" if owner_only else "開放同島玩家"],16)
					status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
					access_row.add_child(status)
					var access_button:=button(("開放同島玩家" if owner_only else "只限田主")+title,func():
						session.perform(request,tile,"island" if owner_only else "owner")
						_close_modal())
					access_button.name=setting[3]
					access_row.add_child(access_button)
			body.add_child(label("採收權限",18))
			var access:String=s.crops[plot_key].get("harvest_access","island")
			var selected_friend:String=s.crops[plot_key].get("harvest_friend","")
			var status_text:String={"owner":"只限田主","island":"同島玩家皆可手動採收","friend":"田主與指定玩家"}.get(access,"")
			if access=="friend" and s.players.has(selected_friend):
				status_text+=" · "+str(s.players[selected_friend].name)
			body.add_child(label("目前："+status_text,16))
			if not s.crops[plot_key].has("harvest_access"):
				body.add_child(label("選擇開放同島玩家後，可一併開放收割機。",15))
			var choices:=[["owner","只限田主"],["island","開放同島玩家（含收割機）"]]
			for player_id in s.players:
				if player_id!=session.own_id:
					choices.append(["friend:"+player_id,"開放給 "+str(s.players[player_id].name)])
			for choice in choices:
				var mode:String=choice[0]
				var control:=button(choice[1],func():
					session.perform("plot_harvest_access",tile,mode)
					_close_modal())
				control.disabled=(mode==access and s.crops[plot_key].has("harvest_access")) or (access=="friend" and mode=="friend:"+selected_friend)
				body.add_child(control)
			return
		if closest.begins_with("flower:"):
			FlowerUI.open(self,closest.trim_prefix("flower:"))
			return
		if closest.begins_with("salt:"):
			SaltUI.open(self,closest.trim_prefix("salt:"))
			return
		if closest==SaltBrineUI.POINT:SaltBrineUI.open(self);return
		if closest==GoldPanUI.POINT:GoldPanUI.open(self);return
		if closest==OreRouteUI.POINT:OreRouteUI.interact(self);return
		if closest.begins_with("tea:"):
			var site:=closest.trim_prefix("tea:")
			if site.begins_with("pick:"):TeaUI.open(self,"pick",World.cell(site.trim_prefix("pick:")))
			else:TeaUI.open(self,site)
			return
		if closest.begins_with("station_resident:"):_station_resident_menu(closest.trim_prefix("station_resident:"));return
		if closest=="bobo_sort":_bobo_sort_menu();return
		if closest=="travel":_travel_menu();return
		if closest.begins_with("transit:"):_travel_menu(closest.trim_prefix("transit:"));return
		if closest=="mine_mud":_mine_mud_menu(int(p.get("mud_alcove",0)));return
		if closest.begins_with("mine_site:"):_mine_site_menu(closest.trim_prefix("mine_site:"));return
		if closest=="mine_survey":MineSurveyUI.open(self,int(region.trim_prefix("mine_")),true);return
		if closest.begins_with("extract:"):session.perform("mine_extract",World.cell(closest.trim_prefix("extract:")));return
		if closest.begins_with("mine:"):session.perform("mine_copper",World.cell(closest.trim_prefix("mine:")));return
		# 第 40 章：準備好的島民在星禾（中段的田）與三處水口開「回訪・旱日分流」頁。
		if closest=="gardener":
			if RevisitUI.gardener_opens(s):RevisitUI.open(self,World.LANYANG_REVISIT.SERVICE)
			else:_gardener_menu()
			return
		if closest.begins_with("memory:"):
			var memory_cell:=World.cell(closest.trim_prefix("memory:"))
			if RevisitUI.available(s):RevisitUI.open(self,memory_cell)
			else:HistoryUI.open(self,"observe",memory_cell)
			return
		if closest.begins_with("ditch:"):LanyangUI.open(self,"clear",World.cell(closest.trim_prefix("ditch:")));_layout_preview.call_deferred();return
		if Village.NPCS.has(closest):_resident_menu(closest);return
		if closest=="quarry":_quarry_menu();return
		if closest=="copper":automation_ui.copper(self);return
		if closest=="lingpopo_tree":LifeTasks.bell_inspection(self,"tree");return
		if closest=="board":_board();return
		if closest=="shop":_shop();return
		if closest=="shipping":_shipping_menu();return
		if closest=="community":_community_menu();return
		if closest=="animal":_animal_menu();return
		if closest=="companion_cat":_cat_menu();return
		if closest=="companion_dog":_dog_menu();return
		if closest=="companion_fox":_fox_menu();return
		if closest.begins_with("fox_track:"):
			session.perform("fox_track",World.cell(closest.trim_prefix("fox_track:")))
			return
		if closest.begins_with("livestock:"):LifeAlmanac.livestock_menu(self,closest.get_slice(":",1));return
		if closest in World.RESIDENT_BOND.WALK_UP:_resident_bond_menu(closest);return
		if closest==World.WARM_SPRINGS.BATH_ACTION:
			session.perform(closest,World.WARM_SPRINGS.BATH_ENTRANCE)
			return
		if closest==World.WARM_SPRINGS.INN_POINT:LifeTasks.warm_springs_inn(self);return
		if closest==World.WARM_SPRINGS.INN_PORTAL:
			session.perform(closest,World.WARM_SPRINGS.INN_EXIT)
			return
		if closest.begins_with(World.WARM_SPRINGS.INN_USE+":"):
			session.perform(World.WARM_SPRINGS.INN_USE,World.cell(closest.get_slice(":",1)))
			return
		if closest=="market":MarketUI.open(self);return
		if closest.begins_with("harvest:"):HarvestUI.interact(self,closest.trim_prefix("harvest:"));return
		if closest==FishMeetUI.POINT:_fishmeet_menu();return
		if closest==ShowcaseUI.POINT:ShowcaseUI.open(self);return
		if closest==SouvenirUI.POINT:SouvenirUI.open(self);return
		if closest=="aru_park":LifeTasks.aru_park(self);return
		if closest in [World.WANGAN_MEMORY.POINT,World.WANGAN_MEMORY.COURT_POINT]:HistoryUI.open(self,"wangan");return
		if closest==World.Hedgehog.POINT:LifeAlmanac.hedgehog_menu(self);return
		if closest==World.Squirrel.POINT:LifeAlmanac.squirrel_menu(self);return
		if closest==World.Seal.POINT:LifeAlmanac.seal_menu(self);return
		if closest==World.Deer.POINT:LifeAlmanac.deer_menu(self);return
		if closest in [World.WANGAN_MEMORY.WEIR_POINT,World.WANGAN_MEMORY.WEIR_LOOKOUT_POINT]:
			HistoryUI.open(self,"wangan_weir")
			return
		if closest==World.SEAWEED_POINT:session.perform(World.SEAWEED_POINT,World.SEAWEED_CELL);return
		if closest==World.WANGAN_COAST.SHELL_POINT:
			session.perform(World.WANGAN_COAST.SHELL_POINT,World.WANGAN_COAST.SHELL_CELL)
			return
		if closest==World.WANGAN_COAST.STAR_SAND_POINT:
			session.perform(World.WANGAN_COAST.STAR_SAND_POINT,World.WANGAN_COAST.STAR_SAND)
			return
		if closest==World.WANGAN_COAST.STAR_REPAIR_POINT:
			_star_walk_project()
			return
		if closest==World.WANGAN_COAST.DOCK_ORDERS_POINT:
			LifeAlmanac.orders_menu(self,true)
			return
		if closest==MemoryExhibitUI.POINT:MemoryExhibitUI.open(self);return
		var obj:Dictionary=s.objects[closest]
		if obj.type in ["chest","private_chest","supply_box"]:
			if obj.get("locked",false) and not (obj.get("guest_deposit",false) or obj.get("guest_withdraw",false)):_notice("這個私人箱尚未向你開放。",false)
			else:_chest(World.cell(closest))
		elif obj.type=="bench":automation_ui.workbench(self,World.cell(closest))
		elif obj.type=="expedition_tent":
			var content:=_open_modal(World.BUILD[obj.type].name)
			content.add_child(label(str(obj.author)+" 的探險紀念",21))
			content.add_child(label("從渡口的第一班船，到礦坑深處與北門海岸。這頂帳篷紀念搭建者走過的 14 個地區。",16))
		elif obj.type in World.RESIDENT_GOALS.FESTIVAL_BELL_KINDS:session.perform(World.RESIDENT_GOALS.FESTIVAL_BELL_RING,World.cell(closest))
		elif obj.type==World.WELCOME_SIGN.KIND:LifeTasks.welcome_sign(self,World.cell(closest),obj)
		elif obj.type==World.INN_TEA_TABLE:LifeTasks.inn_tea_table(self,World.cell(closest),obj)
		elif obj.type==World.INDUSTRY.LUGGAGE_RACK:
			var anchor:=World.station_anchor(s.objects,World.cell(closest))
			LifeTasks.luggage_rack(self,World.cell(closest),s.objects[World.key(anchor)])
		elif obj.type in World.RESIDENT_GOALS.INSCRIPTION_KINDS or obj.type==World.RESIDENT_GOALS.STONE_BENCH:
			var anchor:=World.master_bench_anchor(s.objects,World.cell(closest))
			LifeTasks.aru_inscription(self,anchor,s.objects[World.key(anchor)])
		elif obj.type in ["author_sign","author_shelf"]:
			var content:=_open_modal(World.BUILD[obj.type].name)
			content.add_child(label("建造者 · "+str(obj.get("author","")),21))
		elif obj.type==World.RESIDENT_GOALS.MAILBOX_KIND:LifeTasks.address_letter(self)
		elif obj.type in World.RESIDENT_GOALS.WARDROBES:LifeTasks.guest_wardrobe(self,World.cell(closest),obj.type)
		elif obj.type=="sketch_easel":LifeAlmanac.collection_menu(self,1)
		elif obj.type=="rope_rack":LifeTasks.bond_events(self,"achao")
		elif obj.type=="fish_display":LifeAlmanac.collection_menu(self,2)
		elif obj.type==World.INDUSTRY.GATE_KIND:GateUI.open(self,World.cell(closest))
		elif obj.type==World.INDUSTRY.TOWER_KIND:TowerUI.open(self,World.cell(closest))
		elif obj.type==World.LANYANG_REVISIT.PLAQUE_KIND:GateUI.plaque(self,World.cell(closest))
		elif obj.type==World.JINGUASHI_REVISIT.LANTERN_KIND:JgRevisitUI.lantern_card(self,World.cell(closest))
		elif obj.type==World.TEA_REVISIT.TEAWARE_KIND:TeaRevisitUI.teaware_card(self,World.cell(closest))
		elif obj.type==World.SALT_REVISIT.BASKET_KIND:SaltRevisitUI.basket_card(self,World.cell(closest))
		elif World.INDUSTRY.SPRINKLER_CAPACITIES.has(obj.type):automation_ui.sprinkler(self,World.cell(closest))
		elif obj.type=="forester":forestry_ui.device(self,World.cell(closest))
		elif obj.type=="conveyor":logistics_ui.device(self,World.cell(closest))
		elif obj.type=="waterworks":WaterworksUI.open(self,World.cell(closest))
		elif obj.type=="mine_drill":MineDrillUI.open(self,World.cell(closest))
		elif obj.type==World.INDUSTRY.ANIMAL_COLLECTOR:automation_ui.animal_collector(self,World.cell(closest))
		elif obj.type==World.INDUSTRY.ASSEMBLY_TABLE:automation_ui.assembly(self,World.station_anchor(s.objects,World.cell(closest)))
		elif obj.type in ["water_tank","water_pump","sawmill","charcoal_kiln","mill","seed_maker","loom","glass_furnace","small_smelter","jam_pot","clay_kiln","dye_table"]:industry_ui.device(self,World.station_anchor(s.objects,World.cell(closest)))
		elif obj.type=="door":session.perform("door",World.cell(closest))
		elif obj.type=="stove":_cook_menu(World.cell(closest))
		elif obj.type=="bed" and session.solo_rest_enabled:_night_rest_menu()
		elif obj.type==World.INDUSTRY.INN_BED:session.perform("inn_bed_rest",World.cell(closest))
		elif obj.type==World.INDUSTRY.FOOT_BATH:LifeTasks.foot_bath(self,World.cell(closest),World.station_anchor(s.objects,World.cell(closest)))
		else:_notice("這是你的落腳處。晚上可以繼續在島上活動。",true)
	else:_notice("靠近箱子、工作台、公告板或種子攤，再按 {interact}。",false)

func _open_modal(title:String,epilogue_music:=false) -> VBoxContainer:
	if playing:session.input_direction(Vector2.ZERO)
	area_drag=false
	capture_drag=false
	moving_object=false
	_close_modal(epilogue_music)
	if epilogue_music and sound:sound.music.set_epilogue(true)
	if village_art_preview:
		_hide_world_hud()
		modal_shade=ColorRect.new()
		modal_shade.color=Color(0.12,0.19,0.14,0.42)
		modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.add_child(modal_shade)
		modal=panel(hud,Rect2(210,90,860,620))
		# Wrapped labels briefly report tall minimums before their parent receives
		# its width. Refit when that minimum settles, keeping the body scrollable.
		modal.minimum_size_changed.connect(_layout_preview.call_deferred)
		var shell:=VBoxContainer.new()
		shell.add_theme_constant_override("separation",12)
		modal.add_child(shell)
		var heading:=HBoxContainer.new()
		shell.add_child(heading)
		var title_label:=label(title,26)
		title_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		heading.add_child(title_label)
		heading.add_child(button("關閉  Esc",_close_modal))
		shell.add_child(HSeparator.new())
		var scroll:=ScrollContainer.new()
		scroll.name="ModalScroll"
		scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		shell.add_child(scroll)
		var content:=VBoxContainer.new()
		content.name="ModalContent"
		content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation",12)
		scroll.add_child(content)
		var footer_divider:=HSeparator.new()
		footer_divider.name="ModalFooterDivider"
		shell.add_child(footer_divider)
		modal_feedback=label("Esc 回到島上",14)
		modal_feedback.custom_minimum_size.y=24
		shell.add_child(modal_feedback)
		toast.hide()
		_layout_preview()
		_layout_preview.call_deferred()
		LifeShell.reveal(self,modal)
		if controller_navigation:_focus_controller_menu.call_deferred(content)
		return content
	modal=panel(hud,Rect2(365,95,640,570))
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",10)
	modal.add_child(col)
	var row:=HBoxContainer.new()
	col.add_child(row)
	var h:=label(title,25)
	h.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(h)
	row.add_child(button("關閉  Esc",_close_modal))
	if controller_navigation:_focus_controller_menu.call_deferred(col)
	return col

func _focus_controller_menu(scope:Control) -> void:
	if not controller_navigation or not is_instance_valid(scope) or not scope.is_visible_in_tree():return
	var current:=get_viewport().gui_get_focus_owner()
	if is_instance_valid(current) and scope.is_ancestor_of(current):return
	var solo:=scope.find_child("TitleSolo",true,false) as Button
	if solo!=null and solo.is_visible_in_tree() and not solo.disabled:
		solo.grab_focus()
		return
	var first_card:=scope.find_child("GuideCard0",true,false) as Control
	if first_card!=null:
		first_card.grab_focus()
		var guide_scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
		guide_scroll.set_deferred("scroll_vertical",0)
		return
	var controls:=scope.find_children("*","Control",true,false)
	for control:Control in controls:
		if control is BaseButton and control.is_visible_in_tree() and not control.disabled and control.focus_mode==Control.FOCUS_ALL:
			control.grab_focus()
			return

func _controller_menu_direction(index:int) -> bool:
	const SIDES:={JOY_BUTTON_DPAD_LEFT:SIDE_LEFT,JOY_BUTTON_DPAD_RIGHT:SIDE_RIGHT,
		JOY_BUTTON_DPAD_UP:SIDE_TOP,JOY_BUTTON_DPAD_DOWN:SIDE_BOTTOM}
	if not SIDES.has(index):return false
	var focus:=get_viewport().gui_get_focus_owner()
	if focus==null or not modal.is_ancestor_of(focus):
		_focus_controller_menu(modal)
		return true
	var next:=focus.find_valid_focus_neighbor(SIDES[index])
	if next!=null and modal.is_ancestor_of(next):
		next.grab_focus()
		var scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
		if scroll!=null and not modal.has_meta("pocket_guide") and scroll.is_ancestor_of(next):scroll.ensure_control_visible(next)
	return true

func _close_modal(keep_epilogue_music:=false) -> void:
	if playing and is_instance_valid(modal) and modal.has_meta("night_vote_panel"):
		if int(modal.get_meta("night_vote_pending",0))!=0:
			modal.set_meta("night_vote_closing",true)
			return
		var ballot:Dictionary=session.snapshot.get("night_vote",{})
		if ballot.get("mine",false):
			modal.set_meta("night_vote_closing",true)
			modal.set_meta("night_vote_cancelling",true)
			_submit_night_vote("no:%d"%ballot.id)
			return
	gather_hold.clear()
	if not keep_epilogue_music and sound and not sound.music.story_return_track.is_empty():
		sound.music.set_epilogue(false)
		if playing:sound.set_world(session.snapshot,session.own_id)
	bindings_panel=null
	if modal:modal.hide();modal.queue_free();modal=null
	if is_instance_valid(modal_shade):modal_shade.hide();modal_shade.queue_free()
	modal_shade=null
	modal_feedback=null
	for control in inventory_hidden_controls:
		if is_instance_valid(control):control.show()
	inventory_hidden_controls.clear()
	if village_art_preview and toast:toast.visible=toast_time>0
	map_view=null
	get_viewport().gui_release_focus()
	if village_art_preview:_layout_preview.call_deferred()
	if session.local_paused:_resume_island_when_ready.call_deferred()

func _resume_island_when_ready() -> void:
	if modal==null:session.local_paused=false

func _hide_world_hud() -> void:
	for child in hud.get_children():
		if child is Control and child.visible:
			inventory_hidden_controls.append(child)
			child.hide()

func _chapter_menu() -> void:
	ChapterUI.open(self)
	_add_tea_chapter_link()
	FlowerUI.chapter_link(self)
	SaltUI.chapter_link(self)
	_add_greenhouse_chapter_link()
	_add_hoist_chapter_link()
	_layout_preview.call_deferred()

## Q07 「卡住的升降台」: island-story link once B6 is open; stays readable after
## the repair so late joiners can re-read 波波's reply.
func _add_hoist_chapter_link() -> void:
	if not is_instance_valid(modal) or not modal.has_meta("chapter_content"):return
	if int(session.snapshot.get("mine_depths",{}).get("unlocked",1))<6:return
	var content:VBoxContainer=modal.get_meta("chapter_content")
	if content.find_child("HoistLetterLink",false,false):return
	var link:=button("卡住的升降台",_hoist_letter)
	link.name="HoistLetterLink"
	link.icon=LifeShell.icon("letter")
	content.add_child(link)

## Live checklist state for the hoist letter (read-only snapshot view).
func _hoist_letter_state() -> Dictionary:
	var depths=session.snapshot.get("mine_depths",{})
	if not depths is Dictionary:depths={}
	var person:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{})
	var bag:Dictionary=person.get("inventory",{})
	var cost:Dictionary=World.MINES.HOIST_COST
	var stocked:=true
	var counts:=PackedStringArray()
	for item in cost:
		var have:=int(bag.get(str(item),0))
		stocked=stocked and have>=int(cost[item])
		counts.append("%s %d／%d"%[World.NAMES.get(str(item),str(item)),have,int(cost[item])])
	var repaired:bool=World.MINES.hoist_ready(depths)
	return {"unlocked":int(depths.get("unlocked",1)),"repaired":repaired,"stocked":stocked,"counts":" · ".join(counts)}

func _hoist_letter() -> void:
	var body:=_open_modal("卡住的升降台")
	modal.name="HoistLetter"
	modal.set_meta("hoist_letter",true)
	modal.set_meta("life_modal_layout","hoist_letter")
	var scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:
		var shell:=scroll.get_parent() as VBoxContainer
		shell.add_theme_constant_override("separation",6)
	var progress:VBoxContainer=LifeTasks.card(body)
	progress.add_child(label("波波的來信",21))
	var letter:=label("下坑口的升降台卡在半路了。鋼索還好好的，是幾個銅接頭鏽死，滑輪的墊木也磨光了。幫我湊齊材料，我就能讓籠子再動起來，大家不必一層層走下去。",16)
	letter.name="HoistLetterBody"
	progress.add_child(letter)
	var cost:Dictionary=World.MINES.HOIST_COST
	var joints:=int(cost.get("copper_joint",12))
	var planks:=int(cost.get("plank",4))
	var rows:Array[HBoxContainer]=[]
	rows.append(_hoist_step_row(progress,"HoistStep1","開通第 6 層"))
	rows.append(_hoist_step_row(progress,"HoistStep2","備妥 %d 個銅接頭與 %d 塊木板"%[joints,planks]))
	rows.append(_hoist_step_row(progress,"HoistStep3","到金瓜石下坑路牌交付"))
	rows.append(_hoist_step_row(progress,"HoistStep4","修好後：升降台直達第 6、10、15 層"))
	var reply:=label("",16)
	reply.name="HoistLetterReply"
	progress.add_child(reply)
	progress.add_child(button("返回島嶼故事",_chapter_menu))
	var update:=func():
		var now:=_hoist_letter_state()
		var repaired:bool=now.repaired
		_hoist_step_set(rows[0],int(now.unlocked)>=6,"目前已開通到第 %d 層。"%int(now.unlocked))
		_hoist_step_set(rows[1],repaired or bool(now.stocked),"材料已交給波波。" if repaired else "持有／所需：%s"%str(now.counts))
		_hoist_step_set(rows[2],repaired,"波波已收下材料。" if repaired else "走到下坑路牌旁，按「交付修理材料」。")
		_hoist_step_set(rows[3],repaired,"並取得玻璃爐圖樣，在家園工坊「生活」頁建造。")
		reply.text="波波回信：籠子又動起來了，一路晃到第十五層，燈都沒熄。玻璃爐的圖樣夾在信裡，第六層的赭土拿來糊爐壁剛剛好。" if repaired else ""
		reply.visible=repaired
	modal.set_meta("hoist_letter_update",update)
	update.call()

func _hoist_step_row(parent:VBoxContainer,id:String,title:String) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.name=id
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	var marker:=label("○",18)
	marker.name="Mark"
	marker.autowrap_mode=TextServer.AUTOWRAP_OFF
	marker.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	row.add_child(marker)
	var copy:=VBoxContainer.new()
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",2)
	row.add_child(copy)
	var heading:=label(title,17)
	heading.name="Title"
	copy.add_child(heading)
	var detail:=label("",15)
	detail.name="Detail"
	copy.add_child(detail)
	return row

func _hoist_step_set(row:HBoxContainer,done:bool,detail:String) -> void:
	row.set_meta("done",done)
	var marker:=row.find_child("Mark",true,false) as Label
	if marker:
		marker.text="✓" if done else "○"
		marker.add_theme_color_override("font_color",Color("436930") if done else Color("876849"))
	var copy:=row.find_child("Detail",true,false) as Label
	if copy:copy.text=detail

func _refresh_hoist_letter() -> void:
	if not is_instance_valid(modal) or not modal.has_meta("hoist_letter_update"):return
	var update=modal.get_meta("hoist_letter_update")
	if update is Callable and (update as Callable).is_valid():(update as Callable).call()

func _add_greenhouse_chapter_link() -> void:
	if not is_instance_valid(modal) or not modal.has_meta("chapter_content"):return
	if int(session.snapshot.get("mine_depths",{}).get("unlocked",1))<5:return
	var content:VBoxContainer=modal.get_meta("chapter_content")
	if content.find_child("GreenhouseLetter",false,false):return
	var link:=button("冬天也開花",_greenhouse_letter)
	link.name="GreenhouseLetter"
	link.icon=LifeShell.icon("letter")
	content.add_child(link)

func _greenhouse_letter() -> void:
	var body:=_open_modal("冬天也開花")
	var progress:VBoxContainer=LifeTasks.card(body)
	var person:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{})
	var completed:String=person.get("greenhouse_cross_season_crop","")
	var crafted:bool=person.get("greenhouse_glass_crafted",false)
	var covered:bool=session.snapshot.get("roofs",{}).values().any(func(roof):
		return roof.get("type","")=="greenhouse_roof" and roof.get("owner","")==session.own_id)
	progress.add_child(label("星禾的來信",21))
	progress.add_child(label("冬天一到，花田就安靜下來了。我想留一小塊暖地，讓錯過花季的種子，也有機會慢慢長大。",16))
	_greenhouse_step(progress,crafted,"製作溫室玻璃","到望安星砂海岸或金瓜石第五層採晶砂，再到工作台用晶砂 2、木炭 1 製作。")
	_greenhouse_step(progress,covered or not completed.is_empty(),"在自己的農田搭玻璃棚","在家園工坊的「基礎」選溫室玻璃棚。玻璃擋雨，記得澆水。")
	var ending:="挑一株當季會休眠的作物，在自己的棚內照顧到成熟。"
	var reported:bool=person.get("greenhouse_reported",false)
	if completed.is_empty():
		var now:=float(session.snapshot.get("time",0.0))
		var bag:Dictionary=person.get("inventory",{})
		for crop_id:String in World.CROP_SEASONS:
			if int(bag.get(crop_id+"_seed",0))<=0 or World.crop_grows_in_season(crop_id,World.REGIONS.HOME,Vector2i.ZERO,now):continue
			ending="背包裡的%s種子目前不適合露天種植。可種進自己的玻璃棚，澆水後等它長大。"%World.NAMES[crop_id]
			break
	if not completed.is_empty():
		ending="在棚裡收成了%s。" % World.NAMES.get(completed,completed)
	_greenhouse_step(progress,not completed.is_empty(),"收成跨季作物",ending)
	_greenhouse_step(progress,reported,"向星禾回報","星禾已把收成寫進手記。" if reported else "到宜蘭水圳找星禾，分享你的收成紀錄。")
	progress.add_child(button("返回島嶼故事",_chapter_menu))

func _greenhouse_step(parent:VBoxContainer,done:bool,title:String,detail:String) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	var marker:=label("✓" if done else "○",18)
	marker.add_theme_color_override("font_color",Color("436930") if done else Color("876849"))
	row.add_child(marker)
	var copy:=VBoxContainer.new()
	copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation",2)
	row.add_child(copy)
	copy.add_child(label(title,17))
	copy.add_child(label(detail,15))

func _add_tea_chapter_link() -> void:
	if not TeaUI.unlocked(session.snapshot) or not is_instance_valid(modal) or not modal.has_meta("chapter_content"):return
	var content:VBoxContainer=modal.get_meta("chapter_content")
	if content.find_child("ChapterTeaLetter",false,false):return
	var link:=button("第二章・茶陶合作手帳",func():TeaUI.open(self,"journal"))
	link.name="ChapterTeaLetter"
	link.icon=LifeShell.icon("letter")
	content.add_child(link)

func _community_menu() -> void:
	CommunityUI.open(self)
	LifeTasks.add_milu_recipe_page(self,"table")
	_layout_preview.call_deferred()

func _gardener_menu() -> void:
	LanyangUI.open(self)
	_layout_preview.call_deferred()

func _history_menu() -> void:
	HistoryUI.open(self)

func _travel_menu(station_id:String="",selected:String="") -> void:
	TravelUI.open(self,station_id,selected)
	if station_id=="ferry":LifeTasks.add_achao_route_marker(self,"ferry")
	_layout_preview.call_deferred()

func _station_resident_menu(region:String) -> void:
	StationLifeUI.open(self,region)
	_layout_preview.call_deferred()

func _floor_placement_menu(tile:Vector2i,floor_piece:Dictionary) -> void:
	var column:=_open_modal("木地板 · 家園權限")
	var current:=str(floor_piece.get("placement_access","legacy"))
	for option in [["owner","只限地板主人"],["island","開放同島玩家"],["legacy","沿用預設規則"]]:
		var mode:String=option[0]
		var caption:String=option[1]
		var choice:=button(caption,func():session.perform("floor_placement_access",tile,mode);_close_modal())
		choice.disabled=mode==current
		column.add_child(choice)
	column.add_child(label("預設規則允許手動擺放，藍圖施工限地板主人。",15))
	column.add_child(HSeparator.new())
	var private_room:bool=floor_piece.get("owner_visit",false)
	var guest_id:=str(floor_piece.get("visit_guest",""))
	var room:=World.ROOM_ENCLOSURE.analyze(session.snapshot,tile)
	var place:="房間" if room.sealed else "戶外地塊"
	var preview:=World.new()
	preview.state=session.snapshot
	var restriction:=preview.visit_restriction_problem(session.own_id,room)
	var can_restrict:=restriction.is_empty()
	var visit_status:="僅屋主可進入" if private_room else "開放同島玩家"
	if not guest_id.is_empty():
		visit_status="屋主與 "+str(session.snapshot.players.get(guest_id,{}).get("name","指定島民"))
	column.add_child(label(place+"參觀 · "+visit_status,18))
	if not room.sealed:
		column.add_child(label("相連木地板 %d 格 · 戶外最多 %d 格，公共通道需保持開放。"%[room.area,World.MAX_OUTDOOR_VISIT_TILES],15))
	var access:=button("開放"+place+"參觀" if private_room else "將"+place+"設為僅屋主可進",func():
		session.perform("room_visit_access",tile,"island" if private_room else "owner")
		_close_modal())
	access.disabled=not private_room and not can_restrict
	column.add_child(access)
	if not can_restrict:column.add_child(label(restriction,15))
	if not guest_id.is_empty():
		var revoke:=button("收回指定訪客權限",func():session.perform("room_visit_access",tile,"owner");_close_modal())
		revoke.disabled=not can_restrict
		column.add_child(revoke)
	if can_restrict:
		var players:Dictionary=session.snapshot.players
		var names:Dictionary={}
		for player in players.values():
			names[player.name]=int(names.get(player.name,0))+1
		for player_id:String in players:
			if player_id==session.own_id:continue
			var display_name:String=players[player_id].name
			if names[display_name]>1:display_name+="（"+player_id.right(6)+"）"
			var guest:=button("指定訪客 · "+display_name,func():
				session.perform("room_visit_access",tile,"friend:"+player_id)
				_close_modal())
			guest.disabled=player_id==guest_id
			column.add_child(guest)

func _furniture_removal_menu(tile:Vector2i,furniture:Dictionary) -> void:
	var column:=_open_modal(World.BUILD[furniture.type].name+" · 拆除權限")
	var shared:bool=furniture.get("guest_remove",false)
	column.add_child(label("同島玩家可拆除這件家具。" if shared else "目前只有物主可拆除。",18))
	column.add_child(label("拆除時，建材會退回物主的背包。",16))
	column.add_child(button("收回拆除權" if shared else "開放同島玩家拆除",func():
		session.perform("furniture_remove_access",tile,"owner" if shared else "island")
		_close_modal()))

func _star_walk_project() -> void:
	var column:=_open_modal("星砂海岸・修復步道")
	column.add_child(label("把木棧道接回沙岸，屋裡做玻璃時就能到這裡找晶砂。",16))
	var bag:Dictionary=session.snapshot.players[session.own_id].inventory
	var available:=true
	for material:String in World.WANGAN_COAST.STAR_COST:
		var required:int=World.WANGAN_COAST.STAR_COST[material]
		var held:=int(bag.get(material,0))
		column.add_child(label("%s　%d／%d"%[World.NAMES[material],held,required],16))
		available=available and held>=required
	var repair:=button("交付材料並修好步道",func():
		_close_modal()
		session.perform(World.WANGAN_COAST.STAR_REPAIR_POINT,World.WANGAN_COAST.STAR_REPAIR))
	repair.name="StarWalkRepair"
	repair.disabled=not available
	column.add_child(repair)

func _map_menu(return_to_ticket:=Callable()) -> void:
	var col:=_open_modal("周邊地圖  {map}")
	modal.set_meta("life_modal_layout","island_map")
	if return_to_ticket.is_valid():
		modal.set_meta("return_to_travel_ticket",return_to_ticket)
	map_view=IslandMap.new()
	col.add_child(map_view)
	map_view.update_world(session.snapshot,session.own_id)
	var map_heading:Node=col.get_parent().get_parent().get_child(0) if village_art_preview else col.get_child(0)
	var trip_link:Button
	if return_to_ticket.is_valid():
		trip_link=map_heading.get_child(1) as Button
		trip_link.text="返回旅途車票"
		trip_link.pressed.disconnect(_close_modal)
		trip_link.pressed.connect(return_to_ticket)
		if controller_navigation:trip_link.grab_focus.call_deferred()
	else:
		trip_link=button("台灣旅圖",_travel_menu)
		map_heading.add_child(trip_link)
	trip_link.name="LocalMapTravel"
	if session.snapshot.get("region_id")=="jinguashi":
		var history_link:=button("礦山記憶",func():HistoryUI.open(self,"jinguashi",Vector2i(-1,-1),_map_menu))
		history_link.name="JinguashiMapHistory"
		map_heading.add_child(history_link)
	elif session.snapshot.get("region_id")==SaltUI.REGION:
		var salt_history:=button("鹽田記憶",func():SaltUI.open(self,"journal"))
		salt_history.name="BeimenMapHistory"
		map_heading.add_child(salt_history)
	_layout_preview.call_deferred()

func _build_menu() -> void:
	if village_art_preview:life_panels.build_menu(self);return
	var col:=_open_modal("把家園蓋成喜歡的樣子")
	col.add_child(label("選物件後點地面放置。材料在成功保存後扣除。",14))
	var undo_row:=HBoxContainer.new()
	undo_row.name="UndoRow"
	undo_row.add_theme_constant_override("separation",8)
	col.add_child(undo_row)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=420
	col.add_child(scroll)
	# Confirmation strip sits under the undo row; the list shrinks while it shows.
	undo_ui.attach(self,undo_row,col,undo_row.get_index()+1,func(shown:bool):scroll.custom_minimum_size.y=340 if shown else 420)
	var book:=button("藍圖冊",_blueprint_menu)
	book.name="BlueprintBook"
	book.tooltip_text="框選整組建築存成藍圖，再放到地圖上報價施工"
	undo_row.add_child(book)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",8)
	scroll.add_child(rows)
	for kind in World.BUILD:
		var recipe:Dictionary=World.BUILD[kind]
		var price:=""
		for item in recipe:
			if World.NAMES.has(item):price+="%s %d  "%[World.NAMES[item],recipe[item]]
		var selected_kind:String=kind
		var person:Dictionary=session.snapshot.players.get(session.own_id,{})
		var allowed:=Village.unlocked(person,kind)
		var entry:=button(recipe.name+"     "+price if allowed else recipe.name+"  ·  完成居民故事解鎖（{journal}）",func():building=selected_kind;building_style="";_select_tool("build");_close_modal())
		entry.disabled=not allowed
		rows.add_child(entry)

func _seed_menu() -> void:
	if village_art_preview:life_panels.seed_menu(self);return
	var seed_action:="seed_area" if selected=="seed_area" else "seed"
	var col:=_open_modal("今天想種什麼？")
	for kind in World.CROPS:
		var c:Dictionary=World.CROPS[kind]
		var selected_crop:String=kind
		col.add_child(button("%s  ·  測試成熟時間 %d 秒"%[c.name,c.time],func():crop=selected_crop;_select_tool(seed_action);_close_modal()))
	col.add_child(button("種樹苗  {plant_tree}  ·  三分鐘長成  ·  不需澆水",func():_select_tool("plant_tree");_close_modal()))
	col.add_child(label("原型為方便試玩加快成長。需要先鋤地，再播種與澆水。",16))

func _inventory() -> void:
	if village_art_preview:
		_open_inventory_grid()
		return
	var col:=_open_modal("隨身背包")
	modal.set_meta("input_inventory",true)
	var s:Dictionary=session.snapshot
	if not s.players.has(session.own_id):return
	var p:Dictionary=s.players[session.own_id]
	col.add_child(label("鈴幣  %d"%p.coins,22))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=350
	col.add_child(scroll)
	var text:=""
	for item in World.NAMES:text+="%-12s   %d\n"%[World.NAMES[item],p.inventory.get(item,0)]
	scroll.add_child(label(text,18))
	col.add_child(label("工具不會損壞。世界無人時暫停生長，離開不用擔心作物枯萎。",14))

func _open_inventory_grid() -> void:
	if playing:session.input_direction(Vector2.ZERO)
	area_drag=false
	capture_drag=false
	moving_object=false
	_close_modal()
	for child in hud.get_children():
		if child is Control and child.visible:
			inventory_hidden_controls.append(child)
			child.hide()
	toast.hide()
	modal_shade=ColorRect.new()
	modal_shade.color=Color(0.12,0.19,0.14,0.48)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(modal_shade)
	var backpack:=InventoryPanel.new()
	modal=backpack
	hud.add_child(backpack)
	backpack.close_requested.connect(_close_modal)
	backpack.rice_ball_requested.connect(func():session.perform("eat_rice_ball",Vector2i.ZERO))
	backpack.ginger_tea_requested.connect(func():session.perform("drink_ginger_tea",Vector2i.ZERO))
	backpack.rope_requested.connect(func():session.perform("handcraft_rope",Vector2i.ZERO))
	backpack.setup(session.snapshot,session.own_id,hud.theme,binding_label)
	backpack.layout_for(get_viewport().get_visible_rect().size)
	LifeShell.reveal(self,backpack)
	_layout_preview.call_deferred()

func _shipping_menu() -> void:
	if playing:session.input_direction(Vector2.ZERO)
	area_drag=false
	capture_drag=false
	moving_object=false
	_close_modal()
	_hide_world_hud()
	toast.hide()
	modal_shade=ColorRect.new()
	modal_shade.color=Color(0.12,0.19,0.14,0.42)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(modal_shade)
	var shipping:=ShippingPanel.new()
	modal=shipping
	hud.add_child(shipping)
	shipping.close_requested.connect(_close_modal)
	shipping.shipment_requested.connect(func(payload:String):
		shipping.pending_sequence=session.counter+1
		session.perform("ship",World.SHIPPING.cell_for(session.snapshot),payload)
	)
	shipping.setup(session.snapshot,session.own_id,hud.theme)
	shipping.layout_for(get_viewport().get_visible_rect().size)
	LifeShell.reveal(self,shipping)
	_layout_preview.call_deferred()

func _board() -> void:
	if village_art_preview:
		LifeTasks.board(self)
		LifeTasks.add_achao_route_marker(self,"board")
		LifeTasks.add_milu_recipe_page(self,"board")
		LifeTasks.add_public_mural_link(self)
		_add_freight_board_link()
		return
	var col:=_open_modal("渡口的共同工程")
	LifeTasks.add_milu_recipe_page(self,"board")
	LifeTasks.add_public_mural_link(self)
	var s:Dictionary=session.snapshot
	col.add_child(label("把公告板修好，河灣橋就能重新開放。\n大家可以各自採集，材料會累積在同一個工程裡。",19))
	col.add_child(label("木材 %d / 30\n石材 %d / 10"%[s.donations.wood,s.donations.stone],26))
	col.add_child(button("捐入背包裡需要的材料",func():session.perform("donate",Vector2i(40,29));_close_modal()))
	col.add_child(label("只扣尚缺的數量，不會把多餘材料全部拿走。",15))
	if s.board:
		col.add_child(label("野餐準備：蘿蔔湯 %d / 2，麵包 %d / 1"%[s.picnic_materials.soup,s.picnic_materials.bread],18))
		col.add_child(button("把料理放到野餐桌上",func():session.perform("picnic",Vector2i(40,29));_close_modal()))
		col.add_child(button("生活訂單  ·  每個世界日更新",_orders_menu))
		if s.picnic:col.add_child(button("一起玩風鈴接力  {festival}",_festival_menu))
		if s.picnic:col.add_child(button("一起玩豐收接力（廣場西側）",_harvest_menu))
		col.add_child(button("河岸釣魚會（河灣橋南岸）" if s.picnic else "河岸釣魚會・渡口野餐後開放",_fishmeet_menu))
		col.add_child(button("家園布置題（渡口西南草地）" if s.picnic else "家園布置題・渡口野餐後開放",_showcase_menu))
		col.add_child(button(SouvenirUI.entry_caption(s.picnic),_souvenir_menu))
	if int(s.get("mine_depths",{}).get("unlocked",1))>=5:col.add_child(button("礦車寄運與待領貨物",_freight_menu))
	LifeTasks.add_fund_controls(self,col,s)

func _auto_freight_menu() -> void:
	AutoFreightUI.open(self)

func _freight_menu() -> void:
	FreightUI.open(self)

func _bobo_sort_menu() -> void:
	BoboSortUI.open(self)

func _mine_mud_menu(phase:int) -> void:
	var snapshot:Dictionary=session.snapshot
	var adventure:bool=snapshot.get("world_mode")=="adventure"
	if phase==0 and adventure:
		var person:Dictionary=snapshot.players.get(session.own_id,{})
		var duel:Dictionary=person.get("mud_duel",{})
		var now:=float(snapshot.get("time",0.0))
		var strike_at:=float(duel.get("strike_at",-100.0))
		if now<strike_at+World.MINES.MUD_RECOVERY:
			if now>=strike_at:session.perform("mine_mud_duel",World.MINES.MUD_GATE,"strike")
			else:_notice("牠正在準備衝刺，先側移。",false)
			return
	var column:=_open_modal("礦洞北側 · 小泥團")
	if phase==0 and adventure:
		column.add_child(label("小泥團會先蹲低再衝刺。看到提示後向左或右側移，等牠停下，再按 {interact} 反擊。",18))
		var begin:=button("開始挑戰小泥團",func():
			session.perform("mine_mud_duel",World.MINES.MUD_GATE,"start")
			_close_modal())
		begin.name="MineMudDuel"
		column.add_child(begin)
	elif phase==0:
		column.add_child(label("小泥團趴在洞口。牠抬起頭，似乎聞到了蘿蔔的香味。",18))
		var bait:=button("用一顆蘿蔔引開牠",func():
			session.perform("mine_mud_lure",World.MINES.MUD_GATE)
			_close_modal())
		bait.name="MineMudLure"
		column.add_child(bait)
	else:
		column.add_child(label("小泥團讓出通道，洞裡露出了四塊銅礦料。",18))
		var claim:=button("拾取銅礦料",func():
			session.perform("mine_mud_claim",World.MINES.MUD_REWARD)
			_close_modal())
		claim.name="MineMudClaim"
		column.add_child(claim)

func _mine_site_menu(site:String) -> void:
	MineUI.open(self,site)

func _mine_survey_menu(page:int=1,return_site:String="") -> void:
	MineSurveyUI.open(self,page,false,return_site)

func _add_freight_board_link() -> void:
	if int(session.snapshot.get("mine_depths",{}).get("unlocked",1))<5:return
	var content=modal.find_child("ModalContent",true,false)
	if content:
		var link:Button=button("礦車寄運 · 查看到貨與待領",_freight_menu)
		link.name="BoardFreight"
		content.add_child(link)
		content.move_child(link,0)

func _shop() -> void:
	if village_art_preview:
		life_panels.shop(self)
		LifeTasks.add_milu_recipe_page(self,"shop")
		var content:=modal.find_child("ModalContent",true,false) as VBoxContainer
		if content:
			_add_tea_counter_link(content)
			FlowerUI.counter_link(self,content)
			SaltUI.counter_link(self,content)
		return
	var col:=_open_modal("小栗的種子攤")
	LifeTasks.add_milu_recipe_page(self,"shop")
	col.add_child(button("和小栗聊聊",func():_resident_menu("xiaoli")))
	if session.snapshot.has("own_shop_history"):
		var trade_book:=button("翻開交易簿",life_panels.trade_book.bind(self))
		trade_book.name="ShopTradeBook"
		col.add_child(trade_book)
	_add_tea_counter_link(col)
	FlowerUI.counter_link(self,col)
	SaltUI.counter_link(self,col)
	col.add_child(label("「把收成帶來吧，再帶些新的種子回家！」",18))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=360
	col.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",8)
	scroll.add_child(rows)
	for kind in World.CROPS:
		var c:Dictionary=World.CROPS[kind]
		var chosen:String=kind
		var row:=HBoxContainer.new()
		rows.add_child(row)
		var l:=label(c.name,17)
		l.custom_minimum_size.x=150
		row.add_child(l)
		if FlowerUI.stall_locked(session.snapshot,kind):row.add_child(label(FlowerUI.STALL_LOCK_REASON,14))
		else:row.add_child(button("種子 %d 鈴幣"%c.seed_price,func():session.perform("buy",Vector2i(43,29),chosen)))
		row.add_child(button("出售全部 · 每個 %d"%c.price,func():session.perform("sell",Vector2i(43,29),chosen)))
	for item in World.FISH.keys()+World.OTHER_SALES.keys():
		var chosen:String=item
		var price:int=World.FISH[item].price if World.FISH.has(item) else World.OTHER_SALES[item]
		rows.add_child(button("出售全部 %s · 每個 %d 鈴幣"%[World.NAMES[item],price],func():session.perform("sell",Vector2i(43,29),chosen)))
	var inventory:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{})
	for item:String in inventory:
		if int(inventory[item])<=0 or not World.CROP_CATALOG.quality_item(item):continue
		rows.add_child(button("出售全部 %s · 每個 %d 鈴幣"%[World.NAMES[item],World.CROP_CATALOG.quality_price(item)],
			session.perform.bind("sell",Vector2i(43,29),item)))
	rows.add_child(button("購買樹苗 · 每棵 20 鈴幣",func():session.perform("buy",Vector2i(43,29),"sapling")))
	col.add_child(label("買一包種子會扣一次錢；出售前請留意按鈕會賣出該作物全部收成。",15))

func _add_tea_counter_link(content:VBoxContainer) -> void:
	if not TeaUI.unlocked(session.snapshot):return
	var link:=button("小栗的茶單與回收",_tea_home)
	link.name="XiaoliTeaOrder"
	link.icon=LifeShell.icon("letter")
	content.add_child(link)
	content.move_child(link,0)

func _tea_home()->void:
	TeaUI.open(self,"home")

func _chest(p:Vector2i) -> void:
	if village_art_preview:life_panels.chest(self,p);return
	var box:Dictionary=session.snapshot.objects[World.key(p)]
	var private_box:bool=box.type in World.PRIVATE_BOXES
	var visitor:bool=box.get("locked",false)
	var can_withdraw:bool=not visitor or box.get("guest_withdraw",false)
	var can_deposit:bool=not visitor or box.get("guest_deposit",false)
	var col:=_open_modal("私人箱" if private_box else "共用箱")
	col.add_child(label("每次存取一個。裡面有物品時不能拆除。",15))
	if box.type=="private_chest" and not visitor:
		col.add_child(_chest_deposit_toggle(p,box))
		col.add_child(_chest_withdraw_picker(p))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=390
	col.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for item in World.NAMES:
		var chosen:String=item
		var row:=HBoxContainer.new()
		rows.add_child(row)
		var obj:Dictionary=session.snapshot.objects[World.key(p)]
		var l:=label("%s  箱內 %d"%[World.NAMES[item],obj.items.get(item,0)] if can_withdraw else World.NAMES[item],16)
		l.custom_minimum_size.x=270
		row.add_child(l)
		if can_deposit:row.add_child(button("存 1",func():session.perform("deposit",p,chosen);_close_modal()))
		if can_withdraw:row.add_child(button("取 1",func():session.perform("withdraw",p,chosen);_close_modal()))

func _chest_deposit_toggle(p:Vector2i,box:Dictionary) -> Button:
	var open:bool=box.get("guest_deposit",false)
	var toggle:=button("停止接受同島玩家存入" if open else "允許同島玩家存入",func():
		session.perform("box_deposit_access",p,"owner" if open else "island")
		_close_modal())
	toggle.name="ChestGuestDeposit"
	return toggle

func _chest_withdraw_picker(p:Vector2i) -> Button:
	var picker:=button("設定訪客取出權限",_chest_withdraw_menu.bind(p))
	picker.name="ChestGuestWithdraw"
	return picker

func _chest_withdraw_menu(p:Vector2i) -> void:
	var box:Dictionary=session.snapshot.objects.get(World.key(p),{})
	if box.get("type")!="private_chest" or box.get("locked",false):return
	var column:=_open_modal("私人箱 · 取出權限")
	var current:=str(box.get("withdraw_guest",""))
	column.add_child(label("指定一位在線島民查看與取出箱內物品。存入權限可另外設定。",16))
	var revoke:=button("只限箱主取出",func():
		session.perform("box_withdraw_access",p,"owner")
		_close_modal())
	revoke.disabled=current.is_empty()
	column.add_child(revoke)
	var people:Dictionary=session.snapshot.players
	var names:Dictionary={}
	for person in people.values():names[person.name]=int(names.get(person.name,0))+1
	for player_id:String in people:
		if player_id==session.own_id:continue
		var display_name:String=people[player_id].name
		if names[display_name]>1:display_name+="（"+player_id.right(6)+"）"
		var choice:=button("開放給 "+display_name,func():
			session.perform("box_withdraw_access",p,"friend:"+player_id)
			_close_modal())
		choice.disabled=player_id==current
		column.add_child(choice)

func _workshop_guide(topic:int=-1)->void:
	load("res://scripts/workshop_guide.gd").open(self,topic)

func _help() -> void:
	if village_art_preview:LifeShell.help(self);return
	var col:=_open_modal("第一天的小島生活")
	col.add_child(label("1  在空地鋤田 → 選種子 → 澆水 → 成熟後採收。\n2  樹用斧頭三下，石頭用鎬兩下。\n3  按 {build_menu} 選家具，點附近空地放置。\n4  靠近公告板按 {interact}，捐材料修橋。\n5  靠近種子攤按 {interact}，出售收成、買種子。\n6  放一個箱子，與朋友共享材料。",19))
	col.add_child(label("操作範圍為角色周圍約三格。{zoom} 切換近景與遠景；{journal} 看居民手帳。\n{move_object} 搬自己的家具；選地板、步道或屋頂後，{area_modifier}＋拖曳可一次鋪設。\n固定鏡頭沒有旋轉或震動，每次成功操作後保存。",16))
	col.add_child(label("{fish} 釣魚；小石灶做料理與飼料；靠近糯米雞按 {interact} 照料。\n{plant_tree} 種樹苗，三分鐘長成；砍樹取得下一棵樹苗。\n{remove} 拆除也能移回樹苗、恢復自己的空農田。屋頂需先鋪地板，進屋會淡化。",15))

	col.add_child(label("{collection} 看生活圖鑑與里程碑；Esc 選單可調整音效音量與減少動態。",15))

func _cook_menu(p:Vector2i) -> void:
	# Both HUD styles share the queue workbench (legacy stove.job is shown inside it).
	if village_art_preview:life_panels.cook(self,p);return
	CookingQueueUI.open(self,p)

func _resident_story_dialogue(parent:Container,resident:String) -> void:
	LifeTasks.add_resident_dialogue(self,parent,resident)

## T066：茶茶、星禾的好感頁（從茶園與水圳對話頁進入）。
func _resident_bond_menu(resident:String) -> void:
	LifeTasks.bond_dialogue(self,resident)

func _tea_host() -> void:
	TeaUI.open(self,"host")

func _resident_menu(resident:String) -> void:
	if village_art_preview:LifeTasks.resident(self,resident);return
	var npc:Dictionary=Village.NPCS[resident]
	var col:=_open_modal(npc.name+"的島上日常")
	var person:Dictionary=session.snapshot.players[session.own_id]
	var stage:=int(person.get("stories",{}).get(resident,0))
	col.add_child(label(npc.hello,18))
	LifeTasks.add_resident_dialogue(self,col,resident)
	col.add_child(label("關係故事  %d / 4"%stage,16))
	if stage<4:
		var q:Dictionary=Village.QUESTS[resident][stage]
		col.add_child(label(q.title,24))
		col.add_child(label(q.goal,19))
		var needed:=""
		for item in q.items:needed+="%s：%d / %d\n"%[World.NAMES[item],person.inventory.get(item,0),q.items[item]]
		if q.has("counter"):needed+="目前完成 %d / %d 次\n"%[person.get(q.counter,0),q.target]
		var reward:="完成獲得 %d 鈴幣"%q.coins
		for item in q.reward:reward+="、%s %d"%[World.NAMES[item],int(q.reward[item])]
		if q.has("unlock"):reward+="，並取得"+World.BUILD[q.unlock].name+"圖樣"
		col.add_child(label(needed+reward,17))
		var request:=resident+":"+str(stage)
		col.add_child(button("交付這段委託",func():session.perform("quest",Village.resident_cell(session.snapshot,resident),request);_close_modal()))
	else:col.add_child(label("「"+Village.QUESTS[resident][3].line+"」",22))
	var bond_actions:=HFlowContainer.new()
	LifeTasks.add_bond_controls(self,col,bond_actions,resident)
	LifeTasks.add_address_delivery(self,bond_actions,resident)
	if resident=="milu":
		LifeTasks.add_milu_apron_button(self,bond_actions)
		LifeTasks.add_milu_recipe_book(self,bond_actions)
	col.add_child(bond_actions)
	if not LifeTasks.bond_view(self,resident).is_empty():col.add_child(button("關係事件",LifeTasks.bond_events.bind(self,resident)))
	col.add_child(button("打開故事手冊  {journal}",_journal))
	col.add_child(label("故事沒有期限，朋友可以先完成；你的進度與紀念都會保留。",15))

func _journal(selected_resident:String="") -> void:
	var region:=str(session.snapshot.get("region_id","home"))
	if selected_resident.is_empty() and region=="tianwei":
		FlowerUI.open(self,"journal")
		return
	if selected_resident.is_empty() and region==SaltUI.REGION:
		SaltUI.open(self,"journal")
		return
	if selected_resident.is_empty() and region in ["maokong","yingge"]:
		TeaUI.open(self,"journal")
		return
	if selected_resident.is_empty() and region in World.MINES.IDS:
		_mine_survey_menu(int(region.trim_prefix("mine_")))
		return
	if village_art_preview:LifeTasks.journal(self,selected_resident);return
	var col:=_open_modal("島民手冊  {journal}")
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=440
	col.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",12)
	scroll.add_child(rows)
	var person:Dictionary=session.snapshot.players[session.own_id]
	for resident in Village.NPCS:
		var stage:=int(person.get("stories",{}).get(resident,0))
		rows.add_child(label(Village.NPCS[resident].name+"  ·  %d / 4 段故事"%stage,23))
		for i in range(4):
			var q:Dictionary=Village.QUESTS[resident][i]
			if i<stage:rows.add_child(label("✓ "+q.title+"\n「"+q.line+"」",17))
			elif i==stage:rows.add_child(label("接下來："+q.title+"\n"+q.goal+"\n到居民身邊按 {interact} 交件。",18))
			else:rows.add_child(label("尚未展開："+q.title,15))
	rows.add_child(label("公告板修好後，每天有三張生活訂單；M 地圖可找公共採石點。番茄可連收三次，每次收成後需要再澆水。",17))

func _orders_menu() -> void:
	LifeAlmanac.orders_menu(self)

func _quarry_menu() -> void:
	var col:=_open_modal("河灣公共採石點")
	var q:Dictionary=session.snapshot.get("quarry",{})
	var wait:=maxi(0,ceili(float(q.get("ready",0))-float(session.snapshot.time)))
	col.add_child(label("三下取出 6 石材，之後約 45 秒露出新石層。\n和朋友共享進度，沒人在線時等待也暫停。",19))
	col.add_child(label("新石層約剩 %d 秒"%wait if wait>0 else "目前進度 %d / 3"%q.get("hits",0),24))
	col.add_child(button("採一下石材",func():session.perform("quarry",Vector2i(54,25));_close_modal()))

func _festival_memory() -> void:
	LifeAlmanac.festival_story(self,true)

func _festival_menu() -> void:
	if village_art_preview:LifeAlmanac.festival_menu(self);return
	var col:=_open_modal("渡口派對  ·  風鈴接力")
	var s:Dictionary=session.snapshot
	var f:Dictionary=s.festival
	col.add_child(label("一到四位島民沿渡口接力收集十二枚金色風鈴。\n靠近風鈴按 {interact}，下一枚就會出現在另一處。\n沒有失敗倒數，不消耗材料，中途離線也會保留進度。",18))
	if not s.picnic:
		col.add_child(label("先完成公告板的渡口野餐，就能一起辦小派對。",22))
		col.add_child(button("豐收接力・渡口野餐後開放",_harvest_menu))
		col.add_child(button("河岸釣魚會・渡口野餐後開放",_fishmeet_menu))
		col.add_child(button("家園布置題・渡口野餐後開放",_showcase_menu))
		col.add_child(button(SouvenirUI.ENTRY_LOCKED,_souvenir_menu))
		return
	col.add_child(button("豐收接力（廣場西側，1～8 人）",_harvest_menu))
	col.add_child(button("河岸釣魚會（河灣橋南岸，1～8 人）",_fishmeet_menu))
	col.add_child(button("家園布置題（渡口西南草地，1～8 人）",_showcase_menu))
	col.add_child(button(SouvenirUI.ENTRY_OPEN,_souvenir_menu))
	if f.active:
		var cell:=Festival.target(f)
		col.add_child(label("第 %d 場 · 共同收集 %d / 12\n下一枚在渡口座標 %d, %d。"%[int(f.round),int(f.collected),cell.x,cell.y],22))
	else:
		if int(f.round)>0:col.add_child(label("上一場完成！用時 %d 秒 · 最快 %d 秒\n獎勵已存入每位參與者的背包帳目。"%[ceili(float(f.finished)-float(f.started)),ceili(float(f.best))],20))
		var wait:=maxi(0,ceili(float(f.ready)-float(s.time)))
		var round_id:=str(int(f.round))
		var start:=button("約 %d 秒後可再玩"%wait if wait>0 else "在公告板旁開始一場接力",func():session.perform("festival_start",Vector2i(40,29),round_id);_close_modal())
		start.disabled=wait>0
		col.add_child(start)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=130
	col.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for contributor in f.contributors.values():rows.add_child(label("%s  ·  接住 %d 枚%s"%[contributor.name,int(contributor.count),"" if f.active else "  ·  鈴幣 +%d"%(20+2*int(contributor.count))],17))
	col.add_child(label("完成後每位有收集的島民得 20 鈴幣，加上每枚 2 鈴幣。\n五分鐘世界時間後可再玩；沒人在線時計時暫停。",16))

func _animal_menu() -> void:
	if village_art_preview:LifeAlmanac.animal_menu(self);return
	var col:=_open_modal("糯米雞的小小日常")
	LifeAlmanac.add_animal_sketch(self,col,"chicken",World.CHICKEN_CELL)
	var animal:Dictionary=session.snapshot.get("animal",{})
	col.add_child(label(World.chicken_status(animal,float(session.snapshot.time)),20))
	if animal.has("basket_eggs"):
		col.add_child(label("收集籃 · 雞蛋 %d / %d"%[animal.basket_eggs,World.EGG_BASKET_CAPACITY],17))
	else:
		col.add_child(button("裝設收集籃",func():session.perform("install_egg_basket",World.CHICKEN_CELL);_close_modal()))
	col.add_child(label("親密度  %d\n餵食需要一份飼料；可用小麥 1、纖維 2 在小石灶做出四份。"%animal.get("bond",0),17))
	col.add_child(button("摸摸糯米雞",func():session.perform("pet",Vector2i(45,34));_close_modal()))
	col.add_child(button("餵一份飼料",func():session.perform("feed",Vector2i(45,34));_close_modal()))
	col.add_child(button("收取雞蛋",func():session.perform("egg",Vector2i(45,34));_close_modal()))
	LifeAlmanac.add_chicken_cuddle(self,col)
	col.add_child(label("沒餵食只會暫停產蛋，牠不會餓死，也不會因離線討厭你。",15))

func _collection_gallery() -> void:
	LifeAlmanac.collection_menu(self,6)

func _collection_menu() -> void:
	if village_art_preview:LifeAlmanac.collection_menu(self);return
	var col:=_open_modal("小島生活圖鑑  {collection}")
	col.add_child(label("記錄親手採收、釣魚、料理和海岸採集。出售或使用後仍會保留。",16))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=425
	col.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",12)
	scroll.add_child(rows)
	var person:Dictionary=session.snapshot.players[session.own_id]
	var collection:Dictionary=person.get("collection",{})
	for id in Collections.MILESTONES:
		var milestone:Dictionary=Collections.MILESTONES[id]
		var progress:int=Collections.progress(person,id)
		var claimed:bool=collection.get("claimed",{}).get(id,false)
		rows.add_child(label("%s  ·  %d / %d"%[milestone.name,progress,int(milestone.target)],21))
		rows.add_child(label(milestone.reward_text,16))
		var request:String=id
		var claim:=button("✓ 已領取" if claimed else ("領取里程碑獎勵" if progress>=int(milestone.target) else "再發現一些，慢慢來"),func():session.perform("claim_milestone",Vector2i.ZERO,request);_close_modal())
		claim.disabled=claimed or progress<int(milestone.target)
		rows.add_child(claim)
	var catalogs:={ "菜園的收成":["crops",World.CROPS], "島岸的魚":["fish",World.FISH],
		"親手領取的料理":["meals",World.RECIPES], "望安海岸採集":["shore",Collections.SHORE_FINDS] }
	for heading in catalogs:
		rows.add_child(label(heading,22))
		var category:String=catalogs[heading][0]
		var entries:Dictionary=catalogs[heading][1]
		for id in entries:
			if category=="meals" and not World.Collections.is_meal(id):continue
			var found:bool=collection.get(category,{}).get(id,false)
			rows.add_child(label(("✓ " if found else "○ ")+entries[id].name,17))
	rows.add_child(label("新版開始記錄親手取得的種類；舊背包物品不會自動算入圖鑑。",15))

func _settings_menu() -> void:
	if village_art_preview:LifeShell.settings(self);return
	var col:=_open_modal("音效與舒適設定")
	if village_art_preview:modal.set_meta("life_modal_layout","settings");_layout_preview()
	col.add_child(label("固定 2D 視角，沒有鏡頭旋轉、震動或動態模糊。",17))
	var camera:=LifeShell.camera_setting(self,col)
	var audio:=LifeShell.audio_settings(self,col)
	var motion:=CheckButton.new()
	motion.text="減少裝飾動態"
	motion.tooltip_text="開啟時保留靜態提示；關閉可看見釣魚、料理與共餐動畫。兩種模式皆無鏡頭震動。"
	motion.custom_minimum_size.y=44
	motion.button_pressed=sound.reduced_motion
	col.add_child(motion)
	var zoom:=OptionButton.new()
	zoom.add_item("近景：較大的角色與像素",2)
	zoom.add_item("遠景：看見較多島嶼",1)
	zoom.selected=0 if view.zoom==2.0 else 1
	zoom.custom_minimum_size.y=44
	col.add_child(zoom)
	var text_scale:=LifeShell.text_scale_setting(self,col)
	var fishing:=CheckBox.new()
	fishing.text="標準釣魚 · 對準魚影"
	fishing.button_pressed=sound.standard_fishing
	fishing.tooltip_text="取消勾選可用輕鬆釣魚：咬鉤後按一次收竿，無倒數。"
	col.add_child(fishing)
	var save_button:=button("儲存設定並試聽",func():
		if not sound.save_preferences(settings_path,audio.volume.value/100.0,motion.button_pressed,zoom.get_selected_id(),null,fishing.button_pressed,text_scale.get_selected_id(),audio.music_volume.value/100.0,LifeShell.audio_levels(audio),camera.selected==1):_notice("設定保存失敗，原本設定仍保留。",false);return
		view.reduced_motion=sound.reduced_motion;view.zoom=float(sound.preferred_zoom)
		view.fixed_area_camera=sound.fixed_area_camera
		_apply_font_scale_tree()
		_notice("設定已儲存，下次啟動會沿用。",true)
		sound.play_cue("reward",true)
	)
	save_button.name="SaveComfort"
	col.add_child(save_button)
	col.add_child(label("提示音是短而柔和的合成音，連續操作不會疊加多個聲音。\n重要訊息也會顯示文字，靜音仍能完成遊戲。\n設定只保存在這台電腦；Z 可隨時切換近遠景。",16))

func _show_emote(actor:String,region:String,caption:String) -> void:
	if not mute_emotes and is_instance_valid(view) and view.region_id()==region:
		view.player_emotes[actor]={"region":region,"caption":caption,"until":Time.get_ticks_msec()+3000}

func _emote_menu() -> void:
	var aim:Vector2i=_controller_target() if controller_aim else view.to_cell(get_viewport().get_mouse_position())
	var content:=_open_modal("島民招呼")
	content.add_child(button("區域聊天",_chat_menu))
	var marker:=button("地圖標記",_map_signal_menu.bind(aim))
	marker.name="OpenMapSignals"
	content.add_child(marker)
	for id:String in session.EMOTES:
		content.add_child(button(session.EMOTES[id],func():session.perform("emote",Vector2i.ZERO,id);_close_modal()))
	content.add_child(button("顯示其他玩家的招呼" if mute_emotes else "隱藏玩家招呼",func():
		mute_emotes=not mute_emotes
		view.player_emotes.clear()
		_emote_menu()
	))

func _map_signal_menu(cell:Vector2i) -> void:
	var content:=_open_modal("給島民的地圖標記")
	content.add_child(label("標記瞄準的位置，同區域的島民可在周邊地圖查看 30 秒。",16))
	for kind:String in Session.MAP_SIGNALS:
		var choice:=button(Session.MAP_SIGNALS[kind],_send_map_signal.bind(cell,kind))
		choice.name="MapSignal_"+kind
		content.add_child(choice)
	var cancel:=button("取消我的標記",_send_map_signal.bind(cell,"cancel"))
	cancel.name="MapSignal_cancel"
	content.add_child(cancel)

func _send_map_signal(cell:Vector2i,kind:String) -> void:
	_close_modal()
	session.perform("map_signal",cell,kind)

func _receive_island_chat(region:String,sender:String,message:String) -> void:
	if mute_chat or str(session.snapshot.get("region_id","home"))!=region:return
	island_messages.append(sender+"  "+message)
	if island_messages.size()>24:island_messages.pop_front()
	if is_instance_valid(modal):
		var history:=modal.find_child("IslandChatHistory",true,false) as RichTextLabel
		if history!=null:
			history.text="\n".join(island_messages)

func _chat_menu() -> void:
	var content:=_open_modal("區域聊天")
	var history:=RichTextLabel.new()
	history.name="IslandChatHistory"
	history.custom_minimum_size.y=180
	history.scroll_following=true
	history.text="\n".join(island_messages)
	content.add_child(history)
	var field:=LineEdit.new()
	field.name="IslandChatInput"
	field.max_length=Session.CHAT_LENGTH
	field.placeholder_text="輸入訊息，按 Enter 送出"
	content.add_child(field)
	var submit:=func(raw:String):
		var message:=Session.chat_text(raw)
		if message.is_empty():return
		session.perform("island_chat",Vector2i.ZERO,message)
		field.clear()
	field.text_submitted.connect(submit)
	content.add_child(button("送出",func():submit.call(field.text)))
	content.add_child(button("顯示聊天" if mute_chat else "隱藏聊天",func():
		mute_chat=not mute_chat
		island_messages.clear()
		_chat_menu()
	))
	field.grab_focus()

func _trade_menu() -> void:
	preload("res://scripts/trade_ui.gd").open(self)

func _night_rest_menu() -> void:
	if not session.solo_rest_enabled:
		_night_vote_menu()
		return
	var body:=_open_modal("休息到清晨")
	if session.solo_rest_enabled and session.peers.size()==1:session.local_paused=true
	modal.set_meta("life_modal_layout","night_rest")
	var minute:=int(fposmod(float(session.snapshot.get("time",0.0)),World.WEATHER.DAY_SECONDS))
	body.add_child(label("現在 %02d:%02d  →  清晨 06:00"%[minute/60,minute%60],20))
	body.add_child(label("休息期間，農田與設備會照常運作。",16))
	var reason:String=session.solo_rest_reason()
	if not reason.is_empty():body.add_child(label(reason,16))
	var confirm:=button("休息到 06:00",func():
		_close_modal()
		session.perform("night_rest",Vector2i.ZERO)
	)
	confirm.name="NightRestConfirm"
	confirm.disabled=not reason.is_empty()
	body.add_child(confirm)
	_layout_preview.call_deferred()

func _night_vote_menu() -> void:
	var body:=_open_modal("休息到清晨")
	modal.set_meta("life_modal_layout","night_rest")
	modal.set_meta("night_vote_panel",true)
	var status:=label("",20)
	status.name="NightVoteStatus"
	body.add_child(status)
	body.add_child(label("所有在線島民都同意後，才會一起休息到 06:00。",16))
	var yes:=button("提出投票並同意",func():
		var number:=int(session.snapshot.get("night_vote",{}).get("id",0))
		_submit_night_vote("yes:%d"%number if number>0 else "open")
	)
	yes.name="NightVoteYes"
	body.add_child(yes)
	var no:=button("暫不休息",func():
		var number:=int(session.snapshot.get("night_vote",{}).get("id",0))
		if number>0:_submit_night_vote("no:%d"%number)
	)
	no.name="NightVoteNo"
	body.add_child(no)
	_refresh_night_vote(session.snapshot)
	_layout_preview.call_deferred()

func _submit_night_vote(choice:String) -> void:
	if not is_instance_valid(modal) or int(modal.get_meta("night_vote_pending",0))!=0:return
	modal.set_meta("night_vote_pending",session.counter+1)
	modal.set_meta("night_vote_cancelling",choice.begins_with("no:"))
	_refresh_night_vote(session.snapshot)
	if session.perform("night_vote",Vector2i.ZERO,choice)==0 and is_instance_valid(modal):
		modal.set_meta("night_vote_pending",0)
		_refresh_night_vote(session.snapshot)

func _refresh_night_vote(snapshot:Dictionary) -> void:
	if not is_instance_valid(modal) or not modal.has_meta("night_vote_panel"):return
	var status:=modal.find_child("NightVoteStatus",true,false) as Label
	var yes:=modal.find_child("NightVoteYes",true,false) as Button
	var no:=modal.find_child("NightVoteNo",true,false) as Button
	if status==null or yes==null or no==null:return
	var vote:Dictionary=snapshot.get("night_vote",{})
	var active:=int(vote.get("id",0))>0
	var voted:=bool(vote.get("mine",false))
	var waiting:=int(modal.get_meta("night_vote_pending",0))!=0
	var building_pending:=_blueprint_mode() in BLUEPRINT_SENT_MODES
	var minute:=int(fposmod(float(snapshot.get("time",0.0)),World.WEATHER.DAY_SECONDS))
	status.text="%d／%d 位同意 · 剩 %d 秒"%[vote.yes,vote.total,vote.seconds] if active else "午夜 00:00 後可提出投票"
	if not active and minute<World.REST_DAWN:status.text="目前 %02d:%02d · 可提出投票"%[minute/60,minute%60]
	yes.text="已同意，等其他島民" if voted else ("同意休息" if active else "提出投票並同意")
	if building_pending:status.text="請先確認藍圖施工結果，再同意休息。"
	yes.disabled=waiting or voted or building_pending or minute>=World.REST_DAWN
	no.visible=active
	no.disabled=waiting

func _rabbit_menu() -> void:
	LifeAlmanac.companion_menu(self)

func _cat_menu() -> void:
	LifeAlmanac.companion_menu(self,"cat")

func _dog_menu() -> void:
	LifeAlmanac.companion_menu(self,"dog")

func _fox_menu() -> void:
	LifeAlmanac.fox_menu(self)

func _pause_menu() -> void:
	session.local_paused=local_mode and session.world!=null and session.peers.size()==1 and session.peers.has(1)
	if session.local_paused:session.input_direction(Vector2.ZERO)
	if village_art_preview:LifeShell.pause(self);return
	var col:=_open_modal("島上生活選單")
	col.add_child(label("單機島已暫停，回到島上繼續。" if session.local_paused else "多人世界在有人在線時繼續運行。",17))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=400
	col.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",8)
	scroll.add_child(rows)
	rows.add_child(button("回到遊戲",_close_modal))
	if session.solo_rest_enabled or session.snapshot.has("night_vote"):rows.add_child(button("休息到清晨" if session.solo_rest_enabled else "夜間投票",_night_rest_menu))
	if village_art_preview:
		rows.add_child(button("選擇釣竿  {fish}",func():_close_modal();_select_tool("fish")))
	rows.add_child(button("選擇作物種子",_seed_menu))
	rows.add_child(button("查看小島地圖  {map}",_map_menu))
	rows.add_child(button("居民故事與下一步  {journal}",_journal))
	rows.add_child(button("生活圖鑑與里程碑  {collection}",_collection_menu))
	rows.add_child(button("渡口風鈴接力  {festival}",_festival_menu))
	var trade_button:=button("島民交換",_trade_menu)
	trade_button.name="PauseTrade"
	rows.add_child(trade_button)
	rows.add_child(button("島民招呼",_emote_menu))
	var comfort_button:=button("音效與舒適設定",_settings_menu)
	comfort_button.name="PauseComfort"
	rows.add_child(comfort_button)
	rows.add_child(button("鍵盤操作設定",_bindings_menu))
	if not island_passport.is_empty():rows.add_child(button("島嶼通行簿",_passport_menu))
	rows.add_child(button("卡住了，回到渡口",func():session.perform("rescue",Vector2i.ZERO);_close_modal()))
	rows.add_child(button("儲存並離開遊戲",_quit))
	col.add_child(label("目前為原型：直接跟隨鏡頭、預設無震動、無閃光。\n存檔位於此電腦的 Godot 使用者資料夾，並保留一份上一版備份。",15))

func _passport_menu() -> void:
	if island_passport.is_empty():return
	var column:=_open_modal("島嶼通行簿")
	modal.set_meta("island_passport",true)
	column.add_child(label(str(island_passport.get("world_name","封測島嶼")),23))
	var members:Array=island_passport.get("members",[])
	column.add_child(label("成員 %d／%d" % [members.size(),int(island_passport.get("capacity",4))],16))
	if session.snapshot.has("can_build_public_plot"):
		var plot_status:=label(_public_build_plot_status(session.snapshot),16)
		plot_status.name="PublicBuildPlotStatus"
		column.add_child(plot_status)
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=240
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var roster:=VBoxContainer.new()
	roster.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(roster)
	for member in members:
		var row:=PanelContainer.new()
		row.add_theme_stylebox_override("panel",LifeTheme.badge_style())
		roster.add_child(row)
		var details:=VBoxContainer.new()
		row.add_child(details)
		var role_labels:={"owner":"島主","admin":"管理員","member":"成員"}
		details.add_child(label("%s  ·  %s" % [member.get("name","島民"),role_labels.get(member.get("role"),"成員")],18))
		var activity:=int(member.get("last_activity",0))
		details.add_child(label("最後活動 %s（UTC）" % Time.get_datetime_string_from_unix_time(activity,true) if activity>0 else "尚無活動紀錄",14))
		var target_id:=str(member.get("management_id",""))
		if not target_id.is_empty():
			var actions:=HBoxContainer.new()
			details.add_child(actions)
			if island_passport.get("can_manage",false):
				var enable:bool=member.get("role")!="admin"
				actions.add_child(button("設為管理員" if enable else "收回管理權",func():session.request_admin_change(target_id,enable)))
			var display_name:=str(member.get("name","島民"))
			var blocked:bool=member.get("blocked",false)
			if not blocked:
				actions.add_child(button("請離島",func():_confirm_member_removal(target_id,display_name,false)))
			actions.add_child(button("解除封鎖" if blocked else "封鎖入島",func():
				if blocked:session.request_member_block(target_id,false)
				else:_confirm_member_removal(target_id,display_name,true)))
			if member.get("role")=="member":
				var grant:bool=not member.get("public_builder",false)
				details.add_child(button("授予渡口公共地塊施工權" if grant else "收回渡口公共地塊施工權",
					func():session.request_public_builder(target_id,grant)))
	if island_passport.get("can_manage",false):
		var invite_actions:=HBoxContainer.new()
		column.add_child(invite_actions)
		var rotate:=button("更新邀請（有效一小時）",func():session.request_invite_rotation())
		rotate.icon=LifeShell.icon("letter")
		invite_actions.add_child(rotate)
		var revoke:=button("撤銷目前邀請",func():session.request_invite_revocation())
		revoke.flat=true
		invite_actions.add_child(revoke)
		passport_code=LineEdit.new()
		passport_code.secret=true
		passport_code.editable=false
		passport_code.placeholder_text="更新後可查看邀請碼"
		column.add_child(passport_code)
		var reveal:=CheckButton.new()
		reveal.text="顯示邀請碼"
		reveal.toggled.connect(func(enabled:bool):passport_code.secret=not enabled)
		column.add_child(reveal)
		column.add_child(button("查看管理紀錄",_passport_management_history))
	passport_feedback=label("",16)
	column.add_child(passport_feedback)
	var back:=button("返回生活選單",_pause_menu)
	back.flat=true
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	column.add_child(back)

func _public_build_plot_status(snapshot:Dictionary) -> String:
	return "渡口北側公共地塊 · 可施工" if snapshot.get("can_build_public_plot",false) else "渡口北側公共地塊 · 向島主或管理員申請施工權"

func _passport_management_history() -> void:
	if not island_passport.get("can_manage",false):return
	var column:=_open_modal("島嶼管理紀錄")
	var history:Array=island_passport.get("management_history",[])
	if history.is_empty():column.add_child(label("目前沒有管理紀錄。",17))
	var scroll:=ScrollContainer.new()
	scroll.custom_minimum_size.y=290
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows:=VBoxContainer.new()
	rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var titles:={"invite_rotate":"更新邀請","invite_revoke":"撤銷邀請","admin_grant":"指派管理員",
		"admin_revoke":"收回管理權","block":"封鎖入島","unblock":"解除封鎖","kick":"請離島",
		"public_build_grant":"授予公共地塊施工權","public_build_revoke":"收回公共地塊施工權"}
	for index in range(history.size()-1,-1,-1):
		var event:Dictionary=history[index]
		var action:String=titles.get(event.get("action"),"")
		if action.is_empty():continue
		var target:=str(event.get("target",""))
		if not target.is_empty():action+=" · "+target
		rows.add_child(label(action,18))
		var date:=Time.get_datetime_string_from_unix_time(int(event.at),true)
		rows.add_child(label("%s · %s UTC" % [event.actor,date],14))
		rows.add_child(HSeparator.new())
	column.add_child(button("返回通行簿",_passport_menu))

func _confirm_member_removal(target_id:String,display_name:String,block:bool) -> void:
	var dialog:=ConfirmationDialog.new()
	dialog.title="封鎖入島" if block else "請離島"
	dialog.dialog_text=("封鎖 %s 進入這座島？對方將離開目前連線，直到解除封鎖才可再入島。" if block else "請 %s 中斷本次連線？對方仍可重新加入。") % display_name
	dialog.confirmed.connect(func():
		if block:session.request_member_block(target_id,true)
		else:session.request_member_kick(target_id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	modal.add_child(dialog)
	dialog.popup_centered()

func _exit_tree()->void:
	# Blueprint nodes first: unhook Session signals and drop the overlay/strip
	# (which reference shared village art and item icons) before the texture
	# caches below are cleared. dispose() never deletes a pending record.
	if is_instance_valid(blueprints):blueprints.dispose()
	if is_instance_valid(blueprint_strip):blueprint_strip.free()
	blueprint_strip=null
	if is_instance_valid(blueprint_overlay):
		blueprint_overlay.controller=null
		blueprint_overlay.source_view=null
		blueprint_overlay.free()
	blueprint_overlay=null
	if is_instance_valid(blueprints):blueprints.free()
	blueprints=null
	# These are disposable texture caches, not game state. Release them while
	# the renderer is alive; another view can lazily rebuild them if needed.
	View.TeaArt.clear_cache()
	View.TeaResidents.clear_cache()
	View.FurnitureArt.clear_cache()
	if get_tree() and get_tree().root.has_meta(BuildThumbnail.CACHE_KEY):
		get_tree().root.remove_meta(BuildThumbnail.CACHE_KEY)

func _notification(what:int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:_quit()
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:gather_hold.clear()

func _quit() -> void:
	if session and not session.shutdown():
		if hud:
			var col:=_open_modal("最後一次保存沒有成功")
			col.add_child(label("可以檢查儲存空間後重試。若直接離開，會使用上次已保存的進度。",18))
			col.add_child(button("重試保存並離開",_quit))
			col.add_child(button("離開並保留上次存檔",func():get_tree().quit()))
		return
	if sound:
		sound.close()
		await get_tree().create_timer(0.15).timeout
	get_tree().quit()
