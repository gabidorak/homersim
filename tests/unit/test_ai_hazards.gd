extends GutTest
## M10 phase E: the hazard checks the AI driver uses (AiHazards): is a point inside a jet or a box,
## and should a bot wait at the edge of a cyclic hazard.

func test_box_hazards_are_centred_and_on_the_floor() -> void:
	var size := Vector3(3.0, 0.5, 3.0)  # a puddle
	assert_true(AiHazards.inside(AiHazards.Shape.BOX, Vector3(1.4, 0.0, -1.4), size))
	assert_false(AiHazards.inside(AiHazards.Shape.BOX, Vector3(1.6, 0.0, 0.0), size), "beside it")
	assert_true(AiHazards.inside(AiHazards.Shape.BOX, Vector3(1.6, 0.0, 0.0), size, 0.3), "within the margin")
	assert_true(AiHazards.inside(AiHazards.Shape.BOX, Vector3(0.0, -0.3, 0.0), size), "feet a little below the box")
	assert_false(AiHazards.inside(AiHazards.Shape.BOX, Vector3(0.0, 2.0, 0.0), size), "on a catwalk above it")


func test_jets_blow_along_plus_z_from_the_nozzle() -> void:
	var size := Vector3(1.8, 1.6, 4.0)
	assert_true(AiHazards.inside(AiHazards.Shape.JET, Vector3(0.0, 0.0, 3.5), size))
	assert_false(AiHazards.inside(AiHazards.Shape.JET, Vector3(0.0, 0.0, -0.5), size), "behind the nozzle")
	assert_false(AiHazards.inside(AiHazards.Shape.JET, Vector3(0.0, 0.0, 4.5), size), "past its reach")
	assert_false(AiHazards.inside(AiHazards.Shape.JET, Vector3(1.2, 0.0, 2.0), size), "to the side")


func test_wait_for_the_off_phase() -> void:
	assert_true(AiHazards.should_wait(true, 2.0, 1.2), "live")
	assert_true(AiHazards.should_wait(false, 0.8, 1.2), "switching on before we'd get through")
	assert_false(AiHazards.should_wait(false, 2.5, 1.2), "off for long enough: go")
