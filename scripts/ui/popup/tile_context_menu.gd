## 地块操作上下文菜单。
##
## 在地块框选完成后弹出，提供操作选项（翻耕、挖掘、种植、收获、取消）以及
## 派遣选项（派遣翻耕/种植/收获/挖掘），后者将任务分配给工作单位执行。
## 使用全屏透明遮罩阻断世界交互，避免点击空地触发新选择。
##
## 支持二级菜单：当 [member show_debug_menu] 为 true 时，所有操作项收入
## "Debug" 子菜单中，鼠标悬浮即可展开。子菜单触发按钮使用不同颜色标识。
## 子菜单仅在鼠标悬浮到另一个触发器时切换，不会自动关闭。
##
## 使用方式：
##   由 [TileSelector] 在框选完成时实例化并调用 [method show_menu]。
class_name TileContextMenu extends CanvasLayer

# ============================================================
# 1. 信号
# ============================================================

## 菜单项被选中。action 为 "plow"/"dig"/"plant"/"harvest" 或 "task_plow"/"task_plant"/"task_harvest"/"task_dig"。
## 派遣类 action 由本菜单内部直接生成 TaskData 分发，不再向上传递。
signal action_selected(action: String, tiles: Array)

## 菜单被取消（点遮罩或取消按钮）。
signal cancelled()

# ============================================================
# 3. 常量
# ============================================================

## 直接操作菜单项（立即执行，不走工人）。
const MENU_ITEMS: Array[Dictionary] = [
	{ "text": "翻耕", "action": "plow" },
	{ "text": "挖掘", "action": "dig" },
	{ "text": "种植", "action": "plant" },
	{ "text": "收获", "action": "harvest" },
]

## 派遣菜单项（生成 TaskData 分配给工人执行）。
const TASK_MENU_ITEMS: Array[Dictionary] = [
	{ "text": "派遣翻耕", "action": "task_plow" },
	{ "text": "派遣种植", "action": "task_plant" },
	{ "text": "派遣收获", "action": "task_harvest" },
	{ "text": "派遣挖掘", "action": "task_dig" },
]

const BUTTON_MIN_WIDTH: float = 200.0
const BUTTON_FONT_SIZE: int = 22
const PANEL_PADDING: int = 12

## 子菜单触发按钮的背景颜色（区别于普通按钮，标识其拥有子菜单）。
const SUBMENU_TRIGGER_BG: Color = Color(0.18, 0.28, 0.52, 0.9)
## 子菜单触发按钮的边框颜色。
const SUBMENU_TRIGGER_BORDER: Color = Color(0.35, 0.5, 0.75, 0.9)
## 子菜单面板的背景颜色。
const SUBMENU_PANEL_BG: Color = Color(0.1, 0.1, 0.14, 0.97)
## 子菜单面板的边框颜色。
const SUBMENU_PANEL_BORDER: Color = Color(0.3, 0.38, 0.6, 0.9)

# ============================================================
# 4. @export 变量
# ============================================================

## 是否显示 Debug 子菜单。
## [b]true[/b] 时所有操作项收入 "Debug" 二级菜单；[b]false[/b] 时直接平铺在主菜单中。
## 开发阶段可开启，正式玩法中关闭（地块指令由其他系统接管）。
@export var show_debug_menu: bool = true

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

# 子菜单系统
var _submenu_panel: Panel = null
## 所有子菜单触发按钮的引用（用于 hover 时切换子菜单）。
var _trigger_buttons: Array[Button] = []

# ============================================================
# 7. @onready 变量
# ============================================================

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	layer = 100001
	visible = false
	_build_ui()

# ============================================================
# 9. 公开方法
# ============================================================

## 在指定屏幕位置显示菜单。
func show_menu(screen_pos: Vector2, selected_tiles: Array) -> void:
	tiles = selected_tiles
	_title_label.text = "已选中 %d 个地块" % tiles.size()

	# 确保子菜单隐藏
	_hide_submenu()

	# 先粗略定位，等一帧让布局生效后再做边界修正
	_panel.position = screen_pos + Vector2(8, 8)
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	_adjust_menu_to_screen()

	visible = true

	# 自动展开第一个可用的二级菜单
	if show_debug_menu and _trigger_buttons.size() > 0:
		_show_submenu()

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

	if show_debug_menu:
		# Debug 子菜单触发按钮
		var debug_btn: Button = _create_submenu_trigger("Debug", vbox)
		_trigger_buttons.append(debug_btn)
		# 在 _blocker 上构建子菜单面板（独立定位）
		_build_submenu_panel()
	else:
		# 直接显示所有操作按钮（无子菜单模式）
		for item: Dictionary in MENU_ITEMS:
			var btn: Button = _create_action_button(item["text"], item["action"])
			vbox.add_child(btn)
		var sep2: HSeparator = HSeparator.new()
		vbox.add_child(sep2)
		for item: Dictionary in TASK_MENU_ITEMS:
			var btn: Button = _create_action_button(item["text"], item["action"])
			vbox.add_child(btn)

	# 分隔线
	var sep_last: HSeparator = HSeparator.new()
	vbox.add_child(sep_last)

	# 取消按钮 — 始终显示
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

