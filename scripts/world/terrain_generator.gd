## 随机地形生成器。
##
## 挂载在 [code]world[/code] 节点上，在 [method _ready] 时自动生成地图网格。
## 支持多种生成模式，地形配置从外部 JSON 文件加载。
##
## 地块创建支持两种模式：
##   - [b]TSCN 模式[/b]：配置中指定了 [code]scene[/code] 的变种，直接实例化 PackedScene。
##   - [b]程序化模式[/b]：没有 TSCN 的变种，动态创建 Sprite2D 节点并附加纹理和脚本。
##
## 使用方式：
##   1. 将本脚本挂载到 world 场景的根节点
##   2. 在编辑器中调整 map_width / map_height / seed / generation_mode 等参数
##   3. 编辑 [code]config/terrain_config.json[/code] 配置地块类型、属性与变种
##   4. 运行游戏即可看到生成的地形
class_name TerrainGenerator extends Node2D

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

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

## 纹理资源目录根路径（从配置文件读取）。
var _texture_dir: String = "res://assets/sprites/tiles/"

## 占位/降级纹理（从配置文件读取）。
var _null_texture: Texture2D = null

## 脚本资源目录根路径（从配置文件读取）。
var _script_dir: String = "res://scripts/world/tiles/"

## 从配置文件加载的地形配置缓存。[br]
## 结构：[code]{ "dirt": { "weight": 0.60, "tile_type": 0, "defaults": {...},
## "variants": { "soil": { "scene": PackedScene, ... }, ... } }, ... }[/code]
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

	# 地形生成完成后，全量更新所有地块的属性（温度、湿度、肥力）和标签
	update_all_tiles_properties()

	if notify_on_complete and EventBus:
		EventBus.terrain_generated.emit()

## 根据网格坐标获取地块数据。
## 返回 [code]null[/code] 表示该位置无地块。
func get_tile_data_at(grid_x: int, grid_y: int) -> Resource:
	var node: Node = _find_tile_node(grid_x, grid_y)
	if node:
		return node.get_meta("tile_data", null)
	return null

## 获取已加载的地形配置缓存。
## 供 [TileActions] 等外部系统查询地块类型配置（用于转化目标查找等）。
func get_tile_configs() -> Dictionary:
	return _tile_configs

## 根据地块类型键名（如 "dirt"、"stone"）获取配置。
func get_tile_config_for_type(type_key: String) -> Dictionary:
	return _tile_configs.get(type_key, {})

## 合并类型默认值与变种覆盖值，返回可用于 [method TileInfo.apply_defaults] 的配置字典。
func merge_tile_config(type_cfg: Dictionary, variant_cfg: Dictionary) -> Dictionary:
	return _merge_tile_config(type_cfg, variant_cfg)

## 程序化创建地块节点（无 TSCN 场景时使用）。
##
## 根据配置中的纹理和脚本路径创建 [Sprite2D] 节点，
## 并设置 [member BaseTile.tile_type]、[member BaseTile.variant]、
## [member BaseTile.display_name] 等标识属性。
##
## [param type_cfg] 类型级配置字典（含 tile_type、defaults 等）。
## [param variant_cfg] 变种级配置字典（含 name、texture、script 等）。
## [param variant_key] 变种键名（如 "grassland"、"gravel" 等）。
##
## 返回配置好的 [Node2D] 节点，纹理缺失时使用 null_img 降级。
func create_tile_programmatically(type_cfg: Dictionary, variant_cfg: Dictionary, variant_key: String) -> Node2D:
	return _create_tile_programmatically(type_cfg, variant_cfg, variant_key)

## 根据类型键和变种键创建地块实例。
## 优先使用 TSCN 模式，无场景时回退到程序化创建。
func create_tile_instance(type_key: String, variant_key: String) -> Node2D:
	var type_cfg: Dictionary = _tile_configs.get(type_key, {})
	if type_cfg.is_empty():
		push_error("TerrainGenerator: 未知的地块类型 '%s'" % type_key)
		return _create_fallback_tile()
	var variants: Dictionary = type_cfg.get("variants", {})
	var variant_cfg: Dictionary = variants.get(variant_key, {})
	if variant_cfg.is_empty():
		push_warning("TerrainGenerator: 类型 '%s' 中不存在变种 '%s'" % [type_key, variant_key])
		return _create_fallback_tile()
	return _create_tile_instance(type_cfg, variant_cfg, variant_key)

