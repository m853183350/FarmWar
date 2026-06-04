## 地块操作工具 — 全局 Autoload。
##
## 提供地块转化（翻耕、挖掘等）的底层方法，供 UI、AI、脚本等任意系统调用。
## 地块转化映射配置从 [code]config/tile_conversions.json[/code] 加载，
## 新增转化类型只需修改 JSON 配置即可，无需改代码。
##
## 使用方式：
##   [code]TileActions.plow_tiles(tiles)[/code]   — 翻耕（DIRT → FARMLAND）
##   [code]TileActions.dig_tiles(tiles)[/code]    — 挖掘（STONE → DIRT）
##
## 注意：本脚本不直接引用项目自定义 class_name（TileInfo、BaseTile 等），
## 而是通过 preload 的 Script 常量和 duck typing 访问，确保 autoload 编译独立性。
extends Node

# ============================================================
# 3. 常量
# ============================================================

## 地块转化配置文件路径。
const CONFIG_PATH: String = "res://config/tile_conversions.json"

## TileInfo 脚本资源（用于创建实例和访问枚举）。
const TileInfoScript: Script = preload("res://scripts/world/tile_data.gd")

## 作物 ID 到场景路径的映射。
## 新增作物时在此添加条目即可（后续可迁移到 JSON 配置）。
const CROP_SCENES: Dictionary = {
	"wheat_tier1": "res://scenes/crops/wheat_tire_1.tscn",
}

# ============================================================
# 4. @export 变量
# ============================================================

## 是否在转化完成后通过 EventBus 广播事件。
@export var notify_on_action: bool = true

# ============================================================
# 6. 私有变量
# ============================================================

## 缓存的转化配置字典。
## 结构：{ "plow": [{ "source": "...", "target": "..." }, ...], "dig": [...] }
var _config: Dictionary = {}

## 缓存的 world 节点引用（首次访问时查找）。
var _world_cache: Node2D = null

## 配置是否已加载。
var _config_loaded: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_load_config()

# ============================================================
# 9. 公开方法 — 翻耕
# ============================================================

## 将指定网格坐标上的可翻耕地块转化为农田。
##
## 翻耕规则（来自 [code]config/tile_conversions.json[/code] 的 [code]plow[/code] 段）：
##   - 只有 source 场景路径匹配的地块才会被转化
##   - 转化后继承源地块的 fertility 和 moisture
##   - 沙地（sand 变种）已是农田，不会被二次转化
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
## [param world_override] 可选：指定 world 节点（为 null 时自动查找 group "world"）。
##
## 返回实际成功转化的地块数量。找不到 world 或配置缺失时返回 0。
func plow_tiles(tiles: Array, world_override: Node2D = null) -> int:
	var world: Node2D = _resolve_world(world_override)
	if world == null:
		return 0

	var conversions: Array = _get_conversions_for("plow")
	if conversions.is_empty():
		push_warning("TileActions: 没有可用的翻耕转化规则（config 中缺少 plow 段或为空）")
		return 0

	var count: int = 0
	for grid_pos in tiles:
		if not grid_pos is Vector2i:
			continue
		var pos: Vector2i = grid_pos as Vector2i
		if _try_convert_tile(world, pos, conversions):
			count += 1

	if count > 0:
		print("TileActions: 翻耕完成，转化了 %d 个地块" % count)
		if notify_on_action and EventBus:
			EventBus.tile_action_completed.emit("plow", tiles, count)

	return count

# ============================================================
# 9. 公开方法 — 挖掘
# ============================================================

## 将指定网格坐标上的可挖掘地块转化为普通土壤。
##
## 挖掘规则（来自 [code]config/tile_conversions.json[/code] 的 [code]dig[/code] 段）：
##   - 只有 source 场景路径匹配的地块才会被转化
##   - 挖掘产出石材资源（数量由原地块 StoneTile 实例的 get_dig_produce() 决定）
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
## [param world_override] 可选：指定 world 节点（为 null 时自动查找 group "world"）。
##
## 返回实际成功挖掘的地块数量。
func dig_tiles(tiles: Array, world_override: Node2D = null) -> int:
	var world: Node2D = _resolve_world(world_override)
	if world == null:
		return 0

	var conversions: Array = _get_conversions_for("dig")
	if conversions.is_empty():
		push_warning("TileActions: 没有可用的挖掘转化规则（config 中缺少 dig 段或为空）")
		return 0

	var count: int = 0
	var total_produce: int = 0
	for grid_pos in tiles:
		if not grid_pos is Vector2i:
			continue
		var pos: Vector2i = grid_pos as Vector2i
		# 挖掘前先收集产出
		var produce: int = _collect_dig_produce(world, pos)
		total_produce += produce
		if _try_convert_tile(world, pos, conversions):
			count += 1

	if count > 0:
		print("TileActions: 挖掘完成，转化了 %d 个地块，产出石材 %d" % [count, total_produce])
		if notify_on_action and EventBus:
			EventBus.tile_action_completed.emit("dig", tiles, count)

	return count

