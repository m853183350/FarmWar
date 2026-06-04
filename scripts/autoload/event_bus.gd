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
