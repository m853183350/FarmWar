## 加载界面，在场景切换过程中显示加载进度。
##
## 使用 [method ResourceLoader.load_threaded_request] 在后台线程预加载
## 游戏场景资源，同时显示进度条动画。加载完成后自动切换到游戏场景。
##
## 如果后台加载失败，会回退到直接 [method SceneTree.change_scene_to_file]。
class_name LoadingScreen extends CanvasLayer

# ============================================================
# 3. 常量
# ============================================================

const GAME_SCENE_PATH: String = "res://scenes/game/game.tscn"

# ============================================================
# 6. 私有变量
# ============================================================

## 进度条控件引用。
var _progress_bar: ProgressBar = null

## 状态文本 Label 引用。
var _status_label: Label = null

## 是否正在执行场景切换（防重入）。
var _transitioning: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	layer = 100000
	EventBus.game_state_changed.emit(&"loading")
	_build_ui()
	_animate_entrance()
	_start_loading()

func _process(_delta: float) -> void:
	if _transitioning:
		return

	if _progress_bar == null:
		return

	var status: int = ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH)
	var progress: Array = []

	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_status_label.text = "正在准备资源..."

		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			status = ResourceLoader.load_threaded_get_status(GAME_SCENE_PATH, progress)
			if progress.size() > 0:
				var pct: float = float(progress[0]) * 100.0
				# 平滑插值让进度条动画更流畅
				_progress_bar.value = lerpf(_progress_bar.value, pct, 0.2)
				_status_label.text = "正在加载资源... %d%%" % int(_progress_bar.value)

		ResourceLoader.THREAD_LOAD_LOADED:
			_progress_bar.value = 100.0
			_status_label.text = "加载完成，正在进入游戏..."
			_transitioning = true
			_enter_game()

		ResourceLoader.THREAD_LOAD_FAILED:
			_status_label.text = "资源加载失败，正在重试..."
			_transitioning = true
			_fallback_load()

# ============================================================
# 9. 公开方法 — 无
# ============================================================

# ============================================================
# 10. 私有方法 — UI 构建
# ============================================================

## 构建加载界面 UI。
##
## 结构：
##   ColorRect（全屏深色背景）
##   → Panel（居中，~500×180）
##     → VBoxContainer
##       → 标题 Label "正在加载..."
##       → ProgressBar
##       → 状态文本 Label
func _build_ui() -> void:
	# 全屏背景
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.04, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 居中面板
	var panel: Panel = Panel.new()
	panel.name = "Panel"
	panel.size = Vector2(500, 180)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", MenuStyle.create_panel_style())
	add_child(panel)

	# 面板居中
	var vs: Vector2 = get_viewport().get_visible_rect().size
	panel.position = (vs - panel.size) * 0.5

	# 内容容器
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# 弹性空间（顶部）
	var top_spacer: Control = Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(top_spacer)

	# 标题
	var title: Label = Label.new()
	title.name = "TitleLabel"
	title.text = "正在加载..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", MenuStyle.ACCENT_COLOR)
	vbox.add_child(title)

	# 进度条
	_progress_bar = ProgressBar.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.custom_minimum_size = Vector2(400, 24)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)

	# 状态文本
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "正在准备..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", MenuStyle.DIM_TEXT_COLOR)
	vbox.add_child(_status_label)

	# 弹性空间（底部）
	var bottom_spacer: Control = Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(bottom_spacer)

func _animate_entrance() -> void:
	var panel: Panel = get_node_or_null("Panel") as Panel
	if panel == null:
		return
	panel.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)

# ============================================================
# 10. 私有方法 — 加载逻辑
# ============================================================

## 开始后台加载游戏场景。
func _start_loading() -> void:
	var err: Error = ResourceLoader.load_threaded_request(GAME_SCENE_PATH)
	if err != OK:
		push_warning("LoadingScreen: 无法启动后台加载，使用直接加载")
		_fallback_load()

## 进入游戏场景（加载完成后调用）。
func _enter_game() -> void:
	# 短暂延迟让玩家看到 100% 完成状态
	await get_tree().create_timer(0.3).timeout
	if _progress_bar != null:
		# 取整到 100
		_progress_bar.value = 100.0
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

## 回退加载：直接切换场景（不经过进度条）。
func _fallback_load() -> void:
	_transitioning = true
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
