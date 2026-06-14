## 模式选择器 — HUD 顶部的核心指令模式切换组件。
##
## 管理多个模式方框，每个方框包含背景贴图、图标和键位提示。玩家通过键盘顶行按键
## （[code]1[/code]~[code]=[/code]）或鼠标点击来选择当前操作模式。
##
## 默认包含"光标模式"和"采集"两种模式；每解锁一科作物，自动追加新模式方框。
## 支持运行时动态增删方框（[method add_mode] / [method remove_mode]）、
## 锁定/解锁（[method lock_mode] / [method unlock_mode]）、查询当前状态
## （[method get_current_mode] / [method get_selected_index] / [method get_mode_count]）。
##
## 使用方式：
##   - 挂载在 [HFlowContainer] 场景上（[code]mode_selector.tscn[/code]）
##   - 放在 HUD 的顶部居中位置
##   - 通过 [signal mode_selected] 或 [signal EventBus.mode_changed] 通知其他系统
class_name ModeSelector extends HFlowContainer

# ============================================================
# 1. 信号
# ============================================================

## 玩家选择了一个模式（按键或点击）。
signal mode_selected(mode_id: StringName)

# ============================================================
# 3. 常量
# ============================================================

const CONFIG_PATH: String = "res://config/ui/mode_definitions.json"
const SELECT_SOUND: AudioStream = preload("res://resources/sound/选中.ogg")
const StringToKey = preload("res://scripts/utils/string_to_key.gd")

# ============================================================
# 4. @export 变量
# ============================================================

## 单个方框的像素尺寸（宽高相同）。
@export var slot_size: int = 120

## 方框内图标的像素尺寸。
@export var icon_size: int = 96

## 方框之间的像素间距。
@export var spacing: int = 0

## 鼠标悬停时的图标缩放倍数。
@export var hover_scale: float = 1.2

## 选中时的图标缩放倍数。
@export var selected_scale: float = 1.35

## 缩放动画持续时间（秒）。
@export var scale_duration: float = 0.15

## 键位标签的字体大小。
@export var key_label_font_size: int = 14

## 未解锁方框的不透明度（应用于图标和标签）。
@export var locked_alpha: float = 0.4

# ============================================================
# 6. 私有变量
# ============================================================

## 模式定义数组 [{id, name, icon_path, tooltip}, ...]。
var _modes: Array[Dictionary] = []

## 当前选中模式的索引（默认 0 = 光标模式）。
var _selected_index: int = 0

## 所有方框 Control 节点的引用数组。
var _slots: Array[Control] = []

## 每个方框对应的 Godot 按键枚举值数组。
var _slot_keys: Array[Key] = []

## 当前鼠标悬停的方框索引（-1 表示无）。
var _hovered_index: int = -1

## 作物科图标映射表 {family_id: {id, icon_path}}，从配置 [code]plant_icons[/code] 加载。
var _plant_icons: Dictionary = {}

## 方框背景纹理（从配置 [code]slot_background[/code] 路径加载）。
var _slot_bg_texture: Texture2D = null

## 初始化完成标志。用于抑制首次选中音效。
var _initialized: bool = false

# ============================================================
# 7. @onready 变量
# ============================================================

@onready var _audio_player: AudioStreamPlayer = $AudioStreamPlayer

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 必须启用 _input() 以处理键盘事件（Control 默认不调用 _input）
	set_process_input(true)
	# 连接自身 gui_input：拦截 slot 间隙的鼠标事件，防止穿透到游戏世界
	self.gui_input.connect(_on_self_gui_input)
	# 定位：屏幕上沿居中，占据左 1/4 到右 1/4（中间 50% 宽度）
	# CanvasLayer 下 anchor 高度计算不可靠，使用 offset 手动定位
	var vs: Vector2 = get_viewport().get_visible_rect().size
	offset_left = vs.x * 0.25
	offset_top = 4.0
	offset_right = vs.x * 0.75
	offset_bottom = 4.0 + float(slot_size)
	_setup_container()
	_load_config()
	_populate_slots()

