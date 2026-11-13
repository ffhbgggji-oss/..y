extends CanvasLayer
class_name MobileAnimUI

signal import_requested
signal camera_reset_requested
signal save_requested
signal load_requested
signal frame_add_requested
signal frame_duplicate_requested
signal frame_delete_requested
signal tweens_requested(count: int)
signal play_requested
signal frame_changed(value: float)
signal tool_changed(mode: String)
signal rig_mode_changed(mode: String)
signal mp4_export_requested
signal mode_2d_requested
signal camera_mode_changed(mode: String)
signal camera_height_requested(amount: float)
signal bones_visibility_changed(visible: bool)
signal model_transform_requested(property_name: String, axis: String, value: float)
signal bone_axis_changed(axis: String)
signal audio_import_requested
signal audio_play_requested
signal audio_stop_requested
signal audio_remove_requested
signal audio_seek_changed(seconds: float)
signal audio_offset_changed(seconds: float)
signal audio_volume_changed(value: float)
signal audio_clip_selected(index: int)

var top_reserved := 224.0
var bottom_reserved := 160.0
var play_button: Button
var frame_slider: HSlider
var tween_count: SpinBox
var status_label: Label
var tool_button: Button
var tool_mode := "rotate"
var rig_mode := "FK"
var rig_mode_button: Button
var camera_mode := "animation"
var bones_visible := true
var camera_mode_button: Button
var bones_button: Button
var axis_selector: OptionButton
var model_property_selector: OptionButton
var model_axis_selector: OptionButton
var model_value: SpinBox
var audio_clip_selector: OptionButton
var audio_position_slider: HSlider
var audio_offset: SpinBox
var audio_volume: HSlider
var audio_time_label: Label

func _ready() -> void:
    visible = true
    _build_ui()

