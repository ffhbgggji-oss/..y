extends Node3D

# Small mobile Verlet-cloth preview; deliberately limited in resolution.
const GRID_X := 8
const GRID_Y := 8
const SPACING := 0.16
const SOLVER_ITERATIONS := 3
const GRAVITY := Vector3(0.0, -2.0, 0.0)

var points := PackedVector3Array()
var previous := PackedVector3Array()
var links: Array[Vector2i] = []
var rest_lengths := PackedFloat32Array()
var cloth_mesh: ArrayMesh
var elapsed := 0.0

func _ready() -> void:
    _build_grid()
    _build_constraints()
    _build_mesh()

func _build_grid() -> void:
    for y in range(GRID_Y):
        for x in range(GRID_X):
            var point := Vector3((float(x) - float(GRID_X - 1) * 0.5) * SPACING, 2.8 - float(y) * SPACING, 0.0)
            points.append(point)
            previous.append(point)

func _build_constraints() -> void:
    for y in range(GRID_Y):
        for x in range(GRID_X):
            var index := y * GRID_X + x
            if x + 1 < GRID_X:
                _add_link(index, index + 1)
            if y + 1 < GRID_Y:
                _add_link(index, index + GRID_X)
            if x + 1 < GRID_X and y + 1 < GRID_Y:
                _add_link(index, index + GRID_X + 1)
                _add_link(index + 1, index + GRID_X)

func _add_link(a: int, b: int) -> void:
    links.append(Vector2i(a, b))
    rest_lengths.append(points[a].distance_to(points[b]))

func _build_mesh() -> void:
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "ClothMesh"
    cloth_mesh = ArrayMesh.new()
    mesh_instance.mesh = cloth_mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.88, 0.25, 0.31, 0.9)
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mesh_instance.material_override = material
    add_child(mesh_instance)
    _update_mesh()

func _process(delta: float) -> void:
    elapsed += delta
    var dt := minf(delta, 1.0 / 30.0)
    for i in range(points.size()):
        if _is_pinned(i):
            continue
        var current := points[i]
        var velocity := (points[i] - previous[i]) * 0.985
        previous[i] = current
        points[i] = current + velocity + GRAVITY * dt * dt
        points[i].x += sin(elapsed * 2.0 + float(i) * 0.15) * 0.0008

    for _iteration in range(SOLVER_ITERATIONS):
        for link_index in range(links.size()):
            var link := links[link_index]
            var a := link.x
            var b := link.y
            var delta_vector := points[b] - points[a]
            var distance := delta_vector.length()
            if distance <= 0.00001:
                continue
            var correction := delta_vector * ((distance - rest_lengths[link_index]) / distance) * 0.5
            if not _is_pinned(a):
                points[a] += correction
            if not _is_pinned(b):
                points[b] -= correction
    _update_mesh()

func _is_pinned(index: int) -> bool:
    return index < GRID_X

func _update_mesh() -> void:
    if cloth_mesh == null:
        return
    var indices := PackedInt32Array()
    for y in range(GRID_Y - 1):
        for x in range(GRID_X - 1):
            var a := y * GRID_X + x
            var b := a + 1
            var c := a + GRID_X
            var d := c + 1
            indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = points
    arrays[Mesh.ARRAY_INDEX] = indices
    cloth_mesh.clear_surfaces()
    cloth_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
