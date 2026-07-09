"""
Table builder — groups ParsedFile objects into tables and flattens nested structures.
"""
import json
from typing import Any, Optional

from config_reader import ParsedFile

# Sentinel to mark a column whose values should be displayed as inline JSON
ARRAY_OF_OBJECTS_SENTINEL = "__aoo__"


class TableDef:
	"""Metadata for a table group."""

	def __init__(self, table_id: str, display_name: str, mode: str):
		self.table_id: str = table_id
		self.display_name: str = display_name
		self.mode: str = mode  # "file-as-row" | "key-as-row" | "single-object" | "array"
		self.columns: list[str] = []  # ordered column paths
		self.column_types: dict[str, str] = {}  # column_path -> "str"|"int"|"float"|"bool"|"json"
		self.sub_tables: dict[str, list] = {}  # column_path -> list of sub-table data for each row


class TableData:
	"""Full data for a table (columns + rows + value map)."""

	def __init__(self, table_def: TableDef):
		self.table_def: TableDef = table_def
		# rows: list of { "row_key": str, "row_label": str, "_file": str, "_key_in_file": str|None, "cells": {col: value} }
		self.rows: list[dict] = []


def _flatten_dict(d: dict, prefix: str = "", max_depth: int = 3) -> dict[str, Any]:
	"""
	Flatten a nested dict to dot-notation keys.
	Arrays of primitives become comma-joined strings.
	Arrays of objects become JSON strings (marked for sub-table expansion).
	Objects deeper than max_depth become JSON strings.
	"""
	result: dict[str, Any] = {}
	for key, value in d.items():
		full_key: str = f"{prefix}.{key}" if prefix else key
		if isinstance(value, dict):
			if prefix.count(".") >= max_depth - 1:
				result[full_key] = json.dumps(value, ensure_ascii=False)
			else:
				result.update(_flatten_dict(value, full_key, max_depth))
		elif isinstance(value, list):
			if len(value) == 0:
				result[full_key] = "[]"
			elif isinstance(value[0], dict):
				# Array of objects — store as JSON string, mark as expandable
				result[full_key] = json.dumps(value, ensure_ascii=False)
			else:
				# Array of primitives — comma-join
				result[full_key] = ", ".join(str(v) for v in value)
		else:
			result[full_key] = value
	return result


def _infer_column_type(sample_values: list) -> str:
	"""Infer the type of a column from sample values."""
	for v in sample_values:
		if v is None:
			continue
		if isinstance(v, bool):
			return "bool"
		if isinstance(v, int):
			return "int"
		if isinstance(v, float):
			return "float"
		if isinstance(v, str):
			# Check if it looks like JSON (array of objects marker)
			s = v.strip()
			if s.startswith("[") and s.endswith("]") and len(s) > 2:
				try:
					parsed = json.loads(s)
					if isinstance(parsed, list) and len(parsed) > 0 and isinstance(parsed[0], dict):
						return "json_array"
				except json.JSONDecodeError:
					pass
			return "str"
	return "str"


def _unflatten_value(flat_dict: dict[str, Any]) -> dict:
	"""
	Reverse _flatten_dict: convert dot-notation keys back to nested dict/list structure.
	Only handles the object-flattening case (not arrays-of-objects).
	"""
	result: dict = {}
	for key, value in flat_dict.items():
		parts: list[str] = key.split(".")
		current: dict = result
		for i, part in enumerate(parts[:-1]):
			if part not in current:
				current[part] = {}
			if not isinstance(current[part], dict):
				current[part] = {}
			current = current[part]
		# Try to parse numbers back
		current[parts[-1]] = _parse_value(value)
	return result


def _parse_value(value) -> Any:
	"""Parse a string value back to its likely original type."""
	if isinstance(value, str):
		s: str = value.strip()
		# Boolean
		if s.lower() == "true":
			return True
		if s.lower() == "false":
			return False
		if s.lower() == "null" or s == "":
			return None
		# Integer
		try:
			if "." not in s and "e" not in s.lower():
				return int(s)
		except ValueError:
			pass
		# Float
		try:
			return float(s)
		except ValueError:
			pass
		# JSON array/object
		if (s.startswith("[") and s.endswith("]")) or (s.startswith("{") and s.endswith("}")):
			try:
				return json.loads(s)
			except json.JSONDecodeError:
				pass
	return value


