extends RefCounted
class_name AnimationProjectSerializer

## Versioned JSON serializer for frame-based skeletal animation.
const FORMAT_VERSION := 2

static func save_project(path: String, frames: Array, fps: float) -> Error:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    var payload := {
        "version": FORMAT_VERSION,
        "fps": maxf(1.0, fps),
        "frames": _encode_frames(frames)
    }
    file.store_string(JSON.stringify(payload))
    return file.get_error()

static func load_project(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "Файл проекта не найден"}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {"ok": false, "error": "Не удалось открыть файл проекта"}
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK or not (parser.data is Dictionary):
        return {"ok": false, "error": "Некорректный JSON проекта"}
    var data: Dictionary = parser.data
    var version := int(data.get("version", 0))
    if version < 1 or version > FORMAT_VERSION:
        return {"ok": false, "error": "Неподдерживаемая версия проекта"}
    var frames: Array[Dictionary] = []
    for raw in data.get("frames", []):
        if raw is Dictionary:
            frames.append(_decode_frame(raw))
    if frames.is_empty():
        return {"ok": false, "error": "В проекте нет кадров"}
    return {"ok": true, "fps": float(data.get("fps", 8.0)), "frames": frames}

static func _encode_frames(frames: Array) -> Array:
    var output: Array = []
    for frame in frames:
        var bones_json: Dictionary = {}
        var bone_poses: Dictionary = frame.get("bones", {})
        for key in bone_poses.keys():
            var pose: Dictionary = bone_poses[key]
            var p: Vector3 = pose.get("position", Vector3.ZERO)
            var q: Quaternion = pose.get("rotation", Quaternion.IDENTITY)
            var s: Vector3 = pose.get("scale", Vector3.ONE)
            bones_json[str(key)] = {"p": [p.x, p.y, p.z], "q": [q.x, q.y, q.z, q.w], "s": [s.x, s.y, s.z]}
        var camera_pose: Dictionary = frame.get("camera", {})
        var cp: Vector3 = camera_pose.get("position", Vector3.ZERO)
        var cq: Quaternion = camera_pose.get("rotation", Quaternion.IDENTITY)
        output.append({
            "kind": frame.get("kind", "pose"),
            "bones": bones_json,
            "camera": {"p": [cp.x, cp.y, cp.z], "q": [cq.x, cq.y, cq.z, cq.w]}
        })
    return output

static func _decode_frame(raw: Dictionary) -> Dictionary:
    var bones: Dictionary = {}
    var raw_bones: Dictionary = raw.get("bones", {})
    for key in raw_bones.keys():
        var pose: Dictionary = raw_bones[key]
        if not pose.has("p") or not pose.has("q") or not pose.has("s"):
            continue
        var p: Array = pose["p"]
        var q: Array = pose["q"]
        var s: Array = pose["s"]
        if p.size() < 3 or q.size() < 4 or s.size() < 3:
            continue
        bones[str(key)] = {
            "position": Vector3(p[0], p[1], p[2]),
            "rotation": Quaternion(q[0], q[1], q[2], q[3]).normalized(),
            "scale": Vector3(s[0], s[1], s[2])
        }
    var camera_pose := {"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY}
    var raw_camera: Dictionary = raw.get("camera", {})
    if raw_camera.has("p") and raw_camera.has("q"):
        var cp: Array = raw_camera["p"]
        var cq: Array = raw_camera["q"]
        if cp.size() >= 3 and cq.size() >= 4:
            camera_pose = {
                "position": Vector3(cp[0], cp[1], cp[2]),
                "rotation": Quaternion(cq[0], cq[1], cq[2], cq[3]).normalized()
            }
    var kind := str(raw.get("kind", "pose"))
    if kind != "tween":
        kind = "pose"
    return {"kind": kind, "bones": bones, "camera": camera_pose}