## 创建带有子菜单的触发按钮，使用特殊颜色标识。
## 鼠标悬浮时自动展开子菜单。
func _create_submenu_trigger(text: String, parent: Control) -> Button:
	var btn: Button = Button.new()
	btn.name = "Btn_Submenu_" + text
	btn.text = "▶ " + text
	btn.custom_minimum_size.x = BUTTON_MIN_WIDTH
	btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)

	# 特殊样式 — 区别于普通按钮
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SUBMENU_TRIGGER_BG
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = SUBMENU_TRIGGER_BORDER
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style)

	var style_hover: StyleBoxFlat = style.duplicate()
	style_hover.bg_color = Color(
		SUBMENU_TRIGGER_BG.r + 0.06, SUBMENU_TRIGGER_BG.g + 0.06, SUBMENU_TRIGGER_BG.b + 0.08, 0.95
	)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.8, 0.8))

	btn.mouse_entered.connect(_on_submenu_trigger_entered)

	parent.add_child(btn)
	return btn

## 构建 Debug 子菜单面板。
## 作为 [member _blocker] 的直接子节点，可独立于主面板自由定位。
func _build_submenu_panel() -> void:
	_submenu_panel = Panel.new()
	_submenu_panel.name = "SubmenuPanel"
	_submenu_panel.visible = false
	_submenu_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "SubmenuVBox"
	vbox.add_theme_constant_override("separation", 4)
	_submenu_panel.add_child(vbox)

	# 即时操作
	for item: Dictionary in MENU_ITEMS:
		var btn: Button = _create_action_button(item["text"], item["action"])
		vbox.add_child(btn)

	# 分隔线
	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	# 派遣操作
	for item: Dictionary in TASK_MENU_ITEMS:
		var btn: Button = _create_action_button(item["text"], item["action"])
		vbox.add_child(btn)

	_submenu_panel.add_theme_stylebox_override("panel", _make_submenu_stylebox())

	_blocker.add_child(_submenu_panel)

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

func _make_submenu_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = SUBMENU_PANEL_BG
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = SUBMENU_PANEL_BORDER
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
# 10. 私有方法 — 子菜单显示与定位
# ============================================================

## 鼠标进入任意子菜单触发按钮。
## 显示该触发按钮对应的子菜单。如果有其他子菜单已打开则先关闭。
func _on_submenu_trigger_entered() -> void:
	_show_submenu()

## 显示子菜单。
func _show_submenu() -> void:
	if _submenu_panel == null:
		return
	_submenu_panel.visible = true
	_position_submenu()

## 隐藏子菜单。
func _hide_submenu() -> void:
	if _submenu_panel != null:
		_submenu_panel.visible = false

