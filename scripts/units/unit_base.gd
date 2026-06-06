## 作战单位抽象基类。
##
## 所有单位（农场工人、战士等）都必须继承本类。
## 定义了通用属性、状态机、移动系统（含寻路框架）和动画/音效组件的访问接口。
##
## 移动系统说明：
##   - 逻辑移动在 [method _on_tick] 中驱动，每 tick 前进 move_speed * tick_delta 的距离
##   - 画面在 [method _process] 中做插值，确保高于 20FPS 的显示帧率下视觉平滑
##   - 当前使用直线移动；A* 寻路框架已预留，待 pathfinding.gd 实现后接入
##
## 子类必须：
##   - 覆写 [method _get_unit_type_name] 返回单位类型标识
##   - 覆写 [method _on_tick] 实现各自的逻辑（并调用 super._on_tick(delta) 处理移动）
##   - 可选覆写 [method _load_config] 加载自身 JSON 配置
class_name UnitBase
extends CharacterBody2D

# ============================================================
# 1. 信号
# ============================================================

## 单位状态变化时发出。
signal state_changed(old_state: int, new_state: int)

## 单位到达目标位置时发出（移动阶段完成）。
signal move_completed()

## 单位移动受阻时发出（寻路失败等）。
signal move_blocked(reason: String)

# ============================================================
# 2. 枚举
# ============================================================

## 单位状态。
enum UnitState {
	IDLE,        ## 空闲，无任务，站立不动
	MOVING,      ## 移动中，向目标地块导航
	WORKING,     ## 工作中，正在执行地块操作
	COMBAT,      ## 战斗中（预留）
	DEAD,        ## 死亡
}

# ============================================================
# 3. 常量
# ============================================================

## 每个地块的像素大小（需与 [TerrainGenerator.tile_size] 保持一致）。
const TILE_SIZE: int = 64

## 寻路失败后的等待时间（秒）。
const FIND_PATH_WAIT_TIME: float = 0.5

## 连续寻路失败最大次数，超过后执行瞬移。
const FIND_PATH_FAIL_MAX: int = 10

# ============================================================
# 5. 公开变量
# ============================================================

## 单位唯一标识（如 "farm_worker_1"）。
var unit_id: StringName = &""

## 单位类型 ID（如 "farm_worker"）。
var unit_type: StringName = &""

## 显示名称（如 "农场工人"）。
var display_name: String = ""

## 最大生命值。
var max_health: float = 50.0

## 当前生命值。
var current_health: float = 50.0

## 移动速度（格/秒）。3.0 表示每秒移动 3 个地块。
var move_speed: float = 3.0

## 阵营。0 = 玩家，1+ = 敌方。
var faction: int = 0

## 当前世界坐标位置（浮点数）。
## 取整后除以 TILE_SIZE 可得到对应的地块 Vector2i。
var grid_position: Vector2 = Vector2.ZERO

## 当前状态。
var state: int = UnitState.IDLE

## 朝向（用于动画翻转，1 = 右，-1 = 左）。
var facing_direction: Vector2 = Vector2.RIGHT

# ============================================================
# 6. 私有变量 — 移动系统
# ============================================================

## 目标世界坐标（移动的目的地）。
var _target_position: Vector2 = Vector2.ZERO

## 上一 tick 的实际位置（用于画面插值）。
var _prev_tick_position: Vector2 = Vector2.ZERO

## 当前 tick 的目标位置（用于画面插值）。
var _next_tick_position: Vector2 = Vector2.ZERO

## 寻路路径点数组（预留，A* 实现后使用）。
var _move_path: Array[Vector2] = []

## 当前路径点索引（预留）。
var _path_index: int = 0

## 是否正在等待重新寻路。
var _waiting_for_path: bool = false

## 寻路等待计时器。
var _path_wait_timer: float = 0.0

## 连续寻路失败次数。
var _find_path_fail_count: int = 0

## tick 信号连接状态。
var _tick_connected: bool = false

# ============================================================
# 7. @onready 变量
# ============================================================

