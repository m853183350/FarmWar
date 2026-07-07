## 全局事件总线，用于系统间解耦通信。
## 各系统通过 EventBus 发送和接收事件，避免直接依赖。
##
## 通过 Autoload 全局访问：[code]EventBus[/code]
##
## 使用方式：
##   EventBus.some_event.connect(_on_some_event)
##   EventBus.some_event.emit(args)
extends Node

# ============================================================
# 1. 信号
# ============================================================

## 地形生成完成。
signal terrain_generated()

## 地形变更（地块类型转换、建筑放置等）。
## [param tiles] 变更的地块网格坐标数组 [Array] of [Vector2i]。
signal terrain_changed(tiles: Array)

## 游戏状态变化（暂停/恢复/结束等）。
signal game_state_changed(new_state: StringName)

## 地块被点击（传递地块引用）。
signal tile_clicked(tile: Node2D)

## 调试指令被执行（传递指令字符串）。
signal debug_command_executed(command: String)

## 地块框选完成（传递网格坐标数组）。
signal tiles_selected(tiles: Array)

## 地块操作菜单项被点击。action: "plow"/"dig"/etc.
signal tile_action_triggered(action: StringName, tiles: Array)

## 地块操作完成。action: "plow"/"dig"/etc., count: 成功转化的数量。
signal tile_action_completed(action: StringName, tiles: Array, count: int)

## 请求收获指定地块上的作物。由 [TileActions] 发出，[Crop] 监听并自行收获。
## 这样作物可以自主管理收获逻辑，避免 TileActions 通过 duck typing 调用 harvest()。
signal crop_harvest_requested(tile: Node2D)

## 作物被收获（携带产物列表和作物标识）。
## 由 [Crop.harvest] 发出，[Storage] 等系统监听以收集产物。
## [param yields] 产物数组（[Array] of [Dictionary]）：{ "item_id": String, "amount": float }
## [param crop_id] 收获的作物标识（如 "wheat_tier1"）。
signal crop_harvested(yields: Array, crop_id: String)

# ---- 作战单位事件 ----

## 工人任务完成。
## 由 [UnitManager] 在工人完成一个任务时发出。
## [param task] 为 TaskData 实例。
signal worker_task_completed(worker_id: StringName, task)

## 工人任务失败。
## 由 [FarmWorker] 在任务执行失败时发出。
signal worker_task_failed(worker_id: StringName, task, reason: String)

## 工人队列清空（全部任务完成）。
## 由 [FarmWorker] 发出。
signal worker_queue_empty(worker_id: StringName)

## 工人状态变化。
## 由 [FarmWorker] 发出。
signal worker_state_changed(worker_id: StringName, old_state: int, new_state: int)

# ---- 地块分配 ----

## 地块被分配给某种作物进行自动耕作。
## 由 [FarmlandManager.assign_tiles] 发出。
## [param tiles] 分配的网格坐标数组（[Array] of [Vector2i]）。
## [param crop_id] 作物标识（如 "wheat_tier1"）。
signal farmland_assigned(tiles: Array, crop_id: String)

## 地块的自动耕作分配被移除。
## 由 [FarmlandManager.unassign_tiles] 发出。
## [param tiles] 取消分配的网格坐标数组（[Array] of [Vector2i]）。
signal farmland_unassigned(tiles: Array)

## 采集动作被触发（用于 UI 反馈/音效等）。
## [param action] 采集动作类型（如 "dig", "chop", "fish"）。
## [param tiles] 目标地块数组（[Array] of [Vector2i]）。
signal gather_action_triggered(action: StringName, tiles: Array)

# ---- 作物生长 ----

## 作物生长阶段转变。
## 由 [Crop._advance_stage] 在每次阶段推进时发出。
## [param crop_node] 发出信号的作物节点引用。
## [param grid_pos] 作物所在地块的网格坐标。
## [param crop_id] 作物标识（如 "wheat_tier1"）。
## [param old_stage] 转变前的阶段索引。
## [param new_stage] 转变后的阶段索引。
## [param is_mature] 是否已达到成熟阶段。
signal crop_stage_changed(crop_node: Node2D, grid_pos: Vector2i, crop_id: String, old_stage: int, new_stage: int, is_mature: bool)

