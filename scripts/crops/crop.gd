## 作物抽象基类。
##
## 所有作物（小麦、水稻等）都必须继承本类。
## 定义了作物的生长阶段系统、TickSystem 驱动、视觉帧切换和收获接口。
##
## 子类必须覆写：
##   - [method _get_stage_data] — 返回生长阶段数据数组
##   - [method _get_harvest_yields] — 返回收获产物数据数组
##   - [method _get_crop_info] — 返回作物基本信息字典
##
## 使用方式：
##   1. 子类覆写三个方法
##   2. 调用 [method plant] 将作物放置到农田地块上
##   3. TickSystem 自动驱动生长
##   4. 通过 [signal EventBus.crop_harvest_requested] 事件触发收获
class_name Crop extends Sprite2D

# ============================================================
# 3. 常量
# ============================================================

const ZIndexConfig = preload("res://scripts/utils/z_index_config.gd")

# ============================================================
# 1. 信号
# ============================================================

## 生长阶段变化时发出（old_stage, new_stage）。
signal stage_changed(old_stage: int, new_stage: int)

## 作物被收获时发出（yields: Array[Dictionary]）。
signal harvested(yields: Array)

## 作物枯萎/死亡时发出。
signal withered()

# ============================================================
# 3. 常量
# ============================================================

## 作物材质资源（crops1x1 ShaderMaterial）。
const CROP_MATERIAL: ShaderMaterial = preload("res://resources/materials/crops/crops1x1.tres")

## Sprite sheet 中每帧宽度（px）。
const FRAME_WIDTH: int = 8

## Sprite sheet 中每帧高度（px）。
const FRAME_HEIGHT: int = 16

# ============================================================
# 5. 公开变量 — 状态
# ============================================================

## 当前生长阶段索引（0 = 种子/刚种下）。
var growth_stage: int = 0

## 当前阶段内的生长进度（0.0 ~ 1.0）。达到 1.0 时自动进入下一阶段。
var growth_progress: float = 0.0

## 作物生命值。0.0 表示死亡/枯萎。
var health: float = 1.0

## 所在地块引用。
var tile: Node2D = null

## 最近一次收获的产物列表。供 [TileActions] 在发出收获事件后读取。
## 每次调用 [method harvest] 时更新。
var last_harvest_yields: Array = []

# ============================================================
# 6. 私有变量
# ============================================================

var _stage_data: Array = []
var _crop_info: Dictionary = {}
var _tick_connected: bool = false
var _harvest_event_connected: bool = false

# ============================================================
# 8. 生命周期方法
# ============================================================

func _ready() -> void:
	# 应用作物通用材质（.duplicate() 确保每株作物独立控制参数）
	material = CROP_MATERIAL.duplicate()

	# 初始化阶段数据和身份信息
	_stage_data = _get_stage_data()
	_crop_info = _get_crop_info()

	# 连接到 TickSystem 驱动生长
	if TickSystem:
		TickSystem.tick_elapsed.connect(_on_tick)
		_tick_connected = true

	# 监听收获事件 — 作物自主管理收获，避免外部通过 duck typing 调用
	if EventBus:
		EventBus.crop_harvest_requested.connect(_on_harvest_requested)
		_harvest_event_connected = true

	# 设置初始视觉帧
	_apply_stage_visuals()
	# 若初始阶段 duration=0，立刻推进到下一个阶段
	if _stage_data.size() > 0:
		var first_stage: Dictionary = _stage_data[0]
		if first_stage.get("tick_duration", -1) == 0:
			_advance_stage()

func _exit_tree() -> void:
	if _tick_connected and TickSystem:
		TickSystem.tick_elapsed.disconnect(_on_tick)
		_tick_connected = false
	if _harvest_event_connected and EventBus:
		EventBus.crop_harvest_requested.disconnect(_on_harvest_requested)
		_harvest_event_connected = false

