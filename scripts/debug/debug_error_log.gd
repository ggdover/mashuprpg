extends Logger
## Counts engine / script errors and warnings while the autoplay bot or the screenshot tour runs
## (installed with OS.add_logger). Thread-safe. OWNER: flow (wave 2).

const KEEP := 40

var error_count := 0
var warning_count := 0
## The first KEEP messages of each kind ("file:line code rationale").
var errors: PackedStringArray = []
var warnings: PackedStringArray = []

var _mutex := Mutex.new()


func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var msg := "%s:%d %s %s" % [file, line, code, rationale]
	if msg.contains("leaked at exit") or msg.contains("Pages in use"):
		return
	_mutex.lock()
	if error_type == ERROR_TYPE_WARNING:
		warning_count += 1
		if warnings.size() < KEEP:
			warnings.append(msg)
	else:
		error_count += 1
		if errors.size() < KEEP:
			errors.append(msg)
	_mutex.unlock()


func get_error_count() -> int:
	_mutex.lock()
	var n := error_count
	_mutex.unlock()
	return n


func get_warning_count() -> int:
	_mutex.lock()
	var n := warning_count
	_mutex.unlock()
	return n


func get_errors() -> PackedStringArray:
	_mutex.lock()
	var e := errors.duplicate()
	_mutex.unlock()
	return e


func get_warnings() -> PackedStringArray:
	_mutex.lock()
	var e := warnings.duplicate()
	_mutex.unlock()
	return e
