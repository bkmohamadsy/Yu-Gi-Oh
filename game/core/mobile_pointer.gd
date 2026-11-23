extends CanvasLayer



var _menu: = PanelContainer.new()
var _bar_box: = HBoxContainer.new()
var _left: = Button.new()
var _right: = Button.new()
var _cancel_btn: = Button.new()
var _response_cancel_panel: = PanelContainer.new()
var _response_cancel_btn: = Button.new()
var _target: = Vector2.ZERO
var _finger: = -1
var _active_fingers: Dictionary = {}
var _previous_emulation: = true
var _pressed_button: = MOUSE_BUTTON_NONE
var _dispatching: = false
var _hold_time: = 0.0
var _holding: = false
var _start: = Vector2.ZERO
var _generation: = 0
var _actions: Array[int] = []
var _choices: Array[Button] = []
var _button_actions: Array[int] = []
var _right_available: = false
var _preparing: = false
var _pending_release: = false
var _confirm_scene: Node
var _confirm_until: = 0
var _tribute_hint: = Label.new()
var _deck_touch: = false
var _drag_starting: = false
var _pending_drop: = false
var _selected_card: = ""
var _touch_card: = ""
var _scroll_axis: = ""
var _scroll_kind: = ""
var _scroll_node: Node
var _scrolling: = false
var _scroll_last: = Vector2.ZERO
var _scroll_amount: = 0.0


var _hand_touch_active: = false
var _hand_scrub_active: = false
var _hand_swipe_triggered: = false
var _hand_start_point: = Vector2.ZERO
var _hand_start_scene_pos: = Vector2.ZERO
var _bar_card_identity: = ""

const HOLD_SECONDS: = 0.5
const SCRUB_THRESHOLD_PX: = 10.0
const SWIPE_UP_MIN_DY: = 34.0
const SWIPE_DIAGONAL_RATIO: = 0.45

const ACTION_NAMES: = {
	1: "Summon", 
	2: "Change Position", 
	3: "Attack", 
	4: "Activate", 
	5: "Set", 
	6: "Change Position", 
	7: "Change Position", 
	8: "Draw", 
	9: "Surrender", 
	10: "Fusion", 
	11: "Special Summon (ATK)", 
	12: "Special Summon (DEF)", 
}

const ACTION_KEYS: = {
	1: ["action_summon", "استدعاء", "Summon"], 
	2: ["action_change_position", "تغيير الوضعية", "Change Position"], 
	3: ["action_attack", "هجوم", "Attack"], 
	4: ["action_activate", "تفعيل", "Activate"], 
	5: ["action_set", "وضع مقلوب", "Set"], 
	6: ["action_change_position", "تغيير الوضعية", "Change Position"], 
	7: ["action_change_position", "تغيير الوضعية", "Change Position"], 
	8: ["action_draw", "سحب", "Draw"], 
	9: ["action_surrender", "انسحاب", "Surrender"], 
	10: ["action_fusion", "دمج", "Fusion"], 
	11: ["action_special_atk", "استدعاء خاص", "Special Summon"], 
	12: ["action_special_def", "استدعاء خاص (دفاع)", "Special Summon (DEF)"], 
}


func _bridge() -> Node:
	return get_node_or_null("/root/LocalizationBridge")


func _is_arabic() -> bool:
	var bridge: = _bridge()
	return bridge != null and bridge.is_arabic()


func _tr_ui(key: String, ar_default: String, fallback: String) -> String:
	var bridge: = _bridge()
	if bridge == null:
		return fallback
	return bridge.tr_ui(key, ar_default if bridge.is_arabic() else fallback)


func _action_label_text(action_id: int) -> String:
	if ACTION_KEYS.has(action_id):
		var spec: Array = ACTION_KEYS[action_id]
		return _tr_ui(spec[0], spec[1], spec[2])
	return _tr_ui("action_choose", "اختيار", ACTION_NAMES.get(action_id, "Choose"))


func _scene_point(point: Vector2) -> Vector2:
	if not is_instance_valid(Game._screen):
		return point
	if is_instance_valid(Game._screen_host) and Game._screen_host.has_method("duel_transform"):
		var duel_xf: Transform2D = Game._screen_host.duel_transform()
		return duel_xf.affine_inverse() * _physical(point)
	return Game._screen.get_viewport().get_screen_transform().affine_inverse() * _physical(point)


func is_hand_scrub_active() -> bool:
	return _hand_scrub_active


func is_action_bar_visible() -> bool:
	return _menu.visible


func has_active_popup_or_bar() -> bool:
	return _menu.visible or _hand_scrub_active


func action_bar_buttons() -> Array[String]:
	var out: Array[String] = []
	if not _menu.visible:
		return out
	for btn in _choices:
		if btn.visible:
			out.append(btn.text)
	if _cancel_btn.visible:
		out.append(_cancel_btn.text)
	return out





func strict_state_guard(scene: Node = Game._screen) -> bool:
	if not is_instance_valid(scene) or not PlatformInput._normal_duel_active():
		return false
	if bool(scene.get("_finished")) or scene.get("_result") != null:
		return false
	var d = scene.get("_duel")
	if d == null:
		return false
	var guard: = get_node_or_null("/root/BackNavigationGuard")
	if guard != null and guard.has_method("is_modal_open") and guard.is_modal_open():
		return false
	if not scene._waiting_for_player():
		return false
	var turn: int = d.m.u16(10564594)
	if (turn & 1) != 0:
		return false
	var phase: int = (turn >> 1) & 7
	if phase not in [2, 3, 4]:
		return false
	if not d.dialog_open.is_empty() or is_instance_valid(scene.get("_dialog_box")):
		return false
	if not d.list_open.is_empty() or is_instance_valid(scene.get("_list_window")):
		return false
	if not d.ui_pending.is_empty():
		return false
	if _target_selection(scene) or _response_cancel_active(scene):
		return false
	var visual = scene.get("_visual")
	if visual != null:
		if visual.busy() or bool(visual.get("_start_banner_shade")):
			return false
		if not visual.active.is_empty() or not visual.pending.is_empty():
			return false
	return true


