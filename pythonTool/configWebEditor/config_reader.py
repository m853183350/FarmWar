"""
Config file scanner — recursively reads the config directory and parses all JSON files.
Each file is returned as a ParsedFile with its path, data, and structure signature.
"""
import json
import os
from typing import Optional


class ParsedFile:
	"""Represents a single parsed JSON config file."""

	def __init__(self, rel_path: str, abs_path: str, data, top_level_keys: tuple, top_level_type: str):
		self.rel_path: str = rel_path
		self.abs_path: str = abs_path
		self.data = data
		self.top_level_keys: tuple = top_level_keys  # sorted tuple of top-level keys (for grouping)
		self.top_level_type: str = top_level_type  # "object", "array", or "map"

	@property
	def filename(self) -> str:
		return os.path.basename(self.rel_path)

	@property
	def parent_dir(self) -> str:
		return os.path.dirname(self.rel_path).replace("\\", "/")


def _get_top_level_keys(data) -> tuple:
	"""Return sorted tuple of top-level keys for structure comparison."""
	if isinstance(data, dict):
		return tuple(sorted(data.keys()))
	elif isinstance(data, list) and len(data) > 0 and isinstance(data[0], dict):
		# For arrays of objects, use first item's keys as signature
		return tuple(sorted(data[0].keys()))
	return ()


def _classify_type(data) -> str:
	"""
	Classify the top-level JSON type.
	- "array" : top-level is a list
	- "map"   : top-level is a dict whose values are ALL dicts (keyed collection)
	- "object": top-level is a dict (not a map)
	"""
	if isinstance(data, list):
		return "array"
	if isinstance(data, dict):
		if len(data) > 0 and all(isinstance(v, dict) for v in data.values()):
			return "map"
		return "object"
	return "object"


def scan_config_dir(config_dir: str) -> list[ParsedFile]:
	"""
	Recursively scan `config_dir` for all .json files.
	Returns a list of ParsedFile objects.
	"""
	files: list[ParsedFile] = []
	abs_config_dir: str = os.path.abspath(config_dir)

	if not os.path.isdir(abs_config_dir):
		print(f"[config_reader] WARNING: config dir not found: {abs_config_dir}")
		return files

	for root, dirs, filenames in os.walk(abs_config_dir):
		for fname in filenames:
			if not fname.endswith(".json"):
				continue
			abs_path: str = os.path.join(root, fname)
			rel_path: str = os.path.relpath(abs_path, abs_config_dir).replace("\\", "/")

			try:
				with open(abs_path, "r", encoding="utf-8") as f:
					data = json.load(f)
				# File is closed immediately — no handle held
			except (json.JSONDecodeError, IOError) as e:
				print(f"[config_reader] WARNING: failed to parse {rel_path}: {e}")
				continue

			tl_keys: tuple = _get_top_level_keys(data)
			tl_type: str = _classify_type(data)
			files.append(ParsedFile(rel_path, abs_path, data, tl_keys, tl_type))

	return files
