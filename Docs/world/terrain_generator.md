# TerrainGenerator

挂载在 `world` 场景根节点，负责在游戏启动时按指定的生成模式生成地图网格。地形配置从外部 JSON 文件加载，便于扩展新地块类型。

## 用途

- 根据 `generation_mode` 选择对应的生成算法铺满地图
- 支持两种地块创建模式：
  - **TSCN 模式**：配置中指定了 `scene` 的变种，直接实例化 PackedScene
  - **程序化模式**：没有 TSCN 的变种，动态创建 `Sprite2D` 节点并附加纹理和脚本
- 从 `config/terrain_config.json` 读取所有地块数据（通行性、可建造性、肥力、湿度等），注入 `TileInfo`
- 为每个地块附加 `TileInfo` 数据资源
- 支持自定义种子、地图尺寸、配置文件路径

## 生成模式

| 模式 | 枚举值 | 说明 |
|------|--------|------|
| `ALL_RANDOM` | `0` | 全随机 — 遍历所有网格，按配置中的权重随机选取地块类型 |
| `ISLAND` | `1` | 岛屿 — 中心陆地 + 周围水域（**待实现**，当前降级为占位网格） |

通过 `GenerationMode` 枚举扩展新模式：添加枚举值 → 实现 `_generate_xxx()` → 在 `generate()` 的 `match` 中增加分支。

## 双模式地块创建

### TSCN 模式

当变种配置中包含 `scene` 字段时，直接实例化 PackedScene。目前有 TSCN 资源的地块：

| 类型 | 变种 | TSCN 路径 |
|------|------|----------|
| dirt | soil | `res://scenes/world/dirt_1.tscn` |
| stone | hard_stone | `res://scenes/world/stone_1.tscn` |
| ocean | deep | `res://scenes/world/ocean_1.tscn` |
| farmland | soil_farmland | `res://scenes/world/farmland_1.tscn` |

### 程序化模式

当变种配置中无 `scene` 字段时，动态创建 `Sprite2D` 节点，流程：
1. 创建 `Sprite2D` 节点（`texture_filter=1`, `scale=(8,8)`, `centered=false`）
2. 从 `texture_dir` + `texture` 字段加载纹理；若纹理缺失或未指定，使用 `null_texture` 降级
3. 从 `script_dir` + `script` 字段加载脚本，设置到节点上
4. 在 `_ready()` 之前通过 `set()` 设置 `tile_type`、`variant`、`display_name`（子类 `_ready()` 检测已设置则不再覆盖）

### 降级策略

当配置文件缺失、场景路径无效或加载失败时，系统按以下优先级降级：

1. 配置指定场景 → 程序化创建（使用配置中的纹理/脚本）
2. 纹理缺失 → `res://assets/sprites/null_img.png` 占位纹理
3. 占位纹理也不可用 → 无纹理的空白 Sprite2D
4. 所有配置不可用 → 占位网格（仅 `null_img` 场景或程序化创建的降级节点）

所有降级操作均通过 `push_error` / `push_warning` 输出到 Godot 调试器。

## 依赖

| 依赖 | 说明 |
|------|------|
| `config/terrain_config.json` | 地形配置文件（地块类型、属性、纹理、脚本、权重） |
| `res://assets/sprites/null_img.png` | 降级占位纹理（纹理缺失时使用） |
| `res://scripts/world/tile_data.gd` | TileInfo 资源类（预加载访问枚举和 new） |
| `res://scripts/world/tiles/*.gd` | 地块子类脚本（DirtTile、StoneTile、OceanTile、FarmlandTile） |
| `EventBus` | 生成完成后发出 `terrain_generated` 信号 |

## 配置文件格式

