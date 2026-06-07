## 随机地形生成器。
##
## 挂载在 [code]world[/code] 节点上，在 [method _ready] 时自动生成地图网格。
## 支持多种生成模式，地形配置从外部 JSON 文件加载。
##
## 使用方式：
##   1. 将本脚本挂载到 world 场景的根节点
##   2. 在编辑器中调整 map_width / map_height / seed / generation_mode 等参数
##   3. 编辑 [code]resources/world/terrain_config.json[/code] 配置地块类型与权重
##   4. 运行游戏即可看到生成的地形
class_name TerrainGenerator extends Node2D

# ============================================================
# 1. 信号
# ============================================================

# ============================================================
# 2. 枚举
# ============================================================

## 地形生成模式。
enum GenerationMode {
	ALL_RANDOM,  ## 全随机 — 按权重随机生成所有地块
	ISLAND,      ## 岛屿 — 中心陆地 + 周围水域（待实现）
}

# ============================================================
# 3. 常量
# ============================================================

## 预加载 TileInfo 脚本，用于访问其枚举和创建实例。
const TileInfoRef: Script = preload("res://scripts/world/tile_data.gd")

## 默认地形配置文件路径。
const DEFAULT_CONFIG_PATH: String = "res://config/terrain_config.json"

## 降级占位场景 — 配置缺失或资源加载失败时使用。
const FALLBACK_SCENE_PATH: String = "res://scenes/debug/null_img.tscn"

# ============================================================
# 4. @export 变量
# ============================================================

## 地形生成模式。
@export var generation_mode: GenerationMode = GenerationMode.ALL_RANDOM

## 地图宽度（地块列数）。
@export var map_width: int = 32

## 地图高度（地块行数）。
@export var map_height: int = 32

## 单个地块的像素大小（应与 tile 场景的视觉尺寸匹配）。
@export var tile_size: int = 64

## 地形随机种子。设为 0 则每次随机。
@export var seed: int = 0

## 地形配置文件路径（JSON 格式）。
@export var config_path: String = DEFAULT_CONFIG_PATH

## 是否在生成完成后通过 EventBus 广播。
@export var notify_on_complete: bool = true

# ============================================================
# 5. 公开变量
# ============================================================

# ============================================================
# 6. 私有变量
# ============================================================

var _rng: RandomNumberGenerator = null

## 从配置文件加载的地形配置缓存。[br]
## 结构：{ "dirt": { "scene": PackedScene, "weight": 0.45 }, ... }
var _tile_configs: Dictionary = {}

# ============================================================
# 7. @onready 变量
# ============================================================

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 注册到 "world" group，供 TileActions 等系统查找
	add_to_group("world")
	# 监听地块操作事件
	if EventBus:
		EventBus.tile_action_triggered.connect(_on_tile_action_triggered)
	generate()
	Pathfinding._ensure_initialized()

func _exit_tree() -> void:
	if EventBus:
		EventBus.tile_action_triggered.disconnect(_on_tile_action_triggered)

# ============================================================
# 9. 公开方法
# ============================================================

## 执行地形生成。
## 会先清除已有的子节点（重新生成），然后根据 [member generation_mode] 调用对应的生成算法。
func generate() -> void:
	_clear_existing_tiles()
	_init_rng()
	_load_config()

	match generation_mode:
		GenerationMode.ALL_RANDOM:
			_generate_all_random()
		GenerationMode.ISLAND:
			_generate_island()
		_:
			push_error("TerrainGenerator: 未知的生成模式: %d" % generation_mode)
			return

	print("TerrainGenerator: 生成了 %d 个地块 (%dx%d, mode=%d)" % [get_child_count(), map_width, map_height, generation_mode])

	if notify_on_complete and EventBus:
		EventBus.terrain_generated.emit()

## 根据网格坐标获取地块数据。
## 返回 [code]null[/code] 表示该位置无地块。
func get_tile_data_at(grid_x: int, grid_y: int) -> Resource:
	var node: Node = _find_tile_node(grid_x, grid_y)
	if node:
		return node.get_meta("tile_data", null)
	return null