## 处理键盘事件，用于模式切换快捷键（1~=）。
## 注意：键盘事件不会经过 GUI 系统，所以必须通过 _input 处理。
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed:
			_select_by_key(key_event.keycode, key_event)


# ============================================================
# 9. 公开方法
# ============================================================

## 获取当前选中的模式 ID。
func get_current_mode() -> StringName:
	if _modes.size() > 0 and _selected_index >= 0 and _selected_index < _modes.size():
		return _modes[_selected_index].get("id", &"cursor") as StringName
	return &"cursor"

## 通过模式 ID 选择模式。
##
## [param id] 模式标识（如 "cursor"、"gather"、"wheat_tier1"）。
## 如果找不到匹配的模式，不做任何操作。
func select_mode_by_id(id: StringName) -> void:
	for i: int in range(_modes.size()):
		if _modes[i].get("id", "") == id:
			_select_slot(i)
			return

## 通过按键选择模式。
##
## [param keycode] Godot 按键枚举值。
## 如果按键不匹配任何方框，不做任何操作。
func select_mode_by_key(keycode: Key) -> void:
	var index: int = _slot_keys.find(keycode)
	if index >= 0 and index < _slots.size():
		_select_slot(index)

## 切换到光标模式。
func select_cursor_mode() -> void:
	_select_slot(0)

## 添加一个新模式（游戏过程中解锁作物时调用）。
##
## [param id] 唯一模式标识。
## [param mode_name] 显示名称（暂用于 tooltip）。
## [param icon] 图标纹理（已由调用方加载）。
## [param tooltip] 悬浮提示文本。
## [param locked] 是否初始锁定。
##
## 返回添加后的方框索引，如果超出最大槽位数则返回 -1。
func add_mode(id: StringName, mode_name: String, icon: Texture2D, tooltip: String = "", locked: bool = false) -> int:
	if _modes.size() >= _slot_keys.size():
		push_warning("ModeSelector: 已达到最大模式数量 (%d)，无法添加 '%s'" % [_slot_keys.size(), id])
		return -1

	var mode_dict: Dictionary = {
		"id": id,
		"name": mode_name,
		"icon_texture": icon,
		"tooltip": tooltip,
		"locked": locked,
	}
	_modes.append(mode_dict)
	var index: int = _slots.size()
	var slot: Control = _create_slot(mode_dict, index)
	_slots.append(slot)
	add_child(slot)

	if locked:
		_set_slot_locked(slot, true)

	return index

## 根据作物科 ID 从配置添加新模式（便捷方法）。
##
## 从 [member _plant_icons] 中查找 [param family_id] 对应的图标路径，
## 加载纹理后调用 [method add_mode]。
##
## 返回添加后的方框索引，如果超出最大槽位数或找不到配置则返回 -1。
func add_mode_for_family(family_id: String) -> int:
	if not _plant_icons.has(family_id):
		print("ModeSelector: 未找到作物科 '%s' 的图标配置" % family_id)
		return -1
	var info: Dictionary = _plant_icons[family_id] as Dictionary
	var icon_path: String = info.get("icon", "")
	var icon: Texture2D = _load_icon_texture(icon_path)
	return add_mode(family_id.to_lower() as StringName, family_id, icon, "")

## 解锁指定模式的方框。
func unlock_mode(id: StringName) -> void:
	for i: int in range(_modes.size()):
		if _modes[i].get("id", "") == id:
			_modes[i]["locked"] = false
			if i < _slots.size():
				_set_slot_locked(_slots[i], false)
			return

## 锁定指定模式的方框（灰显且不可交互）。
func lock_mode(id: StringName) -> void:
	for i: int in range(_modes.size()):
		if _modes[i].get("id", "") == id:
			_modes[i]["locked"] = true
			if i < _slots.size():
				_set_slot_locked(_slots[i], true)
			# 如果当前选中的恰是被锁定的模式，自动切回光标模式
			if i == _selected_index:
				_select_slot(0)
			return

