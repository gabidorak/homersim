class_name LevelMap
extends Resource
## The top-down plan of a level for the in-game map (MapView): rooms, walls, doors, vents, ladders.
## For the plant it is written by tools/map/gen_plant.py next to the level (levels/plant/PlantMap.tres),
## from the same numbers as the level itself, so the two can't drift apart. The level points at it with
## a MapInfo node. Everything is in world metres on the ground plane: Vector2(x, z), +x east, +z south
## (north is up on the map). Segments are stored as pairs of points (start, end, start, end…).
## What moves or changes (players, machine health, cage occupants, pickups) isn't here: MapView reads
## it from the level's nodes while it draws.

@export var title := ""  ## English, translated when shown
@export var area := Rect2()  ## what the full map shows
@export var room_names := PackedStringArray()  ## English, translated when shown
@export var room_rects: Array[Rect2] = []
@export var room_colors := PackedColorArray()
@export var room_label_at := PackedVector2Array()  ## where each room's name goes
@export var walls := PackedVector2Array()  ## ground floor walls (pairs)
@export var fences := PackedVector2Array()  ## low outdoor walls (pairs)
@export var doors := PackedVector2Array()  ## doors anyone can open (pairs)
@export var keycard_doors := PackedVector2Array()  ## supervisors' keycard doors (pairs)
@export var windows := PackedVector2Array()  ## (pairs)
@export var vent_ducts := PackedVector2Array()  ## rats: ducts on the floor (pairs)
@export var raised_ducts := PackedVector2Array()  ## rats: ducts and ramps above the floor (pairs)
@export var vent_openings := PackedVector2Array()  ## rats: where a duct opens into a room
@export var ladders := PackedVector2Array()
@export var circles := PackedVector3Array()  ## round landmarks (the cooling tower): (x, z, radius)


## The room whose rectangle holds `point` (the last one listed wins, as it is drawn on top), or -1.
func room_at(point: Vector2) -> int:
	for i in range(room_rects.size() - 1, -1, -1):
		if room_rects[i].has_point(point):
			return i
	return -1