# ============================================================
# 9. 公开方法 — 种植
# ============================================================

## 在指定网格坐标上种植作物。
##
## 只在满足以下条件的地块上种植：
##   - 地块类型为 FARMLAND
##   - 地块上没有其他作物占用
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
## [param crop_id] 作物标识（如 "wheat_tier1"），必须在 [constant CROP_SCENES] 中注册。
## [param world_override] 可选：指定 world 节点。
##
## 返回实际成功种植的数量。
func plant_crop(tiles: Array, crop_id: String, world_override: Node2D = null) -> int:
	var world: Node2D = _resolve_world(world_override)
	if world == null:
		return 0

	var scene_path: String = CROP_SCENES.get(crop_id, "")
	if scene_path.is_empty():
		push_error("TileActions: 未知的作物 ID '%s'，请在 CROP_SCENES 中注册" % crop_id)
		return 0

	var crop_scene: PackedScene = load(scene_path) as PackedScene
	if crop_scene == null:
		push_error("TileActions: 无法加载作物场景: %s" % scene_path)
		return 0

	var count: int = 0
	for grid_pos in tiles:
		if not grid_pos is Vector2i:
			continue
		var pos: Vector2i = grid_pos as Vector2i
		if _try_plant_crop(world, pos, crop_scene):
			count += 1

	if count > 0:
		print("TileActions: 种植完成，种植了 %d 株 %s" % [count, crop_id])
		if notify_on_action and EventBus:
			EventBus.tile_action_completed.emit("plant", tiles, count)

	return count

# ============================================================
# 10. 私有方法 — 配置加载
# ============================================================

