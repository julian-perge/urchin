# Every shader in the project compiles (julian-perge/urchin#426). Godot does
# not compile a shader when it loads the file. It compiles it, also in a
# headless run, when something first asks the renderer for it, and then logs
# "Shader compilation failed" if the code has an error. GUT fails the test that
# was running when the engine logged that error. So each test here loads its
# shader fresh from disk and asks for its uniform list, which compiles it. A
# .gdshaderinc does not compile alone. It compiles as part of each shader that
# includes it, so the last test fails when no shader includes it, directly or
# through another include.
extends GutTest

const ROOT: String = "res://"
# GUT ships in addons/, and the game does not use its files.
const SKIPPED: Array[String] = ["res://addons"]
const INCLUDE_LINE: String = "^\\s*#include\\s+\"([^\"]+)\""

# GUT reads a parameterized test's default argument again for each parameter,
# so the folder walk runs once here and not once per shader.
var _shaders: Array[String] = _files(ROOT, ".gdshader")


# Every file under folder whose name ends in extension. Godot does not import a
# folder that holds a .gdignore file, so the game cannot use what is in it.
func _files(folder: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	if folder in SKIPPED or FileAccess.file_exists(folder.path_join(".gdignore")):
		return found
	for name: String in DirAccess.get_files_at(folder):
		if name.ends_with(extension):
			found.append(folder.path_join(name))
	for name: String in DirAccess.get_directories_at(folder):
		found.append_array(_files(folder.path_join(name), extension))
	return found


func test_the_project_has_shaders_to_check() -> void:
	assert_gt(_shaders.size(), 0, "the search found no .gdshader file")


func test_each_shader_compiles(path: String = use_parameters(_shaders)) -> void:
	var shader: Shader = ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_IGNORE)
	assert_not_null(shader, "%s did not load" % path)
	if shader != null:
		shader.get_shader_uniform_list()


# The res:// path of each file that an #include line of the file at path names.
# A path that does not start with res:// is relative to the including file's
# folder, as Godot's shader preprocessor reads it.
func _includes(path: String) -> Array[String]:
	var pattern := RegEx.create_from_string(INCLUDE_LINE)
	var found: Array[String] = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var include: RegExMatch = pattern.search(line)
		if include == null:
			continue
		var target: String = include.get_string(1)
		if not target.begins_with("res://"):
			target = path.get_base_dir().path_join(target).simplify_path()
		found.append(target)
	return found


func test_each_shader_include_is_part_of_a_shader() -> void:
	var reached: Dictionary[String, bool] = {}
	var pending: Array[String] = _shaders.duplicate()
	while not pending.is_empty():
		for target: String in _includes(pending.pop_back()):
			if not reached.has(target):
				reached[target] = true
				pending.append(target)
	for path: String in _files(ROOT, ".gdshaderinc"):
		assert_true(reached.has(path), "no .gdshader includes %s, directly or through another include" % path)
