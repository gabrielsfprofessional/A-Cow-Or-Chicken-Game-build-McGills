extends SceneTree
## Writes LICENSES.txt for a release (card T29): Godot's MIT license, its copyright
## notices and the license texts of the third-party code inside the engine.
## They must ship with the game. tools/release.ps1 runs it with the console build:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/write_licenses.gd -- --out=<file>
## The editor build and the export templates are the same engine version, so the
## texts match what is inside the .exe. Exits 1 when it can't write the file.

const OUT_FLAG: String = "--out="


func _init() -> void:
	var out_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_FLAG):
			out_path = arg.substr(OUT_FLAG.length()).strip_edges()
	if out_path == "":
		printerr("[Licenses] pass -- --out=<file>")
		quit(1)
		return
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("[Licenses] could not write %s (error %d)" % [out_path, FileAccess.get_open_error()])
		quit(1)
		return
	file.store_string(_text())
	file.close()
	print("[Licenses] wrote %s" % out_path)
	quit(0)


func _text() -> String:
	var lines: PackedStringArray = []
	var version_info: Dictionary = Engine.get_version_info()
	lines.append("A Cow or Chicken is made with the Godot Engine %s (https://godotengine.org/license)." % str(version_info.get("string", "")))
	lines.append("")
	lines.append("==== Godot Engine license ====")
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append("==== Copyright notices of the parts inside the engine ====")
	for component: Variant in Engine.get_copyright_info():
		if not component is Dictionary:
			continue
		var entry: Dictionary = component
		lines.append("")
		lines.append("- %s" % str(entry.get("name", "")))
		var parts: Variant = entry.get("parts", [])
		if not parts is Array:
			continue
		for part: Variant in parts:
			if not part is Dictionary:
				continue
			var details: Dictionary = part
			var files: Variant = details.get("files", [])
			if files is Array:
				lines.append("  Files: %s" % ", ".join(PackedStringArray(files)))
			var holders: Variant = details.get("copyright", [])
			if holders is Array:
				for holder: Variant in holders:
					lines.append("  Copyright: %s" % str(holder))
			lines.append("  License: %s" % str(details.get("license", "")))
	lines.append("")
	lines.append("==== Third-party license texts ====")
	var licenses: Dictionary = Engine.get_license_info()
	var names: Array = licenses.keys()
	names.sort()
	for license_name: Variant in names:
		lines.append("")
		lines.append("---- %s ----" % str(license_name))
		lines.append(str(licenses[license_name]))
	return "\n".join(lines) + "\n"
