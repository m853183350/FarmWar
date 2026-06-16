# CropPicker（作物选择器）

弹出式 UI 组件。在种植模式（PLANT_FAMILY）下，玩家框选地块后弹出本面板，列出指定植物科下所有已解锁作物，供玩家点击选择。

> 类名：`CropPicker`，继承 `CanvasLayer`
> 场景路径：`res://scenes/ui/popup/crop_picker.tscn`

---

## 设计动机

玩家在顶部 ModeSelector 选择植物科模式（如"禾本科"）后框选地块，需要从该科下选择一个具体作物来种植。CropPicker 提供这个中间选择步骤——它在框选完成后弹出，列出该科所有已解锁作物，玩家点击即选定。

## 用途

- 植物科模式下，在玩家确定"种什么"之前阻止误操作
- 作物数据从 `config/crops/` 目录一次性加载到内存，后续筛选免 IO
- 提供 `set_crop_unlocked()` 接口供科技树等外部系统控制可选范围

## 依赖

| 依赖 | 说明 |
|------|------|
| `config/crops/` | 作物配置 JSON 文件目录 |
| 无其他 autoload 依赖 | 纯 UI 组件，通过信号与外部通信 |

## 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `crop_selected` | `crop_id: String` | 玩家选中了作物 |
| `picker_cancelled` | — | 玩家取消选择（点击取消按钮或遮罩） |

## 公开 API

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `show_for_family(family_id: String)` | `void` | 显示指定植物科作物列表，无可用作物时自动取消 |
| `set_crop_unlocked(crop_id: String, unlocked: bool)` | `void` | 设置指定作物的解锁状态 |

#### show_for_family(family_id)

从缓存的 `all_crops` 中筛选已解锁且 `plant_family` 匹配的作物，填充到列表中。若该科下无可用作物，自动发出 `picker_cancelled` 并 `queue_free()`。

#### set_crop_unlocked(crop_id, unlocked)

供外部系统（如科技树）控制可选作物范围。设置后，下次 `show_for_family()` 时生效。

### 变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `all_crops` | `Array[Dictionary]` | 全部作物数据的内存缓存（公开，供外部查询） |

## UI 结构

```
CanvasLayer (layer=100002, 在 TileContextMenu 之上)
├── ColorRect (Blocker)          # 全屏半透明遮罩，点击取消
└── Panel (360×480, 居中)
    └── VBoxContainer
        ├── Label (Title)        # "选择作物 — Poaceae"
        ├── HSeparator
        ├── ScrollContainer
        │   └── VBoxContainer (CropList)
        │       ├── Button       # 作物卡片（图标 + 名称 + 描述）
        │       ├── Button
        │       └── ...
        ├── HSeparator
        └── Button (取消)
```

### 作物卡片

每个作物显示为一个按钮：
- **左侧**：图标（48×48 PlaceholderTexture2D，后续替换为作物预览图）
- **右侧**：名称 + 描述/等级

点击任意作物卡片 → 发出 `crop_selected(crop_id)` → `queue_free()`

## 作物配置格式

作物 JSON 文件位于 `config/crops/`，示例：

```json
{
  "crop_id": "wheat_tier1",
  "crop_name": "小麦",
  "plant_family": "Poaceae",
  "tier": 1,
  "description": "基础粮食作物，生长周期短",
  "scene_path": "res://scenes/crops/plants/wheat_tier1.tscn",
  "unlocked": true
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `crop_id` | `String` | 作物唯一标识 |
| `crop_name` | `String` | 显示名称 |
| `plant_family` | `String` | 所属植物科（如 `"Poaceae"`） |
| `tier` | `int` | 等级 |
| `description` | `String` | 描述文本 |
| `scene_path` | `String` | 作物场景路径 |
| `unlocked` | `bool` | 是否已解锁（默认 `true`，可通过 `set_crop_unlocked` 控制） |

## 完整交互流程

```
玩家点击顶部 ModeSelector → 植物科模式（如 "Poaceae"）
    ↓ TileSelector 切换到 PLANT_FAMILY 模式
    ↓
玩家框选目标地块
    ↓
TileSelector._handle_plant_family(tiles)
    ├── 实例化 CropPicker
    ├── 连接 crop_selected → _on_crop_selected
    ├── 连接 picker_cancelled → _on_picker_cancelled
    └── picker.show_for_family("Poaceae")
    ↓
CropPicker 显示，列出"小麦"等禾本科作物
    ↓
玩家点击"小麦"
    ↓ CropPicker.crop_selected.emit("wheat_tier1")
    ↓ CropPicker queue_free()
    ↓
TileSelector._on_crop_selected("wheat_tier1", tiles)
    └── FarmlandManager.assign_tiles(tiles, "wheat_tier1")
    └── 工人自动开始耕作循环
```

## 使用示例

```gdscript
# 创建并显示作物选择器
var picker: CropPicker = CROP_PICKER_SCENE.instantiate()
add_child(picker)
picker.crop_selected.connect(_on_crop_selected)
picker.picker_cancelled.connect(_on_picker_cancelled)
picker.show_for_family("Poaceae")

func _on_crop_selected(crop_id: String) -> void:
    print("玩家选择了: %s" % crop_id)
    FarmlandManager.assign_tiles(selected_tiles, crop_id)

func _on_picker_cancelled() -> void:
    print("玩家取消了作物选择")

# 通过科技树控制可选作物
# 例：玩家解锁小麦后才能在小黑麦科中选择
picker.set_crop_unlocked("wheat_tier1", true)
```

## 视觉参数

| 属性 | 值 | 说明 |
|------|-----|------|
| CanvasLayer layer | 100002 | 在 TileContextMenu（100001）之上 |
| Panel 尺寸 | 360×480 | 固定大小 |
| 遮罩颜色 | `rgba(0,0,0,0.3)` | 半透明黑 |
| 面板背景 | `rgba(26,26,38,0.95)` | 深色半透明 |
| 面板边框 | `rgba(102,102,128,0.8)` | 圆角 8px |
| 标题字色 | `rgba(230,217,153)` | 淡金色 |
| 卡片高度 | 56px | 每个作物按钮 |
| 图标尺寸 | 48×48 | 占位图标 |

## 关联文档

- [../mode_selector.md](../mode_selector.md) — 模式选择器（触发 PLANT_FAMILY 模式）
- [../../autoload/farmland_manager.md](../../autoload/farmland_manager.md) — 农田管理器（接收 crop_selected 结果）
- [../../autoload/event_bus.md](../../autoload/event_bus.md) — EventBus.mode_changed 信号
