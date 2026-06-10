## 寻路算法实现。
##
## 提供两种算法：
##   - 直接 A*（[method find_path]）：适用于各单位不同目的地的场景。
##   - Flow Field（[method compute_flow_field]）：适用于大量单位涌向同一目标的场景。
##
## 所有方法均为纯计算，无共享状态，线程安全。
class_name Pathfinding extends Object

# ============================================================
# 内部类
# ============================================================

## 二叉最小堆，用于 A* / Dijkstra 优先队列。
## 存储 [[key, f, g], ...]，按 f 值排序。
## 支持延迟删除：重复 key 的旧条目在 pop 时由调用方跳过。
class _MinHeap extends RefCounted:
	var _data: Array[Array] = []  ## [[key: Variant, f: float, g: float], ...]

	func push(key, f: float, g: float) -> void:
		_data.append([key, f, g])
		_sift_up(_data.size() - 1)

	## 返回 [key, f, g]，空堆返回 []
	func pop() -> Array:
		if _data.is_empty():
			return []
		var result: Array = _data[0]
		var last: Array = _data.pop_back()
		if not _data.is_empty():
			_data[0] = last
			_sift_down(0)
		return result

	func is_empty() -> bool:
		return _data.is_empty()

	func clear() -> void:
		_data.clear()

	func _sift_up(idx: int) -> void:
		while idx > 0:
			var parent: int = (idx - 1) / 2
			if _data[idx][1] < _data[parent][1]:
				_swap(idx, parent)
				idx = parent
			else:
				break

	func _sift_down(idx: int) -> void:
		var size: int = _data.size()
		while true:
			var smallest: int = idx
			var left: int = 2 * idx + 1
			var right: int = 2 * idx + 2
			if left < size and _data[left][1] < _data[smallest][1]:
				smallest = left
			if right < size and _data[right][1] < _data[smallest][1]:
				smallest = right
			if smallest == idx:
				break
			_swap(idx, smallest)
			idx = smallest

	func _swap(i: int, j: int) -> void:
		var tmp: Array = _data[i]
		_data[i] = _data[j]
		_data[j] = tmp


## 流场数据，存储从每个可达格子到目标的最优移动方向。
class FlowField extends RefCounted:
	var goal: Vector2i
	var width: int
	var height: int
	var _directions: Array[Array] = []  ## [x][y] → Vector2（归一化方向）
	var _costs: Array[Array] = []       ## [x][y] → float（到目标的累计积分成本）

	## 获取指定地块的推荐移动方向。
	## 返回归一化 Vector2，不可达或越界返回 Vector2.ZERO。
	func get_direction_at(tile: Vector2i) -> Vector2:
		if not is_valid_tile(tile):
			return Vector2.ZERO
		var d: Vector2 = _directions[tile.x][tile.y]
		return d

	## 获取指定地块到目标的累计积分成本。
	## 越界返回 INF。
	func get_cost_at(tile: Vector2i) -> float:
		if not is_valid_tile(tile):
			return INF
		return _costs[tile.x][tile.y]

	## 检查坐标是否在流场范围内。
	func is_valid_tile(tile: Vector2i) -> bool:
		return tile.x >= 0 and tile.x < width and tile.y >= 0 and tile.y < height


# ============================================================
# 常量
# ============================================================

const TILE_SIZE: int = 64
const SQRT2: float = 1.4142135623730951
const INF: float = 1e30

# ============================================================
# 公开静态方法 — 直接 A*
# ============================================================

## 直接 A* 寻路。
##
## [param start] 起点地块坐标。
## [param goal] 终点地块坐标。
## [param cost_grid] 二维通行成本数组 [x][y] → float，负数表示不可通行。
## 返回世界坐标路径 [Array] of [Vector2]，空数组表示不可达。
static func find_path(start: Vector2i, goal: Vector2i, cost_grid: Array[Array]) -> Array[Vector2]:
	if cost_grid.is_empty():
		return []

	var width: int = cost_grid.size()
	var height: int = cost_grid[0].size() if width > 0 else 0
	if width == 0 or height == 0:
		return []

	# 边界检查
	if start.x < 0 or start.x >= width or start.y < 0 or start.y >= height:
		return []
	if goal.x < 0 or goal.x >= width or goal.y < 0 or goal.y >= height:
		return []

	# 不可通行检查
	if not _is_passable(start, cost_grid):
		return []
	if not _is_passable(goal, cost_grid):
		return []

	# 同格短路
	if start == goal:
		return [Vector2(
			float(start.x) * TILE_SIZE + float(TILE_SIZE) / 2.0,
			float(start.y) * TILE_SIZE + float(TILE_SIZE) / 2.0
		)]

	# 底层 A*
	var tile_path: Array[Vector2i] = _astar_search(start, goal, cost_grid, width, height)
	if tile_path.is_empty():
		return []

	# 平滑 + 转世界坐标
	var smoothed: Array[Vector2i] = smooth_path(tile_path, cost_grid, width, height)
	return _tiles_to_world(smoothed)


