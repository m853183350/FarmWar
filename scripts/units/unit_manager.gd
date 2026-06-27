## 单位管理器 — Autoload 全局单例。
##
## 负责所有作战单位的生命周期管理：生成、注册、注销、查询和任务分配。
## 维护全局待分配任务池，在工人空闲时自动分配。
##
## 通过 Autoload 全局访问：[code]UnitManager[/code]
##
## 使用方式：
##   [code]UnitManager.spawn_worker(Vector2i(5, 3))[/code]
##   [code]UnitManager.distribute_tasks(task_list)[/code]
extends Node

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

# ============================================================
# 1. 信号
# ============================================================

## 工人被生成时发出。
signal worker_spawned(worker_id: StringName)

## 工人被移除时发出。
signal worker_removed(worker_id: StringName)

## 任务成功分配到工人时发出。
signal task_assigned(task: TaskData, worker_id: StringName)

# ============================================================
# 3. 常量
# ============================================================

## 农场工人场景路径。
const FARM_WORKER_SCENE: String = "res://scenes/units/player_units/farm_worker.tscn"
const debug_print_flag: bool = false

# ============================================================
# 5. 公开变量
# ============================================================

## 已注册的工人字典 { unit_id: FarmWorker }。
var workers: Dictionary = {}

## 全局待分配任务池。工人队列满时，多余任务暂存于此。
var pending_tasks: Array[TaskData] = []

# ============================================================
# 6. 私有变量
# ============================================================

## 工人自增 ID 计数器。
var _worker_id_counter: int = 0

# ============================================================
# 9. 公开方法 — 生成与销毁
# ============================================================

## 在指定网格位置生成一个农场工人。
## 返回生成的 [FarmWorker] 实例。场景加载失败或 world 不可用时返回 null。
func spawn_worker(grid_pos: Vector2i) -> FarmWorker:
	if debug_print_flag:
		print("UnitManager: 请求生成工人于 %s" % grid_pos)
	var world: Node2D = WorldUtils.get_world()
	if world == null:
		push_error("UnitManager: 无法获取 world 节点，不能生成工人")
		return null

	var scene: PackedScene = load(FARM_WORKER_SCENE) as PackedScene
	if scene == null:
		push_error("UnitManager: 无法加载农场工人场景: %s" % FARM_WORKER_SCENE)
		return null

	var worker: FarmWorker = scene.instantiate() as FarmWorker
	_worker_id_counter += 1
	worker.unit_id = "farm_worker_%d" % _worker_id_counter
	worker.name = worker.unit_id

	# 设置初始位置
	var world_pos: Vector2 = Vector2(grid_pos.x * 64, grid_pos.y * 64)
	worker.global_position = world_pos
	worker.grid_position = world_pos

	world.add_child(worker)
	_register_worker(worker)

	if debug_print_flag:
		print("UnitManager: 生成工人 %s 于 %s" % [worker.unit_id, grid_pos])
	worker_spawned.emit(worker.unit_id)
	return worker

## 移除指定工人。
func remove_worker(worker: FarmWorker) -> void:
	if worker == null:
		return
	var worker_id: StringName = worker.unit_id
	_unregister_worker(worker)

	# 将该工人的待执行任务回收到全局池
	var tasks: Array[TaskData] = worker.get_tasks()
	for task: TaskData in tasks:
		if task.status == TaskData.TaskStatus.PENDING:
			pending_tasks.append(task)
	worker.cancel_all_tasks()

	worker.queue_free()
	print("UnitManager: 移除工人 %s" % worker_id)
	worker_removed.emit(worker_id)

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 查找指定数量的空闲工人（state == IDLE 且队列未满）。
func find_idle_workers(count: int = 1) -> Array[FarmWorker]:
	var result: Array[FarmWorker] = []
	for worker: FarmWorker in workers.values():
		if is_instance_valid(worker) and worker.is_idle() and not worker.is_queue_full():
			result.append(worker)
			if result.size() >= count:
				break
	return result

## 根据 unit_id 查找工人。返回 null 表示未找到。
func find_worker(worker_id: StringName) -> FarmWorker:
	if workers.has(worker_id):
		var worker: FarmWorker = workers[worker_id] as FarmWorker
		if is_instance_valid(worker):
			return worker
	return null

## 获取所有存活的工人。
func get_all_workers() -> Array[FarmWorker]:
	var result: Array[FarmWorker] = []
	for worker: FarmWorker in workers.values():
		if is_instance_valid(worker):
			result.append(worker)
	return result

## 获取全局待分配任务数。
func get_pending_task_count() -> int:
	return pending_tasks.size()

# ============================================================
# 9. 公开方法 — 任务分配
# ============================================================

