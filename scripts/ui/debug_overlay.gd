## Debug 叠加层。
##
## 作为 Autoload 注册在项目设置中，挂载在 Layer 5（Debug 层）。
## F3 开关显示，F4/F5 翻页。鼠标事件穿透，不阻挡任何操作。
##
## 各系统通过 [method set_entry] 写入键值对数据，
## 叠加层按 key 字母序渲染为彩色纯文本。
##
## 使用方式：
##   [codeblock]
##   DebugOverlay.set_entry("fps", Engine.get_frames_per_second())
##   DebugOverlay.set_entry("tick", TickSystem.get_tick_count())
##   DebugOverlay.remove_entry("fps")
##   [/codeblock]
extends CanvasLayer

# ============================================================
# 1. 信号
# ============================================================

## 数据变更时发出，参数为新数据快照。
signal data_changed(data: Dictionary)

# ============================================================
# 3. 常量
# ============================================================

const FONT_SIZE: int = 11
const LINE_SPACING: int = 2
const PANEL_WIDTH_RATIO: float = 0.33
const H_MARGIN: int = 8
const V_MARGIN: int = 6
const PAGE_INDICATOR_HEIGHT: int = 18
const CORNER_RADIUS: int = 4

const BG_COLOR: Color = Color(0.102, 0.102, 0.102, 0.8)
const KEY_COLOR: Color = Color(0.667, 0.667, 0.667, 1.0)
const VALUE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const PAGE_COLOR: Color = Color(0.533, 0.533, 0.533, 1.0)

# ============================================================
# 6. 私有变量
# ============================================================

var _data: Dictionary = {}
var _current_page: int = 0
var _total_pages: int = 1

# ============================================================
# 6. 私有变量 — UI 控件引用
# ============================================================

var _bg_rect: ColorRect = null
var _content_label: RichTextLabel = null
var _page_label: Label = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	layer = 5
	_create_ui()
	_hide()
	# 监听窗口尺寸变化以重新布局
	get_tree().root.size_changed.connect(_on_viewport_size_changed)

func _process(_delta: float) -> void:
	if not visible:
		return
	_render()

func _input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_F3:
			_toggle()
			get_viewport().set_input_as_handled()
		KEY_F4:
			if not visible:
				return
			if _current_page > 0:
				_current_page -= 1
			get_viewport().set_input_as_handled()
		KEY_F5:
			if not visible:
				return
			if _current_page < _total_pages - 1:
				_current_page += 1
			get_viewport().set_input_as_handled()

# ============================================================
# 9. 公开方法
# ============================================================

## 设置一个调试数据条目。key 已存在则覆盖 value。
func set_entry(key: String, value: Variant) -> void:
	_data[key] = value

## 移除一个调试数据条目。key 不存在时不报错。
func remove_entry(key: String) -> void:
	_data.erase(key)

## 获取某个条目的字符串值。key 不存在返回空字符串。
func get_entry(key: String) -> String:
	if _data.has(key):
		return str(_data[key])
	return ""

## 清空所有条目。
func clear_entries() -> void:
	_data.clear()
	_current_page = 0
	_total_pages = 1

## 获取当前所有数据的只读副本。
func get_all_entries() -> Dictionary:
	return _data.duplicate()

## 批量设置条目（合并到现有数据，同名 key 覆盖）。
func set_entries(data: Dictionary) -> void:
	_data.merge(data, true)

# ============================================================
# 10. 私有方法 — UI 创建
# ============================================================

