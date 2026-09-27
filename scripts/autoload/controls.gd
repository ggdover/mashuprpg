extends Node
## Autoload "Controls": registers every input action at startup (the InputMap is built in code,
## not in project.godot) and gives the UI human-readable key labels.
## OWNER: orchestrator. Other modules only READ from here. FROZEN during waves 1-2: module agents must NOT edit this file. Need a new signal/stat/helper?
## Keep it in a file you own and list it in your final report; the orchestrator merges between waves.
##
## Poll actions with Input.is_action_pressed("skill_3"), or handle them in _unhandled_input so
## clicks that land on UI panels never reach gameplay.

## action -> list of bindings. An int binding below 16 is a mouse button index, anything else is a
## physical keycode.
const BINDINGS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"skill_1": [MOUSE_BUTTON_LEFT],
	# The right mouse button orbits the camera (CameraRig), so slot 2 is on the middle button.
	"skill_2": [MOUSE_BUTTON_MIDDLE],
	"skill_3": [KEY_Q],
	"skill_4": [KEY_E],
	"skill_5": [KEY_R],
	"skill_6": [KEY_F],
	"dodge": [KEY_SPACE],
	"parry": [KEY_SHIFT],
	"potion_life": [KEY_1],
	"potion_mana": [KEY_2],
	"town_portal": [KEY_T],
	"highlight_items": [KEY_ALT],
	"toggle_inventory": [KEY_I],
	"toggle_character": [KEY_C],
	"toggle_passives": [KEY_P],
	"toggle_skills": [KEY_K],
	"toggle_minimap": [KEY_TAB],
	"toggle_acts": [KEY_M],
	"toggle_debug": [KEY_F1],
	"toggle_camera_info": [KEY_F2],
	"pause_menu": [KEY_ESCAPE],
	"zoom_in": [MOUSE_BUTTON_WHEEL_UP],
	"zoom_out": [MOUSE_BUTTON_WHEEL_DOWN],
	# Debug helpers, only honoured when OS.is_debug_build().
	"debug_level_up": [KEY_F9],
	"debug_spawn_loot": [KEY_F10],
	"debug_god_mode": [KEY_F11],
	"debug_screenshot": [KEY_F12],
}

## The six skill-bar actions in slot order (slot index 0..5).
const SKILL_ACTIONS: Array[String] = ["skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6"]

const _MOUSE_LABELS := {
	MOUSE_BUTTON_LEFT: "LMB",
	MOUSE_BUTTON_RIGHT: "RMB",
	MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}
const _KEY_LABELS := {
	KEY_SHIFT: "Shift",
}


func _ready() -> void:
	for action: String in BINDINGS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for code: int in BINDINGS[action]:
			InputMap.action_add_event(action, _make_event(code))


func _make_event(code: int) -> InputEvent:
	if code < 16:
		var mb := InputEventMouseButton.new()
		mb.button_index = code as MouseButton
		return mb
	var key := InputEventKey.new()
	key.physical_keycode = code as Key
	return key


## Short label for the first binding of an action, e.g. "Q", "LMB", "Space".
func label_for(action: String) -> String:
	if not BINDINGS.has(action) or BINDINGS[action].is_empty():
		return "?"
	var code: int = BINDINGS[action][0]
	if code < 16:
		return _MOUSE_LABELS.get(code, "Mouse %d" % code)
	return _KEY_LABELS.get(code, OS.get_keycode_string(code as Key))


## Label for skill-bar slot 0..5.
func skill_slot_label(slot: int) -> String:
	if slot < 0 or slot >= SKILL_ACTIONS.size():
		return "?"
	return label_for(SKILL_ACTIONS[slot])