`config/terrain_config.json`：

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
      "defaults": {
        "passable": true,
        "buildable": true,
        "farmland": false,
        "hardness": 1,
        "depth": 0.0,
        "fishable": false,
        "resource_type": 0
      },
      "variants": {
        "soil": {
          "name": "普通土壤",
          "scene": "res://scenes/world/dirt_1.tscn",
          "moisture_base_rate": 0.8,
          "fertility_base": 0.8
        },
        "grassland": {
          "name": "草地",
          "texture": "dirt1.png",
          "script": "dirt_tile.gd",
          "moisture_base_rate": 0.8,
          "fertility_base": 0.8
        }
      },
      "gather_actions": [...]
    }
  }
}
```

### 字段说明

| 字段 | 级别 | 说明 |
|------|------|------|
| `texture_dir` | 全局 | 纹理资源根目录 |
| `null_texture` | 全局 | 降级占位纹理路径 |
| `script_dir` | 全局 | 脚本资源根目录 |
| `weight` | 类型 | 全随机模式下的出现权重（0 = 不自然生成） |
| `name` | 类型 | 类型中文名 |
| `tile_type` | 类型 | `TileInfo.TileType` 枚举值 |
| `default_variant` | 类型 | 随机生成时使用的默认变种键名 |
| `tags` | 类型 | 地块标签数组（如 `["water_source"]`） |
| `defaults` | 类型 | 类型级默认属性（passable、buildable 等） |
| `variants` | 类型 | 变种字典，键名为变种标识 |
| `scene` | 变种 | TSCN 场景路径（有则 TSCN 模式） |
| `texture` | 变种 | 纹理文件名（相对于 `texture_dir`，程序化模式） |
| `script` | 变种 | 脚本文件名（相对于 `script_dir`，程序化模式） |
| `moisture_base_rate` | 变种 | 湿度基础倍率 |
| `fertility_base` | 变种 | 肥力基础值 |

变种级可覆盖类型级属性（如 `hardness`、`depth`、`farmland` 等），传入 `TileInfo.apply_defaults()` 时会自动合并。

## 公开 API

### @export 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `generation_mode` | `GenerationMode` | `ALL_RANDOM` | 地形生成模式 |
| `map_width` | `int` | `32` | 地图宽度（列数） |
| `map_height` | `int` | `32` | 地图高度（行数） |
| `tile_size` | `int` | `64` | 单个地块像素大小 |
| `seed` | `int` | `0` | 随机种子，0 = 每次随机 |
| `config_path` | `String` | `res://config/terrain_config.json` | 地形配置文件路径 |
| `notify_on_complete` | `bool` | `true` | 是否广播 terrain_generated 事件 |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `generate()` | `void` | 清除已有地块并重新生成（可在运行时调用） |
| `get_tile_data_at(grid_x, grid_y)` | `Resource` | 查询指定坐标的 TileInfo 资源，无则返回 null |
| `get_tile_configs()` | `Dictionary` | 获取已加载的地形配置缓存 |
| `get_tile_config_for_type(type_key)` | `Dictionary` | 按类型键名获取配置 |
| `merge_tile_config(type_cfg, variant_cfg)` | `Dictionary` | 合并类型默认值 + 变种覆盖值 |
| `create_tile_instance(type_key, variant_key)` | `Node2D` | 创建地块实例（自动选择 TSCN/程序化模式） |
| `create_tile_programmatically(type_cfg, variant_cfg, variant_key)` | `Node2D` | 程序化创建地块（供外部系统如 TileActions 调用） |
| `update_all_tiles_properties()` | `void` | 全量刷新所有地块的温度/湿度/肥力 |
| `propagate_tile_tag_change(old_data, new_data, grid_pos)` | `void` | 标签变化时传播更新周围地块 |

## 地块命名规则

每个生成的 tile 节点命名为 `tile_X_Y`，其中 X 为列号、Y 为行号，从 `(0, 0)` 到 `(map_width-1, map_height-1)`。

通过 `get_node("tile_%d_%d" % [x, y])` 可直接查找。

## 扩展新地块类型

1. 在 `config/terrain_config.json` 的 `tiles` 中添加新条目（类型键名、权重、defaults、变种等）
2. 如需要特殊逻辑，在 `scripts/world/tiles/` 中创建对应的子类脚本并继承 `BaseTile`
3. 为新变种准备纹理（放入 `texture_dir`）或 TSCN 场景
4. 无需修改 `TerrainGenerator` 代码 — 配置驱动自动加载

## 扩展新生成模式

1. 在 `GenerationMode` 枚举中添加新值
2. 实现对应的 `_generate_xxx()` 私有方法
3. 在 `generate()` 的 `match` 分支中调用该方法

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
    print(tile.get_type_name())  # "土质地面" / "石质地面" / "水域" / "农田"

# 程序化创建一个未制作 TSCN 的地块变种
var grass_tile := world.create_tile_instance("dirt", "grassland")
```

## 关联文档

- [Docs/整体设计.md](../整体设计.md)
- [Docs/地块系统/1.3地形生成器.md](../地块系统/1.3地形生成器.md)
- [Docs/world/tile_data.md](tile_data.md)
- [config/terrain_config.json](../../config/terrain_config.json) — 实际配置