## 创建子控件：背景 ColorRect、内容 RichTextLabel、页码 Label。
func _create_ui() -> void:
	# 背景面板
	_bg_rect = ColorRect.new()
	_bg_rect.name = "Background"
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_rect.color = BG_COLOR
	add_child(_bg_rect)

	# 内容文本
	_content_label = RichTextLabel.new()
	_content_label.name = "ContentLabel"
	_content_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_label.bbcode_enabled = true
	_content_label.clip_contents = true
	_content_label.scroll_active = false
	_content_label.selection_enabled = false
	_content_label.size_flags_horizontal = Control.SIZE_FILL
	_content_label.size_flags_vertical = Control.SIZE_FILL
	add_child(_content_label)

	# 页码指示器
	_page_label = Label.new()
	_page_label.name = "PageLabel"
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_page_label.add_theme_font_size_override("font_size", FONT_SIZE - 1)
	_page_label.add_theme_color_override("font_color", PAGE_COLOR)
	add_child(_page_label)

	# 应用字体设置
	_setup_font()

	# 初始布局
	_update_layout()

func _setup_font() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	_content_label.add_theme_font_override("normal_font", font)
	_content_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_content_label.add_theme_constant_override("line_separation", LINE_SPACING)

## 更新子控件的位置和大小（屏幕尺寸变化时调用）。
func _update_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width: float = viewport_size.x * PANEL_WIDTH_RATIO
	var panel_height: float = viewport_size.y

	# 背景：右上角
	_bg_rect.position = Vector2(viewport_size.x - panel_width, 0.0)
	_bg_rect.size = Vector2(panel_width, panel_height)

	# 内容文本：带内边距
	_content_label.position = Vector2(
		viewport_size.x - panel_width + H_MARGIN,
		V_MARGIN
	)
	_content_label.size = Vector2(
		panel_width - H_MARGIN * 2.0,
		panel_height - V_MARGIN * 2.0 - PAGE_INDICATOR_HEIGHT
	)

	# 页码：右下角
	_page_label.position = Vector2(
		viewport_size.x - panel_width + H_MARGIN,
		panel_height - PAGE_INDICATOR_HEIGHT - V_MARGIN
	)
	_page_label.size = Vector2(panel_width - H_MARGIN * 2.0, PAGE_INDICATOR_HEIGHT)

func _on_viewport_size_changed() -> void:
	_update_layout()

# ============================================================
# 10. 私有方法 — 渲染
# ============================================================

## 构建并刷新显示文本。
func _render() -> void:
	if _data.is_empty():
		_content_label.text = ""
		_page_label.text = ""
		_total_pages = 1
		return

	# 计算每页行数
	var line_height: float = float(FONT_SIZE + LINE_SPACING)
	var content_height: float = _content_label.size.y
	var lines_per_page: int = maxi(1, int(floorf(content_height / line_height)))

	# 排序 key
	var keys: Array[String] = []
	keys.assign(_data.keys())
	keys.sort_custom(func(a: String, b: String) -> bool:
		return a.to_lower() < b.to_lower()
	)

	# 计算总页数
	_total_pages = maxi(1, ceili(float(keys.size()) / float(lines_per_page)))
	_current_page = clampi(_current_page, 0, _total_pages - 1)

	# 当前页的条目范围
	var start: int = _current_page * lines_per_page
	var end: int = mini(start + lines_per_page, keys.size())

	# 用 BBCode 构建文本
	var lines: PackedStringArray = PackedStringArray()
	for i: int in range(start, end):
		var key: String = keys[i]
		var val_str: String = str(_data[key])
		var line: String = (
			"[color=#" + _color_to_hex(KEY_COLOR) + "]" +
			key +
			"[/color][color=#" + _color_to_hex(VALUE_COLOR) + "]: " +
			val_str +
			"[/color]"
		)
		lines.append(line)

	_content_label.text = "\n".join(lines)
	_page_label.text = "[%d/%d]" % [_current_page + 1, _total_pages]

# ============================================================
# 10. 私有方法 — 输入
# ============================================================

## 切换叠加层可见性。
func _toggle() -> void:
	if visible:
		_hide()
	else:
		_show()

func _show() -> void:
	_update_layout()
	_current_page = 0
	show()

func _hide() -> void:
	hide()

# ============================================================
# 10. 私有方法 — 工具
# ============================================================

## 将 Color 转换为 BBCode 可用的 RRGGBB 十六进制字符串。
func _color_to_hex(c: Color) -> String:
	return "%02X%02X%02X" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
