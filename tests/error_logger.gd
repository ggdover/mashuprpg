extends Logger
## Captures engine/script errors (not warnings) so the test runner can fail the test that caused
## them. push_warning() is NOT captured; push_error() and runtime SCRIPT ERRORs are.
## OWNER: orchestrator.

var _mutex := Mutex.new()
var _errors: PackedStringArray = []


func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var msg := "%s:%d %s %s" % [file, line, code, rationale]
	if msg.contains("leaked at exit"):
		return
	_mutex.lock()
	_errors.append(msg)
	_mutex.unlock()


func take() -> PackedStringArray:
	_mutex.lock()
	var e := _errors.duplicate()
	_errors.clear()
	_mutex.unlock()
	return e
