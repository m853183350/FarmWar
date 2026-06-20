## 调试工具 — 挂载在 main 场景中。
##
## 负责：
##   - 在开发阶段生成测试工人
##   - 向 [DebugOverlay]（右侧）写入 tick 等通用调试数据
##   - 向 [DebugOverlayLeft]（左侧）写入工人任务队列和待分配任务数据
##   - 通过信号监听工人状态变化，实时刷新左侧调试面板
extends Node

const TaskDataClass: GDScript = preload("res://scripts/units/task_data.gd")
@export var ModeSelector: Node

@export var player:Node
# ============================================================
# 3. 常量
# ============================================================

## 定时刷新间隔（秒）。用于捕获没有信号通知的变更（如 pending_tasks 新增）。
const PERIODIC_REFRESH_INTERVAL: float = 0.5

# ============================================================
# 6. 私有变量
# ============================================================

## 已连接的 task_added 信号映射 worker -> bool，防止重复连接。
var _worker_task_added_connected: Dictionary = {}

## 定时刷新计时器（秒）。
var _periodic_refresh_timer: float = 0.0

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 生成测试工人
	UnitManager.spawn_worker(Vector2i(5, 3))
	UnitManager.spawn_worker(Vector2i(5, 4))
	UnitManager.spawn_worker(Vector2i(5, 5))
	
	# UnitManager.spawn_worker(Vector2i(5, 3))
	# UnitManager.spawn_worker(Vector2i(5, 4))
	# UnitManager.spawn_worker(Vector2i(5, 5))
	
	# UnitManager.spawn_worker(Vector2i(5, 3))
	# UnitManager.spawn_worker(Vector2i(5, 4))
	# UnitManager.spawn_worker(Vector2i(5, 5))
	player.get_node("PropManager").add_prop("sunshine_coin")
	
	# UnitManager.spawn_worker(Vector2i(5, 3))
	# UnitManager.spawn_worker(Vector2i(5, 4))
	# UnitManager.spawn_worker(Vector2i(5, 5))
	# 启动时加本科选项
	ModeSelector.add_mode_for_family("Poaceae")
	EventBus.mode_changed.connect(_show_mode_change)

	# 连接工人相关信号
	_connect_worker_signals()

	# 延迟初始刷新，确保所有 worker 的 _ready 已完成
	_refresh_worker_display.call_deferred()

func _process(delta: float) -> void:
	DebugOverlay.set_entry("tick", TickSystem.get_tick_count())
	DebugOverlay.set_entry("tick_ms", "%.2f" % TickSystem.tick_computation_time_ms)
	DebugOverlay.set_entry("tick_avg_1s", "%.2f" % TickSystem.tick_avg_time_ms)
	DebugOverlay.set_entry("tick_max_5s", "%.2f" % TickSystem.tick_max_time_5s_ms)

	# 定时刷新左侧面板，捕获无信号通知的变更（如 pending_tasks 新增）
	_periodic_refresh_timer += delta
	if _periodic_refresh_timer >= PERIODIC_REFRESH_INTERVAL:
		_periodic_refresh_timer = 0.0
		_refresh_worker_display()

func _print_loop() -> void:
	print("每秒print一次")
	await get_tree().create_timer(1.0)
	_print_loop()

func _show_mode_change(name: StringName) -> void:
	DebugOverlay.set_entry("当前模式：", name)
	return

# ============================================================
# 10. 私有方法 — 信号连接
# ============================================================

## 连接到所有工人相关的全局信号。
func _connect_worker_signals() -> void:
	# EventBus 全局信号
	if not EventBus.worker_state_changed.is_connected(_on_worker_state_changed):
		EventBus.worker_state_changed.connect(_on_worker_state_changed)
	if not EventBus.worker_task_completed.is_connected(_on_worker_task_completed):
		EventBus.worker_task_completed.connect(_on_worker_task_completed)
	if not EventBus.worker_queue_empty.is_connected(_on_worker_queue_empty):
		EventBus.worker_queue_empty.connect(_on_worker_queue_empty)

	# UnitManager 信号
	if not UnitManager.worker_spawned.is_connected(_on_worker_spawned):
		UnitManager.worker_spawned.connect(_on_worker_spawned)
	if not UnitManager.worker_removed.is_connected(_on_worker_removed):
		UnitManager.worker_removed.connect(_on_worker_removed)
	if not UnitManager.task_assigned.is_connected(_on_task_assigned):
		UnitManager.task_assigned.connect(_on_task_assigned)

	# 连接已存在工人的 task_added 信号
	for worker: FarmWorker in UnitManager.get_all_workers():
		_connect_worker_task_added(worker)

## 连接指定工人的 task_added 信号（防止重复）。
func _connect_worker_task_added(worker: FarmWorker) -> void:
	var key: StringName = worker.unit_id
	if _worker_task_added_connected.get(key, false):
		return
	if not worker.task_added.is_connected(_on_worker_task_added):
		worker.task_added.connect(_on_worker_task_added.bind(worker))
	_worker_task_added_connected[key] = true

## 断开指定工人的 task_added 信号。
func _disconnect_worker_task_added(worker: FarmWorker) -> void:
	var key: StringName = worker.unit_id
	if worker.task_added.is_connected(_on_worker_task_added):
		worker.task_added.disconnect(_on_worker_task_added)
	_worker_task_added_connected.erase(key)