# ============================================================
# 10. 私有方法 — 配置加载
# ============================================================

## 从 JSON 配置文件加载地形配置，存入 [member _tile_configs]。
func _load_config() -> void:
	_tile_configs.clear()

	if not FileAccess.file_exists(config_path):
		push_error("TerrainGenerator: 地形配置文件不存在: %s" % config_path)
		return

	var file: FileAccess = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("TerrainGenerator: 无法打开地形配置文件: %s" % config_path)
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("TerrainGenerator: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return

	var data = json.data
	if not data is Dictionary:
		push_error("TerrainGenerator: 配置文件顶层应为 JSON 对象")
		return

	var raw: Dictionary = data as Dictionary
	for key: String in raw:
		var entry = raw[key]
		if not entry is Dictionary:
			push_warning("TerrainGenerator: 跳过配置项 '%s'（值不是 JSON 对象）" % key)
			continue

		var entry_dict: Dictionary = entry as Dictionary
		if not entry_dict.has("scene") or not entry_dict.has("weight"):
			push_warning("TerrainGenerator: 跳过配置项 '%s'（缺少 scene 或 weight 字段）" % key)
			continue

		var scene_path: String = entry_dict["scene"]
		if not ResourceLoader.exists(scene_path):
			push_error("TerrainGenerator: 地块场景不存在 '%s'，降级为占位场景" % scene_path)
			scene_path = FALLBACK_SCENE_PATH

		var scene: PackedScene = _safe_load_scene(scene_path)
		_tile_configs[key] = {
			"scene": scene,
			"weight": float(entry_dict["weight"]),
		}

## 安全加载场景 — 成功返回 PackedScene，失败则降级为占位场景。
func _safe_load_scene(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var loaded: PackedScene = load(path)
		if loaded != null:
			return loaded
		push_error("TerrainGenerator: 场景加载失败 '%s'，降级为占位场景" % path)
	else:
		push_error("TerrainGenerator: 场景路径不存在 '%s'，降级为占位场景" % path)

	if ResourceLoader.exists(FALLBACK_SCENE_PATH):
		var fallback: PackedScene = load(FALLBACK_SCENE_PATH)
		if fallback != null:
			return fallback

	push_error("TerrainGenerator: 占位场景也不可用 '%s'" % FALLBACK_SCENE_PATH)
	return null

## 根据配置键名获取对应的 TileType 枚举值。
func _key_to_tile_type(key: String) -> int:
	match key:
		"dirt":
			return TileInfoRef.TileType.DIRT
		"stone":
			return TileInfoRef.TileType.STONE
		"ocean":
			return TileInfoRef.TileType.OCEAN
		"farmland":
			return TileInfoRef.TileType.FARMLAND
		_:
			push_warning("TerrainGenerator: 未知的地块类型键 '%s'，fallback 为 DIRT" % key)
			return TileInfoRef.TileType.DIRT

## 根据配置键名获取默认变种名称。
func _key_to_variant(key: String) -> String:
	match key:
		"dirt":
			return "soil"
		"stone":
			return "hard_stone"
		"ocean":
			return "deep"
		"farmland":
			return "soil_farmland"
		_:
			return ""

# ============================================================
# 10. 私有方法 — 地形生成算法
# ============================================================

## 全随机生成模式。
## 遍历所有网格位置，按配置中的权重随机选取地块类型并实例化。
func _generate_all_random() -> void:
	if _tile_configs.is_empty():
		push_warning("TerrainGenerator: 没有可用的地形配置，全部使用占位场景")
		_generate_fallback_grid()
		return

	# 构建加权选择列表
	var entries: Array[Dictionary] = []
	var total_weight: float = 0.0
	for key: String in _tile_configs:
		var cfg: Dictionary = _tile_configs[key]
		var entry := {
			"key": key,
			"type": _key_to_tile_type(key),
			"scene": cfg["scene"],
			"weight": cfg["weight"],
		}
		entries.append(entry)
		total_weight += cfg["weight"]

	if total_weight <= 0.0:
		push_error("TerrainGenerator: 权重之和必须大于 0")
		return

	for x: int in range(map_width):
		for y: int in range(map_height):
			var entry: Dictionary = _pick_weighted(entries, total_weight)
			var scene: PackedScene = entry["scene"] as PackedScene
			var instance: Node2D = scene.instantiate()

			# 定位
			instance.position = Vector2(x * tile_size, y * tile_size)

			# 命名便于调试
			instance.name = "tile_%d_%d" % [x, y]

			# 附加 TileData（含变种信息）
			var variant: String = _key_to_variant(entry["key"])
			var data: Resource = _create_tile_data(x, y, entry["type"], variant)
			if instance is BaseTile:
				(instance as BaseTile).set_tile_data(data)
			else:
				instance.set_meta("tile_data", data)

			add_child(instance)

## 岛屿生成模式（待实现）。
## 生成中心陆地被水域环绕的岛屿地形。
func _generate_island() -> void:
	push_warning("TerrainGenerator: ISLAND 生成模式尚未实现")
	_generate_fallback_grid()

## 全部使用占位场景铺满网格。
func _generate_fallback_grid() -> void:
	var fallback_scene: PackedScene = _safe_load_scene(FALLBACK_SCENE_PATH)
	if fallback_scene == null:
		push_error("TerrainGenerator: 占位场景不可用，无法生成任何地块")
		return

	for x: int in range(map_width):
		for y: int in range(map_height):
			var instance: Node2D = fallback_scene.instantiate()
			instance.position = Vector2(x * tile_size, y * tile_size)
			instance.name = "tile_%d_%d" % [x, y]

			var data: Resource = _create_tile_data(x, y, TileInfoRef.TileType.DIRT)
			if instance is BaseTile:
				(instance as BaseTile).set_tile_data(data)
			else:
				instance.set_meta("tile_data", data)

			add_child(instance)

## 按权重随机选取一个配置条目。
func _pick_weighted(entries: Array[Dictionary], total_weight: float) -> Dictionary:
	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry: Dictionary in entries:
		cumulative += entry["weight"]
		if roll < cumulative:
			return entry
	return entries[0]

# ============================================================
# 10. 私有方法 — 工具
# ============================================================

func _clear_existing_tiles() -> void:
	for child: Node in get_children():
		child.queue_free()

func _init_rng() -> void:
	_rng = RandomNumberGenerator.new()
	if seed != 0:
		_rng.seed = seed
	else:
		_rng.randomize()

## 创建地块数据资源。[br]
## [param variant] 用于设置变种名称（如 "soil"、"hard_stone"、"deep"），
## [TileInfo.apply_defaults] 会根据 [member TileInfo.tile_type] + [member TileInfo.variant] 设置完整默认值。
func _create_tile_data(x: int, y: int, tile_type: int, variant: String = "") -> Resource:
	var data: Resource = TileInfoRef.new()
	data.grid_position = Vector2i(x, y)
	data.tile_type = tile_type
	data.variant = variant
	data.apply_defaults()
	return data

func _find_tile_node(grid_x: int, grid_y: int) -> Node:
	var expected_name: String = "tile_%d_%d" % [grid_x, grid_y]
	return get_node_or_null(expected_name)

# ============================================================
# 10. 私有方法 — 事件处理
# ============================================================

## 响应地块操作菜单，将操作分发到 [TileActions] 执行。
func _on_tile_action_triggered(action: StringName, tiles: Array) -> void:
	var world_node: Node2D = self as Node2D
	match action:
		&"plow":
			TileActions.plow_tiles(tiles, world_node)
		&"dig":
			TileActions.dig_tiles(tiles, world_node)
		&"harvest":
			TileActions.harvest_crop(tiles, world_node)
		&"plant":
			TileActions.plant_crop(tiles, "wheat_tier1", world_node)
		_:
			push_warning("TerrainGenerator: 未知的地块操作 '%s'" % action)