func _hide_action_bar() -> void :
	if _menu.visible:
		_menu.hide()
	_bar_card_identity = ""


func _has_right_action(point: Vector2) -> bool:
	var scene: Node = Game._screen
	if not is_instance_valid(scene): return false
	var script_path: String = scene.get_script().resource_path
	var local: = _scene_point(point)
	if PlatformInput._normal_duel_active():
		if not strict_state_guard(scene):
			return false
		var hit: Dictionary = scene._hit_card(local)
		return not hit.is_empty() and int(hit.get("p", -1)) == 0 and int(hit.get("loc", -1)) in [0, 5, 11]
	if script_path.ends_with("deck_editor.gd"):
		return scene._modal == null and (scene._button_at(local) == "filter_label" or not scene._hit_at(local).is_empty())
	return false


const NATIVE_TOUCH_SCREENS: = [
	"launcher_android.gd", 
	"launcher.gd", 
	"android_content_setup.gd", 
	"content_setup.gd", 
	"AutoPckBootstrapper.gd", 
	"boot.gd", 
]


func _use_native_touch() -> bool:
	var guard: = get_node_or_null("/root/BackNavigationGuard")
	if guard != null and guard.has_method("is_modal_open") and guard.is_modal_open():
		return true
	if is_inside_tree() and get_tree() != null and get_tree().root != null:
		for win in get_tree().root.get_embedded_subwindows():
			if is_instance_valid(win) and win.visible:
				return true
	var scene: Node = Game._screen
	if not is_instance_valid(scene):
		return true
	var script: Script = scene.get_script()
	if script == null:
		return true
	return script.resource_path.get_file() in NATIVE_TOUCH_SCREENS


func _sync_touch_emulation() -> bool:
	var want_native: = _use_native_touch()
	if want_native:
		if not Input.emulate_mouse_from_touch:
			if _finger != -1 or _pressed_button != MOUSE_BUTTON_NONE or _menu.visible or _hand_touch_active:
				cancel()
			Input.emulate_mouse_from_touch = true
	elif Input.emulate_mouse_from_touch and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		Input.emulate_mouse_from_touch = false
	return Input.emulate_mouse_from_touch


func _mode() -> String:
	return str(SaveData.data.get("launcher", {}).get("pointer_mode", "menu"))


func _process(delta: float) -> void :
	if _sync_touch_emulation():
		return
	if _menu.visible and PlatformInput._normal_duel_active():
		if not strict_state_guard(Game._screen) or _hand_scrub_active:
			_hide_action_bar()
		elif _bar_card_identity != "":
			var cur: = _card_identity(_target)
			if cur != _bar_card_identity and _bar_card_identity.begins_with("duel:"):

				var parts: = _bar_card_identity.split(":")
				if parts.size() >= 4 and Game._screen._duel != null:
					var p: = int(parts[1])
					var loc: = int(parts[2])
					var idx: = int(parts[3])
					var card_at: = int(Game._screen._duel.m.u16(Game._screen._duel.f5419b0(p, loc, idx)) & 4095)
					if card_at == 0:
						_hide_action_bar()
	if is_instance_valid(_confirm_scene) and Game._screen == _confirm_scene and Time.get_ticks_msec() < _confirm_until:
		var question: Dictionary = _confirm_scene._duel.dialog_open

		if _pressed_button == MOUSE_BUTTON_NONE and not _dispatching and is_instance_valid(_confirm_scene._dialog_box) and not question.get("closing", false) and int(question.get("type", -1)) == 1 and int(question.get("msg", -1)) in [1, 2]:
			_confirm_scene._answer_dialog(1)
			_confirm_scene = null
	_update_tribute_hint()
	_update_response_cancel_button()
	if not _holding or _pressed_button != MOUSE_BUTTON_NONE or _scrolling or (_scroll_kind != "" and _scroll_kind != "bag"): return
	if _hand_touch_active or _hand_scrub_active: return
	if _touch_card == "" and _deck_touch and _mode() == "menu": return

	_hold_time += delta / maxf(Engine.time_scale, 0.001)
	if _hold_time >= HOLD_SECONDS:
		_holding = false
		if _touch_card != "" and _selected_card != _touch_card:
			_finish_card_tap(_target)
		elif _touch_card.begins_with("duel:") and _actions.has(5):
			_execute_action.call_deferred(5, _target)
		else: _dispatch_click.call_deferred(MOUSE_BUTTON_RIGHT, _target)


func _style_action_bar() -> void :
	var panel_style: = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.045, 0.075, 0.94)
	panel_style.border_color = Color(1.0, 0.82, 0.3, 0.92)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel_style.shadow_color = Color(0, 0, 0, 0.65)
	panel_style.shadow_size = 10
	_menu.add_theme_stylebox_override("panel", panel_style)


func _style_action_button(btn: Button, is_cancel: bool = false) -> void :
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(76, 36)
	btn.add_theme_font_size_override("font_size", 14)
	var fg: = Color(1.0, 0.88, 0.86) if is_cancel else Color(1.0, 0.95, 0.72)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	for state in ["normal", "hover", "pressed"]:
		var st: = StyleBoxFlat.new()
		if is_cancel:
			st.bg_color = Color(0.28, 0.08, 0.08, 0.95) if state != "normal" else Color(0.18, 0.05, 0.05, 0.92)
			st.border_color = Color(0.95, 0.45, 0.4, 0.85)
		else:
			st.bg_color = Color(0.18, 0.13, 0.06, 0.98) if state != "normal" else Color(0.11, 0.085, 0.05, 0.95)
			st.border_color = Color(1.0, 0.82, 0.3, 0.95) if state != "normal" else Color(0.85, 0.66, 0.22, 0.78)
		st.set_border_width_all(1)
		st.set_corner_radius_all(7)
		st.content_margin_left = 10
		st.content_margin_right = 10
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		btn.add_theme_stylebox_override(state, st)
	var bridge: = _bridge()
	if bridge != null:
		bridge.apply_rtl_control(btn, _is_arabic())


