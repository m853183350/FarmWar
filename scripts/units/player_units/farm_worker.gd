## 农场工人 — 玩家的基础劳作单位。
##
## 继承 [UnitBase]，不可直接操控，所有行为由任务队列驱动。
## 工人从任务队列中按 FIFO 顺序取出任务，自动完成移动和执行动作。
##
## 特性：
##   - 任务驱动 AI：通过 [method add_task] 追加任务，每 tick 自动执行
##   - 隐式移动：执行地块操作时自动导航到目标相邻格
##   - 父子任务：批量操作（如框选 5 块地种植）通过父任务分组，子任务依次执行
##   - 配置驱动：属性从 [code]config/units/farm_worker.json[/code] 加载
##
## 使用方式：
##   [code]worker.add_task(TaskData.create(TaskData.TaskType.PLANT, Vector2i(3, 5), {"crop_id": "wheat_tier1"}))[/code]
class_name FarmWorker
extends UnitBase

# ============================================================
# 1. 信号
# ============================================================

## 一个任务成功完成。
signal task_completed(task: TaskData)

## 一个任务失败。
signal task_failed(task: TaskData, reason: String)

## 新任务加入队列。
signal task_added(task: TaskData)

## 任务队列变为空（全部完成）。
signal queue_empty()

# ============================================================
# 3. 常量
# ============================================================

## 农场工人配置文件路径。
const CONFIG_PATH: String = "res://config/units/farm_worker.json"

# ============================================================
# 5. 公开变量 — 工作属性
# ============================================================

## 工作速度倍率（影响翻耕/种植/收获耗时）。
var work_speed: float = 1.0

## 工具等级（影响可执行的操作类型，预留）。
var tool_level: int = 1

## 携带种子/物品槽位数（预留）。
var carry_capacity: int = 5

## 种植操作基础 tick 数。
var plant_ticks: int = 20

## 收获操作基础 tick 数。
var harvest_ticks: int = 30

## 翻耕操作基础 tick 数。
var plow_ticks: int = 40

## 挖掘操作基础 tick 数。
var dig_ticks: int = 30

# ============================================================
# 6. 私有变量
# ============================================================

## 任务队列（FIFO，index 0 为当前任务）。仅存储叶子任务。
var _tasks: Array[TaskData] = []

## 队列最大长度。
var _max_tasks: int = 1000

## 等待子任务完成的父任务列表。
var _pending_parents: Array[TaskData] = []

## 世界节点缓存（用于查找地块）。
var _world_cache: Node2D = null

## JSON 配置缓存。
var _config_cache: Dictionary = {}

## 当前正在播放的行走音效播放器。
var _footstep_player: AudioStreamPlayer2D = null

# ============================================================
# 11. 虚方法覆写
# ============================================================

func _get_unit_type_name() -> String:
	return "farm_worker"

func _load_config() -> void:
	_config_cache = _load_config_file()
	if _config_cache.is_empty():
		push_warning("FarmWorker: 配置文件为空或加载失败，使用默认值")
		return

	unit_type = _config_cache.get("unit_type", "farm_worker")
	display_name = _config_cache.get("display_name", "农场工人")
	max_health = _config_cache.get("max_health", 50.0)
	current_health = max_health
	move_speed = _config_cache.get("move_speed", 3.0)
	work_speed = _config_cache.get("work_speed", 1.0)
	tool_level = _config_cache.get("tool_level", 1)
	_max_tasks = _config_cache.get("max_tasks", 1000)
	carry_capacity = _config_cache.get("carry_capacity", 5)
	plant_ticks = _config_cache.get("plant_ticks", 20)
	harvest_ticks = _config_cache.get("harvest_ticks", 30)
	plow_ticks = _config_cache.get("plow_ticks", 40)
	dig_ticks = _config_cache.get("dig_ticks", 30)

# ============================================================
# 9. 公开方法 — 任务队列操作
# ============================================================