## 全量更新所有地块的属性（温度、湿度、肥力）和标签。
##
## 流程：
##   1. 遍历所有子节点（地块），先统一更新标签
##   2. 再遍历所有地块，重新计算温度 / 湿度 / 肥力
##
## 应在以下时机调用：
##   - 地形生成完成后（[method generate] 自动调用）
##   - 外部需要全量刷新时（如加载存档后）
func update_all_tiles_properties() -> void:
	# 第一步：更新所有地块的标签
	for child: Node in get_children():
		if child is BaseTile:
			(child as BaseTile).update_tags()

	# 第二步：更新所有地块的温度、湿度、肥力
	for child: Node in get_children():
		if child is BaseTile:
			(child as BaseTile).update_properties()

	print("TerrainGenerator: 已完成全量地块属性更新")

## 响应地块变化，若变化涉及带有特定标签的地块，传播更新周围地块属性。
##
## 变化前和变化后都应检查是否有标签需要传播。
## [param old_tile_data] 变化前的地块数据（可能为 [code]null[/code]）。
## [param new_tile_data] 变化后的地块数据。
## [param grid_pos] 地块网格坐标。
func propagate_tile_tag_change(old_tile_data: Resource, new_tile_data: Resource, grid_pos: Vector2i) -> void:
	var old_tags: Array[String] = []
	var new_tags: Array[String] = []

	if old_tile_data:
		old_tags = old_tile_data.tags
	if new_tile_data:
		new_tags = new_tile_data.tags

	# 收集需要传播的标签（变化前后涉及的所有标签）
	var affected_tags: Array[String] = []
	for tag: String in old_tags:
		if tag not in affected_tags:
			affected_tags.append(tag)
	for tag: String in new_tags:
		if tag not in affected_tags:
			affected_tags.append(tag)

	for tag: String in affected_tags:
		BaseTile.propagate_tag_update(tag, grid_pos, self)

# ============================================================
# 10. 私有方法 — 配置加载
# ============================================================

## 从 JSON 配置文件加载地形配置，存入 [member _tile_configs]。
## 同时预加载场景、纹理和脚本资源。
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

	# 读取全局路径配置
	_texture_dir = raw.get("texture_dir", "res://assets/sprites/tiles/")
	_script_dir = raw.get("script_dir", "res://scripts/world/tiles/")
	var null_tex_path: String = raw.get("null_texture", "res://assets/sprites/null_img.png")
	_null_texture = _safe_load_texture(null_tex_path)

	# 验证 null_texture 加载成功
	if _null_texture == null:
		push_error("TerrainGenerator: 降级纹理不可用 '%s'，程序化地块将无纹理" % null_tex_path)

	# 解析各地块类型配置
	var tiles_raw = raw.get("tiles", {})
	if not tiles_raw is Dictionary:
		push_error("TerrainGenerator: 配置文件中缺少 'tiles' 字段或格式错误")
		return

	var tiles_dict: Dictionary = tiles_raw as Dictionary
	for type_key: String in tiles_dict:
		var entry = tiles_dict[type_key]
		if not entry is Dictionary:
			push_warning("TerrainGenerator: 跳过配置项 '%s'（值不是 JSON 对象）" % type_key)
			continue

		var entry_dict: Dictionary = entry as Dictionary
		var type_cfg := {
			"weight": float(entry_dict.get("weight", 0.0)),
			"name": entry_dict.get("name", ""),
			"tile_type": int(entry_dict.get("tile_type", 0)),
			"default_variant": entry_dict.get("default_variant", ""),
			"tags": entry_dict.get("tags", []),
			"defaults": entry_dict.get("defaults", {}),
			"variants": {},
			"gather_actions": entry_dict.get("gather_actions", []),
		}

		# 解析变种：预加载 scene / texture / script
		var variants_raw = entry_dict.get("variants", {})
		if not variants_raw is Dictionary:
			push_warning("TerrainGenerator: 类型 '%s' 的 variants 不是 JSON 对象，跳过" % type_key)
			type_cfg["variants"] = {}
		else:
			var variants_dict: Dictionary = variants_raw as Dictionary
			for var_key: String in variants_dict:
				var var_entry = variants_dict[var_key]
				if not var_entry is Dictionary:
					continue

				var var_dict: Dictionary = var_entry as Dictionary
				var var_cfg := {
					"name": var_dict.get("name", ""),
				}

				# 拷贝数值属性（变种级覆盖）
				for prop in ["moisture_base_rate", "fertility_base", "hardness", "depth",
						"fishable", "farmland", "resource_type"]:
					if var_dict.has(prop):
						var_cfg[prop] = var_dict[prop]

				# 加载场景（TSCN 模式）
				if var_dict.has("scene") and not str(var_dict["scene"]).is_empty():
					var scene_path: String = var_dict["scene"]
					var scene: PackedScene = _safe_load_scene(scene_path)
					if scene:
						var_cfg["scene"] = scene
					else:
						push_warning("TerrainGenerator: 变种 '%s.%s' 的场景加载失败，回退到程序化创建" % [type_key, var_key])

				# 加载纹理（程序化模式）
				if var_dict.has("texture") and not str(var_dict["texture"]).is_empty():
					var tex_path: String = _texture_dir + var_dict["texture"]
					var tex: Texture2D = _safe_load_texture(tex_path)
					if tex:
						var_cfg["texture"] = tex

				# 加载脚本（程序化模式）
				if var_dict.has("script") and not str(var_dict["script"]).is_empty():
					var script_path: String = _script_dir + var_dict["script"]
					if ResourceLoader.exists(script_path):
						var scr: Script = load(script_path) as Script
						if scr:
							var_cfg["script"] = scr
						else:
							push_error("TerrainGenerator: 脚本加载失败 '%s'" % script_path)
					else:
						push_error("TerrainGenerator: 脚本路径不存在 '%s'" % script_path)

				type_cfg["variants"][var_key] = var_cfg

		_tile_configs[type_key] = type_cfg

