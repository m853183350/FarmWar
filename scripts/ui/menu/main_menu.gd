## 主菜单场景。
##
## 游戏启动后加载的第一个场景。提供通向所有局外系统的导航：
## 开始游戏、加载游戏、成就、设置、退出游戏。
##
## 使用 [method get_tree().change_scene_to_file] 切换场景，
## Autoload 在场景切换过程中保持存活。
##
## 开始游戏流程：
##   主菜单 → 确认对话框 → 加载界面 → 游戏世界
class_name MainMenu extends CanvasLayer

# ============================================================
# 3. 常量
# ============================================================

const LOADING_SCENE_PATH: String = "res://scenes/menu/loading_screen.tscn"

# ============================================================
# 6. 私有变量
# ============================================================

## 所有菜单按钮的引用数组。
var _buttons: Array[Button] = []

## 确认对话框根节点（遮罩层）。
var _confirm_overlay: Control = null

## toast 提示节点引用。
var _toast: Control = null

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	layer = 100000
	EventBus.game_state_changed.emit(&"main_menu")
	_build_ui()
	_animate_entrance()

# ============================================================
# 9. 公开方法 — 无
# ============================================================

# ============================================================
# 10. 私有方法 — UI 构建
# ============================================================

## 构建完整的主菜单 UI 树。
##
## 结构：
##   ColorRect（全屏背景）
##   → VBoxContainer（居中）
##     → 标题 Label
##     → HSeparator
##     → 按钮 ×5
##     → HSeparator
##     → 版本号 Label
func _build_ui() -> void:
	# 全屏深色背景
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.04, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 居中容器
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "MenuVBox"
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	# 标题
	var title: Label = _create_title()
	vbox.add_child(title)

	# 分隔线
	var sep1: HSeparator = HSeparator.new()
	sep1.custom_minimum_size = Vector2(MenuStyle.BUTTON_WIDTH, 0)
	vbox.add_child(sep1)

	# 菜单按钮
	var button_defs: Array[Dictionary] = _get_button_defs()
	for def: Dictionary in button_defs:
		var btn: Button = _create_menu_button(
			def.get("text", "") as String,
			def.get("callback", "") as String
		)
		vbox.add_child(btn)
		_buttons.append(btn)

	# 分隔线
	var sep2: HSeparator = HSeparator.new()
	sep2.custom_minimum_size = Vector2(MenuStyle.BUTTON_WIDTH, 0)
	vbox.add_child(sep2)

	# 版本号
	var version: Label = _create_version_label()
	vbox.add_child(version)

	# 居中定位
	_adjust_position()

## 创建标题 Label。
func _create_title() -> Label:
	var label: Label = Label.new()
	label.name = "TitleLabel"
	label.text = "Farm War"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", MenuStyle.TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", MenuStyle.ACCENT_COLOR)
	return label

## 获取菜单按钮定义数组。
func _get_button_defs() -> Array[Dictionary]:
	return [
		{"text": "开始游戏", "callback": "_on_start_game_pressed"},
		{"text": "加载游戏", "callback": "_on_load_game_pressed"},
		{"text": "成就", "callback": "_on_achievements_pressed"},
		{"text": "设置", "callback": "_on_settings_pressed"},
		{"text": "退出游戏", "callback": "_on_exit_pressed"},
	]

## 创建单个菜单按钮。
##
## [param text] 按钮文字。
## [param callback_name] 按钮按下的回调方法名。
func _create_menu_button(text: String, callback_name: String) -> Button:
	var btn: Button = Button.new()
	btn.name = "Btn%s" % text.replace(" ", "")
	btn.text = text
	btn.custom_minimum_size = Vector2(MenuStyle.BUTTON_WIDTH, MenuStyle.BUTTON_HEIGHT)
	btn.add_theme_font_size_override("font_size", MenuStyle.BUTTON_FONT_SIZE)
	btn.add_theme_color_override("font_color", MenuStyle.TEXT_COLOR)
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 安装样式
	btn.add_theme_stylebox_override("normal", MenuStyle.create_button_normal_style())
	btn.add_theme_stylebox_override("hover", MenuStyle.create_button_hover_style())
	btn.add_theme_stylebox_override("pressed", MenuStyle.create_button_pressed_style())

	# 连接回调
	var _err: int = btn.pressed.connect(Callable(self, callback_name))

	return btn