## 向队尾追加任务。
## 若任务有子任务，子任务会被展开加入队列，父任务进入待完成跟踪列表。
## 若提供了 [param parent_task]，会建立父子关系。
## 队列满时返回 false。
func add_task(task: TaskData, parent_task: TaskData = null) -> bool:
	if is_queue_full():
		return false

	if parent_task:
		parent_task.add_child_task(task)

	if not task.child_tasks.is_empty():
		# 父任务：展开子任务到队列，父任务进入跟踪列表
		_pending_parents.append(task)
		for child: TaskData in task.child_tasks:
			if is_queue_full():
				break
			_tasks.append(child)
	else:
		# 叶子任务：直接加入队列
		_tasks.append(task)

	task_added.emit(task)
	return true

## 向队尾批量追加任务。
## [param parent_tasks] 必须与 [param tasks] 长度相同（可为 null 表示无父任务）。
## 返回每个任务是否添加成功的布尔数组。
func add_tasks_batch(tasks: Array[TaskData], parent_tasks: Array[TaskData] = []) -> Array[bool]:
	var results: Array[bool] = []
	for i: int in range(tasks.size()):
		var task: TaskData = tasks[i]
		var parent: TaskData = null
		if i < parent_tasks.size():
			parent = parent_tasks[i]
		results.append(add_task(task, parent))
	return results

## 获取队列拷贝（只读）。
func get_tasks() -> Array[TaskData]:
	return _tasks.duplicate()

## 获取队列中任务数。
func get_task_count() -> int:
	return _tasks.size()

## 队列是否已满。
func is_queue_full() -> bool:
	return _tasks.size() >= _max_tasks

## 队列是否为空。
func is_queue_empty() -> bool:
	return _tasks.is_empty()

## 返回当前正在执行的任务（队列第一位）。空队列返回 null。
func get_current_task() -> TaskData:
	if _tasks.is_empty():
		return null
	return _tasks[0]

## 清空所有待执行任务（当前 IN_PROGRESS 的任务及其父子关联任务会继续执行完）。
func clear_pending_tasks() -> void:
	var i: int = _tasks.size() - 1
	while i >= 0:
		var task: TaskData = _tasks[i]
		if task.status == TaskData.TaskStatus.PENDING:
			task.status = TaskData.TaskStatus.CANCELLED
			_tasks.remove_at(i)
		i -= 1

## 取消所有任务（包括当前正在执行的）。
func cancel_all_tasks() -> void:
	for task: TaskData in _tasks:
		task.status = TaskData.TaskStatus.CANCELLED
	_tasks.clear()
	_pending_parents.clear()
	# 停止移动
	_target_position = grid_position
	_next_tick_position = grid_position
	_set_state(UnitState.IDLE)
	queue_empty.emit()

## 设置工作速度倍率（Buff 系统用）。
func set_work_speed(multiplier: float) -> void:
	work_speed = maxf(0.1, multiplier)

# ============================================================
# 10. 私有方法 — Tick 驱动（覆写）
# ============================================================

func _on_tick(delta: float) -> void:
	super._on_tick(delta)

	if state == UnitState.DEAD:
		return

	# 处理任务队列：在 IDLE 和 WORKING 状态下推进任务
	# MOVING 状态由 UnitBase 处理移动，不在此处处理任务
	if state != UnitState.MOVING:
		_process_task_queue(delta)

# ============================================================
# 10. 私有方法 — 任务队列处理
# ============================================================

## 处理任务队列：取出队首任务，根据状态分发。
func _process_task_queue(_delta: float) -> void:
	if _tasks.is_empty():
		return

	var current: TaskData = _tasks[0]

	match current.status:
		TaskData.TaskStatus.PENDING:
			_start_task(current)
		TaskData.TaskStatus.IN_PROGRESS:
			_continue_task(current, _delta)
		TaskData.TaskStatus.COMPLETED, TaskData.TaskStatus.FAILED, TaskData.TaskStatus.CANCELLED:
			_finish_task(current)

# ============================================================
# 10. 私有方法 — 任务启动
# ============================================================