## 路径平滑（String Pulling 拉绳法）。
## 合并视线无阻挡的共线路径点。
static func smooth_path(tile_path: Array[Vector2i], cost_grid: Array[Array], width: int, height: int) -> Array[Vector2i]:
	if tile_path.size() <= 2:
		return tile_path.duplicate()

	var result: Array[Vector2i] = [tile_path[0]]
	var left_idx: int = 0
	var right_idx: int = 1

	while right_idx < tile_path.size() - 1:
		if _line_of_sight(tile_path[left_idx], tile_path[right_idx + 1], cost_grid, width, height):
			right_idx += 1
		else:
			result.append(tile_path[right_idx])
			left_idx = right_idx
			right_idx += 1

	result.append(tile_path[tile_path.size() - 1])
	return result


# ============================================================
# 公开静态方法 — Flow Field
# ============================================================

## 计算流场。
##
## 从 [param goal] 出发运行 Dijkstra，为每个可达格子计算通往目标的最优方向。
## [param cost_grid] 二维通行成本数组。
## 返回 [FlowField] 对象，不可达格子的方向为 Vector2.ZERO。
static func compute_flow_field(goal: Vector2i, cost_grid: Array[Array]) -> FlowField:
	var width: int = cost_grid.size()
	var height: int = cost_grid[0].size() if width > 0 else 0
	if width == 0 or height == 0:
		return _empty_flow_field(goal, width, height)

	if goal.x < 0 or goal.x >= width or goal.y < 0 or goal.y >= height:
		return _empty_flow_field(goal, width, height)

	if not _is_passable(goal, cost_grid):
		return _empty_flow_field(goal, width, height)

	# 初始化积分成本
	var integration: Array[Array] = []
	integration.resize(width)
	for x: int in range(width):
		integration[x] = []
		integration[x].resize(height)
		for y: int in range(height):
			integration[x][y] = INF

	# 初始化方向
	var directions: Array[Array] = []
	directions.resize(width)
	for x: int in range(width):
		directions[x] = []
		directions[x].resize(height)
		for y: int in range(height):
			directions[x][y] = Vector2.ZERO

	# Dijkstra 从 goal 向外扩展
	var heap := _MinHeap.new()

	integration[goal.x][goal.y] = 0.0
	heap.push(goal, 0.0, 0.0)

	while not heap.is_empty():
		var entry: Array = heap.pop()
		if entry.is_empty():
			break
		var cur: Vector2i = entry[0]
		var cur_int: float = entry[1]

		# 延迟删除：跳过过时条目
		if cur_int > integration[cur.x][cur.y]:
			continue

		for neighbor: Vector2i in _get_8_neighbors(cur, width, height):
			if cost_grid[neighbor.x][neighbor.y] < 0.0:
				continue

			# 墙角约束（邻居→cur 的对角移动）
			if _is_diagonal(cur, neighbor) and not _can_cut_corner(cur, neighbor, cost_grid):
				continue

			# 从 neighbor 移动到 cur 的成本 = 进入 cur 的成本
			var edge_cost: float = cost_grid[cur.x][cur.y]
			if _is_diagonal(cur, neighbor):
				edge_cost *= SQRT2

			var new_int: float = cur_int + edge_cost
			if new_int < integration[neighbor.x][neighbor.y]:
				integration[neighbor.x][neighbor.y] = new_int
				directions[neighbor.x][neighbor.y] = (Vector2(cur) - Vector2(neighbor)).normalized()
				heap.push(neighbor, new_int, 0.0)

	# 构建 FlowField 对象
	var field := FlowField.new()
	field.goal = goal
	field.width = width
	field.height = height
	field._directions = directions
	field._costs = integration
	return field


# ============================================================
# 公开静态方法 — 查询工具
# ============================================================

## 检查地块是否可通过。
static func is_passable(tile: Vector2i, cost_grid: Array[Array]) -> bool:
	if cost_grid.is_empty():
		return false
	var width: int = cost_grid.size()
	var height: int = cost_grid[0].size() if width > 0 else 0
	if tile.x < 0 or tile.x >= width or tile.y < 0 or tile.y >= height:
		return false
	return cost_grid[tile.x][tile.y] >= 0.0


## 获取地块通行成本（负数 = 不可通行）。
static func get_cost_at(tile: Vector2i, cost_grid: Array[Array]) -> float:
	if cost_grid.is_empty():
		return -1.0
	var width: int = cost_grid.size()
	var height: int = cost_grid[0].size() if width > 0 else 0
	if tile.x < 0 or tile.x >= width or tile.y < 0 or tile.y >= height:
		return -1.0
	return cost_grid[tile.x][tile.y]