def _parse_cell_value_for_save(value, original_value) -> Any:
	"""
	Convert an edited cell value back to the original type.
	If original was a list, try to parse it back.
	If original was int/float, cast back.
	"""
	if value is None:
		return None

	if isinstance(original_value, bool):
		if isinstance(value, bool):
			return value
		if isinstance(value, str):
			return value.lower() == "true"

	if isinstance(original_value, int):
		try:
			return int(value)
		except (ValueError, TypeError):
			return value

	if isinstance(original_value, float):
		try:
			return float(value)
		except (ValueError, TypeError):
			return value

	if isinstance(original_value, list):
		if isinstance(value, str):
			try:
				return json.loads(value)
			except json.JSONDecodeError:
				# May be comma-separated values
				return [v.strip() for v in value.split(",") if v.strip()]
		return value

	return value


def build_tables(parsed_files: list[ParsedFile]) -> list[TableData]:
	"""
	Group parsed files into tables and flatten data for display.
	Returns a list of TableData objects ready for the frontend.
	"""
	table_datas: list[TableData] = []

	# --- Step 1: Group files ---
	# Group by (parent_dir, top_level_keys) for file-as-row mode
	group_key_to_files: dict[tuple, list[ParsedFile]] = {}
	single_files: list[ParsedFile] = []

	for pf in parsed_files:
		group_key: tuple = (pf.parent_dir, pf.top_level_keys)
		if group_key not in group_key_to_files:
			group_key_to_files[group_key] = []
		group_key_to_files[group_key].append(pf)

	# Separate: groups with 2+ files → file-as-row; singles → other modes
	multi_file_groups: dict[tuple, list[ParsedFile]] = {}
	for gk, files in group_key_to_files.items():
		if len(files) >= 2:
			multi_file_groups[gk] = files
		else:
			single_files.extend(files)

	# --- Step 2: Build file-as-row tables ---
	for gk, files in multi_file_groups.items():
		parent_dir, tl_keys = gk
		table_id: str = parent_dir if parent_dir else "root"
		display_name: str = table_id.replace("/", " › ")

		table_def: TableDef = TableDef(table_id, display_name, "file-as-row")
		# Collect all flattened columns across all files
		all_columns: set[str] = set()
		flattened_rows: list[dict] = []

		for pf in files:
			if pf.top_level_type in ("object", "map"):
				flat: dict[str, Any] = _flatten_dict(pf.data)
			elif pf.top_level_type == "array":
				# Top-level array — just store as JSON for now
				flat = {"_data": json.dumps(pf.data, ensure_ascii=False)}
			else:
				flat = {}
			all_columns.update(flat.keys())
			flattened_rows.append({
				"flat": flat,
				"pf": pf,
			})

		# Determine column order: put likely "id" columns first, then alphabetical
		id_candidates: set[str] = {"unit_type", "prop_id", "crop_id", "skill_id", "id", "display_name"}
		id_cols: list[str] = [c for c in id_candidates if c in all_columns]
		other_cols: list[str] = sorted(all_columns - set(id_cols))
		ordered_columns: list[str] = id_cols + other_cols
		table_def.columns = ordered_columns

		# Build rows
		for fr in flattened_rows:
			pf: ParsedFile = fr["pf"]
			# Determine row key from the data (use first id-like field) or filename
			row_key: str = pf.filename
			row_label: str = pf.filename
			for id_col in id_cols:
				if id_col in fr["flat"]:
					row_key = str(fr["flat"][id_col])
					row_label = str(fr["flat"][id_col])
					break

			cells: dict[str, Any] = {}
			for col in ordered_columns:
				val = fr["flat"].get(col)
				if val is None:
					cells[col] = ""
				elif isinstance(val, bool):
					cells[col] = val
				elif isinstance(val, (int, float)):
					cells[col] = val
				else:
					cells[col] = str(val)

			table_data_row = {
				"row_key": row_key,
				"row_label": row_label,
				"_file": pf.rel_path,
				"_key_in_file": None,
				"_original_data": pf.data,
				"cells": cells,
			}
			table_def.column_types = {}
			for col in ordered_columns:
				samples: list = [r["cells"].get(col) for r in [table_data_row]]
				table_def.column_types[col] = _infer_column_type(samples)

			td: TableData = _find_or_create_table_data(table_datas, table_def)
			td.rows.append(table_data_row)

		# Recompute column types across all rows
		for col in ordered_columns:
			samples = [r["cells"].get(col) for r in td.rows]
			td.table_def.column_types[col] = _infer_column_type(samples)

	# --- Step 3: Build single-file tables ---
	for pf in single_files:
		parent_dir: str = pf.parent_dir
		table_id: str = pf.rel_path
		display_name: str = pf.rel_path.replace("/", " › ")

		if pf.top_level_type == "map":
			# Key-as-row mode: expand top-level keys into rows
			table_def = TableDef(table_id, display_name, "key-as-row")
			all_columns_set: set[str] = set()
			flattened_entries: list[dict] = []

			for key, sub_obj in pf.data.items():
				flat = _flatten_dict(sub_obj)
				all_columns_set.update(flat.keys())
				flattened_entries.append({"key": key, "flat": flat})

			id_cols_map: list[str] = [c for c in id_candidates if c in all_columns_set]
			other_cols_map: list[str] = sorted(all_columns_set - set(id_cols_map))
			ordered_cols: list[str] = id_cols_map + other_cols_map
			table_def.columns = ordered_cols

			td_map: TableData = _find_or_create_table_data(table_datas, table_def)
			for entry in flattened_entries:
				cells: dict[str, Any] = {}
				for col in ordered_cols:
					val = entry["flat"].get(col)
					if val is None:
						cells[col] = ""
					elif isinstance(val, bool):
						cells[col] = val
					elif isinstance(val, (int, float)):
						cells[col] = val
					else:
						cells[col] = str(val)

				td_map.rows.append({
					"row_key": f"{pf.rel_path}#{entry['key']}",
					"row_label": entry["key"],
					"_file": pf.rel_path,
					"_key_in_file": entry["key"],
					"_original_data": pf.data[entry["key"]],
					"cells": cells,
				})

			for col in ordered_cols:
				samples = [r["cells"].get(col) for r in td_map.rows]
				td_map.table_def.column_types[col] = _infer_column_type(samples)

		elif pf.top_level_type == "array":
			# Array mode: each item is a row
			table_def = TableDef(table_id, display_name, "array")
			all_columns_set_arr: set[str] = set()
			flat_items: list[dict] = []

			for idx, item in enumerate(pf.data):
				if isinstance(item, dict):
					flat = _flatten_dict(item)
					all_columns_set_arr.update(flat.keys())
					flat_items.append({"idx": idx, "flat": flat})

			ordered_cols_arr: list[str] = sorted(all_columns_set_arr)
			table_def.columns = ordered_cols_arr

			td_arr: TableData = _find_or_create_table_data(table_datas, table_def)
			for item in flat_items:
				cells = {}
				for col in ordered_cols_arr:
					val = item["flat"].get(col)
					if val is None:
						cells[col] = ""
					elif isinstance(val, bool):
						cells[col] = val
					elif isinstance(val, (int, float)):
						cells[col] = val
					else:
						cells[col] = str(val)

				td_arr.rows.append({
					"row_key": f"{pf.rel_path}[{item['idx']}]",
					"row_label": f"[{item['idx']}]",
					"_file": pf.rel_path,
					"_key_in_file": item["idx"],
					"_original_data": pf.data[item["idx"]] if isinstance(pf.data, list) else {},
					"cells": cells,
				})

			for col in ordered_cols_arr:
				samples = [r["cells"].get(col) for r in td_arr.rows]
				td_arr.table_def.column_types[col] = _infer_column_type(samples)

		elif pf.top_level_type == "object":
			# Single object — one row per file (fallback for non-map objects)
			table_def = TableDef(table_id, display_name, "single-object")
			flat = _flatten_dict(pf.data)
			ordered_cols_obj: list[str] = sorted(flat.keys())
			table_def.columns = ordered_cols_obj

			cells = {}
			for col in ordered_cols_obj:
				val = flat.get(col)
				if val is None:
					cells[col] = ""
				elif isinstance(val, bool):
					cells[col] = val
				elif isinstance(val, (int, float)):
					cells[col] = val
				else:
					cells[col] = str(val)

			td_obj: TableData = _find_or_create_table_data(table_datas, table_def)
			td_obj.rows.append({
				"row_key": pf.filename,
				"row_label": pf.filename,
				"_file": pf.rel_path,
				"_key_in_file": None,
				"_original_data": pf.data,
				"cells": cells,
			})

			for col in ordered_cols_obj:
				samples = [r["cells"].get(col) for r in td_obj.rows]
				td_obj.table_def.column_types[col] = _infer_column_type(samples)

	return table_datas


