## 地块信息面板 — 显示鼠标悬停地块的属性和作物状态。
##
## 作为 HUD 层的 Autoload，位于屏幕右侧居中。
## 实时刷新（_process），无数据时自动隐藏。
## 鼠标事件穿透，不阻挡任何操作。
##
## 显示内容：
##   - 地块信息：湿度 / 温度 / 肥力
##   - 作物信息：作物类型 / 生长速度（倍率 + 剩余秒数）/ 收获倍率
extends CanvasLayer

const WorldUtils := preload("res://scripts/utils/world_utils.gd")

# ============================================================
# 3. 常量 — 布局
# ============================================================

## 面板宽度占窗口宽度的比例。
const PANEL_WIDTH_RATIO: float = 0.10

## 面板高度占窗口高度的比例。
const PANEL_HEIGHT_RATIO: float = 0.25

## 面板内边距（px）。
const PANEL_PADDING: int = 8

## 行间距（px）。
const LINE_SEPARATION: int = 4

## 标题字体大小。
const HEADER_FONT_SIZE: int = 13

## 正文字体大小。
const BODY_FONT_SIZE: int = 11

## 背景颜色（深色半透明）。
const BG_COLOR: Color = Color(0.08, 0.08, 0.12, 0.88)

## 标题颜色。
const HEADER_COLOR: Color = Color(0.4, 0.7, 1.0, 1.0)

## 正文本颜色。
const TEXT_COLOR: Color = Color(0.85, 0.85, 0.85, 1.0)

## 高亮数值颜色（重要指标）。
const HIGHLIGHT_COLOR: Color = Color(1.0, 0.85, 0.3, 1.0)

## 无数据时显示的占位符。
const NO_DATA: String = "—"

# ============================================================
# 6. 私有变量 — 缓存
# ============================================================

var _world_cache: Node2D = null
var _tile_size_cache: int = 64

# ============================================================
# 6. 私有变量 — UI 控件引用
# ============================================================

var _bg: ColorRect = null
var _vbox: VBoxContainer = null

var _tile_header: Label = null
var _moisture_label: Label = null
var _temperature_label: Label = null
var _fertility_label: Label = null

var _crop_header: Label = null
var _crop_type_label: Label = null
var _speed_label: Label = null
var _yield_label: Label = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	layer = 100000
	_create_ui()
	_update_layout()
	get_tree().root.size_changed.connect(_update_layout)

func _process(_delta: float) -> void:
	_update_display()

# ============================================================
# 10. 私有方法 — UI 创建
# ============================================================

func _create_ui() -> void:
	# 背景
	_bg = ColorRect.new()
	_bg.name = "Background"
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.color = BG_COLOR
	add_child(_bg)

	# 垂直容器
	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_theme_constant_override("separation", LINE_SEPARATION)
	add_child(_vbox)

	# -- 地块信息段 --
	_tile_header = _create_label("◈ 地块信息", HEADER_FONT_SIZE, HEADER_COLOR)
	_vbox.add_child(_tile_header)

	_moisture_label = _create_label("", BODY_FONT_SIZE, TEXT_COLOR)
	_vbox.add_child(_moisture_label)

	_temperature_label = _create_label("", BODY_FONT_SIZE, TEXT_COLOR)
	_vbox.add_child(_temperature_label)

	_fertility_label = _create_label("", BODY_FONT_SIZE, TEXT_COLOR)
	_vbox.add_child(_fertility_label)

	# 分隔间距
	_vbox.add_child(_create_spacer(6))

	# -- 作物信息段 --
	_crop_header = _create_label("◈ 作物信息", HEADER_FONT_SIZE, HEADER_COLOR)
	_vbox.add_child(_crop_header)

	_crop_type_label = _create_label("", BODY_FONT_SIZE, TEXT_COLOR)
	_vbox.add_child(_crop_type_label)

	_speed_label = _create_label("", BODY_FONT_SIZE, TEXT_COLOR)
	_vbox.add_child(_speed_label)

	_yield_label = _create_label("", BODY_FONT_SIZE, HIGHLIGHT_COLOR)
	_vbox.add_child(_yield_label)

## 创建带样式的 Label。
func _create_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

## 创建垂直间距占位 Control。
func _create_spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer

# ============================================================
# 10. 私有方法 — 布局
# ============================================================

func _update_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width: float = viewport_size.x * PANEL_WIDTH_RATIO
	var panel_height: float = viewport_size.y * PANEL_HEIGHT_RATIO
	var panel_x: float = viewport_size.x - panel_width
	var panel_y: float = (viewport_size.y - panel_height) / 2.0

	# 背景
	_bg.position = Vector2(panel_x, panel_y)
	_bg.size = Vector2(panel_width, panel_height)

	# 内容容器（带内边距）
	_vbox.position = Vector2(panel_x + PANEL_PADDING, panel_y + PANEL_PADDING)
	_vbox.size = Vector2(panel_width - PANEL_PADDING * 2, panel_height - PANEL_PADDING * 2)