## 启动一个 PENDING 任务：验证地块、设置工作参数、开始移动。
func _start_task(task: TaskData) -> void:
	match task.task_type:
		TaskData.TaskType.MOVE:
			_start_move_task(task)
		TaskData.TaskType.PLOW:
			_start_tile_task(task, plow_ticks, _validate_plow)
		TaskData.TaskType.PLANT:
			_start_tile_task(task, plant_ticks, _validate_plant)
		TaskData.TaskType.HARVEST:
			_start_tile_task(task, harvest_ticks, _validate_harvest)
		TaskData.TaskType.DIG:
			_start_tile_task(task, dig_ticks, _validate_dig)
		TaskData.TaskType.WAIT:
			_start_wait_task(task)
		_:
			task.status = TaskData.TaskStatus.FAILED
			_push_failed(task, "未知任务类型: %d" % task.task_type)

## 纯移动任务：设置目标并进入 MOVING 状态。
func _start_move_task(task: TaskData) -> void:
	task.status = TaskData.TaskStatus.IN_PROGRESS
	task.total_ticks = 0
	_set_move_target_world(_tile_to_world(task.target_tile))
	_set_state(UnitState.MOVING)
	animation_controller.play("walk")
	_start_footstep_sfx()

## 地块操作任务（PLOW/PLANT/HARVEST/DIG）：验证 → 开始移动阶段。
func _start_tile_task(task: TaskData, base_ticks: int, validator: Callable) -> void:
	var reason: String = validator.call(task)
	if not reason.is_empty():
		task.status = TaskData.TaskStatus.FAILED
		_push_failed(task, reason)
		return

	task.status = TaskData.TaskStatus.IN_PROGRESS
	task.total_ticks = maxi(1, int(ceil(float(base_ticks) / work_speed)))

	# 检查是否已在目标地块相邻格
	if is_adjacent_to(task.target_tile):
		# 已在相邻格，直接进入工作阶段
		_begin_work_phase(task)
	else:
		# 需要移动：找到最近的相邻可通行格
		var move_target: Vector2i = _find_nearest_adjacent(task.target_tile)
		if move_target == Vector2i.ZERO and not is_adjacent_to(task.target_tile):
			# 找不到可到达的相邻格（被包围）
			task.status = TaskData.TaskStatus.FAILED
			_push_failed(task, "目标地块不可到达")
			return
		# 进入移动阶段
		_set_move_target_world(_tile_to_world(move_target))
		_set_state(UnitState.MOVING)
		animation_controller.play("walk")
		_start_footstep_sfx()

## 等待任务。
func _start_wait_task(task: TaskData) -> void:
	task.status = TaskData.TaskStatus.IN_PROGRESS
	task.total_ticks = task.params.get("duration_ticks", 0)

# ============================================================
# 10. 私有方法 — 任务继续
# ============================================================

## 继续执行 IN_PROGRESS 任务。
func _continue_task(task: TaskData, _delta: float) -> void:
	match task.task_type:
		TaskData.TaskType.MOVE:
			_continue_move_task(task)
		TaskData.TaskType.PLOW, TaskData.TaskType.PLANT, TaskData.TaskType.HARVEST, TaskData.TaskType.DIG:
			_continue_tile_task(task)
		TaskData.TaskType.WAIT:
			_continue_wait_task(task)

## 继续移动任务：若已到达则完成。
func _continue_move_task(task: TaskData) -> void:
	if state == UnitState.IDLE:
		# 移动已完成（move_completed 信号触发状态切换）
		task.status = TaskData.TaskStatus.COMPLETED
		_stop_footstep_sfx()

## 继续地块操作任务：移动阶段完成后进入工作阶段，工作完成后执行动作。
func _continue_tile_task(task: TaskData) -> void:
	if state == UnitState.MOVING:
		return  # 还在移动中，等待 move_completed

	if state == UnitState.IDLE and not is_adjacent_to(task.target_tile):
		# 移动完成但不在相邻格（可能目标移动了），重新寻路
		var move_target: Vector2i = _find_nearest_adjacent(task.target_tile)
		_set_move_target_world(_tile_to_world(move_target))
		_set_state(UnitState.MOVING)
		animation_controller.play("walk")
		_start_footstep_sfx()
		return

	# 工作阶段
	if state != UnitState.WORKING:
		# 刚完成移动，开始工作
		if is_adjacent_to(task.target_tile):
			_begin_work_phase(task)
		return

	# 推进工作进度
	task.elapsed_ticks += 1
	task.progress = clampf(float(task.elapsed_ticks) / float(task.total_ticks), 0.0, 1.0)

	if task.progress >= 1.0:
		# 工作完成，执行实际操作
		_execute_task_action(task)
		task.status = TaskData.TaskStatus.COMPLETED

