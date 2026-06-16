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

The project is at the design phase. `main.tscn` is an empty `Node2D` scene. No scripts, scenes, resources, or assets have been created yet. The coding standards and game design are documented; implementation is about to begin.