## 分配任务列表到可用工人。
## 优先分配给空闲工人，剩余任务进入全局待分配池。
## 返回成功分配的任务数。
func distribute_tasks(tasks: Array[TaskData]) -> int:
	if debug_print_flag:
		print("UnitManager: 开始请求分配 %d 个任务" % tasks.size())
	var assigned_count: int = 0
	var idle_workers: Array[FarmWorker] = find_idle_workers(tasks.size() * 2)

	for task: TaskData in tasks:
		var assigned: bool = _try_assign_task(task, idle_workers)
		if assigned:
			assigned_count += 1
		else:
			pending_tasks.append(task)

	if assigned_count > 0:
		print("UnitManager: 分配了 %d 个任务到工人，%d 个进入待分配池" % [assigned_count, tasks.size() - assigned_count])

	return assigned_count

## 将单个任务分配给最合适的工人（当前采用最近优先策略）。
func _try_assign_task(task: TaskData, idle_workers: Array[FarmWorker]) -> bool:
	# 筛掉队列已满的工人
	var available: Array[FarmWorker] = []
	for w: FarmWorker in idle_workers:
		if is_instance_valid(w) and not w.is_queue_full():
			available.append(w)

	if available.is_empty():
		return false

	# 最近优先策略：分配给距离目标地块最近的工人
	var best_worker: FarmWorker = available[0]
	var best_dist: float = INF

	for w: FarmWorker in available:
		var dist: float = w.grid_position.distance_to(
			Vector2(task.target_tile.x * 64, task.target_tile.y * 64)
		)
		if dist < best_dist:
			best_dist = dist
			best_worker = w

	if best_worker:
		best_worker.add_task(task)
		task_assigned.emit(task, best_worker.unit_id)
		return true

	return false

## 尝试将待分配池中的任务分配给指定工人。
## 在工人完成任务后调用。
func _try_assign_pending_to_worker(worker: FarmWorker) -> void:
	if pending_tasks.is_empty():
		return
	if not is_instance_valid(worker) or worker.is_queue_full():
		return

	var task: TaskData = pending_tasks.pop_front()
	worker.add_task(task)
	task_assigned.emit(task, worker.unit_id)

# ============================================================
# 10. 私有方法 — 注册管理
# ============================================================

## 注册工人到管理字典。
func _register_worker(worker: FarmWorker) -> void:
	workers[worker.unit_id] = worker

	# 连接信号以跟踪任务完成
	if not worker.task_completed.is_connected(_on_worker_task_completed):
		worker.task_completed.connect(_on_worker_task_completed.bind(worker))
	if not worker.queue_empty.is_connected(_on_worker_queue_empty):
		worker.queue_empty.connect(_on_worker_queue_empty.bind(worker))
	if not worker.state_changed.is_connected(_on_worker_state_changed):
		worker.state_changed.connect(_on_worker_state_changed.bind(worker))

## 注销工人。
func _unregister_worker(worker: FarmWorker) -> void:
	workers.erase(worker.unit_id)
	if worker.task_completed.is_connected(_on_worker_task_completed):
		worker.task_completed.disconnect(_on_worker_task_completed)
	if worker.queue_empty.is_connected(_on_worker_queue_empty):
		worker.queue_empty.disconnect(_on_worker_queue_empty)
	if worker.state_changed.is_connected(_on_worker_state_changed):
		worker.state_changed.disconnect(_on_worker_state_changed)

# ============================================================
# 10. 私有方法 — 信号回调
# ============================================================

## 工人完成一个任务时：发出 EventBus 广播，尝试分配待分配池中的任务。
func _on_worker_task_completed(_task: TaskData, worker: FarmWorker) -> void:
	if EventBus:
		EventBus.worker_task_completed.emit(worker.unit_id, _task)
	_try_assign_pending_to_worker(worker)

## 工人状态变化时：发出 EventBus 广播。
func _on_worker_state_changed(old_state: int, new_state: int, worker: FarmWorker) -> void:
	if EventBus:
		EventBus.worker_state_changed.emit(worker.unit_id, old_state, new_state)

## 工人队列清空时：发出 EventBus 广播，尝试分配待分配池中的剩余任务。
func _on_worker_queue_empty(worker: FarmWorker) -> void:
	if EventBus:
		EventBus.worker_queue_empty.emit(worker.unit_id)

	# 尝试分配待分配池中的所有任务
	while not pending_tasks.is_empty() and not worker.is_queue_full():
		var task: TaskData = pending_tasks.pop_front()
		worker.add_task(task)
		task_assigned.emit(task, worker.unit_id)

# ============================================================
# 10. 私有方法 — 世界查找（已迁移至 WorldUtils）
# ============================================================
