## 小麦 Tier 1 作物 — "原始小麦"。
##
## 挂载在 [code]wheat_tire_1.tscn[/code] 上。
## 属于禾本科（Poaceae），初始即可种植的基础粮食作物。
##
## 所有配置数据从 [code]config/crops/wheat_tier1.json[/code] 加载，
## 修改生长阶段、收获产物、地块需求等只需编辑 JSON，无需改代码。
class_name WheatTier1 extends Crop

const JsonConfigLoader := preload("res://scripts/utils/json_loader.gd")

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
	_config_cache = JsonConfigLoader.load_config_file(CONFIG_PATH, "WheatTier1")
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
# 11. 虚方法覆写 — 土壤需求
# ============================================================

func _get_soil_requirements() -> Dictionary:
	var reqs: Dictionary = _config_cache.get("soil_requirements", {})
	if reqs.is_empty():
		push_error("WheatTier1: JSON 配置中缺少 soil_requirements 对象")
	return reqs

# ============================================================
# 10. 私有方法 — JSON 加载
# ============================================================

# _load_config_file 已迁移至 JsonConfigLoader.load_config_file()