## 继续等待任务。
func _continue_wait_task(task: TaskData) -> void:
	task.elapsed_ticks += 1
	if task.total_ticks > 0:
		task.progress = clampf(float(task.elapsed_ticks) / float(task.total_ticks), 0.0, 1.0)
	if task.elapsed_ticks >= task.total_ticks:
		task.status = TaskData.TaskStatus.COMPLETED

# ============================================================
# 10. 私有方法 — 任务完成
# ============================================================

## 完成任务：从队列移除，检查父任务，发出信号。
func _finish_task(task: TaskData) -> void:
	_tasks.pop_front()

	match task.status:
		TaskData.TaskStatus.COMPLETED:
			task_completed.emit(task)
		TaskData.TaskStatus.FAILED:
			task_failed.emit(task, "执行失败")
		TaskData.TaskStatus.CANCELLED:
			task_failed.emit(task, "已取消")

	# 检查是否有父任务的所有子任务都完成了
	_check_parent_completion()

	# 回到 IDLE 或处理下一个任务
	if _tasks.is_empty():
		_set_state(UnitState.IDLE)
		animation_controller.play("idle")
		queue_empty.emit()
	else:
		# 有下一个任务，继续处理（在下一个 tick 中）
		pass

# ============================================================
# 10. 私有方法 — 工作阶段
# ============================================================

## 开始工作阶段：播放工作动画和音效。
func _begin_work_phase(task: TaskData) -> void:
	_set_state(UnitState.WORKING)
	var anim_name: StringName = _get_work_animation(task.task_type)
	var sound_path: String = _get_work_sound(task.task_type)

	# 播放工作动画
	var duration: float = float(task.total_ticks) * TickSystem.tick_interval
	animation_controller.play_work(anim_name, duration)

	# 播放工作音效
	_play_work_sfx(sound_path)

## 执行任务的实际操作（调用 TileActions 等）。
func _execute_task_action(task: TaskData) -> void:
	var world: Node2D = _get_world()
	if world == null:
		task.status = TaskData.TaskStatus.FAILED
		return

	var tiles: Array[Vector2i] = [task.target_tile]

	match task.task_type:
		TaskData.TaskType.PLOW:
			TileActions.plow_tiles(tiles, world)
		TaskData.TaskType.PLANT:
			var crop_id: String = task.params.get("crop_id", "wheat_tier1")
			TileActions.plant_crop(tiles, crop_id, world)
		TaskData.TaskType.HARVEST:
			TileActions.harvest_crop(tiles, world)
		TaskData.TaskType.DIG:
			TileActions.dig_tiles(tiles, world)
		_:
			pass

# ============================================================
# 10. 私有方法 — 验证
# ============================================================

## 验证地块是否可以翻耕。返回空字符串表示通过，否则返回失败原因。
func _validate_plow(task: TaskData) -> String:
	var world: Node2D = _get_world()
	if world == null:
		return "无法获取世界节点"
	var tile: Node2D = _find_tile(world, task.target_tile)
	if tile == null:
		return "地块不存在"
	if not tile.has_method("can_be_plowed"):
		return "地块不支持翻耕"
	if not tile.can_be_plowed():
		return "该地块不可翻耕"
	return ""

