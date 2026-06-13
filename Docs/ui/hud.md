# HUD 详细布局

HUD 是 Layer 1 常驻 UI 层，始终可见且不阻止地块/单位交互。本文档定义各子组件的精确位置、尺寸、行为和实现细节。

场景根节点：`hud.tscn`（`CanvasLayer`, layer=1），控制器脚本：`hud.gd`。

---

## 整体布局（1920×1080 基准）

```
┌──────────────────────────────────────────────────────────┐
│ [GameClock]               [模式选择器]            [小地图] │  ← 顶部条
│  左上角              左1/4 ~ 右1/4 (50%)        右上角  │
│                                                          │
│ ┌──────────────┐                                         │
│ │  信息面板     │         游 戏 世 界                      │
│ │  (InfoPanel) │                                         │
│ │   左侧       │                                         │
│ │             │                                         │
│ └──────────────┘                                         │
│                                           ┌────────────┐ │
│                                           │  通知条      │ │
│                                           │ (Notification│ │
│                                           │  右侧)      │ │
│                                           └────────────┘ │
│                                                          │
│              ┌──────────────────────────┐                │
│              │      快捷栏 (ActionBar)   │                │
│              │      底部居中             │                │
│              └──────────────────────────┘                │
└──────────────────────────────────────────────────────────┘
```

### 各组件位置规格

| 组件 | 水平位置 | 垂直位置 | Anchor | 尺寸 |
|------|---------|---------|--------|------|
| **GameClock** | 左上角，距左边缘 16px | 距顶边缘 8px | 左上 | 自适应内容 |
| **模式选择器** | 左 1/4 ~ 右 1/4（水平居中） | 距顶边缘 8px | 顶部居中 | 宽度 50% 视口 |
| **小地图** | 右上角，距右边缘 16px | 距顶边缘 8px | 右上 | 180×120px |
| **信息面板** | 左侧，距左边缘 8px | 垂直居中 | 左侧居中 | 宽 280px，高度自适应 |
| **通知条** | 右侧，距右边缘 8px | 垂直居中偏上 | 右侧 | 宽 260px，高度 60% |
| **快捷栏** | 底部居中 | 距底边缘 16px | 底部居中 | 自适应内容 |
| **资源栏** | 已合并到模式选择器上方或与模式选择器同行 | TBD | TBD | TBD |

> **注意**：ResourceBar（资源栏）和 ActionBar（快捷栏）的精确位置与模式选择器的相对关系由 hud.tscn 场景布局决定。资源显示可能在模式选择器上方另起一行，也可能整合到顶部条的紧凑布局中。

---

## 顶部条布局

顶部条由三个元素组成：GameClock（左）、模式选择器（中）、小地图（右）。

### 实现方式

在 `hud.tscn` 中，使用 `MarginContainer` 包裹一个 `HBoxContainer`：

```
hud.tscn (Control, anchor: full rect)
├── MarginContainer (顶部条容器, anchor: top, 高度自适应)
│   └── HBoxContainer
│       ├── GameClock (Control 或 MarginContainer)
│       │   ├── 暂停/速度按钮
│       │   └── 时间 Label
│       ├── 间隔 (Control, expand, 将模式选择器推向中间)
│       ├── ModeSelector (HFlowContainer)
│       ├── 间隔 (Control, expand, 将小地图推向右)
│       └── Minimap (SubViewportContainer)
```

或使用 `Container` + 手动 anchor 定位实现更精确的控制。

---

## 模式选择器 (ModeSelector)

详见 [mode_selector.md](mode_selector.md)。

**核心要点：**
- 从配置 `config/ui/mode_definitions.json` 加载默认模式
- 初始包含"光标模式"和"采集"两个方框
- 每解锁一科作物，动态追加新方框
- 方框从左到右排列，一行放不下时自动换行
- 键盘 `1`~`=` 或鼠标点击选择模式
- 选中时播放 `resources/sound/选中.ogg` 音效

---

