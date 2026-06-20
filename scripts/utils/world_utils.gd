## 世界/地块工具函数。
##
## 提供获取世界节点、查找地块、坐标转换、读取地块数据等全局静态方法，
## 避免各处重复编写相同的查找/转换逻辑。
##
## 使用方式：
##   [code]const WorldUtils = preload("res://scripts/utils/world_utils.gd")[/code]
##   [code]var world: Node2D = WorldUtils.get_world()[/code]
##   [code]var tile: Node2D = WorldUtils.find_tile(world, Vector2i(5, 3))[/code]
extends RefCounted

# ============================================================
# 3. 常量
# ============================================================

## 默认地块尺寸（像素），用于坐标转换。
const DEFAULT_TILE_SIZE: int = 64

# ============================================================
# 9. 静态方法 — 世界查找
# ============================================================

## 获取世界节点（通过 group "world"）。
##
## 通过 [method Engine.get_main_loop] 获取 [SceneTree]，
## 再通过 [method SceneTree.get_first_node_in_group] 查找 world 节点。
## 返回 [code]null[/code] 表示世界尚未加载或不在场景树中。
##
## 注意：频繁调用（如每 tick）的类建议在本地缓存结果，避免重复查找。
static func get_world() -> Node2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("world") as Node2D

# ============================================================
# 9. 静态方法 — 地块查找
# ============================================================

## 在 world 中按网格坐标查找地块节点。
##
## 地块节点命名规则：[code]tile_X_Y[/code]（由 [TerrainGenerator] 保证）。
## [param world] 世界节点（通常由 [method get_world] 返回）。
## [param grid_pos] 网格坐标。
##
## 返回对应的 [Node2D] 地块节点；若不存在则返回 [code]null[/code]。
static func find_tile(world: Node2D, grid_pos: Vector2i) -> Node2D:
	var tile_name: String = "tile_%d_%d" % [grid_pos.x, grid_pos.y]
	var tile: Node = world.get_node_or_null(tile_name)
	if tile and tile is Node2D:
		return tile as Node2D
	return null

# ============================================================
# 9. 静态方法 — 坐标转换
# ============================================================

## 网格坐标转世界坐标（地块中心）。
##
## [param tile] 网格坐标（行列索引）。
## [param tile_size] 地块尺寸，默认 [member DEFAULT_TILE_SIZE]（64px）。
##
## 返回像素级世界坐标（地块中心点）。
static func tile_to_world(tile: Vector2i, tile_size: int = DEFAULT_TILE_SIZE) -> Vector2:
	return Vector2(
		float(tile.x) * float(tile_size) + float(tile_size) / 2.0,
		float(tile.y) * float(tile_size) + float(tile_size) / 2.0
	)

# ============================================================
# 9. 静态方法 — 地块数据
# ============================================================

## 获取地块的 TileInfo 数据。
##
## 优先通过 [method BaseTile.get_tile_data] 方法获取，
## 其次尝试 [method Object.has_meta] 读取 [code]"tile_data"[/code] 元数据，
## 最后尝试 duck typing（检查 [code]has_method("get_tile_data")[/code]）。
##
## 返回 [TileInfo] 或兼容的 [Resource]；无法获取时返回 [code]null[/code]。
static func get_tile_data(tile: Node) -> Resource:
	if tile.has_method("get_tile_data"):
		return tile.get_tile_data()
	if tile.has_meta("tile_data"):
		return tile.get_meta("tile_data")
	return null
