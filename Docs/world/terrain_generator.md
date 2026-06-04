# TerrainGenerator

挂载在 `world` 场景根节点，负责在游戏启动时按指定的生成模式生成地图网格。地形配置从外部 JSON 文件加载，便于扩展新地块类型。

## 用途

- 根据 `generation_mode` 选择对应的生成算法铺满地图
- 实例化 JSON 配置中指定的 tile 场景铺满地图
- 为每个地块附加 `TileInfo` 数据资源
- 支持自定义种子、地图尺寸、配置文件路径

## 生成模式

| 模式 | 枚举值 | 说明 |
|------|--------|------|
| `ALL_RANDOM` | `0` | 全随机 — 遍历所有网格，按配置中的权重随机选取地块类型 |
| `ISLAND` | `1` | 岛屿 — 中心陆地 + 周围水域（**待实现**，当前降级为占位网格） |

通过 `GenerationMode` 枚举扩展新模式：添加枚举值 → 实现 `_generate_xxx()` → 在 `generate()` 的 `match` 中增加分支。

## 降级策略

当配置文件缺失、场景路径无效或加载失败时，系统按以下优先级降级：

1. 配置指定场景 → `res://scenes/debug/null_img.tscn` 占位场景
2. 占位场景也不可用 → `generate()` 报错，不生成任何地块

所有降级操作均通过 `push_error` / `push_warning` 输出到 Godot 调试器。

## 依赖

| 依赖 | 说明 |
|------|------|
| `res://resources/world/terrain_config.json` | 地形配置文件（地块类型 → 场景路径 + 权重） |
| `res://scenes/debug/null_img.tscn` | 降级占位场景（资源缺失时使用） |
| `res://scripts/world/tile_data.gd` | TileInfo 资源类（预加载访问枚举和 new） |
| `EventBus` | 生成完成后发出 `terrain_generated` 信号 |

## 配置文件格式

`resources/world/terrain_config.json`：

```json
{
  "dirt": {
    "scene": "res://scenes/world/dirt_1.tscn",
    "weight": 0.45
  },
  "stone": {
    "scene": "res://scenes/world/stone_1.tscn",
    "weight": 0.25
  },
  "ocean": {
    "scene": "res://scenes/world/ocean_1.tscn",
    "weight": 0.30
  }
}
```

- 键名（`dirt` / `stone` / `ocean`）对应 `TileInfo.TileType` 枚举，由 `_key_to_tile_type()` 映射
- `scene` — 地块 PackedScene 路径
- `weight` — 在全随机模式下的出现权重
- 添加新地块类型只需在 JSON 中增加条目并在 `_key_to_tile_type()` 中添加映射

## 公开 API

### @export 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `generation_mode` | `GenerationMode` | `ALL_RANDOM` | 地形生成模式 |
| `map_width` | `int` | `32` | 地图宽度（列数） |
| `map_height` | `int` | `32` | 地图高度（行数） |
| `tile_size` | `int` | `64` | 单个地块像素大小 |
| `seed` | `int` | `0` | 随机种子，0 = 每次随机 |
| `config_path` | `String` | `res://resources/world/terrain_config.json` | 地形配置文件路径 |
| `notify_on_complete` | `bool` | `true` | 是否广播 terrain_generated 事件 |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `generate()` | `void` | 清除已有地块并重新生成（可在运行时调用） |
| `get_tile_data_at(grid_x: int, grid_y: int)` | `Resource` | 查询指定坐标的 TileInfo 资源，无则返回 null |

## 地块命名规则

每个生成的 tile 节点命名为 `tile_X_Y`，其中 X 为列号、Y 为行号，从 `(0, 0)` 到 `(map_width-1, map_height-1)`。

通过 `get_node("tile_%d_%d" % [x, y])` 可直接查找。

## 扩展新生成模式

1. 在 `GenerationMode` 枚举中添加新值
2. 实现对应的 `_generate_xxx()` 私有方法
3. 在 `generate()` 的 `match` 分支中调用该方法

示例（添加基于噪声的生成模式）：

```gdscript
enum GenerationMode {
    ALL_RANDOM,
    NOISE_BASED,  ## 基于噪声的地形生成
}

func generate() -> void:
    # ...
    match generation_mode:
        GenerationMode.ALL_RANDOM:
            _generate_all_random()
        GenerationMode.NOISE_BASED:
            _generate_noise_based()

func _generate_noise_based() -> void:
    # 使用 FastNoiseLite 生成连续地形...
    pass
```

## 使用示例

```gdscript
# 在编辑器中调整 world 节点属性即可，无需写代码
# _ready() 自动调用 generate()

# 运行时重新生成（不同种子和模式）
var world := get_node("/root/Node2D/world") as Node2D
world.map_width = 64
world.map_height = 64
world.seed = 42
world.generation_mode = TerrainGenerator.GenerationMode.ALL_RANDOM
world.generate()

# 查询地块
var tile := world.get_tile_data_at(10, 5)
if tile:
    print(tile.get_type_name())  # "泥土" / "石头" / "水面"
```

## 关联文档

- [Docs/整体设计.md](../整体设计.md)
- [Docs/地块系统/1.3地形生成器.md](../地块系统/1.3地形生成器.md)
- [Docs/world/tile_data.md](tile_data.md)