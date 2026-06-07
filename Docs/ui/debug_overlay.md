# DebugOverlay — 调试叠加层

运行时调试信息叠加层，挂载在 Layer 5（Debug 层），按 F3 开关显示。不阻挡任何游戏操作（鼠标事件穿透），纯文本展示当前世界/系统状态数据。

---

## 用途

- 开发阶段快速查看关键运行时数据（FPS、tick 计数、选中对象信息等）
- 各系统可将诊断信息注入叠加层，无需各自创建独立 UI
- 不干扰正常游戏操作——鼠标点击/拖拽直接穿透到下层

---

## 设计概览

```
┌──────────────────────────────────────────────────────────┐
│                                                  ┌──────┐│
│                                                  │Debug ││
│                                                  │Overlay││
│                                                  │      ││
│                                                  │ key1 ││
│                                                  │  val ││
│                                                  │ key2 ││
│                                                  │  val ││
│                                                  │ ...  ││
│                                                  │      ││
│                                                  │[1/3] ││
│                                                  └──────┘│
│                              ≈ 1/3 屏幕宽                  │
└──────────────────────────────────────────────────────────┘
```

| 属性 | 值 |
|------|-----|
| CanvasLayer 层级 | 5（Debug 层，与调试控制台同级） |
| 位置 | 右上角，右对齐 |
| 宽度 | 约 1/3 屏幕宽（~640px @ 1920×1080） |
| 高度 | 自适应内容，最大不超过屏幕高度 - 边距 |
| 背景 | 半透明黑色（`#00000088`），圆角 |
| 字体 | 小号等宽字体（默认 11px，可配置） |
| 文本颜色 | 白色/浅灰 |
| 鼠标过滤 | `MOUSE_FILTER_IGNORE`（事件穿透） |
| 默认可见性 | 隐藏 |

---

## 数据结构

### 内部存储

```gdscript
## 调试数据字典。key 为 String，value 为任意类型（显示时转 String）。
var _data: Dictionary = {}
```

选择 `Dictionary` 的理由：
- GDScript 原生类型，零额外依赖
- key-value 模型天然支持按标识增/删/改
- 遍历简单，序列化方便

**限制与约定：**
- key 必须是 `String` 类型，建议使用 `snake_case`（如 `fps`, `tick_count`, `selected_tile`）
- value 任意类型，显示时自动调用 `str()` 转换
- 若 value 为 `Callable` 或 `Object` 等无意义字符串化的类型，建议调用方自行转为有意义的字符串再存入

### 数据来源

各系统通过 autoload 的公开方法写入。数据写入方与叠加层解耦——叠加层不关心数据来自哪个系统，只负责展示。

常见数据来源示例：

| key | value 示例 | 写入方 |
|-----|-----------|--------|
| `fps` | `"60"` | 渲染循环 / `_process()` |
| `tick_count` | `"1420"` | `TickSystem` |
| `tick_rate` | `"20/s"` | `TickSystem` |
| `selected_tile` | `"(12, 8) flat_soil"` | 选择系统 |
| `camera_zoom` | `"1.50"` | `CameraController` |
| `unit_count` | `"12/50"` | `UnitManager` |
| `mouse_world_pos` | `"(256, 512)"` | 输入处理 |
| `weather` | `"rain(0.7)"` | `WeatherManager` |

---

## 显示规则

### 排序

每帧刷新时，将 `_data` 的 keys 取出，**按 key 字符串的字母序（case-insensitive）升序排列**，再依次渲染。

```
# 示例：_data 中有 {"zoom": "1.5", "fps": "60", "tick": "100"}
# 排序后显示顺序：fps → tick → zoom
```

> 设计考量：首字母排序 vs 全文排序。首字母排序在中文 key（拼音首字母不同）场景下会让用户困惑为何"种子数"排在"天气"前面。采用全文 case-insensitive 排序，规则透明、可预测。若有特殊排序需求，可通过 key 命名前缀控制（如 `01_fps`, `02_tick`）。

### 行格式

```
key: value
```

- key 与 value 之间用 `": "`（冒号+空格）分隔
- key 部分的显示宽度固定为左对齐不固定宽度（更简单）
- **推荐：不固定宽度，左对齐即可**——调试工具优先简单可靠

### 自动换行

- 使用 `RichTextLabel` 或 `Label` 的 `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART`
- 单行 value 过长时自动折行，折行部分缩进 2 个空格以区分新条目
- 若单条 value 包含多行文本（含 `\n`），原样保留换行

### 分页

若全部内容无法在一屏内显示（总行数超出一页容纳量），启用分页：

| 按键 | 功能 |
|------|------|
| `F4` | 上一页（Page Up） |
| `F5` | 下一页（Page Down） |

分页行为：
- 计算显示区域高度和字体行高，得出每页最大行数 `_lines_per_page`
- 维护 `_current_page: int`（从 0 开始）
- 底部显示页码指示器：`[当前页/总页数]`
- 翻页到边界时 clamp（第一页不能再往上，最后一页不能再往下）
- 数据更新导致总页数变化时，若当前页超出新总页数，自动 clamp 到最后一页

> **F5 冲突说明：** 设计文档中 F5 规划为"快速存档"。在 debug 叠加层可见时，F5 优先触发翻页，快速存档功能被抑制。叠加层隐藏时恢复 F5 的存档功能。这是合理的——debug 叠加层是开发工具，发布版本中不会启用，不存在冲突。

---

## 文件规划

