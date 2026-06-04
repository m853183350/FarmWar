## Tick 计数器标签。
##
## 挂载在 [Label] 节点上，监听 [method TickSystem.tick_elapsed] 信号，
## 每次 tick 时计数 +1 并更新显示文本。
## 在 [method _exit_tree] 时自动断开信号连接。
class_name TickCounterLabel extends Label

# ============================================================
# 6. 私有变量
# ============================================================

var _count: int = 0

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	text = "0"
	if TickSystem.tick_elapsed.is_connected(_on_tick):
		return
	TickSystem.tick_elapsed.connect(_on_tick)

func _exit_tree() -> void:
	if TickSystem.tick_elapsed.is_connected(_on_tick):
		TickSystem.tick_elapsed.disconnect(_on_tick)

# ============================================================
# 10. 私有方法
# ============================================================

func _on_tick(_delta: float) -> void:
	_count += 1
	text = str(_count)
