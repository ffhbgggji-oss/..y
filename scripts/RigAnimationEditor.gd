extends Node
class_name RigAnimationEditor

## Optional skeletal editor module. Attach as a child of MainStudio to enable it.
const BONE_SCRIPT = preload("res://scripts/RigBoneController.gd")
const CAMERA_SCRIPT = preload("res://scripts/CameraKeyframeController.gd")
const UI_SCRIPT = preload("res://scripts/MobileAnimUI.gd")
const IMPORTER_SCRIPT = preload("res://scripts/AndroidModelImporter.gd")
const SERIALIZER_SCRIPT = preload("res://scripts/AnimationProjectSerializer.gd")
const TWO_D_EDITOR_SCRIPT = preload("res://scripts/TwoDAnimationEditor.gd")
const SKELETON_OVERLAY_SCRIPT = preload("res://scripts/SkeletonOverlay3D.gd")
const BONE_GIZMO_SCRIPT = preload("res://scripts/BoneTransformGizmo.gd")
const AUDIO_TIMELINE_SCRIPT = preload("res://scripts/AudioTimeline.gd")
const OBJ_IMPORTER_SCRIPT = preload("res://scripts/ObjRuntimeImporter.gd")
const SAVE_FILE := "user://rig_animation.json"
const MAX_FRAMES := 2000

var studio: Node3D
var camera: Camera3D
var puppet_root: Node3D
var skeleton: Skeleton3D
var bones: RigBoneController
var camera_controller: CameraKeyframeController
var export_camera: Camera3D
var export_camera_controller: CameraKeyframeController
var active_camera_mode := "animation"
var skeleton_overlay: SkeletonOverlay3D
var bone_gizmo: BoneTransformGizmo
var bones_visible := true
var bone_axis_mode := "screen"
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
var last_touch_midpoint := Vector2.ZERO
var ik_drag_plane := Plane(Vector3.FORWARD, Vector3.ZERO)
var audio_timeline
var two_d_editor
var mp4_exporting := false

func _ready() -> void:
    studio = get_parent() as Node3D
    if not is_instance_valid(studio):
        return
    # MainStudio creates its camera, puppet root and legacy controls in _ready().
    await get_tree().process_frame
    camera = studio.get_node_or_null("Camera3D") as Camera3D
    puppet_root = studio.get_node_or_null("PuppetRoot") as Node3D
    _load_model_transform_state()
    # Keep the original controls visible until the replacement UI is fully
    # created. If any optional editor module fails during startup, the app
    # still has usable controls instead of opening as a bare 3D viewport.
    var legacy_ui := studio.get("ui_layer") as CanvasLayer
    if is_instance_valid(legacy_ui):
        legacy_ui.visible = true
    bones = BONE_SCRIPT.new()
    add_child(bones)
    camera_controller = CAMERA_SCRIPT.new()
    add_child(camera_controller)
    camera_controller.bind_camera(camera)
    _create_export_camera()
    skeleton_overlay = SKELETON_OVERLAY_SCRIPT.new()
    skeleton_overlay.name = "SkeletonOverlay3D"
    studio.add_child(skeleton_overlay)
    importer = IMPORTER_SCRIPT.new()
    add_child(importer)
    importer.model_path_selected.connect(_import_model)
    importer.import_failed.connect(_on_import_failed)
    mobile_ui = UI_SCRIPT.new()
    mobile_ui.name = "MobileAnimUI"
    mobile_ui.layer = 20
    mobile_ui.visible = true
    mobile_ui.process_mode = Node.PROCESS_MODE_ALWAYS
    add_child(mobile_ui)
    # Wait one frame so CanvasLayer/Control layout is initialized before
    # hiding the legacy UI and before calculating touch-safe viewport zones.
    await get_tree().process_frame
    mobile_ui.visible = true
    bone_gizmo = BONE_GIZMO_SCRIPT.new()
    bone_gizmo.name = "BoneTransformGizmo"
    mobile_ui.add_child(bone_gizmo)
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
    mobile_ui.tool_changed.connect(func(mode: String):
        tool_mode = mode
        _update_bone_gizmo()
    )
    mobile_ui.rig_mode_changed.connect(_set_rig_mode)
    mobile_ui.mp4_export_requested.connect(_export_mp4)
    mobile_ui.camera_mode_changed.connect(_set_camera_mode)
    mobile_ui.camera_height_requested.connect(_adjust_active_camera_height)
    mobile_ui.bones_visibility_changed.connect(_set_bones_visible)
    mobile_ui.model_transform_requested.connect(_set_model_transform)
    mobile_ui.bone_axis_changed.connect(func(axis: String): bone_axis_mode = axis)
    audio_timeline = AUDIO_TIMELINE_SCRIPT.new()
    add_child(audio_timeline)
    audio_timeline.status_changed.connect(mobile_ui.set_status)
    audio_timeline.clips_changed.connect(mobile_ui.set_audio_clips)
    audio_timeline.position_changed.connect(mobile_ui.set_audio_position)
    mobile_ui.audio_import_requested.connect(audio_timeline.request_import)
    mobile_ui.audio_play_requested.connect(audio_timeline.play)
    mobile_ui.audio_stop_requested.connect(audio_timeline.stop)
    mobile_ui.audio_remove_requested.connect(audio_timeline.remove_selected)
    mobile_ui.audio_seek_changed.connect(audio_timeline.seek)
    mobile_ui.audio_offset_changed.connect(audio_timeline.set_selected_start)
    mobile_ui.audio_volume_changed.connect(audio_timeline.set_master_volume)
    mobile_ui.audio_clip_selected.connect(_on_audio_clip_selected)
    if Engine.has_singleton("GodotAndroidFilePicker"):
        var audio_picker = Engine.get_singleton("GodotAndroidFilePicker")
        if audio_picker.has_signal("audio_selected"):
            audio_picker.audio_selected.connect(audio_timeline.add_audio_file)
    var loaded_audio_names := PackedStringArray()
    for audio_clip in audio_timeline.clips:
        loaded_audio_names.append(str(audio_clip.get("name", "Audio")))
    mobile_ui.set_audio_clips(loaded_audio_names, audio_timeline.selected_clip)
    mobile_ui.set_audio_position(audio_timeline.timeline_position, audio_timeline.timeline_duration)
    two_d_editor = TWO_D_EDITOR_SCRIPT.new()
    add_child(two_d_editor)
    two_d_editor.configure(studio, mobile_ui)
    mobile_ui.mode_2d_requested.connect(func(): two_d_editor.set_active(true))
    _refresh_skeleton()
    frames.append(_capture_frame("pose"))
    _refresh_timeline()
    mobile_ui.set_status("Импортируйте ригнутую GLB-модель. Твины создаются между двумя позами.")
    # Hide the old UI only after the new CanvasLayer is alive and populated.
    if is_instance_valid(legacy_ui):
        legacy_ui.visible = false
    # Ensure the editor camera is the active viewport camera at startup.
    if is_instance_valid(camera):
        camera.current = true
    if is_instance_valid(export_camera):
        export_camera.current = false
    set_process_input(true)

