extends CSGMesh3D
class_name Brush

const POLYGON_OPEN  = "Begin Polygon"
const POLYGON_CLOSE = "End Polygon"

var pre_pivot: Vector3
var location: Vector3

## Polygons in UE1 world space (post-transform, applied by BrushActor).
var poly_list: Array[Polygon] = []
		
func _ready() -> void:
	if poly_list.size() >= 16:
		create_stairs_meshes()
	else:
		var array_mesh = create_array_mesh()
		var mesh_instance = null
		if is_csg_brush():
			generate_csg_mesh(array_mesh)
		else:
			mesh_instance = generate_static_mesh(array_mesh)
		if Engine.is_editor_hint() and mesh_instance:
			mesh_instance.owner = get_tree().edited_scene_root

func generate_static_mesh(array_mesh: ArrayMesh) -> MeshInstance3D:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = assign_texture(array_mesh)
	var map_generator: T3DMapGenerator = get_parent().get_parent()
	map_generator.add_child(mesh_instance)
	return mesh_instance

func generate_csg_mesh(array_mesh: ArrayMesh, stairs_index: int = 0) -> void:
	var csg_operation = (get_parent() as BrushActor).csg_operation	
	if stairs_index > 0:
		self.name = "%s_%s_Stairs%s" % [self.name, csg_operation, stairs_index]
	else:
		self.name = "%s_%s" % [self.name, csg_operation]
	if csg_operation.contains("Subtract"):
		self.operation = CSGShape3D.OPERATION_SUBTRACTION
	self.mesh = assign_texture(array_mesh)
	## -> BrushActor -> T3DMapGenerator
	var map_generator: T3DMapGenerator = get_parent().get_parent()
	reparent(map_generator.csg_root)
	if Engine.is_editor_hint():
		owner = get_tree().edited_scene_root

func is_csg_brush() -> bool:
	return not (get_parent() as BrushActor).csg_operation.strip_edges().is_empty()

func assign_texture(mesh: ArrayMesh) -> ArrayMesh:
	for index in range(mesh.get_surface_count()):
		var texture_name = poly_list[index].texture
		var mat = Finder.get_material(texture_name)
		if mat:
			mesh.surface_set_name(index, texture_name)
			mesh.surface_set_material(index, mat)
	return mesh

func add_tri(arr:ArrayMesh, polygon: Polygon) -> ArrayMesh:
	var verts = PackedVector3Array(polygon.vertices)
	var norms = PackedVector3Array([
		polygon.normal,
		polygon.normal,
		polygon.normal
	])
	var uvs = PackedVector2Array([
		calc_uv(polygon.vertices[0], polygon),
		calc_uv(polygon.vertices[1], polygon),
		calc_uv(polygon.vertices[2], polygon),
	])
	var idxs = PackedInt32Array([
		0, 2, 1
	])
	return add_to_mesh(arr, verts, norms, uvs, idxs)
	
func add_quad(arr:ArrayMesh, polygon: Polygon) -> ArrayMesh:
	var verts = PackedVector3Array(polygon.vertices)
	var norms = PackedVector3Array([
		polygon.normal,
		polygon.normal,
		polygon.normal,
		polygon.normal
	])
	var uvs = PackedVector2Array([
		calc_uv(polygon.vertices[0], polygon),
		calc_uv(polygon.vertices[1], polygon),
		calc_uv(polygon.vertices[2], polygon),
		calc_uv(polygon.vertices[3], polygon)
	])
	var idxs = PackedInt32Array([0, 2, 1, 0, 3, 2])
	return add_to_mesh(arr, verts, norms, uvs, idxs)

func add_to_mesh(arr: ArrayMesh, verts, norms, uvs, idxs) -> ArrayMesh:
	var surface_array := []
	surface_array.resize(Mesh.ARRAY_MAX)
	surface_array[Mesh.ARRAY_VERTEX] = verts
	surface_array[Mesh.ARRAY_NORMAL] = norms
	surface_array[Mesh.ARRAY_TEX_UV] = uvs
	surface_array[Mesh.ARRAY_INDEX] = idxs
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	return arr

func create_array_mesh() -> ArrayMesh:
	var array_mesh = ArrayMesh.new()
	for polygon in poly_list:	
		if polygon.vertices.size() == 3:
			array_mesh = add_tri(array_mesh, polygon)
		elif polygon.vertices.size() == 4:
			array_mesh = add_quad(array_mesh, polygon)
		else:
			printerr("cannot construct polygon of size %s" % polygon.vertices.size())
	return array_mesh

func create_stairs_meshes() -> void:
	for index in range(len(poly_list)/4):
		var array_mesh = ArrayMesh.new()
		for poly in range(index*4, (index*4)+4):
			array_mesh = add_quad(array_mesh, poly_list[poly])
		generate_csg_mesh(array_mesh, index)

func calc_uv(vertex: Vector3, polygon: Polygon) -> Vector2:
	var rel := vertex - polygon.origin
	return Vector2(rel.dot(polygon.texture_u), rel.dot(polygon.texture_v))


func create(data: Array[String]) -> void:
	var poly_data: Array[String] = []
	var in_poly := false
	for line in data:
		if line.begins_with(POLYGON_OPEN):
			poly_data.clear()
			poly_data.append(line)
			in_poly = true
		elif line.begins_with(POLYGON_CLOSE):
			if poly_data.size() > 0:
				var poly := Polygon.new()
				poly.create(poly_data)
				poly_list.append(poly)
			in_poly = false
		elif in_poly:
			poly_data.append(line)