## 加载 JSON 配置文件并缓存到 [member _config]。
## 仅在首次调用时执行实际加载，后续直接使用缓存。
func _load_config() -> void:
	if _config_loaded:
		return

	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("TileActions: 转化配置文件不存在: %s" % CONFIG_PATH)
		_config_loaded = true
		return

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("TileActions: 无法打开转化配置文件: %s" % CONFIG_PATH)
		_config_loaded = true
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("TileActions: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		_config_loaded = true
		return

	var data = json.data
	if data is Dictionary:
		_config = data as Dictionary
	else:
		push_error("TileActions: 配置文件顶层应为 JSON 对象")

	_config_loaded = true

## 获取指定操作类型的所有转化规则。
func _get_conversions_for(action: String) -> Array:
	if not _config_loaded:
		_load_config()
	if _config.has(action):
		var rules = _config[action]
		if rules is Array:
			return rules as Array
	return []

# ============================================================
# 10. 私有方法 — 地块查找与转化
# ============================================================

## 解析世界节点引用。
## 优先使用传入的覆盖节点，其次使用缓存，最后通过 group "world" 查找。
func _resolve_world(world_override: Node2D) -> Node2D:
	if world_override:
		return world_override
	if _world_cache and is_instance_valid(_world_cache):
		return _world_cache
	_world_cache = get_tree().get_first_node_in_group("world") as Node2D
	return _world_cache

## 在 world 中按网格坐标查找已有的地块节点。
## 地块节点命名规则：tile_X_Y（由 [TerrainGenerator] 保证）。
func _find_tile(world: Node2D, grid_pos: Vector2i) -> Node2D:
	var tile_name: String = "tile_%d_%d" % [grid_pos.x, grid_pos.y]
	var tile: Node = world.get_node_or_null(tile_name)
	if tile and tile is Node2D:
		return tile as Node2D
	return null

## 尝试对单个地块执行转化。
## 检查地块的场景路径是否匹配任一转化规则的 [code]source[/code]，
## 匹配则替换为目标场景。返回 [code]true[/code] 表示成功转化。
func _try_convert_tile(world: Node2D, grid_pos: Vector2i, conversions: Array) -> bool:
	var old_tile: Node2D = _find_tile(world, grid_pos)
	if old_tile == null:
		return false

	var source_path: String = old_tile.scene_file_path
	if source_path.is_empty():
		return false

	var target_path: String = ""
	var target_tile_type: int = -1
	for rule in conversions:
		var rule_dict: Dictionary = rule as Dictionary
		if rule_dict.get("source", "") == source_path:
			target_path = rule_dict.get("target", "")
			target_tile_type = rule_dict.get("target_tile_type", -1)
			break

	if target_path.is_empty():
		return false

	_replace_tile(world, old_tile, target_path, grid_pos, target_tile_type)
	return true

## 执行地块节点替换。
##
## 流程：
##   1. 实例化目标场景
##   2. 克隆位置和节点名称
##   3. 继承旧地块的 TileInfo 关键属性（fertility、moisture 等）
##   4. 为目标地块创建并附加新的 TileInfo（类型设为目标类型）
##   5. 替换子节点并释放旧节点
##
## [param target_tile_type] 对应 TileInfo.TileType 枚举值（-1 = 继承旧值）。
func _replace_tile(world: Node2D, old_tile: Node2D, target_scene_path: String, grid_pos: Vector2i, target_tile_type: int = -1) -> void:
	var target_scene: PackedScene = load(target_scene_path) as PackedScene
	if target_scene == null:
		push_error("TileActions: 无法加载目标场景: %s" % target_scene_path)
		return

	var new_tile: Node2D = target_scene.instantiate()
	new_tile.position = old_tile.position
	new_tile.name = old_tile.name

	# 继承旧地块的 TileInfo 数据（使用 duck typing 避免 class_name 依赖）
	var old_data: Resource = null
	if old_tile.has_method("get_tile_data"):
		old_data = old_tile.get_tile_data()
	elif old_tile.has_meta("tile_data"):
		old_data = old_tile.get_meta("tile_data")

	if old_data:
		var new_data: Resource = _create_converted_data(old_data, target_tile_type)
		if new_tile.has_method("set_tile_data"):
			new_tile.set_tile_data(new_data)
		else:
			new_tile.set_meta("tile_data", new_data)

	# 替换节点
	world.remove_child(old_tile)
	old_tile.queue_free()
	world.add_child(new_tile)

## 为转化后的地块创建新的 TileInfo 数据资源。
## 继承源地块的坐标、肥力、湿度；[param target_tile_type] 指定目标地块大类。
func _create_converted_data(old_data: Resource, target_tile_type: int) -> Resource:
	var new_data: Resource = TileInfoScript.new()
	new_data.grid_position = old_data.grid_position
	# 使用目标类型（由 JSON 配置的 target_tile_type 指定）
	if target_tile_type >= 0:
		new_data.tile_type = target_tile_type
	else:
		new_data.tile_type = old_data.tile_type
	# 继承耕地相关属性
	new_data.fertility = old_data.fertility
	new_data.moisture = old_data.moisture
	# apply_defaults() 会根据 tile_type + variant 设置通行/建造等默认值
	new_data.apply_defaults()
	# 恢复继承值（apply_defaults 可能将 fertility/moisture 覆盖为目标类型的默认值）
	new_data.fertility = old_data.fertility
	new_data.moisture = old_data.moisture
	return new_data

# ============================================================
# 10. 私有方法 — 种植辅助
# ============================================================

## 尝试在单个地块上种植作物。
## 检查地块是否为 FARMLAND 且无作物占用，通过则实例化作物场景并调用 [method Crop.plant]。
func _try_plant_crop(world: Node2D, grid_pos: Vector2i, crop_scene: PackedScene) -> bool:
	var tile: Node2D = _find_tile(world, grid_pos)
	if tile == null:
		return false

	# 检查地块是否为农田
	var tile_data = null
	if tile.has_method("get_tile_data"):
		tile_data = tile.get_tile_data()
	elif tile.has_meta("tile_data"):
		tile_data = tile.get_meta("tile_data")

	if tile_data == null:
		return false

	# TileType.FARMLAND = 3
	if tile_data.tile_type != 3:
		return false

	# 检查是否已有作物占用
	if tile.has_method("has_occupant_of_type"):
		if tile.has_occupant_of_type("Crop"):
			return false

	# 实例化作物
	var crop: Node2D = crop_scene.instantiate()
	crop.name = "crop_%d_%d" % [grid_pos.x, grid_pos.y]

	# 先添加到 world 再调用 plant（plant 需要访问 tile）
	world.add_child(crop)

	# 调用作物的 plant 方法
	if crop.has_method("plant"):
		crop.plant(tile)

	return true

# ============================================================
# 10. 私有方法 — 挖掘产出
# ============================================================

## 在挖掘前从原石质地块收集石材产出。
## 通过 duck typing 调用 get_dig_produce()，非石质地块返回 0。
func _collect_dig_produce(world: Node2D, grid_pos: Vector2i) -> int:
	var tile: Node2D = _find_tile(world, grid_pos)
	if tile == null:
		return 0
	if tile.has_method("get_dig_produce"):
		return tile.get_dig_produce()
	return 0
