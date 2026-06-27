## GameRoot — 游戏场景根节点控制器。
##
## 负责游戏启动初始化：
##   - 启动 TickSystem 逻辑时钟（菜单阶段未启动）
##   - 发射 [code]game_state_changed[/code] 信号
##   - 在调试版本中加载开发调试工具
##
## 挂载在 [code]scenes/game/game.tscn[/code] 的根 [Node2D] 上。
class_name GameRoot extends Node2D

# ============================================================
# 1. 信号 — 无
# ============================================================

# ============================================================
# 3. 常量
# ============================================================

const DEBUGGER_SCRIPT: GDScript = preload("res://scripts/utils/debugger.gd")

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 启动逻辑时钟（菜单阶段 auto_start=false，此时显式启动）
	TickSystem.start()

	# 通知各系统游戏开始
	EventBus.game_state_changed.emit(&"playing")

	# 开发调试工具仅在调试版本加载
	if OS.is_debug_build():
		_spawn_debug_tools()

# ============================================================
# 10. 私有方法
# ============================================================

## 在调试版本中加载开发工具节点。
##
## 创建 [Debugger] 实例并添加到场景树，替代原 [code]main.tscn[/code] 中
## 无条件加载的"调试工具"节点。
func _spawn_debug_tools() -> void:
	var debugger: Node = DEBUGGER_SCRIPT.new()
	debugger.name = "Debugger"
	debugger.set(&"ModeSelector", $HUD/ModeSelector)
	debugger.set(&"player", $Player)
	add_child(debugger)
