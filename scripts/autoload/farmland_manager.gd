## 农田管理器 — 全局 Autoload。
##
## 管理地块→作物分配关系，驱动工人的自动耕作循环（翻耕→种植→等待成熟→收获→重新种植）。
## 通过事件驱动状态机推进，不依赖 tick 轮询。
##
## 核心流程：
##   1. [method assign_tiles] 接收地块和作物 ID，初始分配
##   2. 监听 [signal EventBus.worker_task_completed] 推进任务链
##   3. 监听 [signal EventBus.crop_matured] 在作物成熟时创建 HARVEST 任务
##   4. 监听 [signal EventBus.crop_harvested] 兜底：手动收获后自动补种
##
## 通过 Autoload 全局访问：[code]FarmlandManager[/code]
extends Node

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

# ============================================================
# 2. 枚举
# ============================================================

## 地块分配状态。
enum AssignState {
	NEEDS_PLOW,    ## 需要先翻耕（地块是 DIRT）
	NEEDS_PLANT,   ## 可以种植（地块已是 FARMLAND 且无作物）
	GROWING,       ## 作物生长中
	NEEDS_HARVEST, ## 作物已成熟，等待收获
}

# ============================================================
# 6. 私有变量
# ============================================================

## 地块分配表：{ Vector2i: {"crop_id": String, "state": AssignState} }
var _assignments: Dictionary = {}

## 缓存的 world 节点引用。
var _world_cache: Node2D = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	if EventBus:
		EventBus.worker_task_completed.connect(_on_worker_task_completed)
		EventBus.crop_matured.connect(_on_crop_matured)
		# crop_harvested 作为兜底：当手动即时操作收获已分配地块后自动补种
		EventBus.crop_harvested.connect(_on_crop_harvested)

# ============================================================
# 9. 公开方法
# ============================================================

## 将一批地块分配给指定作物，启动自动耕作循环。
##
## 遍历每个地块，根据当前状态（DIRT / FARMLAND 空 / FARMLAND 已有作物）
## 创建对应的初始任务（PLOW / PLANT / HARVEST）。
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
## [param crop_id] 作物标识（如 "wheat_tier1"）。
func assign_tiles(tiles: Array[Vector2i], crop_id: String) -> void:
	var valid_count: int = 0
	var world: Node2D = _resolve_world()
	if world == null:
		push_error("FarmlandManager: 无法获取 world 节点")
		return

	for grid_pos: Vector2i in tiles:
		var tile: Node2D = WorldUtils.find_tile(world, grid_pos)
		if tile == null:
			continue

		var tile_type: int = _get_tile_type(tile)

		match tile_type:
			0:  # DIRT → 先翻耕再种植
				_assignments[grid_pos] = {"crop_id": crop_id, "state": AssignState.NEEDS_PLOW}
				_create_plow_task(grid_pos, crop_id)
				valid_count += 1

			3:  # FARMLAND
				if _has_crop(tile):
					# 已有作物：成熟则收获，未成熟则不操作（保留现有作物）
					if _is_crop_mature(tile):
						_assignments[grid_pos] = {"crop_id": crop_id, "state": AssignState.NEEDS_HARVEST}
						_create_harvest_task(grid_pos, crop_id)
						valid_count += 1
					# 未成熟则不操作
				else:
					# 空农田 → 直接种植
					_assignments[grid_pos] = {"crop_id": crop_id, "state": AssignState.NEEDS_PLANT}
					_create_plant_task(grid_pos, crop_id)
					valid_count += 1

			_:  # 其他类型（STONE、OCEAN 等）→ 跳过
				pass

	print("FarmlandManager: %d/%d 个地块已分配给 %s" % [valid_count, tiles.size(), crop_id])
	if valid_count > 0 and EventBus:
		EventBus.farmland_assigned.emit(tiles, crop_id)

## 取消指定地块的自动耕作分配。
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
func unassign_tiles(tiles: Array[Vector2i]) -> void:
	for grid_pos: Vector2i in tiles:
		_assignments.erase(grid_pos)
	if EventBus:
		EventBus.farmland_unassigned.emit(tiles)

## 检查地块是否已分配给自动循环。
func is_assigned(grid_pos: Vector2i) -> bool:
	return _assignments.has(grid_pos)

## 获取地块的分配信息。
## 返回 [Dictionary]：{"crop_id": String, "state": AssignState}。未分配返回空字典。
func get_assignment(grid_pos: Vector2i) -> Dictionary:
	var result: Variant = _assignments.get(grid_pos, {})
	if result is Dictionary:
		return result as Dictionary
	return {}

## 获取所有分配了指定作物的地块坐标。
func get_tiles_for_crop(crop_id: String) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for grid_pos: Vector2i in _assignments:
		var info: Dictionary = _assignments[grid_pos] as Dictionary
		if info.get("crop_id", "") == crop_id:
			tiles.append(grid_pos)
	return tiles

## 获取所有已分配的地块坐标。
func get_all_assigned_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for grid_pos: Vector2i in _assignments:
		tiles.append(grid_pos)
	return tiles

## 获取已分配地块总数。
func get_assignment_count() -> int:
	return _assignments.size()

