## 地块操作上下文菜单。
##
## 在地块框选完成后弹出，提供操作选项（翻耕、挖掘、种植、收获、取消）以及
## 派遣选项（派遣翻耕/种植/收获/挖掘），后者将任务分配给工作单位执行。
## 使用全屏透明遮罩阻断世界交互，避免点击空地触发新选择。
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

	# 即时操作按钮
	for item: Dictionary in MENU_ITEMS:
		var btn: Button = _create_action_button(item["text"], item["action"])
		vbox.add_child(btn)

	# 分隔线
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	# 派遣操作按钮（任务驱动）
	for item: Dictionary in TASK_MENU_ITEMS:
		var btn: Button = _create_action_button(item["text"], item["action"])
		vbox.add_child(btn)

	# 分隔线
	var sep3: HSeparator = HSeparator.new()
	vbox.add_child(sep3)

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
