# MenuStyle — 菜单样式工具

## 用途

为所有菜单场景提供统一的视觉样式。纯静态工具类（`extends RefCounted`），不挂载到场景树。

## 公开 API

### 面板

- `create_panel_style() -> StyleBoxFlat` — 深色半透明面板（圆角 12px，边框 1px）
- `create_toast_style() -> StyleBoxFlat` — Toast 提示背景（圆角 8px）

### 按钮

- `create_button_normal_style() -> StyleBoxFlat` — 普通状态
- `create_button_hover_style() -> StyleBoxFlat` — 悬停状态（金色边框）
- `create_button_pressed_style() -> StyleBoxFlat` — 按下状态

### 字体

- `get_title_font() -> SystemFont` — 标题（48px，Arial/Noto Sans SC/SimHei）
- `get_button_font() -> SystemFont` — 按钮（24px）
- `get_small_font() -> SystemFont` — 辅助文本（14px）

## 颜色常量

| 常量 | 值 | 用途 |
|------|-----|------|
| `BG_COLOR` | `(0.08, 0.08, 0.12, 0.92)` | 面板背景 |
| `ACCENT_COLOR` | `(0.9, 0.85, 0.4)` | 强调色（金色） |
| `TEXT_COLOR` | `(0.95, 0.95, 0.95)` | 主文本 |
| `DIM_TEXT_COLOR` | `(0.5, 0.5, 0.5)` | 辅助文本 |
