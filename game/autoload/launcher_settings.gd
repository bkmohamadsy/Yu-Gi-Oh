extends Node

const ASPECTS: = ["stretch", "original", "overlay"]
const FRAME_RATES: = [30, 60, 0]
var aspect: = "stretch"
var frame_rate: = 0
var simulation_speed: = 1.0
var fast_play: = false
var improved_card_texts: = false
var v2_defaults_migrated: = false
var _refresh_clock: = 0.0

func _ready() -> void :
	reload_preferences()
	apply_timing()

func reload_preferences() -> void :
	var config: = ConfigFile.new()
	config.load(Paths.settings_path())
	v2_defaults_migrated = bool(config.get_value("launcher", "v2_defaults_migrated", false))
	if not v2_defaults_migrated:
		apply_v2_defaults_migration(config)
		return
	var loaded_aspect: = str(config.get_value("launcher", "aspect", "stretch")).strip_edges().to_lower()
	if loaded_aspect == "stretched":
		loaded_aspect = "stretch"
	aspect = loaded_aspect if loaded_aspect in ASPECTS else "stretch"
	frame_rate = int(config.get_value("launcher", "fps", 0))
	if frame_rate not in FRAME_RATES: frame_rate = 0
	simulation_speed = float(config.get_value("launcher", "simulation_speed", 1.0))
	if simulation_speed not in [1.0, 2.0]: simulation_speed = 1.0
	fast_play = bool(config.get_value("launcher", "fast_play", false))
	improved_card_texts = bool(config.get_value("launcher", "improved_card_texts", false))

static func _save_config_atomic(config: ConfigFile, target_path: String) -> Error:
	if target_path.is_empty():
		return ERR_INVALID_PARAMETER
	var parent_dir: = target_path.get_base_dir()
	if not parent_dir.is_empty():
		var dir_err: = DirAccess.make_dir_recursive_absolute(parent_dir)
		if dir_err != OK:
			return dir_err
	var tmp_path: = target_path + ".prefs.tmp"
	var err: = config.save(tmp_path)
	if err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return err
	err = DirAccess.rename_absolute(tmp_path, target_path)
	if err != OK:
		if FileAccess.file_exists(tmp_path):
			DirAccess.remove_absolute(tmp_path)
		return config.save(target_path)
	return OK


func apply_v2_defaults_migration(config: ConfigFile = null, settings_file: String = "") -> bool:
	var target_path: = settings_file if not settings_file.is_empty() else Paths.settings_path()
	if config == null:
		config = ConfigFile.new()
		config.load(target_path)
	if bool(config.get_value("launcher", "v2_defaults_migrated", false)):
		v2_defaults_migrated = true
		return false
	aspect = "stretch"
	v2_defaults_migrated = true
	frame_rate = int(config.get_value("launcher", "fps", 0))
	if frame_rate not in FRAME_RATES: frame_rate = 0
	simulation_speed = float(config.get_value("launcher", "simulation_speed", 1.0))
	if simulation_speed not in [1.0, 2.0]: simulation_speed = 1.0
	fast_play = bool(config.get_value("launcher", "fast_play", false))
	improved_card_texts = bool(config.get_value("launcher", "improved_card_texts", false))
	config.set_value("launcher", "aspect", "stretch")
	config.set_value("launcher", "v2_defaults_migrated", true)
	config.set_value("preferences", "language", "a")
	if not Paths.storage_error or not settings_file.is_empty():
		var error: = _save_config_atomic(config, target_path)
		if error != OK:
			push_error("No se pudieron guardar los ajustes: " + error_string(error))
	if settings_file.is_empty():
		var assets_node: = get_node_or_null("/root/Assets")
		if assets_node != null:
			if not assets_node.set_language("a"):
				assets_node.set("lang", "a")
		var save_node: = get_node_or_null("/root/SaveData")
		if Paths.has_data() and not Paths.storage_error and save_node != null and save_node.get("data") is Dictionary and str(save_node.get("persistence_error")) == "":
			save_node.data.get_or_add("settings", {})["language"] = "a"
			save_node.save()
		var bridge: = get_node_or_null("/root/LocalizationBridge")
		if bridge != null:
			bridge.reload_localization()
	return true

func save_preferences() -> void :
	var config: = ConfigFile.new()
	config.load(Paths.settings_path())
	config.set_value("launcher", "aspect", aspect)
	config.set_value("launcher", "fps", frame_rate)
	config.set_value("launcher", "simulation_speed", simulation_speed)
	config.set_value("launcher", "fast_play", fast_play)
	config.set_value("launcher", "improved_card_texts", improved_card_texts)
	config.set_value("launcher", "v2_defaults_migrated", true)
	v2_defaults_migrated = true
	var error: = _save_config_atomic(config, Paths.settings_path())
	if error != OK: push_error("No se pudieron guardar los ajustes: " + error_string(error))
	apply_timing()

func gameplay_aspect() -> int:
	return Window.CONTENT_SCALE_ASPECT_IGNORE if aspect == "stretch" else Window.CONTENT_SCALE_ASPECT_KEEP

func display_fps() -> int:
	if DisplayServer.get_name() == "headless": return 60
	var rate: = DisplayServer.screen_get_refresh_rate(get_window().current_screen)
	return roundi(rate) if rate > 0.0 else 60




func monitor_fps_cap() -> int:
	return 0 if OS.has_feature("mobile") else display_fps()




var _cmdline_max_fps: = Engine.max_fps

func _cmdline_timing() -> bool:
	return _cmdline_max_fps > 0

func apply_timing() -> void :
	if _cmdline_timing(): return
	Engine.max_fps = monitor_fps_cap() if frame_rate == 0 else frame_rate
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if frame_rate == 0 else DisplayServer.VSYNC_DISABLED)

func _process(delta: float) -> void :

	_refresh_clock += delta
	if _refresh_clock >= 1.0:
		_refresh_clock = 0.0
		if frame_rate == 0 and not _cmdline_timing(): Engine.max_fps = monitor_fps_cap()
