## 菜单 UI 样式工具。
##
## 提供静态工厂方法，为所有菜单场景生成统一的 [StyleBoxFlat] 和 [SystemFont] 配置。
## 避免各菜单场景重复样式代码。作为 [RefCounted] 纯工具类使用，不挂载到场景树。
##
## 使用方式：
##   var style: StyleBoxFlat = MenuStyle.create_panel_style()
##   var font: SystemFont = MenuStyle.get_button_font()
class_name MenuStyle extends RefCounted

# ============================================================
# 3. 常量 — 颜色
# ============================================================

const BG_COLOR: Color = Color(0.08, 0.08, 0.12, 0.92)
const ACCENT_COLOR: Color = Color(0.9, 0.85, 0.4)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.95)
const DIM_TEXT_COLOR: Color = Color(0.5, 0.5, 0.5)
const BUTTON_NORMAL_COLOR: Color = Color(0.15, 0.15, 0.22, 0.9)
const BUTTON_HOVER_COLOR: Color = Color(0.25, 0.25, 0.35, 0.95)
const BUTTON_PRESSED_COLOR: Color = Color(0.1, 0.1, 0.15, 0.95)
const BORDER_COLOR: Color = Color(0.3, 0.3, 0.4, 0.6)
const TOAST_BG_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)

# ============================================================
# 3. 常量 — 尺寸
# ============================================================

const CORNER_RADIUS: int = 12
const BUTTON_WIDTH: float = 320.0
const BUTTON_HEIGHT: float = 60.0
const BUTTON_FONT_SIZE: int = 24
const TITLE_FONT_SIZE: int = 48
const SMALL_FONT_SIZE: int = 14

# ============================================================
# 9. 公开方法 — 面板样式
# ============================================================

## 创建面板背景样式（深色半透明，带圆角和边框）。
static func create_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = BORDER_COLOR
	style.corner_radius_top_left = CORNER_RADIUS
	style.corner_radius_top_right = CORNER_RADIUS
	style.corner_radius_bottom_left = CORNER_RADIUS
	style.corner_radius_bottom_right = CORNER_RADIUS
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	return style

# ============================================================
# 9. 公开方法 — 按钮样式
# ============================================================

## 创建按钮普通状态样式。
static func create_button_normal_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BUTTON_NORMAL_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = BORDER_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

## 创建按钮悬停状态样式。
static func create_button_hover_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BUTTON_HOVER_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

## 创建按钮按下状态样式。
static func create_button_pressed_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BUTTON_PRESSED_COLOR
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style

## 创建 toast 提示背景样式。
static func create_toast_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = TOAST_BG_COLOR
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style

# ============================================================
# 9. 公开方法 — 字体
# ============================================================

## 获取标题字体（大号，金色）。
static func get_title_font() -> SystemFont:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Noto Sans SC", "SimHei"])
	font.font_size = TITLE_FONT_SIZE
	return font

## 获取按钮字体（中号，白色）。
static func get_button_font() -> SystemFont:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Noto Sans SC", "SimHei"])
	font.font_size = BUTTON_FONT_SIZE
	return font

## 获取小号字体（用于版本号等辅助文本）。
static func get_small_font() -> SystemFont:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Arial", "Noto Sans SC", "SimHei"])
	font.font_size = SMALL_FONT_SIZE
	return font
