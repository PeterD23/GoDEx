@tool
class_name ForwardParser
extends Node

const ACTOR_START := "Begin Actor"
const ACTOR_END := "End Actor"
const BEGIN := "Begin"
const END := "End"

var property_value := RegEx.create_from_string("[^, \\)]*")

var lines : Array[String]
var index := 0

var first_subtract_skipped := false

class PolygonBuilder:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	
	func add_triangles(verts: Array[Vector3], normal: Vector3, origin: Vector3, u: Vector3, v: Vector3, texture_scale : Vector2, texture_pan: Vector2, inds: Array) -> void:
		var size := vertices.size()
		vertices.append_array(verts)
		
		for i in verts.size():
			normals.append(normal)
			var texture_origin := verts[i] - origin
			uvs.append((Vector2(texture_origin.dot(u), texture_origin.dot(v)) + texture_pan) / texture_scale)
		
		if inds.is_empty():
			# assume triangle fan
			for i in range(1, verts.size() - 1):
				indices.append(size)
				indices.append(size + i + 1)
				indices.append(size + i)
		else:
			for i in inds:
				indices.append(size + i)
	
	
	func build(mesh: ArrayMesh) -> int:
		var surface_array := []
		surface_array.resize(Mesh.ARRAY_MAX)
		surface_array[Mesh.ARRAY_VERTEX] = vertices
		surface_array[Mesh.ARRAY_NORMAL] = normals
		surface_array[Mesh.ARRAY_TEX_UV] = uvs
		surface_array[Mesh.ARRAY_INDEX]  = indices
		
		var index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
		return index


func _read_file(filename: String) -> void:
	lines.clear()
	index = 0
	
	var file := FileAccess.open(filename, FileAccess.READ)
	
	while file and not file.eof_reached():
		var line := file.get_line().strip_edges()
		lines.append(line)


func _next_line() -> String:
	var result := lines[index]
	index += 1
	return result


# returns (str) as str
static func _paren(str: String) -> String:
	if str.begins_with("(") and str.ends_with(")"):
		str = str.trim_prefix("(").trim_suffix(")")
	return str


# returns key=value as {key, value} dict
static func _kv(str: String) -> Dictionary:
	var parts := str.split("=", true, 1)
	if parts.size() != 2:
		return {key = "", value = ""}
	return {key = parts[0], value = parts[1]}


static func _tokens(str: String) -> Array:
	return str.split(" ", false)


static func _parse_begin(str: String) -> Dictionary:
	var t = _tokens(str)
	var result = {type = t[1]}
	for n in range(2, t.size()):
		var kv = _kv(t[n])
		result[kv.key] = kv.value
	return result


static func _parse_data(str: String) -> Dictionary:
	var kv := str.split(" ", false, 1)
	if kv.size() != 2:
		push_warning("Unable to parse data line: ", str)
		return { type = "unknown" }
	
	if kv[0] == "Pan":
		var uv := kv[1].split(" ")
		var u := _kv(uv[0])
		var v := _kv(uv[1])
		return { type = kv[0], value = { U = u.value, V = v.value} }
	
	var c = kv[1].split(",")
	if c.size() == 1:
		return { type = kv[0], value = float(kv[1]) }
	if c.size() == 3:
		return { type = kv[0], value = Vector3(float(c[0]), float(c[1]), float(c[2]))}
	return { type = kv[0], value = kv[1] }


# parse a property of the form K=V, where V is a value or property list
# V is terminated with , or ) or ' ' by regex (hence non-static)
# returns rest of string
func _parse_property(str: String, prop: Dictionary) -> String:
	var kv = _kv(str)
	if kv.value.begins_with("("):
		var pl := {}
		prop[kv.key] = pl
		var next = kv.value
		while next[0] != ")":
			next = _parse_property(next.right(-1), pl)
		return next.right(-1)
	
	var result := property_value.search(kv.value).get_string()
	prop[kv.key] = result
	return kv.value.substr(result.length())