func _build_ui() -> void:
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(root)

    var top := PanelContainer.new()
    top.anchor_right = 1.0
    top.offset_left = 8
    top.offset_top = 8
    top.offset_right = -8
    top.offset_bottom = 72
    root.add_child(top)
    var top_row := HFlowContainer.new()
    top.add_child(top_row)
    var title := Label.new()
    title.text = "КУКОЛЬНАЯ 3D-АНИМАЦИЯ"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top_row.add_child(title)
    _button(top_row, "Импорт", func(): import_requested.emit())
    _button(top_row, "Камера", func(): camera_reset_requested.emit())
    _button(top_row, "Сохранить", func(): save_requested.emit())
    _button(top_row, "Загрузить", func(): load_requested.emit())
    _button(top_row, "2D", func(): mode_2d_requested.emit())
    tool_button = _button(top_row, "Поворот", _cycle_tool)
    camera_mode_button = _button(top_row, "Камера: Анимация", _cycle_camera_mode)
    _button(top_row, "Камера ↑", func(): camera_height_requested.emit(0.15))
    _button(top_row, "Камера ↓", func(): camera_height_requested.emit(-0.15))
    bones_button = _button(top_row, "Кости: Вкл", _toggle_bones)

    var tools_row := HFlowContainer.new()
    root.add_child(tools_row)
    tools_row.anchor_left = 0.0
    tools_row.anchor_right = 1.0
    tools_row.offset_left = 8
    tools_row.offset_top = 74
    tools_row.offset_right = -8
    tools_row.offset_bottom = 164
    var axis_label := Label.new()
    axis_label.text = "Ось:"
    tools_row.add_child(axis_label)
    axis_selector = OptionButton.new()
    axis_selector.add_item("Экран")
    axis_selector.add_item("X")
    axis_selector.add_item("Y")
    axis_selector.add_item("Z")
    axis_selector.item_selected.connect(_on_bone_axis_selected)
    tools_row.add_child(axis_selector)
    var model_label := Label.new()
    model_label.text = "Модель:"
    tools_row.add_child(model_label)
    model_property_selector = OptionButton.new()
    model_property_selector.add_item("Позиция")
    model_property_selector.add_item("Вращение")
    model_property_selector.add_item("Масштаб")
    tools_row.add_child(model_property_selector)
    model_axis_selector = OptionButton.new()
    model_axis_selector.add_item("X")
    model_axis_selector.add_item("Y")
    model_axis_selector.add_item("Z")
    model_axis_selector.add_item("Все")
    tools_row.add_child(model_axis_selector)
    model_value = SpinBox.new()
    model_value.min_value = -360.0
    model_value.max_value = 360.0
    model_value.step = 0.05
    model_value.value = 1.0
    model_value.custom_minimum_size = Vector2(88, 38)
    tools_row.add_child(model_value)
    _button(tools_row, "Применить", _apply_model_transform)
    rig_mode_button = _button(tools_row, "Режим: FK", _toggle_rig_mode)
    _button(tools_row, "Экспорт MP4", func(): mp4_export_requested.emit())

    var audio_row := HFlowContainer.new()
    root.add_child(audio_row)
    audio_row.anchor_left = 0.0
    audio_row.anchor_right = 1.0
    audio_row.offset_left = 8
    audio_row.offset_top = 166
    audio_row.offset_right = -8
    audio_row.offset_bottom = 224
    _button(audio_row, "＋ Аудио", func(): audio_import_requested.emit())
    _button(audio_row, "▶ Звук", func(): audio_play_requested.emit())
    _button(audio_row, "■", func(): audio_stop_requested.emit())
    audio_clip_selector = OptionButton.new()
    audio_clip_selector.custom_minimum_size = Vector2(130, 38)
    audio_clip_selector.item_selected.connect(func(index: int): audio_clip_selected.emit(index))
    audio_row.add_child(audio_clip_selector)
    _button(audio_row, "Удалить звук", func(): audio_remove_requested.emit())
    audio_offset = SpinBox.new()
    audio_offset.min_value = 0.0
    audio_offset.max_value = 3600.0
    audio_offset.step = 0.1
    audio_offset.suffix = " сек"
    audio_offset.custom_minimum_size = Vector2(100, 38)
    audio_offset.value_changed.connect(func(value: float): audio_offset_changed.emit(value))
    audio_row.add_child(audio_offset)
    audio_volume = HSlider.new()
    audio_volume.min_value = 0.0
    audio_volume.max_value = 1.0
    audio_volume.step = 0.05
    audio_volume.value = 1.0
    audio_volume.custom_minimum_size = Vector2(90, 38)
    audio_volume.value_changed.connect(func(value: float): audio_volume_changed.emit(value))
    audio_row.add_child(audio_volume)
    audio_position_slider = HSlider.new()
    audio_position_slider.min_value = 0.0
    audio_position_slider.max_value = 30.0
    audio_position_slider.step = 0.05
    audio_position_slider.custom_minimum_size = Vector2(180, 38)
    audio_position_slider.value_changed.connect(func(value: float): audio_seek_changed.emit(value))
    audio_row.add_child(audio_position_slider)
    audio_time_label = Label.new()
    audio_time_label.text = "Звук: 0.0 с"
    audio_row.add_child(audio_time_label)

    var bottom := PanelContainer.new()
    bottom.anchor_top = 1.0
    bottom.anchor_right = 1.0
    bottom.anchor_bottom = 1.0
    bottom.offset_left = 8
    bottom.offset_top = -154
    bottom.offset_right = -8
    bottom.offset_bottom = -8
    root.add_child(bottom)
    var layout := VBoxContainer.new()
    bottom.add_child(layout)
    var actions := HFlowContainer.new()
    layout.add_child(actions)
    play_button = _button(actions, "▶", func(): play_requested.emit())
    _button(actions, "+ Кадр", func(): frame_add_requested.emit())
    _button(actions, "Дубль", func(): frame_duplicate_requested.emit())
    _button(actions, "Удалить", func(): frame_delete_requested.emit())
    tween_count = SpinBox.new()
    tween_count.min_value = 1
    tween_count.max_value = 120
    tween_count.value = 12
    tween_count.step = 1
    tween_count.custom_minimum_size = Vector2(72, 40)
    actions.add_child(tween_count)
    _button(actions, "Tween", func(): tweens_requested.emit(int(tween_count.value)))

    frame_slider = HSlider.new()
    frame_slider.min_value = 0
    frame_slider.max_value = 0
    frame_slider.step = 1
    frame_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    frame_slider.value_changed.connect(func(value: float): frame_changed.emit(value))
    layout.add_child(frame_slider)
    status_label = Label.new()
    status_label.text = "Импортируйте ригнутую GLB-модель"
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(status_label)

