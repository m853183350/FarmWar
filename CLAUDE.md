# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**FarmWar (农场战争)** — a 2D top-down strategy game built in Godot 4.6. Players grow crops as the primary resource, then use harvests to build automation, defenses, and armies to survive enemy attacks and win. One session lasts 20–60 minutes (10 min on easy mode).

## Engine & Configuration

- **Godot 4.6.3** (editor: `Godot_v4.6.3-stable_win64.exe`)
- Renderer: `mobile` (even on PC)
- Physics: Jolt Physics
- Viewport: 1920×1080
- No addons, no export presets yet
- 开发环境：vscode terminal in Windows 11

## Common Commands

```bash
# Run the project (editor)
godot -e

# Run the project (game only, no editor)
godot

# Run a specific scene
godot scenes/some_scene.tscn

# Headless run (for CI/automation)
godot --headless

# Run editor unit tests
godot --test

# Export the project
godot --export-release "Windows Desktop" build/

# Edit with python3
python
# not python3
```

## Architecture (Planned)

The game is divided into **in-match systems** and **meta-game systems**:

见 /Docs/整体设计.md

## Directory Structure

**important** from `Docs/目录结构.md`. AI can edit this file when necessary.

## Coding Standards (from `Docs/代码规范.md`)

**Language:** GDScript (Godot 4.6 syntax). Tabs for indentation, UTF-8, LF line endings, max 120 chars per line.

**Naming:**
| What | Rule | Example |
|------|------|---------|
| Files/dirs | `snake_case` | `player_controller.gd` |
| Classes | `PascalCase` | `PlayerController` |
| Variables/functions | `snake_case` | `move_speed`, `take_damage()` |
| Constants/enums | `UPPER_SNAKE_CASE` | `MAX_HEALTH`, `State.IDLE` |
| Signals | `snake_case`, past tense | `health_changed`, `died` |
| Private members | `_` prefix | `_current_health`, `_on_timer()` |

**Key rules:**
- **Strict static typing** — all variables, parameters, and return types must be explicitly typed. Never rely on type inference except `:=` for constants.
- One class per file, class name matches file name.
- Use `@onready var x: Type = $NodePath` for child references — never `get_node()` in `_ready()`.
- `preload` commonly-used resources at the top as constants; `load` for runtime-only assets.
- Node references use `$` with unique node names; never use `get_node("..")` for upward traversal.
- **Composition over inheritance** — use child nodes + component scripts instead of deep class hierarchies.
- Use `Tween` for animations, not manual interpolation in `_process`.
- Signals connected dynamically (`.connect()`) must be disconnected in `_exit_tree()`.
- `match` over long `if-elif` chains; `if` nesting max 3 levels deep.
- No magic numbers — use named constants.
- Autoloads (`scripts/autoload/`) for cross-scene shared logic; never cross-reference nodes between scenes.
- Scene root node type must match its script's `extends` type.
- One Scene can only have 1 script. If there's multiple scripts, use child node.
- If an object has more than 5 attributes, use json file in /config
- All files must use Tab indentation (width: 4 spaces)
- No trailing whitespace
- Use `utils/json_loader.gd` to load json config

**Class-internal declaration order:**
1. Signals
2. Enums
3. Constants
4. `@export` variables
5. Public variables
6. Private variables
7. `@onready` variables
8. Lifecycle methods (`_ready`, `_process`, etc.)
9. Public methods
10. Private methods

**Documentation:** Every `.gd` file gets a matching `.md` in `Docs/` (mirroring `scripts/` structure) covering: purpose, dependencies, public API, connected signals, and usage examples. Each class must have a `##` doc comment at the top. Signals and public methods should have `##` comments.

## Current State

项目已进入**早期实现阶段**。已完成的核心系统：

**已实现：**
- **TickSystem** — 逻辑时钟 Autoload（独立线程，20 tick/s，`auto_start=false`，由 GameRoot 显式启动）
- **EventBus** — 全局事件总线（21 个信号，含 `game_state_changed`，解耦系统间通信）
- **主菜单系统** — `MainMenu`（开始/加载/成就/设置/退出）+ `LoadingScreen`（后台预加载+进度条）+ `GameRoot`（游戏初始化）
- **场景切换流程** — `main_menu.tscn` → 确认对话框 → `loading_screen.tscn` → `game.tscn`
- **地块系统** — `BaseTile` + 4 种子类（DirtTile / FarmlandTile / StoneTile / OceanTile），`TerrainGenerator` 随机生成
- **作物系统** — `Crop` 基类 + `WheatTier1`，生长阶段 + Tick 驱动 + 收获产物
- **农场工人** — `FarmWorker`（extends UnitBase），任务队列驱动自动耕作循环
- **FarmlandManager** — 地块→作物分配 + 事件驱动的自动耕作（翻耕→种植→等待成熟→收获）
- **UnitManager** — 工人生命周期管理 + 任务分配（最近优先策略）
- **PathfindingManager** — 多套成本网格（ground/flying/aquatic） + 异步 A* 寻路 + 流场
- **TileActions / GatherActions** — 地块转化（翻耕/挖掘/种植/收获）+ 采集判定
- **ZIndexConfig** — 渲染排序系统（Y 轴排序 + 10 层类型优先级）
- **ModeSelector** — 模式切换 UI（光标/采集/作物）
- **Storage** — 分区仓库（监听收获事件自动入库）
- **DebugUI / DebugOverlay** — F3 调试叠加层（分左右两侧，F4/F5 翻页）

**已规划、未实现：**
- 经济/商店系统、建筑系统
- 敌人 AI、天气系统、科技树系统
- 局外系统（局外成长、设置、存档）
- 调试控制台（`/` 键命令输入）
- 音频管理器（AudioManager Autoload）
- 暂停菜单（ESC 键）
- 加载游戏、成就、设置界面

**当前地图规格：** 50×50（~2500 地块），可扩展到 200×200。项目入口为 `scenes/menu/main_menu.tscn`，游戏场景为 `scenes/game/game.tscn`（含 Camera2D、TileSelector、ModeSelector HUD）。`main.tscn` 已弃用待删除。