## 作物达到成熟阶段（可收获）。
## 由 [Crop._advance_stage] 在进入最终阶段时发出。
## 供 [FarmlandManager] 监听以自动创建 HARVEST 任务。
## [param crop_node] 成熟的作物节点引用。
## [param grid_pos] 作物所在地块的网格坐标。
## [param crop_id] 成熟的作物标识。
signal crop_matured(crop_node: Node2D, grid_pos: Vector2i, crop_id: String)

# ---- UI 相关 ----

## 模式选择器切换模式。
## 由 [ModeSelector] 发出，[TileSelector] 等系统监听以调整行为。
## [param mode_id] 新模式标识，如 "cursor"、"gather"、"wheat_tier1"。
signal mode_changed(mode_id: StringName)

## 地块修饰器发生变化（MODIFIER 道具添加/移除/数量变化）。
## 由 [PropManager] 发出，[BaseTile] 等监听以重新计算地块属性。
signal tile_modifiers_changed()

# ---- 战斗单位事件 ----

## 技能施放开始时发出。
## 由 [CombatUnitBase.start_skill] 发出。
signal skill_cast_started(unit_id: StringName, skill_id: StringName, target_id: StringName)

## 技能命中目标时发出。
## 由 [CombatUnitBase.deal_damage_to] 发出。
signal skill_hit(caster_id: StringName, target_id: StringName, skill_id: StringName, damage: float, is_crit: bool)

## 技能施放完成时发出。
## 由 [CombatUnitBase._finish_skill] 发出。
signal skill_cast_finished(unit_id: StringName, skill_id: StringName)

## 单位被击杀时发出。
## 由 [CombatUnitBase._die] 发出。
signal unit_killed(killed_id: StringName, killer_id: StringName)

## 单位生命值变化时发出。
## 由 [CombatUnitBase.take_damage] / [CombatUnitBase.heal] 发出。
signal unit_health_changed(unit_id: StringName, old_health: float, new_health: float)

## 单位法力值变化时发出。
## 由 [CombatUnitBase.restore_mana] / [CombatUnitBase._finish_skill] 发出。
signal unit_mana_changed(unit_id: StringName, old_mana: float, new_mana: float)

## Buff 被应用时发出。
## 由 [CombatUnitBase.apply_buff] 发出。
signal unit_buff_applied(unit_id: StringName, buff_id: StringName)

## Buff 过期/被移除时发出。
## 由 [CombatUnitBase.remove_buff] 发出。
signal unit_buff_expired(unit_id: StringName, buff_id: StringName)

## 弹射物被发射时发出。
## 由 [CombatUnitBase._try_spawn_projectile] 发出。
signal projectile_fired(projectile_id: StringName, skill_id: StringName, from_unit_id: StringName)

## 弹射物命中目标时发出（预留 Phase 5）。
signal projectile_hit(projectile_id: StringName, target_id: StringName)

## 指令系统信号（Phase 3+）

## 指令被发出时广播。
## [param command_type] 指令类型（int，对应 CombatTask.CombatTaskType）。
## [param params] 指令参数字典。
signal command_issued(command_type: int, params: Dictionary)

## 全体集合指令覆盖。所有友方单位收到后立即移动到集结点。
signal command_override_rally(position: Vector2)

## 全体撤退指令覆盖。所有友方单位收到后立即移动到撤退点。
signal command_override_retreat(position: Vector2)

## 全体原地待命指令覆盖。所有友方单位收到后停止当前任务。
signal command_override_hold()

## 战斗任务被分配到单位时发出。
signal combat_task_assigned(unit_id: StringName, task_id: int)

## 战斗任务完成时发出。
signal combat_task_completed(unit_id: StringName, task_id: int)

## 战斗任务被全局指令覆盖时发出。
signal combat_task_overridden(unit_id: StringName, task_id: int)

## 敌方单位生成时发出。
signal enemy_spawned(enemy_id: StringName, wave_number: int)

## 敌方波次开始时发出。
signal enemy_wave_started(wave_number: int)

## 敌方波次清除时发出。
signal enemy_wave_cleared(wave_number: int)

## 战利品被单位采集时发出。
## [param unit_id] 采集者的单位 ID。
## [param loot_name] 被采集的战利品节点名。
signal loot_collected(unit_id: StringName, loot_name: StringName)

## 小队任务整体完成时发出。
## 由 [SquadTaskTracker] 在确认所有成员满足完成条件后发出。
## [param squad_id] 完成的小队 ID。
signal squad_task_completed(squad_id: StringName)
