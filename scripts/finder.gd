@tool
extends Node

var textures_list: Dictionary[String, String]
var loaded_materials: Dictionary[String, StandardMaterial3D]

func compile_texture_array():
	textures_list.clear()
	textures_list = get_all_file_paths("res://textures", "png")


func get_texture_size(texture: String) -> Vector2:
	if not textures_list.has(texture):
		print("Texture not found: ", texture)
		return Vector2.ONE
	
	return load(textures_list[texture]).get_size()


func get_material(texture: String) -> StandardMaterial3D:
	if textures_list.is_empty():
		compile_texture_array()
	
	if texture.is_empty():
		return null
	
	if not textures_list.has(texture):
		print("Texture not found: ", texture)
		return null
	
	if loaded_materials.has(texture):
		return loaded_materials[texture]
	
	var mat = StandardMaterial3D.new()
	mat.albedo_texture = load(textures_list[texture])
	loaded_materials[texture] = mat
	return mat


func _populate_file_paths(path: String, extension: String, files: Dictionary[String, String]):
	var all_files : Array = DirAccess.get_files_at(path)
	var target_files := all_files.filter(func(x): return x.get_extension() == extension)
	var texture_names := target_files.map(func(x): return x.get_basename())
	var full_path_files := target_files.map(func(x): return path + "/" + x)
	
	for n in target_files.size():
		files[texture_names[n]] = full_path_files[n]
	
	for folder in DirAccess.get_directories_at(path):
		_populate_file_paths(path + "/" + folder, extension, files)


func get_all_file_paths(path: String, extension: String) -> Dictionary[String, String]:
	var file_paths : Dictionary[String, String] = {}
	_populate_file_paths(path, extension, file_paths)
	return file_paths