@onready var animation_controller: AnimationController = $AnimationController as AnimationController
@onready var audio_controller: AudioController = $AudioController as AudioController
@onready var sprite: Sprite2D = $Sprite2D as Sprite2D
@onready var selection_indicator: Sprite2D = $SelectionIndicator as Sprite2D
@onready var health_bar: ProgressBar = $HealthBar as ProgressBar

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	grid_position = global_position
	_prev_tick_position = grid_position
	_next_tick_position = grid_position
	_target_position = grid_position

	# 连接到 TickSystem
	if TickSystem:
		TickSystem.tick_elapsed.connect(_on_tick)
		_tick_connected = true

	# 子类加载配置
	_load_config()

	# 设置初始状态
	_set_state(UnitState.IDLE)
	selection_indicator.visible = false

func _exit_tree() -> void:
	if _tick_connected and TickSystem:
		TickSystem.tick_elapsed.disconnect(_on_tick)
		_tick_connected = false

func _process(_delta: float) -> void:
	# 画面插值：在两帧 tick 位置之间平滑过渡
	# 只有当 tick 驱动的 _next_tick_position 与 _prev_tick_position 不同时才需要插值
	if state == UnitState.MOVING or _prev_tick_position.distance_to(_next_tick_position) > 0.1:
		# 计算插值因子：基于自上次 tick 以来的时间比例
		# 简单方式：直接设置到 next 位置，视觉上也足够流畅（tick 间隔仅 50ms）
		# 复杂方式（更平滑）：在 _process 中每帧做 lerp
		global_position = global_position.lerp(_next_tick_position, 0.5)

# ============================================================
# 9. 公开方法 — 状态
# ============================================================

## 获取当前状态枚举值。
func get_state() -> int:
	return state

## 是否处于空闲状态。
func is_idle() -> bool:
	return state == UnitState.IDLE

## 是否存活。
func is_alive() -> bool:
	return state != UnitState.DEAD

# ============================================================
# 9. 公开方法 — 移动
# ============================================================

## 设置移动目标（网格坐标）。
## 单位会在后续 tick 中自动导航到目标地块的相邻格。
func set_move_target_tile(tile: Vector2i) -> void:
	# 计算目标地块的世界坐标
	var target_world: Vector2 = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
	_set_move_target_world(target_world)

## 设置移动目标（世界坐标）。
func set_move_target_world(world_pos: Vector2) -> void:
	_set_move_target_world(world_pos)

## 是否已到达目标位置。
func is_at_target() -> bool:
	return grid_position.distance_to(_target_position) < 1.0

## 获取目标地块的相邻单元格坐标列表（4 方向）。
func get_adjacent_cells(tile: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(tile.x, tile.y - 1),
		Vector2i(tile.x, tile.y + 1),
		Vector2i(tile.x - 1, tile.y),
		Vector2i(tile.x + 1, tile.y),
	]

## 获取当前所在地块坐标。
func get_current_tile() -> Vector2i:
	return Vector2i(roundi(grid_position.x / TILE_SIZE), roundi(grid_position.y / TILE_SIZE))

## 是否在指定地块的相邻格。
func is_adjacent_to(tile: Vector2i) -> bool:
	var my_tile: Vector2i = get_current_tile()
	var adjacents: Array[Vector2i] = get_adjacent_cells(tile)
	return my_tile in adjacents

# ============================================================
# 9. 公开方法 — 生命值
# ============================================================

## 受到伤害。
func take_damage(amount: float) -> void:
	current_health = maxf(0.0, current_health - amount)
	if current_health <= 0.0:
		_die()

## 治疗。
func heal(amount: float) -> void:
	current_health = minf(max_health, current_health + amount)

# ============================================================
# 10. 私有方法 — Tick 驱动
# ============================================================

## Tick 回调。子类应覆写并调用 super._on_tick(delta)。
func _on_tick(_delta: float) -> void:
	if state == UnitState.DEAD:
		return
	if state == UnitState.MOVING:
		_execute_move_phase(_delta)

