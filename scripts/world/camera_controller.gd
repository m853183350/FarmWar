## 摄像机控制器。
##
## 挂载在 [Camera2D] 节点上，提供：
## - 鼠标移动到窗口边缘时平滑移动视角
## - 鼠标滚轮缩放，带平滑过渡
## - 地块左键交互由 [TileSelector] 接管
extends Camera2D

# ============================================================
# 3. 常量
# ============================================================

# ============================================================
# 4. @export 变量
# ============================================================

## 触发边缘滚动的像素宽度。
@export var edge_margin: int = 20

## 边缘滚动最大速度（像素/秒）。
@export var max_scroll_speed: float = 600.0

## 滚动加速度（像素/秒²）。
@export var scroll_acceleration: float = 2000.0

## 最小缩放值。
@export var min_zoom: float = 0.3

## 最大缩放值。
@export var max_zoom: float = 4.0

## 每格滚轮缩放量。
@export var zoom_step: float = 0.1

## 缩放平滑系数（越大越快到达目标值）。
@export var zoom_smoothness: float = 10.0

# ============================================================
# 6. 私有变量
# ============================================================

var _scroll_velocity: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0
var _tile_size: int = 64

# ============================================================
# 7. @onready 变量
# ============================================================

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_target_zoom = zoom.x
	# 尝试从父节点的 TerrainGenerator 读取 tile_size
	var parent: Node = get_parent()
	if parent and parent.has_method("generate"):
		_tile_size = parent.get("tile_size")

func _process(delta: float) -> void:
	_update_edge_scroll(delta)
	_update_zoom(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_target_zoom = clampf(_target_zoom - zoom_step, min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_target_zoom = clampf(_target_zoom + zoom_step, min_zoom, max_zoom)

# ============================================================
# 9. 公开方法
# ============================================================

## 设置当前 tile 尺寸（可从外部同步）。
func set_tile_size(size: int) -> void:
	_tile_size = size

# ============================================================
# 10. 私有方法
# ============================================================

func _update_edge_scroll(delta: float) -> void:
	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_size: Vector2 = viewport_rect.size

	# 隐藏鼠标在视口外时获取位置可能异常，保护一下
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	# 注意：鼠标可能不在视口内（如程序刚启动）
	var input_dir := Vector2.ZERO
	if mouse_pos.x >= 0 and mouse_pos.x <= viewport_size.x and mouse_pos.y >= 0 and mouse_pos.y <= viewport_size.y:
		if mouse_pos.x < edge_margin:
			input_dir.x = -1.0
		elif mouse_pos.x > viewport_size.x - edge_margin:
			input_dir.x = 1.0
		if mouse_pos.y < edge_margin:
			input_dir.y = -1.0
		elif mouse_pos.y > viewport_size.y - edge_margin:
			input_dir.y = 1.0

	var target_velocity: Vector2 = input_dir * max_scroll_speed
	if input_dir != Vector2.ZERO:
		_scroll_velocity = _scroll_velocity.move_toward(target_velocity, scroll_acceleration * delta)
	else:
		_scroll_velocity = _scroll_velocity.move_toward(Vector2.ZERO, scroll_acceleration * delta)

	# 应用相机坐标系缩放，确保实际滚动速度与缩放无关
	var zoom_factor: float = zoom.x
	if zoom_factor > 0.001:
		position += _scroll_velocity * delta / zoom_factor

func _update_zoom(delta: float) -> void:
	var current_zoom: float = zoom.x
	if abs(current_zoom - _target_zoom) < 0.0005:
		zoom = Vector2(_target_zoom, _target_zoom)
		return
	var new_zoom: float = lerpf(current_zoom, _target_zoom, zoom_smoothness * delta)
	if abs(new_zoom - _target_zoom) < 0.0005:
		new_zoom = _target_zoom
	zoom = Vector2(new_zoom, new_zoom)
