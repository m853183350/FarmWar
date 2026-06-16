# EventBus

Autoload 全局单例。全局事件总线，用于各个游戏系统之间的解耦通信。

## 用途

- 替代直接的跨系统引用，通过信号实现发布-订阅模式
- 系统 A 发出事件，系统 B/C/D 监听，互不依赖
- 降低系统间耦合度，便于测试和维护

## 依赖

- 无外部依赖

## 公开 API

### 信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `terrain_generated` | — | 地形生成完成，地图可用 |
| `game_state_changed` | `new_state: StringName` | 游戏状态变化（如 `paused`、`playing`） |
| `tile_clicked` | `tile: Node2D` | 地块被点击，传递地块节点引用 |
| `tiles_selected` | `tiles: Array` | 地块框选完成，传递网格坐标数组 |
| `tile_action_triggered` | `action: StringName, tiles: Array` | 地块操作菜单项被点击（action: "plow"/"dig"） |
| `tile_action_completed` | `action: StringName, tiles: Array, count: int` | 地块操作完成，count 为成功转化数 |
| `debug_command_executed` | `command: String` | 调试指令被执行 |

### 工人相关信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `worker_task_completed` | `worker_id: StringName, task: TaskData` | 工人完成一个任务 |
| `worker_task_failed` | `worker_id: StringName, task: TaskData, reason: String` | 工人任务执行失败 |
| `worker_queue_empty` | `worker_id: StringName` | 工人任务队列清空 |
| `worker_state_changed` | `worker_id: StringName, old_state: int, new_state: int` | 工人状态变化 |

### 地块分配信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `farmland_assigned` | `tiles: Array, crop_id: String` | 地块被分配给自动耕作系统 |
| `farmland_unassigned` | `tiles: Array` | 地块取消自动耕作分配 |

### 采集动作信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `gather_action_triggered` | `action: StringName, tiles: Array` | 采集动作被触发（"dig"/"chop"/"fish" 等） |

### 作物生长信号

| 信号 | 参数 | 说明 |
|------|------|------|
| `crop_stage_changed` | `crop_node: Node2D, grid_pos: Vector2i, crop_id: String, old_stage: int, new_stage: int, is_mature: bool` | 作物生长阶段变化 |
| `crop_matured` | `crop_node: Node2D, grid_pos: Vector2i, crop_id: String` | 作物达到成熟阶段，可收获 |
| `crop_harvested` | `yields: Array, crop_id: String` | 作物被收获

## 使用示例

```gdscript
# 发出事件
EventBus.terrain_generated.emit()

# 监听事件
func _ready() -> void:
    EventBus.game_state_changed.connect(_on_game_state_changed)

func _on_game_state_changed(new_state: StringName) -> void:
    match new_state:
        &"paused":
            _pause_all_units()
        &"playing":
            _resume_all_units()

# 清理（如果需要）
func _exit_tree() -> void:
    EventBus.game_state_changed.disconnect(_on_game_state_changed)

# 作物成熟 → 自动收获（FarmlandManager 监听）
func _ready() -> void:
    EventBus.crop_matured.connect(_on_crop_matured)

func _on_crop_matured(crop_node: Node2D, grid_pos: Vector2i, crop_id: String) -> void:
    var task: TaskData = TaskData.create(TaskData.TaskType.HARVEST, grid_pos, {"crop_id": crop_id})
    UnitManager.distribute_tasks([task])

# 地块分配 → UI 高亮（UI 层监听）
func _ready() -> void:
    EventBus.farmland_assigned.connect(_highlight_assigned_tiles)
    EventBus.farmland_unassigned.connect(_clear_assigned_highlight)
```

## 扩展指南

新增跨系统事件时，在此文件添加信号声明即可，无需修改其他代码：

```gdscript
## 作物收获完成。
## 由 [Crop.harvest] 发出。
signal crop_harvested(yields: Array, crop_id: String)

## 地块分配给自动耕作系统。
## 由 [FarmlandManager.assign_tiles] 发出。
signal farmland_assigned(tiles: Array, crop_id: String)
```

## 关联文档

- [Docs/整体设计.md](../整体设计.md)
- [Docs/autoload/tick_system.md](tick_system.md)
- [farmland_manager.md](farmland_manager.md) — FarmlandManager（监听 crop_matured、crop_harvested）
- [gather_actions.md](gather_actions.md) — GatherActions（发出 gather_action_triggered）
- [../crops/crop.md](../crops/crop.md) — Crop（发出 crop_stage_changed、crop_matured、crop_harvested）
- [../ui/popup/crop_picker.md](../ui/popup/crop_picker.md) — CropPicker（接收 farmland_assigned 的最终消费者）