## 移除一个模式。
##
## [param id] 模式标识。不能移除最后一个模式（至少保留一个）。
##
## 返回 [code]true[/code] 表示移除成功，[code]false[/code] 表示未找到或无法移除。
func remove_mode(id: StringName) -> bool:
	var index: int = -1
	for i: int in range(_modes.size()):
		if _modes[i].get("id", "") == id:
			index = i
			break

	if index < 0:
		push_warning("ModeSelector: 未找到模式 '%s'，无法移除" % id)
		return false

	if _modes.size() <= 1:
		push_warning("ModeSelector: 至少保留一个模式，无法移除 '%s'" % id)
		return false

	# 清理 slot 节点
	var slot: Control = _slots[index]
	slot.queue_free()
	_slots.remove_at(index)
	_modes.remove_at(index)

	# 重新索引后续 slot（名称、元数据、信号绑定）
	for i: int in range(index, _slots.size()):
		_reindex_slot(i)

	# 记录移除前选中是否恰是待移除的模式
	var was_selected: bool = (_selected_index == index)

	# 如移除的恰是当前选中，切换到相邻可用模式
	if _selected_index > index:
		_selected_index -= 1
	elif _selected_index == index:
		_selected_index = clampi(_selected_index, 0, _slots.size() - 1)
	else:
		pass  # _selected_index < index，无需调整

	# 更新新选中方框的视觉状态
	_animate_slot_scale(_selected_index, _get_target_scale(_selected_index))

	# 仅当移除的恰是当前选中模式时发出信号（索引偏移不算模式变更）
	if was_selected:
		var new_mode_id: StringName = get_current_mode()
		mode_selected.emit(new_mode_id)
		if EventBus:
			EventBus.mode_changed.emit(new_mode_id)

	return true

## 获取当前选中模式的索引。
func get_selected_index() -> int:
	return _selected_index

## 获取当前模式总数。
func get_mode_count() -> int:
	return _modes.size()

## 检查指定模式是否存在。
func has_mode(id: StringName) -> bool:
	for mode: Dictionary in _modes:
		if mode.get("id", "") == id:
			return true
	return false

# ============================================================
# 10. 私有方法 — 初始化
# ============================================================

## 设置 HFlowContainer 的布局参数。
func _setup_container() -> void:
	add_theme_constant_override("h_separation", spacing)
	add_theme_constant_override("v_separation", spacing)
	alignment = HFlowContainer.ALIGNMENT_CENTER