# ============================================================
# 10. 私有方法 — 移动系统
# ============================================================

## 执行移动阶段（每 tick 由 _on_tick 调用）。
## 直接向目标位置直线移动；A* 寻路在 _move_path 实现后启用。
func _execute_move_phase(_delta: float) -> void:
	if state != UnitState.MOVING:
		return

	# 检查是否已到达目标
	if grid_position.distance_to(_target_position) < 1.0:
		grid_position = _target_position
		_next_tick_position = _target_position
		_move_path.clear()
		_set_state(UnitState.IDLE)
		move_completed.emit()
		return

	# 若在等待重新寻路
	if _waiting_for_path:
		_path_wait_timer += _delta
		if _path_wait_timer >= FIND_PATH_WAIT_TIME:
			_waiting_for_path = false
			_path_wait_timer = 0.0
			_try_find_path()
		return

	# 直接直线移动（A* 未实现前的降级方案）
	_direct_move(_delta)

## 直线移动到目标（降级方案，A* 实现后替换）。
func _direct_move(_delta: float) -> void:
	var direction: Vector2 = _target_position - grid_position
	var distance: float = direction.length()

	if distance < 0.5:
		grid_position = _target_position
		return

	# 每 tick 移动 move_speed * tick_interval 的距离
	# tick_interval 默认 0.05s，move_speed 单位为 格/秒
	# 实际移动距离：move_speed * 0.05 格 = move_speed * 0.05 * TILE_SIZE 像素
	var step: float = move_speed * TILE_SIZE * TickSystem.tick_interval
	var move_dir: Vector2 = direction.normalized()
	var move_dist: float = minf(step, distance)

	_prev_tick_position = grid_position
	grid_position += move_dir * move_dist
	_next_tick_position = grid_position

	# 更新朝向
	if move_dir.x != 0.0:
		facing_direction = Vector2(signf(move_dir.x), 0.0)

	# 同步全局位置
	global_position = grid_position

## 尝试寻路到目标位置（A* 框架，待实现）。
func _try_find_path() -> void:
	# TODO: 接入 A* 寻路系统（pathfinding.gd）
	# 当前降级为直线移动
	_find_path_fail_count += 1

	if _find_path_fail_count >= FIND_PATH_FAIL_MAX:
		# 连续失败达到上限，执行瞬移
		_teleport_to_target()
		return

	# 暂时使用直线移动（不设置 _waiting_for_path）
	pass

## 瞬移到目标位置（卡死时的兜底手段）。
func _teleport_to_target() -> void:
	push_warning("UnitBase: %s 寻路连续失败 %d 次，执行瞬移" % [unit_id, _find_path_fail_count])
	grid_position = _target_position
	_next_tick_position = _target_position
	_prev_tick_position = _target_position
	global_position = _target_position
	_find_path_fail_count = 0
	_move_path.clear()
	_set_state(UnitState.IDLE)
	move_completed.emit()

## 设置移动目标（世界坐标）并进入 MOVING 状态。
func _set_move_target_world(world_pos: Vector2) -> void:
	_target_position = world_pos
	_find_path_fail_count = 0
	_waiting_for_path = false
	_move_path.clear()

	if grid_position.distance_to(_target_position) < 1.0:
		# 已在目标位置
		return

	_set_state(UnitState.MOVING)

# ============================================================
# 10. 私有方法 — 状态管理
# ============================================================

## 设置状态并发出信号。
func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	var old_state: int = state
	state = new_state
	state_changed.emit(old_state, new_state)

# ============================================================
# 10. 私有方法 — 生命值
# ============================================================

## 单位死亡。
func _die() -> void:
	_set_state(UnitState.DEAD)
	# 子类可覆写以添加死亡动画、音效等

# ============================================================
# 11. 虚方法 — 子类应覆写
# ============================================================

## 返回单位类型名称。子类必须覆写。
func _get_unit_type_name() -> String:
	return "unit_base"

## 加载单位 JSON 配置。子类可覆写以加载专属配置。
func _load_config() -> void:
	pass