# ============================================================
# 9. 公开方法 — 种植
# ============================================================

## 将作物放置到指定地块上。
## 由 [TileActions] 或 [CropManager] 在验证通过后调用。
##
## [param target_tile] 必须是 FARMLAND 类型且无其他作物占用。
func plant(target_tile: Node2D) -> void:
	tile = target_tile
	# 定位：与地块同坐标，场景自带的 offset 处理视觉偏移
	position = target_tile.position
	# 注册为地块内容物
	if target_tile.has_method("add_occupant"):
		target_tile.add_occupant(self)
	# 按地块位置计算并设置渲染排序 z_index
	update_z_index()

# ============================================================
# 9. 公开方法 — 收获
# ============================================================

## 收获作物，返回产物数组。
## 只有处于最终阶段（成熟）时才能收获。
##
## 通常由 [signal EventBus.crop_harvest_requested] 事件触发，而非直接调用。
## 也可以被 [TileActions] 等系统直接调用（向后兼容）。
##
## 返回 [Array] of [Dictionary]：
##   { "item_id": String, "amount": float }
##   只有随机判定通过的产物才会出现在返回数组中。未成熟时返回空数组。
func harvest() -> Array:
	if not _is_mature():
		push_warning("Crop: 作物 %s 尚未成熟，无法收获" % _crop_info.get("crop_id", "unknown"))
		last_harvest_yields = []
		return []

	var yields: Array = _roll_yields()
	last_harvest_yields = yields

	# 通过 EventBus 广播产物，供 Storage 等系统收集
	if EventBus:
			EventBus.crop_harvested.emit(yields, _crop_info.get("crop_id", "unknown"))

	# 发出信号
	harvested.emit(yields)

	# 从地块移除
	if tile and tile.has_method("remove_occupant"):
		tile.remove_occupant(self)

	# 释放自身
	queue_free()

	return yields

## 是否处于可收获的成熟阶段。
func is_mature() -> bool:
	return _is_mature()

# ============================================================
# 9. 公开方法 — 销毁
# ============================================================

## 强制销毁作物（如被敌人破坏、地块被移除等）。
## 不产生任何收获物。
func destroy() -> void:
	withered.emit()
	if tile and tile.has_method("remove_occupant"):
		tile.remove_occupant(self)
	queue_free()

# ============================================================
# 9. 公开方法 — 渲染排序
# ============================================================

## 获取渲染层优先级。
##
## 生长阶段 ≤ 1（种子/幼苗）时返回 [enum ZIndexConfig.RenderLayer.CROP_LOW]，
## 之后返回 [enum ZIndexConfig.RenderLayer.CROP_TALL]。
## 子类可覆写以自定义判定逻辑。
func get_render_layer() -> int:
	if growth_stage <= 1:
		return ZIndexConfig.RenderLayer.CROP_LOW
	return ZIndexConfig.RenderLayer.CROP_TALL

## 获取视觉高度（世界像素）。
##
## 使用 [method ZIndexConfig.get_sprite_visual_height] 从精灵纹理和缩放计算。
func get_visual_height() -> float:
	return ZIndexConfig.get_sprite_visual_height(self)

## 获取排序锚点 y 值 = [member CanvasItem.global_position].y + [method get_visual_height]。
func get_sorting_y() -> float:
	return global_position.y + get_visual_height()

## 根据当前排序锚点和生长阶段更新 [member CanvasItem.z_index]。
func update_z_index() -> void:
	z_index = ZIndexConfig.calc_z_index(get_sorting_y(), get_render_layer())

# ============================================================
# 10. 私有方法 — Tick 驱动
# ============================================================

func _on_tick(_delta: float) -> void:
	if health <= 0.0:
		return

	var stage_info: Dictionary = _stage_data[growth_stage]
	var duration: int = stage_info.get("tick_duration", 0)

	# 最终阶段（tick_duration = -1 或 0）不再推进生长
	if duration <= 0:
		return

	# 每 tick 推进 (1 / duration)
	growth_progress += 1.0 / float(duration)

	if growth_progress >= 1.0:
		growth_progress = 0.0
		_advance_stage()

