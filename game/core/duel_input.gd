extends RefCounted

const DEFAULTS: = [[KEY_ESCAPE], [KEY_UP, KEY_KP_8], [KEY_DOWN, KEY_KP_2], [KEY_LEFT, KEY_KP_4], [KEY_RIGHT, KEY_KP_6], 
	[KEY_SPACE], [KEY_ENTER, KEY_KP_ENTER], [KEY_F1], [KEY_F2], [KEY_F3], [KEY_F4], 
	[KEY_HOME, KEY_TAB], [KEY_ESCAPE, KEY_INSERT]]
const BITS: = [2, 64, 128, 32, 16, 8, 1, 65536, 131072, 262144, 
	524288, 1024, 256]

const JOEY_DEFAULTS: = [[KEY_ESCAPE], [KEY_UP, KEY_KP_8], [KEY_DOWN, KEY_KP_2], [KEY_LEFT, KEY_KP_4], [KEY_RIGHT, KEY_KP_6], 
	[KEY_SPACE], [KEY_ENTER, KEY_KP_ENTER], [KEY_F1], [KEY_F2], [KEY_F3], [KEY_F4], 
	[KEY_F5], [KEY_F6], [KEY_F7], [KEY_F8], [KEY_F9], [KEY_F10], [KEY_F11], [KEY_F12], 
	[KEY_HOME, KEY_TAB], [KEY_ESCAPE, KEY_INSERT]]

static func cancel_slot(game: String) -> int:
	return 20 if game == "joey" else 12

static func options(game: String = "") -> Dictionary:
	var tree: = Engine.get_main_loop() as SceneTree
	if game == "": game = str(tree.root.get_node("Game").current_game)
	if game == "": game = "yugi"
	return tree.root.get_node("SaveData").data.get("options", {}).get(game, {})

static func pointer_motion(game: String = "") -> bool:
	return bool(options(game).get("pointer_motion", true))

static func slots(event: InputEventKey, game: String) -> int:
	var key: = event.keycode if event.keycode != 0 else event.physical_keycode
	var bindings: Dictionary = options(game).get("keys", {})
	var defaults: Array = JOEY_DEFAULTS if game == "joey" else DEFAULTS
	var found: = 0
	for slot in defaults.size():
		var keys: Array = bindings.get(str(slot), defaults[slot])
		for code in keys:
			if int(code) == key:
				found |= 1 << slot
				break
	return found

static func bits(event: InputEventKey, game: String) -> int:
	var groups: = slots(event, game)
	var result: = 0
	for slot in (JOEY_DEFAULTS.size() if game == "joey" else DEFAULTS.size()):
		var bit: int = BITS[slot] if game != "joey" or slot < 7 else (65536 << (slot - 7) if slot < 19 else 1024 if slot == 19 else 256)
		if groups & (1 << slot): result |= bit
	return result
