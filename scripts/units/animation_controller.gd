## 动画控制器 — 通用单位动画组件。
##
## 挂载在单位节点下，持有 [AnimationPlayer] 引用并根据单位状态切换动画。
## 所有单位类型（工人、战士等）共用此组件。
##
## 使用方式：
##   [code]animation_controller.play("walk")[/code]
##   [code]animation_controller.play_work("plow", 2.0)[/code]
class_name AnimationController
extends Node

# ============================================================
# 4. @export 变量
# ============================================================

## 关联的动画播放器节点。
@export var animation_player: AnimationPlayer = null

# ============================================================
# 6. 私有变量
# ============================================================

## 当前正在播放的动画名称。
var _current_anim: StringName = &""

## 是否正在播放工作动画（单次动画，完成后切回 idle）。
var _is_work_anim: bool = false

# ============================================================
# 9. 公开方法
# ============================================================

## 播放指定动画（循环）。
## 如果已在播放相同动画则跳过，避免动画抖动。
func play(anim_name: StringName) -> void:
	if anim_name == _current_anim and not _is_work_anim:
		return
	if animation_player == null:
		return
	if not animation_player.has_animation(anim_name):
		push_warning("AnimationController: 动画 '%s' 不存在于 AnimationPlayer 中" % anim_name)
		return

	animation_player.play(anim_name)
	_current_anim = anim_name
	_is_work_anim = false

## 播放工作动画（单次播放，完成后自动切回 idle）。
## [param duration] 可选：动画持续时间（秒）。若不传则使用动画本身的长度。
func play_work(anim_name: StringName, duration: float = -1.0) -> void:
	if animation_player == null:
		return
	if not animation_player.has_animation(anim_name):
		push_warning("AnimationController: 工作动画 '%s' 不存在于 AnimationPlayer 中" % anim_name)
		return

	animation_player.play(anim_name)
	_current_anim = anim_name
	_is_work_anim = true

	# 若指定了持续时间，调整播放速度以匹配
	if duration > 0.0:
		var anim: Animation = animation_player.get_animation(anim_name)
		if anim and anim.length > 0.0:
			animation_player.speed_scale = anim.length / duration

## 停止当前动画。
func stop() -> void:
	if animation_player == null:
		return
	animation_player.stop()
	_current_anim = &""
	_is_work_anim = false
	animation_player.speed_scale = 1.0

## 是否正在播放工作动画。
func is_playing_work() -> bool:
	return _is_work_anim

## 返回当前动画名称。
func get_current_animation() -> StringName:
	return _current_anim