| 文件 | 路径 | 说明 |
|------|------|------|
| 场景 | `scenes/ui/debug_overlay.tscn` | CanvasLayer + RichTextLabel |
| 脚本 | `scripts/ui/debug_overlay.gd` | 显示逻辑、输入处理、数据渲染 |
| 注册 | `project.godot` autoload 列表 | `DebugOverlay` → `res://scenes/ui/debug_overlay.tscn` |

> 注：数据存储直接在场景根节点的脚本中（作为 autoload，天然全局单例）。不需要额外的数据管理 autoload，保持简洁。

---

## 公开 API

```gdscript
## 设置一个调试数据条目。key 已存在则覆盖 value。
func set_entry(key: String, value: Variant) -> void

## 移除一个调试数据条目。key 不存在时不报错。
func remove_entry(key: String) -> void

## 获取某个条目的值（返回 String，因显示时已转换）。key 不存在返回空字符串。
func get_entry(key: String) -> String

## 清空所有条目。
func clear_entries() -> void

## 获取当前所有数据的只读副本。
func get_all_entries() -> Dictionary

## 批量设置条目（合并到现有数据，同名 key 覆盖）。
func set_entries(data: Dictionary) -> void
```

### 信号

```gdscript
## 数据变更时发出。参数为新数据快照。
signal data_changed(data: Dictionary)
```

> `data_changed` 信号主要用于未来扩展（如多区域联动或日志记录），当前阶段叠加层自身通过 `_process` 或直接更新即可，不强制依赖此信号。

---

## 输入处理

叠加层可见时的按键捕获（在 `_input(event)` 中处理）：

| 按键 | 条件 | 行为 |
|------|------|------|
| `F3` | — | 切换可见性（show/hide） |
| `F4` | 可见 + 有上一页 | 上一页 |
| `F5` | 可见 + 有下一页 | 下一页 |

- 按键事件消费后调用 `accept_event()` 防止穿透到游戏层（仅 F3/F4/F5 在 overlay 可见时消费）。
- 其他所有输入事件不处理，穿透到下层——**叠加层不阻挡任何操作**。

---

## 刷新策略

有两种可选方案：目前采用方案A

### 方案 A：每帧刷新（推荐初期）

```gdscript
func _process(_delta: float) -> void:
    if visible:
        _render()
```

- 优点：实现简单，数据总是最新
- 缺点：每帧都在重建文本，有微小性能开销

### 方案 B：按变更刷新

```gdscript
func set_entry(key: String, value: Variant) -> void:
    _data[key] = value
    if visible:
        _render()
```

- 优点：仅在数据变化时重建文本
- 缺点：调用方频繁更新（如每 tick 更新 tick_count）时等同于每帧刷新

**推荐：采用方案 A（每帧刷新）。** 调试叠加层仅在开发阶段启用，每帧渲染一段文本的开销可忽略不计。方案 A 实现简单，无数据同步隐患。若日后性能敏感，再切换为方案 B。

---

## 外观规格

| 属性 | 值 |
|------|-----|
| 字体 | 系统默认等宽字体（`font_size = 11`） |
| 字体颜色 | `#E0E0E0`（浅灰白），且有黑色描边 |
| 背景色 | `#1A1A1ACC`（深灰，~80% 不透明） |
| 背景圆角 | 4px（通过 StyleBoxFlat 或 NinePatchRect） |
| 内边距 | 水平 8px，垂直 6px |
| 行间距 | 2px |
| Key 颜色 | `#AAAAAA`（中灰） |
| Value 颜色 | `#FFFFFF`（白） |
| 页码颜色 | `#888888`（暗灰） |

> 颜色均通过常量定义，方便后续调整为可配置项。

---

## 使用示例

```gdscript
# 在任何系统中写入调试数据
DebugOverlay.set_entry("fps", Engine.get_frames_per_second())
DebugOverlay.set_entry("tick", TickSystem.current_tick)
DebugOverlay.set_entry("camera_zoom", "%.2f" % camera.zoom.x)
DebugOverlay.set_entry("selected", "tile(12,8)")
DebugOverlay.set_entry("units_alive", "%d/%d" % [alive, total])

# 移除不再需要的条目
DebugOverlay.remove_entry("selected")

# 批量设置
DebugOverlay.set_entries({
    "fps": 60,
    "tick": 0,
    "weather": "clear",
})

# 清空
DebugOverlay.clear_entries()
```

---

## 待扩展

当前为"第一块区域"（右上角纯文本面板）。后续可扩展：

| 扩展方向 | 说明 |
|---------|------|
| 多区域 | 支持左侧、底部等更多显示区域，每个区域独立数据源 |
| 图表模式 | FPS 折线图、tick 时间线等图形化展示 |
| 分组/折叠 | key 按前缀分组（`crop.*`, `unit.*`），支持折叠 |
| 颜色标记 | value 根据阈值变色（如 FPS < 30 变红） |
| 持久化配置 | 哪些条目默认显示，保存到 `config/`，写代码时这项先生成，但内容可以留空 |
| 指令交互 | 在叠加层上直接输入指令修改数据（与 DebugConsole 联动） |

---

## 关联文档

- [Docs/整体设计.md](../整体设计.md) — 调试系统章节
- [Docs/ui/11.1玩家UI系统.md](11.1玩家UI系统.md) — UI 分层架构（Layer 5 Debug）
- [Docs/autoload/debug_console.md](../autoload/debug_console.md) — 调试控制台（同属 Debug 层）
- [Docs/目录结构.md](../目录结构.md) — 文件存放位置
