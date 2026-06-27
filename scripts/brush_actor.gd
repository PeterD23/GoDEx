@icon("res://icons//cube.svg")
extends Actor
class_name BrushActor

# Order variables by their appearance in the file, makes it a bit easier to parse!
# Not all of them will appear, 
@export var csg_operation: String = ""

@export var main_scale: Vector3 = Vector3.ONE
@export var post_scale: Vector3 = Vector3.ONE
@export var temp_scale: Vector3 = Vector3.ONE

@export var poly_flags: int = 0

@export var distance_from_player: float = 0.0
@export var level: String = ""
@export var tag: String = ""
@export var region: Dictionary
@export var location: Vector3 = Vector3.ZERO

@export var brush: Brush

@export var pre_pivot: Vector3 = Vector3.ZERO

@export var rotation_pitch: int = 0
@export var rotation_yaw: int = 0
@export var rotation_roll: int = 0

func create(data: Array[String]) -> void:
	assign_brush(data)
	assign_descriptors(data)
	transform_brush()

func _ready() -> void:
	if Engine.is_editor_hint():
		self.owner = get_tree().edited_scene_root
	add_child(brush)


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

func assign_brush(data: Array[String]) -> void:
	var slice_start := 0
	var slice_end := data.size()
	for i in range(data.size()):
		if data[i].begins_with("Begin Brush"):
			slice_start = i
		elif data[i].begins_with("End Brush"):
			slice_end = i
			break
	brush = Brush.new()
	brush.name = data[slice_start].replace("Begin Brush Name=", "").strip_edges()
	brush.create(data.slice(slice_start + 1, slice_end))


func assign_descriptors(data: Array[String]) -> void:
	for line in data:
		var kv := line.split("=", false, 1)
		if kv.size() < 2:
			continue
		var key := kv[0].strip_edges()
		var val := kv[1].strip_edges()
		match key:
			"CsgOper": csg_operation = val
			"DistanceFromPlayer": distance_from_player = float(val)
			"Level": level = val
			"Tag": tag = val
			"Location": location = parse_xyz_vector3(val)
			"PrePivot": pre_pivot = parse_xyz_vector3(val)
			"Rotation": parse_rotation(val)
			"MainScale": main_scale = parse_ue1_scale(val)
			"PostScale": post_scale = parse_ue1_scale(val)
			"TempScale": temp_scale = parse_ue1_scale(val)


func transform_brush() -> void:
	brush.pre_pivot = pre_pivot
	brush.location = location
	for poly in brush.poly_list:
		poly.origin = transform_vertex(poly.origin)
		poly.normal = transform_direction(poly.normal)
		poly.texture_u = transform_direction(poly.texture_u)
		poly.texture_v = transform_direction(poly.texture_v)
		
		var new_verts := PackedVector3Array()
		for v in poly.vertices:
			v = transform_vertex(v)
			new_verts.append(v)
		poly.vertices = new_verts

func coord(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)


func transform_vertex(v: Vector3) -> Vector3:
	v = v * main_scale
	v = v - pre_pivot
	v = rotate_yaw(v, rotation_yaw)
	v = rotate_pitch(v, rotation_pitch)
	v = rotate_roll(v, rotation_roll)
	v = v * post_scale
	v = v * temp_scale
	v = v + location
	# UE1 (X-right, Y-forward, Z-up, left-handed)
	# Godot (X-right, Y-up, Z-back, right-handed)
	return coord(v) * UU_TO_METRES


func transform_direction(d: Vector3) -> Vector3:
	d = d * main_scale
	d = rotate_yaw(d, rotation_yaw)
	d = rotate_pitch(d, rotation_pitch)
	d = rotate_roll(d, rotation_roll)
	d = d * post_scale
	d = d * temp_scale
	return Vector3(d.x, d.z, -d.y)


# UE1 rotation units: 65536 = 360°
const UE1_TO_RAD := TAU / 65536.0

# 60.352 UU = 1 metre
const UU_TO_METRES := 1.0 / 60.352


func rotate_yaw(v: Vector3, units: int) -> Vector3:
	if units == 0:
		return v
	var a := units * UE1_TO_RAD
	var c := cos(a); var s := sin(a)
	return Vector3(c * v.x - s * v.y, s * v.x + c * v.y, v.z)


func rotate_pitch(v: Vector3, units: int) -> Vector3:
	if units == 0:
		return v
	var a := units * UE1_TO_RAD
	var c := cos(a); var s := sin(a)
	return Vector3(c * v.x + s * v.z, v.y, -s * v.x + c * v.z)


func rotate_roll(v: Vector3, units: int) -> Vector3:
	if units == 0:
		return v
	var a := units * UE1_TO_RAD
	var c := cos(a); var s := sin(a)
	return Vector3(v.x, c * v.y - s * v.z, s * v.y + c * v.z)


func parse_xyz_vector3(data: String) -> Vector3:
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	var chars_to_remove = "PrePivotOldLocation=()"
	data = data.remove_chars(chars_to_remove)
	var vector_data = data.split(",")
	for el in vector_data:
		match el[0]:
			'X':
				x = float(el.substr(1))
			'Y':
				y = float(el.substr(1))
			'Z':
				z = float(el.substr(1))
	return Vector3(x, y, z)


func parse_rotation(data: String) -> void:
	var chars_to_remove = "()"
	data = data.remove_chars(chars_to_remove).replace("Rotation=","")
	var vector_data = data.split(",")
	for el in vector_data:
		var split = el.split("=")
		match split[0]:
			'Yaw':
				rotation_yaw = float(split[1])
			'Pitch':
				rotation_pitch = float(split[1])
			'Roll':
				rotation_roll = float(split[1])


func parse_ue1_scale(s: String) -> Vector3:
	var inner_re := RegEx.new()
	inner_re.compile(r"Scale=\(([^)]*)\)")
	var m := inner_re.search(s)
	if not m:
		return Vector3.ONE
	var inner := m.get_string(1)
	var sx := 1.0; var sy := 1.0; var sz := 1.0
	var rx := RegEx.new(); rx.compile(r"X=([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)")
	var ry := RegEx.new(); ry.compile(r"Y=([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)")
	var rz := RegEx.new(); rz.compile(r"Z=([+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)")
	var mx := rx.search(inner); if mx: sx = float(mx.get_string(1))
	var my := ry.search(inner); if my: sy = float(my.get_string(1))
	var mz := rz.search(inner); if mz: sz = float(mz.get_string(1))
	return Vector3(sx, sy, sz)
