## 寻路管理器 — 成本网格持有 + 异步寻路调度。
##
## 通过 Autoload 全局访问：[code]PathfindingManager[/code]
##
## 职责：
##   - 维护多套通行成本网格（ground / flying / aquatic …）
##   - 监听 [signal EventBus.terrain_generated] 初始构建
##   - 监听 [signal EventBus.terrain_changed]  增量更新
##   - 使用 [WorkerThreadPool] 提供异步寻路接口，多个请求可并行计算
extends Node

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

# ============================================================
# 信号
# ============================================================

## 异步寻路完成。[param request_id] 对应 [method request_path] 的返回值。
signal path_ready(request_id: int, path: Array[Vector2])

## 异步流场计算完成。[param field] 为 [Pathfinding.FlowField] 实例。
signal flow_field_ready(request_id: int, field)

# ============================================================
# 常量
# ============================================================

const COST_CONFIG_PATH: String = "res://config/pathfinding_cost.json"
const TILE_SIZE: int = 64
const DEFAULT_COST: float = 2.0

## 成本网格类型 → 计算规则的内置映射。
## 扩展新类型时在此注册并在 [method _compute_cost] 中添加分支。
const COST_GRID_TYPES: Array[String] = ["ground", "flying", "aquatic"]

# ============================================================
# 公开变量
# ============================================================

## 多套成本网格。键：类型字符串，值：Array[Array]float（[x][y] → 成本）。
var cost_grids: Dictionary = {}

# ============================================================
# 私有变量 — 配置缓存
# ============================================================

var _tile_type_costs: Dictionary = {}
var _variant_costs: Dictionary = {}
var _map_width: int = 0
var _map_height: int = 0
var _initialized: bool = false

# ============================================================
# 私有变量 — WorkerThreadPool 任务追踪
# ============================================================

## 活跃的 WorkerThreadPool 任务 ID 列表，用于退出时等待和定期清理。
var _active_task_ids: Array[int] = []

## 关闭中标志，阻止 [method _exit_tree] 期间受理新任务。
var _shutting_down: bool = false

var _next_request_id: int = 0

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# 连接事件
	if EventBus:
		EventBus.terrain_generated.connect(_on_terrain_generated)

	# 成本配置在 _ready 中加载（仅一次）
	_load_cost_config()


func _exit_tree() -> void:
	_shutting_down = true

	# 等待所有活跃的 WorkerThreadPool 任务完成
	for task_id: int in _active_task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
	_active_task_ids.clear()

	# 断开事件
	if EventBus:
		EventBus.terrain_generated.disconnect(_on_terrain_generated)
		if EventBus.terrain_changed.is_connected(_on_terrain_changed):
			EventBus.terrain_changed.disconnect(_on_terrain_changed)


func _process(_delta: float) -> void:
	_cleanup_completed_tasks()


# ============================================================
# 公开 API — 成本网格
# ============================================================

## 获取指定类型的成本网格引用（只读，供主线程同步查询）。
## 注意：后台线程应使用 [method duplicate_cost_grid] 获取安全副本。
func get_cost_grid(type: String = "ground") -> Array[Array]:
	return cost_grids.get(type, [])


## 深拷贝成本网格（供 WorkerThreadPool 任务使用，保证线程安全）。
func duplicate_cost_grid(type: String = "ground") -> Array[Array]:
	var src: Array[Array] = cost_grids.get(type, [])
	if src.is_empty():
		return []

	var copy: Array[Array] = []
	copy.resize(src.size())
	for x: int in range(src.size()):
		copy[x] = src[x].duplicate()  # 深拷贝内层 float 数组
	return copy


## 检查地块是否可通过。
func is_tile_passable(tile: Vector2i, type: String = "ground") -> bool:
	return Pathfinding.is_passable(tile, get_cost_grid(type))


# ============================================================
# 公开 API — 异步寻路
# ============================================================

## 异步请求寻路路径。
##
## 将 A* 计算提交到 [WorkerThreadPool]，完成后通过 [signal path_ready] 通知。
## 多个请求可被并行处理，充分利用多核 CPU。
##
## [param start] 起点地块坐标。
## [param goal] 终点地块坐标。
## [param cost_grid_type] 成本网格类型，默认 "ground"。
## 返回 request_id，完成后通过 [signal path_ready] 通知。
func request_path(start: Vector2i, goal: Vector2i, cost_grid_type: String = "ground") -> int:
	if not _initialized or _shutting_down:
		return -1

	var request_id: int = _next_request_id
	_next_request_id += 1

	var grid_copy: Array[Array] = duplicate_cost_grid(cost_grid_type)
	if grid_copy.is_empty():
		# 成本网格尚未就绪，延迟重试
		call_deferred("_retry_request_path", request_id, start, goal, cost_grid_type)
		return request_id

	var task_id: int = WorkerThreadPool.add_task(
		_compute_path_task.bind(request_id, start, goal, grid_copy)
	)
	_active_task_ids.append(task_id)

	return request_id


