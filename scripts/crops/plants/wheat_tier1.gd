## 小麦 Tier 1 作物 — "原始小麦"。
##
## 挂载在 [code]wheat_tire_1.tscn[/code] 上。
## 属于禾本科（Poaceae），初始即可种植的基础粮食作物。
##
## 所有配置数据从 [code]config/crops/wheat_tier1.json[/code] 加载，
## 修改生长阶段、收获产物、地块需求等只需编辑 JSON，无需改代码。
class_name WheatTier1 extends Crop

# ============================================================
# 3. 常量
# ============================================================

## 作物配置文件路径。
const CONFIG_PATH: String = "res://config/crops/wheat_tier1.json"

# ============================================================
# 6. 私有变量
# ============================================================

var _config_cache: Dictionary = {}

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 先加载 JSON 配置并缓存，再调用父类 _ready()
	# 父类 _ready() 会调用 _get_stage_data() 等方法，此时缓存已就绪
	_config_cache = _load_config_file()
	super._ready()

# ============================================================
# 11. 虚方法覆写 — 身份
# ============================================================

func _get_crop_info() -> Dictionary:
	return {
		"crop_id": _config_cache.get("crop_id", ""),
		"crop_name": _config_cache.get("crop_name", ""),
		"plant_family": _config_cache.get("plant_family", ""),
		"tier": _config_cache.get("tier", 0),
		"description": _config_cache.get("description", ""),
		"scene_path": _config_cache.get("scene_path", ""),
	}

# ============================================================
# 11. 虚方法覆写 — 生长阶段
# ============================================================

func _get_stage_data() -> Array:
	var stages: Array = _config_cache.get("growth_stages", [])
	if stages.is_empty():
		push_error("WheatTier1: JSON 配置中缺少 growth_stages 数组")
	return stages

# ============================================================
# 11. 虚方法覆写 — 收获产物
# ============================================================

func _get_harvest_yields() -> Array:
	var yields: Array = _config_cache.get("harvest_yields", [])
	if yields.is_empty():
		push_error("WheatTier1: JSON 配置中缺少 harvest_yields 数组")
	return yields

# ============================================================
# 10. 私有方法 — JSON 加载
# ============================================================

## 从 [constant CONFIG_PATH] 加载并解析 JSON 配置文件。
## 返回解析后的 Dictionary。加载失败时返回空字典。
func _load_config_file() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("WheatTier1: 配置文件不存在: %s" % CONFIG_PATH)
		return {}

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("WheatTier1: 无法打开配置文件: %s" % CONFIG_PATH)
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("WheatTier1: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return {}

	var data = json.data
	if data is Dictionary:
		return data as Dictionary

	push_error("WheatTier1: 配置文件顶层应为 JSON 对象")
	return {}
