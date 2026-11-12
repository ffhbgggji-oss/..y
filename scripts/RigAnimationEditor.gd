extends Node
class_name RigAnimationEditor

## Optional skeletal editor module. Attach as a child of MainStudio to enable it.
const BONE_SCRIPT = preload("res://scripts/RigBoneController.gd")
const CAMERA_SCRIPT = preload("res://scripts/CameraKeyframeController.gd")
const UI_SCRIPT = preload("res://scripts/MobileAnimUI.gd")
const IMPORTER_SCRIPT = preload("res://scripts/AndroidModelImporter.gd")
const SERIALIZER_SCRIPT = preload("res://scripts/AnimationProjectSerializer.gd")
const TWO_D_EDITOR_SCRIPT = preload("res://scripts/TwoDAnimationEditor.gd")
const SAVE_FILE := "user://rig_animation.json"
const MAX_FRAMES := 2000

var studio: Node3D
var camera: Camera3D
var puppet_root: Node3D
var skeleton: Skeleton3D
var bones: RigBoneController
var camera_controller: CameraKeyframeController
var mobile_ui: MobileAnimUI
var importer: AndroidModelImporter
var frames: Array[Dictionary] = []
var current_frame := 0
var selected_bone := -1
var tool_mode := "rotate"
var is_playing := false
var playback_phase := 0.0
var playback_fps := 24.0
var active_pointer := -1
var pointer_mode := ""
var touches: Dictionary = {}
var last_pinch_distance := 0.0
var two_d_editor

func _ready() -> void:
    studio = get_parent() as Node3D
    if not is_instance_valid(studio):
        return
    # MainStudio creates its camera, puppet root and legacy controls in _ready().
    await get_tree().process_frame
    camera = studio.get_node_or_null("Camera3D") as Camera3D
    puppet_root = studio.get_node_or_null("PuppetRoot") as Node3D
    var legacy_ui := studio.get("ui_layer") as CanvasLayer
    if is_instance_valid(legacy_ui):
        legacy_ui.visible = false
    bones = BONE_SCRIPT.new()
    add_child(bones)
    camera_controller = CAMERA_SCRIPT.new()
    add_child(camera_controller)
    camera_controller.bind_camera(camera)
    importer = IMPORTER_SCRIPT.new()
    add_child(importer)
    importer.model_path_selected.connect(_import_model)
    importer.import_failed.connect(_on_import_failed)
    mobile_ui = UI_SCRIPT.new()
    add_child(mobile_ui)
    mobile_ui.import_requested.connect(importer.open_model_picker)
    mobile_ui.camera_reset_requested.connect(_reset_camera)
    mobile_ui.save_requested.connect(_save_project)
    mobile_ui.load_requested.connect(_load_project)
    mobile_ui.frame_add_requested.connect(_add_frame)
    mobile_ui.frame_duplicate_requested.connect(_duplicate_frame)
    mobile_ui.frame_delete_requested.connect(_delete_frame)
    mobile_ui.tweens_requested.connect(_generate_tweens)
    mobile_ui.play_requested.connect(_toggle_playback)
    mobile_ui.frame_changed.connect(_on_frame_changed)
    mobile_ui.tool_changed.connect(func(mode: String): tool_mode = mode)
    two_d_editor = TWO_D_EDITOR_SCRIPT.new()
    add_child(two_d_editor)
    two_d_editor.configure(studio, mobile_ui)
    mobile_ui.mode_2d_requested.connect(func(): two_d_editor.set_active(true))
    _refresh_skeleton()
    frames.append(_capture_frame("pose"))
    _refresh_timeline()
    mobile_ui.set_status("Импортируйте ригнутую GLB-модель. Твины создаются между двумя позами.")

func _process(delta: float) -> void:
    if two_d_editor != null and two_d_editor.active:
        return
    if not is_playing or frames.size() < 2:
        return
    playback_phase = fposmod(playback_phase + delta * playback_fps, float(frames.size()))
    var from_index := int(floor(playback_phase))
    var to_index := (from_index + 1) % frames.size()
    var weight := playback_phase - float(from_index)
    var a: Dictionary = frames[from_index]
    var b: Dictionary = frames[to_index]
    _refresh_skeleton()
    bones.apply_pose(bones.interpolate_pose(a.get("bones", {}), b.get("bones", {}), weight))
    camera_controller.apply_key(camera_controller.interpolate_keys(a.get("camera", {}), b.get("camera", {}), weight))
    current_frame = from_index
    mobile_ui.set_timeline(frames.size(), current_frame, str(a.get("kind", "pose")))

