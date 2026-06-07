## HPA* (Hierarchical Pathfinding A*) 寻路算法实现。
##
## 将地图划分为固定大小的簇，在簇级别构建抽象图，
## 在线查询时仅在抽象图上运行 A*，再将结果细化为逐格路径。
##
## 使用方式：
##   [code]var path: Array[Vector2] = Pathfinding.find_path(start_tile, goal_tile)[/code]
##
## 要求：
##   - 场景中必须有属于 [code]"world"[/code] group 的节点（TerrainGenerator），
##     且其子节点为带有 [member TileInfo] metadata 的地块实例。
##   - [code]config/pathfinding_cost.json[/code] 存在且格式正确。
class_name Pathfinding extends Object

# ============================================================
# 3. 常量 
# ============================================================

const TILE_SIZE: int = 64
const DEFAULT_CLUSTER_SIZE: int = 10
const DEFAULT_COST: float = 2.0
const SQRT2: float = 1.4142135623730951
const COST_CONFIG_PATH: String = "res://config/pathfinding_cost.json"

# ============================================================
# 5. 静态变量 — 缓存
# ============================================================

static var _cost_grid: Array[Array] = []  ## Array[Array] of float, _cost_grid[x][y]
static var _map_width: int = 0
static var _map_height: int = 0
static var _cluster_size: int = DEFAULT_CLUSTER_SIZE
static var _num_clusters_x: int = 0
static var _num_clusters_y: int = 0

## 抽象图：entrance_id (Vector2i) → Array[{to: Vector2i, cost: float, path: Array[Vector2i]}]
static var _abstract_graph: Dictionary = {}

## 每个簇包含的 entrance ID 列表：cluster_coord (Vector2i) → Array[Vector2i]
static var _cluster_entrances: Dictionary = {}

## entrance_id → {cluster_coord: tile_in_cluster (Vector2i), ...}
## 每个 entrance 映射其所属各簇到簇内对应的地块坐标。
static var _entrance_tiles: Dictionary = {}

## 成本配置缓存
static var _tile_type_costs: Dictionary = {}
static var _variant_costs: Dictionary = {}

## 脏簇列表（地形变更后待重建的簇）。
static var _dirty_clusters: Array[Vector2i] = []

## 是否已完成首次初始化。
static var _initialized: bool = false

static var debug_print_flag: bool = false

# ============================================================
# 9. 公开静态方法 — 寻路入口
# ============================================================

## 主寻路接口。
##
## [param start_tile] 起点地块坐标。
## [param goal_tile] 终点地块坐标。
## 返回世界坐标路径点数组 [Array] of [Vector2]，空数组表示不可达。
static func find_path(start_tile: Vector2i, goal_tile: Vector2i) -> Array[Vector2]:
	var start_time: int = Time.get_ticks_usec()
	_ensure_initialized()

	if debug_print_flag:
		print("Pathfinding: 寻路请求 from %s to %s" % [start_tile, goal_tile])

	if _cost_grid.is_empty():
		return []

	# 边界检查
	if start_tile.x < 0 or start_tile.x >= _map_width or start_tile.y < 0 or start_tile.y >= _map_height:
		return []
	if goal_tile.x < 0 or goal_tile.x >= _map_width or goal_tile.y < 0 or goal_tile.y >= _map_height:
		return []

	# 起/终点不可通行
	if not _is_passable(start_tile):
		return []
	if not _is_passable(goal_tile):
		return []

	# 同簇短路：起点和终点在同一簇内，直接底层 A*
	var cs := _get_cluster(start_tile)
	var cg := _get_cluster(goal_tile)

	if cs == cg:
		var cluster_bounds := _cluster_bounds(cs)
		var tile_path: Array[Vector2i] = _low_level_astar(start_tile, goal_tile, cluster_bounds)
		if tile_path.is_empty():
			return []
		var smoothed: Array[Vector2i] = _smooth_path(tile_path)
		return _tiles_to_world(smoothed)

	# 临时插入 start/goal 到抽象图
	var temp_edges: Dictionary = {}  # Vector2i → Array[{to: Vector2i, cost: float, path: Array[Vector2i]}]

	_insert_temp_node(start_tile, cs, temp_edges, true)
	var start_edges: Array = temp_edges.get(start_tile, [])
	if start_edges.is_empty():
		return []  # start 无法到达簇内任何 entrance

	_insert_temp_node(goal_tile, cg, temp_edges, false)

	# 检查 goal 是否可被到达（至少一个 entrance 能到 goal）
	var goal_reachable := false
	for node_key in temp_edges:
		for edge: Dictionary in temp_edges[node_key]:
			if edge["to"] == goal_tile:
				goal_reachable = true
				break
		if goal_reachable:
			break
	if not goal_reachable:
		return []

	# 抽象图 A*
	var abstract_path: Array[Vector2i] = _abstract_astar(start_tile, goal_tile, temp_edges)
	if abstract_path.is_empty():
		return []

	# 细化抽象路径为逐格路径
	var tile_path: Array[Vector2i] = _refine_path(abstract_path, temp_edges)
	if tile_path.is_empty():
		return []

	var smoothed: Array[Vector2i] = _smooth_path(tile_path)
	var end_time: int = Time.get_ticks_usec()
	print("Pathfinding: 寻路完成，耗时 %.2f ms，路径长度: %d" % [(end_time - start_time) / 1000.0, smoothed.size()])
	return _tiles_to_world(smoothed)