func _ready() -> void :
	layer = 100
	_tribute_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tribute_hint.add_theme_color_override("font_color", Color.YELLOW)
	_tribute_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_tribute_hint.add_theme_constant_override("shadow_offset_x", 2)
	_tribute_hint.add_theme_constant_override("shadow_offset_y", 2)
	_tribute_hint.add_theme_font_size_override("font_size", 20)
	_tribute_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tribute_hint.hide()
	add_child(_tribute_hint)
	_previous_emulation = Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = _use_native_touch()
	_style_action_bar()
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	add_child(_menu)
	_bar_box.add_theme_constant_override("separation", 6)
	_bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(_bar_box)
	_choices.assign([_left, _right])
	for button in _choices:
		_style_action_button(button, false)
		_bar_box.add_child(button)
	_style_action_button(_cancel_btn, true)
	_bar_box.add_child(_cancel_btn)
	var cancel_panel_style: = StyleBoxFlat.new()
	cancel_panel_style.bg_color = Color(0.14, 0.04, 0.05, 0.94)
	cancel_panel_style.border_color = Color(0.95, 0.45, 0.4, 0.92)
	cancel_panel_style.set_border_width_all(2)
	cancel_panel_style.set_corner_radius_all(10)
	cancel_panel_style.content_margin_left = 4
	cancel_panel_style.content_margin_right = 4
	cancel_panel_style.content_margin_top = 4
	cancel_panel_style.content_margin_bottom = 4
	cancel_panel_style.shadow_color = Color(0, 0, 0, 0.65)
	cancel_panel_style.shadow_size = 8
	_response_cancel_panel.add_theme_stylebox_override("panel", cancel_panel_style)
	_response_cancel_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_response_cancel_panel.visible = false
	_style_action_button(_response_cancel_btn, true)
	_response_cancel_btn.custom_minimum_size = Vector2(118, 40)
	_response_cancel_panel.add_child(_response_cancel_btn)
	add_child(_response_cancel_panel)


func _exit_tree() -> void :
	Input.emulate_mouse_from_touch = _previous_emulation
	_release()


func cancel() -> void :
	_hide_action_bar()
	_tribute_hint.hide()
	_response_cancel_panel.hide()
	_selected_card = ""
	_touch_card = ""
	_scroll_kind = ""
	_scrolling = false
	_confirm_scene = null
	_finger = -1
	_active_fingers.clear()
	_holding = false
	_preparing = false
	_drag_starting = false
	_hand_touch_active = false
	if _hand_scrub_active and is_instance_valid(Game._screen) and Game._screen.has_method("set_hand_scrub_active"):
		Game._screen.set_hand_scrub_active(false)
	_hand_scrub_active = false
	_hand_swipe_triggered = false
	_generation += 1
	_release()
	if is_inside_tree():
		_sync_touch_emulation.call_deferred()


func _input(event: InputEvent) -> void :
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _sync_touch_emulation():
			return
		get_viewport().set_input_as_handled()
		handle_touch_event(event)
	elif event is InputEventMouseButton and _menu.visible:
		get_viewport().set_input_as_handled()
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_choose(event.position)
	elif event is InputEventMouseButton and _response_cancel_panel.visible and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _response_cancel_panel.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			_trigger_response_right_click_cancel()


func handle_touch_event(event: InputEvent) -> void :
	if event is InputEventScreenDrag:
		if _active_fingers.has(event.index):
			_active_fingers[event.index] = event.position
		if _hand_touch_active and event.index == _finger:
			_handle_hand_drag(event.position)
			return
		if event.index == _finger and _holding:
			_target = event.position
			if _scroll_drag(_target): return
			if _drag_starting: return
			if _pressed_button == MOUSE_BUTTON_NONE and _target.distance_to(_start) > 12:
				_begin_drag(_start)
				return
			_move_mouse(_target)
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			cancel()
			return
		if not event.pressed:
			_active_fingers.erase(event.index)
			if _hand_touch_active and event.index == _finger:
				_handle_hand_release(event.position)
				_finger = -1
				return
			if event.index == _finger:
				_finger = -1
				if _scrolling:
					_scrolling = false
					_scroll_kind = ""
					_holding = false
					_selected_card = ""
					return
				_scroll_kind = ""
				if _drag_starting:
					_pending_drop = true
					return
				if _preparing:
					_pending_release = true
					return
				if _holding:
					_holding = false
					if _pressed_button == MOUSE_BUTTON_NONE:
						if _touch_card != "": _finish_card_tap(_target)
						elif _deck_touch and _mode() == "menu": _show_at(_target)
						else: _dispatch_click.call_deferred(MOUSE_BUTTON_LEFT, _target)
					else: _release()
			return
		_active_fingers[event.index] = event.position

		if _active_fingers.size() >= 2:
			_trigger_two_finger_cancel()
			return
		if _dispatching or _preparing or (_finger != -1 and _finger != event.index):
			return
		_finger = event.index
		if _response_cancel_panel.visible and _response_cancel_panel.get_global_rect().has_point(event.position):
			_finger = -1
			_hide_action_bar()
			_trigger_response_right_click_cancel()
			return
		if _menu.visible:
			var prev_visible: = _menu.visible
			var hit_btn: = _choose(event.position)
			if hit_btn or not prev_visible:
				_finger = -1
				return

		_actions.clear()
		var scene: Node = Game._screen
		var scene_pos: = _scene_point(event.position)

		if PlatformInput._normal_duel_active() and is_instance_valid(scene) and scene.has_method("phase_button_at") and scene.phase_button_at(scene_pos) >= 0 and scene_pos.x < 262.0:
			_hide_action_bar()
			_touch_card = ""
			_target = event.position
			_start = _target
			_holding = true
			_press(MOUSE_BUTTON_LEFT, _target)
			return

		if _try_begin_hand_touch(event.position, scene_pos):
			return
		_touch_card = _card_identity(event.position)
		if _touch_card == "": _selected_card = ""
		_deck_touch = is_instance_valid(scene) and scene.get_script().resource_path.ends_with("deck_editor.gd") and scene._modal == null and not scene._hit_at(scene_pos).is_empty()
		_right_available = _has_right_action(event.position)
		_target = event.position
		_start = _target
		_hold_time = 0.0
		_pending_release = false
		_pending_drop = false
		_scroll_candidate(_target)
		_move_mouse(_target)
		if _scroll_kind != "":
			_holding = true
			return
		if _right_available and PlatformInput._normal_duel_active():
			_prepare_card(_target)
			return
		_begin_touch(_target)