# ============================================================
# 10. 私有方法 — 信号回调
# ============================================================

func _on_worker_state_changed(worker_id: StringName, _old_state: int, _new_state: int) -> void:
	_refresh_worker_display()

func _on_worker_task_completed(_worker_id: StringName, _task: TaskData) -> void:
	_refresh_worker_display()

func _on_worker_queue_empty(_worker_id: StringName) -> void:
	_refresh_worker_display()

func _on_worker_spawned(worker_id: StringName) -> void:
	var worker: FarmWorker = UnitManager.find_worker(worker_id)
	if worker:
		_connect_worker_task_added(worker)
	_refresh_worker_display()

func _on_worker_removed(_worker_id: StringName) -> void:
	# 清理连接记录（worker 已 queue_free，信号自动断开）
	_worker_task_added_connected.erase(_worker_id)
	_refresh_worker_display()

func _on_task_assigned(_task: TaskData, _worker_id: StringName) -> void:
	_refresh_worker_display()

func _on_worker_task_added(_task: TaskData, _worker: FarmWorker) -> void:
	_refresh_worker_display()

# ============================================================
# 10. 私有方法 — 刷新左侧调试面板
# ============================================================

## 读取所有工人的任务列表和待分配任务，更新 [DebugOverlayLeft]。
##
## 按键排序规则：
##   - W{idx:02d}_* — 工人信息（idx 按 unit_id 排序后的序号）
##   - ZZ_* — 待分配任务（排在最后）
##
## 每个工人在 [DebugOverlayLeft] 中占据若干条目：
##   - id: 工人 unit_id
##   - state: 当前状态 (IDLE/MOVING/WORKING/...)
##   - pos: 当前网格坐标
##   - t{idx:02d}: 队列中的任务（按 FIFO 顺序）
##
## 待分配任务：
##   - ZZ_pending_count: 数量
##   - ZZ_p{idx:03d}: 每个待分配任务的简要描述
func _refresh_worker_display() -> void:
	DebugOverlayLeft.clear_entries()

	var all_workers: Array = UnitManager.get_all_workers()

	# 按 unit_id 排序，确保显示顺序稳定
	all_workers.sort_custom(func(a: FarmWorker, b: FarmWorker) -> bool:
		return a.unit_id < b.unit_id
	)

	var idx: int = 0
	for worker: FarmWorker in all_workers:
		if not is_instance_valid(worker):
			continue

		var prefix: String = "W%02d_" % idx

		# 基本信息
		DebugOverlayLeft.set_entry(prefix + "id", worker.unit_id)
		DebugOverlayLeft.set_entry(prefix + "state", _state_name(worker.state))
		var tile: Vector2i = worker.get_current_tile()
		DebugOverlayLeft.set_entry(prefix + "pos", "(%d,%d)" % [tile.x, tile.y])

		# 任务队列
		var tasks: Array[TaskData] = worker.get_tasks()
		if tasks.is_empty():
			DebugOverlayLeft.set_entry(prefix + "t--", "(empty)")
		else:
			for ti: int in range(tasks.size()):
				var tkey: String = prefix + "t%02d" % ti
				var task: TaskData = tasks[ti]
				DebugOverlayLeft.set_entry(tkey, _format_task(task))

		idx += 1

	# 待分配任务（ZZ_ 前缀确保排在最后）
	var pending: Array[TaskData] = UnitManager.pending_tasks
	DebugOverlayLeft.set_entry("ZZ_pending_count", pending.size())
	for pi: int in range(pending.size()):
		var task: TaskData = pending[pi]
		DebugOverlayLeft.set_entry("ZZ_p%03d" % pi, _format_task(task))

# ============================================================
# 10. 私有方法 — 格式化工具
# ============================================================

## 将单位状态枚举值转为可读字符串。
func _state_name(state: int) -> String:
	match state:
		0:
			return "IDLE"
		1:
			return "MOVING"
		2:
			return "WORKING"
		3:
			return "COMBAT"
		4:
			return "DEAD"
		_:
			return "?(%d)" % state

## 将任务格式化为一行摘要字符串。
##
## 格式：[状态标记][进度%] 任务类型→(x,y)
## 示例：
##   - "[▶]50% 种植→(12,8)" — 正在执行中，50% 进度
##   - "[P] 翻耕→(15,3)"     — 等待中
##   - "[✓] 收获→(20,5)"     — 已完成
func _format_task(task: TaskData) -> String:
	var status_char: String = _task_status_char(task.status)
	var type_str: String = task.get_type_name()
	var tile_str: String = "(%d,%d)" % [task.target_tile.x, task.target_tile.y]

	var prog: String = ""
	if task.status == TaskDataClass.TaskStatus.IN_PROGRESS and task.total_ticks > 0:
		prog = "%d%%" % int(task.progress * 100)

	if prog.is_empty():
		return "%s %s→%s" % [status_char, type_str, tile_str]
	else:
		return "%s%s %s→%s" % [status_char, prog, type_str, tile_str]

## 将任务状态枚举值转为单字符标记。
func _task_status_char(status: int) -> String:
	match status:
		0:
			return "[P]"     # PENDING
		1:
			return "[▶]"     # IN_PROGRESS
		2:
			return "[✓]"     # COMPLETED
		3:
			return "[✗]"     # FAILED
		4:
			return "[✕]"     # CANCELLED
		_:
			return "[?]"
