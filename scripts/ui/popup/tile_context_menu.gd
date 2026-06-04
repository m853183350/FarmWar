## 地块操作上下文菜单。
##
## 在地块框选完成后弹出，提供操作选项（翻耕、挖掘、取消）。
## 使用全屏透明遮罩阻断世界交互，避免点击空地触发新选择。
##
## 使用方式：
##   由 [TileSelector] 在框选完成时实例化并调用 [method show_menu]。
class_name TileContextMenu extends CanvasLayer

# ============================================================
# 1. 信号
# ============================================================

## 菜单项被选中。action 为 "plow"/"dig" 等，tiles 为选中的地块坐标数组。
signal action_selected(action: String, tiles: Array)

## 菜单被取消（点遮罩或取消按钮）。
signal cancelled()

# ============================================================
# 3. 常量
# ============================================================

const MENU_ITEMS: Array[Dictionary] = [
	{ "text": "翻耕", "action": "plow" },
	{ "text": "挖掘", "action": "dig" },
	{ "text": "种植", "action": "plant" },
]

const BUTTON_MIN_WIDTH: float = 160.0
const BUTTON_FONT_SIZE: int = 22
const PANEL_PADDING: int = 12

# ============================================================
# 5. 公开变量
# ============================================================

var tiles: Array = []

# ============================================================
# 6. 私有变量
# ============================================================

var _blocker: ColorRect = null
var _panel: Panel = null
var _title_label: Label = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	layer = 4
	visible = false
	_build_ui()

# ============================================================
# 9. 公开方法
# ============================================================

## 在指定屏幕位置显示菜单。
func show_menu(screen_pos: Vector2, selected_tiles: Array) -> void:
	tiles = selected_tiles
	_title_label.text = "已选中 %d 个地块" % tiles.size()

	# 将面板定位到鼠标附近，确保不超出屏幕右/下边缘
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = _panel.size
	var pos: Vector2 = screen_pos + Vector2(8, 8)
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = screen_pos.x - panel_size.x - 8
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = screen_pos.y - panel_size.y - 8
	_panel.position = pos

	visible = true

# ============================================================
# 10. 私有方法 — 构建
# ============================================================

func _build_ui() -> void:
	# 全屏透明遮罩 — 阻断下层交互
	_blocker = ColorRect.new()
	_blocker.name = "Blocker"
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.color = Color(0.0, 0.0, 0.0, 0.0)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(_on_blocker_clicked)
	add_child(_blocker)

	# 菜单面板
	_panel = Panel.new()
	_panel.name = "Panel"
	_blocker.add_child(_panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_title_label)

	# 分隔线
	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# 操作按钮
	for item: Dictionary in MENU_ITEMS:
		var btn: Button = _create_action_button(item["text"], item["action"])
		vbox.add_child(btn)

	# 分隔线
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	# 取消按钮
	var cancel_btn: Button = Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "取消"
	cancel_btn.custom_minimum_size.x = BUTTON_MIN_WIDTH
	cancel_btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	cancel_btn.pressed.connect(_on_cancel)
	vbox.add_child(cancel_btn)

	# 面板内部边距
	_panel.add_theme_stylebox_override("panel", _make_panel_stylebox())

func _create_action_button(text: String, action: String) -> Button:
	var btn: Button = Button.new()
	btn.name = "Btn_" + action
	btn.text = text
	btn.custom_minimum_size.x = BUTTON_MIN_WIDTH
	btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	btn.pressed.connect(_on_action.bind(action))
	return btn

func _make_panel_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = PANEL_PADDING
	style.content_margin_right = PANEL_PADDING
	style.content_margin_top = PANEL_PADDING
	style.content_margin_bottom = PANEL_PADDING
	return style

# ============================================================
# 10. 私有方法 — 事件
# ============================================================

func _on_action(action: String) -> void:
	action_selected.emit(action, tiles)
	queue_free()

func _on_cancel() -> void:
	cancelled.emit()
	queue_free()

func _on_blocker_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		cancelled.emit()
		queue_free()
