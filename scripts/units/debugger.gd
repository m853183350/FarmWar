extends Node

var Taskdata = preload("res://scripts/units/task_data.gd")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	UnitManager.spawn_worker(Vector2i(5, 3))
	# TaskData.create("pole")
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	DebugOverlay.set_entry("tick", TickSystem.get_tick_count())
	pass

func _print_loop():
	print("每秒print一次")
	await get_tree().create_timer(1.0)
	_print_loop()