## 验证地块是否可以种植。返回空字符串表示通过。
func _validate_plant(task: TaskData) -> String:
	var world: Node2D = _get_world()
	if world == null:
		return "无法获取世界节点"
	var tile: Node2D = _find_tile(world, task.target_tile)
	if tile == null:
		return "地块不存在"
	# 检查是否为农田
	var tile_data = _get_tile_data(tile)
	if tile_data == null:
		return "无法获取地块数据"
	if tile_data.tile_type != 3:  # TileType.FARMLAND
		return "该地块不是农田"
	# 检查是否已有作物
	if tile.has_method("has_occupant_of_type"):
		if tile.has_occupant_of_type("Crop"):
			return "该地块已有作物"
	return ""

## 验证地块是否可以收获。返回空字符串表示通过。
func _validate_harvest(task: TaskData) -> String:
	var world: Node2D = _get_world()
	if world == null:
		return "无法获取世界节点"
	var tile: Node2D = _find_tile(world, task.target_tile)
	if tile == null:
		return "地块不存在"
	# 检查是否有作物
	if not tile.has_method("has_occupant_of_type") or not tile.has_occupant_of_type("Crop"):
		return "该地块没有作物"
	# 检查作物是否成熟
	if tile.has_method("get_all_occupants"):
		var occupants: Array = tile.get_all_occupants()
		for occ: Node in occupants:
			if is_instance_valid(occ) and occ.has_method("is_mature"):
				if not occ.is_mature():
					return "作物尚未成熟"
				return ""
	return "无法确认作物状态"

## 验证地块是否可以挖掘。返回空字符串表示通过。
func _validate_dig(task: TaskData) -> String:
	var world: Node2D = _get_world()
	if world == null:
		return "无法获取世界节点"
	var tile: Node2D = _find_tile(world, task.target_tile)
	if tile == null:
		return "地块不存在"
	if not tile.has_method("can_be_dug"):
		return "地块不支持挖掘"
	if not tile.can_be_dug():
		return "该地块不可挖掘"
	return ""

# ============================================================
# 10. 私有方法 — 父任务
# ============================================================

## 检查待完成父任务列表，若有父任务的所有子任务都完成了则标记父任务为完成。
func _check_parent_completion() -> void:
	var completed_parents: Array[TaskData] = []
	for parent: TaskData in _pending_parents:
		if parent.are_child_tasks_completed():
			parent.status = TaskData.TaskStatus.COMPLETED
			completed_parents.append(parent)
			task_completed.emit(parent)

	for parent: TaskData in completed_parents:
		_pending_parents.erase(parent)

# ============================================================
# 10. 私有方法 — 移动辅助
# ============================================================

## 移动阶段完成时的回调（覆写 UnitBase 信号处理）。
func _on_move_completed() -> void:
	_stop_footstep_sfx()
	# 检查队列中是否有 IN_PROGRESS 的地块任务需要进入工作阶段
	if not _tasks.is_empty():
		var current: TaskData = _tasks[0]
		if current.status == TaskData.TaskStatus.IN_PROGRESS:
			match current.task_type:
				TaskData.TaskType.PLOW, TaskData.TaskType.PLANT, TaskData.TaskType.HARVEST, TaskData.TaskType.DIG:
					if is_adjacent_to(current.target_tile):
						_begin_work_phase(current)

## 查找目标地块最近的可通行相邻格。
## 返回 [code]Vector2i.ZERO[/code] 表示无可通行相邻格（被包围）。
func _find_nearest_adjacent(target_tile: Vector2i) -> Vector2i:
	var world: Node2D = _get_world()
	if world == null:
		return target_tile  # 降级：直接移动到目标地块位置

	var adjacents: Array[Vector2i] = get_adjacent_cells(target_tile)
	var best: Vector2i = Vector2i.ZERO
	var best_dist: float = INF

	for adj: Vector2i in adjacents:
		var tile: Node2D = _find_tile(world, adj)
		if tile == null:
			continue
		# 检查是否可通行
		if tile.has_method("is_passable") and tile.is_passable():
			var dist: float = grid_position.distance_to(Vector2(adj.x * TILE_SIZE, adj.y * TILE_SIZE))
			if dist < best_dist:
				best_dist = dist
				best = adj

	return best

# ============================================================
# 10. 私有方法 — 音效
# ============================================================

