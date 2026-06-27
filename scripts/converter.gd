@tool
extends Node3D
class_name T3DMapGenerator

@export_tool_button("Generate", "MeshInstance3D") var generate_action = generate
@export_tool_button("Generate Rooms", "CSGBox3D") var generate_rooms_action = generate_rooms_button
@export_tool_button("Generate Tunnels", "Path3D") var generate_tunnels_action = generate_tunnels_button
@export_tool_button("Expand subtractions", "MeshInstance3D") var expand_subtractions = expand_borderline_subtractions
@export_tool_button("Wipe", "Remove") var delete_action = wipe_existing_data

@export_file("*.t3d") var unreal_text_3d_filename_path: String = ""

var mesh_root: CSGCombiner3D

var _page_slide_tween : Tween

func generate():
	wipe_existing_data()
	create_mesh_root()
	Finder.compile_texture_array()
	
	var parser = ForwardParser.new()
	add_child(parser)
	parser.parse(unreal_text_3d_filename_path, mesh_root)
	parser.queue_free()


func expand_borderline_subtractions() -> void:
	print("Expanding borderline subtractions")
	if not mesh_root:
		return
	
	var static_mesh := mesh_root.bake_static_mesh()
	var tri_mesh := static_mesh.generate_triangle_mesh()
	
	var targets := mesh_root.get_children()
	targets.reverse()
	for child in targets:
		var csg := child as CSGMesh3D
		if not csg:
			continue
		if csg.operation != CSGShape3D.OPERATION_SUBTRACTION:
			continue
		
		# assuming a lot of things here, such as that it's a block
		#if csg.name != "Brush1220":
		#	continue
		
		var aabb := csg.mesh.get_aabb()
		var center := aabb.get_center()
		
		var t := csg.transform
		var a := t * center
		
		var scale := Vector3.ONE
		for direction in [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			var abs_dir : Vector3 = abs(direction)
			var outside := center
			outside += 0.5 * direction * abs_dir.dot(aabb.size) + 4.0 * direction
			var b := t * outside
			
			var poke_out = tri_mesh.intersect_segment(a, b)
			var poke_in = tri_mesh.intersect_segment(b, a)
			if not poke_in or not poke_out:
				continue
			
			# do they hit two different faces?
			if poke_in.face_index == poke_out.face_index:
				continue
			
			# are the faces relatively close together?
			if poke_in.position.distance_to(poke_out.position) > 0.25:
				continue
			
			var width : float = abs_dir.dot(aabb.size)
			scale *= Vector3.ONE - abs_dir
			scale += ((width + 1.0) / width) * abs_dir
		
		if scale == Vector3.ONE:
			continue
		
		var prepos := csg.global_position
		csg.transform = csg.transform.scaled(scale)
		csg.global_position = prepos
		
		print("Correction applied to ", csg.name)
		# wait for csg update and rebake (SLOW)
		await get_tree().process_frame
		static_mesh = mesh_root.bake_static_mesh()
		tri_mesh = static_mesh.generate_triangle_mesh()
	
	print("subtractions fixed(?)")


## Okay so CSGs, fuck me...
## Unreal Engine produces levels that start off as a hunk of marble void
## First brush is a subtract that carves out the map area (ignore this)
## Approach could be AABB testing against adds and subtracts, if a subtract intersects and its
## overall volume is smaller than the add, then group them together into a CSGCombiner
func organise_csgs():
	## Create a node_group for adds that don't intersect a subtract
	var adds = mesh_root.find_children("*CSG_Add", "CSGMesh3D")
	var subtracts = mesh_root.find_children("*CSG_Subtract", "CSGMesh3D")
	var void_subtract = subtracts.pop_at(0)
	void_subtract.queue_free()
	
	## Node group for adds that dont intersect any subs
	generate_non_intersecting_geometry(adds, subtracts)
	
	# Group adds and subtracts that form a room shape
	generate_rooms(adds, subtracts)
	
	# Group adds and subtracts that intersect and share face textures
	subtracts = mesh_root.find_children("*CSG_Subtract", "CSGMesh3D", false)
	generate_tunnels(adds, subtracts)
	
	#combine_adds_with_length_between(50000, 1000000, subtracts)
	#combine_adds_with_length_between(10000, 49999, subtracts)
	#combine_adds_with_length_between(5000, 9999, subtracts)
	#combine_adds_with_length_between(1000, 4999, subtracts)
	
			
	### Group large adds (> 50s) with intersecting adds that are 80% scale
	#adds = mesh_root.find_children("*CSG_Add", "CSGMesh3D", false).filter(func(x): x.get_aabb().size.length_squared() > 50)
	#print("Count of unparented adds is %s" % [len(adds)])
	#print("Count of unparented subs is %s" % [len(subtracts)])
	#index = 0
	#for add: CSGMesh3D in adds:	
		#print("Add size is %s" % add.get_aabb().size.length_squared())
		#var active_combiner = CSGCombiner3D.new()
		#active_combiner.name = "CSG_Group%s" % index
		#mesh_root.add_child(active_combiner)
		#mark_editor(active_combiner)
		#add.reparent(active_combiner)
		#for compare_add: CSGMesh3D in adds:
			#var a = add.mesh.get_aabb()
			#var b = compare_add.mesh.get_aabb()
			#if a.encloses(b) and (b.size.length_squared() > a.size.length_squared()*0.8) and add.get_parent() is not CSGCombiner3D:
				#add.reparent(active_combiner)
		#index += 1
			#
	### Pass two: Group subtracts into the large adds	
	#adds = mesh_root.find_children("*CSG_Add", "CSGMesh3D", true)
	#print("Count of unparented adds is %s" % [len(adds)])
	#print("Count of unparented subs is %s" % [len(subtracts)])
	#index = 0
	#for sub: CSGMesh3D in subtracts:
		#if sub.get_aabb().size.length_squared() > 50:
			#for add: CSGMesh3D in adds:
				#var a = add.mesh.get_aabb()
				#var b = sub.mesh.get_aabb()
				#if a.encloses(b) and add.get_parent() is CSGCombiner3D:
					#sub.reparent(add)
	
	### First pass: Group the adds together that are enclosed
	#var index = 1
	#for add: CSGMesh3D in adds:
		#if add.get_parent() is not CSGCombiner3D:
			#var active_combiner = CSGCombiner3D.new()
			#active_combiner.name = "CSG_Group%s" % index
			#mesh_root.add_child(active_combiner)
			#mark_editor(active_combiner)
			#add.reparent(active_combiner)
			#index += 1
			#for compare_add in adds:
				#if compare_add.get_parent() is CSGCombiner3D:
					#continue
				#var a = add.mesh.get_aabb()
				#var b = compare_add.mesh.get_aabb()
				#if a.encloses(b):
					#compare_add.reparent(active_combiner)
					#
	### Second pass: Adds that enclose subs
	#var combiners = mesh_root.find_children("CSG_Group*","CSGCombiner3D", false)
	#for combiner: CSGCombiner3D in combiners:
		#for add: CSGMesh3D in combiner.get_children():
			#for sub: CSGMesh3D in subtracts:
				#if sub.get_parent() is CSGCombiner3D:
					#continue
				#var a = add.mesh.get_aabb()
				#var b = sub.mesh.get_aabb()
				#if a.encloses(b):
					#sub.reparent(combiner)
					
	## Second pass: Adds that intersect other adds
	#var orphaned_adds = mesh_root.find_children("CSG_Group*","CSGCombiner3D", false).filter(func(x): return x.get_child_count() == 1)
	#print("Count of orphaned adds is %s" % [len(orphaned_adds)])
	#for add: CSGMesh3D in adds:
		#for combiner: CSGCombiner3D in orphaned_adds:
			#var orphaned_add = combiner.get_child(0)
			#var a = add.mesh.get_aabb()
			#var b = orphaned_add.mesh.get_aabb()
			#if a.intersects(b):
				#orphaned_add.reparent(combiner)
				#break

func generate_rooms_button():
	var adds = mesh_root.find_children("*CSG_Add", "CSGMesh3D")
	var subtracts = mesh_root.find_children("*CSG_Subtract", "CSGMesh3D")
	generate_rooms(adds, subtracts)

func generate_tunnels_button():
	var adds = mesh_root.find_children("*CSG_Add", "CSGMesh3D")
	var subtracts = mesh_root.find_children("*CSG_Subtract", "CSGMesh3D")
	generate_tunnels(adds, subtracts)

func generate_non_intersecting_geometry(adds, subtracts):
	var non_intersecting = Node3D.new()
	non_intersecting.name = "solid_geometry"
	mesh_root.add_child(non_intersecting)
	mark_editor(non_intersecting)
	
	var index = 0
	for add: CSGMesh3D in adds:
		var intersects = false
		for sub: CSGMesh3D in subtracts:
			var a = add.mesh.get_aabb()
			var b = sub.mesh.get_aabb()
			if a.intersects(b):
				intersects = true
				break
		if not intersects:
			add.name = "Static_%s" % index
			add.reparent(non_intersecting)
			index += 1

## Test that a subtract is enclosed in an add volume with size of 10m^3
func generate_rooms(adds, subtracts):
	var index = 0
	for sub: CSGMesh3D in subtracts:
		var intersecting: Array[CSGMesh3D] = []
		for add: CSGMesh3D in adds:
			var a = add.mesh.get_aabb()
			var b = sub.mesh.get_aabb()
			if a.encloses(b) and b.size.length_squared() > 1000:
				intersecting.append(add)
		if len(intersecting) > 0:
			var active_combiner = CSGCombiner3D.new()
			active_combiner.name = "RoomGroup_%s" % index
			mesh_root.add_child(active_combiner)
			mark_editor(active_combiner)
			sub.reparent(active_combiner)
			for add in intersecting:
				add.reparent(active_combiner)
			index += 1


func generate_tunnels(adds, subtracts):
	var index = 0
	for sub: CSGMesh3D in subtracts:
		var intersecting: Array[CSGMesh3D] = []
		for add: CSGMesh3D in adds:
			var a = add.mesh.get_aabb()
			var b = sub.mesh.get_aabb()
			if a.intersects(b) and surface_compare(add.mesh, sub.mesh):			
				intersecting.append(add)
		if len(intersecting) > 0:
			var active_combiner = CSGCombiner3D.new()
			active_combiner.name = "TunnelGroup_%s" % index
			mesh_root.add_child(active_combiner)
			mark_editor(active_combiner)
			sub.reparent(active_combiner)
			for add in intersecting:
				if add.get_parent() is not CSGCombiner3D:
					add.reparent(active_combiner)
				else:
					sub.reparent(add.get_parent())
					break
			index += 1

func surface_compare(mesh_a: ArrayMesh, mesh_b: ArrayMesh) -> bool:
	for a in mesh_a.get_surface_count():
		for b in mesh_b.get_surface_count():
			if mesh_a.surface_get_name(a) == mesh_b.surface_get_name(b):
				return true
	return false


func combine_adds_with_length_between(min, max, subtracts):
	## Form a combiner group of the largest adds (> 50000, maybe the ground)
	var adds = mesh_root.find_children("*CSG_Add", "CSGMesh3D", false).filter(func(x):
		var length = x.mesh.get_aabb().size.length_squared()
		return length >= min and length <= max)
	var active_combiner = CSGCombiner3D.new()
	active_combiner.name = "CSG_Group_Over%s" % min
	mesh_root.add_child(active_combiner)
	mark_editor(active_combiner)
	for add: CSGMesh3D in adds:	
		add.reparent(active_combiner)
		print("Add size is %s" % add.mesh.get_aabb().size.length_squared())
		for sub in subtracts:
			var a = add.mesh.get_aabb()
			var b = sub.mesh.get_aabb()
			if a.encloses(b) and sub.get_parent() is not CSGCombiner3D:
				sub.reparent(active_combiner)


func mark_editor(node: Node3D):
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root

func create_mesh_root():
	mesh_root = CSGCombiner3D.new()
	mesh_root.name = "mesh_root"
	var ue_scale = 1.0 / 52.5
	mesh_root.basis = Basis(Vector3(ue_scale, 0.0, 0.0), Vector3(0.0, 0.0, ue_scale), Vector3(0.0, ue_scale, 0.0))
	add_child(mesh_root)
	mark_editor(mesh_root)

func wipe_existing_data():
	for child in get_children():
		remove_child(child)
		child.queue_free()
	EditorInterface.mark_scene_as_unsaved()