## 创建版本号 Label。
func _create_version_label() -> Label:
	var label: Label = Label.new()
	label.name = "VersionLabel"
	label.text = "v0.1.0 — 开发中"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", MenuStyle.SMALL_FONT_SIZE)
	label.add_theme_color_override("font_color", MenuStyle.DIM_TEXT_COLOR)
	return label

## 将菜单容器定位到视口中央。
func _adjust_position() -> void:
	var vbox: VBoxContainer = get_node("MenuVBox") as VBoxContainer
	if vbox == null:
		return
	# 使用 call_deferred 确保布局已计算
	vbox.reset_size()
	await get_tree().process_frame
	var vs: Vector2 = get_viewport().get_visible_rect().size
	vbox.position = (vs - vbox.size) * 0.5 - Vector2(0, 40)

# ============================================================
# 10. 私有方法 — 按钮回调
# ============================================================

func _on_start_game_pressed() -> void:
	_show_start_confirmation()

func _on_load_game_pressed() -> void:
	_show_toast("加载游戏功能尚未实现")

func _on_achievements_pressed() -> void:
	_show_toast("成就功能尚未实现")

func _on_settings_pressed() -> void:
	_show_toast("设置功能尚未实现")

func _on_exit_pressed() -> void:
	get_tree().quit()

# ============================================================
# 10. 私有方法 — 确认对话框
# ============================================================

## 显示"开始新游戏"确认对话框。
##
## 结构：
##   遮罩 ColorRect（半透明）
##   → Panel（居中）
##     → VBoxContainer
##       → 标题 Label
##       → 描述 Label
##       → HBoxContainer
##         → 确认 Button + 取消 Button
func _show_start_confirmation() -> void:
	if _confirm_overlay != null:
		return

	# 遮罩层
	_confirm_overlay = Control.new()
	_confirm_overlay.name = "ConfirmOverlay"
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm_overlay)

	# 半透明遮罩背景
	var blocker: ColorRect = ColorRect.new()
	blocker.name = "Blocker"
	blocker.color = Color(0.0, 0.0, 0.0, 0.5)
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_overlay.add_child(blocker)

	# 对话框面板
	var panel: Panel = Panel.new()
	panel.name = "DialogPanel"
	panel.size = Vector2(400, 200)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", MenuStyle.create_panel_style())
	_confirm_overlay.add_child(panel)

	# 面板居中
	var vs: Vector2 = get_viewport().get_visible_rect().size
	panel.position = (vs - panel.size) * 0.5

	# 内容容器
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "DialogVBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# 标题
	var title: Label = Label.new()
	title.name = "DialogTitle"
	title.text = "开始新游戏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", MenuStyle.ACCENT_COLOR)
	vbox.add_child(title)

	# 描述
	var desc: Label = Label.new()
	desc.name = "DialogDesc"
	desc.text = "确认开始新游戏吗？\n当前未保存的进度将会丢失。"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", MenuStyle.TEXT_COLOR)
	vbox.add_child(desc)

	# 弹性空间
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# 按钮行
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.name = "ButtonRow"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	# 确认按钮
	var confirm_btn: Button = _create_dialog_button("确认", true)
	confirm_btn.pressed.connect(_on_confirm_new_game)
	hbox.add_child(confirm_btn)

	# 取消按钮
	var cancel_btn: Button = _create_dialog_button("取消", false)
	cancel_btn.pressed.connect(_on_cancel_new_game)
	hbox.add_child(cancel_btn)

	# 入场动画：遮罩 + 面板淡入
	blocker.modulate.a = 0.0
	panel.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(blocker, "modulate:a", 1.0, 0.2)
	tween.tween_property(panel, "modulate:a", 1.0, 0.25).set_ease(Tween.EASE_OUT)

