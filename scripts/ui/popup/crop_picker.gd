## 作物选择器弹出 UI。
##
## 在种植模式（PLANT_FAMILY）下，玩家框选地块后弹出本面板，
## 列出指定植物科下所有已解锁作物，供玩家点击选择。
##
## 作物数据从 [code]config/crops/[/code] 目录加载并缓存在内存中，
## 后续 [method show_for_family] 仅做内存筛选，避免重复磁盘 IO。
##
## 使用方式：
##   var picker: CropPicker = CROP_PICKER_SCENE.instantiate()
##   add_child(picker)
##   picker.crop_selected.connect(_on_crop_selected)
##   picker.show_for_family("poaceae")
class_name CropPicker extends CanvasLayer

# ============================================================
# 1. 信号
# ============================================================

## 玩家选中了作物。
signal crop_selected(crop_id: String)

## 玩家取消选择（点击取消按钮或点击遮罩）。
signal picker_cancelled()

# ============================================================
# 3. 常量
# ============================================================

const CROPS_CONFIG_DIR: String = "res://config/crops/"
const TextureLoader = preload("res://scripts/utils/texture_loader.gd")

# ============================================================
# 5. 公开变量
# ============================================================

## 作物数据内存缓存。
## 结构：[{crop_id, crop_name, plant_family, tier, description, scene_path, unlocked, ...}, ...]
var all_crops: Array[Dictionary] = []

# ============================================================
# 6. 私有变量
# ============================================================

var _blocker: ColorRect = null
var _panel: Panel = null
var _title_label: Label = null
var _crop_list: VBoxContainer = null
var _cached_crops: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 最高层 UI 遮罩，置于 TileContextMenu（100001）之上
	layer = 100002
	_build_ui()
	_load_all_crops()
	visible = false

# ============================================================
# 9. 公开方法
# ============================================================

## 显示指定植物科的作物选择器。
##
## 从 [member all_crops] 中筛选已解锁且匹配 [param family_id] 的作物。
## 无可用作物时自动发出 [signal picker_cancelled] 并释放。
func show_for_family(family_id: String) -> void:
	var crops: Array[Dictionary] = []
	for data: Dictionary in all_crops:
		if data.get("plant_family", "").to_lower() == family_id.to_lower():
			if data.get("unlocked", false):
				crops.append(data)

	if crops.is_empty():
		print("CropPicker: 植物科 '%s' 下无可用作物" % family_id)
		picker_cancelled.emit()
		queue_free()
		return

	_title_label.text = "选择作物 — %s" % family_id
	_populate_list(crops)
	_adjust_position()
	visible = true

## 设置指定作物的解锁状态。
## 供科技树等外部系统调用，控制玩家可选作物范围。
func set_crop_unlocked(crop_id: String, unlocked: bool) -> void:
	for data: Dictionary in all_crops:
		if data.get("crop_id", "") == crop_id:
			data["unlocked"] = unlocked
			return

# ============================================================
# 10. 私有方法 — 数据加载
# ============================================================

## 在节点就绪时一次性扫描 config/crops/ 目录，加载全部作物数据。
func _load_all_crops() -> void:
	if _cached_crops:
		return

	var dir: DirAccess = DirAccess.open(CROPS_CONFIG_DIR)
	if dir == null:
		push_error("CropPicker: 无法打开作物配置目录: %s" % CROPS_CONFIG_DIR)
		_cached_crops = true
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if file_name.ends_with(".json") and not dir.current_is_dir():
			var data: Dictionary = _load_crop_json(CROPS_CONFIG_DIR + file_name)
			if not data.is_empty():
				# 默认已解锁（后续可通过 set_crop_unlocked 控制）
				if not data.has("unlocked"):
					data["unlocked"] = true
				all_crops.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()
	_cached_crops = true

## 加载单个作物 JSON 文件，返回解析后的字典。失败返回空字典。
func _load_crop_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("CropPicker: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return {}

	var data: Variant = json.data
	if data is Dictionary:
		return data as Dictionary
	return {}

# ============================================================
# 10. 私有方法 — UI 构建
# ============================================================

## 构建 UI 树：Blocker → Panel → VBoxContainer → (标题 + 列表 + 取消按钮)。
func _build_ui() -> void:
	# 全屏透明遮罩（阻止穿透点击）
	_blocker = ColorRect.new()
	_blocker.name = "Blocker"
	_blocker.color = Color(0.0, 0.0, 0.0, 0.3)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blocker.gui_input.connect(_on_blocker_gui_input)
	add_child(_blocker)

	# 面板
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.size = Vector2(360, 480)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	# 面板样式
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.4, 0.5, 0.8)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", panel_style)

	# 垂直布局容器
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 20)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	vbox.add_child(_title_label)

	# 分隔线
	var sep1: HSeparator = HSeparator.new()
	vbox.add_child(sep1)

	# 作物列表（可滚动）
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_crop_list = VBoxContainer.new()
	_crop_list.name = "CropList"
	_crop_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_crop_list)

	# 分隔线
	var sep2: HSeparator = HSeparator.new()
	vbox.add_child(sep2)

	# 取消按钮
	var cancel_btn: Button = Button.new()
	cancel_btn.name = "CancelBtn"
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.custom_minimum_size = Vector2(0, 40)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	vbox.add_child(cancel_btn)

## 清空列表并重新填充作物按钮。
func _populate_list(crops: Array[Dictionary]) -> void:
	# 清空旧按钮
	for child: Node in _crop_list.get_children():
		child.queue_free()

	for data: Dictionary in crops:
		var btn: Button = _create_crop_button(data)
		_crop_list.add_child(btn)

## 创建单个作物按钮：图标 + 名称 + 描述。
func _create_crop_button(data: Dictionary) -> Button:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(0, 56)
	btn.add_theme_font_size_override("font_size", 14)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	btn.add_child(hbox)

	# 图标（从作物配置的 icon 字段加载纹理，失败时自动使用棋盘格占位符）
	var icon: TextureRect = TextureRect.new()
	icon.name = "IconRect"
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_path: String = data.get("icon", "")
	icon.texture = TextureLoader.load_texture(icon_path, 48)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(icon)

	# 文字区域
	var text_vbox: VBoxContainer = VBoxContainer.new()
	hbox.add_child(text_vbox)

	var name_label: Label = Label.new()
	name_label.name = "NameLabel"
	name_label.text = data.get("crop_name", data.get("crop_id", "???"))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	text_vbox.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.name = "DescLabel"
	var desc: String = data.get("description", "")
	if desc.length() > 0:
		desc_label.text = desc
	else:
		desc_label.text = "Tier %d" % data.get("tier", 1)
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	text_vbox.add_child(desc_label)

	# 连接点击信号
	var crop_id: String = data.get("crop_id", "")
	btn.pressed.connect(_on_crop_button_pressed.bind(crop_id))

	return btn

## 调整面板位置到屏幕中央。
func _adjust_position() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = (vs - _panel.size) * 0.5

# ============================================================
# 10. 私有方法 — 信号回调
# ============================================================

func _on_crop_button_pressed(crop_id: String) -> void:
	crop_selected.emit(crop_id)
	queue_free()

func _on_cancel_pressed() -> void:
	picker_cancelled.emit()
	queue_free()

func _on_blocker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			picker_cancelled.emit()
			queue_free()