## 标记指定地块列表对应的簇为"脏"，下次寻路时自动重建。
## 应在 [signal EventBus.terrain_changed] 事件处理中调用。
static func mark_dirty(tiles: Array) -> void:
	if debug_print_flag:
		print("Pathfinding: 标记脏簇，受影响地块: %s" % [tiles])

	for item in tiles:
		var tile: Vector2i
		if item is Vector2i:
			tile = item as Vector2i
		elif item is Dictionary:
			var d := item as Dictionary
			tile = Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
		else:
			continue

		if tile.x < 0 or tile.x >= _map_width or tile.y < 0 or tile.y >= _map_height:
			continue

		var cluster := _get_cluster(tile)
		if cluster not in _dirty_clusters:
			_dirty_clusters.append(cluster)


## 检查指定地块是否可通过。
static func is_tile_passable(tile: Vector2i) -> bool:
	if debug_print_flag:
		print("Pathfinding: 检查地块可通行性: %s" % [tile])

	_ensure_initialized()
	if _cost_grid.is_empty():
		return false
	if tile.x < 0 or tile.x >= _map_width or tile.y < 0 or tile.y >= _map_height:
		return false
	return _cost_grid[tile.x][tile.y] >= 0.0


## 获取指定地块的移动成本（-1 表示不可通行）。
static func get_cost_at(tile: Vector2i) -> float:
	if debug_print_flag:
		print("Pathfinding: 获取地块成本: %s" % [tile])

	_ensure_initialized()
	if _cost_grid.is_empty():
		return -1.0
	if tile.x < 0 or tile.x >= _map_width or tile.y < 0 or tile.y >= _map_height:
		return -1.0
	return _cost_grid[tile.x][tile.y]


# ============================================================
# 10. 私有静态方法 — 初始化与缓存管理
# ============================================================

## 确保所有缓存已初始化。
static func _ensure_initialized() -> void:
	if debug_print_flag:
		print("Pathfinding: 确保初始化")

	if not _initialized:
		_load_cost_config()
		_initialized = true
	_ensure_cost_grid()
	_ensure_abstract_graph()


## 确保成本网格是最新的。
static func _ensure_cost_grid() -> void:
	if debug_print_flag:
		print("Pathfinding: 确保成本网格")

	var world := _get_world()
	if world == null:
		return

	# 读取地图尺寸
	var tg: Node2D = world as Node2D
	if tg.has_method("get") or "map_width" in tg:
		_map_width = int(tg.get("map_width"))
		_map_height = int(tg.get("map_height"))

	if _map_width <= 0 or _map_height <= 0:
		return

	# 若成本网格为空则完整重建
	if _cost_grid.is_empty():
		_build_cost_grid(world)


## 确保抽象图是最新的（处理脏簇）。
static func _ensure_abstract_graph() -> void:
	if debug_print_flag:
		print("Pathfinding: 确保抽象图")

	if _abstract_graph.is_empty():
		_build_abstract_graph()
		return

	if _dirty_clusters.is_empty():
		return

	# 局部重建脏簇
	for cluster: Vector2i in _dirty_clusters:
		_rebuild_cluster(cluster)
	_dirty_clusters.clear()


## 从 world 节点读取所有地块数据，构建二维成本数组。
static func _build_cost_grid(world: Node2D) -> void:
	if debug_print_flag:
		print("Pathfinding: 读取所有地块数据，构建成本网格")

	_cost_grid.clear()
	_cost_grid.resize(_map_width)

	for x: int in range(_map_width):
		_cost_grid[x] = []
		_cost_grid[x].resize(_map_height)
		for y: int in range(_map_height):
			_cost_grid[x][y] = DEFAULT_COST

	for child: Node in world.get_children():
		var tile_data = _get_tile_data_from_node(child)
		if tile_data == null:
			continue

		var gp: Vector2i = tile_data.grid_position
		if gp.x < 0 or gp.x >= _map_width or gp.y < 0 or gp.y >= _map_height:
			continue

		var cost: float = _get_tile_cost(
			_tile_type_to_key(tile_data.tile_type),
			tile_data.variant
		)
		_cost_grid[gp.x][gp.y] = cost


