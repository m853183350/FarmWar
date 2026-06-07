## 地块选择器（UI 系统）。
##
## 挂载在 [CanvasLayer] 子节点下，处理地块的悬停指示、拖拽框选与模式切换。
## 通过 [method _draw] 绘制悬停框和选择矩形，选中完成后弹出操作菜单。
##
## 与旧版的关键区别：
##   - 由 [CanvasLayer] 容器管理渲染层级，不再手动设置 z_index 与世界对象竞争
##   - [member CanvasLayer.follow_viewport_enabled] 需设为 [code]true[/code]，
##     确保绘制坐标系跟随摄像机，与地块坐标一致
##
## 使用方式：
##   1. 在场景中创建 [CanvasLayer] 节点，设置 [code]layer = 1[/code]、
##      [code]follow_viewport_enabled = true[/code]
##   2. 将本节点添加为该 CanvasLayer 的子节点
##   3. 运行游戏，鼠标悬停查看指示框，左键拖拽框选地块
class_name TileSelector extends Node2D

# ============================================================
# 1. 信号
# ============================================================

## 框选完成，传出选中地块的网格坐标数组。
signal selection_completed(tiles: Array)

# ============================================================
# 2. 枚举
# ============================================================

## 左键操作模式。
enum LeftClickMode {
	SELECT,      ## 选择 — 拖拽框选地块
	# 预留：PLOW, PLANT, BUILD 等
}

# ============================================================
# 3. 常量
# ============================================================

const CONTEXT_MENU_SCENE: PackedScene = preload("res://scenes/ui/popup/tile_context_menu.tscn")

# ============================================================
# 4. @export 变量 — 样式
# ============================================================

@export var HOVER_COLOR: Color = Color(1.0, 0.85, 0.0, 0.9)       ## 悬停指示框颜色（金色）
@export var HOVER_WIDTH: float = 2.0                                 ## 悬停框线宽
@export var SELECTION_FILL: Color = Color(0.2, 0.6, 1.0, 0.25)     ## 选择矩形填充色
@export var SELECTION_OUTLINE: Color = Color(0.2, 0.6, 1.0, 0.8)   ## 选择矩形边框色
@export var SELECTION_WIDTH: float = 2.0                             ## 选择矩形线宽
@export var MIN_DRAG_PX: float = 4.0                                 ## 最小拖拽距离（避免误触）

# ============================================================
# 4. @export 变量 — 配置
# ============================================================

## 当前左键操作模式。
@export var mode: LeftClickMode = LeftClickMode.SELECT

## 单个地块的像素大小（应与 TerrainGenerator.tile_size 一致）。
@export var tile_size: int = 64

## 选择矩形是否需要最小拖拽距离。
@export var require_min_drag: bool = true

# ============================================================
# 6. 私有变量
# ============================================================

## 当前鼠标悬停的网格坐标。(-1, -1) 表示未悬停在地图范围内。
var _hovered_grid: Vector2i = Vector2i(-1, -1)

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _drag_end: Vector2 = Vector2.ZERO

## 拖拽过程中实时预览的地块网格坐标。
var _preview_tiles: Array[Vector2i] = []

## 当前选中的地块网格坐标（菜单关闭前持续显示）。
var _selected_tiles: Array[Vector2i] = []

## 当前活跃的上下文菜单实例。
var _active_menu: TileContextMenu = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 启用 _input() 回调 — Godot 4 中 Node2D 默认不接收输入
	set_process_input(true)

func _process(_delta: float) -> void:
	_update_hover()