func _input(event: InputEvent) -> void:
    if (two_d_editor != null and two_d_editor.active) or is_playing or mobile_ui == null:
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            touches[touch.index] = touch.position
            if touches.size() == 1:
                _begin_pointer(touch.index, touch.position)
            elif touches.size() == 2:
                active_pointer = -1
                pointer_mode = "pinch"
                last_pinch_distance = _touch_distance()
        else:
            touches.erase(touch.index)
            if touch.index == active_pointer:
                active_pointer = -1
                pointer_mode = ""
            if touches.size() < 2:
                last_pinch_distance = 0.0
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if not touches.has(drag.index):
            return
        touches[drag.index] = drag.position
        if touches.size() >= 2:
            var distance := _touch_distance()
            if last_pinch_distance > 0.0 and distance > 0.0:
                camera_controller.pinch_zoom(last_pinch_distance, distance)
                _store_current_frame()
            last_pinch_distance = distance
        elif drag.index == active_pointer:
            _drag_pointer(drag.relative)
    elif event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            if mouse.pressed:
                _begin_pointer(-1, mouse.position)
            else:
                active_pointer = -1
                pointer_mode = ""
    elif event is InputEventMouseMotion and active_pointer == -1:
        _drag_pointer((event as InputEventMouseMotion).relative)

func _begin_pointer(pointer_id: int, position: Vector2) -> void:
    if position.y < mobile_ui.top_reserved or position.y > get_viewport().get_visible_rect().size.y - mobile_ui.bottom_reserved:
        return
    active_pointer = pointer_id
    if tool_mode == "camera":
        pointer_mode = "camera"
        return
    selected_bone = bones.pick_bone(camera, position, 80.0) if skeleton != null else -1
    pointer_mode = tool_mode if selected_bone >= 0 else "camera"
    if selected_bone >= 0:
        mobile_ui.set_status("%s — %s" % [tool_mode, bones.bone_name(selected_bone)])

func _drag_pointer(relative: Vector2) -> void:
    if pointer_mode == "camera":
        camera_controller.orbit_drag(relative)
        _store_current_frame()
        return
    if selected_bone < 0 or skeleton == null:
        return
    var changed := false
    match pointer_mode:
        "rotate": changed = bones.rotate_bone_from_drag(selected_bone, relative, camera)
        "move": changed = bones.move_bone_from_drag(selected_bone, relative, camera)
        "scale": changed = bones.scale_bone_from_drag(selected_bone, relative)
    if changed:
        _store_current_frame()

func _refresh_skeleton() -> void:
    if puppet_root == null:
        return
    skeleton = _find_skeleton(puppet_root)
    bones.bind_skeleton(skeleton)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _capture_frame(kind: String = "pose") -> Dictionary:
    return {"kind": kind, "bones": bones.capture_pose(), "camera": camera_controller.capture_key()}

func _apply_frame(index: int) -> void:
    if index < 0 or index >= frames.size():
        return
    _refresh_skeleton()
    bones.apply_pose(frames[index].get("bones", {}))
    camera_controller.apply_key(frames[index].get("camera", {}))

func _store_current_frame() -> void:
    if is_playing or frames.is_empty():
        return
    frames[current_frame] = _capture_frame(str(frames[current_frame].get("kind", "pose")))

func _add_frame() -> void:
    _stop_playback()
    if frames.size() >= MAX_FRAMES:
        mobile_ui.set_status("Достигнут лимит кадров")
        return
    frames.insert(current_frame + 1, _capture_frame("pose"))
    current_frame += 1
    _refresh_timeline()

func _duplicate_frame() -> void:
    if frames.size() >= MAX_FRAMES:
        return
    frames.insert(current_frame + 1, frames[current_frame].duplicate(true))
    current_frame += 1
    _apply_frame(current_frame)
    _refresh_timeline()

func _delete_frame() -> void:
    if frames.size() <= 1:
        return
    frames.remove_at(current_frame)
    current_frame = clampi(current_frame, 0, frames.size() - 1)
    _apply_frame(current_frame)
    _refresh_timeline()

