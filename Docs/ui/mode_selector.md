# 模式选择器 (ModeSelector)

`ModeSelector` 是 HUD 顶部的核心交互组件，为玩家提供指令模式切换能力。玩家通过键盘顶行按键（`1`~`=`）或鼠标点击来选择当前操作模式，不同模式决定了左键点击/拖拽地块时的行为。

---

## 视图位置

```
屏幕宽度: 1920px（基准）
┌──────────────────────────────────────────────────┐
│ [GameClock]      [==== 模式选择器 ====]      [小地图] │  ← 顶部区域
│                  左1/4 ~ 右1/4                   │
│                    (50% 宽度)                     │
├──────────────────────────────────────────────────┤
│                                                  │
│                    游戏世界                        │
│                                                  │
```

- **水平位置**：从屏幕左 1/4 到右 1/4（占据中间 50% 宽度），整体居中
- **垂直位置**：屏幕顶部，紧贴上边缘
- **布局**：方框从左到右排列，一行宽度不足时自动换行（`HFlowContainer`）

---

## 模式方框结构

```
┌─────────────────────────┐
│                         │
│       ┌───────┐         │
│       │  图标  │         │  ← TextureRect（96×96，居中）
│       │       │         │
│       └───────┘      [1]│  ← Label（键位，右下角）
│                         │
└─────────────────────────┘
        ← 120px →
```

每个方框由三层组成（从底到顶）：
1. **背景**（`TextureRect`）— 120×120 全尺寸背景贴图
2. **图标**（`TextureRect`）— 96×96 居中，支持缩放动画
3. **键位标签**（`Label`）— 右下角，半透明深色底 + 白色文字

### 视觉状态

| 状态 | 图标缩放 | 说明 |
|------|---------|------|
| 默认 | 1.0× | 普通状态 |
| 鼠标悬停 | 1.2× | 表明可点击 |
| 选中 | 1.35× | 当前激活模式 |
| 未解锁 | 0.4 opacity | 灰显，不可交互 |

### 动画参数

| 属性 | 值 | 说明 |
|------|-----|------|
| 缩放过渡时间 | 0.15s | Tween EASE_OUT + TRANS_BACK |
| 悬停缩放 | 1.2 | 相对于默认的倍数 |
| 选中缩放 | 1.35 | 相对于默认的倍数 |
| 未解锁透明度 | 0.4 | modulate.a |

---

## 键位映射

方框位置 → 按键由 `config/ui/mode_definitions.json` 中的 `slot_keys` 数组定义：

| 位置 | 默认键 | Godot KeyCode | 显示文本 |
|------|--------|--------------|---------|
| 0 | `1` | `KEY_1` | `1` |
| 1 | `2` | `KEY_2` | `2` |
| 2 | `3` | `KEY_3` | `3` |
| 3 | `4` | `KEY_4` | `4` |
| 4 | `5` | `KEY_5` | `5` |
| 5 | `6` | `KEY_6` | `6` |
| 6 | `7` | `KEY_7` | `7` |
| 7 | `8` | `KEY_8` | `8` |
| 8 | `9` | `KEY_9` | `9` |
| 9 | `0` | `KEY_0` | `0` |
| 10 | `-` | `KEY_MINUS` | `-` |
| 11 | `=` | `KEY_EQUAL` | `=` |

---

## 信号

| 信号 | 发出时机 | 参数 |
|------|---------|------|
| `mode_selected(mode_id: StringName)` | 玩家通过按键或点击选择模式 | `mode_id`: 如 `"cursor"`, `"gather"` |

同时通过 `EventBus.mode_changed` 广播。

---

## 配置

### 配置文件：`config/ui/mode_definitions.json`

```json
{
  "default_modes": [
    {
      "id": "cursor",
      "name": "光标",
      "icon": "res://assets/sprites/ui/光标模式.png",
      "tooltip": "选择对象和地块"
    },
    {
      "id": "gather",
      "name": "采集",
      "icon": "res://assets/sprites/ui/采集.png",
      "tooltip": "挖掘、砍树等采集操作"
    }
  ],
  "slot_keys": [
    "KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5", "KEY_6",
    "KEY_7", "KEY_8", "KEY_9", "KEY_0", "KEY_MINUS", "KEY_EQUAL"
  ],
  "slot_size": 120,
  "icon_size": 96,
  "spacing": 0,
  "hover_scale": 1.2,
  "selected_scale": 1.35,
  "scale_duration": 0.15,
  "font_size": 14,
  "slot_background": "res://assets/sprites/UI/顶部选项框.png",
  "plant_icons": [
    {
      "id": "Poaceae",
      "icon": "res://assets/sprites/UI/禾本科.png"
    }
  ]
}
```

`plant_icons` 用于 `add_mode_for_family()` 便捷方法从配置加载图标。

---

## 公共 API