## 加载并解析 JSON 配置文件。
func _load_config() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		push_error("ModeSelector: 配置文件不存在: %s" % CONFIG_PATH)
		_fallback_defaults()
		return

	var file: FileAccess = FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("ModeSelector: 无法打开配置文件: %s" % CONFIG_PATH)
		_fallback_defaults()
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("ModeSelector: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		_fallback_defaults()
		return

	var data: Variant = json.data
	if not data is Dictionary:
		push_error("ModeSelector: 配置文件顶层应为 JSON 对象")
		_fallback_defaults()
		return

	var config: Dictionary = data as Dictionary

	# 读取方框尺寸（可被 @export 覆盖）
	if config.has("slot_size"):
		slot_size = int(config["slot_size"])
	if config.has("icon_size"):
		icon_size = int(config["icon_size"])
	if config.has("spacing"):
		spacing = int(config["spacing"])
	if config.has("hover_scale"):
		hover_scale = float(config["hover_scale"])
	if config.has("selected_scale"):
		selected_scale = float(config["selected_scale"])
	if config.has("scale_duration"):
		scale_duration = float(config["scale_duration"])
	if config.has("font_size"):
		key_label_font_size = int(config["font_size"])

	# 读取方框背景纹理
	if config.has("slot_background"):
		var bg_path: String = config["slot_background"] as String
		if not bg_path.is_empty() and ResourceLoader.exists(bg_path):
			var bg_res: Resource = load(bg_path)
			if bg_res is Texture2D:
				_slot_bg_texture = bg_res as Texture2D

	# 读取作物科图标映射
	if config.has("plant_icons"):
		var plants: Array = config["plant_icons"] as Array
		for entry: Variant in plants:
			if entry is Dictionary:
				var d: Dictionary = entry as Dictionary
				var fid: String = d.get("id", "")
				if not fid.is_empty():
					_plant_icons[fid] = d

	# 读取默认模式定义
	if config.has("default_modes"):
		var defaults: Array = config["default_modes"] as Array
		for entry: Variant in defaults:
			if entry is Dictionary:
				var d: Dictionary = entry as Dictionary
				_modes.append({
					"id": d.get("id", ""),
					"name": d.get("name", ""),
					"icon_path": d.get("icon", ""),
					"tooltip": d.get("tooltip", ""),
					"locked": false,
				})

	# 读取槽位按键映射
	if config.has("slot_keys"):
		var keys: Array = config["slot_keys"] as Array
		for key_str: Variant in keys:
			if key_str is String:
				var k: Key = StringToKey._string_to_key(key_str as String)
				_slot_keys.append(k)
	else:
		_default_slot_keys()

	# 更新间距
	add_theme_constant_override("h_separation", spacing)
	add_theme_constant_override("v_separation", spacing)

## 配置加载失败时的回退：硬编码基础模式。
func _fallback_defaults() -> void:
	_modes = [
		{ "id": "cursor", "name": "光标", "icon_path": "", "tooltip": "选择对象和地块", "locked": false },
		{ "id": "gather", "name": "采集", "icon_path": "", "tooltip": "挖掘、砍树等采集操作", "locked": false },
	]
	_default_slot_keys()

## 使用默认槽位按键（键盘顶行 1~=）。
func _default_slot_keys() -> void:
	_slot_keys = [
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6,
		KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUAL,
	]

## 根据模式定义填充所有方框。
func _populate_slots() -> void:
	for i: int in range(_modes.size()):
		var slot: Control = _create_slot(_modes[i], i)
		_slots.append(slot)
		add_child(slot)

	if _modes.size() > 0:
		_select_slot(0)
	_initialized = true

# ============================================================
# 10. 私有方法 — 方框创建
# ============================================================

## 根据模式定义创建一个方框 Control。
##
## 方框由三层组成（从底到顶）：
##   1. 背景 [TextureRect] — 120×120 全尺寸背景贴图
##   2. 图标 [TextureRect] — 居中，由配置指定尺寸
##   3. 键位标签 [Label] — 右下角，纯文本无独立背景
func _create_slot(mode: Dictionary, index: int) -> Control:
	var slot: Control = Control.new()
	slot.name = "Slot_top%d" % index
	slot.custom_minimum_size = Vector2(float(slot_size), float(slot_size))
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	# 1. 背景贴图（底层）
	var bg: TextureRect = _create_background()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(bg)
	slot.set_meta("bg_rect", bg)

	# 2. 图标（中层）
	var icon: TextureRect = _create_icon(mode)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	slot.set_meta("icon_rect", icon)

	# 3. 键位标签（顶层）
	var key_label: Label = _create_key_label(index)
	key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key_label)
	slot.set_meta("key_label", key_label)

	# 元数据
	slot.set_meta("mode_id", mode.get("id", ""))
	slot.set_meta("index", index)

	# 连接交互信号
	slot.gui_input.connect(_on_slot_gui_input.bind(index))
	slot.mouse_entered.connect(_on_slot_mouse_entered.bind(index))
	slot.mouse_exited.connect(_on_slot_mouse_exited.bind(index))

	return slot

## 创建方框背景 TextureRect（全尺寸，置于底层）。
func _create_background() -> TextureRect:
	var bg: TextureRect = TextureRect.new()
	bg.name = "Background"
	bg.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.custom_minimum_size = Vector2(float(slot_size), float(slot_size))
	bg.size = Vector2(float(slot_size), float(slot_size))
	bg.position = Vector2.ZERO
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if _slot_bg_texture:
		bg.texture = _slot_bg_texture

	return bg

