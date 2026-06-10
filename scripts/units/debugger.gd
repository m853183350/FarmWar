extends Node

var Taskdata = preload("res://scripts/units/task_data.gd")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	UnitManager.spawn_worker(Vector2i(5, 3))
	UnitManager.spawn_worker(Vector2i(5, 4))
	UnitManager.spawn_worker(Vector2i(5, 5))
	UnitManager.spawn_worker(Vector2i(5, 6))
	UnitManager.spawn_worker(Vector2i(5, 9))
	UnitManager.spawn_worker(Vector2i(5, 11))
	# TaskData.create("pole")
	


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
