extends Node
class_name T3DFileParser

const ACTOR_OPEN = "Begin Actor"
const ACTOR_CLOSE = "End Actor"

var parsed_actor_data: Array[Actor]

func parse(map_file: String) -> Array[Actor]:
	if map_file.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(map_file)
		if not ResourceUID.has_id(uid):
			printerr("Error: failed to retrieve path for UID (%s)" % map_file)
			return []
		map_file = ResourceUID.get_id_path(uid)
		
	var file: FileAccess = FileAccess.open(map_file, FileAccess.READ)
	if not file:
		file = FileAccess.open(map_file + ".import", FileAccess.READ)
		if file:
			map_file += ".import"
		else:
			printerr("Error: Failed to open map file (" + map_file + ")")
			return parsed_actor_data
			
	var actor_data: Array[String] = []
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with(ACTOR_OPEN):
			actor_data.clear()
			actor_data.append(line)
		elif line.begins_with(ACTOR_CLOSE):
			parsed_actor_data.append(parse_actor(actor_data))
		else:
			actor_data.append(line)
			
	return parsed_actor_data

func parse_actor(actor_data: Array[String]) -> Actor:
	var descriptor = actor_data[0].replace("Begin Actor ","").split(" ")
	var actor: Actor = null
	match descriptor[0]:
		"Class=LevelInfo": actor = LevelInfoActor.new()
		"Class=Brush": actor = BrushActor.new()
		"Class=Light": actor = LightActor.new()
	if actor:
		actor.create(actor_data.slice(1))
	else:
		actor = EmptyActor.new()
	actor.name = descriptor[1].replace("Name=","")
	return actor
