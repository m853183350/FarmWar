# FarmlandManager（农田管理器）

Autoload 全局单例。管理地块→作物分配关系，驱动工人的**自动耕作循环**（翻耕→种植→等待成熟→收获→补种）。

> 通过 Autoload 全局访问：`FarmlandManager`

---

## 设计动机

在引入本系统之前，耕地→种植→收获需要玩家手动逐步操作（框选地块 → 菜单翻耕 → 等待 → 再框选 → 种植 → 等待 → 再框选 → 收获）。这导致大量重复点击，且玩家容易忘记已翻耕但未种植的空地块。

FarmlandManager 将耕作操作串联为**事件驱动的状态机**，实现"玩家分配一次，工人自动循环到永远"。

## 用途

- 管理地块→作物分配关系（`_assignments` 字典）
- 通过事件驱动状态机推进耕作循环，不依赖 tick 轮询
- 监听 EventBus 信号自动创建下一阶段任务：
  - `worker_task_completed` → PLOW 完成后自动 PLANT，HARVEST 完成后自动补种
  - `crop_matured` → 作物成熟时自动创建 HARVEST 任务
  - `crop_harvested` → 兜底：手动收获已分配地块后自动补种
- 公开查询接口，供 UI 高亮已分配地块

## 依赖

| 依赖 | 说明 |
|------|------|
| `EventBus` | 监听 `worker_task_completed`、`crop_matured`、`crop_harvested`；发出 `farmland_assigned`、`farmland_unassigned` |
| `TaskData` | 创建 PLOW/PLANT/HARVEST 任务 |
| `UnitManager` | 通过 `distribute_tasks()` 分配任务给空闲工人 |
| group `"world"` | 通过 group 查找 world 节点获取地块引用 |
| `Crop` | 通过 `has_occupant_of_type("Crop")`、`is_mature()` 检查地块状态 |

## 公开 API

### 枚举

```gdscript
enum AssignState {
    NEEDS_PLOW,     ## 需要先翻耕（地块是 DIRT）
    NEEDS_PLANT,    ## 可以种植（地块已是 FARMLAND 且无作物）
    GROWING,        ## 作物生长中
    NEEDS_HARVEST,  ## 作物已成熟，等待收获
}
```

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `assign_tiles(tiles: Array[Vector2i], crop_id: String)` | `void` | 将一批地块分配给指定作物，启动自动耕作循环 |
| `unassign_tiles(tiles: Array[Vector2i])` | `void` | 取消指定地块的自动耕作分配 |
| `is_assigned(grid_pos: Vector2i)` | `bool` | 检查地块是否已分配给自动循环 |
| `get_assignment(grid_pos: Vector2i)` | `Dictionary` | 获取地块的分配信息：`{crop_id, state}` |
| `get_tiles_for_crop(crop_id: String)` | `Array[Vector2i]` | 获取所有分配了指定作物的地块坐标 |
| `get_all_assigned_tiles()` | `Array[Vector2i]` | 获取所有已分配地块坐标 |
| `get_assignment_count()` | `int` | 已分配地块总数 |

#### assign_tiles(tiles, crop_id)

将一批地块分配给指定作物，根据每个地块的当前状态创建初始任务：

| 地块状态 | 处理方式 |
|---------|---------|
| DIRT | 分配为 `NEEDS_PLOW` → 创建 PLOW 任务 |
| FARMLAND（空） | 分配为 `NEEDS_PLANT` → 创建 PLANT 任务 |
| FARMLAND（成熟作物） | 分配为 `NEEDS_HARVEST` → 创建 HARVEST 任务 |
| FARMLAND（未成熟作物） | 不操作（保留现有作物） |
| STONE / OCEAN | 跳过（不可耕作） |

### 信号（通过 EventBus 发出）

| 信号 | 参数 | 说明 |
|------|------|------|
| `farmland_assigned` | `tiles: Array, crop_id: String` | 地块被分配给自动耕作 |
| `farmland_unassigned` | `tiles: Array` | 地块取消自动耕作分配 |

## 核心流程

### 自动耕作循环状态机

```
玩家框选地块 → CropPicker 选中作物 → FarmlandManager.assign_tiles()
    │
    ├── 地块是 DIRT ──→ [NEEDS_PLOW]  ──→ PLOW 任务
    │       │                                 │
    │       │  工人完成 PLOW                    │
    │       ▼                                 ▼
    │   [NEEDS_PLANT] ←──────────────────────┘
    │       │
    │       │  PLANT 任务
    │       ▼
    │   [GROWING]  ← 作物在生长，等待成熟
    │       │
    │       │  EventBus.crop_matured（由 Crop._advance_stage 发出）
    │       ▼
    │   [NEEDS_HARVEST] → HARVEST 任务
    │       │
    │       │  工人完成收获
    │       ▼
    │   [NEEDS_PLANT]  ← 自动重新种植！
    │       │
    │       └──→ 回到 [GROWING] → ...（无限循环）
```

### 事件驱动（非轮询）

关键设计：**作物成熟通过 EventBus 信号驱动**，而非 tick 轮询。

```
Crop._advance_stage()             ← TickSystem 驱动生长
    │
    ├── EventBus.crop_stage_changed.emit(..., is_mature)
    └── 若 is_mature → EventBus.crop_matured.emit(crop_node, grid_pos, crop_id)
                              │
                              ▼
              FarmlandManager._on_crop_matured()
                  │
                  ├── 更新分配状态: GROWING → NEEDS_HARVEST
                  └── 创建 HARVEST 任务
```

这消除了旧设计中"收获前需轮询地块"或"延迟推断成熟"的 hack，实现精准的"成熟即收获"。

### 兜底：手动收获自动补种

当通过光标模式手动收获已分配地块时（非工人自动化），`crop_harvested` 信号会被触发，FarmlandManager 检测到已分配的 GROWING 地块失去作物后，自动创建 PLANT 任务补种，确保自动循环不中断。

## 调用示例

```gdscript
# 玩家在 CropPicker 中选中 crop_id，系统触发分配
FarmlandManager.assign_tiles(selected_tiles, "wheat_tier1")

# 之后工人自动处理所有耕作操作，无需玩家干预

# UI 查询已分配地块（用于高亮显示）
var assigned: Array[Vector2i] = FarmlandManager.get_all_assigned_tiles()
for pos in assigned:
    var info: Dictionary = FarmlandManager.get_assignment(pos)
    var state: String = "?" 
    match info.get("state", -1):
        FarmlandManager.AssignState.NEEDS_PLOW:    state = "待翻耕"
        FarmlandManager.AssignState.NEEDS_PLANT:   state = "待种植"
        FarmlandManager.AssignState.GROWING:       state = "生长中"
        FarmlandManager.AssignState.NEEDS_HARVEST: state = "待收获"
    print("地块 %s: %s (%s)" % [pos, info.get("crop_id"), state])

# 取消分配（停止自动循环）
FarmlandManager.unassign_tiles(selected_tiles)
```

## 关联文档

- [event_bus.md](event_bus.md) — EventBus 信号定义
- [gather_actions.md](gather_actions.md) — 采集动作判定（非种植类操作）
- [tile_actions.md](tile_actions.md) — 地块操作工具
- [../ui/popup/crop_picker.md](../ui/popup/crop_picker.md) — 作物选择器 UI
- [../crops/crop.md](../crops/crop.md) — 作物基类（发出 crop_matured 信号）
- [../units/3.2农场工人单位.md](../units/3.2农场工人单位.md) — 农场工人（任务执行者）
