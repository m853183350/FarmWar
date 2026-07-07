## GameRoot — 游戏场景根节点控制器。
##
## 负责游戏启动初始化：
##   - 启动 TickSystem 逻辑时钟（菜单阶段未启动）
##   - 发射 [code]game_state_changed[/code] 信号
##   - 创建 Phase 4 子系统（指令系统、小队管理、小队任务追踪）
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
const COMMAND_SYSTEM_SCRIPT: GDScript = preload("res://scripts/game/command_system.gd")
const SQUAD_MANAGER_SCRIPT: GDScript = preload("res://scripts/game/squad_manager.gd")
const SQUAD_TASK_TRACKER_SCRIPT: GDScript = preload("res://scripts/game/squad_task_tracker.gd")

# ============================================================
# 5. 公开变量
# ============================================================

## 指令系统（Phase 4，_ready 中延迟初始化）。
var command_system: CommandSystem = null

## 小队管理器（Phase 4，_ready 中延迟初始化）。
var squad_manager: SquadManager = null

## 小队任务追踪器（Phase 4，_ready 中延迟初始化）。
var squad_task_tracker: SquadTaskTracker = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 启动逻辑时钟（菜单阶段 auto_start=false，此时显式启动）
	TickSystem.start()

	# 创建 Phase 4 子系统（如果场景中不存在则动态创建）
	_ensure_command_system()

	# 通知各系统游戏开始
	EventBus.game_state_changed.emit(&"playing")

	# 开发调试工具仅在调试版本加载
	if OS.is_debug_build():
		_spawn_debug_tools()

# ============================================================
# 10. 私有方法
# ============================================================

## 确保 Phase 4 子系统节点存在（场景中不存在时动态创建）。
func _ensure_command_system() -> void:
	if not has_node("CommandSystem"):
		var cs: Node = Node.new()
		cs.set_script(COMMAND_SYSTEM_SCRIPT)
		cs.name = "CommandSystem"
		add_child(cs)
		command_system = cs as CommandSystem

	if not has_node("SquadManager"):
		var sm: Node = Node.new()
		sm.set_script(SQUAD_MANAGER_SCRIPT)
		sm.name = "SquadManager"
		add_child(sm)
		squad_manager = sm as SquadManager

	if not has_node("SquadTaskTracker"):
		var st: Node = Node.new()
		st.set_script(SQUAD_TASK_TRACKER_SCRIPT)
		st.name = "SquadTaskTracker"
		add_child(st)
		squad_task_tracker = st as SquadTaskTracker

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
