extends RefCounted
class_name Polygon

var item: String = ""
var texture: String = ""
var link: int = -1
var flags: int = 0

var origin: Vector3 = Vector3.ZERO
var normal: Vector3 = Vector3.ZERO
var texture_u: Vector3 = Vector3(1, 0, 0)
var texture_v: Vector3 = Vector3(0, 1, 0)

var vertices: PackedVector3Array

var mesh_data: Array

func create(data: Array[String]) -> void:
	assign_descriptors(data[0])
	assign_polygon_data(data.slice(1))

func is_rectangle() -> bool:
	if vertices.size() != 4:
		return false
	var verts_same = [true, true, true]
	for i in range(len(vertices)-1):
		if vertices[i].x != vertices[i+1].x:
			verts_same[0] = false
		if vertices[i].y != vertices[i+1].y:
			verts_same[1] = false
		if vertices[i].z != vertices[i+1].z:
			verts_same[2] = false
	return verts_same.any(func(x): x == true)
		

func assign_descriptors(first_line: String) -> void:
	var rest := first_line.replace("Begin Polygon", "").strip_edges()
	for token in rest.split(" ", false):
		var kv := token.split("=", false, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"Item":    item    = kv[1]
			"Texture": texture = kv[1]
			"Flags":   flags   = int(kv[1])
			"Link":    link    = int(kv[1])


func assign_polygon_data(lines: Array[String]) -> void:
	for line in lines:
		var kv := line.strip_edges().split(" ", false, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"Origin":   origin    = to_vector3(kv[1])
			"Normal":   normal    = to_vector3(kv[1])
			"TextureU": texture_u = to_vector3(kv[1])
			"TextureV": texture_v = to_vector3(kv[1])
			"Vertex":   vertices.append(to_vector3(kv[1]))

static func to_vector3(s: String) -> Vector3:
	var p := s.strip_edges().split(",")
	if p.size() < 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
