extends RefCounted
class_name ObjRuntimeImporter

## Lightweight runtime OBJ importer for Godot 4.2.
## Imports geometry, UVs and vertex normals. OBJ materials/MTL textures are not
## resolved at runtime yet; a neutral material is assigned to the resulting mesh.

var last_error := ""

func import_file(path: String) -> Node3D:
    last_error = ""
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        last_error = "Не удалось открыть OBJ: " + error_string(FileAccess.get_open_error())
        return null

    var vertices: Array[Vector3] = []
    var uvs: Array[Vector2] = []
    var normals: Array[Vector3] = []
    var surface := SurfaceTool.new()
    surface.begin(Mesh.PRIMITIVE_TRIANGLES)
    var face_count := 0

    while not file.eof_reached():
        var line := file.get_line().strip_edges()
        if line.is_empty() or line.begins_with("#"):
            continue
        line = line.replace("\t", " ")
        var parts := line.split(" ", false)
        if parts.is_empty():
            continue
        match parts[0]:
            "v":
                if parts.size() >= 4:
                    vertices.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
            "vt":
                if parts.size() >= 3:
                    uvs.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
            "vn":
                if parts.size() >= 4:
                    normals.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()).normalized())
            "f":
                if parts.size() < 4:
                    continue
                var face: Array[Dictionary] = []
                for token in parts.slice(1):
                    var fields := token.split("/", true)
                    var vi := _resolve_index(fields[0], vertices.size())
                    if vi < 0 or vi >= vertices.size():
                        face.clear()
                        break
                    var ti := -1
                    var ni := -1
                    if fields.size() > 1 and not fields[1].is_empty():
                        ti = _resolve_index(fields[1], uvs.size())
                    if fields.size() > 2 and not fields[2].is_empty():
                        ni = _resolve_index(fields[2], normals.size())
                    face.append({"v": vi, "t": ti, "n": ni})
                if face.size() < 3:
                    continue
                # Fan triangulation handles triangles and most convex n-gons.
                for i in range(1, face.size() - 1):
                    var tri: Array[Dictionary] = [face[0], face[i], face[i + 1]]
                    var p0: Vector3 = vertices[int(tri[0].v)]
                    var p1: Vector3 = vertices[int(tri[1].v)]
                    var p2: Vector3 = vertices[int(tri[2].v)]
                    var face_normal := (p1 - p0).cross(p2 - p0).normalized()
                    if face_normal.length_squared() < 0.000001:
                        face_normal = Vector3.UP
                    for corner in tri:
                        var uv_index := int(corner.t)
                        var normal_index := int(corner.n)
                        if uv_index >= 0 and uv_index < uvs.size():
                            surface.set_uv(uvs[uv_index])
                        else:
                            surface.set_uv(Vector2.ZERO)
                        if normal_index >= 0 and normal_index < normals.size():
                            surface.set_normal(normals[normal_index])
                        else:
                            surface.set_normal(face_normal)
                        surface.add_vertex(vertices[int(corner.v)])
                    face_count += 1

    if vertices.is_empty() or face_count == 0:
        last_error = "OBJ не содержит корректных граней (f)"
        return null

    var mesh := surface.commit()
    if mesh == null:
        last_error = "Не удалось создать 3D-сетку из OBJ"
        return null

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.78, 0.80, 0.84)
    material.roughness = 0.8
    mesh.surface_set_material(0, material)

    var root := Node3D.new()
    root.name = "ImportedOBJ"
    var instance := MeshInstance3D.new()
    instance.name = "OBJMesh"
    instance.mesh = mesh
    root.add_child(instance)
    return root

func _resolve_index(raw: String, count: int) -> int:
    if raw.is_empty():
        return -1
    var value := raw.to_int()
    if value > 0:
        return value - 1
    if value < 0:
        return count + value
    return -1