func _process(delta: float) -> void:
    if two_d_editor != null and two_d_editor.active:
        return
    if is_playing and frames.size() >= 2:
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
    _update_bone_gizmo()

func _update_bone_gizmo() -> void:
    if bone_gizmo == null:
        return
    if selected_bone < 0 or skeleton == null or selected_bone >= skeleton.get_bone_count():
        bone_gizmo.update_gizmo(Vector2(-10000.0, -10000.0), tool_mode, false)
        return
    var active_cam := _active_camera()
    var world_position := skeleton.global_transform * skeleton.get_bone_global_pose(selected_bone).origin
    if active_cam.is_position_behind(world_position):
        bone_gizmo.update_gizmo(Vector2(-10000.0, -10000.0), tool_mode, false)
        return
    var screen_position := active_cam.unproject_position(world_position)
    var screen_height := get_viewport().get_visible_rect().size.y
    var visible := screen_position.y >= mobile_ui.top_reserved and screen_position.y <= screen_height - mobile_ui.bottom_reserved
    bone_gizmo.update_gizmo(screen_position, tool_mode, visible)

func _input(event: InputEvent) -> void:
    if (mp4_exporting or (two_d_editor != null and two_d_editor.active)) or is_playing or mobile_ui == null:
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
                last_touch_midpoint = _touch_midpoint()
        else:
            touches.erase(touch.index)
            if touch.index == active_pointer:
                active_pointer = -1
                pointer_mode = ""
            if touches.size() < 2:
                last_pinch_distance = 0.0
                last_touch_midpoint = Vector2.ZERO
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if not touches.has(drag.index):
            return
        touches[drag.index] = drag.position
        if touches.size() >= 2:
            var distance := _touch_distance()
            var midpoint := _touch_midpoint()
            if last_pinch_distance > 0.0 and distance > 0.0:
                var controller := _active_camera_controller()
                controller.pan_drag(midpoint - last_touch_midpoint)
                controller.pinch_zoom(last_pinch_distance, distance)
                _store_active_camera_change()
            last_touch_midpoint = midpoint
            last_pinch_distance = distance
        elif drag.index == active_pointer:
            _drag_pointer(drag.relative, drag.position)
    elif event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            if mouse.pressed:
                _begin_pointer(-1, mouse.position)
            else:
                active_pointer = -1
                pointer_mode = ""
    elif event is InputEventMouseMotion and active_pointer == -1:
        _drag_pointer((event as InputEventMouseMotion).relative, (event as InputEventMouseMotion).position)

