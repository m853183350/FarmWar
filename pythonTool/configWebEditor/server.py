"""
Config Web Editor — Flask backend server.
Provides REST API for browsing, editing, and saving JSON config files.
"""
import argparse
import os
import sys

from flask import Flask, jsonify, render_template, request

# Ensure the tool directory is on sys.path for sibling imports
_script_dir: str = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
	sys.path.insert(0, _script_dir)

from config_reader import scan_config_dir, ParsedFile
from table_builder import build_tables, TableData, reconstruct_and_save, _parse_cell_value_for_save
from notes_store import NotesStore

app: Flask = Flask(__name__)

# --- Global state ---
_config_dir: str = ""
_notes_store: NotesStore | None = None
_tables: dict[str, TableData] = {}  # table_id -> TableData
_table_list: list[dict] = []  # summary list for the sidebar


def _get_config_dir() -> str:
	"""Resolve the config directory from CLI args or default location."""
	parser = argparse.ArgumentParser(description="Config Web Editor Server")
	parser.add_argument("--config-dir", default=None, help="Path to config directory")
	parser.add_argument("--port", type=int, default=5000, help="Server port")
	# Parse known args only (Flask may add its own)
	args, _ = parser.parse_known_args()

	if args.config_dir:
		return os.path.abspath(args.config_dir)
	# Default: ../../config relative to this script
	default: str = os.path.abspath(os.path.join(_script_dir, "..", "..", "config"))
	return default


def _get_port() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--port", type=int, default=5000)
	args, _ = parser.parse_known_args()
	return args.port


def _load_all_tables() -> None:
	"""Scan config dir and rebuild all tables."""
	global _tables, _table_list
	print(f"[server] Scanning config dir: {_config_dir}")
	parsed_files: list[ParsedFile] = scan_config_dir(_config_dir)
	table_datas: list[TableData] = build_tables(parsed_files)
	_tables = {}
	_table_list = []
	for td in table_datas:
		_tables[td.table_def.table_id] = td
		_table_list.append({
			"id": td.table_def.table_id,
			"display_name": td.table_def.display_name,
			"mode": td.table_def.mode,
			"row_count": len(td.rows),
			"column_count": len(td.table_def.columns),
			"columns": td.table_def.columns,
		})
	print(f"[server] Loaded {len(_tables)} tables from {len(parsed_files)} files")


# --- Routes ---


@app.route("/")
def index():
	"""Serve the single-page application."""
	return render_template("index.html")


@app.route("/api/tables")
def api_tables():
	"""Return list of all table summaries."""
	print(f"[DEBUG api_tables] _table_list len={len(_table_list)}, _tables len={len(_tables)}")
	return jsonify(_table_list)


@app.route("/api/tables/<path:table_id>")
def api_table_get(table_id: str):
	"""Get full data for a specific table, including notes."""
	td: TableData | None = _tables.get(table_id)
	if td is None:
		return jsonify({"error": f"Table not found: {table_id}"}), 404

	notes: dict[str, str] = _notes_store.get_notes_for_table(table_id) if _notes_store else {}

	return jsonify({
		"id": td.table_def.table_id,
		"display_name": td.table_def.display_name,
		"mode": td.table_def.mode,
		"columns": td.table_def.columns,
		"column_types": td.table_def.column_types,
		"rows": td.rows,
		"notes": notes,
	})


@app.route("/api/tables/<path:table_id>/cell", methods=["PUT"])
def api_table_update_cell(table_id: str):
	"""Update a single cell value in-memory (no file write)."""
	td: TableData | None = _tables.get(table_id)
	if td is None:
		return jsonify({"error": f"Table not found: {table_id}"}), 404

	body: dict = request.get_json()
	if body is None:
		return jsonify({"error": "Request body must be JSON"}), 400

	row_key: str | None = body.get("row_key")
	column: str | None = body.get("column")
	value = body.get("value")

	if not row_key or not column:
		return jsonify({"error": "row_key and column are required"}), 400

	for row in td.rows:
		if row["row_key"] == row_key:
			# Try to preserve original type
			original = row.get("_original_data", {})
			# For dot-notation columns, traverse nested dict
			if "." in column:
				parts = column.split(".")
				target = original
				for p in parts[:-1]:
					target = target.get(p, {}) if isinstance(target, dict) else {}
				orig_val = target.get(parts[-1]) if isinstance(target, dict) else None
			else:
				orig_val = original.get(column) if isinstance(original, dict) else None

			row["cells"][column] = _parse_cell_value_for_save(value, orig_val)
			return jsonify({"status": "ok"})

	return jsonify({"error": f"Row not found: {row_key}"}), 404