func _input(event: InputEvent) -> void:
	# 菜单打开时不处理世界点击（菜单自带遮罩层也会阻止穿透，此为双重保险）
	if _active_menu != null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().set_input_as_handled()
			if event.pressed:
				_on_mouse_pressed(event.position)
			else:
				_on_mouse_released(event.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag_end = get_global_mouse_position()
		_update_preview_tiles()
		queue_redraw()

func _draw() -> void:
	_draw_selected_tiles()
	_draw_preview_tiles()
	_draw_hover_indicator()
	_draw_selection_rect()

# ============================================================
# 9. 公开方法
# ============================================================

## 清除当前选中状态和活跃菜单。
func clear_selection() -> void:
	if _active_menu:
		_active_menu.queue_free()
		_active_menu = null
	_selected_tiles.clear()
	_preview_tiles.clear()
	_dragging = false
	queue_redraw()

# ============================================================
# 10. 私有方法 — 悬停
# ============================================================

func _update_hover() -> void:
	var world_pos: Vector2 = get_global_mouse_position()
	var grid: Vector2i = Vector2i(int(floorf(world_pos.x / tile_size)), int(floorf(world_pos.y / tile_size)))

	# 边界检查
	if world_pos.x < 0 or world_pos.y < 0:
		grid = Vector2i(-1, -1)

	if grid != _hovered_grid:
		_hovered_grid = grid
		queue_redraw()

func _draw_selected_tiles() -> void:
	if _selected_tiles.is_empty():
		return
	for grid: Vector2i in _selected_tiles:
		if grid.x < 0 or grid.y < 0:
			continue
		var rect := Rect2(Vector2(grid) * tile_size, Vector2.ONE * tile_size)
		draw_rect(rect, SELECTION_FILL)
		draw_rect(rect, SELECTION_OUTLINE, false, SELECTION_WIDTH)

func _draw_preview_tiles() -> void:
	if _preview_tiles.is_empty():
		return
	for grid: Vector2i in _preview_tiles:
		if grid.x < 0 or grid.y < 0:
			continue
		var rect := Rect2(Vector2(grid) * tile_size, Vector2.ONE * tile_size)
		draw_rect(rect, SELECTION_FILL)
		draw_rect(rect, SELECTION_OUTLINE, false, SELECTION_WIDTH)

func _draw_hover_indicator() -> void:
	if _hovered_grid.x < 0 or _hovered_grid.y < 0:
		return
	if _dragging and _get_drag_distance() > MIN_DRAG_PX:
		return  # 拖拽中隐藏悬停框
	# 菜单打开时不画悬停框（菜单遮罩在 UI 层，此处的悬停建议隐藏）
	if _active_menu != null:
		return

	var rect := Rect2(Vector2(_hovered_grid) * tile_size, Vector2.ONE * tile_size)
	draw_rect(rect, HOVER_COLOR, false, HOVER_WIDTH)

# ============================================================
# 10. 私有方法 — 拖拽选择
# ============================================================

func _on_mouse_pressed(_screen_pos: Vector2) -> void:
	match mode:
		LeftClickMode.SELECT:
			_dragging = true
			_drag_start = get_global_mouse_position()
			_drag_end = _drag_start
			# 按下时立即显示单个悬停地块的预览
			if _hovered_grid.x >= 0 and _hovered_grid.y >= 0:
				_preview_tiles = [_hovered_grid]
			else:
				_preview_tiles.clear()
			queue_redraw()

func _on_mouse_released(_screen_pos: Vector2) -> void:
	match mode:
		LeftClickMode.SELECT:
			if not _dragging:
				return
			_dragging = false

			if require_min_drag and _get_drag_distance() <= MIN_DRAG_PX:
				# 轻点：选择单个悬停地块
				if _hovered_grid.x >= 0 and _hovered_grid.y >= 0:
					_finalize_selection([_hovered_grid])
			else:
				# 拖拽：使用实时预览的地块列表
				if not _preview_tiles.is_empty():
					_finalize_selection(_preview_tiles.duplicate())

			_preview_tiles.clear()
			queue_redraw()

func _get_drag_distance() -> float:
	return _drag_start.distance_to(_drag_end)

func _get_selection_rect() -> Rect2:
	var pos := Vector2(minf(_drag_start.x, _drag_end.x), minf(_drag_start.y, _drag_end.y))
	var size := Vector2(absf(_drag_end.x - _drag_start.x), absf(_drag_end.y - _drag_start.y))
	return Rect2(pos, size)

func _draw_selection_rect() -> void:
	if not _dragging:
		return
	if require_min_drag and _get_drag_distance() <= MIN_DRAG_PX:
		return

	var rect: Rect2 = _get_selection_rect()
	draw_rect(rect, SELECTION_FILL)
	draw_rect(rect, SELECTION_OUTLINE, false, SELECTION_WIDTH)

func _get_tiles_in_rect(rect: Rect2) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var start_x: int = int(floorf(rect.position.x / tile_size))
	var start_y: int = int(floorf(rect.position.y / tile_size))
	var end_x: int = int(floorf((rect.position.x + rect.size.x) / tile_size))
	var end_y: int = int(floorf((rect.position.y + rect.size.y) / tile_size))

	for x: int in range(start_x, end_x + 1):
		for y: int in range(start_y, end_y + 1):
			if x >= 0 and y >= 0:
				tiles.append(Vector2i(x, y))
	return tiles

## 根据当前拖拽矩形实时更新预览地块列表。
func _update_preview_tiles() -> void:
	var rect: Rect2 = _get_selection_rect()
	_preview_tiles = _get_tiles_in_rect(rect)

# ============================================================
# 10. 私有方法 — 上下文菜单
# ============================================================

func _finalize_selection(tiles: Array[Vector2i]) -> void:
	_selected_tiles = tiles
	queue_redraw()

	selection_completed.emit(tiles)

	if EventBus:
		EventBus.tiles_selected.emit(tiles)

	_show_context_menu(tiles)

func _show_context_menu(tiles: Array[Vector2i]) -> void:
	# 清理旧菜单
	if _active_menu:
		_active_menu.queue_free()
		_active_menu = null

	var menu_instance: Node = CONTEXT_MENU_SCENE.instantiate()
	add_child(menu_instance)
	_active_menu = menu_instance as TileContextMenu

	if _active_menu:
		_active_menu.action_selected.connect(_on_menu_action)
		_active_menu.cancelled.connect(_on_menu_cancelled)
		var screen_pos: Vector2 = get_viewport().get_mouse_position()
		_active_menu.show_menu(screen_pos, tiles)

func _on_menu_action(action: String, _tiles: Array) -> void:
	if EventBus:
		EventBus.tile_action_triggered.emit(action, _tiles)
	_selected_tiles.clear()
	_active_menu = null
	queue_redraw()

func _on_menu_cancelled() -> void:
	_selected_tiles.clear()
	_active_menu = null
	queue_redraw()
