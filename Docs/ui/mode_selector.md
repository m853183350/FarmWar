# 模式选择器 (ModeSelector)

模式选择器是 HUD 顶部的核心交互组件，为玩家提供指令模式切换能力。玩家通过键盘顶行按键（`1`~`=`）或鼠标点击来选择当前操作模式，不同模式决定了左键点击/拖拽地块时的行为。

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

- **水平位置**：从屏幕左 1/4 到右 1/4（即占据中间 50% 宽度），整体居中
- **垂直位置**：屏幕顶部，紧贴上边缘（与 ResourceBar / GameClock 同一行或紧邻其下方）
- **自适应**：通过 anchor 定位，适配不同分辨率；方框尺寸和字体大小随分辨率缩放
- **换行**：方框从左到右排列，一行宽度不足时自动换行（`HFlowContainer`）

---

## 模式方框 (ModeSlot) 规格

### 尺寸与间距

| 属性 | 基准值 (1920×1080) | 说明 |
|------|-------------------|------|
| 方框宽度 | 120px | 正方形方框 |
| 方框高度 | 120px | 正方形方框 |
| 方框间距 | 0px | 水平/垂直间距 |
| 图标内边距 | 0px | 图标与方框边缘的距离 |
| 键位标签字体大小 | 14px | 右下角键位提示 |
| 键位标签背景 | `res://assets/sprites/UI/顶部选项框.png` | 背景图片 |


### 方框结构

```
┌─────────────────────────┐
│                         │
│       ┌───────┐         │
│       │  图标  │         │  ← TextureRect（64×64，居中）
│       │       │         │
│       └───────┘      [1]│  ← Label（键位，右下角）
│                         │
└─────────────────────────┘
        ← 80px →
```

每个方框内部：
- **图标**（`TextureRect`）：居中放置，默认 64×64（内边距 8px 后）= 方框 80px - 8px×2 = 64px
- **键位标签**（`Label`）：右下角，显示对应按键的文本（如 `1`, `2`, `-`, `=`）

### 视觉效果

| 状态 | 图标缩放 | 方框背景 | 说明 |
|------|---------|---------|------|
| 默认 | 1.0× | 无/透明 | 普通状态 |
| 鼠标悬停 | 1.2× | 半透明底色高亮 | 表明可点击 |
| 选中 | 1.35× | 亮色边框/底色 | 当前激活模式 |
| 未解锁 | 0.85× | 灰色半透明 | 灰显，不可点击 |

### 动画参数

| 属性 | 值 | 说明 |
|------|-----|------|
| 缩放过渡时间 | 0.15s | Tween EASE_OUT_BACK |
| 悬停缩放 | 1.2 | 相对于默认的倍数 |
| 选中缩放 | 1.35 | 相对于默认的倍数 |
| 未解锁透明度 | 0.4 | modulate.a |

---

## 模式列表

### 默认模式（始终存在）

| 序号 | 按键 | 模式 ID | 名称 | 图标 | 行为 |
|------|------|---------|------|------|------|
| 1 | `1` | `cursor` | 光标 | `assets/sprites/ui/mode_cursor.png` | 选择对象/地块/单位，不直接发送指令 |
| 2 | `2` | `gather` | 采集 | `assets/sprites/ui/mode_gather.png` | 对地块发送挖掘/砍树等采集指令 |

### 作物模式（随游戏进度解锁）

每解锁一科作物后，自动向模式选择器追加一个新方框：

| 解锁时机 | 模式 ID | 图标 | 行为 |
|---------|---------|------|------|
| 禾本科解锁 | `wheat_tier1` | 小麦图标 | 选中后，点击地块 → 种植小麦 |
| 豆科解锁 | `legume_tier1` | 豆类图标 | 选中后，点击地块 → 种植豆科作物 |
| ... | ... | ... | ... |

按键按方框从左到右顺序依次分配 `1` ~ `=`（共 12 个槽位）。

---

## 信号

### 发出信号

| 信号 | 发出时机 | 参数 |
|------|---------|------|
| `mode_selected(mode_id: StringName)` | 玩家通过按键或点击选择模式 | `mode_id`: 如 `"cursor"`, `"gather"`, `"wheat_tier1"` |

### 监听信号（来自 EventBus）

| 信号 | 用途 |
|------|------|
| `crop_family_unlocked(family_id: String, crop_id: String, icon_path: String)` | 解锁新科作物时添加对应模式方框 |

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
  "select_sound": "res://resources/sound/选中.ogg",
  "font_size": 14,
  "plant_icons":[
    {
      "id": "Poaceae",
      "icon": "res://assets/sprites/UI/禾本科.png"
    }
  ]
}
```

### 键位映射

方框位置 → 按键的映射由 `slot_keys` 数组定义，位置 n 的方框使用 `slot_keys[n]`。可配置为不同布局（如 AZERTY、QWERTZ 等）。

方框位置从 0 开始，依次对应键盘顶行：

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

**重要** 按键交互配置在 `config/player_key_bind.json` 中
---

## 交互流程

```
[键盘按键 KEY_1~KEY_EQUAL] ──→ ModeSelector._handle_key_press()
                                          │
[鼠标点击方框] ──→ ModeSlot._on_pressed() ─┘
                                          │
                                          ▼
                              检查方框是否已解锁
                              播放 "选中.ogg" 音效
                              更新 _selected_index
                              播放选中动画（旧→1.0, 新→1.35）
                              发出 mode_selected(mode_id)
                              发出 EventBus.mode_changed(mode_id)
```



---

## 公共 API

```gdscript
class_name ModeSelector extends HFlowContainer

## 当前选中的模式 ID。
var current_mode: StringName

## 获取当前模式 ID。
func get_current_mode() -> StringName

## 添加一个新模式（游戏过程中解锁作物时调用）。
func add_mode(id: StringName, name: String, icon: Texture2D, tooltip: String = "") -> void

## 通过模式 ID 选择模式（外部调用，如快捷键重映射）。
func select_mode_by_id(id: StringName) -> void

## 通过按键选择模式。
func select_mode_by_key(keycode: Key) -> void

## 切换到光标模式。
func select_cursor_mode() -> void
```

---

## 音效

- **选择音效**：播放 `/resources/sound/选中.ogg`
- 播放方式：通过 `AudioStreamPlayer` 子节点（由 ModeSelector 持有）
- 不通过 AudioManager（避免创建 AudioManager 依赖），因为这是 UI 本地音效

---

## 关联文档

- [11.1玩家UI系统.md](11.1玩家UI系统.md) — UI 整体框架
- [hud.md](hud.md) — HUD 详细布局
- [../autoload/event_bus.md](../autoload/event_bus.md) — EventBus 信号注册
- [../../scripts/ui/mode_selector.gd](../../scripts/ui/mode_selector.gd) — 实现代码
- [../../config/ui/mode_definitions.json](../../config/ui/mode_definitions.json) — 模式配置