func _try_begin_hand_touch(point: Vector2, scene_pos: Vector2) -> bool:
	var scene: Node = Game._screen
	if not PlatformInput._normal_duel_active() or not is_instance_valid(scene) or scene._duel == null:
		return false
	if not scene._duel.dialog_open.is_empty() or not scene._duel.list_open.is_empty() or _target_selection(scene) or _response_cancel_active(scene):
		return false
	if not scene.has_method("_hit_player_hand"):
		return false
	var hand_hit: Dictionary = scene._hit_player_hand(scene_pos)
	if hand_hit.is_empty():
		return false
	_hide_action_bar()
	_hand_touch_active = true
	_hand_scrub_active = false
	_hand_swipe_triggered = false
	_hand_start_point = point
	_hand_start_scene_pos = scene_pos
	_target = point
	_start = point
	_holding = false
	if scene.has_method("set_hand_scrub_active"):
		scene.set_hand_scrub_active(false)
	if scene.has_method("scrub_hand_at"):
		scene.scrub_hand_at(scene_pos)
	_move_mouse(point)
	return true


func _handle_hand_drag(point: Vector2) -> void :
	var scene: Node = Game._screen
	if not is_instance_valid(scene):
		return
	var scene_pos: = _scene_point(point)
	_target = point
	var delta: = scene_pos - _hand_start_scene_pos
	if _hand_scrub_active or (absf(delta.x) >= SCRUB_THRESHOLD_PX and absf(delta.x) >= absf(delta.y)):
		_hand_scrub_active = true
		if scene.has_method("set_hand_scrub_active"):
			scene.set_hand_scrub_active(true)
		_hide_action_bar()
		if scene.has_method("scrub_hand_at"):
			scene.scrub_hand_at(scene_pos)
		_move_mouse(point)
		return
	if not _hand_swipe_triggered and delta.y <= - SWIPE_UP_MIN_DY and - delta.y > absf(delta.x) * 1.15:
		if not strict_state_guard(scene):
			return
		var is_diagonal: = absf(delta.x) > absf(delta.y) * SWIPE_DIAGONAL_RATIO
		_hand_swipe_triggered = true
		_swipe_play_hand_card(_hand_start_point, is_diagonal)


func _handle_hand_release(point: Vector2) -> void :
	var scene: Node = Game._screen
	var was_scrub: = _hand_scrub_active
	var was_swipe: = _hand_swipe_triggered
	_hand_touch_active = false
	_hand_scrub_active = false
	_hand_swipe_triggered = false
	if is_instance_valid(scene) and scene.has_method("set_hand_scrub_active"):
		scene.set_hand_scrub_active(false)
	if was_swipe:
		return
	var scene_pos: = _scene_point(point)
	if is_instance_valid(scene) and scene.has_method("scrub_hand_at"):
		var hit: Dictionary = scene.scrub_hand_at(scene_pos)
		if hit.is_empty() and was_scrub:
			hit = scene._hit_player_hand(scene_pos)
		if not hit.is_empty() and strict_state_guard(scene):
			var center: = point
			var r: Rect2 = hit.get("rect", Rect2())
			if r.has_area():
				center = _point_from_scene(r.get_center())
			_open_card_action_bar(center)


func _point_from_scene(scene_pos: Vector2) -> Vector2:
	if not is_instance_valid(Game._screen):
		return scene_pos
	if is_instance_valid(Game._screen_host) and Game._screen_host.has_method("duel_transform"):
		var duel_xf: Transform2D = Game._screen_host.duel_transform()
		return get_tree().root.get_final_transform().affine_inverse() * (duel_xf * scene_pos)
	return get_tree().root.get_final_transform().affine_inverse() * (Game._screen.get_viewport().get_screen_transform() * scene_pos)


func _await_legal_actions(generation: int) -> void :
	for frame_idx in 6:
		if generation != _generation or not is_inside_tree():
			return
		await get_tree().process_frame
		if generation != _generation or not is_instance_valid(Game._screen):
			return
		var d = Game._screen.get("_duel")
		if d != null and frame_idx >= 1 and d.m.u16(10564618) != 0:
			return


func _swipe_play_hand_card(start_point: Vector2, is_diagonal: bool) -> void :
	var generation: = _generation
	_preparing = true
	_move_mouse(start_point)
	await _await_legal_actions(generation)
	if generation != _generation:
		return
	_preparing = false
	var scene: Node = Game._screen
	if not strict_state_guard(scene):
		return
	var legal: = _read_legal_actions(scene._duel)
	if legal.is_empty():
		return
	var chosen: = -1
	if is_diagonal:
		if legal.has(5):
			chosen = 5
	else:
		for candidate in [1, 4, 11, 12, 10]:
			if legal.has(candidate):
				chosen = candidate
				break
	if chosen != -1:
		_execute_action.call_deferred(chosen, start_point)