func _parse_polygon() -> Dictionary:
	var line := _next_line()
	var vertices : Array[Vector3] = []
	var result := { vertices = vertices }
	while index < lines.size():
		if line.begins_with("End"):
			break
		var data = _parse_data(line)
		match data.type:
			"Vertex": vertices.push_back(data.value)
			"Normal": result["normal"] = data.value
			"Origin": result["origin"] = data.value
			"TextureU": result["texture_u"] = data.value
			"TextureV": result["texture_v"] = data.value
			"Pan": result["pan"] = Vector2(data.value.U.to_float(), data.value.V.to_float())
		line = _next_line()
	
	return result


func _retriangulate_mesh(polygons: Array, vertices: Array[Vector3]) -> void:
	# list of polygons, along with a list of all unique vertices
	# For each polygon, gather all vertices that are coincident,
	# then triangulate that using delaunay triangulation
	
	# Godot has built-in delaunay triangulation for 2D areas
	# so convert all vertices into projected texture space for triangulation
	for polygon in polygons:
		var ov = polygon.vertices
		var retriangulated_vertices : Array[Vector3] = []
		polygon.vertices = retriangulated_vertices
		var points : PackedVector2Array = []
		for i in ov.size():
			var a : Vector3 = ov[i]
			var b : Vector3 = ov[(i + 1) % ov.size()]
			var d := b - a
			var dir := d.normalized()
			
			for v in vertices:
				if b == v:
					continue
				
				var projection := dir.dot(v - a)
				var projected_v := a + dir * projection
				if projected_v.distance_squared_to(v) < 1.0 and projection >= 0 and projection < d.length():
					polygon.vertices.push_back(v)
					var offset = v - ov[0]
					points.push_back(Vector2(offset.dot(polygon.texture_u), offset.dot(polygon.texture_v)))
		
		var indices := Geometry2D.triangulate_delaunay(points)
		polygon["indices"] = indices
		
		# Make sure all indices comport with polygon normal (facing original direction)
		for i in range(0, indices.size(), 3):
			var i0 := indices[i]
			var i1 := indices[i + 1]
			var i2 := indices[i + 2]
			var a : Vector3 = polygon.vertices[i1] - polygon.vertices[i0]
			var b : Vector3 = polygon.vertices[i2] - polygon.vertices[i0]
			if b.cross(a).dot(polygon.normal) < 0.0:
				indices[i + 1] = i2
				indices[i + 2] = i1