## 加载移动成本 JSON 配置。
static func _load_cost_config() -> void:
	if debug_print_flag:
		print("Pathfinding: 加载移动成本json配置")

	if not FileAccess.file_exists(COST_CONFIG_PATH):
		push_warning("Pathfinding: 成本配置文件不存在: %s，全部使用默认成本 %.1f" % [COST_CONFIG_PATH, DEFAULT_COST])
		return

	var file: FileAccess = FileAccess.open(COST_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("Pathfinding: JSON 解析失败 (行 %d): %s" % [json.get_error_line(), json.get_error_message()])
		return

	var data = json.data
	if not data is Dictionary:
		return

	var raw: Dictionary = data as Dictionary
	if raw.has("tile_type_costs"):
		_tile_type_costs = raw["tile_type_costs"]
	if raw.has("variant_costs"):
		_variant_costs = raw["variant_costs"]


## 获取指定类型 + 变种的地块移动成本。
static func _get_tile_cost(tile_type_key: String, variant: String) -> float:
	if debug_print_flag:
		print("Pathfinding: 获取地块成本，类型: %s, 变种: %s" % [tile_type_key, variant])
	# 1. 优先查 variant_costs
	if not variant.is_empty() and _variant_costs.has(variant):
		return float(_variant_costs[variant])

	# 2. 查 tile_type_costs
	if not tile_type_key.is_empty() and _tile_type_costs.has(tile_type_key):
		return float(_tile_type_costs[tile_type_key])

	# 3. 默认成本
	return DEFAULT_COST


## 将 TileInfo.TileType 枚举值映射为配置键名。
static func _tile_type_to_key(tile_type: int) -> String:
	match tile_type:
		0: return "dirt"       # DIRT
		1: return "stone"      # STONE
		2: return "ocean"      # OCEAN
		3: return "farmland"   # FARMLAND
		4: return "slope"      # SLOPE
		5: return "rough"      # ROUGH
		6: return "special"    # SPECIAL
		_: return ""


# ============================================================
# 10. 私有静态方法 — 簇管理
# ============================================================

## 获取地块所属的簇坐标。
static func _get_cluster(tile: Vector2i) -> Vector2i:
	return Vector2i(tile.x / _cluster_size, tile.y / _cluster_size)


## 获取簇的网格边界（Rect2i）。
static func _cluster_bounds(cluster: Vector2i) -> Rect2i:
	var x0 := cluster.x * _cluster_size
	var y0 := cluster.y * _cluster_size
	var w := mini(_cluster_size, _map_width - x0)
	var h := mini(_cluster_size, _map_height - y0)
	return Rect2i(x0, y0, w, h)


## 计算簇的总数。
static func _calc_cluster_counts() -> void:
	_num_clusters_x = ceili(float(_map_width) / float(_cluster_size))
	_num_clusters_y = ceili(float(_map_height) / float(_cluster_size))


# ============================================================
# 10. 私有静态方法 — 入口识别
# ============================================================

## 遍历所有簇边界，识别全部 entrance。
static func _identify_entrances() -> Dictionary:
	if debug_print_flag:
		print("Pathfinding: 识别簇间入口")

	_calc_cluster_counts()

	# 原始入口数据：{cluster_coord: [entrance_tiles_in_cluster]}
	var raw_cluster_entrances: Dictionary = {}
	for cx: int in range(_num_clusters_x):
		for cy: int in range(_num_clusters_y):
			raw_cluster_entrances[Vector2i(cx, cy)] = []

	# 水平边界（左右相邻簇）
	for cx: int in range(_num_clusters_x - 1):
		var left_cluster := Vector2i(cx, 0)
		var left_bounds := _cluster_bounds(left_cluster)
		var boundary_x: int = left_bounds.position.x + left_bounds.size.x - 1  # 左簇最右列

		for cy: int in range(_num_clusters_y):
			var cluster_left := Vector2i(cx, cy)
			var cluster_right := Vector2i(cx + 1, cy)
			var bounds := _cluster_bounds(cluster_left)

			var continuous_segment: Array[Vector2i] = []
			for y: int in range(bounds.position.y, bounds.position.y + bounds.size.y):
				var t_left := Vector2i(boundary_x, y)
				var t_right := Vector2i(boundary_x + 1, y)

				if _is_passable(t_left) and _is_passable(t_right):
					continuous_segment.append(t_left)  # 用左簇内的 tile 代表

			var compressed := _compress_entrance_segment(continuous_segment)
			for tile in compressed:
				raw_cluster_entrances[cluster_left].append(tile)
				raw_cluster_entrances[cluster_right].append(tile)

	# 垂直边界（上下相邻簇）
	for cy: int in range(_num_clusters_y - 1):
		var top_cluster := Vector2i(0, cy)
		var top_bounds := _cluster_bounds(top_cluster)
		var boundary_y: int = top_bounds.position.y + top_bounds.size.y - 1  # 上簇最底行

		for cx: int in range(_num_clusters_x):
			var cluster_top := Vector2i(cx, cy)
			var cluster_bottom := Vector2i(cx, cy + 1)
			var bounds := _cluster_bounds(cluster_top)

			var continuous_segment: Array[Vector2i] = []
			for x: int in range(bounds.position.x, bounds.position.x + bounds.size.x):
				var t_top := Vector2i(x, boundary_y)
				var t_bottom := Vector2i(x, boundary_y + 1)

				if _is_passable(t_top) and _is_passable(t_bottom):
					continuous_segment.append(t_top)  # 用上簇内的 tile 代表

			var compressed := _compress_entrance_segment(continuous_segment)
			for tile in compressed:
				raw_cluster_entrances[cluster_top].append(tile)
				raw_cluster_entrances[cluster_bottom].append(tile)

	# 清理：移除无 entrance 或只有孤立 entrance（< 2 个）的簇条目
	var filtered: Dictionary = {}
	for cluster in raw_cluster_entrances:
		var entrances: Array = raw_cluster_entrances[cluster]
		if entrances.size() >= 2:
			filtered[cluster] = entrances

	return filtered


## 压缩连续的 entrance 段，只保留两端和中间点。
static func _compress_entrance_segment(segment: Array[Vector2i]) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 压缩 entrance 段，原始长度: %d, 原始段: %s" % [segment.size(), segment])

	if segment.size() <= 3:
		return segment.duplicate()

	var result: Array[Vector2i] = []
	result.append(segment[0])
	result.append(segment[segment.size() / 2])
	result.append(segment[segment.size() - 1])
	return result


# ============================================================
# 10. 私有静态方法 — 抽象图构建
# ============================================================

## 构建完整抽象图。
static func _build_abstract_graph() -> void:
	if debug_print_flag:
		print("Pathfinding: 构建完整抽象图")

	_abstract_graph.clear()
	_cluster_entrances.clear()
	_entrance_tiles.clear()

	# 步骤 1：识别所有入口
	var raw_entrances := _identify_entrances()
	if raw_entrances.is_empty():
		push_warning("Pathfinding: 未发现任何簇间入口，抽象图为空")
		return

	# 步骤 2：构建 entrance 到 cluster 的映射
	# 对于每个 entrance tile，确定它是哪些簇的入口
	for cluster in raw_entrances:
		var cluster_coord: Vector2i = cluster as Vector2i
		for entrance_tile in raw_entrances[cluster]:
			var et: Vector2i = entrance_tile as Vector2i
			# entrance ID：使用 entrance tile 本身（已在识别阶段统一为较小坐标侧的 tile）
			if not _entrance_tiles.has(et):
				_entrance_tiles[et] = {}
			_entrance_tiles[et][cluster_coord] = et

	_cluster_entrances = raw_entrances

	# 步骤 3：对每个簇构建内部 entrance 间的最短路径
	for cluster in _cluster_entrances:
		_build_cluster_edges(cluster)


## 构建单簇内所有 entrance 对之间的边。
static func _build_cluster_edges(cluster: Vector2i) -> void:
	if debug_print_flag:
		print("Pathfinding: 构建簇 %s 内的抽象边" % [cluster])

	var entrances: Array = _cluster_entrances.get(cluster, [])
	if entrances.size() < 2:
		return

	var bounds := _cluster_bounds(cluster)

	# 从 _entrance_tiles 获取该簇中每个 entrance 对应的 tile
	# 注意：entrance ID 对应的 tile 可能不在该簇中（如果 entrance 在相邻簇侧）
	# 需要找到它在该簇内的 tile
	var cluster_tiles: Array[Vector2i] = []
	for entrance_id in entrances:
		var eid: Vector2i = entrance_id as Vector2i
		var tile_map: Dictionary = _entrance_tiles.get(eid, {})
		if tile_map.has(cluster):
			cluster_tiles.append(tile_map[cluster])
		else:
			# entrance tile 不在该簇中，需要找相邻 tile
			# 这种情况发生在 entrance 在水平边界的右侧簇或垂直边界的下侧簇
			# entrance ID 使用的是左侧/上侧的 tile
			# 右侧/下侧的相邻 tile 应位于 entrance_id + (1,0) 或 entrance_id + (0,1)
			var neighbor_tile := _find_neighbor_in_cluster(eid, cluster)
			if neighbor_tile != Vector2i(-1, -1):
				# 更新映射以便后续使用
				_entrance_tiles[eid][cluster] = neighbor_tile
				cluster_tiles.append(neighbor_tile)

	if cluster_tiles.size() < 2:
		return

	# 对每对 entrance 计算簇内最短路径
	for i: int in range(cluster_tiles.size()):
		for j: int in range(i + 1, cluster_tiles.size()):
			var t1 := cluster_tiles[i]
			var t2 := cluster_tiles[j]
			var e1: Vector2i = entrances[i] as Vector2i
			var e2: Vector2i = entrances[j] as Vector2i

			var path: Array[Vector2i] = _low_level_astar(t1, t2, bounds)
			if path.is_empty():
				continue

			var path_cost: float = _calculate_path_cost(path)

			# 双向添加边
			if not _abstract_graph.has(e1):
				_abstract_graph[e1] = []
			_abstract_graph[e1].append({
				"to": e2,
				"cost": path_cost,
				"path": path,
			})

			if not _abstract_graph.has(e2):
				_abstract_graph[e2] = []
			_abstract_graph[e2].append({
				"to": e1,
				"cost": path_cost,
				"path": _reverse_path(path),
			})


## 找到 entrance ID 在目标簇中的对应 tile。
## entrance ID 是边界对中一侧的 tile，本方法找到另一侧。
static func _find_neighbor_in_cluster(entrance_id: Vector2i, cluster: Vector2i) -> Vector2i:
	if debug_print_flag:
		print("Pathfinding: 寻找 entrance %s 在簇 %s 中的对应 tile" % [entrance_id, cluster])


	var bounds := _cluster_bounds(cluster)

	# 检查 entrance_id 的四个相邻 tile 哪个在 cluster 内且可通过
	var candidates: Array[Vector2i] = [
		Vector2i(entrance_id.x + 1, entrance_id.y),
		Vector2i(entrance_id.x - 1, entrance_id.y),
		Vector2i(entrance_id.x, entrance_id.y + 1),
		Vector2i(entrance_id.x, entrance_id.y - 1),
	]

	for candidate in candidates:
		if bounds.has_point(candidate) and _is_passable(candidate):
			return candidate

	return Vector2i(-1, -1)


## 重建单个簇的抽象边（地形变更后的局部更新）。
static func _rebuild_cluster(cluster: Vector2i) -> void:
	if debug_print_flag:
		print("Pathfinding: 重建簇 %s 的抽象边" % [cluster])
	# 1. 重新计算该簇范围的成本网格
	var world := _get_world()
	if world == null:
		return

	var bounds := _cluster_bounds(cluster)
	for x: int in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for y: int in range(bounds.position.y, bounds.position.y + bounds.size.y):
			if x < 0 or x >= _map_width or y < 0 or y >= _map_height:
				continue
			var tile_data = _get_tile_data_at(x, y)
			if tile_data:
				var cost: float = _get_tile_cost(
					_tile_type_to_key(tile_data.tile_type),
					tile_data.variant
				)
				_cost_grid[x][y] = cost
			else:
				_cost_grid[x][y] = DEFAULT_COST

	# 2. 移除该簇相关的旧边
	var entrances: Array = _cluster_entrances.get(cluster, [])
	for entrance_id in entrances:
		var eid: Vector2i = entrance_id as Vector2i
		if _abstract_graph.has(eid):
			# 移除指向该簇其他 entrance 的边（在 _build_cluster_edges 中会重新添加）
			var edges: Array = _abstract_graph[eid]
			var other_entrances: Array = entrances.duplicate()
			other_entrances.erase(eid)
			for other in other_entrances:
				for k: int in range(edges.size() - 1, -1, -1):
					if edges[k]["to"] == other:
						edges.remove_at(k)

	# 3. 重建该簇的边
	_build_cluster_edges(cluster)


# ============================================================
# 10. 私有静态方法 — 底层 A*
# ============================================================

## 底层 8 方向 A*，搜索范围限定在 [param bounds] 内。
## 返回 [Array] of [Vector2i] 路径，空数组表示不可达。
static func _low_level_astar(start: Vector2i, goal: Vector2i, bounds: Rect2i) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 低层 A* 搜索 from %s to %s within bounds %s" % [start, goal, bounds])

	var open_set: Array[Dictionary] = []
	var came_from: Dictionary = {}   # Vector2i → Vector2i
	var g_score: Dictionary = {}     # Vector2i → float
	var start_key := start
	var goal_key := goal

	g_score[start_key] = 0.0
	open_set.append({"tile": start_key, "f": _heuristic(start_key, goal_key), "g": 0.0})

	while not open_set.is_empty():
		var current_dict: Dictionary = _pop_min_f(open_set)
		var cur_tile: Vector2i = current_dict["tile"]

		if cur_tile == goal_key:
			return _reconstruct_path(came_from, cur_tile, start_key)

		for neighbor in _get_8_neighbors(cur_tile, bounds):
			if not _is_passable(neighbor):
				continue
			if _is_diagonal(cur_tile, neighbor) and not _can_cut_corner(cur_tile, neighbor):
				continue

			var move_cost: float = _cost_grid[neighbor.x][neighbor.y]
			if _is_diagonal(cur_tile, neighbor):
				move_cost *= SQRT2

			var tentative_g: float = g_score[cur_tile] + move_cost
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				g_score[neighbor] = tentative_g
				came_from[neighbor] = cur_tile
				var f: float = tentative_g + _heuristic(neighbor, goal_key)
				_update_or_add(open_set, neighbor, f, tentative_g)

	return []  # 不可达


## 八方向对角线距离启发式（可接受，保证最优）。
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	if debug_print_flag:
		print("Pathfinding: 计算启发式距离 from %s to %s" % [a, b])


	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	# D = 1, D2 = sqrt(2)
	# h = D * (dx + dy) + (D2 - 2*D) * min(dx, dy)
	#   = dx + dy + (1.414 - 2) * min(dx, dy)
	#   = dx + dy - 0.586 * min(dx, dy)
	return float(dx + dy) - 0.5857864376269049 * float(mini(dx, dy))


## 获取 8 方向邻居，排除出界和超出 bounds 的节点。
static func _get_8_neighbors(tile: Vector2i, bounds: Rect2i) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 获取 %s 的 8 方向邻居，边界限制 %s" % [tile, bounds])

	var neighbors: Array[Vector2i] = []
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := tile.x + dx
			var ny := tile.y + dy
			if nx < 0 or nx >= _map_width or ny < 0 or ny >= _map_height:
				continue
			if not bounds.has_point(Vector2i(nx, ny)):
				continue
			neighbors.append(Vector2i(nx, ny))
	return neighbors


## 判断移动是否为斜向（dx 和 dy 均非零）。
static func _is_diagonal(from: Vector2i, to: Vector2i) -> bool:
	return from.x != to.x and from.y != to.y


## 斜向移动墙角约束：防止穿过对角线上的障碍物。
static func _can_cut_corner(from: Vector2i, to: Vector2i) -> bool:
	var dx := to.x - from.x
	var dy := to.y - from.y
	var side1 := Vector2i(from.x + dx, from.y)
	var side2 := Vector2i(from.x, from.y + dy)
	return _is_passable(side1) and _is_passable(side2)


## 从 came_from 字典重建路径。
static func _reconstruct_path(came_from: Dictionary, current: Vector2i, start: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	var cur := current
	while cur != start:
		if not came_from.has(cur):
			return []  # 数据异常
		cur = came_from[cur] as Vector2i
		path.insert(0, cur)
	return path


## 从 open_set 中取出 f 值最小的节点并返回。
static func _pop_min_f(open_set: Array[Dictionary]) -> Dictionary:
	var min_idx := 0
	var min_f: float = open_set[0]["f"]
	for i: int in range(1, open_set.size()):
		var f: float = open_set[i]["f"]
		if f < min_f:
			min_f = f
			min_idx = i
	var result: Dictionary = open_set[min_idx]
	open_set.remove_at(min_idx)
	return result


## 更新或添加节点到 open_set。
static func _update_or_add(open_set: Array[Dictionary], tile: Vector2i, f: float, g: float) -> void:
	for item: Dictionary in open_set:
		if item["tile"] == tile:
			item["f"] = f
			item["g"] = g
			return
	open_set.append({"tile": tile, "f": f, "g": g})


# ============================================================
# 10. 私有静态方法 — 抽象图 A*
# ============================================================

## 在抽象图上运行 A*。
## [param temp_edges] 临时边字典，包含 start/goal 的临时连接。
static func _abstract_astar(start: Vector2i, goal: Vector2i, temp_edges: Dictionary) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 在抽象图上运行 A* 搜索 from %s to %s with temp edges %s" % [start, goal, temp_edges])

	var open_set: Array[Dictionary] = []
	var came_from: Dictionary = {}   # Vector2i → Vector2i
	var g_score: Dictionary = {}     # Vector2i → float

	g_score[start] = 0.0
	open_set.append({"tile": start, "f": _abstract_heuristic(start, goal), "g": 0.0})

	while not open_set.is_empty():
		var current_dict: Dictionary = _pop_min_f(open_set)
		var cur_node: Vector2i = current_dict["tile"]

		if cur_node == goal:
			return _reconstruct_path(came_from, cur_node, start)

		for edge: Dictionary in _get_abstract_neighbors(cur_node, temp_edges):
			var neighbor: Vector2i = edge["to"]
			var edge_cost: float = edge["cost"]

			var tentative_g: float = g_score[cur_node] + edge_cost
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				g_score[neighbor] = tentative_g
				came_from[neighbor] = cur_node
				var f: float = tentative_g + _abstract_heuristic(neighbor, goal)
				_update_or_add(open_set, neighbor, f, tentative_g)

	return []  # 不可达


## 获取抽象图中节点的邻居（合并缓存边和临时边）。
static func _get_abstract_neighbors(node: Vector2i, temp_edges: Dictionary) -> Array[Dictionary]:
	if debug_print_flag:
		print("Pathfinding: 获取抽象图节点 %s 的邻居，临时边 %s" % [node, temp_edges])

	var neighbors: Array[Dictionary] = []

	if _abstract_graph.has(node):
		for edge: Dictionary in _abstract_graph[node]:
			neighbors.append(edge)

	if temp_edges.has(node):
		for edge: Dictionary in temp_edges[node]:
			neighbors.append(edge)

	return neighbors


## 抽象图启发式：使用目标节点的实际位置（或簇中心）。
static func _abstract_heuristic(a: Vector2i, b: Vector2i) -> float:
	# 对于 entrance 节点，使用其实际坐标
	# 对于 start/goal 临时节点，也使用其实际坐标
	# 均使用八方向对角线距离
	return _heuristic(a, b)


# ============================================================
# 10. 私有静态方法 — 临时节点插入
# ============================================================

## 在抽象图中临时插入起点或终点节点。
## [param is_start] true=起点（start → entrance），false=终点（entrance → goal）。
static func _insert_temp_node(tile: Vector2i, cluster: Vector2i, temp_edges: Dictionary, is_start: bool) -> void:
	if debug_print_flag:
		print("Pathfinding: 临时插入节点 %s 到簇 %s" % [tile, cluster])

	var entrances: Array = _cluster_entrances.get(cluster, [])
	if entrances.is_empty():
		return

	var bounds := _cluster_bounds(cluster)

	if is_start:
		# 起点 → 各 entrance
		if not temp_edges.has(tile):
			temp_edges[tile] = []

		for entrance_id in entrances:
			var eid: Vector2i = entrance_id as Vector2i
			var entrance_tile_in_cluster: Vector2i = _get_entrance_tile_in_cluster(eid, cluster, bounds)
			if entrance_tile_in_cluster == Vector2i(-1, -1):
				continue

			var path: Array[Vector2i] = _low_level_astar(tile, entrance_tile_in_cluster, bounds)
			if path.is_empty():
				continue

			var path_cost: float = _calculate_path_cost(path)
			temp_edges[tile].append({
				"to": eid,
				"cost": path_cost,
				"path": path,
				"target_tile": entrance_tile_in_cluster,
			})
	else:
		# 各 entrance → 终点
		for entrance_id in entrances:
			var eid: Vector2i = entrance_id as Vector2i
			var entrance_tile_in_cluster: Vector2i = _get_entrance_tile_in_cluster(eid, cluster, bounds)
			if entrance_tile_in_cluster == Vector2i(-1, -1):
				continue

			var path: Array[Vector2i] = _low_level_astar(entrance_tile_in_cluster, tile, bounds)
			if path.is_empty():
				continue

			var path_cost: float = _calculate_path_cost(path)
			if not temp_edges.has(eid):
				temp_edges[eid] = []
			temp_edges[eid].append({
				"to": tile,
				"cost": path_cost,
				"path": path,
				"target_tile": entrance_tile_in_cluster,
			})


## 获取 entrance 在指定簇内对应的 tile 坐标。
static func _get_entrance_tile_in_cluster(entrance_id: Vector2i, cluster: Vector2i, bounds: Rect2i) -> Vector2i:
	if debug_print_flag:
		print("Pathfinding: 获取 entrance %s 在簇 %s 内的对应 tile" % [entrance_id, cluster])

	var tile_map: Dictionary = _entrance_tiles.get(entrance_id, {})
	if tile_map.has(cluster):
		return tile_map[cluster] as Vector2i

	# entrance tile 不在该簇中（entrance ID 是对侧 tile），找相邻 tile
	return _find_neighbor_in_cluster(entrance_id, cluster)


# ============================================================
# 10. 私有静态方法 — 路径细化与平滑
# ============================================================

## 将抽象路径细化为逐格 tile 路径。
## 拼接各段缓存的 sub-path，去重连接点。
static func _refine_path(abstract_path: Array[Vector2i], temp_edges: Dictionary) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 细化抽象路径 %s with temp edges %s" % [abstract_path, temp_edges])

	if abstract_path.size() < 2:
		return []

	var result: Array[Vector2i] = []

	for i: int in range(abstract_path.size() - 1):
		var from_node: Vector2i = abstract_path[i]
		var to_node: Vector2i = abstract_path[i + 1]

		var sub_path: Array[Vector2i] = _lookup_sub_path(from_node, to_node, temp_edges)
		if sub_path.is_empty():
			# 缓存未命中，尝试底层 A*（跨越簇边界时使用全图范围）
			var full_bounds := Rect2i(0, 0, _map_width, _map_height)
			sub_path = _low_level_astar(from_node, to_node, full_bounds)
			if sub_path.is_empty():
				return []  # 细化失败

		# 追加子路径。不跳过首节点，避免在 entrance 边界（两侧 tile 不同）
		# 丢失必要的地块过渡。冗余点由 _smooth_path 后处理合并。
		if result.is_empty():
			result.append_array(sub_path)
		else:
			# 仅当首节点与上一段末节点相同时跳过（避免原地踏步）
			var last_tile: Vector2i = result[result.size() - 1]
			var start_idx: int = 0
			if sub_path.size() > 0 and sub_path[0] == last_tile:
				start_idx = 1
			for j: int in range(start_idx, sub_path.size()):
				result.append(sub_path[j])

	return result


## 查找 from → to 的缓存路径。
static func _lookup_sub_path(from: Vector2i, to: Vector2i, temp_edges: Dictionary) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 查找缓存路径 from %s to %s with temp edges %s" % [from, to, temp_edges])

	# 先查临时边
	if temp_edges.has(from):
		for edge: Dictionary in temp_edges[from]:
			if edge["to"] == to:
				var path: Array[Vector2i] = edge.get("path", [])
				return path.duplicate()

	# 再查抽象图缓存
	if _abstract_graph.has(from):
		for edge: Dictionary in _abstract_graph[from]:
			if edge["to"] == to:
				var path: Array[Vector2i] = edge.get("path", [])
				return path.duplicate()

	return []


## String Pulling（拉绳法）路径平滑。
## 合并共线且视线无阻挡的路径点。
static func _smooth_path(tile_path: Array[Vector2i]) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: String Pulling（拉绳法）路径平滑。 %s" % [tile_path])
		
	if tile_path.size() <= 2:
		return tile_path.duplicate()

	var result: Array[Vector2i] = [tile_path[0]]
	var left_idx := 0
	var right_idx := 1

	while right_idx < tile_path.size() - 1:
		if _line_of_sight(tile_path[left_idx], tile_path[right_idx + 1]):
			right_idx += 1
		else:
			result.append(tile_path[right_idx])
			left_idx = right_idx
			right_idx += 1

	# 添加终点
	result.append(tile_path[tile_path.size() - 1])
	return result


## Bresenham 直线遍历，检查路径经过的所有地块是否可通过。
static func _line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	if debug_print_flag:
		print("Pathfinding: Bresenham 直线遍历,检查 %s 到 %s 的视线" % [a, b])
	var x0 := a.x
	var y0 := a.y
	var x1 := b.x
	var y1 := b.y

	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy

	while true:
		if not _is_passable(Vector2i(x0, y0)):
			return false
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			if x0 == x1:
				break
			err += dy
			x0 += sx
		if e2 <= dx:
			if y0 == y1:
				break
			err += dx
			y0 += sy

	return true


# ============================================================
# 10. 私有静态方法 — 坐标转换与工具
# ============================================================

## 将 tile 坐标路径转换为世界坐标路径（地块中心）。
static func _tiles_to_world(tile_path: Array[Vector2i]) -> Array[Vector2]:
	if debug_print_flag:
		print("Pathfinding: 将 tile 坐标路径转换为世界坐标路径（地块中心）。 %s" % [tile_path])

	var world_path: Array[Vector2] = []
	var half_tile: float = float(TILE_SIZE) / 2.0
	for tile in tile_path:
		world_path.append(Vector2(
			float(tile.x) * float(TILE_SIZE) + half_tile,
			float(tile.y) * float(TILE_SIZE) + half_tile
		))
	return world_path


## 检查地块是否可通过（成本 ≥ 0）。
static func _is_passable(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.x >= _map_width or tile.y < 0 or tile.y >= _map_height:
		return false
	return _cost_grid[tile.x][tile.y] >= 0.0


## 计算路径总成本。
static func _calculate_path_cost(path: Array[Vector2i]) -> float:
	if debug_print_flag:
		print("Pathfinding: 计算路径总成本。 %s" % [path])

	if path.size() < 2:
		return 0.0

	var total: float = 0.0
	for i: int in range(path.size() - 1):
		var from_tile := path[i]
		var to_tile := path[i + 1]
		var cost: float = _cost_grid[to_tile.x][to_tile.y]
		if _is_diagonal(from_tile, to_tile):
			cost *= SQRT2
		total += cost
	return total


## 反转路径（用于抽象图中双向边的反向路径）。
static func _reverse_path(path: Array[Vector2i]) -> Array[Vector2i]:
	if debug_print_flag:
		print("Pathfinding: 反转路径。 %s" % [path])
	var reversed: Array[Vector2i] = []
	reversed.resize(path.size())
	for i: int in range(path.size()):
		reversed[path.size() - 1 - i] = path[i]
	return reversed


# ============================================================
# 10. 私有静态方法 — 世界与地块数据访问
# ============================================================

## 获取 world 节点。
static func _get_world() -> Node2D:
	if debug_print_flag:
		print("Pathfinding: 获取 world 节点")
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("world")
	if nodes.is_empty():
		return null
	return nodes[0] as Node2D


## 从节点获取 TileInfo 数据（兼容 BaseTile 和普通 Node 的 metadata）。
static func _get_tile_data_from_node(node: Node) -> Resource:
	if debug_print_flag:
		print("Pathfinding: 从节点 %s 获取 TileInfo 数据" % [node])

	if node is BaseTile:
		return (node as BaseTile).get_tile_data()

	# 兜底：通过 metadata 获取
	var meta_data = node.get_meta("tile_data", null)
	if meta_data is TileInfo:
		return meta_data as TileInfo
	return null


## 通过网格坐标获取地块数据（遍历 world 子节点）。
static func _get_tile_data_at(grid_x: int, grid_y: int) -> Resource:
	if debug_print_flag:
		print("Pathfinding: 通过网格坐标 (%d, %d) 获取地块数据（遍历 world 子节点）" % [grid_x, grid_y])

	var world := _get_world()
	if world == null:
		return null

	var expected_name := "tile_%d_%d" % [grid_x, grid_y]
	var node := world.get_node_or_null(expected_name)
	if node:
		return _get_tile_data_from_node(node)

	# 兜底：遍历查找
	for child: Node in world.get_children():
		var td = _get_tile_data_from_node(child)
		if td and td.grid_position == Vector2i(grid_x, grid_y):
			return td

	return null


# ============================================================
# 10. 私有静态方法 — 调试
# ============================================================

## 获取当前抽象图统计信息（调试用）。
static func get_stats() -> Dictionary:
	return {
		"map_size": Vector2i(_map_width, _map_height),
		"cluster_size": _cluster_size,
		"num_clusters": Vector2i(_num_clusters_x, _num_clusters_y),
		"num_entrances": _abstract_graph.size(),
		"num_dirty_clusters": _dirty_clusters.size(),
		"cost_grid_ready": not _cost_grid.is_empty(),
		"abstract_graph_ready": not _abstract_graph.is_empty(),
	}


## 清空所有缓存，强制完全重建（调试/测试用）。
static func reset_cache() -> void:
	_cost_grid.clear()
	_abstract_graph.clear()
	_cluster_entrances.clear()
	_entrance_tiles.clear()
	_dirty_clusters.clear()
	_initialized = false
	_map_width = 0
	_map_height = 0