# ============================================================
# 10. 私有方法 — 数据更新
# ============================================================

func _update_display() -> void:
	# 延迟缓存世界节点
	if _world_cache == null or not is_instance_valid(_world_cache):
		_world_cache = WorldUtils.get_world()
		if _world_cache == null:
			_show_empty()
			return

	# 使用 world 节点的 get_global_mouse_position() 获取准确的世界坐标。
	# 这样可以正确处理摄像机平移和缩放，与 TileSelector 的行为一致。
	var world_pos: Vector2 = _world_cache.get_global_mouse_position()

	var grid: Vector2i = Vector2i(
		int(floorf(world_pos.x / _tile_size_cache)),
		int(floorf(world_pos.y / _tile_size_cache))
	)

	# 鼠标在世界范围外
	if world_pos.x < 0 or world_pos.y < 0:
		_show_empty()
		return

	# 查找地块
	var tile: Node2D = WorldUtils.find_tile(_world_cache, grid)
	if tile == null:
		_show_empty()
		return

	# 更新地块信息
	_update_tile_info(tile)

	# 更新作物信息（如果有作物）
	_update_crop_info(tile)

	show()

func _show_empty() -> void:
	hide()

# ============================================================
# 10. 私有方法 — 地块信息
# ============================================================

func _update_tile_info(tile: Node2D) -> void:
	var moisture: float = 0.0
	var temperature: float = 25.0
	var fertility: float = 0.0

	if tile.has_method("get_moisture"):
		moisture = tile.get_moisture()
	if tile.has_method("get_temperature"):
		temperature = tile.get_temperature()
	if tile.has_method("get_fertility"):
		fertility = tile.get_fertility()

	var type_name: String = "未知"
	if tile.has_method("get_type_name"):
		type_name = tile.get_type_name()

	_tile_header.text = "◈ %s" % type_name
	_moisture_label.text = "  湿度: %.1f" % moisture
	_temperature_label.text = "  温度: %.1f°C" % temperature
	_fertility_label.text = "  肥力: %.1f" % fertility

# ============================================================
# 10. 私有方法 — 作物信息
# ============================================================

func _update_crop_info(tile: Node2D) -> void:
	# 查找地块上的作物
	var crop: Node2D = null
	if tile.has_method("get_all_occupants"):
		var occupants: Array = tile.get_all_occupants()
		for occ: Node in occupants:
			if is_instance_valid(occ) and occ.has_method("get_yield_multiplier"):
				crop = occ as Node2D
				break

	if crop == null:
		_crop_header.text = "◈ 作物信息"
		_crop_type_label.text = "  %s" % NO_DATA
		_speed_label.text = "  生长速度: %s" % NO_DATA
		_yield_label.text = "  收获倍率: %s" % NO_DATA
		return

	# 作物基本信息
	var crop_id: String = ""
	if crop.has_method("_get_crop_info"):
		crop_id = crop.call("_get_crop_info").get("crop_name", "")
	if crop_id.is_empty() and crop.has_method("get_script"):
		var scr: Script = crop.get_script()
		if scr:
			crop_id = scr.get_global_name()

	_crop_header.text = "◈ 作物信息"
	_crop_type_label.text = "  %s" % crop_id

	# 生长速度信息
	var speed_modifier: float = 1.0
	if crop.has_method("get_growth_speed"):
		speed_modifier = crop.get_growth_speed()

	var stage_info: Dictionary = {}
	if crop.has_method("get_stage_info"):
		stage_info = crop.get_stage_info()

	var speed_text: String = "  %.2fx" % speed_modifier

	# 如果有阶段信息，计算剩余时间
	if not stage_info.is_empty():
		var duration: int = stage_info.get("duration_ticks", 0)
		var progress: float = stage_info.get("progress", 0.0)
		var is_final: bool = stage_info.get("is_final", false)
		var stage_idx: int = stage_info.get("stage_index", 0)
		var total: int = stage_info.get("total_stages", 0)

		if is_final or duration <= 0:
			speed_text += " (已成熟)"
		elif speed_modifier > 0.001:
			var remaining_ticks: float = (1.0 - progress) * float(duration) / speed_modifier
			var remaining_secs: float = remaining_ticks / 20.0
			speed_text += " (%d/%d 剩余%.1fs)" % [stage_idx + 1, total, remaining_secs]
	else:
		speed_text += " (无法获取阶段信息)"

	_speed_label.text = "  生长速度: %s" % speed_text

	# 收获倍率
	var yield_modifier: float = 1.0
	if crop.has_method("get_yield_multiplier"):
		yield_modifier = crop.get_yield_multiplier()
	_yield_label.text = "  收获倍率: %.2fx" % yield_modifier
