## Tick 系统，管理游戏逻辑时钟。
## 使用独立线程运行 tick 循环，通过 [method Object.call_deferred] 将信号发射回主线程，
## 避免计时器逻辑阻塞渲染管线。内置性能仪表，可追踪每次 tick 的计算耗时。
##
## 与画面渲染分离，以固定间隔发出 [signal tick_elapsed] 信号。
## 各游戏系统监听该信号执行逻辑更新，确保帧率无关的行为一致。
##
## 通过 Autoload 全局访问：[code]TickSystem[/code]
extends Node

# ============================================================
# 1. 信号
# ============================================================

## 每次 tick 触发时发出，传递本次 tick 的间隔时间（秒）。
signal tick_elapsed(delta: float)

# ============================================================
# 3. 常量
# ============================================================

## 默认 tick 间隔（秒）：50ms = 每秒 20 tick。
const DEFAULT_TICK_INTERVAL: float = 0.05

## tick 间隔的最小值（秒），防止设置过低导致性能问题。
const MIN_TICK_INTERVAL: float = 0.01

## tick 间隔的最大值（秒）。
const MAX_TICK_INTERVAL: float = 1.0

## 性能仪表：平均时间窗口（秒）。
const AVG_WINDOW_SECONDS: float = 1.0

## 性能仪表：最大时间窗口（秒）。
const MAX_WINDOW_SECONDS: float = 5.0

## 线程休眠步长（毫秒），越小停止响应越快但 CPU 唤醒越多。
const THREAD_SLEEP_STEP_MSEC: int = 10

# ============================================================
# 4. @export 变量
# ============================================================

## 启动时是否自动开始 tick。
@export var auto_start: bool = false

# ============================================================
# 5. 公开变量
# ============================================================

## 当前 tick 间隔（秒），可在运行时修改。
var tick_interval: float = DEFAULT_TICK_INTERVAL

## 性能仪表 — 上一次 tick 的实际计算耗时（毫秒）。
## 在 [signal tick_elapsed] 信号的所有监听器执行完毕后更新。
var tick_computation_time_ms: float = 0.0

## 性能仪表 — 最近 1 秒内每次 tick 计算时间的平均值（毫秒）。
var tick_avg_time_ms: float = 0.0

## 性能仪表 — 最近 5 秒内 tick 计算时间的最大值（毫秒）。
var tick_max_time_5s_ms: float = 0.0

# ============================================================
# 6. 私有变量
# ============================================================

var _thread: Thread = null
var _mutex: Mutex = null
var _is_running: bool = false
var _is_paused: bool = false
var _tick_count: int = 0
var _should_stop: bool = false

## 背压标志：当主线程正在处理 tick 时置为 true，线程在此期间不提交新 tick。
## 避免 call_deferred 堆积导致级联帧丢失。
var _tick_pending: bool = false

## 性能追踪 — 环形缓冲区，每条记录为 {time_usec: int, elapsed_ms: float}。
var _tick_time_records: Array[Dictionary] = []

# ============================================================
# 7. @onready 变量
# ============================================================

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_mutex = Mutex.new()
	if auto_start:
		start()

func _exit_tree() -> void:
	stop()

# ============================================================
# 9. 公开方法
# ============================================================

## 启动 tick 循环（创建并运行工作线程）。
## 如果已在运行则无操作。
func start() -> void:
	if _is_running:
		return
	_should_stop = false
	_is_running = true
	_thread = Thread.new()
	_thread.start(_thread_loop)

## 停止 tick 循环并等待工作线程结束。
## 如果未在运行则无操作。
func stop() -> void:
	if not _is_running:
		return
	_should_stop = true
	_thread.wait_to_finish()
	_thread = null
	_is_running = false

## 暂停 tick（计时器继续运行但信号不触发）。
func pause() -> void:
	_mutex.lock()
	_is_paused = true
	_mutex.unlock()

## 恢复 tick。
func resume() -> void:
	_mutex.lock()
	_is_paused = false
	_mutex.unlock()

