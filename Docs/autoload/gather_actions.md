# GatherActions（采集动作判定器）

Autoload 全局单例。根据地块类型和内容物判定适用的采集动作，生成 TaskData 供工人执行。采集规则从 `config/terrain_config.json` 的 `gather_actions` 键加载。

> 通过 Autoload 全局访问：`GatherActions`

---

## 设计动机

在引入本系统之前，"采集"是一个笼统的概念——需要预先知道地块上有什么才能决定做什么操作。引入 GatherActions 后，**系统自动根据地块类型和内容物匹配采集规则**，玩家只需在采集模式下框选地块，工人自动执行正确的操作（挖石头、砍树、钓鱼等）。

## 用途

- 自动判定地块适用的采集动作（挖掘、砍伐、钓鱼等）
- 规则从配置文件加载，新增地形类型或采集动作无需修改代码
- 通过 `tile_type` 匹配地形类型（兼容 TSCN 和程序化创建的地块）
- 生成 TaskData 供 UnitManager 分配
- 通过 EventBus 发出 `gather_action_triggered` 供 UI 反馈和音效

## 依赖

| 依赖 | 说明 |
|------|------|
| `config/terrain_config.json` | 采集规则配置（`gather_actions` 键，在 `tiles` 下） |
| `EventBus` | 发出 `gather_action_triggered` 信号 |
| `TaskData` | 生成采集任务 |
| group `"world"` | 通过 group 查找 world 节点 |

## 公开 API

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `determine_and_create_tasks(tiles: Array[Vector2i])` | `Array[TaskData]` | 判定所选地块的采集动作，生成任务数组 |

#### determine_and_create_tasks(tiles)

遍历每个地块，按地形类型匹配采集规则，为匹配成功的地块创建 `GATHER` 或 `DIG` 类型任务。无法匹配任何规则的地块被跳过。

返回的 TaskData 包含 `params`：
- `gather_action`: 采集动作标识（如 `"dig"`、`"chop"`、`"fish"`）
- `rule_id`: 匹配到的规则 ID

完成后通过 EventBus 发出 `gather_action_triggered` 信号。

## 配置格式

采集规则在 `config/terrain_config.json` 的 `tiles.<type>.gather_actions` 下：

```json
{
  "texture_dir": "res://assets/sprites/tiles/",
  "null_texture": "res://assets/sprites/null_img.png",
  "script_dir": "res://scripts/world/tiles/",
  "tiles": {
    "dirt": {
      "weight": 0.60,
      "name": "泥土",
      "tile_type": 0,
      "default_variant": "soil",
      "tags": [],
      "defaults": { ... },
      "variants": { ... },
      "gather_actions": [
        {
          "id": "chop_tree",
          "name": "砍伐树木",
          "gather_action": "chop",
          "task_type": "GATHER",
          "conditions": [
            { "type": "has_occupant", "value": "Tree" }
          ]
        }
      ]
    }
  }
}
```

### 规则字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `String` | 规则唯一标识 |
| `name` | `String` | 显示名称 |
| `gather_action` | `String` | 动作标识（`"dig"`、`"chop"`、`"fish"` 等） |
| `task_type` | `String` | 任务类型：`"GATHER"` 或 `"DIG"` |
| `conditions` | `Array` | 匹配条件列表（AND 逻辑） |

### 条件类型

| type | 参数 | 说明 |
|------|------|------|
| `has_occupant` | `value: String` | 地块上是否存在指定类型的内容物（如 `"Tree"`） |
| `property` | `key: String, value: Variant` | 地块的 meta 属性是否等于指定值（如 `fishable=true`） |

### 规则匹配流程

```
determine_and_create_tasks(tiles)
    │
    └── for each tile:
        │
        ├── 通过 tile_type → terrain_key 反向查找地形类型（兼容 TSCN 和程序化地块）
        │
        ├── 遍历该地形的 gather_actions 规则（按数组顺序 = 优先级）
        │
        └── 第一个条件全部匹配的规则 → 生成 TaskData
            │
            ├── has_occupant: 检查 tile.has_occupant_of_type(value)
            └── property: 检查 tile.get_meta(key) == value
```

## 扩展新采集动作

只需在 `terrain_config.json` 中添加 `gather_actions` 条目，无需修改代码：

```json
"dirt": {
  "gather_actions": [
    {
      "id": "chop_tree",
      "name": "砍伐树木",
      "gather_action": "chop",
      "task_type": "GATHER",
      "conditions": [
        { "type": "has_occupant", "value": "Tree" }
      ]
    },
    {
      "id": "pick_berry",
      "name": "采摘浆果",
      "gather_action": "pick",
      "task_type": "GATHER",
      "conditions": [
        { "type": "has_occupant", "value": "BerryBush" }
      ]
    }
  ]
}
```

新动作类型的具体执行逻辑（在 FarmWorker 中匹配 `gather_action` 字符串）需同步添加。

## 日志示例

```
# 玩家进入采集模式，框选 3 块石头
[TileSelector] 采集模式：正在判定 3 块地块的采集动作...
[GatherActions] 地块 (5,3): 匹配规则 "dig_stone" → 挖掘石材
[GatherActions] 地块 (6,3): 匹配规则 "dig_stone" → 挖掘石材
[GatherActions] 地块 (5,4): 匹配规则 "dig_stone" → 挖掘石材
[GatherActions] 已创建 3 个采集任务
[TileSelector] 采集派遣 3/3 个任务
```

## 关联文档

- [event_bus.md](event_bus.md) — EventBus 信号（`gather_action_triggered`）
- [farmland_manager.md](farmland_manager.md) — 农田管理器（种植类操作的对应系统）
- [../units/3.2农场工人单位.md](../units/3.2农场工人单位.md) — 农场工人（执行采集任务）
- [../../config/terrain_config.json](../../config/terrain_config.json) — 采集规则配置
