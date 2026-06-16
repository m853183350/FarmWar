# DebugUI — 调试 UI 系统

运行时调试信息叠加层系统，由 `DebugUI` autoload 统一管理。按 F3 开关显示，F4/F5 翻页。不阻挡任何游戏操作（鼠标事件穿透），纯文本展示当前世界/系统状态数据。

---

## 架构

```
DebugUI (Node)
├── DebugOverlay (CanvasLayer, Layer 5)        ← 右侧面板，通用调试数据
└── DebugOverlayLeft (CanvasLayer, Layer 5)    ← 左侧面板，工人任务等结构化数据
```

| 节点 | 类型 | 说明 |
|------|------|------|
| `DebugUI` | `Node` (autoload) | 总控制器，统一处理 F3/F4/F5 输入 |
| `DebugOverlay` | `CanvasLayer` (autoload) | 右侧面板，独立渲染层 Layer 5，位于屏幕右侧（宽度 1/3） |
| `DebugOverlayLeft` | `CanvasLayer` (autoload) | 左侧面板，独立渲染层 Layer 5，位于屏幕左侧（宽度 1/3） |

**输入流：** `DebugUI._input()` 捕获 F3/F4/F5 → 调用子面板的 `show_overlay()` / `hide_overlay()` / `page_up()` / `page_down()` 公共方法。

**数据流：** 各系统直接通过 autoload 名称（`DebugOverlay`、`DebugOverlayLeft`）写入数据，无需经过 `DebugUI` 中转。

---

## 面板控制 API（DebugUI）

```gdscript
## 显示所有调试叠加层。
func show_all() -> void

## 隐藏所有调试叠加层。
func hide_all() -> void

## 切换所有调试叠加层的可见性。
func toggle_all() -> void

## 所有面板同步上一页。
func page_up_all() -> void

## 所有面板同步下一页。
func page_down_all() -> void
```

### 面板公共方法（由 DebugUI 调用，也可单独调用）

```gdscript
## 显示叠加层面板。
func show_overlay() -> void

## 隐藏叠加层面板。
func hide_overlay() -> void

## 上一页。
func page_up() -> void

## 下一页。
func page_down() -> void
```

---

## 输入处理

所有按键在 `DebugUI._input(event)` 中集中处理：

| 按键 | 条件 | 行为 |
|------|------|------|
| `F3` | — | 同时切换左右面板可见性（show/hide） |
| `F4` | 任一面板可见 + 有上一页 | 左右面板同步上一页 |
| `F5` | 任一面板可见 + 有下一页 | 左右面板同步下一页 |

- 按键事件消费后调用 `set_input_as_handled()` 防止穿透到游戏层。
- 其他所有输入事件不处理，穿透到下层——**叠加层不阻挡任何操作**。

---

## 数据结构（DebugOverlay / DebugOverlayLeft 共用模型）

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

---

## 显示规则

### 排序

每帧刷新时，将 `_data` 的 keys 取出，**按 key 字符串的字母序（case-insensitive）升序排列**，再依次渲染。

### 行格式

```
key: value
```

- key 与 value 之间用 `": "`（冒号+空格）分隔
- 不固定宽度，左对齐

### 分页

若全部内容无法在一屏内显示（总行数超出一页容纳量），启用分页：

| 按键 | 功能 |
|------|------|
| `F4` | 上一页（Page Up） |
| `F5` | 下一页（Page Down） |

分页行为：
- 计算显示区域高度和字体行高，得出每页最大行数
- 维护 `_current_page: int`（从 0 开始）
- 底部显示页码指示器：`[当前页/总页数]`
- 翻页到边界时 clamp（第一页不能再往上，最后一页不能再往下）
- 数据更新导致总页数变化时，若当前页超出新总页数，自动 clamp 到最后一页

---

## 文件规划

| 文件 | 路径 | 说明 |
|------|------|------|
| 脚本 | `scripts/ui/debug_ui.gd` | 总控制器：输入、层级、面板管理 |
| 脚本 | `scripts/ui/debug_overlay.gd` | 右侧面板：数据存储、渲染 |
| 脚本 | `scripts/ui/debug_overlay_left.gd` | 左侧面板：数据存储、渲染 |
| 注册 | `project.godot` autoload 列表 | `DebugUI`、`DebugOverlay`、`DebugOverlayLeft` |