## 信息面板 (InfoPanel)

### 触发时机

| 操作 | 面板行为 |
|------|---------|
| 选中地块 | 显示地块信息（类型、湿度、硬度、是否可耕种、已有作物/建筑） |
| 选中单位 | 显示单位信息（名称、生命值、攻击力、当前状态） |
| 选中建筑 | 显示建筑信息（类型、生命值、生产进度/队列） |
| 取消选中（Esc/点击空地） | 隐藏面板 |

### 面板布局

```
┌──────────────┐
│ 标题栏        │  ← 选中对象名称/类型
│              │
│ 属性列表      │  ← 多行属性（Label + 数值/进度条）
│ • 血量  ████ │
│ • 攻击  ████ │
│ • 状态: 工作中│
│              │
│ ┌──────────┐ │
│ │ 操作按钮  │ │  ← 上下文操作（如"查看详情"、"升级"）
│ └──────────┘ │
└──────────────┘
```

### 信号

| 信号 | 发出时机 | 监听者 |
|------|---------|--------|
| `tile_selected(tile_data)` | 点击地块 | InfoPanel |
| `unit_selected(unit_id)` | 选中单位 | InfoPanel |
| `building_selected(building_id)` | 选中建筑 | InfoPanel |
| `selection_cleared` | 取消选中 | InfoPanel（隐藏） |

---

## 小地图 (Minimap)

### 布局

- 位置：右上角
- 尺寸：180×120px（基准）
- 背景：半透明深色底

### 功能

- 显示地形缩略图
- 显示己方单位/建筑位置（小色点）
- 显示视野范围
- 点击小地图 → 快速跳转摄像机位置
- 快捷键 `M` → 放大/缩小小地图

### 实现方案

- 方案 A：`SubViewport` + 正交 Camera（实时渲染缩略图）— 性能开销较大
- 方案 B：自定义 `_draw()` 绘制 — 灵活但需手动维护
- **推荐**：B 方案，每 N tick 更新一次即可（如 5 tick = 250ms），无需逐帧渲染

---

## 通知条 (NotificationBar)

### 布局

- 位置：右侧，从顶部 25% 到底部 75% 的区域（中间 50% 高度）
- 宽度：260px
- 内部为 `ScrollContainer` + `VBoxContainer`，从下到上滚动（新通知出现在顶部）

### 通知类型

| 级别 | 颜色 | 例子 |
|------|------|------|
| 信息（Info） | 白色 | "收获完成：小麦 +10" |
| 警告（Warning） | 黄色 | "资源不足，无法建造" |
| 严重（Alert） | 红色 | "敌袭警告！东侧出现敌人" |

### 信号

```
EventBus.notification_posted(text: String, level: int)
```

### 行为

- 通知出现时从右侧滑入，3 秒后自动消失
- 多条通知堆积时自动向上推移
- 可点击通知以跳转到相关位置/对象

---

## 快捷栏 (ActionBar)

### 布局

- 位置：底部居中
- 尺寸：自适应内容
- 内部为 `HBoxContainer`，按钮之间间距 8px

### 按钮列表（默认）

| 按钮 | 快捷键 | 功能 |
|------|--------|------|
| 仓库 | `TAB` | 打开仓库界面（Overlay） |
| 商店 | `B` | 打开商店界面（Overlay） |
| 科技树 | `T` | 打开科技树界面（Overlay） |
| 作物图鉴 | `C` | 打开作物图鉴（Overlay） |
| 建造 | `V` | 打开建造菜单（Overlay） |
| 帮助 | `F1` | 打开帮助界面（Overlay） |

### 快捷键由 JSON 配置

```json
{
  "action_bar": [
    { "id": "inventory", "label": "仓库", "key": "KEY_TAB" },
    { "id": "shop", "label": "商店", "key": "KEY_B" },
    { "id": "tech_tree", "label": "科技树", "key": "KEY_T" },
    { "id": "cropopedia", "label": "作物图鉴", "key": "KEY_C" },
    { "id": "build", "label": "建造", "key": "KEY_V" },
    { "id": "help", "label": "帮助", "key": "KEY_F1" }
  ]
}
```