@app.route("/api/tables/<path:table_id>/save", methods=["POST"])
def api_table_save(table_id: str):
	"""Write in-memory changes back to JSON files."""
	td: TableData | None = _tables.get(table_id)
	if td is None:
		return jsonify({"error": f"Table not found: {table_id}"}), 404

	try:
		saved: list[str] = reconstruct_and_save(td, _config_dir)
		return jsonify({"status": "ok", "saved": saved})
	except Exception as e:
		return jsonify({"error": str(e)}), 500


@app.route("/api/refresh", methods=["POST"])
def api_refresh():
	"""Re-scan all config files and reload tables."""
	try:
		_load_all_tables()
		return jsonify({"status": "ok", "table_count": len(_tables)})
	except Exception as e:
		return jsonify({"error": str(e)}), 500


@app.route("/api/notes/<path:table_id>")
def api_notes_get(table_id: str):
	"""Get all notes for a table."""
	if _notes_store is None:
		return jsonify({})
	notes: dict[str, str] = _notes_store.get_notes_for_table(table_id)
	return jsonify(notes)


@app.route("/api/notes/<path:table_id>/<path:row_key>/<path:column>", methods=["PUT"])
def api_notes_set(table_id: str, row_key: str, column: str):
	"""Set a note for a specific cell."""
	if _notes_store is None:
		return jsonify({"error": "Notes store not initialized"}), 500
	body: dict = request.get_json()
	if body is None:
		return jsonify({"error": "Request body must be JSON"}), 400
	note_text: str = body.get("note_text", "")
	_notes_store.set_note(table_id, row_key, column, note_text)
	return jsonify({"status": "ok"})


@app.route("/api/notes/<path:table_id>/<path:row_key>/<path:column>", methods=["DELETE"])
def api_notes_delete(table_id: str, row_key: str, column: str):
	"""Delete a note."""
	if _notes_store is None:
		return jsonify({"error": "Notes store not initialized"}), 500
	_notes_store.delete_note(table_id, row_key, column)
	return jsonify({"status": "ok"})


@app.route("/api/subtable/<path:table_id>/<path:row_key>/<path:column>")
def api_subtable(table_id: str, row_key: str, column: str):
	"""Expand an array-of-objects column into a sub-table."""
	td: TableData | None = _tables.get(table_id)
	if td is None:
		return jsonify({"error": f"Table not found: {table_id}"}), 404

	# Find the row
	for row in td.rows:
		if row["row_key"] == row_key:
			cell_value = row["cells"].get(column, "")
			if isinstance(cell_value, str) and cell_value.strip().startswith("["):
				import json
				try:
					parsed = json.loads(cell_value)
					if isinstance(parsed, list) and len(parsed) > 0 and isinstance(parsed[0], dict):
						# Build columns from all keys
						cols: set[str] = set()
						for item in parsed:
							if isinstance(item, dict):
								cols.update(item.keys())
						cols_list: list[str] = sorted(cols)
						rows_out: list[dict] = []
						for idx, item in enumerate(parsed):
							cells = {}
							for c in cols_list:
								v = item.get(c, "")
								if isinstance(v, (dict, list)):
									cells[c] = json.dumps(v, ensure_ascii=False)
								else:
									cells[c] = str(v) if v is not None else ""
							rows_out.append({
								"row_key": f"{row_key}#{column}[{idx}]",
								"row_label": f"[{idx}]",
								"cells": cells,
							})
						return jsonify({
							"table_id": f"{table_id}/{row_key}/{column}",
							"columns": cols_list,
							"rows": rows_out,
						})
				except json.JSONDecodeError:
					pass
			return jsonify({"columns": [], "rows": []})

	return jsonify({"error": f"Row not found: {row_key}"}), 404


# --- Main ---

def main() -> None:
	global _config_dir, _notes_store

	_config_dir = _get_config_dir()
	port: int = _get_port()

	_db_path: str = os.path.join(_script_dir, "data", "notes.db")
	_notes_store = NotesStore(_db_path)

	print(f"[server] Config dir: {_config_dir}")
	print(f"[server] Database:  {_db_path}")
	print(f"[server] Port:      {port}")

	_load_all_tables()

	print(f"[server] Starting Flask on http://localhost:{port}")
	app.run(host="127.0.0.1", port=port, debug=False)


if __name__ == "__main__":
	main()