func _begin_pointer(pointer_id: int, position: Vector2) -> void:
    if mobile_ui == null:
        return
    var viewport_height := get_viewport().get_visible_rect().size.y
    if position.y < mobile_ui.top_reserved or position.y > viewport_height - mobile_ui.bottom_reserved:
        return
    active_pointer = pointer_id
    # Camera mode is always available, including for the built-in sample model
    # which has no Skeleton3D. A tap/drag on empty space or a non-rigged model
    # therefore still rotates the scene camera.
    if tool_mode == "camera" or skeleton == null:
        selected_bone = -1
        pointer_mode = "camera"
        return
    selected_bone = bones.pick_bone(_active_camera(), position, 80.0)
    pointer_mode = tool_mode if selected_bone >= 0 else "camera"
    if selected_bone >= 0:
        mobile_ui.set_status("%s — %s" % [tool_mode, bones.bone_name(selected_bone)])
        if pointer_mode == "ik":
            var end_position: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(selected_bone).origin
            var plane_normal := _active_camera().global_basis.z.normalized()
            ik_drag_plane = Plane(plane_normal, plane_normal.dot(end_position))
            mobile_ui.set_status("IK: перетащите выбранную конечную кость к цели")
    if skeleton_overlay != null:
        skeleton_overlay.configure(skeleton, selected_bone, bones_visible)
    _update_bone_gizmo()

func _drag_pointer(relative: Vector2, screen_position: Vector2 = Vector2.ZERO) -> void:
    if pointer_mode == "camera":
        var controller := _active_camera_controller()
        if controller != null:
            controller.orbit_drag(relative)
            _store_active_camera_change()
        return
    if selected_bone < 0 or skeleton == null:
        return
    var changed := false
    match pointer_mode:
        "rotate": changed = bones.rotate_bone_axis_from_drag(selected_bone, relative, _active_camera(), bone_axis_mode)
        "move": changed = bones.move_bone_axis_from_drag(selected_bone, relative, _active_camera(), bone_axis_mode)
        "scale": changed = bones.scale_bone_axis_from_drag(selected_bone, relative, bone_axis_mode)
        "ik":
            var active_cam := _active_camera()
            if is_instance_valid(active_cam):
                var ray_origin := active_cam.project_ray_origin(screen_position)
                var ray_direction := active_cam.project_ray_normal(screen_position)
                var target_point = ik_drag_plane.intersects_ray(ray_origin, ray_direction)
                if target_point is Vector3:
                    changed = bones.solve_ik_ccd(selected_bone, target_point, 18, 0.012, 16)
    if changed:
        _store_current_frame()
        if skeleton_overlay != null:
            skeleton_overlay.configure(skeleton, selected_bone, bones_visible)

func _set_rig_mode(mode: String) -> void:
    if mode == "IK":
        tool_mode = "ik"
        mobile_ui.set_status("IK: выберите конечную кость (кисть/стопу) и перетащите её")
    else:
        tool_mode = "rotate"
        mobile_ui.set_status("FK: вращайте выбранные кости вручную")
    _update_bone_gizmo()

