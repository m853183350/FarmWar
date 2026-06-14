extends Node

var Taskdata = preload("res://scripts/units/task_data.gd")
@export var ModeSelector: Node

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	UnitManager.spawn_worker(Vector2i(5, 3))
	UnitManager.spawn_worker(Vector2i(5, 4))
	UnitManager.spawn_worker(Vector2i(5, 5))
	# TaskData.create("pole")
	# 启动时加本科选项
	ModeSelector.add_mode_for_family("Poaceae")
	EventBus.mode_changed.connect(_show_mode_change)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	DebugOverlay.set_entry("tick", TickSystem.get_tick_count())
	DebugOverlay.set_entry("tick_ms", "%.2f" % TickSystem.tick_computation_time_ms)
	DebugOverlay.set_entry("tick_avg_1s", "%.2f" % TickSystem.tick_avg_time_ms)
	DebugOverlay.set_entry("tick_max_5s", "%.2f" % TickSystem.tick_max_time_5s_ms)

func _print_loop():
	print("每秒print一次")
	await get_tree().create_timer(1.0)
	_print_loop()

func _show_mode_change(name: StringName):
	DebugOverlay.set_entry("当前模式：", name)
	return