func _open_card_action_bar(point: Vector2) -> void :
	var generation: = _generation
	_preparing = true
	_target = point
	_move_mouse(point)
	await _await_legal_actions(generation)
	if generation != _generation:
		return
	_preparing = false
	var scene: Node = Game._screen
	if not strict_state_guard(scene):
		_hide_action_bar()
		return
	_actions = _read_legal_actions(scene._duel)
	if _actions.is_empty():
		_hide_action_bar()
		return
	_bar_card_identity = _card_identity(point)
	_show_at(point)


func _trigger_two_finger_cancel() -> void :
	var had_bar: = _menu.visible
	var had_scrub: = _hand_scrub_active
	_hand_touch_active = false
	_hand_scrub_active = false
	_hand_swipe_triggered = false
	_holding = false
	_preparing = false
	_finger = -1
	_generation += 1
	_release()
	var scene: Node = Game._screen
	if is_instance_valid(scene) and scene.has_method("set_hand_scrub_active"):
		scene.set_hand_scrub_active(false)
	_hide_action_bar()
	if had_scrub or had_bar:
		return
	if PlatformInput._normal_duel_active() and is_instance_valid(scene) and scene._duel != null:
		if _response_cancel_active(scene):
			_trigger_response_right_click_cancel()
		elif _target_selection(scene) or not scene._duel.dialog_open.is_empty() or not scene._duel.list_open.is_empty():
			_dispatch_click.call_deferred(MOUSE_BUTTON_RIGHT, _target)
	elif is_instance_valid(scene) and scene.get_script().resource_path.ends_with("deck_editor.gd"):
		if scene._modal == null:
			_dispatch_click.call_deferred(MOUSE_BUTTON_RIGHT, _target)


func _read_legal_actions(d) -> Array[int]:
	var ordered: Array[int] = []
	if d == null:
		return ordered
	var mask: int = d.m.u16(10564618)
	if mask == 0:
		return ordered
	var raw: Array[int] = []
	for i in 12:
		var action: int = d.m.u8(5889820 + i * 4)
		if mask & (1 << action):
			var aid: = action + 1
			if not raw.has(aid):
				raw.append(aid)

	var priority: = [1, 4, 3, 5, 6, 7, 2, 10, 11, 12, 8, 9]
	var added_pos_change: = false
	for aid in priority:
		if raw.has(aid):
			if aid in [2, 6, 7]:
				if added_pos_change:
					continue
				added_pos_change = true
			ordered.append(aid)
	for aid in raw:
		if not ordered.has(aid) and not (aid in [2, 6, 7] and added_pos_change):
			ordered.append(aid)
	return ordered


func _prepare_card(point: Vector2) -> void :
	_preparing = true
	var generation: = _generation

	await _await_legal_actions(generation)
	if generation != _generation: return
	_preparing = false
	var scene: Node = Game._screen
	if not strict_state_guard(scene):
		_hide_action_bar()
		return
	_actions = _read_legal_actions(scene._duel)
	_right_available = _has_right_action(point) and not _actions.is_empty()
	if _right_available:
		_bar_card_identity = _card_identity(point)
	_begin_touch(point)


func _begin_touch(point: Vector2) -> void :
	if _touch_card != "":
		_holding = true
		if _pending_release:
			_holding = false
			_finish_card_tap(point)
	elif _deck_touch:

		_holding = true
	elif not _right_available:
		_holding = true
		_press(MOUSE_BUTTON_LEFT, _target)
		if _pending_release:
			_holding = false
			_release()
	elif _mode() == "hold":
		_holding = true
		if _pending_release:
			_holding = false
			_dispatch_click.call_deferred(MOUSE_BUTTON_LEFT, point)
	else:
		_show_at(point)


func _begin_drag(start: Vector2) -> void :
	var generation: = _generation
	_drag_starting = true
	_hide_action_bar()
	_press(MOUSE_BUTTON_LEFT, start)

	await get_tree().create_timer(2.0 / NativeClock.HZ).timeout
	if generation != _generation: return
	_drag_starting = false
	_move_mouse(_target)
	if _pending_drop:
		_holding = false
		_release(_target)


func _show_at(point: Vector2) -> void :
	_target = point
	var is_duel: = PlatformInput._normal_duel_active()
	if is_duel and not strict_state_guard(Game._screen):
		_hide_action_bar()
		return
	var ar: = _is_arabic()
	_bar_box.layout_direction = Control.LAYOUT_DIRECTION_RTL if ar else Control.LAYOUT_DIRECTION_LTR
	_button_actions.clear()
	var count: = _actions.size() if is_duel else maxi(2, _actions.size())
	if count == 0 and is_duel:
		_hide_action_bar()
		return
	while _choices.size() < count:
		var extra: = Button.new()
		_bar_box.add_child(extra)
		_choices.append(extra)

	_bar_box.move_child(_cancel_btn, -1)
	for i in _choices.size():
		var button: = _choices[i]
		_style_action_button(button, false)
		button.visible = i < count
		if i < _actions.size():
			var aid: = _actions[i]
			button.text = _action_label_text(aid)
			_button_actions.append(aid)
		elif not is_duel:
			var is_deck: bool = is_instance_valid(Game._screen) and str(Game._screen.get_script().resource_path).ends_with("deck_editor.gd")
			if is_deck:
				if Game._screen._button_at(_scene_point(point)) == "filter_label":
					button.text = _tr_ui("next_filter", "الفلتر التالي", "Next filter") if i == 0 else _tr_ui("prev_filter", "الفلتر السابق", "Prev filter")
				elif i == 0:
					button.text = _tr_ui("select", "تحديد", "Select")
				else:
					button.text = _tr_ui("drop_selection", "إفلات", "Drop") if Game._screen._held != 0 else _tr_ui("sort", "ترتيب", "Sort")
			else:
				button.text = _tr_ui("click", "نقرة", "Click") if i == 0 else _tr_ui("right_click", "خيارات", "Right Click")
	_style_action_button(_cancel_btn, true)
	_cancel_btn.text = _tr_ui("cancel", "إلغاء", "Cancel")
	_cancel_btn.visible = true
	_menu.reset_size()
	var bar_size: = _menu.get_combined_minimum_size()
	_menu.size = bar_size
	var bounds: = get_viewport().get_visible_rect()
	var x: = clampf(point.x - bar_size.x * 0.5, bounds.position.x + 6.0, bounds.end.x - bar_size.x - 6.0)
	var y: = point.y - bar_size.y - 28.0
	if y < bounds.position.y + 6.0:
		y = point.y + 20.0
	y = clampf(y, bounds.position.y + 6.0, bounds.end.y - bar_size.y - 6.0)
	_menu.position = Vector2(x, y)
	_menu.show()
	_move_mouse(point)


