## JSON 配置文件加载工具。
##
## 提供从 JSON 文件加载配置的统一入口，封装文件存在性检查、解析、
## 错误日志等逻辑，避免各处重复编写相同的加载/解析代码。
##
## 使用方式：
##   [code]const JsonConfigLoader = preload("res://scripts/utils/json_loader.gd")[/code]
##   [code]var config: Dictionary = JsonConfigLoader.load_config_file("res://config/units/farm_worker.json", "FarmWorker")[/code]
extends RefCounted

# ============================================================
# 7. @onready 变量
# ============================================================

# ============================================================
# 6. 私有变量
# ============================================================

## 配置缓存。key 为文件路径，value 为解析后的 [Dictionary]。
static var _cache: Dictionary = {}

# ============================================================
# 9. 静态方法 — JSON 配置加载
# ============================================================

## 从文件路径加载并解析 JSON 配置文件（带缓存）。
##
## 首次加载时从磁盘读取并解析 JSON，结果存入缓存。
## 后续请求同一 [param path] 时直接返回缓存，避免重复 IO 和解析。
## 大部分配置文件在游戏过程中不会被修改，因此缓存是安全的。
##
## 封装了文件存在性检查、打开、JSON 解析、类型验证等完整流程。
## 任一环节失败时通过 [method @GlobalScope.push_error] 输出带 [param caller]
## 前缀的错误信息，并返回空 [Dictionary]。
##
## [param path] JSON 文件路径（如 [code]"res://config/units/farm_worker.json"[/code]）。
## [param caller] 调用类名，用于错误信息前缀（如 [code]"FarmWorker"[/code]）。
##   留空时不输出类名前缀。
##
## 返回解析后的 [Dictionary]；加载或解析失败时返回空 [Dictionary]。
static func load_config_file(path: String, caller: String = "") -> Dictionary:
	if _cache.has(path):
		return _cache[path]

	var config: Dictionary = _read_config_file(path, caller)
	if not config.is_empty():
		_cache[path] = config
	return config

## 强制重新读取配置文件并刷新缓存。
##
## 与 [method load_config_file] 不同，此方法始终从磁盘重新读取，
## 并用新数据覆盖缓存。适用于配置文件可能被动态修改的场景。
##
## [param path] JSON 文件路径。
## [param caller] 调用类名，用于错误信息前缀。
##
## 返回重新解析后的 [Dictionary]；加载或解析失败时保留旧缓存不变，返回空 [Dictionary]。
static func reload_config_file(path: String, caller: String = "") -> Dictionary:
	var config: Dictionary = _read_config_file(path, caller)
	if not config.is_empty():
		_cache[path] = config
	return config

## 清除指定路径的缓存，或清除全部缓存。
##
## [param path] 要清除的配置文件路径。留空时清除所有缓存。
static func clear_cache(path: String = "") -> void:
	if path.is_empty():
		_cache.clear()
	elif _cache.has(path):
		_cache.erase(path)

# ============================================================
# 10. 私有方法
# ============================================================

## 实际从磁盘读取并解析 JSON 文件（内部方法，不涉及缓存）。
##
## [param path] JSON 文件路径。
## [param caller] 调用类名，用于错误信息前缀。
##
## 返回解析后的 [Dictionary]；失败时返回空 [Dictionary]。
static func _read_config_file(path: String, caller: String) -> Dictionary:
	var prefix: String = ""
	if not caller.is_empty():
		prefix = "%s: " % caller

	if not FileAccess.file_exists(path):
		push_error("%s配置文件不存在: %s" % [prefix, path])
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("%s无法打开配置文件: %s" % [prefix, path])
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(text)
	if err != OK:
		push_error("%sJSON 解析失败 (行 %d): %s" % [prefix, json.get_error_line(), json.get_error_message()])
		return {}

	var data = json.data
	if data is Dictionary:
		return data as Dictionary

	push_error("%s配置文件顶层应为 JSON 对象" % prefix)
	return {}