func _export_mp4() -> void:
    if mp4_exporting:
        return
    if frames.size() < 2:
        mobile_ui.set_status("Для MP4 нужно минимум 2 кадра")
        return
    if not Engine.has_singleton("GodotAndroidFilePicker"):
        mobile_ui.set_status("MP4-экспорт доступен в Android APK с обновлённым плагином")
        return
    var encoder = Engine.get_singleton("GodotAndroidFilePicker")
    if not encoder.has_method("start_mp4_export") or not encoder.has_method("encode_mp4_frame") or not encoder.has_method("finish_mp4_export"):
        mobile_ui.set_status("Android MP4 encoder не найден. Пересоберите APK с новым плагином")
        return

    _stop_playback()
    mp4_exporting = true
    var saved_frame := current_frame
    var saved_camera_mode := active_camera_mode
    var saved_camera_current := camera.current if is_instance_valid(camera) else false
    var saved_export_current := export_camera.current if is_instance_valid(export_camera) else false
    var viewport_size := get_viewport().get_visible_rect().size
    var out_width := maxi(2, int(viewport_size.x))
    var out_height := maxi(2, int(viewport_size.y))
    out_width -= out_width % 2
    out_height -= out_height % 2
    var fps := clampi(int(playback_fps), 12, 60)

    if is_instance_valid(export_camera):
        export_camera.current = true
    if is_instance_valid(camera):
        camera.current = false
    var started: bool = encoder.start_mp4_export(out_width, out_height, fps)
    if not started:
        mp4_exporting = false
        camera.current = saved_camera_current
        if is_instance_valid(export_camera): export_camera.current = saved_export_current
        mobile_ui.set_status("Не удалось запустить MP4-кодировщик")
        return

    var failed := false
    for i in range(frames.size()):
        _apply_frame(i)
        if is_instance_valid(export_camera):
            export_camera.current = true
        await RenderingServer.frame_post_draw
        var frame_image := get_viewport().get_texture().get_image()
        if frame_image == null or frame_image.is_empty():
            failed = true
            break
        if frame_image.get_width() != out_width or frame_image.get_height() != out_height:
            frame_image.resize(out_width, out_height, Image.INTERPOLATE_LANCZOS)
        frame_image.convert(Image.FORMAT_RGBA8)
        var frame_bytes := frame_image.get_data()
        var encoded: bool = encoder.encode_mp4_frame(frame_bytes)
        if not encoded:
            failed = true
            break
        if i % 5 == 0:
            mobile_ui.set_status("Экспорт MP4: %d / %d кадров" % [i + 1, frames.size()])
        await get_tree().process_frame

    var finished: bool = encoder.finish_mp4_export()
    current_frame = saved_frame
    _apply_frame(current_frame)
    active_camera_mode = saved_camera_mode
    if is_instance_valid(camera): camera.current = saved_camera_current
    if is_instance_valid(export_camera): export_camera.current = saved_export_current
    mp4_exporting = false

    if failed or not finished:
        mobile_ui.set_status("Ошибка экспорта MP4. Попробуйте меньшее разрешение или FPS")
        return
    var output_uri := ""
    if encoder.has_method("publish_mp4"):
        output_uri = str(encoder.publish_mp4())
    if output_uri.is_empty():
        output_uri = str(encoder.get_mp4_export_path()) if encoder.has_method("get_mp4_export_path") else ""
    mobile_ui.set_status("MP4 сохранён в Movies/CartoonStudio: " + output_uri)

func _refresh_skeleton() -> void:
    if puppet_root == null:
        return
    skeleton = _find_skeleton(puppet_root)
    bones.bind_skeleton(skeleton)
    if skeleton_overlay != null:
        skeleton_overlay.configure(skeleton, selected_bone, bones_visible)

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
    _active_camera_controller().reset_view()
    _store_active_camera_change()

func _create_export_camera() -> void:
    if not is_instance_valid(camera) or not is_instance_valid(studio):
        return
    export_camera = Camera3D.new()
    export_camera.name = "ExportCamera3D"
    export_camera.fov = camera.fov
    export_camera.near = camera.near
    export_camera.far = camera.far
    export_camera.projection = camera.projection
    export_camera.global_transform = camera.global_transform
    studio.add_child(export_camera)
    export_camera_controller = CAMERA_SCRIPT.new()
    add_child(export_camera_controller)
    export_camera_controller.bind_camera(export_camera)
    _load_export_camera_state()
    export_camera.current = false

func _active_camera() -> Camera3D:
    return export_camera if active_camera_mode == "export" and export_camera != null else camera

func _active_camera_controller() -> CameraKeyframeController:
    if active_camera_mode == "export" and export_camera_controller != null:
        return export_camera_controller
    return camera_controller

func _store_active_camera_change() -> void:
    if active_camera_mode == "animation":
        _store_current_frame()
    else:
        _save_export_camera_state()

func _set_camera_mode(mode: String) -> void:
    active_camera_mode = "export" if mode == "export" else "animation"
    if active_camera_mode == "export":
        export_camera.current = true
        camera.current = false
        mobile_ui.set_status("Камера экспорта: настройте отдельный ракурс")
    else:
        camera.current = true
        export_camera.current = false
        mobile_ui.set_status("Камера анимации: ракурс записывается в ключевые кадры")

func _adjust_active_camera_height(amount: float) -> void:
    _active_camera_controller().adjust_target_height(amount)
    _store_active_camera_change()

func _set_bones_visible(value: bool) -> void:
    bones_visible = value
    if skeleton_overlay != null:
        skeleton_overlay.configure(skeleton, selected_bone, bones_visible)
    mobile_ui.set_status("Отображение костей включено" if value else "Отображение костей выключено")