func _choose(point: Vector2) -> bool:
	if _cancel_btn.visible and _cancel_btn.get_global_rect().has_point(point):
		_hide_action_bar()
		return true
	var chosen: = -1
	for i in _choices.size():
		if _choices[i].visible and _choices[i].get_global_rect().has_point(point):
			chosen = i
			break
	if chosen < 0:
		_hide_action_bar()
		return false
	_hide_action_bar()
	if chosen < _actions.size():
		_execute_action.call_deferred(_actions[chosen], _target)
	else:
		_dispatch_click.call_deferred(MOUSE_BUTTON_LEFT if chosen == 0 else MOUSE_BUTTON_RIGHT, _target)
	return true


func _execute_action(action: int, point: Vector2) -> void :
	if action in [1, 5]:
		_confirm_scene = Game._screen
		_confirm_until = Time.get_ticks_msec() + 5000
	var generation: = _generation
	_dispatching = true
	_move_mouse(point)
	var d = Game._screen._duel
	for attempt in 12:
		if generation != _generation or not is_instance_valid(Game._screen) or d == null: break
		if d.cursor_action == action:

			_press(MOUSE_BUTTON_LEFT, point)
			await get_tree().create_timer(2.0 / NativeClock.HZ).timeout
			_release(point)
			break
		var previous: int = d.cursor_action
		_press(MOUSE_BUTTON_RIGHT, point)
		await get_tree().create_timer(2.0 / NativeClock.HZ).timeout
		_release(point)
		var deadline: = Time.get_ticks_msec() + 1000
		while generation == _generation and d.cursor_action == previous and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		if d.cursor_action == previous: break
	_dispatching = false


