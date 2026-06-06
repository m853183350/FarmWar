## 仓库系统 — 分区物品存储。
##
## 挂载在 [Player] 节点下，管理玩家的物品库存。
## 通过监听 [signal EventBus.crop_harvested] 自动收集收获的产物，
## 当前仅提供控制台打印展示功能，后续将扩展 UI。
##
## 存储结构为分区式字典（JSON 化），分为：
##   - farm_products: 农产品（小麦、作物产物等）
##   - items: 道具、种子、材料等
##   - pending_1 / pending_2: 预留分区，便于后续扩展
class_name Storage extends Node

# ============================================================
# 1. 信号
# ============================================================

## 任意分区内容变化时发出。
signal contents_changed(partition: String)

# ============================================================
# 3. 常量
# ============================================================

## 物品目录配置文件路径。
const ITEM_CATALOG_PATH: String = "res://config/items/item_catalog.json"

## 控制台打印列宽。
const DISPLAY_COLUMN_WIDTH: int = 24

## 分区元数据配置。[br]
## 键为分区标识，值为 display_name 和排序权重。
const PARTITION_CONFIG: Dictionary = {
	"farm_products": {"display_name": "农场产品", "order": 0},
	"items": {"display_name": "道具", "order": 1},
	"pending_1": {"display_name": "待定1", "order": 2},
	"pending_2": {"display_name": "待定2", "order": 3},
}

## 按下Tab键时打印仓库内容到控制台，供调试使用。
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		print_contents()


# ============================================================
# 5. 公开变量
# ============================================================

## 分区存储内容。[br]
## 结构：[code]{ partition_key: { item_id: float_amount } }[/code]
var contents: Dictionary = {}

## 物品目录缓存（从 [constant ITEM_CATALOG_PATH] 加载）。[br]
## 结构：[code]{ item_id: { "display_name": String, "category": String } }[/code]
var catalog: Dictionary = {}

# ============================================================
# 6. 私有变量
# ============================================================

var _harvest_connected: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	_init_partitions()
	_load_catalog()
	if EventBus:
		EventBus.crop_harvested.connect(_on_crop_harvested)
		_harvest_connected = true

func _exit_tree() -> void:
	if _harvest_connected and EventBus:
		EventBus.crop_harvested.disconnect(_on_crop_harvested)
		_harvest_connected = false

# ============================================================
# 9. 公开方法 — 查询
# ============================================================

## 获取物品在所有分区中的总数量。
func get_amount(item_id: String) -> float:
	var total: float = 0.0
	for partition: String in contents:
		var partition_data: Dictionary = contents[partition] as Dictionary
		if partition_data.has(item_id):
			total += partition_data[item_id] as float
	return total

## 检查是否拥有足够数量的物品。
func has_item(item_id: String, amount: float = 1.0) -> bool:
	return get_amount(item_id) >= amount

# ============================================================
# 9. 公开方法 — 存取
# ============================================================

## 从仓库中移除指定数量的物品。[br]
## 返回 [code]true[/code] 表示移除成功，[code]false[/code] 表示数量不足。
func remove_item(item_id: String, amount: float) -> bool:
	if not has_item(item_id, amount):
		return false

	var remaining: float = amount
	for partition: String in contents:
		var partition_data: Dictionary = contents[partition] as Dictionary
		if not partition_data.has(item_id):
			continue
		var available: float = partition_data[item_id] as float
		if available >= remaining:
			partition_data[item_id] = available - remaining
			contents_changed.emit(partition)
			return true
		else:
			remaining -= available
			partition_data.erase(item_id)
			contents_changed.emit(partition)

	return true

# ============================================================
# 9. 公开方法 — 展示
# ============================================================

## 在控制台打印仓库当前内容。[br]
## 格式为分区标题 + 对齐的物品列表，空分区显示 "(空)"。
func print_contents() -> void:
	var header: String = "══════════════════════════════"
	print(header)
	print("  仓库内容")
	print(header)

	var sorted_partitions: Array = _get_sorted_partitions()
	for entry in sorted_partitions:
		var partition_key: String = entry["key"] as String
		var display_name: String = entry["display_name"] as String
		var partition_data: Dictionary = contents[partition_key] as Dictionary

		print("  [%s]" % display_name)

		if partition_data.is_empty():
			print("    (空)")
		else:
			# 按物品名排序
			var sorted_items: Array = []
			for item_id: String in partition_data:
				sorted_items.append({"item_id": item_id, "amount": partition_data[item_id]})
			sorted_items.sort_custom(_compare_items)

			for item_entry in sorted_items:
				var item_id: String = item_entry["item_id"] as String
				var amount: float = item_entry["amount"] as float
				var name: String = _get_display_name(item_id)
				var amount_str: String = "%.2f" % amount if amount != int(amount) else "%d" % int(amount)
				var line: String = "    %s%s" % [name, " "]
				# 手动填充空格对齐
				var padding: String = ""
				var padding_count: int = DISPLAY_COLUMN_WIDTH - name.length()
				for _i: int in range(padding_count):
					padding += " "
				line = "    %s%s%s" % [name, padding, amount_str]
				print(line)

	print(header)

