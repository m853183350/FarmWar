## Tick 系统，管理游戏逻辑时钟。
## 与画面渲染分离，以固定间隔发出 [signal tick_elapsed] 信号。
## 各游戏系统监听该信号执行逻辑更新，确保帧率无关的行为一致。
##
## 通过 Autoload 全局访问：[code]TickSystem[/code]
extends Node

# ============================================================
# 1. 信号
# ============================================================

## 每次 tick 触发时发出，传递本次 tick 的实际间隔时间（秒）。
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

# ============================================================
# 4. @export 变量
# ============================================================

## 启动时是否自动开始 tick。
@export var auto_start: bool = true

# ============================================================
# 5. 公开变量
# ============================================================

## 当前 tick 间隔（秒），可在运行时修改。
var tick_interval: float = DEFAULT_TICK_INTERVAL

# ============================================================
# 6. 私有变量
# ============================================================

var _timer: Timer = null
var _is_paused: bool = false
var _tick_count: int = 0

# ============================================================
# 7. @onready 变量
# ============================================================

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = tick_interval
	_timer.autostart = false
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

	if auto_start:
		start()

# ============================================================
# 9. 公开方法
# ============================================================

## 启动 tick 循环。
func start() -> void:
	if _timer.is_stopped():
		_timer.start()

## 停止 tick 循环。
func stop() -> void:
	_timer.stop()

## 暂停 tick（计时器继续运行但信号不触发）。
func pause() -> void:
	_is_paused = true

## 恢复 tick。
func resume() -> void:
	_is_paused = false

## 修改 tick 间隔并立即生效。
func set_tick_interval(interval: float) -> void:
	tick_interval = clampf(interval, MIN_TICK_INTERVAL, MAX_TICK_INTERVAL)
	_timer.wait_time = tick_interval
	# 如果正在运行，重启计时器以应用新间隔
	if not _timer.is_stopped():
		_timer.start()

## 获取当前 tick 序号（从启动开始计数）。
func get_tick_count() -> int:
	return _tick_count

## 获取暂停状态。
func is_paused() -> bool:
	return _is_paused

# ============================================================
# 10. 私有方法
# ============================================================

func _on_timer_timeout() -> void:
	if _is_paused:
		return
	_tick_count += 1
	tick_elapsed.emit(tick_interval)