func _generate_tweens(count: int) -> void:
    _stop_playback()
    if frames.size() < 2 or frames[current_frame].get("kind", "pose") == "tween":
        mobile_ui.set_status("Выберите начальную позу; следующая обычная поза должна быть после неё")
        return
    var end_index := -1
    for i in range(current_frame + 1, frames.size()):
        if frames[i].get("kind", "pose") != "tween":
            end_index = i
            break
    if end_index < 0:
        mobile_ui.set_status("Добавьте следующую позу перед созданием Tween")
        return
    var start: Dictionary = frames[current_frame]
    var finish: Dictionary = frames[end_index]
    var generated: Array[Dictionary] = []
    var safe_count := clampi(count, 1, 120)
    for step in range(1, safe_count + 1):
        var t := float(step) / float(safe_count + 1)
        generated.append({
            "kind": "tween",
            "bones": bones.interpolate_pose(start.get("bones", {}), finish.get("bones", {}), t),
            "camera": camera_controller.interpolate_keys(start.get("camera", {}), finish.get("camera", {}), t)
        })
    for i in range(end_index - 1, current_frame, -1):
        frames.remove_at(i)
    for i in range(generated.size()):
        frames.insert(current_frame + 1 + i, generated[i])
    current_frame += 1
    _apply_frame(current_frame)
    _refresh_timeline()
    mobile_ui.set_status("Создано %d промежуточных кадров" % safe_count)

func _on_frame_changed(value: float) -> void:
    _stop_playback()
    current_frame = clampi(int(value), 0, frames.size() - 1)
    _apply_frame(current_frame)
    _refresh_timeline()

func _toggle_playback() -> void:
    if frames.size() < 2:
        mobile_ui.set_status("Добавьте минимум два кадра")
        return
    is_playing = not is_playing
    playback_phase = float(current_frame)
    mobile_ui.set_playing(is_playing)

func _stop_playback() -> void:
    is_playing = false
    playback_phase = float(current_frame)
    if mobile_ui != null:
        mobile_ui.set_playing(false)

func _refresh_timeline() -> void:
    if mobile_ui != null:
        var kind := str(frames[current_frame].get("kind", "pose")) if not frames.is_empty() else "pose"
        mobile_ui.set_timeline(frames.size(), current_frame, kind)

func _reset_camera() -> void:
    camera_controller.reset_view()
    _store_current_frame()

func _import_model(path: String) -> void:
    if not FileAccess.file_exists(path):
        _on_import_failed("Файл не найден")
        return
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_file(path, state)
    if error != OK:
        _on_import_failed("GLTF не прочитан: %s" % error_string(error))
        return
    var imported := document.generate_scene(state)
    if imported == null or puppet_root == null:
        _on_import_failed("Не удалось создать модель или отсутствует PuppetRoot")
        return
    for child in puppet_root.get_children():
        child.queue_free()
    imported.name = "ImportedModel"
    puppet_root.add_child(imported)
    await get_tree().process_frame
    _refresh_skeleton()
    frames.clear()
    current_frame = 0
    frames.append(_capture_frame("pose"))
    _refresh_timeline()
    mobile_ui.set_status("Риг найден: %d костей" % skeleton.get_bone_count() if skeleton != null else "Модель загружена, но Skeleton3D не найден")

func _on_import_failed(message: String) -> void:
    if mobile_ui != null:
        mobile_ui.set_status("Импорт: " + message)

func _save_project() -> void:
    _store_current_frame()
    var error := SERIALIZER_SCRIPT.save_project(SAVE_FILE, frames, playback_fps)
    mobile_ui.set_status("Проект сохранён" if error == OK else "Ошибка сохранения: " + error_string(error))

func _load_project() -> void:
    var result: Dictionary = SERIALIZER_SCRIPT.load_project(SAVE_FILE)
    if not result.get("ok", false):
        mobile_ui.set_status(str(result.get("error", "Ошибка загрузки")))
        return
    _stop_playback()
    frames = result["frames"]
    playback_fps = float(result.get("fps", 24.0))
    current_frame = 0
    _apply_frame(current_frame)
    _refresh_timeline()

func _touch_distance() -> float:
    var points: Array = touches.values()
    if points.size() < 2:
        return 0.0
    return (points[0] as Vector2).distance_to(points[1] as Vector2)
