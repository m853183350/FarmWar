"""
Notes store — SQLite-based persistence for per-field annotations.
Uses a single table with config_key as the unique identifier.
config_key format: "relative/path/file.json#json.path.to.field"
DB only stores notes — JSON data is managed entirely in memory by the server.
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
		with sqlite3.connect(self._db_path) as conn:
			conn.execute("""
				CREATE TABLE IF NOT EXISTS notes (
					config_key TEXT PRIMARY KEY,
					note_text TEXT DEFAULT '',
					updated_at TEXT DEFAULT (datetime('now', 'localtime'))
				)
			""")
			conn.commit()

	def set_note(self, config_key: str, note_text: str) -> None:
		"""Insert or update a note by config_key."""
		with sqlite3.connect(self._db_path) as conn:
			conn.execute(
				"""INSERT INTO notes (config_key, note_text, updated_at)
				   VALUES (?, ?, datetime('now', 'localtime'))
				   ON CONFLICT(config_key)
				   DO UPDATE SET note_text = excluded.note_text,
				                 updated_at = datetime('now', 'localtime')""",
				(config_key, note_text)
			)
			conn.commit()

	def delete_note(self, config_key: str) -> None:
		"""Delete a note by config_key."""
		with sqlite3.connect(self._db_path) as conn:
			conn.execute("DELETE FROM notes WHERE config_key = ?", (config_key,))
			conn.commit()

	def get_notes_by_prefix(self, prefix: str) -> dict[str, str]:
		"""
		Get all notes whose config_key starts with `prefix`.
		Returns dict of config_key → note_text.
		"""
		with sqlite3.connect(self._db_path) as conn:
			rows = conn.execute(
				"SELECT config_key, note_text FROM notes WHERE config_key LIKE ? ORDER BY config_key",
				(prefix + "%",)
			).fetchall()
		return {config_key: note_text for config_key, note_text in rows}

	def get_all_notes(self) -> dict[str, str]:
		"""Get all notes as config_key → note_text."""
		with sqlite3.connect(self._db_path) as conn:
			rows = conn.execute(
				"SELECT config_key, note_text FROM notes ORDER BY config_key"
			).fetchall()
		return {config_key: note_text for config_key, note_text in rows}
