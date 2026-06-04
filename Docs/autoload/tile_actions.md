# TileActions（地块操作工具）

Autoload 全局单例，提供地块转化（翻耕、挖掘等）的底层方法。可供 UI、AI、脚本等任意系统直接调用。

> 通过 Autoload 全局访问：`TileActions`

## 用途

- 执行地块类型转化（DIRT → FARMLAND、STONE → DIRT 等）
- 管理转化规则配置（JSON 驱动，新增转化类型无需改代码）
- 继承转化前后的关键属性（如 fertility、moisture）
- 转化完成后通过 EventBus 广播事件

## 依赖

| 依赖 | 说明 |
|------|------|
| `config/tile_conversions.json` | 地块转化映射配置 |
| `EventBus` | 转化完成后发出 `tile_action_completed` 信号 |
| `TileInfo` | 创建转化后的地块数据资源 |
| group `"world"` | 通过 group 查找 world 节点（也可手动传入） |

## 公开 API

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `plow_tiles(tiles: Array, world_override: Node2D = null)` | `int` | 翻耕：将可翻耕地块转化为农田。返回成功数。 |
| `dig_tiles(tiles: Array, world_override: Node2D = null)` | `int` | 挖掘：将可挖掘地块转化为普通土壤。返回成功数。 |

#### plow_tiles(tiles, world_override)

将指定网格坐标上的可翻耕地块转化为农田（DIRT → FARMLAND）。

- **转化规则**：来自 `config/tile_conversions.json` 的 `"plow"` 段
- **属性继承**：fertility 和 moisture 从源地块继承
- **已农田**：沙地（sand 变种）已是农田，不会被二次转化
- `tiles`：`Array[Vector2i]` — 网格坐标数组
- `world_override`：手动指定 world 节点，为 null 时通过 group `"world"` 自动查找
- 返回：实际成功转化的地块数量

#### dig_tiles(tiles, world_override)

将指定网格坐标上的可挖掘地块转化为普通土壤（STONE → DIRT）。

- **转化规则**：来自 `config/tile_conversions.json` 的 `"dig"` 段
- **资源产出**：从 StoneTile 实例的 `get_dig_produce()` 获取石材数量
- `tiles`：`Array[Vector2i]` — 网格坐标数组
- `world_override`：手动指定 world 节点
- 返回：实际成功挖掘的地块数量

### @export 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `notify_on_action` | `bool` | `true` | 转化完成后是否通过 EventBus 广播事件 |

## 配置文件格式

`config/tile_conversions.json`：

```json
{
  "plow": [
    {
      "_comment": "翻耕：土质地面 → 农田",
      "source": "res://scenes/world/dirt_1.tscn",
      "target": "res://scenes/world/farmland_1.tscn"
    }
  ],
  "dig": [
    {
      "_comment": "挖掘：石质地面 → 普通土壤",
      "source": "res://scenes/world/stone_1.tscn",
      "target": "res://scenes/world/dirt_1.tscn"
    }
  ]
}
```

- **顶层 key**：操作类型名称（对应 EventBus 的 action 参数和菜单 action 值）
- **source**：源地块场景路径（`Node2D.scene_file_path`），只匹配完全相同的场景实例
- **target**：目标地块场景路径，必须是有效的 PackedScene
- **_comment**：注释字段（代码忽略此字段）

### 扩展新转化类型

只需在 JSON 中添加新的操作段，无需修改代码：

```json
{
  "plow": [ ... ],
  "dig": [ ... ],
  "fill": [
    {
      "_comment": "填平：浅水 → 普通土壤",
      "source": "res://scenes/world/ocean_1.tscn",
      "target": "res://scenes/world/dirt_1.tscn"
    }
  ]
}
```

然后在任意位置调用 `TileActions.fill_tiles(tiles)`（如果通用性高，可在 TileActions 中添加对应的公开方法）。

## 事件流

```
TileSelector 框选 → 上下文菜单点击"翻耕"
  → EventBus.tile_action_triggered.emit("plow", tiles)
  → TerrainGenerator._on_tile_action_triggered() 监听到
  → TileActions.plow_tiles(tiles, world)
  → 遍历 tiles，检查 scene_file_path 匹配 config 的 source
  → 匹配成功：实例化 target 场景，继承属性，替换节点
  → EventBus.tile_action_completed.emit("plow", tiles, count)
```

## 调用示例

```gdscript
# 任何脚本中直接调用（通过 Autoload）
var tiles: Array[Vector2i] = [Vector2i(3, 5), Vector2i(4, 5), Vector2i(3, 6)]
var count: int = TileActions.plow_tiles(tiles)
print("翻耕了 %d 个地块" % count)

# 手动指定 world 节点（如测试或特殊场景）
var custom_world: Node2D = get_node("/root/MyTestWorld")
TileActions.plow_tiles(tiles, custom_world)

# 挖掘
TileActions.dig_tiles(tiles)
```

## 关联文档

- [Docs/地块系统/1.1地块系统.md](../地块系统/1.1地块系统.md) — 地块系统架构与转化规则
- [Docs/地块系统/1.2主要地块类型.md](../地块系统/1.2主要地块类型.md) — 地块类型属性
- [Docs/autoload/event_bus.md](event_bus.md) — EventBus 信号定义
- [Docs/ui/11.1玩家UI系统.md](../ui/11.1玩家UI系统.md) — 上下文菜单交互
