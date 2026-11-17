extends SceneTree

const Bindings = preload("res://scripts/input_bindings.gd")
var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

# Real Godot 4.7.2 Windows event observed by root for the "5" key: the logical
# keycode is KEY_5 but physical_keycode is 4194313 (KEY_PAUSE).
const NATIVE_FIVE_PHYSICAL := 4194313

func native_key(keycode: int, physical: int, is_pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical
	event.pressed = is_pressed
	return event

func matching_actions(bindings, event: InputEventKey) -> Array:
	var found: Array = []
	for action in bindings.keys:
		if bindings.matches(action, event):
			found.append(action)
	return found

func native_layout_checks(bindings) -> void:
	expect(NATIVE_FIVE_PHYSICAL == KEY_PAUSE and KEY_5 == 53, "fixture mirrors the observed native event codes")
	var five := native_key(KEY_5, NATIVE_FIVE_PHYSICAL)
	expect(Bindings.event_key(five) == KEY_5, "native 5 resolves to its logical keycode")
	expect(matching_actions(bindings, five) == ["axe"], "native 5 selects only the axe")
	# Every default fires from its logical code whatever the physical code says, and only once.
	for action in Bindings.DEFAULTS:
		var event := native_key(Bindings.DEFAULTS[action], NATIVE_FIVE_PHYSICAL)
		if action == "area_modifier":
			event.shift_pressed = true
		expect(matching_actions(bindings, event) == [action], "default %s fires exactly once from a native event" % action)
	for digit in range(8):
		var tool_action: String = ["hoe", "seed", "water", "harvest", "axe", "pick", "build", "remove"][digit]
		expect(matching_actions(bindings, native_key(KEY_1 + digit, KEY_NONE)) == [tool_action],
			"number key %d selects %s" % [digit + 1, tool_action])
	# Layout disagreement (AZERTY: the key labelled Z sits at QWERTY W): no dual trigger.
	var azerty_z := native_key(KEY_Z, KEY_W)
	expect(matching_actions(bindings, azerty_z) == ["zoom"], "labelled Z fires zoom only, never move_up via its physical W")
	var azerty_w := native_key(KEY_W, KEY_Z)
	expect(matching_actions(bindings, azerty_w) == ["move_up"], "labelled W fires move_up only")
	expect(matching_actions(bindings, native_key(KEY_5, NATIVE_FIVE_PHYSICAL, false)).is_empty(), "native 5 release fires nothing")
	var echo := native_key(KEY_5, NATIVE_FIVE_PHYSICAL)
	echo.echo = true
	expect(matching_actions(bindings, echo).is_empty(), "native 5 key repeat fires nothing")
	# Held fallback bookkeeping follows the same rule (Input state is exercised in test_input_routing).
	bindings.observe(native_key(KEY_NONE, KEY_D))
	expect(bindings._fallback_held.has(KEY_D), "physical-only press is tracked for held polling")
	bindings.observe(native_key(KEY_NONE, KEY_D, false))
	expect(not bindings._fallback_held.has(KEY_D), "release clears the physical-only hold")
	bindings.observe(native_key(KEY_W, KEY_D))
	expect(not bindings._fallback_held.has(KEY_D), "a press with a logical code never registers its physical code")

func _initialize() -> void:
	var bindings := Bindings.new()
	var path := "user://bindings-test-%d.cfg" % Time.get_ticks_usec()
	expect(not bindings.load_preferences(path) and bindings.keys == Bindings.DEFAULTS, "first launch uses defaults")
	var unique := {}
	var grouped: Array = []
	for group in Bindings.GROUPS.values():
		grouped.append_array(group)
	for action in Bindings.DEFAULTS:
		var key: int = Bindings.DEFAULTS[action]
		expect(Bindings.allowed(action, key) and not unique.has(key) and grouped.count(action) == 1
			and Bindings.LABELS.has(action), action + " has a valid unique default, name and category")
		unique[key] = true
	native_layout_checks(bindings)
	expect(bindings.keys.inventory == KEY_TAB and bindings.keys.area_modifier == KEY_SHIFT, "inventory and drag defaults retained")
	expect(not bindings.rebind("inventory", KEY_ESCAPE).ok and not bindings.rebind("interact", KEY_ENTER).ok,
		"safety and GUI keys cannot be reassigned")
	expect(not bindings.rebind("interact", KEY_UP).ok and bindings.rebind("move_up", KEY_UP).ok,
		"arrow keys may be used for movement only")
	expect(not bindings.rebind("area_modifier", KEY_Q).ok and not bindings.rebind("interact", KEY_CTRL).ok
		and bindings.rebind("area_modifier", KEY_CTRL).ok, "only the drag action takes bare modifiers")

	var conflict: Dictionary = bindings.rebind("interact", KEY_TAB)
	expect(not conflict.ok and conflict.conflict == "inventory" and bindings.keys.interact == KEY_E,
		"conflict leaves both bindings unchanged until transfer")
	expect(bindings.rebind("interact", KEY_TAB, true).ok and bindings.keys.inventory == KEY_NONE,
		"transfer clears the old action")
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = KEY_E
	expect(not bindings.matches("interact", event), "old binding no longer fires")
	event.keycode = KEY_E
	event.physical_keycode = KEY_TAB
	expect(not bindings.matches("interact", event), "a disagreeing physical code never fires the binding")
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_E
	expect(bindings.matches("interact", event), "the logical keycode (the label the UI shows) fires the rebound action")
	event.physical_keycode = KEY_NONE
	expect(bindings.matches("interact", event), "virtual keyboard without physical keycode uses keycode")
	event.keycode = KEY_NONE
	event.physical_keycode = KEY_TAB
	expect(bindings.matches("interact", event), "event without logical keycode falls back to physical keycode")
	event.keycode = KEY_UNKNOWN
	expect(bindings.matches("interact", event), "unknown logical keycode (IME) falls back to physical keycode")
	event.keycode = KEY_TAB
	event.physical_keycode = KEY_E
	event.echo = true
	expect(not bindings.matches("interact", event), "repeat does not fire a discrete action")
	event.echo = false
	event.ctrl_pressed = true
	expect(not bindings.matches("interact", event), "Ctrl chord is isolated from gameplay")
	event.ctrl_pressed = false
	event.shift_pressed = true
	expect(bindings.matches("interact", event), "Shift does not block gameplay's single physical key")
	event.pressed = false
	expect(not bindings.matches("interact", event), "release does not fire")
	expect(bindings.clear("move_left").ok and bindings.label("move_left") == "未設定", "movement key can be cleared")
	var restored := Bindings.new()
	expect(restored.load_preferences(path) and restored.keys == bindings.keys, "saved preferences replace an existing file and survive reload")
	expect(restored.restore_defaults().ok and bindings.load_preferences(path) and bindings.keys == Bindings.DEFAULTS,
		"restoring defaults is persistent")
	# Version-1 files from the earlier physical-capture panel keep their values (no migration);
	# each stored code now means the key carrying that label, as the settings UI always showed.
	var legacy := ConfigFile.new()
	var legacy_keys: Dictionary = Bindings.DEFAULTS.duplicate()
	legacy_keys.erase("social")
	legacy_keys.move_up = KEY_UP
	legacy_keys.interact = KEY_Q
	legacy.set_value("input", "version", 1)
	legacy.set_value("input", "keys", legacy_keys)
	var migrated := legacy_keys.duplicate()
	migrated.social = KEY_NONE
	expect(legacy.save(path) == OK and restored.load_preferences(path) and restored.keys == migrated
		and restored.label("interact") == "Q", "existing version-1 bindings reload unchanged with their labels")
	expect(matching_actions(restored, native_key(KEY_Q, NATIVE_FIVE_PHYSICAL)) == ["interact"]
		and matching_actions(restored, native_key(KEY_E, KEY_Q)).is_empty(), "reloaded binding fires from its labelled key only")
	var native_conflict: Dictionary = restored.rebind("journal", Bindings.event_key(native_key(KEY_Q, NATIVE_FIVE_PHYSICAL)))
	expect(not native_conflict.ok and native_conflict.get("conflict", "") == "interact" and restored.keys.journal == KEY_J,
		"conflict detection uses the native event identity")
	expect(restored.rebind("journal", KEY_5).get("conflict", "") == "axe", "number key conflicts with its default tool")

	var config := ConfigFile.new()
	config.set_value("input", "version", Bindings.VERSION)
	var malformed: Dictionary = Bindings.DEFAULTS.duplicate()
	malformed.interact = KEY_TAB
	config.set_value("input", "keys", malformed)
	expect(config.save(path) == OK and not restored.load_preferences(path) and restored.keys == Bindings.DEFAULTS,
		"duplicate keys on disk fall back to defaults")
	malformed.interact = KEY_ESCAPE
	config.set_value("input", "keys", malformed)
	expect(config.save(path) == OK and not restored.load_preferences(path) and restored.keys == Bindings.DEFAULTS,
		"reserved key on disk falls back to defaults")
	config.set_value("input", "version", 2)
	config.set_value("input", "keys", Bindings.DEFAULTS)
	expect(config.save(path) == OK and not restored.load_preferences(path), "unknown config version is rejected")
	restored.path = "user://missing-bindings-dir-%d/keys.cfg" % Time.get_ticks_usec()
	expect(not restored.rebind("interact", KEY_Q).ok and restored.keys.interact == KEY_E, "failed save keeps live keys")
	DirAccess.remove_absolute(path)
	print("INPUT_BINDINGS_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