func _set_model_transform(property_name: String, axis: String, value: float) -> void:
    if not is_instance_valid(puppet_root):
        return
    var vector: Vector3 = puppet_root.get(property_name)
    match axis:
        "x": vector.x = value
        "y": vector.y = value
        "z": vector.z = value
        "all": vector = Vector3(value, value, value)
    if property_name == "scale":
        vector.x = clampf(vector.x, 0.05, 20.0)
        vector.y = clampf(vector.y, 0.05, 20.0)
        vector.z = clampf(vector.z, 0.05, 20.0)
    puppet_root.set(property_name, vector)
    _save_model_transform_state()
    mobile_ui.set_status("Параметр модели обновлён: %s %s" % [property_name, axis.to_upper()])

func _save_model_transform_state() -> void:
    if not is_instance_valid(puppet_root):
        return
    var config := ConfigFile.new()
    config.set_value("model", "position", puppet_root.position)
    config.set_value("model", "rotation_degrees", puppet_root.rotation_degrees)
    config.set_value("model", "scale", puppet_root.scale)
    config.save("user://cartoonstudio_model_transform.cfg")

func _load_model_transform_state() -> void:
    if not is_instance_valid(puppet_root):
        return
    var config := ConfigFile.new()
    if config.load("user://cartoonstudio_model_transform.cfg") != OK:
        return
    puppet_root.position = config.get_value("model", "position", puppet_root.position)
    puppet_root.rotation_degrees = config.get_value("model", "rotation_degrees", puppet_root.rotation_degrees)
    puppet_root.scale = config.get_value("model", "scale", puppet_root.scale)

func _save_export_camera_state() -> void:
    if export_camera_controller == null:
        return
    var config := ConfigFile.new()
    config.set_value("camera", "target", export_camera_controller.target)
    config.set_value("camera", "distance", export_camera_controller.distance)
    config.set_value("camera", "yaw", export_camera_controller.yaw)
    config.set_value("camera", "pitch", export_camera_controller.pitch)
    config.save("user://cartoonstudio_export_camera.cfg")

func _load_export_camera_state() -> void:
    var config := ConfigFile.new()
    if config.load("user://cartoonstudio_export_camera.cfg") != OK:
        return
    export_camera_controller.target = config.get_value("camera", "target", export_camera_controller.target)
    export_camera_controller.distance = float(config.get_value("camera", "distance", export_camera_controller.distance))
    export_camera_controller.yaw = float(config.get_value("camera", "yaw", export_camera_controller.yaw))
    export_camera_controller.pitch = float(config.get_value("camera", "pitch", export_camera_controller.pitch))
    export_camera_controller.update_orbit()

func _import_model(path: String) -> void:
    if not FileAccess.file_exists(path):
        _on_import_failed("Файл не найден")
        return
    if path.get_extension().to_lower() == "obj":
        var obj_importer := OBJ_IMPORTER_SCRIPT.new()
        var obj_scene: Node3D = obj_importer.import_file(path)
        if obj_scene == null:
            _on_import_failed(obj_importer.last_error)
            return
        _replace_imported_model(obj_scene, "OBJ-модель загружена (статическая сетка)")
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
    await _replace_imported_model(imported, "Модель GLB/GLTF загружена")

func _replace_imported_model(imported: Node3D, success_message: String) -> void:
    if imported == null or puppet_root == null:
        _on_import_failed("Не удалось создать модель или отсутствует PuppetRoot")
        return
    for child in puppet_root.get_children():
        child.queue_free()
    selected_bone = -1
    _update_bone_gizmo()
    imported.name = "ImportedModel"
    puppet_root.add_child(imported)
    await get_tree().process_frame
    _refresh_skeleton()
    frames.clear()
    current_frame = 0
    frames.append(_capture_frame("pose"))
    _refresh_timeline()
    if skeleton != null:
        mobile_ui.set_status("%s. Найдено костей: %d" % [success_message, skeleton.get_bone_count()])
    else:
        mobile_ui.set_status(success_message + ". Скелет не найден (OBJ обычно статический).")

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

func _on_audio_clip_selected(index: int) -> void:
    if audio_timeline == null or index < 0 or index >= audio_timeline.clips.size():
        return
    audio_timeline.select_clip(index)
    mobile_ui.set_audio_offset(float(audio_timeline.clips[index].get("start", 0.0)))

func _touch_midpoint() -> Vector2:
    var points: Array = touches.values()
    if points.size() < 2:
        return Vector2.ZERO
    return ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5

func _touch_distance() -> float:
    var points: Array = touches.values()
    if points.size() < 2:
        return 0.0
    return (points[0] as Vector2).distance_to(points[1] as Vector2)
