extends Node
class_name AudioTimeline

signal status_changed(message: String)
signal clips_changed(names: PackedStringArray, selected: int)
signal position_changed(seconds: float, duration: float)

const DATA_FILE := "user://cartoonstudio_audio_timeline.json"
const AUDIO_DIR := "user://CartoonStudioAudio"

var clips: Array[Dictionary] = []
var selected_clip := -1
var timeline_position := 0.0
var timeline_duration := 30.0
var is_playing := false
var master_volume := 1.0
var players: Dictionary = {}
var started: Dictionary = {}
var file_dialog: FileDialog

func _ready() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIO_DIR))
    _load_data()

func _process(delta: float) -> void:
    if not is_playing:
        return
    var previous := timeline_position
    timeline_position += delta
    _start_due_clips(previous, timeline_position)
    if timeline_position >= timeline_duration:
        stop()
    position_changed.emit(timeline_position, timeline_duration)

func request_import() -> void:
    if OS.has_feature("android"):
        var plugin = Engine.get_singleton("GodotAndroidFilePicker") if Engine.has_singleton("GodotAndroidFilePicker") else null
        if plugin != null and plugin.has_method("open_audio_picker"):
            plugin.open_audio_picker()
            return
        status_changed.emit("Android audio picker недоступен. Пересоберите APK с обновлённым плагином.")
        return
    if file_dialog == null:
        file_dialog = FileDialog.new()
        file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        file_dialog.access = FileDialog.ACCESS_FILESYSTEM
        file_dialog.add_filter("*.wav, *.ogg, *.mp3", "Audio files")
        file_dialog.file_selected.connect(add_audio_file)
        add_child(file_dialog)
    file_dialog.popup_centered_ratio(0.85)

func add_audio_file(source_path: String) -> void:
    if not FileAccess.file_exists(source_path):
        status_changed.emit("Аудиофайл не найден")
        return
    var extension := source_path.get_extension().to_lower()
    if not ["wav", "ogg", "mp3"].has(extension):
        status_changed.emit("Поддерживаются WAV, OGG и MP3")
        return
    var safe_name := source_path.get_file().validate_filename()
    var destination := AUDIO_DIR.path_join("%d_%s" % [Time.get_ticks_msec(), safe_name])
    var error := DirAccess.copy_absolute(source_path, ProjectSettings.globalize_path(destination))
    if error != OK:
        status_changed.emit("Не удалось скопировать аудио: " + error_string(error))
        return
    var stream := _load_stream(destination)
    if stream == null:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
        status_changed.emit("Не удалось прочитать аудио")
        return
    var clip := {
        "name": source_path.get_file(),
        "path": destination,
        "start": timeline_position,
        "volume": 1.0,
        "duration": stream.get_length()
    }
    clips.append(clip)
    selected_clip = clips.size() - 1
    timeline_duration = maxf(timeline_duration, float(clip.start) + float(clip.duration) + 2.0)
    _save_data()
    _emit_clips()
    status_changed.emit("Добавлено аудио: " + str(clip.name))

func select_clip(index: int) -> void:
    if index >= 0 and index < clips.size():
        selected_clip = index
        _emit_clips()

func set_selected_start(seconds: float) -> void:
    if selected_clip < 0 or selected_clip >= clips.size():
        return
    clips[selected_clip].start = maxf(0.0, seconds)
    _recalculate_duration()
    _save_data()
    _emit_clips()

func set_master_volume(value: float) -> void:
    master_volume = clampf(value, 0.0, 1.0)
    for player in players.values():
        (player as AudioStreamPlayer).volume_db = linear_to_db(maxf(0.001, master_volume))

func remove_selected() -> void:
    if selected_clip < 0 or selected_clip >= clips.size():
        return
    stop()
    var path := str(clips[selected_clip].path)
    if FileAccess.file_exists(path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    clips.remove_at(selected_clip)
    selected_clip = mini(selected_clip, clips.size() - 1)
    _recalculate_duration()
    _save_data()
    _emit_clips()
    status_changed.emit("Аудиоклип удалён")

func play() -> void:
    if clips.is_empty():
        status_changed.emit("Сначала добавьте аудиофайл")
        return
    _stop_players()
    started.clear()
    is_playing = true
    _start_due_clips(timeline_position - 0.0001, timeline_position)
    status_changed.emit("Воспроизведение звуковой дорожки")

func stop() -> void:
    is_playing = false
    _stop_players()
    status_changed.emit("Звуковая дорожка остановлена")

func seek(seconds: float) -> void:
    timeline_position = clampf(seconds, 0.0, timeline_duration)
    if is_playing:
        play()
    position_changed.emit(timeline_position, timeline_duration)

func _start_due_clips(previous: float, current: float) -> void:
    for i in range(clips.size()):
        if started.has(i):
            continue
        var clip: Dictionary = clips[i]
        var start := float(clip.get("start", 0.0))
        var duration := float(clip.get("duration", 0.0))
        if current < start:
            continue
        var stream := _load_stream(str(clip.get("path", "")))
        if stream == null:
            started[i] = true
            continue
        var player := AudioStreamPlayer.new()
        player.name = "AudioClip_%d" % i
        player.stream = stream
        player.volume_db = linear_to_db(maxf(0.001, master_volume * float(clip.get("volume", 1.0))))
        add_child(player)
        players[i] = player
        var offset := maxf(0.0, current - start)
        if offset < duration:
            player.play(offset)
        started[i] = true

func _stop_players() -> void:
    for player in players.values():
        if is_instance_valid(player):
            (player as AudioStreamPlayer).stop()
            (player as AudioStreamPlayer).queue_free()
    players.clear()

func _load_stream(path: String) -> AudioStream:
    if not FileAccess.file_exists(path):
        return null
    match path.get_extension().to_lower():
        "wav": return AudioStreamWAV.load_from_file(path)
        "ogg": return AudioStreamOggVorbis.load_from_file(path)
        "mp3": return AudioStreamMP3.load_from_file(path)
    return null

func _recalculate_duration() -> void:
    timeline_duration = 30.0
    for clip in clips:
        timeline_duration = maxf(timeline_duration, float(clip.get("start", 0.0)) + float(clip.get("duration", 0.0)) + 2.0)

func _emit_clips() -> void:
    var names := PackedStringArray()
    for clip in clips:
        names.append(str(clip.get("name", "Audio")))
    clips_changed.emit(names, selected_clip)

func _save_data() -> void:
    var file := FileAccess.open(DATA_FILE, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify({"clips": clips, "duration": timeline_duration}))

func _load_data() -> void:
    if not FileAccess.file_exists(DATA_FILE):
        return
    var file := FileAccess.open(DATA_FILE, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        clips.clear()
        for item in parsed.get("clips", []):
            if item is Dictionary and FileAccess.file_exists(str(item.get("path", ""))):
                clips.append(item)
        _recalculate_duration()
        _emit_clips()
