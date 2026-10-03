extends GutTest
## The in-game map's plan of the plant (levels/plant/PlantMap.tres, written by tools/map/gen_plant.py):
## it loads, its arrays line up, everything sits inside the map, every area the level names is a room
## on it (the minimap shows that name), and the level points at it.

const PLAN := "res://levels/plant/PlantMap.tres"
const POI_DIR := "res://levels/plant/pois/"


func _plan() -> LevelMap:
	return load(PLAN) as LevelMap


func test_plan_loads_and_lines_up() -> void:
	var plan := _plan()
	assert_not_null(plan)
	var rooms := plan.room_names.size()
	assert_gt(rooms, 10)
	assert_eq([plan.room_rects.size(), plan.room_colors.size(), plan.room_label_at.size()], [rooms, rooms, rooms])
	for pairs: PackedVector2Array in [plan.walls, plan.fences, plan.doors, plan.keycard_doors, plan.windows,
			plan.vent_ducts, plan.raised_ducts]:
		assert_eq(pairs.size() % 2, 0, "segments come in pairs")
	assert_gt(plan.walls.size(), 100)
	assert_gt(plan.doors.size(), 0)
	assert_eq(plan.keycard_doors.size(), 4, "the two keycard doors")
	assert_gt(plan.vent_openings.size(), 6)
	assert_ne(plan.title, "")


func test_everything_is_inside_the_map() -> void:
	var plan := _plan()
	var area := plan.area.grow(0.01)
	for i in plan.room_rects.size():
		assert_true(area.encloses(plan.room_rects[i]), plan.room_names[i])
		assert_true(plan.room_rects[i].grow(0.01).has_point(plan.room_label_at[i]), "%s: its name is inside it" % plan.room_names[i])
	for points: PackedVector2Array in [plan.walls, plan.doors, plan.vent_ducts, plan.vent_openings, plan.ladders]:
		for p in points:
			assert_true(area.has_point(p), "%s is on the map" % p)


func test_every_area_of_the_level_is_a_room() -> void:
	var names := Array(_plan().room_names)
	var display := RegEx.create_from_string("(?m)^display_name = \"([^\"]*)\"$")
	var areas := RegEx.create_from_string("(?m)^area_names = PackedStringArray\\((.*)\\)$")
	var checked := 0
	for file in DirAccess.get_files_at(POI_DIR):
		if not file.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string(POI_DIR + file)
		var root := text.substr(0, text.find("\n[node ", text.find("[node ") + 1))  # (the root node's block)
		var listed := areas.search(root)
		var area_names: Array = []
		if listed != null:
			area_names = Array(listed.get_string(1).trim_prefix("\"").trim_suffix("\"").split("\", \""))
		elif display.search(root) != null:
			area_names = [display.search(root).get_string(1)]
		for area: String in area_names:
			if area == "Vents":
				continue  # (the ducts: MapOverlay says "In the vents" from the VentVolumes instead)
			assert_has(names, area, "%s (%s) has a room on the map" % [area, file])
			checked += 1
	assert_gt(checked, 12)


func test_room_at() -> void:
	var plan := _plan()
	assert_eq(plan.room_names[plan.room_at(Vector2(0, 10))], "Control Room")
	assert_eq(plan.room_names[plan.room_at(Vector2(-41, -30))], "Substation", "drawn over the yard, so it wins")
	assert_eq(plan.room_names[plan.room_at(Vector2(0, -30))], "Yard")
	assert_eq(plan.room_at(Vector2(0, 100)), -1)


func test_the_plant_points_at_its_plan() -> void:
	var text := FileAccess.get_file_as_string("res://levels/plant/Plant.tscn")
	assert_string_contains(text, "path=\"%s\"" % PLAN)
	assert_string_contains(text, "path=\"res://levels/map_info.gd\"")


func test_the_feed_moves_under_the_minimap() -> void:
	var before := Config.show_minimap
	Config.show_minimap = true
	assert_gt(MapOverlay.feed_top(), MapOverlay.MARGIN + MapOverlay.MINIMAP_SIZE)
	Config.show_minimap = false
	assert_eq(MapOverlay.feed_top(), 30.0)
	Config.show_minimap = before