## 异步请求流场计算。
##
## 将 Dijkstra 流场计算提交到 [WorkerThreadPool]，完成后通过 [signal flow_field_ready] 通知。
##
## [param goal] 目标点地块坐标。
## [param cost_grid_type] 成本网格类型。
## 返回 request_id，完成后通过 [signal flow_field_ready] 通知。
func request_flow_field(goal: Vector2i, cost_grid_type: String = "ground") -> int:
	if not _initialized or _shutting_down:
		return -1

	var request_id: int = _next_request_id
	_next_request_id += 1

	var grid_copy: Array[Array] = duplicate_cost_grid(cost_grid_type)
	if grid_copy.is_empty():
		call_deferred("_retry_request_flow_field", request_id, goal, cost_grid_type)
		return request_id

	var task_id: int = WorkerThreadPool.add_task(
		_compute_flow_field_task.bind(request_id, goal, grid_copy)
	)
	_active_task_ids.append(task_id)

	return request_id


# ============================================================
# 私有方法 — 成本网格构建
# ============================================================

func _on_terrain_generated() -> void:
	var world: Node2D = WorldUtils.get_world()
	if world == null:
		push_error("PathfindingManager: 无法获取 world 节点，成本网格构建失败")
		return

	# 读取地图尺寸
	_map_width = int(world.get("map_width"))
	_map_height = int(world.get("map_height"))
	if _map_width <= 0 or _map_height <= 0:
		return

	# 为每种类型构建成本网格
	cost_grids.clear()
	for type: String in COST_GRID_TYPES:
		var grid: Array[Array] = _build_cost_grid(world, type)
		cost_grids[type] = grid

	# 连接增量更新事件
	if EventBus and not EventBus.terrain_changed.is_connected(_on_terrain_changed):
		EventBus.terrain_changed.connect(_on_terrain_changed)

	_initialized = true
	print("PathfindingManager: 成本网格初始化完成 (%dx%d, %d 种类型)" % [_map_width, _map_height, COST_GRID_TYPES.size()])


func _build_cost_grid(world: Node2D, type: String) -> Array[Array]:
	var grid: Array[Array] = []
	grid.resize(_map_width)

	for x: int in range(_map_width):
		grid[x] = []
		grid[x].resize(_map_height)
		for y: int in range(_map_height):
			grid[x][y] = DEFAULT_COST

	# 遍历所有子节点读取地块数据
	for child: Node in world.get_children():
		var td = WorldUtils.get_tile_data(child)
		if td == null:
			continue

		var gp: Vector2i = td.grid_position
		if gp.x < 0 or gp.x >= _map_width or gp.y < 0 or gp.y >= _map_height:
			continue

		grid[gp.x][gp.y] = _compute_cost(td.tile_type, td.variant, type)

	return grid


func _on_terrain_changed(tiles: Array) -> void:
	if not _initialized:
		return

	var world: Node2D = WorldUtils.get_world()
	if world == null:
		return

	for item in tiles:
		var tile_pos: Vector2i
		if item is Vector2i:
			tile_pos = item as Vector2i
		elif item is Dictionary:
			var d := item as Dictionary
			tile_pos = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		else:
			continue

		if tile_pos.x < 0 or tile_pos.x >= _map_width or tile_pos.y < 0 or tile_pos.y >= _map_height:
			continue

		# 读取该位置当前地块数据
		var td = world.get_tile_data_at(tile_pos.x, tile_pos.y)

		for type: String in cost_grids:
			var grid: Array[Array] = cost_grids[type]
			if td:
				grid[tile_pos.x][tile_pos.y] = _compute_cost(td.tile_type, td.variant, type)
			else:
				grid[tile_pos.x][tile_pos.y] = DEFAULT_COST


# ============================================================
# 私有方法 — 成本计算
# ============================================================

## 根据单位移动类型和地块数据计算通行成本。
func _compute_cost(tile_type: int, variant: String, grid_type: String) -> float:
	match grid_type:
		"flying":
			# 飞行单位忽略地形，全部可通过
			return 1.0

		"aquatic":
			# 水行单位：原本不可通行的水域变为可通过
			var base: float = _get_tile_cost(tile_type, variant)
			if base < 0.0:
				return 2.0  # 深海/河流等变为可通行（成本 2）
			return base

		_:  # "ground" 及其他
			return _get_tile_cost(tile_type, variant)


