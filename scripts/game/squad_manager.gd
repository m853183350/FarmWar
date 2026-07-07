## 战术小队管理器 — 维护玩家配置的战术小队列表。
##
## 作为 [GameRoot] 的子节点挂载。提供小队的 CRUD、序列化/反序列化
## （持久化到 JSON），以及两个内置默认小队的管理。
##
## 使用方式：
##   SquadManager.get_squads()          # 获取所有小队（含内置）
##   SquadManager.get_custom_squads()   # 获取玩家自定义小队
##   SquadManager.add_squad(config)     # 添加自定义小队
class_name SquadManager
extends Node

# ============================================================
# 3. 常量
# ============================================================

## 小队配置 JSON 文件路径。
const SQUADS_CONFIG_PATH: String = "res://config/squads/squads.json"

## 内置小队 ID 常量。
const BUILTIN_IDLE_ALL: StringName = &"idle_all"
const BUILTIN_ALL_UNITS: StringName = &"all_units"

# ============================================================
# 5. 公开变量
# ============================================================

## 所有小队列表（含内置小队，按 sort_order 降序排列）。
var squads: Array[SquadConfig] = []

# ============================================================
# 6. 私有变量
# ============================================================

## 是否已初始化（加载完成）。
var _loaded: bool = false

# ============================================================
# 8. 生命周期
# ============================================================

func _ready() -> void:
	_load_squads()

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 获取所有小队（含内置，按 sort_order 降序排列）。
func get_squads() -> Array[SquadConfig]:
	return squads

## 获取玩家自定义小队（不含内置）。
func get_custom_squads() -> Array[SquadConfig]:
	var result: Array[SquadConfig] = []
	for squad: SquadConfig in squads:
		if not squad.is_builtin:
			result.append(squad)
	return result

## 按 ID 查找小队。返回 null 表示未找到。
func get_squad(squad_id: StringName) -> SquadConfig:
	for squad: SquadConfig in squads:
		if squad.squad_id == squad_id:
			return squad
	return null

## 获取小队数量（含内置）。
func get_squad_count() -> int:
	return squads.size()

# ============================================================
# 9. 公开方法 — 编辑
# ============================================================

## 添加一个自定义小队。
## [param squad] 小队配置（应设好 squad_id、display_name、entries）。
func add_squad(squad: SquadConfig) -> void:
	if squad == null:
		return
	if get_squad(squad.squad_id) != null:
		push_warning("SquadManager: 小队 ID '%s' 已存在，跳过" % squad.squad_id)
		return
	squad.is_builtin = false
	squads.append(squad)
	_sort_squads()
	_save_squads()

## 移除指定 ID 的自定义小队（内置小队不可移除）。
func remove_squad(squad_id: StringName) -> bool:
	var squad: SquadConfig = get_squad(squad_id)
	if squad == null:
		return false
	if squad.is_builtin:
		push_warning("SquadManager: 内置小队 '%s' 不可删除" % squad_id)
		return false
	squads.erase(squad)
	_save_squads()
	return true

## 更新指定小队配置。
func update_squad(squad_id: StringName, new_config: SquadConfig) -> bool:
	var idx: int = -1
	for i: int in range(squads.size()):
		if squads[i].squad_id == squad_id:
			idx = i
			break
	if idx < 0:
		return false
	if squads[idx].is_builtin:
		push_warning("SquadManager: 内置小队 '%s' 不可修改" % squad_id)
		return false
	squads[idx] = new_config
	_sort_squads()
	_save_squads()
	return true

# ============================================================
# 10. 私有方法 — 初始化
# ============================================================

## 创建内置默认小队。
func _create_builtin_squads() -> void:
	# "有空的人都过来" — 所有空闲友方单位
	var idle_squad: SquadConfig = SquadConfig.new()
	idle_squad.squad_id = BUILTIN_IDLE_ALL
	idle_squad.display_name = "有空的人都过来"
	idle_squad.sort_order = -1
	idle_squad.is_builtin = true
	squads.append(idle_squad)

	# "全军总攻击" — 所有友方战斗单位
	var all_squad: SquadConfig = SquadConfig.new()
	all_squad.squad_id = BUILTIN_ALL_UNITS
	all_squad.display_name = "全军总攻击"
	all_squad.sort_order = -2
	all_squad.is_builtin = true
	squads.append(all_squad)

## 从 JSON 加载玩家自定义小队。
func _load_squads() -> void:
	if _loaded:
		return
	_loaded = true

	# 先创建内置小队
	_create_builtin_squads()

	# 尝试加载自定义小队
	if not FileAccess.file_exists(SQUADS_CONFIG_PATH):
		return

	var file: FileAccess = FileAccess.open(SQUADS_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return

	var data: Dictionary = JSON.parse_string(file.get_as_text()) as Dictionary
	file.close()
	if data == null:
		return

	var custom_squads_data: Array = data.get("squads", []) as Array
	for squad_data: Dictionary in custom_squads_data:
		var squad: SquadConfig = _dict_to_squad(squad_data)
		if squad != null:
			squads.append(squad)

	_sort_squads()

## 保存自定义小队到 JSON。
func _save_squads() -> void:
	var custom_data: Array[Dictionary] = []
	for squad: SquadConfig in squads:
		if squad.is_builtin:
			continue
		custom_data.append(_squad_to_dict(squad))

	var data: Dictionary = {"squads": custom_data}
	var json_text: String = JSON.stringify(data, "\t")

	var file: FileAccess = FileAccess.open(SQUADS_CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SquadManager: 无法写入小队配置 %s" % SQUADS_CONFIG_PATH)
		return
	file.store_string(json_text)
	file.close()

# ============================================================
# 10. 私有方法 — 序列化
# ============================================================

## 将 SquadConfig 转换为字典。
func _squad_to_dict(squad: SquadConfig) -> Dictionary:
	var entries_data: Array[Dictionary] = []
	for entry: SquadEntry in squad.entries:
		entries_data.append({
			"unit_type": entry.unit_type,
			"count": entry.count,
		})

	return {
		"squad_id": squad.squad_id,
		"display_name": squad.display_name,
		"entries": entries_data,
		"sort_order": squad.sort_order,
	}

## 将字典转换为 SquadConfig。
func _dict_to_squad(data: Dictionary) -> SquadConfig:
	var squad: SquadConfig = SquadConfig.new()
	squad.squad_id = data.get("squad_id", &"") as StringName
	squad.display_name = data.get("display_name", "") as String
	squad.sort_order = data.get("sort_order", 0) as int
	squad.is_builtin = false

	var entries_data: Array = data.get("entries", []) as Array
	for entry_data: Dictionary in entries_data:
		var entry: SquadEntry = SquadEntry.new()
		entry.unit_type = entry_data.get("unit_type", &"") as StringName
		entry.count = entry_data.get("count", 0) as int
		squad.entries.append(entry)

	return squad

## 按 sort_order 降序排列小队。
func _sort_squads() -> void:
	squads.sort_custom(func(a: SquadConfig, b: SquadConfig): return a.sort_order > b.sort_order)