## 安全加载场景 — 成功返回 PackedScene，失败返回 null。
func _safe_load_scene(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var loaded: PackedScene = load(path) as PackedScene
		if loaded != null:
			return loaded
		push_error("TerrainGenerator: 场景加载失败 '%s'" % path)
	else:
		push_error("TerrainGenerator: 场景路径不存在 '%s'" % path)
	return null

## 安全加载纹理 — 成功返回 Texture2D，失败返回 null。
func _safe_load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var loaded: Texture2D = load(path) as Texture2D
		if loaded != null:
			return loaded
		push_error("TerrainGenerator: 纹理加载失败 '%s'" % path)
	else:
		push_error("TerrainGenerator: 纹理路径不存在 '%s'" % path)
	return null

## 合并类型默认值与变种覆盖值，返回可用于 [method TileInfo.apply_defaults] 的配置字典。
func _merge_tile_config(type_cfg: Dictionary, variant_cfg: Dictionary) -> Dictionary:
	var merged: Dictionary = {}

	# 复制类型级默认值
	var defaults: Dictionary = type_cfg.get("defaults", {})
	for key in defaults:
		merged[key] = defaults[key]

	# 设置标签（类型级）
	merged["tags"] = type_cfg.get("tags", [])

	# 用变种级属性覆盖
	for key in variant_cfg:
		if key not in ["name", "scene", "texture", "script"]:
			merged[key] = variant_cfg[key]

	# 变种名
	merged["variant_name"] = variant_cfg.get("name", "")

	return merged

# ============================================================
# 10. 私有方法 — 地形生成算法
# ============================================================

## 全随机生成模式。
## 遍历所有网格位置，按配置中的权重随机选取地块类型，再选取默认变种。
## 有 TSCN 的变种直接实例化场景，没有的则程序化创建 Sprite2D。
func _generate_all_random() -> void:
	if _tile_configs.is_empty():
		push_warning("TerrainGenerator: 没有可用的地形配置，全部使用占位场景")
		_generate_fallback_grid()
		return

	# 构建加权类型选择列表
	var types: Array[Dictionary] = []
	var total_weight: float = 0.0
	for key: String in _tile_configs:
		var cfg: Dictionary = _tile_configs[key]
		var w: float = cfg.get("weight", 0.0)
		if w <= 0.0:
			continue
		types.append({"key": key, "weight": w})
		total_weight += w

	if total_weight <= 0.0:
		push_error("TerrainGenerator: 权重之和必须大于 0")
		return

	for x: int in range(map_width):
		for y: int in range(map_height):
			var type_key: String = _pick_weighted_key(types, total_weight)
			var type_cfg: Dictionary = _tile_configs[type_key]
			var variant_key: String = type_cfg.get("default_variant", "")
			var variants: Dictionary = type_cfg.get("variants", {})
			var variant_cfg: Dictionary = variants.get(variant_key, {})

			if variant_cfg.is_empty():
				push_warning("TerrainGenerator: 类型 '%s' 缺少默认变种 '%s'" % [type_key, variant_key])
				continue

			# 创建地块实例
			var instance: Node2D = _create_tile_instance(type_cfg, variant_cfg, variant_key)
			if instance == null:
				continue

			# 定位
			instance.position = Vector2(x * tile_size, y * tile_size)

			# 命名便于调试
			instance.name = "tile_%d_%d" % [x, y]

			# 附加 TileInfo
			var merged_config: Dictionary = _merge_tile_config(type_cfg, variant_cfg)
			var tile_type: int = type_cfg.get("tile_type", 0)
			var data: Resource = _create_tile_data(x, y, tile_type, variant_key, merged_config)
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
	for x: int in range(map_width):
		for y: int in range(map_height):
			var instance: Node2D = _create_fallback_tile()
			instance.position = Vector2(x * tile_size, y * tile_size)
			instance.name = "tile_%d_%d" % [x, y]

			var data: Resource = _create_tile_data(x, y, TileInfoRef.TileType.DIRT)
			if instance is BaseTile:
				(instance as BaseTile).set_tile_data(data)
			else:
				instance.set_meta("tile_data", data)

			add_child(instance)

## 创建一个降级占位地块节点。
## 优先使用 FALLBACK_SCENE_PATH，不可用时程序化创建使用 null_texture。
func _create_fallback_tile() -> Node2D:
	# 尝试加载占位场景
	if ResourceLoader.exists(FALLBACK_SCENE_PATH):
		var scene: PackedScene = load(FALLBACK_SCENE_PATH) as PackedScene
		if scene:
			return scene.instantiate()

	# 场景不可用，程序化创建
	var node := Sprite2D.new()
	node.texture_filter = 1
	node.scale = Vector2(8, 8)
	node.centered = false
	if _null_texture:
		node.texture = _null_texture
	return node

## 按权重随机选取一个类型键名。
func _pick_weighted_key(entries: Array[Dictionary], total_weight: float) -> String:
	var roll: float = _rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry: Dictionary in entries:
		cumulative += entry["weight"]
		if roll < cumulative:
			return entry["key"]
	return entries[0]["key"]

# ============================================================
# 10. 私有方法 — 地块实例创建
# ============================================================

## 根据配置创建地块实例。
## 优先 TSCN 模式（variant_cfg 含 scene），否则程序化创建。
func _create_tile_instance(type_cfg: Dictionary, variant_cfg: Dictionary, variant_key: String) -> Node2D:
	# TSCN 模式
	if variant_cfg.has("scene") and variant_cfg["scene"] != null:
		var scene: PackedScene = variant_cfg["scene"] as PackedScene
		if scene:
			return scene.instantiate()

	# 程序化模式
	return _create_tile_programmatically(type_cfg, variant_cfg, variant_key)

## 程序化创建地块节点。
##
## 创建 [Sprite2D] 节点，从配置读取纹理（无则用 null_texture），
## 附加脚本并设置 tile_type / variant / display_name。
func _create_tile_programmatically(type_cfg: Dictionary, variant_cfg: Dictionary, variant_key: String) -> Node2D:
	var node := Sprite2D.new()
	node.texture_filter = 1
	node.scale = Vector2(8, 8)
	node.centered = false

	# 设置纹理（配置指定 → 降级纹理）
	var texture: Texture2D = variant_cfg.get("texture", null) as Texture2D
	if texture == null:
		texture = _null_texture
	if texture:
		node.texture = texture

	# 设置脚本
	if variant_cfg.has("script") and variant_cfg["script"] != null:
		var scr: Script = variant_cfg["script"] as Script
		node.set_script(scr)
		# 在 _ready() 之前设置标识属性，子类 _ready() 将不再覆盖
		node.set("tile_type", type_cfg.get("tile_type", -1))
		node.set("variant", variant_key)
		node.set("display_name", variant_cfg.get("name", ""))

	return node

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
## [param config] 由 [method _merge_tile_config] 合并后的配置字典，传入 [method TileInfo.apply_defaults]。
func _create_tile_data(x: int, y: int, tile_type: int, variant: String = "", config: Dictionary = {}) -> Resource:
	var data: Resource = TileInfoRef.new()
	data.grid_position = Vector2i(x, y)
	data.tile_type = tile_type
	data.variant = variant
	if not config.is_empty():
		data.apply_defaults(config)
	return data

func _find_tile_node(grid_x: int, grid_y: int) -> Node:
	return WorldUtils.find_tile(self, Vector2i(grid_x, grid_y))

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
