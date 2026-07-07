## 自动选兵工具 — 纯静态工具类。
##
## 从 [UnitManager] 已注册的战斗单位中按条件自动选取最合适的单位。
## 用于 [CommandSystem] 发出指令时，自动选择距离最近、符合条件的空闲单位。
##
## 使用方式：
##   var units: Array = UnitSelection.select_for_squad(squad_config, position)
##   var units: Array = UnitSelection.select_units(position, 5, &"swordsman", 0)
class_name UnitSelection
extends RefCounted

# ============================================================
# 9. 公开方法 — 静态选择
# ============================================================

## 按战术小队配置选取单位。
##
## 遍历小队的每个 [SquadEntry]，从 [UnitManager] 中按 unit_type + count 选取
## 最近的空闲单位。内置默认小队有特殊逻辑：
##   - "idle_all": 选取所有空闲友方战斗单位
##   - "all_units": 选取所有友方战斗单位（无视状态）
##
## [param squad_config] 小队配置（SquadConfig Resource）。
## [param from_position] 从哪个位置计算距离（世界坐标）。
## [param faction] 阵营过滤（默认 0 = 友方）。
## [return] 选中的单位数组。
static func select_for_squad(squad_config: Resource, from_position: Vector2, faction: int = 0) -> Array:
	if squad_config == null:
		return []

	var selected: Array = []
	var used_ids: Array[StringName] = []

	var is_builtin: bool = squad_config.get("is_builtin") as bool if squad_config.get("is_builtin") != null else false
	var squad_id: StringName = squad_config.get("squad_id") as StringName if squad_config.get("squad_id") != null else &""

	# 内置小队特殊处理
	if is_builtin:
		match squad_id:
			&"idle_all":
				return select_units(from_position, -1, &"", faction, true, true)
			&"all_units":
				return select_units(from_position, -1, &"", faction, false, false)

	# 普通小队：按 entries 逐一选取
	var entries: Array = squad_config.get("entries") as Array if squad_config.get("entries") != null else []
	if entries.is_empty():
		return []

	for entry: Resource in entries:
		var unit_type: StringName = entry.get("unit_type") as StringName if entry.get("unit_type") != null else &""
		var count: int = entry.get("count") as int if entry.get("count") != null else 0
		if count <= 0:
			continue

		var of_type: Array = _get_combat_units_by_type(from_position, unit_type, faction, true, true, used_ids)
		var taken: int = mini(count, of_type.size())
		for i: int in range(taken):
			var unit = of_type[i]
			selected.append(unit)
			used_ids.append(unit.unit_id)

	return selected

## 通用选兵方法：按条件选取 N 个最近的单位。
##
## [param from_position] 从哪个位置计算距离（世界坐标）。
## [param count] 选取数量（-1 = 不限，选取所有符合条件者）。
## [param unit_type_filter] 单位类型过滤（"" = 不限）。
## [param faction] 阵营过滤。
## [param only_idle] 是否只选空闲单位（state == IDLE）。
## [param exclude_tasked] 是否排除已有任务的单位（current_task != null）。
## [param exclude_ids] 已排除的 unit_id 列表（避免重复选取）。
## [return] 按距离排序的单位数组（最近的在前）。
static func select_units(
	from_position: Vector2,
	count: int = -1,
	unit_type_filter: StringName = &"",
	faction: int = 0,
	only_idle: bool = true,
	exclude_tasked: bool = true,
	exclude_ids: Array[StringName] = []
) -> Array:
	var candidates: Array = []

	for unit in UnitManager.get_combat_units(faction):
		if exclude_ids.has(unit.unit_id):
			continue
		if unit_type_filter != &"" and unit.unit_type != unit_type_filter:
			continue
		if only_idle and not unit.is_idle():
			continue
		if exclude_tasked and unit.current_task != null:
			continue
		candidates.append(unit)

	# 按距离排序（最近优先）
	candidates.sort_custom(func(a, b):
		return a.grid_position.distance_squared_to(from_position) < \
		       b.grid_position.distance_squared_to(from_position)
	)

	# 截取指定数量
	if count > 0 and candidates.size() > count:
		candidates.resize(count)

	return candidates

# ============================================================
# 10. 私有方法 — 静态辅助
# ============================================================

## 获取指定类型的战斗单位列表（按距离排序，排除已选 ID）。
static func _get_combat_units_by_type(
	from_position: Vector2,
	unit_type: StringName,
	faction: int,
	only_idle: bool,
	exclude_tasked: bool,
	exclude_ids: Array[StringName]
) -> Array:
	var candidates: Array = []

	for unit in UnitManager.get_combat_units(faction):
		if exclude_ids.has(unit.unit_id):
			continue
		if unit.unit_type != unit_type:
			continue
		if only_idle and not unit.is_idle():
			continue
		if exclude_tasked and unit.current_task != null:
			continue
		candidates.append(unit)

	candidates.sort_custom(func(a, b):
		return a.grid_position.distance_squared_to(from_position) < \
		       b.grid_position.distance_squared_to(from_position)
	)

	return candidates