# ============================================================
# 10. 私有方法 — 事件驱动的循环推进
# ============================================================

## 工人完成任务后推进状态。
func _on_worker_task_completed(worker_id: StringName, task: TaskData) -> void:
	var grid_pos: Vector2i = task.target_tile
	if not _assignments.has(grid_pos):
		return

	var info: Dictionary = _assignments[grid_pos] as Dictionary
	var crop_id: String = info.get("crop_id", "")
	var state: int = info.get("state", -1)

	match task.task_type:
		TaskData.TaskType.PLOW:
			if state == AssignState.NEEDS_PLOW:
				info["state"] = AssignState.NEEDS_PLANT
				_assignments[grid_pos] = info
				_create_plant_task(grid_pos, crop_id)

		TaskData.TaskType.PLANT:
			if state == AssignState.NEEDS_PLANT:
				info["state"] = AssignState.GROWING
				_assignments[grid_pos] = info
				# 不再在此处创建 HARVEST 任务 — 由 crop_matured 信号驱动

		TaskData.TaskType.HARVEST:
			if state == AssignState.NEEDS_HARVEST:
				info["state"] = AssignState.NEEDS_PLANT
				_assignments[grid_pos] = info
				_create_plant_task(grid_pos, crop_id)

## 作物成熟时自动创建 HARVEST 任务（核心循环推进点）。
##
## 作物在 [method Crop._advance_stage] 进入最终阶段时通过 EventBus 发出。
## 这消除了轮询/延迟推断/任务反复失败等 hack，实现精准的"成熟即收获"。
func _on_crop_matured(crop_node: Node2D, grid_pos: Vector2i, crop_id: String) -> void:
	if not _assignments.has(grid_pos):
		return
	var info: Dictionary = _assignments[grid_pos] as Dictionary
	if info.get("state", -1) == AssignState.GROWING:
		info["state"] = AssignState.NEEDS_HARVEST
		_assignments[grid_pos] = info
		_create_harvest_task(grid_pos, crop_id)

## 兜底：当通过手动即时操作收获已分配地块时，自动补种。
##
## 用于处理光标模式下手动收获已分配地块的情况，确保自动循环不中断。
func _on_crop_harvested(yields: Array, crop_id: String) -> void:
	for grid_pos: Vector2i in _assignments:
		var info: Dictionary = _assignments[grid_pos] as Dictionary
		if info.get("state", -1) == AssignState.GROWING and info.get("crop_id", "") == crop_id:
			var world: Node2D = _resolve_world()
			var tile: Node2D = WorldUtils.find_tile(world, grid_pos)
			if tile == null or not _has_crop(tile):
				info["state"] = AssignState.NEEDS_PLANT
				_assignments[grid_pos] = info
				_create_plant_task(grid_pos, crop_id)

# ============================================================
# 10. 私有方法 — 任务创建
# ============================================================

## 创建翻耕任务并分配给工人。
func _create_plow_task(grid_pos: Vector2i, crop_id: String) -> void:
	var task: TaskData = TaskData.create(TaskData.TaskType.PLOW, grid_pos, {"crop_id": crop_id})
	var tasks: Array[TaskData] = [task]
	UnitManager.distribute_tasks(tasks)

## 创建种植任务并分配给工人。
func _create_plant_task(grid_pos: Vector2i, crop_id: String) -> void:
	var task: TaskData = TaskData.create(TaskData.TaskType.PLANT, grid_pos, {"crop_id": crop_id})
	var tasks: Array[TaskData] = [task]
	UnitManager.distribute_tasks(tasks)

## 创建收获任务并分配给工人。
func _create_harvest_task(grid_pos: Vector2i, crop_id: String) -> void:
	var task: TaskData = TaskData.create(TaskData.TaskType.HARVEST, grid_pos, {"crop_id": crop_id})
	var tasks: Array[TaskData] = [task]
	UnitManager.distribute_tasks(tasks)

# ============================================================
# 10. 私有方法 — 世界与地块
# ============================================================

## 解析世界节点引用（带缓存）。
func _resolve_world() -> Node2D:
	if _world_cache and is_instance_valid(_world_cache):
		return _world_cache
	_world_cache = WorldUtils.get_world()
	return _world_cache

## 获取地块的 TileType 枚举值。
## DIRT=0, STONE=1, OCEAN=2, FARMLAND=3
func _get_tile_type(tile: Node2D) -> int:
	var data: Resource = WorldUtils.get_tile_data(tile)
	if data != null:
		return data.tile_type
	return -1

## 检查地块上是否有作物。
func _has_crop(tile: Node2D) -> bool:
	if tile.has_method("has_occupant_of_type"):
		return tile.has_occupant_of_type("Crop")
	return false

## 检查地块上的作物是否已成熟。
func _is_crop_mature(tile: Node2D) -> bool:
	if not tile.has_method("get_all_occupants"):
		return false
	var occupants: Array = tile.get_all_occupants()
	for occ: Node in occupants:
		if is_instance_valid(occ) and occ.has_method("is_mature") and occ.has_method("harvest"):
			return occ.is_mature()
	return false
