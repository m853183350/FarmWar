## 地块操作工具 — 全局 Autoload。
##
## 提供地块转化（翻耕、挖掘等）的底层方法，供 UI、AI、脚本等任意系统调用。
## 地块转化映射配置从 [code]config/tile_conversions.json[/code] 加载，
## 新增转化类型只需修改 JSON 配置即可，无需改代码。
##
## 转化匹配不再依赖 [member Node.scene_file_path]，改为按 [enum TileInfo.TileType] 匹配，
## 因此同时适用于 TSCN 实例化和程序化创建的地块。
##
## 使用方式：
##   [code]TileActions.plow_tiles(tiles)[/code]   — 翻耕（DIRT → FARMLAND）
##   [code]TileActions.dig_tiles(tiles)[/code]    — 挖掘（STONE → DIRT）
extends Node

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

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
## 结构：{ "plow": [{ "source_tile_type": 0, "target_type_key": "...", "target_variant": "..." }], ... }
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
##   - 只有 tile_type 匹配 [code]source_tile_type[/code] 的地块才会被转化
##   - 转化后继承源地块的 fertility 和 moisture
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
##   - 只有 tile_type 匹配 [code]source_tile_type[/code] 的地块才会被转化
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
		# print("TileActions: 种植完成，种植了 %d 株 %s" % [count, crop_id])
		if notify_on_action and EventBus:
			EventBus.tile_action_completed.emit("plant", tiles, count)

	return count

# ============================================================
# 9. 公开方法 — 收获
# ============================================================

## 收获指定网格坐标上已成熟的作物。
##
## 只在满足以下条件的地块上收获：
##   - 地块类型为 FARMLAND
##   - 地块上有 Crop 类型的作物占用
##   - 作物已成熟（[method Crop.is_mature] 返回 true）
##
## [param tiles] 网格坐标数组（[Array] of [Vector2i]）。
## [param world_override] 可选：指定 world 节点（为 null 时自动查找 group "world"）。
##
## 返回实际成功收获的作物数量。
func harvest_crop(tiles: Array, world_override: Node2D = null) -> int:
	var world: Node2D = _resolve_world(world_override)
	if world == null:
		return 0

	var count: int = 0
	var total_yields: Dictionary = {}

	for grid_pos in tiles:
		if not grid_pos is Vector2i:
			continue
		var pos: Vector2i = grid_pos as Vector2i
		var yields: Array = _try_harvest_crop(world, pos)
		if yields.size() > 0:
			count += 1
			for y in yields:
				var y_dict: Dictionary = y as Dictionary
				var item_id: String = y_dict.get("item_id", "")
				var amount: float = y_dict.get("amount", 0.0)
				if total_yields.has(item_id):
					total_yields[item_id] = total_yields[item_id] + amount
				else:
					total_yields[item_id] = amount

	if count > 0:
		print("TileActions: 收获完成，收获了 %d 株作物，产物: %s" % [count, total_yields])
		if notify_on_action and EventBus:
			EventBus.tile_action_completed.emit("harvest", tiles, count)

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
## 优先使用传入的覆盖节点，其次使用缓存，最后通过 WorldUtils 查找。
func _resolve_world(world_override: Node2D) -> Node2D:
	if world_override:
		return world_override
	if _world_cache and is_instance_valid(_world_cache):
		return _world_cache
	_world_cache = WorldUtils.get_world()
	return _world_cache

## 尝试对单个地块执行转化。
## 检查地块的 tile_type 是否匹配任一转化规则的 [code]source_tile_type[/code]，
## 匹配则替换为目标地块。返回 [code]true[/code] 表示成功转化。
## 支持 TSCN 实例化和程序化创建的地块（不再依赖 scene_file_path）。
func _try_convert_tile(world: Node2D, grid_pos: Vector2i, conversions: Array) -> bool:
	var old_tile: Node2D = WorldUtils.find_tile(world, grid_pos)
	if old_tile == null:
		return false

	# 获取源地块的 tile_type
	var old_data: Resource = null
	if old_tile.has_method("get_tile_data"):
		old_data = old_tile.get_tile_data()
	elif old_tile.has_meta("tile_data"):
		old_data = old_tile.get_meta("tile_data")

	if old_data == null:
		return false

	var source_type: int = old_data.tile_type

	# 查找匹配的转化规则
	var target_type_key: String = ""
	var target_variant: String = ""
	for rule in conversions:
		var rule_dict: Dictionary = rule as Dictionary
		if rule_dict.get("source_tile_type", -1) == source_type:
			target_type_key = rule_dict.get("target_type_key", "")
			target_variant = rule_dict.get("target_variant", "")
			break

	if target_type_key.is_empty():
		return false

	_replace_tile(world, old_tile, target_type_key, target_variant, grid_pos)
	return true