## 开始循环播放行走音效。
func _start_footstep_sfx() -> void:
	if _footstep_player:
		return
	var footstep_path: String = _config_cache.get("sounds", {}).get("footstep", "")
	if footstep_path.is_empty() or not ResourceLoader.exists(footstep_path):
		return
	var stream: AudioStream = load(footstep_path) as AudioStream
	if stream:
		_footstep_player = audio_controller.play_looping(stream)

## 停止行走音效。
func _stop_footstep_sfx() -> void:
	if _footstep_player:
		audio_controller.stop_looping(_footstep_player)
		_footstep_player = null

## 播放工作音效（一次性）。
func _play_work_sfx(sound_path: String) -> void:
	if sound_path.is_empty() or not ResourceLoader.exists(sound_path):
		return
	var stream: AudioStream = load(sound_path) as AudioStream
	if stream:
		audio_controller.play_sfx(stream)

## 获取任务类型对应的工作动画名称。
func _get_work_animation(task_type: int) -> StringName:
	var anims: Dictionary = _config_cache.get("animations", {})
	match task_type:
		TaskData.TaskType.PLOW:
			return anims.get("plow", "plow")
		TaskData.TaskType.PLANT:
			return anims.get("plant", "plant")
		TaskData.TaskType.HARVEST:
			return anims.get("harvest", "harvest")
		TaskData.TaskType.DIG:
			return anims.get("plow", "plow")  # 挖掘复用翻耕动画
		_:
			return "idle"

## 获取任务类型对应的工作音效路径。
func _get_work_sound(task_type: int) -> String:
	var sounds: Dictionary = _config_cache.get("sounds", {})
	match task_type:
		TaskData.TaskType.PLOW:
			return sounds.get("plow", "")
		TaskData.TaskType.PLANT:
			return sounds.get("plant", "")
		TaskData.TaskType.HARVEST:
			return sounds.get("harvest", "")
		TaskData.TaskType.DIG:
			return sounds.get("plow", "")
		_:
			return ""

# ============================================================
# 10. 私有方法 — 世界交互
# ============================================================

## 获取世界节点（通过 group "world" 缓存）。
func _get_world() -> Node2D:
	if _world_cache and is_instance_valid(_world_cache):
		return _world_cache
	_world_cache = get_tree().get_first_node_in_group("world") as Node2D
	return _world_cache

## 在 world 中按网格坐标查找地块节点。
func _find_tile(world: Node2D, grid_pos: Vector2i) -> Node2D:
	var tile_name: String = "tile_%d_%d" % [grid_pos.x, grid_pos.y]
	var tile: Node = world.get_node_or_null(tile_name)
	if tile and tile is Node2D:
		return tile as Node2D
	return null

## 获取地块的 TileInfo 数据。
func _get_tile_data(tile: Node2D) -> Resource:
	if tile.has_method("get_tile_data"):
		return tile.get_tile_data()
	if tile.has_meta("tile_data"):
		return tile.get_meta("tile_data")
	return null

## 网格坐标转世界坐标（地块中心）。
func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

# ============================================================
# 10. 私有方法 — 工具
# ============================================================

## 推送任务失败日志并发出信号。
func _push_failed(task: TaskData, reason: String) -> void:
	push_warning("FarmWorker: 任务 %d (%s) 失败: %s" % [task.task_id, task.get_type_name(), reason])

## 加载 JSON 配置文件。
func _load_config_file() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("FarmWorker: 配置文件不存在: %s" % CONFIG_PATH)
		return {}

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("FarmWorker: 无法打开配置文件: %s" % CONFIG_PATH)
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("FarmWorker: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return {}

	var data = json.data
	if data is Dictionary:
		return data as Dictionary

	push_error("FarmWorker: 配置文件顶层应为 JSON 对象")
	return {}

# ============================================================
# 8. 生命周期方法 — 信号连接
# ============================================================

func _ready() -> void:
	super._ready()
	# 监听移动完成信号，用于地块任务从移动阶段切换到工作阶段
	if not move_completed.is_connected(_on_move_completed):
		move_completed.connect(_on_move_completed)