func _physical(point: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * point


func _move_mouse(point: Vector2) -> void :
	var motion: = InputEventMouseMotion.new()
	motion.position = _physical(point)
	motion.global_position = motion.position
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT if _pressed_button == MOUSE_BUTTON_RIGHT else 0
	Input.parse_input_event(motion)


func _dispatch_click(button: MouseButton, point: Vector2) -> void :
	var generation: = _generation
	_dispatching = true
	_move_mouse(point)
	await get_tree().process_frame
	if generation != _generation:
		_dispatching = false
		return
	_press(button, point)
	await get_tree().process_frame
	_release(point)
	_dispatching = false


func _press(button: MouseButton, point: Vector2) -> void :
	_pressed_button = button
	var press: = InputEventMouseButton.new()
	press.position = _physical(point)
	press.global_position = press.position
	press.button_index = button
	press.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	press.pressed = true
	press.set_meta("platform_touch", true)
	Input.parse_input_event(press)


func _release(point: Vector2 = _target) -> void :
	if _pressed_button == MOUSE_BUTTON_NONE: return
	var release: = InputEventMouseButton.new()
	release.position = _physical(point)
	release.global_position = release.position
	release.button_index = _pressed_button
	release.pressed = false
	release.set_meta("platform_touch", true)
	Input.parse_input_event(release)
	_pressed_button = MOUSE_BUTTON_NONE



func _scroll_candidate(point: Vector2) -> void :
	_scroll_kind = ""
	_scroll_node = null
	_scrolling = false
	_scroll_amount = 0.0
	_scroll_axis = ""
	_scroll_last = _scene_point(point)
	var scene: Node = Game._screen
	if not is_instance_valid(scene): return
	var path: String = scene.get_script().resource_path
	var local: = _scroll_last
	if path.ends_with("deck_editor.gd"):
		if is_instance_valid(scene._modal):
			if scene._modal.get_script().resource_path.ends_with("deck_warning_dialog.gd"):
				var body: Control = scene._modal._body.get_parent()
				if body.get_global_rect().has_point(local):
					_scroll_kind = "bar"
					_scroll_node = scene._modal._scroll
			elif scene._modal.get_script().resource_path.ends_with("deck_file_dialog.gd") and scene._modal._list_rect.has_point(local - scene._modal.position):
				_scroll_kind = "files"
				_scroll_node = scene._modal
			return
		if local.x < 224 and local.y >= 370 and local.y < 548 and is_instance_valid(scene._detail_scroll):
			_scroll_kind = "bar"
			_scroll_node = scene._detail_scroll
		elif not scene._swap and scene._zone_at(local) == scene.BAG and scene._button_at(local) == "":
			_scroll_kind = "bag"
			_scroll_node = scene
	elif path.ends_with("card_list.gd"):
		if scene._text_clip.get_rect().has_point(local):
			if scene.has_method("_scroll_text"):
				_scroll_kind = "text"
				_scroll_node = scene
			else:
				_scroll_kind = "bar"
				_scroll_node = scene._scroll
		elif scene.has_method("_hit_slot"):
			if scene._hit_slot(local) != -1:
				_scroll_kind = "pages"
				_scroll_node = scene
		elif scene._hit(Vector2i(local)) >= 0 and scene._hit(Vector2i(local)) < scene.PER_PAGE:
			_scroll_kind = "pages"
			_scroll_node = scene
	elif PlatformInput._normal_duel_active():
		var list: Node = scene._list_window
		if is_instance_valid(list) and list.has_scroll and Rect2(Vector2(list.center) - Vector2(list.size) / 2, Vector2(list.size)).has_point(local):
			_scroll_kind = "list"
			_scroll_node = list
	if _scroll_kind == "":
		_scroll_node = _scroll_control(scene, local)
		if _scroll_node != null: _scroll_kind = "control"


func _scroll_control(node: Node, point: Vector2) -> Node:
	for child in node.get_children():
		var found: = _scroll_control(child, point)
		if found != null: return found
	if node is ScrollContainer and node.is_visible_in_tree() and node.get_global_rect().has_point(point): return node
	return null


func _scroll_drag(point: Vector2) -> bool:
	if _scroll_kind == "" or not is_instance_valid(_scroll_node): return false
	var local: = _scene_point(point)
	var distance: = local - _scene_point(_start)
	var horizontal: = _scroll_kind in ["pages", "list"]
	if not _scrolling:
		if distance.length() < 12: return true

		if _scroll_kind == "bag" and absf(distance.x) > absf(distance.y):
			_scroll_kind = ""
			return false
		_scrolling = true
		_selected_card = ""
		_scroll_axis = "x" if horizontal and absf(distance.x) > absf(distance.y) else "y"
		_hide_action_bar()
		_release()
	var delta: = _scroll_last - local
	_scroll_last = local
	match _scroll_kind:
		"bar", "control":
			_scroll_amount += delta.y
			var pixels: = int(_scroll_amount)
			_scroll_amount -= pixels
			if _scroll_kind == "bar": _scroll_node.set_value(_scroll_node.value + pixels)
			else: _scroll_node.scroll_vertical += pixels
		"text": _scroll_node._scroll_text(delta.y)
		_:
			_scroll_amount += delta.x if _scroll_axis == "x" else delta.y
			var pitch: = 80.0 if _scroll_kind == "pages" else 32.0
			while absf(_scroll_amount) >= pitch:
				var step: = 1 if _scroll_amount > 0 else -1
				_scroll_amount -= step * pitch
				if _scroll_kind == "pages":
					if _scroll_node.has_method("_turn_page"): _scroll_node._turn_page(step)
					else:
						var page: = clampi(_scroll_node._page + step, 0, maxi(0, _scroll_node._pages - 1))
						if page != _scroll_node._page: _scroll_node._set_page(page, step > 0)
				elif _scroll_kind == "bag": _scroll_node._trunk_scroll = clampi(_scroll_node._trunk_scroll + step, 0, maxi(0, _scroll_node._view.size() - _scroll_node.TRUNK_ROWS))
				elif _scroll_kind == "files":
					_scroll_node._scroll = clampi(_scroll_node._scroll + step, 0, maxi(0, _scroll_node._files.size() - _scroll_node._visible_rows()))
					_scroll_node.queue_redraw()
				else:
					_scroll_node.row = clampi(_scroll_node.row + step, _scroll_node.row_min, _scroll_node.row_max)
					_scroll_node.queue_redraw()
	return true


func _card_identity(point: Vector2) -> String:
	var scene: Node = Game._screen
	if not is_instance_valid(scene): return ""
	var path: String = scene.get_script().resource_path
	var at: = _scene_point(point)
	if path.ends_with("deck_editor.gd") and scene._modal == null:
		var hit: Dictionary = scene._hit_at(at)
		if not hit.is_empty(): return "deck:%s" % hit["key"]
	if PlatformInput._normal_duel_active() and scene._duel != null and scene._duel.dialog_open.is_empty() and scene._duel.list_open.is_empty() and not _target_selection(scene):
		var hit: Dictionary = scene._hit_card(at)
		if not hit.is_empty(): return "duel:%s:%s:%s:%s" % [hit["p"], hit["loc"], hit["i"], hit["id"]]
	return ""


func _finish_card_tap(point: Vector2) -> void :
	var scene: Node = Game._screen
	if _deck_touch and is_instance_valid(scene):
		var hit: Dictionary = scene._hit_at(_scene_point(point))
		if not hit.is_empty():
			if scene.has_method("select_card_by_hit"):
				scene.select_card_by_hit(hit)
			else:
				scene._show_detail(CardDB.by_id(scene._key_id(hit["key"])))
		if _selected_card != _touch_card:
			_selected_card = _touch_card
		return
	if _touch_card.begins_with("duel:") and strict_state_guard(scene) and not _actions.is_empty():
		_selected_card = _touch_card
		_bar_card_identity = _touch_card
		_show_at(point)
		return
	if _selected_card != _touch_card:
		_selected_card = _touch_card
		return
	if _touch_card.begins_with("duel:") and not _actions.is_empty():
		_execute_action.call_deferred(1 if _actions.has(1) else _actions[0], point)
	else:
		_dispatch_click.call_deferred(MOUSE_BUTTON_LEFT, point)


func _material_selection(scene: Node) -> bool:
	if scene._duel == null: return false
	var action: int = scene._duel.m.u32(10564616)
	return (action & 2) != 0


func _target_selection(scene: Node) -> bool:
	if scene._duel == null: return false
	if _response_cancel_active(scene):
		return false
	if _material_selection(scene) or scene._duel.m.u8(10564620) >= 2:
		return true
	var d = scene._duel
	if not d.dialog_open.is_empty() or not d.list_open.is_empty():
		return false
	if d is JoeyPresentationAdapter:
		if d.engine == null:
			return false
		var em = d.engine.m

		var c86: int = int(em.u8(10837126))
		if (c86 & 1) != 0 and (((c86 >> 1) & 127) in [3, 5]):
			return true

		var c88: int = int(em.u8(10837128))
		if (c88 & 1) != 0 and (((c88 >> 1) & 127) == 6):
			return true
		return false

	var fce: int = int(d.m.u8(10575822))
	if (fce & 1) != 0 and (((fce >> 1) & 127) in [3, 5]):
		return true

	var fd0: int = int(d.m.u8(10575824))
	if (fd0 & 1) != 0 and (((fd0 >> 1) & 127) == 6):
		return true
	return false


func _response_cancel_active(scene: Node) -> bool:
	if not is_instance_valid(scene) or not PlatformInput._normal_duel_active():
		return false
	if bool(scene.get("_finished")) or scene.get("_result") != null:
		return false
	var d = scene.get("_duel")
	if d == null or not d.dialog_open.is_empty() or not d.list_open.is_empty():
		return false
	var guard: = get_node_or_null("/root/BackNavigationGuard")
	if guard != null and guard.has_method("is_modal_open") and guard.is_modal_open():
		return false
	if d is JoeyPresentationAdapter:
		if d.engine == null:
			return false
		var em = d.engine.m

		var c86: int = int(em.u8(10837126))
		if (c86 & 1) != 0:
			var chain_phase: int = (c86 >> 1) & 127
			return chain_phase in [12, 14] and (int(em.u32(10837224)) & 31) == 10
		if (int(em.u8(10837128)) & 1) != 0:
			return false

		var ce8: int = int(em.u32(10837224))
		if int(em.u16(10837124)) == 0 and (ce8 & 8192) != 0 and ((ce8 >> 5) & 63) == 10:
			return true

		if d.game_mode == d.GAME_NETWORK and (int(em.u32(10846816)) & 512) != 0 and (int(em.u8(10837226)) & 127) == 2:
			return true
		return false

	var fce: int = int(d.m.u8(10575822))
	if (fce & 1) != 0:
		var cstate: int = (fce >> 1) & 127
		return cstate in [12, 14] and int(d.m.u8(10576016)) == 10
	if (int(d.m.u8(10575824)) & 1) != 0:
		return false

	if int(d.m.u16(10575810)) == 0 and (int(d.m.u8(10576018)) & 64) != 0 and int(d.m.u8(10576017)) == 10:
		return true

	var a5a44: int = int(d.m.u32(10574404))
	if (a5a44 & 32768) != 0 and (a5a44 & 1024) == 0 and (int(d.m.u16(10576018)) >> 9) == 2:
		return true
	return false


func _update_response_cancel_button() -> void :
	var scene: Node = Game._screen
	if not _response_cancel_active(scene):
		if _response_cancel_panel.visible:
			_response_cancel_panel.hide()
		return
	var label: = _tr_ui("response_cancel_activation", "إلغاء التفعيل", "Cancel Activation")
	if _response_cancel_btn.text != label:
		_response_cancel_btn.text = label
	var bridge: = _bridge()
	if bridge != null:
		bridge.apply_rtl_control(_response_cancel_btn, _is_arabic())
	_response_cancel_panel.reset_size()
	var sz: = _response_cancel_panel.get_combined_minimum_size()
	_response_cancel_panel.size = sz
	var bounds: = get_viewport().get_visible_rect()
	_response_cancel_panel.position = Vector2(bounds.end.x - sz.x - 10.0, bounds.position.y + 8.0)
	if not _response_cancel_panel.visible:
		_response_cancel_panel.show()


func _trigger_response_right_click_cancel() -> void :
	var scene: Node = Game._screen
	if not _response_cancel_active(scene):
		_response_cancel_panel.hide()
		return
	_response_cancel_panel.hide()
	_selected_card = ""
	_touch_card = ""
	_dispatch_response_right_click.call_deferred()


func _dispatch_response_right_click() -> void :
	var generation: = _generation
	_dispatching = true


	var empty_point: = _point_from_scene(Vector2(4, 4))
	_move_mouse(empty_point)
	await get_tree().process_frame
	if generation != _generation:
		_dispatching = false
		return
	_press(MOUSE_BUTTON_RIGHT, empty_point)
	await get_tree().process_frame
	_release(empty_point)
	_dispatching = false


func _update_tribute_hint() -> void :
	_tribute_hint.hide()
	var scene: Node = Game._screen
	if not is_instance_valid(scene) or not PlatformInput._normal_duel_active() or scene._duel == null: return
	var d = scene._duel
	var action: int = d.m.u32(10564616)
	if not _material_selection(scene) or ((action >> 2) & 15) not in [0, 4] or not d.dialog_open.is_empty(): return
	var state: int = d.m.u8(10564621)
	if state not in [2, 3, 4, 5, 10, 11]: return
	if state in [10, 11]:
		_tribute_hint.text = _tr_ui("tribute_hint_select", "اختر وحشاً للتضحية به", "Tap a monster to Tribute")
	elif state in [2, 3]:
		_tribute_hint.text = _tr_ui("tribute_hint_first", "اختر التضحية الأولى", "Select 1st Tribute")
	else:
		_tribute_hint.text = _tr_ui("tribute_hint_second", "اختر التضحية الثانية", "Select 2nd Tribute")
	var bridge: = _bridge()
	if bridge != null:
		bridge.apply_rtl_control(_tribute_hint, _is_arabic())
	var bounds: = get_viewport().get_visible_rect()
	_tribute_hint.position = bounds.position + Vector2(4, 8)
	_tribute_hint.size = Vector2(bounds.size.x - 8, 36)
	_tribute_hint.show()