```gdscript
# === 查询 ===

## 获取当前选中的模式 ID。始终返回有效值（最差也是 "cursor"）。
func get_current_mode() -> StringName

## 获取当前选中模式的索引（从 0 开始）。
func get_selected_index() -> int

## 获取当前模式总数。
func get_mode_count() -> int

## 检查指定模式是否存在。
func has_mode(id: StringName) -> bool


# === 增删 ===

## 添加一个新模式。
## [param id]         唯一模式标识（如 "wheat_tier1"）。
## [param mode_name]  显示名称。
## [param icon]       图标纹理（需由调用方预加载，如 load() 或 preload）。
## [param tooltip]    悬浮提示文本（可选）。
## [param locked]     是否初始锁定（可选，默认 false）。
## 返回：添加后的方框索引；超过 12 个上限则返回 -1。
func add_mode(id: StringName, mode_name: String, icon: Texture2D,
              tooltip: String = "", locked: bool = false) -> int

## 根据作物科 ID 从配置添加新模式（便捷方法）。
## 从 plant_icons 配置中查找图标路径并加载，然后调用 add_mode。
## 返回：方框索引；未找到配置或超上限返回 -1。
func add_mode_for_family(family_id: String) -> int

## 移除一个模式。不能移除最后一个模式。
## 返回 true 表示成功，false 表示未找到或无法移除。
func remove_mode(id: StringName) -> bool


# === 选择 ===

## 通过模式 ID 切换选中（如 "cursor"、"gather"）。
func select_mode_by_id(id: StringName) -> void

## 通过键盘按键切换选中。
func select_mode_by_key(keycode: Key) -> void

## 切换到光标模式（索引 0）。
func select_cursor_mode() -> void


# === 锁定 ===

## 解锁指定模式（可交互）。
func unlock_mode(id: StringName) -> void

## 锁定指定模式（灰显且不可交互，若为当前选中则自动切回光标模式）。
func lock_mode(id: StringName) -> void
```

---

## 使用示例

### 游戏初始化

`ModeSelector` 在 `_ready()` 时自动从 `config/ui/mode_definitions.json` 加载默认模式（光标 + 采集）。无需手动初始化。

### 解锁作物时添加模式

```gdscript
# 方式 1：从配置加载图标（推荐，图标路径集中在 JSON 中管理）
var index: int = mode_selector.add_mode_for_family("Poaceae")
if index >= 0:
    print("禾本科模式已添加到位置 %d" % index)

# 方式 2：手动加载图标后添加
var icon: Texture2D = load("res://assets/sprites/ui/wheat_icon.png")
mode_selector.add_mode("wheat_tier1", "小麦", icon, "种植小麦作物")

# 初始锁定，后续条件满足后再解锁
var idx: int = mode_selector.add_mode("advanced", "高级", icon, "", true)
# ... 玩家达成条件后 ...
mode_selector.unlock_mode("advanced")
```

### 读取当前选中状态

```gdscript
# 方式 1：获取 ID
var mode_id: StringName = mode_selector.get_current_mode()
match mode_id:
    "cursor":
        # 光标模式逻辑
        pass
    "gather":
        # 采集模式逻辑
        pass

# 方式 2：获取索引
var idx: int = mode_selector.get_selected_index()
print("当前选中第 %d 个方框" % idx)
```

### 程序化切换模式

```gdscript
# 通过 ID 切换
mode_selector.select_mode_by_id("gather")

# 切回光标模式
mode_selector.select_cursor_mode()
```

### 动态管理方框

```gdscript
# 检查模式是否存在
if mode_selector.has_mode("wheat_tier1"):
    mode_selector.remove_mode("wheat_tier1")

# 遍历所有模式
for i in range(mode_selector.get_mode_count()):
    mode_selector.select_mode_by_key(KEY_1 + i)
    print("模式: %s" % mode_selector.get_current_mode())
```

### 监听模式切换

```gdscript
# 直接连接 ModeSelector 信号
mode_selector.mode_selected.connect(_on_mode_changed)

func _on_mode_changed(mode_id: StringName) -> void:
    print("切换到模式: %s" % mode_id)

# 或通过 EventBus 监听（解耦）
func _ready() -> void:
    EventBus.mode_changed.connect(_on_global_mode_changed)
```

---

## 内部流程

```
[键盘按键 1~=] ──→ _input() → _select_by_key()
                                      │
[鼠标点击方框] ──→ _on_slot_gui_input() ─┘
                                      │
                                      ▼
                          检查方框是否已解锁
                          播放 "选中.ogg" 音效
                          更新 _selected_index
                          播放选中动画
                          发出 mode_selected(mode_id)
                          发出 EventBus.mode_changed(mode_id)
```

---

## 关联文档

- [11.1玩家UI系统.md](11.1玩家UI系统.md) — UI 整体框架
- [hud.md](hud.md) — HUD 详细布局
- [../autoload/event_bus.md](../autoload/event_bus.md) — EventBus 信号注册
- [../../scripts/ui/mode_selector.gd](../../scripts/ui/mode_selector.gd) — 实现代码
- [../../config/ui/mode_definitions.json](../../config/ui/mode_definitions.json) — 模式配置
