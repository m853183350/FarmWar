## 音效控制器 — 通用单位音效组件。
##
## 挂载在单位节点下，持有 [AudioStreamPlayer2D] 引用并管理音效播放。
## 支持一次性音效和循环音效（如脚步声）。
##
## 若音频资源缺失，会输出 warning 并跳过播放，不中断游戏逻辑。
##
## 使用方式：
##   [code]audio_controller.play_sfx(load("res://assets/audio/sfx/plow.ogg"))[/code]
##   [code]var footstep_player: AudioStreamPlayer2D = audio_controller.play_looping(footstep_stream)[/code]
##   [code]audio_controller.stop_looping(footstep_player)[/code]
class_name AudioController
extends Node

# ============================================================
# 4. @export 变量
# ============================================================

## 主音效播放器节点。
@export var audio_player: AudioStreamPlayer2D = null

# ============================================================
# 6. 私有变量
# ============================================================

## 当前活跃的循环音效播放器列表。
var _looping_players: Array[AudioStreamPlayer2D] = []

# ============================================================
# 9. 公开方法 — 一次性音效
# ============================================================

## 播放一次性音效。
## [param stream] 音频流资源。若为 null 或无效则输出 warning 并跳过。
## [param volume_db] 音量偏移（分贝），0.0 为原始音量。
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		push_warning("AudioController: 音频流为 null，跳过播放")
		return
	if audio_player == null:
		push_warning("AudioController: audio_player 未设置，跳过播放")
		return

	audio_player.stream = stream
	audio_player.volume_db = volume_db
	audio_player.play()

# ============================================================
# 9. 公开方法 — 循环音效
# ============================================================

## 播放循环音效（如行走脚步声）。
## 创建一个新的 [AudioStreamPlayer2D] 子节点并开始循环播放。
## 返回该播放器句柄，供后续 [method stop_looping] 停止使用。
func play_looping(stream: AudioStream) -> AudioStreamPlayer2D:
	if stream == null:
		push_warning("AudioController: 音频流为 null，无法启动循环播放")
		return null

	var player: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = audio_player.bus if audio_player else &"Master"
	player.finished.connect(_on_looping_finished.bind(player))
	add_child(player)
	player.play()
	_looping_players.append(player)
	return player

## 停止指定的循环音效播放器。
func stop_looping(player: AudioStreamPlayer2D) -> void:
	if player == null:
		return
	if player in _looping_players:
		_looping_players.erase(player)
	player.stop()
	player.queue_free()

## 停止所有循环音效。
func stop_all_looping() -> void:
	for player: AudioStreamPlayer2D in _looping_players:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	_looping_players.clear()

# ============================================================
# 10. 私有方法
# ============================================================

## 循环音效播放完成时的回调（重新播放实现循环）。
func _on_looping_finished(player: AudioStreamPlayer2D) -> void:
	if is_instance_valid(player) and player in _looping_players:
		player.play()
