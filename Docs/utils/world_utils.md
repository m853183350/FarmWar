# 世界/地块工具 (WorldUtils)

`WorldUtils` 是世界/地块操作的统一工具类，提供获取世界节点、查找地块、坐标转换、读取地块数据等全局静态方法。避免各处重复编写相同的查找/转换逻辑。

---

## 文件位置

- **脚本**：`scripts/utils/world_utils.gd`
- **类型**：`RefCounted`（纯静态工具，无需实例化）

---

## 使用方式

```gdscript
const WorldUtils = preload("res://scripts/utils/world_utils.gd")

# 获取世界节点
var world: Node2D = WorldUtils.get_world()

# 按网格坐标查找地块节点
var tile: Node2D = WorldUtils.find_tile(world, Vector2i(5, 3))

# 网格坐标转世界坐标（地块中心）
var pos: Vector2 = WorldUtils.tile_to_world(Vector2i(5, 3))

# 获取地块的 TileInfo 数据
var data: Resource = WorldUtils.get_tile_data(tile)
```

---

## 静态方法

### `get_world() -> Node2D`

获取世界节点（通过 group `"world"`）。

通过 `Engine.get_main_loop()` 获取 `SceneTree`，再通过 `get_first_node_in_group("world")` 查找。返回 `null` 表示世界尚未加载。

> **注意**：频繁调用（如每 tick）的类建议在本地缓存结果，避免重复查找。

### `find_tile(world: Node2D, grid_pos: Vector2i) -> Node2D`

在 world 中按网格坐标查找地块节点。

地块节点命名规则：`tile_X_Y`（由 `TerrainGenerator` 保证）。

| 参数 | 类型 | 说明 |
|------|------|------|
| `world` | `Node2D` | 世界节点（通常由 `get_world()` 返回） |
| `grid_pos` | `Vector2i` | 网格坐标 |

返回对应的 `Node2D` 地块节点；若不存在则返回 `null`。

### `tile_to_world(tile: Vector2i, tile_size: int = 64) -> Vector2`

网格坐标转世界坐标（地块中心）。

| 参数 | 类型 | 说明 |
|------|------|------|
| `tile` | `Vector2i` | 网格坐标（行列索引） |
| `tile_size` | `int` | 地块尺寸，默认 64px |

返回像素级世界坐标（地块中心点）。

### `get_tile_data(tile: Node) -> Resource`

从地块节点获取 `TileInfo` 数据。

优先级：
1. 通过 `tile.get_tile_data()` 方法
2. 通过 `tile.get_meta("tile_data")` 元数据

无法获取时返回 `null`。

---

## 引用方

| 文件 | 使用的方法 |
|------|----------|
| `scripts/units/player_units/farm_worker.gd` | `get_world`, `find_tile`, `tile_to_world`, `get_tile_data` |
| `scripts/units/unit_manager.gd` | `get_world` |
| `scripts/autoload/pathfinding_manager.gd` | `get_world`, `get_tile_data` |
| `scripts/autoload/farmland_manager.gd` | `find_tile`, `get_tile_data`（通过 `_resolve_world` 调用 `get_world`） |
| `scripts/autoload/gather_actions.gd` | `get_world`, `find_tile` |
| `scripts/autoload/tile_actions.gd` | `find_tile`（通过 `_resolve_world` 调用 `get_world`） |
| `scripts/world/terrain_generator.gd` | `find_tile`（通过 `_find_tile_node` 包装） |

---

## 相关文件

- [[terrain_generator]] — 地形生成器（地块命名规则的保证方）
- [[tile_data]] — TileInfo 数据结构
- [[base_tile]] — 地块基类
