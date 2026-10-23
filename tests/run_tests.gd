extends SceneTree
## Headless test runner. Usage: godot --headless --path . -s tests/run_tests.gd
## Runs every `func test_*` in tests/test_*.gd. Prints `TESTS: <n> passed, <m> failed` and exits 1 on any failure.

var failures := 0
var current := ""


func _init() -> void:
	var passed := 0
	var failed := 0
	var dir := DirAccess.open("res://tests")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():  # parse error: fail it, don't hang
			failed += 1
			print("  FAILED ", f, " (script does not compile)")
			continue
		var inst = script.new()
		inst.set("runner", self)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			current = f + "::" + name
			var before := failures
			inst.call(name)
			if failures == before:
				passed += 1
			else:
				failed += 1
				print("  FAILED ", current)
	print("TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, what: String) -> void:
	if not cond:
		failures += 1
		print("    check failed in ", current, ": ", what)