## 创建确认对话框中的按钮。
func _create_dialog_button(text: String, is_primary: bool) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if is_primary:
		# 确认按钮使用强调色
		var normal_style: StyleBoxFlat = StyleBoxFlat.new()
		normal_style.bg_color = Color(MenuStyle.ACCENT_COLOR.r * 0.3, MenuStyle.ACCENT_COLOR.g * 0.3, MenuStyle.ACCENT_COLOR.b * 0.2, 0.9)
		normal_style.border_width_left = 1
		normal_style.border_width_right = 1
		normal_style.border_width_top = 1
		normal_style.border_width_bottom = 1
		normal_style.border_color = MenuStyle.ACCENT_COLOR
		normal_style.corner_radius_top_left = 8
		normal_style.corner_radius_top_right = 8
		normal_style.corner_radius_bottom_left = 8
		normal_style.corner_radius_bottom_right = 8
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_color_override("font_color", MenuStyle.ACCENT_COLOR)
	else:
		btn.add_theme_stylebox_override("normal", MenuStyle.create_button_normal_style())
		btn.add_theme_stylebox_override("hover", MenuStyle.create_button_hover_style())
		btn.add_theme_stylebox_override("pressed", MenuStyle.create_button_pressed_style())
		btn.add_theme_color_override("font_color", MenuStyle.TEXT_COLOR)

	return btn

func _on_confirm_new_game() -> void:
	get_tree().change_scene_to_file(LOADING_SCENE_PATH)

func _on_cancel_new_game() -> void:
	if _confirm_overlay != null:
		_confirm_overlay.queue_free()
		_confirm_overlay = null

# ============================================================
# 10. 私有方法 — Toast 提示
# ============================================================

## 显示临时 toast 提示，2 秒后自动消失。
##
## [param message] 提示文本内容。
func _show_toast(message: String) -> void:
	if _toast != null:
		_toast.queue_free()

	# 容器
	_toast = Control.new()
	_toast.name = "Toast"
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)

	# 背景面板
	var panel: Panel = Panel.new()
	panel.name = "ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", MenuStyle.create_toast_style())
	_toast.add_child(panel)

	# 文本 Label
	var label: Label = Label.new()
	label.name = "ToastLabel"
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", MenuStyle.TEXT_COLOR)
	panel.add_child(label)

	# 自适应尺寸
	await get_tree().process_frame
	panel.size = label.size + Vector2(32, 20)
	label.position = Vector2(16, 10)

	# 定位：屏幕底部中央
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_toast.position = Vector2((vs.x - panel.size.x) * 0.5, vs.y * 0.75)

	# Toast 入场动画（从下方滑入 + 淡入）
	_toast.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_toast, "modulate:a", 1.0, 0.3)

	# 2 秒后淡出并销毁
	tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	tween.tween_callback(_toast.queue_free)
	tween.tween_callback(func() -> void: _toast = null)

# ============================================================
# 10. 私有方法 — 入场动画
# ============================================================

## 菜单入场动画：按钮从透明渐入，依次错开延迟。
func _animate_entrance() -> void:
	for i: int in range(_buttons.size()):
		var btn: Button = _buttons[i]
		btn.modulate.a = 0.0
		btn.position.x -= 30.0  # 从左侧滑入
		var tween: Tween = create_tween()
		tween.tween_interval(float(i) * 0.08)
		tween.set_parallel(true)
		tween.tween_property(btn, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
		tween.tween_property(btn, "position:x", btn.position.x + 30.0, 0.3).set_ease(Tween.EASE_OUT)

	# 版本号也在最后淡入
	for child: Node in get_children():
		if child is Label and child.name == "VersionLabel":
			var version: Label = child as Label
			version.modulate.a = 0.0
			var tween: Tween = create_tween()
			tween.tween_interval(float(_buttons.size()) * 0.08)
			tween.tween_property(version, "modulate:a", 1.0, 0.4)