---

## GameClock（游戏时钟）

### 布局

- 位置：左上角（在模式选择器左侧）
- 内容：
  - 游戏时间显示（`HH:MM` 格式，从 tick 换算）
  - 暂停/播放按钮（`Space` 快捷键）
  - 速度控制按钮（1× / 2× / 4×）

### 信号

```
TickSystem.tick_elapsed(delta: float) → GameClock 更新显示
EventBus.game_state_changed(new_state) → 切换暂停/播放图标
```

---

## 资源栏 (ResourceBar)

### 布局

- 位置：模式选择器上方，或与模式选择器同一行（TBD）

### 显示资源（由 config 驱动）

```json
{
  "resources": [
    { "id": "money", "label": "金钱", "icon": "res://..." },
    { "id": "crop_yield", "label": "作物产量", "icon": "res://..." },
    { "id": "population", "label": "人口", "icon": "res://..." }
  ]
}
```

### 信号

```
EventBus.resource_updated(resource_id, new_value, delta) → ResourceBar 更新对应 Label
```

---

## HUD 场景树（hud.tscn）

```
hud (Control, stretch to full viewport)
├── TopBar (MarginContainer)
│   └── HBoxContainer
│       ├── GameClock (PanelContainer)
│       ├── SpacerLeft (Control, expand X)
│       ├── ResourceBar + ModeSelector (VBoxContainer)
│       │   ├── ResourceBar (HBoxContainer)
│       │   └── ModeSelector (HFlowContainer)
│       ├── SpacerRight (Control, expand X)
│       └── Minimap (PanelContainer)
│
├── InfoPanel (PanelContainer, 左侧)
│
├── NotificationBar (ScrollContainer, 右侧)
│
└── ActionBar (HBoxContainer, 底部居中)
```

> **说明**：ResourceBar 和 ModeSelector 可以用一个 `VBoxContainer` 包裹，放在头顶居中位置。ResourceBar 在上行（显示金钱、产量、人口等），ModeSelector 在下行（模式选择方框）。

---

## 交互规则

### 鼠标穿透

HUD 的 `mouse_filter` 需设置正确：
- 按钮类（ModeSelector 方框、ActionBar 按钮）→ `MOUSE_FILTER_STOP`（拦截点击）
- 纯显示类（ResourceBar 标签、GameClock 标签）→ `MOUSE_FILTER_IGNORE`（鼠标穿透到游戏世界）
- 容器 → `MOUSE_FILTER_PASS`（传递）

### 快捷键处理优先级

1. Debug 控制台（`/`, `F3`, `F4`, `F5`）— 最高优先级
2. Overlay 界面的快捷键（仅在对应 Overlay 打开时生效）
3. HUD 快捷键（ActionBar、ModeSelector）
4. 游戏世界快捷键

### Esc 键处理流程

```
Esc 按下
  ├── ContextMenu 打开? → 关闭 ContextMenu
  ├── Overlay 打开? → 关闭当前 Overlay
  ├── 有选中对象? → 取消选中（切换回光标模式）
  └── 无选中? → 打开设置/暂停菜单
```

> 注：ModeSelector 若当前模式非光标模式，Esc 应将其切换回光标模式而非直接取消选中。具体行为在 `mode_selector.gd` 的 `_input` 中处理。

---

## 关联文档

- [11.1玩家UI系统.md](11.1玩家UI系统.md) — UI 整体框架与层级架构
- [mode_selector.md](mode_selector.md) — 模式选择器详细设计
- [../autoload/event_bus.md](../autoload/event_bus.md) — 全局事件总线
- [../autoload/tick_system.md](../autoload/tick_system.md) — Tick 系统
- [../../scripts/ui/hud.gd](../../scripts/ui/hud.gd) — HUD 控制器脚本（待创建）