## 创建图标 TextureRect（居中于方框内）。
func _create_icon(mode: Dictionary) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.name = "Icon"

	# 加载纹理：优先使用预加载好的纹理（来自 add_mode 参数），其次尝试文件路径
	var texture: Texture2D = null
	if mode.has("icon_texture") and mode["icon_texture"] is Texture2D:
		print("ModeSelector: 使用预加载图标纹理 for mode '%s'" % mode.get("id", ""))
		texture = mode["icon_texture"] as Texture2D
	else:
		texture = _load_icon_texture(mode.get("icon_path", ""))
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 位置：居中于方框内
	var icon_offset: float = float(slot_size - icon_size) * 0.5
	icon.position = Vector2(icon_offset, icon_offset)
	icon.custom_minimum_size = Vector2(float(icon_size), float(icon_size))
	icon.size = Vector2(float(icon_size), float(icon_size))

	# 设置缩放中心点
	icon.pivot_offset = Vector2(float(icon_size) * 0.5, float(icon_size) * 0.5)

	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return icon

## 创建键位标签（右下角，半透明深色底 + 白色文字，确保在任何背景下可读）。
func _create_key_label(index: int) -> Label:
	var label: Label = Label.new()
	label.name = "KeyLabel"

	if index < _slot_keys.size():
		var keycode: Key = _slot_keys[index]
		label.text = OS.get_keycode_string(keycode)
	else:
		label.text = "?"

	label.add_theme_font_size_override("font_size", key_label_font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 半透明深色背景确保对比度
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	label.add_theme_stylebox_override("normal", style)

	# 估算尺寸（单字符 14px + 内容边距），Label 入树后会自动调整
	var est_w: float = 24.0
	var est_h: float = 20.0
	label.custom_minimum_size = Vector2(est_w, est_h)
	# 位置：右下角，距边缘 4px
	label.position = Vector2(float(slot_size) - est_w - 4.0, float(slot_size) - est_h - 4.0)

	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return label

## 加载图标纹理；失败时生成纯色占位符。
func _load_icon_texture(path: String) -> Texture2D:
	if not path.is_empty() and ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			print("ModeSelector: 成功加载图标纹理: %s" % path)
			return res as Texture2D

	# 生成占位符纹理
	print("ModeSelector: 无法加载图标纹理 '%s'，使用占位符" % path)
	return _create_placeholder_texture()

## 生成一个纯色占位纹理（棋盘格风格，便于识别缺失资源）。
func _create_placeholder_texture() -> Texture2D:
	var img: Image = Image.create(icon_size, icon_size, false, Image.FORMAT_RGBA8)
	var cell_size: int = maxi(icon_size / 4, 1)
	for y: int in range(icon_size):
		var row_checker: bool = (y / cell_size) % 2 == 0
		for x: int in range(icon_size):
			var col_checker: bool = (x / cell_size) % 2 == 0
			var is_checker: bool = row_checker == col_checker
			var c: Color = Color(0.3, 0.3, 0.4, 1.0) if is_checker else Color(0.4, 0.4, 0.5, 1.0)
			img.set_pixel(x, y, c)

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	return tex as Texture2D

# ============================================================
# 10. 私有方法 — 交互处理
# ============================================================

## 处理 ModeSelector 自身区域的鼠标输入（slot 之间的空白间隙）。
## 接受所有鼠标按键事件，防止点击穿透到游戏世界。（暂时不需要，非slot内的空白部分应当可以穿透）
func _on_self_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# print("ModeSelector: 收到自身 GUI 输入事件，拦截: %s" % event)
		# accept_event()
		pass

## 处理方框上的鼠标输入。
func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	# print("ModeSelector: 方框 %d 收到 GUI 输入事件: %s" % [index, event])
	if not event is InputEventMouseButton:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	print("ModeSelector: 方框 %d 收到鼠标事件: button=%d, pressed=%s" % [index, mb.button_index, mb.pressed])
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_select_slot(index)
		accept_event()

## 鼠标进入方框。
func _on_slot_mouse_entered(index: int) -> void:
	_hovered_index = index
	_animate_slot_scale(index, _get_target_scale(index))

## 鼠标离开方框。
func _on_slot_mouse_exited(index: int) -> void:
	if _hovered_index == index:
		_hovered_index = -1
	_animate_slot_scale(index, _get_target_scale(index))

## 通过键盘按键选择模式。
func _select_by_key(keycode: Key, _event: InputEventKey) -> void:
	var index: int = _slot_keys.find(keycode)
	if index < 0 or index >= _slots.size():
		return
	# 检查是否被锁定
	if index < _modes.size() and _modes[index].get("locked", false):
		return
	_select_slot(index)
	get_viewport().set_input_as_handled()

## 选中指定索引的方框。
func _select_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	if index < _modes.size() and _modes[index].get("locked", false):
		return

	var old_index: int = _selected_index
	_selected_index = index

	# 动画：旧选中缩回 → 新选中放大
	if old_index >= 0 and old_index < _slots.size():
		_animate_slot_scale(old_index, _get_target_scale(old_index))
	_animate_slot_scale(index, _get_target_scale(index))

	# 初始化阶段跳过音效和信号（首次 _populate_slots 时自动选中光标模式）
	if not _initialized:
		return

	# 播放音效
	_play_select_sound()

	print("ModeSelector: 选中模式 '%s' (索引 %d)" % [_modes[index].get("id", ""), index])
	# 发送信号
	var mode_id: StringName = get_current_mode()
	mode_selected.emit(mode_id)
	if EventBus:
		EventBus.mode_changed.emit(mode_id)

# ============================================================
# 10. 私有方法 — 动画与效果
# ============================================================

## 获取指定索引方框的目标缩放。
func _get_target_scale(index: int) -> float:
	if index == _selected_index:
		return selected_scale
	if index == _hovered_index:
		return hover_scale
	return 1.0

## 使用 Tween 动画缩放指定方框的图标。
func _animate_slot_scale(index: int, target: float) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	var icon: TextureRect = slot.get_meta("icon_rect") as TextureRect
	if icon == null:
		return

	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(icon, "scale", Vector2(target, target), scale_duration)

# ============================================================
# 10. 私有方法 — 状态
# ============================================================

## 设置方框的锁定状态。
func _set_slot_locked(slot: Control, locked: bool) -> void:
	var bg: TextureRect = slot.get_meta("bg_rect") as TextureRect
	var icon: TextureRect = slot.get_meta("icon_rect") as TextureRect
	var key_label: Label = slot.get_meta("key_label") as Label

	if locked:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if bg:
			bg.modulate.a = locked_alpha
		if icon:
			icon.modulate.a = locked_alpha
		if key_label:
			key_label.modulate.a = locked_alpha
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		if bg:
			bg.modulate.a = 1.0
		if icon:
			icon.modulate.a = 1.0
		if key_label:
			key_label.modulate.a = 1.0

## 重新设置指定索引方框的名称、元数据与信号绑定。
## 在 [method remove_mode] 移除方框后调用，确保后续方框索引正确。
func _reindex_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot: Control = _slots[index]
	slot.name = "Slot_top%d" % index
	slot.set_meta("index", index)
	slot.set_meta("mode_id", _modes[index].get("id", ""))

	# 断开旧信号再重新以新 index 绑定
	if slot.gui_input.is_connected(_on_slot_gui_input):
		slot.gui_input.disconnect(_on_slot_gui_input)
	if slot.mouse_entered.is_connected(_on_slot_mouse_entered):
		slot.mouse_entered.disconnect(_on_slot_mouse_entered)
	if slot.mouse_exited.is_connected(_on_slot_mouse_exited):
		slot.mouse_exited.disconnect(_on_slot_mouse_exited)

	slot.gui_input.connect(_on_slot_gui_input.bind(index))
	slot.mouse_entered.connect(_on_slot_mouse_entered.bind(index))
	slot.mouse_exited.connect(_on_slot_mouse_exited.bind(index))

# ============================================================
# 10. 私有方法 — 音效
# ============================================================

func _play_select_sound() -> void:
	if _audio_player == null:
		return
	_audio_player.stream = SELECT_SOUND
	_audio_player.play()