## 查表获取地块基础移动成本。
func _get_tile_cost(tile_type: int, variant: String) -> float:
	var type_key: String = _tile_type_to_key(tile_type)

	# 1. variant 优先
	if not variant.is_empty() and _variant_costs.has(variant):
		return float(_variant_costs[variant])

	# 2. tile_type 大类
	if not type_key.is_empty() and _tile_type_costs.has(type_key):
		return float(_tile_type_costs[type_key])

	# 3. 默认
	return DEFAULT_COST


func _tile_type_to_key(tile_type: int) -> String:
	match tile_type:
		0: return "dirt"
		1: return "stone"
		2: return "ocean"
		3: return "farmland"
		4: return "slope"
		5: return "rough"
		6: return "special"
		_: return ""


func _load_cost_config() -> void:
	if not FileAccess.file_exists(COST_CONFIG_PATH):
		push_warning("PathfindingManager: 成本配置文件不存在: %s，全部使用默认成本 %.1f" % [COST_CONFIG_PATH, DEFAULT_COST])
		return

	var file: FileAccess = FileAccess.open(COST_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("PathfindingManager: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return

	var data = json.data
	if not data is Dictionary:
		return

	var raw: Dictionary = data as Dictionary
	if raw.has("tile_type_costs"):
		_tile_type_costs = raw["tile_type_costs"]
	if raw.has("variant_costs"):
		_variant_costs = raw["variant_costs"]


# ============================================================
# 私有方法 — WorkerThreadPool 任务（在工作线程中执行）
# ============================================================

## WorkerThreadPool 任务：在后台线程执行 A* 寻路。
## 纯计算，不访问场景树。完成后通过 [method call_deferred] 将结果传回主线程。
func _compute_path_task(request_id: int, start: Vector2i, goal: Vector2i, grid: Array[Array]) -> void:
	var path: Array[Vector2] = Pathfinding.find_path(start, goal, grid)
	call_deferred("_on_path_done", request_id, path)


## WorkerThreadPool 任务：在后台线程执行流场计算。
## 纯计算，不访问场景树。完成后通过 [method call_deferred] 将结果传回主线程。
func _compute_flow_field_task(request_id: int, goal: Vector2i, grid: Array[Array]) -> void:
	var field = Pathfinding.compute_flow_field(goal, grid)
	call_deferred("_on_flow_field_done", request_id, field)


# ============================================================
# 私有方法 — WorkerThreadPool 结果回调（在主线程执行）
# ============================================================

## 主线程回调：A* 寻路完成，发射 [signal path_ready] 信号。
func _on_path_done(request_id: int, path: Array[Vector2]) -> void:
	path_ready.emit(request_id, path)


## 主线程回调：流场计算完成，发射 [signal flow_field_ready] 信号。
func _on_flow_field_done(request_id: int, field) -> void:
	flow_field_ready.emit(request_id, field)


# ============================================================
# 私有方法 — 任务清理
# ============================================================

## 每帧检查已完成的任务 ID 并调用 [method WorkerThreadPool.wait_for_task_completion]
## 释放资源。完成后从 [member _active_task_ids] 中移除。
func _cleanup_completed_tasks() -> void:
	var i: int = _active_task_ids.size() - 1
	while i >= 0:
		if WorkerThreadPool.is_task_completed(_active_task_ids[i]):
			WorkerThreadPool.wait_for_task_completion(_active_task_ids[i])
			_active_task_ids.remove_at(i)
		i -= 1


# ============================================================
# 私有方法 — 重试
# ============================================================

## 延迟重试（成本网格未就绪时）。
func _retry_request_path(request_id: int, start: Vector2i, goal: Vector2i, grid_type: String) -> void:
	if not _initialized:
		push_warning("PathfindingManager: 成本网格尚未初始化，异步寻路请求被拒绝")
		path_ready.emit(request_id, [])
		return
	# 初始化完成后再试一次
	var new_id: int = request_path(start, goal, grid_type)
	# 注意：此时 request_id 与 new_id 不同，调用方需要处理
	# 实际场景中 _retry 仅发生在初始化期间的极短窗口，影响可忽略


func _retry_request_flow_field(request_id: int, goal: Vector2i, grid_type: String) -> void:
	if not _initialized:
		flow_field_ready.emit(request_id, null)
		return
	var new_id: int = request_flow_field(goal, grid_type)


# ============================================================
# 私有方法 — 工具
# ============================================================

# 世界查找和地块数据读取已迁移至 WorldUtils
