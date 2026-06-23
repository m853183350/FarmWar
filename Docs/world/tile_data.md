# TileInfo（原 TileData）

地块数据资源类，描述单个地块的类型、通行性和可建造性等属性。

> 注意：`class_name` 为 `TileInfo`，文件名仍为 `tile_data.gd`。因 Godot 4.x 已有原生类 `TileData`，故改名避免冲突。
>
> 所有默认属性值从 `config/terrain_config.json` 注入，代码中不再硬编码。

## 用途

- 作为地块的数据载体，由 `TerrainGenerator` 在生成地形时为每个地块实例创建
- 通过 `node.set_meta("tile_data", data)` 或 `BaseTile.set_tile_data()` 附加到 tile 节点上
- 供其他系统（建筑、作物、战斗）查询地块属性

## 依赖

- `config/terrain_config.json` — 地块类型默认属性 + 变种覆盖值（由 TerrainGenerator 加载并合并后传入）

## 公开 API

### 枚举

| 枚举 | 值 | 说明 |
|------|-----|------|
| `TileType.DIRT` | 0 | 土质平地，可耕种 |
| `TileType.STONE` | 1 | 石质平地，清理后可建造 |
| `TileType.OCEAN` | 2 | 水域，不可通行 |
| `TileType.FARMLAND` | 3 | 农田，由 DIRT 耕作转化 |
| `TileType.SLOPE` | 4 | 斜坡（预留） |
| `TileType.ROUGH` | 5 | 崎岖地块（预留） |
| `TileType.SPECIAL` | 6 | 特殊地块（预留） |

### 属性

| 属性 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `grid_position` | `Vector2i` | `(0, 0)` | 网格坐标 |
| `tile_type` | `TileType` | `DIRT` | 地块大类 |
| `variant` | `String` | `""` | 细分变种键名（如 "soil"、"grassland"） |
| `variant_name` | `String` | `""` | 变种人类可读名称 |
| `passable` | `bool` | `true` | 是否可通行 |
| `buildable` | `bool` | `true` | 是否可建造 |
| `farmland` | `bool` | `false` | 是否可耕种/已是农田 |
| `fertility` | `float` | `0.0` | 肥力值 (0.0 ~ 5.0)，最终计算值 |
| `moisture` | `float` | `0.0` | 湿度值 (0.0 ~ 5.0)，最终计算值 |
| `hardness` | `int` | `1` | 硬度，影响建造/挖掘耗时 |
| `depth` | `float` | `0.0` | 水深 (0.0 ~ 1.0) |
| `fishable` | `bool` | `false` | 是否可钓鱼 |
| `resource_type` | `int` | `0` | 资源类型枚举值 |
| `tags` | `Array[String]` | `[]` | 地块标签（如 "water_source"） |
| `moisture_base_rate` | `float` | `1.0` | 湿度基础倍率（地块倍率） |
| `fertility_base` | `float` | `0.0` | 肥力基础值（地块基础值） |

### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `apply_defaults(config: Dictionary)` | `void` | 根据传入的配置字典设置所有默认属性（配置由 TerrainGenerator 从 JSON 加载并合并类型默认值 + 变种覆盖值） |
| `sync_tags()` | `void` | 兜底方法：根据 `tile_type` 同步标签（当 config 未提供 tags 时使用） |
| `get_type_name()` | `String` | 返回中文类型名（土质地面/石质地面/水域/农田/未知） |
| `can_be_plowed()` | `bool` | 地块是否可被耕作（DIRT 且非 farmland） |
| `can_be_dug()` | `bool` | 地块是否可被挖掘（STONE） |

### 配置字典结构

`apply_defaults()` 接收的 config 字典由 `TerrainGenerator._merge_tile_config()` 合并而成，包含：

| 字段 | 来源 | 说明 |
|------|------|------|
| `passable` ~ `resource_type` | 类型级 `defaults` | 类型通用属性 |
| `tags` | 类型级 `tags` | 地块标签数组 |
| `moisture_base_rate` | 变种级 | 湿度基础倍率 |
| `fertility_base` | 变种级 | 肥力基础值 |
| `variant_name` | 变种级 `name` | 变种人类可读名称 |
| `hardness` 等 | 变种级覆盖 | 变种可覆盖类型级默认值 |

## 使用示例

```gdscript
# 通过 TerrainGenerator 读取
var data: Resource = world.get_tile_data_at(3, 7)
if data and data.farmland:
    _plant_crop_at(3, 7)

# 自行创建（需传入合并后的配置字典）
var info := TileInfo.new()
info.grid_position = Vector2i(5, 5)
info.tile_type = TileInfo.TileType.DIRT
info.variant = "grassland"
info.apply_defaults(merged_config)

# 在其他脚本中通过 preload 访问枚举
const TileInfoRef: Script = preload("res://scripts/world/tile_data.gd")
if tile_type == TileInfoRef.TileType.OCEAN:
    return  # 海洋不可建造
```

## 关联文档

- [Docs/地块系统/1.1地块系统.md](../地块系统/1.1地块系统.md)
- [Docs/地块系统/1.2主要地块类型.md](../地块系统/1.2主要地块类型.md)
- [Docs/world/terrain_generator.md](terrain_generator.md)
- [config/terrain_config.json](../../config/terrain_config.json) — 实际配置数据