# ============================================================
# 10. 私有方法 — 初始化
# ============================================================

## 初始化所有分区的空字典。
func _init_partitions() -> void:
	for partition_key: String in PARTITION_CONFIG:
		contents[partition_key] = {}

## 加载物品目录配置文件。
func _load_catalog() -> void:
	if not FileAccess.file_exists(ITEM_CATALOG_PATH):
		push_warning("Storage: 物品目录配置文件不存在: %s" % ITEM_CATALOG_PATH)
		return

	var file: FileAccess = FileAccess.open(ITEM_CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("Storage: 无法打开物品目录配置: %s" % ITEM_CATALOG_PATH)
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("Storage: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return

	var data = json.data
	if data is Dictionary:
		catalog = data as Dictionary
	else:
		push_error("Storage: 物品目录配置文件顶层应为 JSON 对象")

# ============================================================
# 10. 私有方法 — 事件响应
# ============================================================

## 响应 [signal EventBus.crop_harvested] 事件。[br]
## 遍历产物数组，将每项产物存入对应分区，然后打印仓库内容。
func _on_crop_harvested(yields: Array, _crop_id: String) -> void:
	for yield_entry in yields:
		var entry_dict: Dictionary = yield_entry as Dictionary
		var item_id: String = entry_dict.get("item_id", "")
		var amount: float = entry_dict.get("amount", 0.0)
		if item_id.is_empty() or amount <= 0.0:
			continue
		_deposit_item(item_id, amount)

	# print_contents()

# ============================================================
# 10. 私有方法 — 物品操作
# ============================================================

## 将物品存入对应的分区。[br]
## 物品类别不存在于目录时默认存入 [code]"items"[/code] 分区。
func _deposit_item(item_id: String, amount: float) -> void:
	var partition: String = _resolve_partition(item_id)
	if not contents.has(partition):
		contents[partition] = {}

	var partition_data: Dictionary = contents[partition] as Dictionary
	if partition_data.has(item_id):
		partition_data[item_id] = partition_data[item_id] as float + amount
	else:
		partition_data[item_id] = amount

	contents_changed.emit(partition)

## 根据物品 ID 解析所属分区。[br]
## 从物品目录查找类别，再映射到分区。未知物品默认存入 [code]"items"[/code]。
func _resolve_partition(item_id: String) -> String:
	if catalog.has(item_id):
		var entry: Dictionary = catalog[item_id] as Dictionary
		var category: String = entry.get("category", "")
		if not category.is_empty():
			return _resolve_category_to_partition(category)
	# 未知物品降级到 items 分区
	if not catalog.has(item_id):
		push_warning("Storage: 物品 '%s' 不在物品目录中，默认存入 'items' 分区" % item_id)
	return "items"

## 将物品类别映射到分区键。
func _resolve_category_to_partition(category: String) -> String:
	match category:
		"farm_product":
			return "farm_products"
		"seed":
			return "items"
		"material":
			return "items"
		"consumable":
			return "pending_1"
		_:
			return "items"

# ============================================================
# 10. 私有方法 — 工具
# ============================================================

## 获取按 [constant PARTITION_CONFIG] 中 order 排序的分区列表。
func _get_sorted_partitions() -> Array:
	var result: Array = []
	for partition_key: String in PARTITION_CONFIG:
		var cfg: Dictionary = PARTITION_CONFIG[partition_key] as Dictionary
		result.append({
			"key": partition_key,
			"display_name": cfg.get("display_name", partition_key),
			"order": cfg.get("order", 999),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	return result

## 获取物品的人类可读名称。[br]
## 从目录查找，未知物品返回 item_id 本身。
func _get_display_name(item_id: String) -> String:
	if catalog.has(item_id):
		var entry: Dictionary = catalog[item_id] as Dictionary
		var name_: String = entry.get("display_name", "")
		if not name_.is_empty():
			return name
	return item_id

static func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	return a["item_id"] < b["item_id"]
