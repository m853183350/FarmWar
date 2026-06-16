## Debug UI — 调试 UI 总控制器。
##
## 作为 Autoload 注册在项目设置中。负责统一管理
## 所有调试叠加层的显示/隐藏和翻页。
##
## F3 开关显示，F4/F5 翻页。所有输入在此集中处理，
## 通过调用子面板的公共方法同步控制所有 debug 层 UI。
##
## 子面板（各自为独立 CanvasLayer，挂载在 Layer 5）：
##   - [DebugOverlay]：右侧调试数据面板
##   - [DebugOverlayLeft]：左侧调试数据面板（工人任务等）
extends Node

# ============================================================
# 6. 私有变量
# ============================================================

var _overlay_right: CanvasLayer = null
var _overlay_left: CanvasLayer = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 获取 autoload 实例并重新挂载为子节点
	_overlay_right = get_node("/root/DebugOverlay") as CanvasLayer
	_overlay_left = get_node("/root/DebugOverlayLeft") as CanvasLayer

	if _overlay_right:
		_overlay_right.get_parent().remove_child(_overlay_right)
		add_child(_overlay_right)

	if _overlay_left:
		_overlay_left.get_parent().remove_child(_overlay_left)
		add_child(_overlay_left)

## 集中处理所有调试 UI 的按键输入。
func _input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_F3:
			toggle_all()
			get_viewport().set_input_as_handled()
		KEY_F4:
			if not _is_any_visible():
				return
			page_up_all()
			get_viewport().set_input_as_handled()
		KEY_F5:
			if not _is_any_visible():
				return
			page_down_all()
			get_viewport().set_input_as_handled()

# ============================================================
# 9. 公开方法
# ============================================================

## 显示所有调试叠加层。
func show_all() -> void:
	if _overlay_right and _overlay_right.has_method("show_overlay"):
		_overlay_right.show_overlay()
	if _overlay_left and _overlay_left.has_method("show_overlay"):
		_overlay_left.show_overlay()

## 隐藏所有调试叠加层。
func hide_all() -> void:
	if _overlay_right and _overlay_right.has_method("hide_overlay"):
		_overlay_right.hide_overlay()
	if _overlay_left and _overlay_left.has_method("hide_overlay"):
		_overlay_left.hide_overlay()

## 切换所有调试叠加层的可见性。
func toggle_all() -> void:
	if _is_any_visible():
		hide_all()
	else:
		show_all()

## 所有面板同步上一页。
func page_up_all() -> void:
	if _overlay_right and _overlay_right.has_method("page_up"):
		_overlay_right.page_up()
	if _overlay_left and _overlay_left.has_method("page_up"):
		_overlay_left.page_up()

## 所有面板同步下一页。
func page_down_all() -> void:
	if _overlay_right and _overlay_right.has_method("page_down"):
		_overlay_right.page_down()
	if _overlay_left and _overlay_left.has_method("page_down"):
		_overlay_left.page_down()

# ============================================================
# 10. 私有方法
# ============================================================

func _is_any_visible() -> bool:
	var right_vis: bool = _overlay_right and _overlay_right.visible
	var left_vis: bool = _overlay_left and _overlay_left.visible
	return right_vis or left_vis
