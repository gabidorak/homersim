class_name PhysicsLayers
extends RefCounted
## Collision layer bits (names also set in Project Settings → Layer Names → 3D Physics).

const WORLD := 1  ## layer 1: level geometry
const PLAYERS := 2  ## layer 2: player bodies
const TRIGGERS := 4  ## layer 3: trigger areas (vents, later interactables)
