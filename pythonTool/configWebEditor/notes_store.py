"""
Notes store — SQLite-based persistence for per-field annotations.
Notes are stored separately from the JSON files so they survive config reloads.
"""
import os
import sqlite3


class NotesStore:
	"""Manages per-field notes in a SQLite database."""

	def __init__(self, db_path: str):
		os.makedirs(os.path.dirname(db_path), exist_ok=True)
		self._db_path: str = db_path
		self._init_db()

	def _init_db(self) -> None:
		"""Create the notes table if it doesn't exist."""
		with sqlite3.connect(self._db_path) as conn:
			conn.execute("""
				CREATE TABLE IF NOT EXISTS notes (
					table_id TEXT NOT NULL,
					row_key TEXT NOT NULL,
					column_path TEXT NOT NULL,
					note_text TEXT DEFAULT '',
					updated_at TEXT DEFAULT (datetime('now', 'localtime')),
					PRIMARY KEY (table_id, row_key, column_path)
				)
			""")
			conn.commit()

	def get_notes_for_table(self, table_id: str) -> dict[str, str]:
		"""
		Get all notes for a table.
		Returns dict keyed by "<row_key>/<column_path>" → note_text.
		"""
		with sqlite3.connect(self._db_path) as conn:
			rows = conn.execute(
				"SELECT row_key, column_path, note_text FROM notes WHERE table_id = ? ORDER BY row_key, column_path",
				(table_id,)
			).fetchall()
		result: dict[str, str] = {}
		for row_key, col_path, note_text in rows:
			result[f"{row_key}/{col_path}"] = note_text
		return result

	def get_all_notes(self) -> dict[str, dict[str, str]]:
		"""
		Get all notes grouped by table_id.
		Returns { table_id: { "row_key/col_path": note_text } }
		"""
		result: dict[str, dict[str, str]] = {}
		with sqlite3.connect(self._db_path) as conn:
			rows = conn.execute(
				"SELECT table_id, row_key, column_path, note_text FROM notes ORDER BY table_id, row_key, column_path"
			).fetchall()
		for table_id, row_key, col_path, note_text in rows:
			if table_id not in result:
				result[table_id] = {}
			result[table_id][f"{row_key}/{col_path}"] = note_text
		return result

	def set_note(self, table_id: str, row_key: str, column_path: str, note_text: str) -> None:
		"""Insert or update a note."""
		with sqlite3.connect(self._db_path) as conn:
			conn.execute(
				"""INSERT INTO notes (table_id, row_key, column_path, note_text, updated_at)
				   VALUES (?, ?, ?, ?, datetime('now', 'localtime'))
				   ON CONFLICT(table_id, row_key, column_path)
				   DO UPDATE SET note_text = excluded.note_text, updated_at = datetime('now', 'localtime')""",
				(table_id, row_key, column_path, note_text)
			)
			conn.commit()

	def delete_note(self, table_id: str, row_key: str, column_path: str) -> None:
		"""Delete a note."""
		with sqlite3.connect(self._db_path) as conn:
			conn.execute(
				"DELETE FROM notes WHERE table_id = ? AND row_key = ? AND column_path = ?",
				(table_id, row_key, column_path)
			)
			conn.commit()
