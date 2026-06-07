## 渲染排序配置与工具函数。
##
## 提供 z_index 计算公式、渲染层枚举、精灵视觉高度计算等。
## 所有需要参与排序的对象通过 [code]const ZIndexConfig = preload("res://scripts/utils/z_index_config.gd")[/code] 引用，
## 然后调用 [method calc_z_index] 设置自身 z_index。
##
## 使用示例：
##   [code]tile.z_index = ZIndexConfig.calc_z_index(tile.get_sorting_y(), ZIndexConfig.RenderLayer.GROUND)[/code]
extends RefCounted

# ============================================================
# 2. 枚举 — 渲染层优先级
# ============================================================

## 渲染层优先级。
## 值越小越先渲染（在底层），值越大越后渲染（在上层）。
enum RenderLayer {
	GROUND = 0,        ## 地块
	DECORATION = 1,    ## 装饰物
	ITEM = 2,          ## 掉落物
	RESOURCE = 3,      ## 资源节点
	CROP_LOW = 4,      ## 作物（矮阶段，视觉不超出本格）
	CROP_TALL = 5,     ## 作物（高阶段，视觉可能超出本格）
	BUILDING = 6,      ## 建筑
	UNIT = 7,          ## 作战单位
	EFFECT = 8,        ## 特效
	OVERLAY = 9,       ## UI 标记（建议独立 CanvasLayer）
}

# ============================================================
# 3. 常量
# ============================================================

## 每个地块行内可容纳的层级数。10 层足够覆盖所有 [enum RenderLayer]。
const LAYER_MULTIPLIER: int = 10

## 地块像素大小（需与 [constant UnitBase.TILE_SIZE] 和 TerrainGenerator.tile_size 保持一致）。
const TILE_SIZE: int = 64

## z_index 有效范围（Godot 硬限制）。
const Z_INDEX_MIN: int = -2147483648
const Z_INDEX_MAX: int = 2147483647

# ============================================================
# 9. 静态方法 — z_index 计算
# ============================================================

## 根据排序锚点 y 值和渲染层计算 z_index。
##
## 以地块行为单位进行排序（[code]sorting_y / TILE_SIZE[/code]），确保 z_index 不超过 Godot 限制 [member Z_INDEX_MAX]。
## 对于最大 400×400 的地图，z_index 范围保持在 [0, 4000] 以内。
##
## [param sorting_y] 对象视觉底部的世界 y 坐标
## [param layer]     渲染层优先级，取 [enum RenderLayer]
static func calc_z_index(sorting_y: float, layer: int) -> int:
	var tile_row: int = floori(sorting_y / float(TILE_SIZE))
	var z: int = tile_row * LAYER_MULTIPLIER + clampi(layer, 0, LAYER_MULTIPLIER - 1)
	return clampi(z, Z_INDEX_MIN, Z_INDEX_MAX)

# ============================================================
# 9. 静态方法 — 精灵视觉尺寸
# ============================================================

## 获取 Sprite2D 的视觉高度（世界像素）。
##
## 适用于 [code]centered = false[/code] 的精灵。
## 公式：[code]visual_height = offset.y * scale.y + display_height * scale.y[/code]
##
## 若 [param sprite] 无纹理且无 region，返回 [member TILE_SIZE]。
static func get_sprite_visual_height(sprite: Sprite2D) -> float:
	if not is_instance_valid(sprite):
		return float(TILE_SIZE)

	var disp_h: float = 0.0
	if sprite.region_enabled:
		disp_h = sprite.region_rect.size.y
	elif sprite.texture:
		disp_h = sprite.texture.get_height()

	if disp_h <= 0.0:
		return float(TILE_SIZE)

	return sprite.offset.y * sprite.scale.y + disp_h * sprite.scale.y

## 获取 Sprite2D 的排序锚点 y（[member CanvasItem.global_position].y + 视觉高度）。
static func get_sprite_sorting_y(sprite: Sprite2D) -> float:
	if not is_instance_valid(sprite):
		return 0.0
	return sprite.global_position.y + get_sprite_visual_height(sprite)