## 执行地块节点替换。
##
## 通过 [TerrainGenerator] 创建目标地块（自动选择 TSCN 或程序化模式），
## 继承旧地块的 TileInfo 关键属性（fertility、moisture 等）。
func _replace_tile(world: Node2D, old_tile: Node2D, target_type_key: String, target_variant: String, grid_pos: Vector2i) -> void:
	# 通过 TerrainGenerator 创建目标地块实例
	var new_tile: Node2D = null
	if world.has_method("create_tile_instance"):
		new_tile = world.create_tile_instance(target_type_key, target_variant)
	else:
		push_error("TileActions: world 节点没有 create_tile_instance 方法")
		return

	if new_tile == null:
		push_error("TileActions: 无法创建目标地块 '%s.%s'" % [target_type_key, target_variant])
		return

	new_tile.position = old_tile.position
	new_tile.name = old_tile.name

	# 继承旧地块的 TileInfo 数据
	var old_data: Resource = null
	if old_tile.has_method("get_tile_data"):
		old_data = old_tile.get_tile_data()
	elif old_tile.has_meta("tile_data"):
		old_data = old_tile.get_meta("tile_data")

	if old_data and world.has_method("get_tile_config_for_type") and world.has_method("merge_tile_config"):
		var type_cfg: Dictionary = world.get_tile_config_for_type(target_type_key)
		var variants: Dictionary = type_cfg.get("variants", {})
		var variant_cfg: Dictionary = variants.get(target_variant, {})
		var merged_config: Dictionary = world.merge_tile_config(type_cfg, variant_cfg)

		var new_data: Resource = _create_converted_data(old_data, type_cfg.get("tile_type", 0), target_variant, merged_config)
		if new_tile.has_method("set_tile_data"):
			new_tile.set_tile_data(new_data)
		else:
			new_tile.set_meta("tile_data", new_data)

	# 替换节点
	world.remove_child(old_tile)
	old_tile.queue_free()
	world.add_child(new_tile)
	new_tile.update_properties()  # 更新新地块的计算属性（fertility、moisture 等）

## 为转化后的地块创建新的 TileInfo 数据资源。
## 继承源地块的坐标、肥力、湿度；通过 config 设置目标类型的默认属性。
func _create_converted_data(old_data: Resource, target_tile_type: int, target_variant: String, merged_config: Dictionary) -> Resource:
	var new_data: Resource = TileInfoScript.new()
	new_data.grid_position = old_data.grid_position
	new_data.tile_type = target_tile_type
	new_data.variant = target_variant

	# 使用合并后的配置设置默认属性
	if not merged_config.is_empty():
		new_data.apply_defaults(merged_config)

	# 继承耕地相关属性（覆盖 apply_defaults 可能重置的值）
	new_data.fertility = old_data.fertility
	new_data.moisture = old_data.moisture
	return new_data

# ============================================================
# 10. 私有方法 — 种植辅助
# ============================================================

## 尝试在单个地块上种植作物。
## 检查地块是否为 FARMLAND 且无作物占用，通过则实例化作物场景并调用 [method Crop.plant]。
func _try_plant_crop(world: Node2D, grid_pos: Vector2i, crop_scene: PackedScene) -> bool:
	var tile: Node2D = WorldUtils.find_tile(world, grid_pos)
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
# 10. 私有方法 — 收获辅助
# ============================================================

## 尝试在单个地块上收获作物。
##
## 验证通过后通过 [signal EventBus.crop_harvest_requested] 事件通知作物自行收获，
## 而非直接调用 [method Crop.harvest]。作物在 [method Crop._on_harvest_requested] 中
## 检查目标地块是否匹配并执行收获。
##
## 返回产物数组（[Array] of [Dictionary]），无作物或未成熟时返回空数组。
func _try_harvest_crop(world: Node2D, grid_pos: Vector2i) -> Array:
	var tile: Node2D = WorldUtils.find_tile(world, grid_pos)
	if tile == null:
		return []

	# 检查地块是否为农田（TileType.FARMLAND = 3）
	var tile_data = null
	if tile.has_method("get_tile_data"):
		tile_data = tile.get_tile_data()
	elif tile.has_meta("tile_data"):
		tile_data = tile.get_meta("tile_data")

	if tile_data == null:
		return []
	if tile_data.tile_type != 3:
		return []

	# 检查是否有作物占用
	if not tile.has_method("has_occupant_of_type"):
		return []
	if not tile.has_occupant_of_type("Crop"):
		return []

	# 获取作物 occupant（用于成熟度检查和读取产物）
	var crop_node: Node = null
	if tile.has_method("get_all_occupants"):
		var all_occupants: Array = tile.get_all_occupants()
		for occ: Node in all_occupants:
			if is_instance_valid(occ) and occ.has_method("harvest"):
				crop_node = occ
				break

	if crop_node == null:
		return []

	# 检查作物是否成熟
	if crop_node.has_method("is_mature"):
		if not crop_node.is_mature():
			return []

	# 通过事件驱动收获 — 作物自行响应并收获
	if EventBus:
		EventBus.crop_harvest_requested.emit(tile)
	else:
		if crop_node.has_method("harvest"):
			crop_node.harvest()
		return []

	# 从作物节点读取产物（queue_free 延迟释放，节点仍可访问）
	if is_instance_valid(crop_node):
		var yields = crop_node.get("last_harvest_yields")
		if yields is Array:
			return yields as Array

	return []

# ============================================================
# 10. 私有方法 — 挖掘产出
# ============================================================

## 在挖掘前从原石质地块收集石材产出。
## 通过 duck typing 调用 get_dig_produce()，非石质地块返回 0。
func _collect_dig_produce(world: Node2D, grid_pos: Vector2i) -> int:
	var tile: Node2D = WorldUtils.find_tile(world, grid_pos)
	if tile == null:
		return 0
	if tile.has_method("get_dig_produce"):
		return tile.get_dig_produce()
	return 0
