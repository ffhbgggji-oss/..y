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
signal mode_2d_requested

var top_reserved := 82.0
var bottom_reserved := 160.0
var play_button: Button
var frame_slider: HSlider
var tween_count: SpinBox
var status_label: Label
var tool_button: Button
var tool_mode := "rotate"

func _ready() -> void:
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

func _cycle_tool() -> void:
    if tool_mode == "rotate":
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