# ============================================================
# 10. 私有方法 — 阶段管理
# ============================================================

## 进入下一个生长阶段。
func _advance_stage() -> void:
	var old_stage: int = growth_stage
	growth_stage = mini(growth_stage + 1, _stage_data.size() - 1)
	_apply_stage_visuals()
	stage_changed.emit(old_stage, growth_stage)
	# 生长阶段变化可能导致渲染层从 CROP_LOW 变为 CROP_TALL
	update_z_index()

## 根据当前阶段设置 region_rect（视觉帧）。
func _apply_stage_visuals() -> void:
	var stage_info: Dictionary = _stage_data[growth_stage]
	var frame_x: int = stage_info.get("frame_x", 0)
	region_enabled = true
	region_rect = Rect2(frame_x, 0, FRAME_WIDTH, FRAME_HEIGHT)

## 当前阶段是否为最终阶段（成熟）。
func _is_mature() -> bool:
	return growth_stage >= _stage_data.size() - 1

# ============================================================
# 10. 私有方法 — 收获计算
# ============================================================

## 根据收获数据表和概率掷骰，返回实际获得的产物列表。
func _roll_yields() -> Array:
	var result: Array = []
	var yield_data: Array = _get_harvest_yields()

	for entry in yield_data:
		var entry_dict: Dictionary = entry as Dictionary
		var probability: float = entry_dict.get("probability", 1.0)
		# 概率掷骰（100% 概率则必然产出）
		if probability >= 1.0 or randf() < probability:
			result.append({
				"item_id": entry_dict.get("item_id", ""),
				"amount": entry_dict.get("base_amount", 0.0),
			})

	return result

# ============================================================
# 10. 私有方法 — 收获事件响应
# ============================================================

## 响应 [signal EventBus.crop_harvest_requested] 事件。
## 检查目标地块是否为自身所在地块，匹配且成熟时执行收获。
func _on_harvest_requested(target_tile: Node2D) -> void:
	if target_tile == tile and _is_mature():
		harvest()

# ============================================================
# 11. 虚方法 — 子类必须覆写
# ============================================================

## 返回作物基本信息字典。
##
## 必须包含的键：
##   - crop_id: String — 作物唯一标识
##   - crop_name: String — 人类可读名称
##   - plant_family: String — 所属"科"
##   - tier: int — 等级
##   - description: String — 描述文本
##   - scene_path: String — 场景文件路径
func _get_crop_info() -> Dictionary:
	push_error("Crop: 子类 %s 必须覆写 _get_crop_info()" % get_script().resource_path)
	return {}

## 返回生长阶段数据数组。
##
## 每个阶段为 [Dictionary]，包含：
##   - name: String — 阶段名称
##   - tick_duration: int — 阶段持续 tick 数（-1 表示最终阶段，不再推进）
##   - frame_x: int — 在 sprite sheet 中的 x 偏移（px），用于设置 region_rect
##   - passable: bool — 此阶段是否可通行
##
## 最后一个阶段必须 tick_duration 设为 -1（成熟后不再自动生长）。
func _get_stage_data() -> Array:
	push_error("Crop: 子类 %s 必须覆写 _get_stage_data()" % get_script().resource_path)
	return []

## 返回收获产物数据数组。
##
## 每个产物为 [Dictionary]，包含：
##   - item_id: String — 物品标识
##   - base_amount: float — 基础产出数量
##   - probability: float — 产出概率（0.0 ~ 1.0，1.0 = 100% 必出）
func _get_harvest_yields() -> Array:
	push_error("Crop: 子类 %s 必须覆写 _get_harvest_yields()" % get_script().resource_path)
	return []