func _parse_next_brush(parent: Node3D, actor: Dictionary):
	# First, parse out all properties and polygons
	var polygons := []
	var line := _next_line()
	while index < lines.size():
		if line.begins_with(BEGIN):
			var begin := _parse_begin(line)
			if begin.type == "Polygon":
				var polygon := _parse_polygon()
				polygon.merge(begin)
				polygons.push_back(polygon)
		elif line.begins_with(END):
			if line == ACTOR_END:
				break
		else:
			# Another property
			_parse_property(line, actor)
		line = _next_line()
	
	# Don't create the gigantic subtract hulls at the start, so only
	# start adding brushes from the first additive brush
	if not first_subtract_skipped:
		if actor.get("CsgOper", "CSG_Subtract") == "CSG_Subtract":
			print("Skipping ", actor.Name)
			return
	
	first_subtract_skipped = true
	
	# Hack to pick out specific brushes for investigation, debugging, etc.
	#if actor.Name != "Brush191":
	#	return
	
	# Analyze the mesh
	var all_vertices : Dictionary[Vector3, bool] = {}
	var faces := 0
	var planar = false
	for polygon in polygons:
		for vertex in polygon.vertices:
			all_vertices[vertex] = true
		faces += polygon.vertices.size() - 2
	
	# check euler characteristic, if != 2 then badly formed mesh
	# edges = (faces * 3) / 2
	# faces - edges = -faces / 2
	# multiply through by two to avoid integer rounding
	if (2 * all_vertices.size() - faces != 4):
		# if faces <= 12 then it is planar, effectively a sprite
		# if faces > 12 then it must be remeshed to correct the manifold
		if faces <= 12:
			planar = true
		else:
			_retriangulate_mesh(polygons, all_vertices.keys())
	
	if planar:
		return
	
	# Combine polygons into builders
	var builders : Dictionary[String, PolygonBuilder]
	for polygon in polygons:
		if not polygon.has("Texture"):
			continue
		
		if not builders.has(polygon.Texture):
			builders[polygon.Texture] = PolygonBuilder.new()
		var size := Finder.get_texture_size(polygon.Texture)
		builders[polygon.Texture].add_triangles(
			polygon.vertices,
			polygon.normal,
			polygon.origin,
			polygon.texture_u,
			polygon.texture_v,
			size,
			polygon.get("pan", Vector2.ZERO),
			polygon.get("indices", [])
		)
	
	if builders.is_empty():
		# no polygons
		return
	
	var mesh = ArrayMesh.new()
	for texture in builders:
		var builder := builders[texture]
		var surface_index = builder.build(mesh)
		var material = Finder.get_material(texture)
		if material:
			mesh.surface_set_name(surface_index, texture)
			mesh.surface_set_material(surface_index, material)
	
	var node := CSGMesh3D.new()
	node.name = actor.Name
	node.mesh = mesh
	
	# Apply all properties
	if actor.has("MainScale") and actor.MainScale.has("Scale"):
		var main_scale = Vector3.ONE
		main_scale.x = actor.MainScale.Scale.get("X", "1.0").to_float()
		main_scale.y = actor.MainScale.Scale.get("Y", "1.0").to_float()
		main_scale.z = actor.MainScale.Scale.get("Z", "1.0").to_float()
		node.transform = node.transform.scaled(main_scale)
	if actor.has("PrePivot"):
		var pre_pivot = Vector3.ZERO
		pre_pivot.x = actor.PrePivot.get("X", "0.0").to_float()
		pre_pivot.y = actor.PrePivot.get("Y", "0.0").to_float()
		pre_pivot.z = actor.PrePivot.get("Z", "0.0").to_float()
		node.transform = node.transform.translated(-pre_pivot)
	if actor.has("Rotation"):
		var scale := PI / 32768
		if actor.Rotation.has("Yaw"):
			node.transform = node.transform.rotated(Vector3(0.0, 0.0, 1.0), actor.Rotation.Yaw.to_int() * scale)
		if actor.Rotation.has("Pitch"):
			node.transform = node.transform.rotated(Vector3(0.0, 1.0, 0.0), actor.Rotation.Pitch.to_int() * scale)
		if actor.Rotation.has("Roll"):
			node.transform = node.transform.rotated(Vector3(1.0, 0.0, 0.0), actor.Rotation.Roll.to_int() * scale)
	if actor.has("PostScale") and actor.PostScale.has("Scale"):
		var post_scale = Vector3.ONE
		post_scale.x = actor.PostScale.Scale.get("X", "1.0").to_float()
		post_scale.y = actor.PostScale.Scale.get("Y", "1.0").to_float()
		post_scale.z = actor.PostScale.Scale.get("Z", "1.0").to_float()
		node.transform = node.transform.scaled(post_scale)
	if actor.has("TempScale"):
		var temp_scale = Vector3.ONE
		temp_scale.x = actor.TempScale.get("X", "1.0").to_float()
		temp_scale.y = actor.TempScale.get("Y", "1.0").to_float()
		temp_scale.z = actor.TempScale.get("Z", "1.0").to_float()
		node.transform = node.transform.scaled(temp_scale)
	if actor.has("Location"):
		var location = Vector3.ZERO
		location.x = actor.Location.get("X", "0.0").to_float()
		location.y = actor.Location.get("Y", "0.0").to_float()
		location.z = actor.Location.get("Z", "0.0").to_float()
		node.transform = node.transform.translated(location)
	if actor.get("CsgOper", "CSG_Add") == "CSG_Subtract":
		node.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root


func _parse_next_actor(parent: Node3D):
	var line := _next_line()
	while index < lines.size() and not line.begins_with(ACTOR_START):
		line = _next_line()
	
	if not line.begins_with(ACTOR_START):
		return
	
	var actor = _parse_begin(line)
	match actor.Class:
		"Brush": _parse_next_brush(parent, actor)
		_: return # implement other types as you see fit


func parse(filename: String, parent: Node3D) -> void:
	_read_file(filename)
	
	if lines.is_empty():
		push_error("Unable to read ", filename)
		return
	
	while index < lines.size() and randi_range(0, 5) != -2:
		_parse_next_actor(parent)