---

## 公开 API（数据操作 — 左右面板相同）

```gdscript
## 设置一个调试数据条目。key 已存在则覆盖 value。
func set_entry(key: String, value: Variant) -> void

## 移除一个调试数据条目。key 不存在时不报错。
func remove_entry(key: String) -> void

## 获取某个条目的值（返回 String）。key 不存在返回空字符串。
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

---

## 外观规格

| 属性 | 值 |
|------|-----|
| CanvasLayer 层级 | 5（Debug 层） |
| 字体 | 系统默认等宽字体（`font_size = 11`） |
| 背景色 | `#1A1A1ACC`（深灰，~80% 不透明） |
| 背景圆角 | 4px |
| 内边距 | 水平 8px，垂直 6px |
| 行间距 | 2px |
| Key 颜色 | `#AAAAAA`（中灰） |
| Value 颜色 | `#FFFFFF`（白） |
| 页码颜色 | `#888888`（暗灰） |
| 鼠标过滤 | `MOUSE_FILTER_IGNORE`（事件穿透） |
| 默认可见性 | 隐藏 |
| 右侧面板宽度 | 约 1/3 屏幕宽，右上角 |
| 左侧面板宽度 | 约 1/3 屏幕宽，左侧 |

---

## 数据来源

各系统通过 autoload 的公开方法写入。数据写入方与叠加层解耦——叠加层不关心数据来自哪个系统，只负责展示。

| key | value 示例 | 写入方 | 面板 |
|-----|-----------|--------|------|
| `tick` | `"1420"` | `debugger.gd` | 右 |
| `tick_ms` | `"1.23"` | `debugger.gd` | 右 |
| `Storage` | `(仓库内容)` | `storage.gd` | 右 |
| `W00_id` | `"worker_01"` | `debugger.gd` | 左 |
| `W00_state` | `"WORKING"` | `debugger.gd` | 左 |
| `W00_t00` | `任务摘要` | `debugger.gd` | 左 |
| `ZZ_pending_count` | `3` | `debugger.gd` | 左 |

---

## 使用示例

```gdscript
# 写入右侧面板（通用调试数据）
DebugOverlay.set_entry("fps", Engine.get_frames_per_second())
DebugOverlay.set_entry("tick", TickSystem.current_tick)
DebugOverlay.set_entry("camera_zoom", "%.2f" % camera.zoom.x)

# 写入左侧面板（结构化数据）
DebugOverlayLeft.set_entry("W00_id", "worker_01")
DebugOverlayLeft.set_entry("W00_state", "WORKING")

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

# 控制面板（通常由 DebugUI 自动处理，也可手动调用）
DebugUI.show_all()
DebugUI.hide_all()
DebugUI.toggle_all()
DebugUI.page_up_all()
DebugUI.page_down_all()
```

---

## 刷新策略

采用方案 A：**每帧刷新**。

```gdscript
func _process(_delta: float) -> void:
    if not visible:
        return
    _render()
```

- 优点：实现简单，数据总是最新
- 缺点：每帧都在重建文本，有微小性能开销
- 调试叠加层仅在开发阶段启用，开销可忽略不计

---

## 待扩展

| 扩展方向 | 说明 |
|---------|------|
| 多区域 | 底部、全屏等更多显示区域 |
| 图表模式 | FPS 折线图、tick 时间线等图形化展示 |
| 分组/折叠 | key 按前缀分组（`crop.*`, `unit.*`），支持折叠 |
| 颜色标记 | value 根据阈值变色（如 FPS < 30 变红） |
| 持久化配置 | 哪些条目默认显示，保存到 `config/` |
| 指令交互 | 在叠加层上直接输入指令修改数据 |

---

## 关联文档

- [Docs/整体设计.md](../整体设计.md) — 调试系统章节
- [Docs/ui/11.1玩家UI系统.md](11.1玩家UI系统.md) — UI 分层架构（Layer 5 Debug）
- [Docs/autoload/debug_console.md](../autoload/debug_console.md) — 调试控制台（同属 Debug 层）
- [Docs/目录结构.md](../目录结构.md) — 文件存放位置