func _button(parent: Control, caption: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size = Vector2(72, 38)
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _toggle_rig_mode() -> void:
    rig_mode = "IK" if rig_mode == "FK" else "FK"
    if rig_mode_button != null:
        rig_mode_button.text = "Режим: " + rig_mode
    if rig_mode == "IK":
        tool_mode = "ik"
        tool_button.text = "IK: цель"
    else:
        tool_mode = "rotate"
        tool_button.text = "Поворот"
    rig_mode_changed.emit(rig_mode)
    tool_changed.emit(tool_mode)

func _cycle_tool() -> void:
    if rig_mode == "IK":
        tool_mode = "ik"
        tool_button.text = "IK: цель"
    elif tool_mode == "rotate":
        tool_mode = "move"
        tool_button.text = "Перемещение"
    elif tool_mode == "move":
        tool_mode = "scale"
        tool_button.text = "Масштаб"
    else:
        tool_mode = "rotate"
        tool_button.text = "Поворот"
    tool_changed.emit(tool_mode)

func set_timeline(count: int, selected: int, kind: String = "pose") -> void:
    if frame_slider != null:
        frame_slider.max_value = maxi(0, count - 1)
        frame_slider.set_value_no_signal(clampi(selected, 0, maxi(0, count - 1)))
    if status_label != null:
        status_label.text = "%s %d / %d" % ["Твин" if kind == "tween" else "Кадр", selected + 1, count]

func set_playing(value: bool) -> void:
    if play_button != null:
        play_button.text = "⏸" if value else "▶"

func set_status(message: String) -> void:
    if status_label != null:
        status_label.text = message


func _cycle_camera_mode() -> void:
    camera_mode = "export" if camera_mode == "animation" else "animation"
    camera_mode_button.text = "Камера: Экспорт" if camera_mode == "export" else "Камера: Анимация"
    camera_mode_changed.emit(camera_mode)

func _toggle_bones() -> void:
    bones_visible = not bones_visible
    bones_button.text = "Кости: Вкл" if bones_visible else "Кости: Выкл"
    bones_visibility_changed.emit(bones_visible)

func _on_bone_axis_selected(index: int) -> void:
    var axis := "screen"
    if index > 0:
        axis = ["X", "Y", "Z"][index - 1]
    bone_axis_changed.emit(axis)

func _apply_model_transform() -> void:
    var properties := ["position", "rotation_degrees", "scale"]
    var axes := ["x", "y", "z", "all"]
    var property_name: String = str(properties[model_property_selector.selected])
    var axis: String = str(axes[model_axis_selector.selected])
    model_transform_requested.emit(property_name, axis, model_value.value)


func set_audio_clips(names: PackedStringArray, selected: int) -> void:
    if audio_clip_selector == null:
        return
    audio_clip_selector.clear()
    for item in names:
        audio_clip_selector.add_item(item)
    if selected >= 0 and selected < names.size():
        audio_clip_selector.select(selected)

func set_audio_position(seconds: float, duration: float) -> void:
    if audio_position_slider == null:
        return
    audio_position_slider.max_value = maxf(1.0, duration)
    audio_position_slider.set_value_no_signal(seconds)
    audio_time_label.text = "Звук: %.1f / %.1f с" % [seconds, duration]

func set_audio_offset(seconds: float) -> void:
    if audio_offset != null:
        audio_offset.set_value_no_signal(seconds)