def _find_or_create_table_data(table_datas: list[TableData], table_def: TableDef) -> TableData:
	"""Find existing TableData by table_id, or create a new one."""
	for td in table_datas:
		if td.table_def.table_id == table_def.table_id:
			return td
	td = TableData(table_def)
	table_datas.append(td)
	return td


def reconstruct_and_save(table_data: TableData, config_dir: str) -> list[str]:
	"""
	Reconstruct JSON from table cells and write back to original files.
	Returns list of saved file paths.
	"""
	saved: list[str] = []
	abs_config_dir: str = os.path.abspath(config_dir)

	# Group rows by their _file path
	file_to_rows: dict[str, list[dict]] = {}
	for row in table_data.rows:
		fpath: str = row["_file"]
		if fpath not in file_to_rows:
			file_to_rows[fpath] = []
		file_to_rows[fpath].append(row)

	for rel_path, rows in file_to_rows.items():
		abs_path: str = os.path.join(abs_config_dir, rel_path)

		if table_data.table_def.mode == "key-as-row":
			# Rebuild a map object: top-level keys → nested objects
			result: dict = {}
			for row in rows:
				key: str = row["_key_in_file"]
				if key is None:
					continue
				# Rebuild the sub-object from flattened cells
				# Exclude special columns
				flat_cells: dict[str, Any] = {
					k: _parse_cell_value_for_save(v, row.get("_original_data", {}).get(k, v))
					for k, v in row["cells"].items()
				}
				result[key] = _unflatten_value(flat_cells)
		elif table_data.table_def.mode == "array":
			result = []
			rows_sorted: list[dict] = sorted(rows, key=lambda r: r["_key_in_file"] if isinstance(r["_key_in_file"], int) else 0)
			for row in rows_sorted:
				flat_cells = {
					k: _parse_cell_value_for_save(v, row.get("_original_data", {}).get(k, v))
					for k, v in row["cells"].items()
				}
				result.append(_unflatten_value(flat_cells))
		else:
			# file-as-row or single-object: each row is one file
			row = rows[0]
			flat_cells = {
				k: _parse_cell_value_for_save(v, row.get("_original_data", {}).get(k, v))
				for k, v in row["cells"].items()
			}
			result = _unflatten_value(flat_cells)

		# Write via temp file for safety
		import os as _os
		tmp_path: str = abs_path + ".tmp"
		try:
			with open(tmp_path, "w", encoding="utf-8") as f:
				json.dump(result, f, ensure_ascii=False, indent="\t")
			_os.replace(tmp_path, abs_path)
			saved.append(rel_path)
		except IOError as e:
			print(f"[table_builder] ERROR saving {rel_path}: {e}")
			if _os.path.exists(tmp_path):
				_os.remove(tmp_path)

	return saved