## 定位子菜单，确保不超出屏幕边界。
## 默认紧贴主面板右侧，顶部对齐。
## - 若子菜单底部超出屏幕 → 向上移动直到底部贴合窗口下沿。
## - 若子菜单右侧超出屏幕 → 向左移动整个主菜单；若仍超出则子菜单移至主面板左侧。
func _position_submenu() -> void:
	if _submenu_panel == null or not _submenu_panel.visible:
		return

	# 让子菜单根据内容确定自身尺寸
	_submenu_panel.size = Vector2.ZERO
	var vbox: VBoxContainer = _submenu_panel.get_child(0) as VBoxContainer
	if vbox:
		var min_size: Vector2 = vbox.get_combined_minimum_size()
		var style: StyleBox = _submenu_panel.get_theme_stylebox("panel", "Panel")
		var pad: Vector2 = Vector2.ZERO
		if style:
			pad = style.get_minimum_size()
		_submenu_panel.size = min_size + pad

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var submenu_size: Vector2 = _submenu_panel.size
	var panel_pos: Vector2 = _panel.position
	var panel_size: Vector2 = _panel.size

	# 默认：子菜单紧贴主面板右侧，顶部对齐
	var submenu_pos: Vector2 = panel_pos + Vector2(panel_size.x, 0)
	var total_right: float = submenu_pos.x + submenu_size.x

	# 右侧超出 → 尝试向左移动整个菜单
	if total_right > viewport_size.x:
		var overflow: float = total_right - viewport_size.x
		var new_panel_x: float = panel_pos.x - overflow
		if new_panel_x < 0:
			new_panel_x = 0
		_panel.position.x = new_panel_x
		# 重新计算子菜单位置
		submenu_pos.x = _panel.position.x + panel_size.x
		total_right = submenu_pos.x + submenu_size.x
		# 如果移到底仍超出 → 子菜单放在主面板左侧
		if total_right > viewport_size.x:
			submenu_pos.x = _panel.position.x - submenu_size.x
			if submenu_pos.x < 0:
				submenu_pos.x = 0

	# 底部超出 → 向上移动
	if submenu_pos.y + submenu_size.y > viewport_size.y:
		submenu_pos.y = viewport_size.y - submenu_size.y

	# 顶部超出 → 贴顶
	if submenu_pos.y < 0:
		submenu_pos.y = 0

	_submenu_panel.position = submenu_pos

# ============================================================
# 10. 私有方法 — 菜单位置调整
# ============================================================

## 调整主菜单面板位置，使其完全在屏幕内显示。
func _adjust_menu_to_screen() -> void:
	# 让面板根据内容确定尺寸
	_panel.size = Vector2.ZERO
	var vbox: VBoxContainer = _panel.get_child(0) as VBoxContainer
	if vbox:
		var min_size: Vector2 = vbox.get_combined_minimum_size()
		var style: StyleBox = _panel.get_theme_stylebox("panel", "Panel")
		var pad: Vector2 = Vector2.ZERO
		if style:
			pad = style.get_minimum_size()
		_panel.size = min_size + pad

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = _panel.size
	var pos: Vector2 = _panel.position

	# 底部超出 → 向上移动
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = viewport_size.y - panel_size.y
		if pos.y < 0:
			pos.y = 0

	# 右侧超出 → 向左移动
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = viewport_size.x - panel_size.x
		if pos.x < 0:
			pos.x = 0

	_panel.position = pos

# ============================================================
# 10. 私有方法 — 事件
# ============================================================

func _on_action(action: String) -> void:
	if action.begins_with("task_"):
		# 派遣类操作：为每个地块生成独立 TaskData，通过 UnitManager 分发给工人
		_dispatch_tasks(action, tiles)
	else:
		# 即时操作：向上层发出信号（由 TileSelector → EventBus → TerrainGenerator 处理）
		action_selected.emit(action, tiles)
	queue_free()

func _on_cancel() -> void:
	cancelled.emit()
	queue_free()

func _on_blocker_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		cancelled.emit()
		queue_free()

# ============================================================
# 10. 私有方法 — 派遣任务
# ============================================================

## 将菜单中的派遣 action 转换为 TaskData 并分发给工人。
## 每个地块生成一个独立的任务（无父子关系），批量提交到 [UnitManager]。
func _dispatch_tasks(action: String, selected_tiles: Array) -> void:
	var task_type: int = _action_to_task_type(action)
	if task_type == -1:
		push_warning("TileContextMenu: 未知的派遣操作 '%s'" % action)
		return

	var tasks: Array[TaskData] = []
	for tile: Vector2i in selected_tiles:
		var params: Dictionary = {}
		if task_type == TaskData.TaskType.PLANT:
			# 默认种植小麦，后续可从 UI 选择作物品种
			params["crop_id"] = "wheat_tier1"
		var task: TaskData = TaskData.create(task_type, tile, params)
		tasks.append(task)

	if tasks.is_empty():
		return

	var assigned: int = UnitManager.distribute_tasks(tasks)
	print("TileContextMenu: 生成 %d 个派遣任务（%s），成功分配 %d 个，%d 个进入待分配池" % [
		tasks.size(), action, assigned, tasks.size() - assigned
	])

## 将菜单 action 字符串映射到 [enum TaskData.TaskType] 枚举值。
## 返回 -1 表示未知 action。
func _action_to_task_type(action: String) -> int:
	match action:
		"task_plow":
			return TaskData.TaskType.PLOW
		"task_plant":
			return TaskData.TaskType.PLANT
		"task_harvest":
			return TaskData.TaskType.HARVEST
		"task_dig":
			return TaskData.TaskType.DIG
		_:
			return -1