# ============================================================
# 私有静态方法 — A* 搜索
# ============================================================

static func _astar_search(start: Vector2i, goal: Vector2i, cost_grid: Array[Array], width: int, height: int) -> Array[Vector2i]:
	var heap := _MinHeap.new()
	var g_score: Dictionary = {}       # Vector2i → float
	var came_from: Dictionary = {}     # Vector2i → Vector2i

	g_score[start] = 0.0
	heap.push(start, _heuristic(start, goal), 0.0)

	while not heap.is_empty():
		var entry: Array = heap.pop()
		if entry.is_empty():
			break
		var cur: Vector2i = entry[0]
		var cur_g: float = entry[2]

		# 延迟删除：跳过 g 值已过时的条目
		if cur_g > g_score.get(cur, INF):
			continue

		if cur == goal:
			return _reconstruct_path(came_from, cur, start)

		for neighbor: Vector2i in _get_8_neighbors(cur, width, height):
			if cost_grid[neighbor.x][neighbor.y] < 0.0:
				continue
			if _is_diagonal(cur, neighbor) and not _can_cut_corner(cur, neighbor, cost_grid):
				continue

			var move_cost: float = cost_grid[neighbor.x][neighbor.y]
			if _is_diagonal(cur, neighbor):
				move_cost *= SQRT2

			var tentative_g: float = cur_g + move_cost
			if tentative_g < g_score.get(neighbor, INF):
				g_score[neighbor] = tentative_g
				came_from[neighbor] = cur
				var f: float = tentative_g + _heuristic(neighbor, goal)
				heap.push(neighbor, f, tentative_g)

	return []  # 不可达


# ============================================================
# 私有静态方法 — 辅助函数
# ============================================================

## 八方向对角线距离启发式（可接受且一致，保证 A* 最优）。
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return float(dx + dy) - 0.5857864376269049 * float(mini(dx, dy))


## 获取 8 方向邻居（限界内，不含自身，不含不可通行检查）。
static func _get_8_neighbors(tile: Vector2i, width: int, height: int) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx: int = tile.x + dx
			var ny: int = tile.y + dy
			if nx < 0 or nx >= width or ny < 0 or ny >= height:
				continue
			neighbors.append(Vector2i(nx, ny))
	return neighbors


## 判断是否为对角移动（两坐标的 dx 和 dy 均非零）。
static func _is_diagonal(from: Vector2i, to: Vector2i) -> bool:
	return from.x != to.x and from.y != to.y


## 对角移动墙角约束：检查两个"肩部"地块是否均可通行。
static func _can_cut_corner(from: Vector2i, to: Vector2i, cost_grid: Array[Array]) -> bool:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	var side1 := Vector2i(from.x + dx, from.y)
	var side2 := Vector2i(from.x, from.y + dy)
	return cost_grid[side1.x][side1.y] >= 0.0 and cost_grid[side2.x][side2.y] >= 0.0


static func _is_passable(tile: Vector2i, cost_grid: Array[Array]) -> bool:
	return cost_grid[tile.x][tile.y] >= 0.0


## 重建路径（从 came_from 字典）。
static func _reconstruct_path(came_from: Dictionary, current: Vector2i, start: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	var cur: Vector2i = current
	while cur != start:
		if not came_from.has(cur):
			return []
		cur = came_from[cur] as Vector2i
		path.insert(0, cur)
	return path


## Bresenham 直线遍历。检查从 a 到 b 的直线经过的所有地块是否均可通行。
static func _line_of_sight(a: Vector2i, b: Vector2i, cost_grid: Array[Array], _width: int, _height: int) -> bool:
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y

	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy

	while true:
		if not _is_passable(Vector2i(x0, y0), cost_grid):
			return false
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
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


## Tile 坐标路径 → 世界坐标路径（地块中心）。
static func _tiles_to_world(tile_path: Array[Vector2i]) -> Array[Vector2]:
	var world_path: Array[Vector2] = []
	var half_tile: float = float(TILE_SIZE) / 2.0
	for tile: Vector2i in tile_path:
		world_path.append(Vector2(
			float(tile.x) * float(TILE_SIZE) + half_tile,
			float(tile.y) * float(TILE_SIZE) + half_tile
		))
	return world_path


## 创建空流场（全部方向为零）。
static func _empty_flow_field(goal: Vector2i, width: int, height: int) -> FlowField:
	var field := FlowField.new()
	field.goal = goal
	field.width = width
	field.height = height
	field._directions = []
	field._costs = []
	field._directions.resize(width)
	field._costs.resize(width)
	for x: int in range(width):
		field._directions[x] = []
		field._directions[x].resize(height)
		field._costs[x] = []
		field._costs[x].resize(height)
		for y: int in range(height):
			field._directions[x][y] = Vector2.ZERO
			field._costs[x][y] = INF
	return field