## 修改 tick 间隔并立即生效。
func set_tick_interval(interval: float) -> void:
	_mutex.lock()
	tick_interval = clampf(interval, MIN_TICK_INTERVAL, MAX_TICK_INTERVAL)
	_mutex.unlock()

## 获取当前 tick 序号（从启动开始计数）。
func get_tick_count() -> int:
	_mutex.lock()
	var count: int = _tick_count
	_mutex.unlock()
	return count

## 获取暂停状态。
func is_paused() -> bool:
	_mutex.lock()
	var paused: bool = _is_paused
	_mutex.unlock()
	return paused

# ============================================================
# 10. 私有方法 — 线程
# ============================================================

## 工作线程主循环。
## 以 [member tick_interval] 为周期休眠，到期后通过
## [method call_deferred] 将 tick 处理调度到主线程。
## 使用背压机制防止 tick 堆积。
func _thread_loop() -> void:
	while not _should_stop:
		# 读取当前间隔（线程安全）
		_mutex.lock()
		var interval: float = tick_interval
		_mutex.unlock()

		# 分段休眠，以便在 [method stop] 调用后快速响应
		var total_ms: int = maxi(1, int(interval * 1000.0))
		var remaining_ms: int = total_ms
		while remaining_ms > 0 and not _should_stop:
			var sleep_ms: int = mini(THREAD_SLEEP_STEP_MSEC, remaining_ms)
			OS.delay_msec(sleep_ms)
			remaining_ms -= sleep_ms

		if _should_stop:
			return

		# 背压检查：如果上一个 tick 尚未处理完毕则跳过本次
		_mutex.lock()
		if not _tick_pending:
			_tick_pending = true
			_mutex.unlock()
			call_deferred("_on_tick_deferred")
		else:
			_mutex.unlock()

## 主线程回调，由 [method call_deferred] 从工作线程调度执行。
## 负责测量耗时、发射信号并更新性能仪表。
func _on_tick_deferred() -> void:
	# 防御：stop() 后可能仍有已入队的 call_deferred
	if not _is_running:
		return

	_mutex.lock()
	var paused: bool = _is_paused
	_mutex.unlock()

	if paused:
		_mutex.lock()
		_tick_pending = false
		_mutex.unlock()
		return

	# 测量 tick 处理耗时
	var start_usec: int = Time.get_ticks_usec()

	_mutex.lock()
	_tick_count += 1
	var current_interval: float = tick_interval
	_mutex.unlock()

	tick_elapsed.emit(current_interval)

	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	tick_computation_time_ms = elapsed_ms

	# 记录并更新性能仪表
	_update_performance_metrics(elapsed_ms)

	# 释放背压
	_mutex.lock()
	_tick_pending = false
	_mutex.unlock()

# ============================================================
# 10. 私有方法 — 性能追踪
# ============================================================

## 将本次耗时追加到环形缓冲区，并重新计算平均值与最大值。
func _update_performance_metrics(elapsed_ms: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	_tick_time_records.append({
		"time_usec": now_usec,
		"elapsed_ms": elapsed_ms,
	})

	var avg_cutoff: int = now_usec - int(AVG_WINDOW_SECONDS * 1_000_000.0)
	var max_cutoff: int = now_usec - int(MAX_WINDOW_SECONDS * 1_000_000.0)

	var sum_ms: float = 0.0
	var avg_count: int = 0
	var max_ms: float = 0.0

	# 反向遍历，同时清理过期记录
	var i: int = _tick_time_records.size() - 1
	while i >= 0:
		var record: Dictionary = _tick_time_records[i]
		if record["time_usec"] < max_cutoff:
			_tick_time_records.remove_at(i)
			i -= 1
			continue

		if record["time_usec"] >= avg_cutoff:
			sum_ms += record["elapsed_ms"]
			avg_count += 1

		if record["elapsed_ms"] > max_ms:
			max_ms = record["elapsed_ms"]

		i -= 1

	tick_avg_time_ms = sum_ms / float(avg_count) if avg_count > 0 else 0.0
	tick_max_time_5s_ms = max_ms
