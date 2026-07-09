/**
 * Config Web Editor — Frontend SPA
 * Handles table browsing, inline editing, save, notes, and sub-table expansion.
 */
(function () {
	"use strict";

	// --- State ---
	let tables = [];               // List of table summaries from /api/tables
	let activeTableId = null;      // Currently displayed table id
	let activeTableData = null;    // Full table data from /api/tables/<id>
	let dirtyCells = new Set();    // Set of "row_key:column" strings that have been modified
	let activeNoteCell = null;     // { table_id, row_key, column }

	// --- DOM refs ---
	const $ = (sel) => document.querySelector(sel);
	const $$ = (sel) => document.querySelectorAll(sel);

	const elTableNav = $("#table-nav");
	const elTableSearch = $("#table-search");
	const elTableTitle = $("#table-title");
	const elTableMeta = $("#table-meta");
	const elTableContainer = $("#table-container");
	const elTablePlaceholder = $("#table-placeholder");
	const elDirtyCounter = $("#dirty-counter");
	const elNotesPanel = $("#notes-panel");
	const elNotesCellPath = $("#notes-cell-path");
	const elNotesTextarea = $("#notes-textarea");
	const elSubtableOverlay = $("#subtable-overlay");
	const elSubtableTitle = $("#subtable-title");
	const elSubtableContainer = $("#subtable-container");
	const elToastContainer = $("#toast-container");

	// --- Toast ---
	function toast(msg, type) {
		type = type || "info";
		const el = document.createElement("div");
		el.className = "toast " + type;
		el.textContent = msg;
		if (!elToastContainer) {
			const c = document.createElement("div");
			c.id = "toast-container";
			document.body.appendChild(c);
		}
		(document.getElementById("toast-container") || document.body).appendChild(el);
		setTimeout(function () { el.remove(); }, 2500);
	}

	// --- API helpers ---
	async function apiGet(url) {
		const r = await fetch(url);
		if (!r.ok) throw new Error(r.status + " " + r.statusText);
		return r.json();
	}

	async function apiPut(url, body) {
		const r = await fetch(url, {
			method: "PUT",
			headers: { "Content-Type": "application/json" },
			body: JSON.stringify(body),
		});
		if (!r.ok) throw new Error(r.status + " " + r.statusText);
		return r.json();
	}

	async function apiPost(url, body) {
		const opts = {
			method: "POST",
			headers: { "Content-Type": "application/json" },
		};
		if (body !== undefined) opts.body = JSON.stringify(body);
		const r = await fetch(url, opts);
		if (!r.ok) throw new Error(r.status + " " + r.statusText);
		return r.json();
	}

	async function apiDelete(url) {
		const r = await fetch(url, { method: "DELETE" });
		if (!r.ok) throw new Error(r.status + " " + r.statusText);
		return r.json();
	}

	// --- Initialization ---
	async function init() {
		try {
			tables = await apiGet("/api/tables");
			renderSidebar(tables);
		} catch (e) {
			toast("Failed to load tables: " + e.message, "error");
		}
	}

	// --- Sidebar ---
	function renderSidebar(tableList) {
		if (!elTableNav) return;
		// Group tables by top-level directory
		const groups = {};
		tableList.forEach(function (t) {
			const parts = t.id.split("/");
			const group = parts.length > 1 ? parts[0] : "(root)";
			if (!groups[group]) groups[group] = [];
			groups[group].push(t);
		});

		const sortedGroups = Object.keys(groups).sort();
		let html = "";
		sortedGroups.forEach(function (g) {
			html += '<div class="table-nav-group">' + escHtml(g) + "</div>";
			groups[g].forEach(function (t) {
				const active = t.id === activeTableId ? " active" : "";
				html += '<button class="table-nav-item' + active + '" data-table-id="' + escHtml(t.id) + '">';
				html += escHtml(t.display_name || t.id);
				html += '<span class="item-count">' + t.row_count + "r</span>";
				html += "</button>";
			});
		});
		elTableNav.innerHTML = html;

		// Bind click events
		elTableNav.querySelectorAll(".table-nav-item").forEach(function (btn) {
			btn.addEventListener("click", function () {
				loadTable(this.dataset.tableId);
			});
		});
	}

	function updateSidebarActive() {
		elTableNav.querySelectorAll(".table-nav-item").forEach(function (btn) {
			btn.classList.toggle("active", btn.dataset.tableId === activeTableId);
		});
	}

	// --- Table loading ---
	async function loadTable(tableId) {
		activeTableId = tableId;
		updateSidebarActive();
		try {
			activeTableData = await apiGet("/api/tables/" + encodeURIComponent(tableId));
			dirtyCells = new Set();
			updateDirtyCounter();
			renderTable(activeTableData);
		} catch (e) {
			toast("Failed to load table: " + e.message, "error");
		}
	}

	function renderTable(data) {
		if (!elTableTitle || !elTableContainer || !elTableMeta) return;
		elTablePlaceholder.style.display = "none";

		elTableTitle.textContent = data.display_name || data.id;
		elTableMeta.textContent = data.mode + " · " + data.rows.length + " rows · " + data.columns.length + " columns";

		const cols = data.columns;
		const rows = data.rows;
		const colTypes = data.column_types || {};
		const notes = data.notes || {};

		let html = '<table class="data-table"><thead><tr>';
		html += '<th class="col-row-label">Row</th>';
		cols.forEach(function (c) {
			html += "<th>" + escHtml(c) + "</th>";
		});
		html += '<th class="col-notes">Notes</th>';
		html += "</tr></thead><tbody>";

		rows.forEach(function (row) {
			html += "<tr>";
			html += '<td class="row-label">' + escHtml(row.row_label) + "</td>";
			cols.forEach(function (col) {
				const cellKey = row.row_key + ":" + col;
				const dirty = dirtyCells.has(cellKey);
				const colType = colTypes[col] || "str";
				const val = row.cells[col];
				const noteKey = row.row_key + "/" + col;
				const hasNote = notes[noteKey] && notes[noteKey].trim();

				let cellClass = "";
				let displayVal = "";
				let dataAttrs = ' data-row-key="' + escHtml(row.row_key) + '" data-column="' + escHtml(col) + '"';

				if (colType === "bool") {
					cellClass = "bool " + (val === true || val === "true" ? "true" : "false");
					displayVal = val === true || val === "true" ? "✓ true" : "✗ false";
				} else if (colType === "int" || colType === "float") {
					cellClass = "number";
					displayVal = val !== undefined && val !== null ? String(val) : "";
				} else if (colType === "json_array") {
					cellClass = "json-array";
					displayVal = val || "";
					dataAttrs += ' data-json-array="1"';
				} else {
					displayVal = val !== undefined && val !== null ? String(val) : "";
				}

				if (dirty) cellClass += " dirty";

				html += '<td class="' + cellClass + '">';
				if (colType === "json_array") {
					html += '<span class="cell-value json-array" contenteditable="false"' + dataAttrs + ' title="Click to view/edit array">' + escHtml(truncate(displayVal, 60)) + "</span>";
				} else {
					const editable = colType !== "bool";
					html += '<span class="cell-value' + (editable ? "" : "") + '" contenteditable="' + (editable ? "true" : "false") + '"' + dataAttrs + ">" + escHtml(displayVal) + "</span>";
				}
				html += "</td>";
			});
			// Notes column
			html += '<td class="col-notes-cell"><button class="notes-btn" data-row-key="' + escHtml(row.row_key) + '">';
			html += "📝";
			html += "</button></td>";
			html += "</tr>";
		});
		html += "</tbody></table>";

		elTableContainer.innerHTML = html;

		// Bind cell editing
		bindCellEvents(data);

		// Bind notes buttons
		bindNotesButtons(data);
	}

	function bindCellEvents(data) {
		elTableContainer.querySelectorAll(".cell-value").forEach(function (span) {
			// Handle double-click on json-array cells
			if (span.classList.contains("json-array")) {
				span.addEventListener("click", function () {
					openSubTable(span.dataset.rowKey, span.dataset.column);
				});
				return;
			}

			// Boolean cells: toggle on click
			if (span.classList.contains("bool")) {
				span.addEventListener("click", function () {
					const current = span.classList.contains("true");
					setCellValue(data.id, span.dataset.rowKey, span.dataset.column, !current, span);
				});
				return;
			}

			// Editable cells
			const rowKey = span.dataset.rowKey;
			const column = span.dataset.column;

			span.addEventListener("focus", function () {
				span.classList.add("editing");
			});

			span.addEventListener("blur", function () {
				span.classList.remove("editing");
				const newVal = span.textContent;
				const original = getOriginalValue(rowKey, column);
				const originalStr = original !== undefined && original !== null ? String(original) : "";
				if (newVal !== originalStr) {
					setCellValue(data.id, rowKey, column, newVal, span);
				}
			});

			span.addEventListener("keydown", function (e) {
				if (e.key === "Escape") {
					span.textContent = getOriginalValue(rowKey, column) || "";
					span.blur();
				} else if (e.key === "Tab") {
					e.preventDefault();
					span.blur();
					// Focus next editable cell
					const allCells = Array.from(elTableContainer.querySelectorAll(".cell-value:not(.bool):not(.json-array)"));
					const idx = allCells.indexOf(span);
					if (idx >= 0 && idx < allCells.length - 1) {
						allCells[idx + 1].focus();
					}
				} else if (e.key === "Enter" && !e.shiftKey) {
					e.preventDefault();
					span.blur();
				}
			});
		});
	}

	function getOriginalValue(rowKey, column) {
		if (!activeTableData) return undefined;
		for (let i = 0; i < activeTableData.rows.length; i++) {
			const row = activeTableData.rows[i];
			if (row.row_key === rowKey) {
				return row.cells[column];
			}
		}
		return undefined;
	}

	function setCellValue(tableId, rowKey, column, value, spanEl) {
		// Update local state optimistically
		if (activeTableData) {
			for (let i = 0; i < activeTableData.rows.length; i++) {
				if (activeTableData.rows[i].row_key === rowKey) {
					activeTableData.rows[i].cells[column] = value;
					break;
				}
			}
		}

		// Mark dirty
		const cellKey = rowKey + ":" + column;
		dirtyCells.add(cellKey);
		if (spanEl) spanEl.classList.add("dirty");
		updateDirtyCounter();

		// Send to server (in-memory update)
		apiPut("/api/tables/" + encodeURIComponent(tableId) + "/cell", {
			row_key: rowKey,
			column: column,
			value: value,
		}).then(function () {
			// Success — keep dirty marker (not saved to disk yet)
		}).catch(function (e) {
			toast("Failed to update cell: " + e.message, "error");
			dirtyCells.delete(cellKey);
			if (spanEl) spanEl.classList.remove("dirty");
			updateDirtyCounter();
		});
	}

	function updateDirtyCounter() {
		if (!elDirtyCounter) return;
		if (dirtyCells.size > 0) {
			elDirtyCounter.classList.remove("hidden");
			elDirtyCounter.textContent = dirtyCells.size + " unsaved";
		} else {
			elDirtyCounter.classList.add("hidden");
		}
	}

	// --- Save ---
	async function saveAll() {
		if (!activeTableId) {
			toast("No table selected", "info");
			return;
		}
		try {
			const result = await apiPost("/api/tables/" + encodeURIComponent(activeTableId) + "/save");
			dirtyCells = new Set();
			updateDirtyCounter();
			// Remove dirty markers from DOM
			elTableContainer.querySelectorAll(".dirty").forEach(function (el) {
				el.classList.remove("dirty");
			});
			toast("Saved " + result.saved.length + " file(s)", "success");
		} catch (e) {
			toast("Save failed: " + e.message, "error");
		}
	}

	// --- Refresh ---
	async function refreshAll() {
		try {
			const result = await apiPost("/api/refresh");
			tables = await apiGet("/api/tables");
			renderSidebar(tables);
			activeTableData = null;
			dirtyCells = new Set();
			updateDirtyCounter();
			if (elTableContainer) elTableContainer.innerHTML = "";
			if (elTablePlaceholder) elTablePlaceholder.style.display = "";
			if (elTableTitle) elTableTitle.textContent = "Select a table";
			if (elTableMeta) elTableMeta.textContent = "";
			toast("Refreshed: " + result.table_count + " tables loaded", "success");
		} catch (e) {
			toast("Refresh failed: " + e.message, "error");
		}
	}

	// --- Notes ---
	function bindNotesButtons(data) {
		const notes = data.notes || {};
		elTableContainer.querySelectorAll(".notes-btn").forEach(function (btn) {
			const rowKey = btn.dataset.rowKey;
			// Check if any note exists for this row
			let hasAny = false;
			Object.keys(notes).forEach(function (k) {
				if (k.startsWith(rowKey + "/")) hasAny = true;
			});
			if (hasAny) btn.classList.add("has-note");

			btn.addEventListener("click", function (e) {
				e.stopPropagation();
				openNotesPanel(data.id, rowKey);
			});
		});
	}

	function openNotesPanel(tableId, rowKey) {
		if (!elNotesPanel || !elNotesTextarea || !elNotesCellPath) return;
		elNotesPanel.classList.remove("collapsed");
		activeNoteCell = { table_id: tableId, row_key: rowKey, column: null };
		elNotesCellPath.textContent = tableId + " / " + rowKey;
		elNotesTextarea.value = "";
		elNotesTextarea.placeholder = "Select a cell in the table to add a note, or write a row-level note here.";
		elNotesTextarea.focus();
	}

	function openCellNote(tableId, rowKey, column) {
		if (!elNotesPanel || !elNotesTextarea || !elNotesCellPath) return;
		elNotesPanel.classList.remove("collapsed");
		activeNoteCell = { table_id: tableId, row_key: rowKey, column: column };
		elNotesCellPath.textContent = tableId + " / " + rowKey + " / " + column;

		// Load existing note
		apiGet("/api/notes/" + encodeURIComponent(tableId)).then(function (notes) {
			const noteKey = rowKey + "/" + column;
			elNotesTextarea.value = notes[noteKey] || "";
		}).catch(function () {
			elNotesTextarea.value = "";
		});
	}

	function saveNote() {
		if (!activeNoteCell || !activeNoteCell.table_id || !elNotesTextarea) return;
		const noteText = elNotesTextarea.value;
		const col = activeNoteCell.column || "_row";

		apiPut(
			"/api/notes/" + encodeURIComponent(activeNoteCell.table_id) + "/" +
			encodeURIComponent(activeNoteCell.row_key) + "/" + encodeURIComponent(col),
			{ note_text: noteText }
		).then(function () {
			toast("Note saved", "success");
			// If currently viewing this table, reload to show note indicators
			if (activeTableId === activeNoteCell.table_id) {
				loadTable(activeTableId);
			}
		}).catch(function (e) {
			toast("Failed to save note: " + e.message, "error");
		});
	}

	function deleteNote() {
		if (!activeNoteCell || !activeNoteCell.table_id || !elNotesTextarea) return;
		const col = activeNoteCell.column || "_row";

		apiDelete(
			"/api/notes/" + encodeURIComponent(activeNoteCell.table_id) + "/" +
			encodeURIComponent(activeNoteCell.row_key) + "/" + encodeURIComponent(col)
		).then(function () {
			elNotesTextarea.value = "";
			toast("Note deleted", "info");
			if (activeTableId === activeNoteCell.table_id) {
				loadTable(activeTableId);
			}
		}).catch(function (e) {
			toast("Failed to delete note: " + e.message, "error");
		});
	}

	function closeNotesPanel() {
		if (!elNotesPanel) return;
		elNotesPanel.classList.add("collapsed");
		activeNoteCell = null;
		if (elNotesTextarea) elNotesTextarea.value = "";
	}

	// --- Sub-table ---
	function openSubTable(rowKey, column) {
		if (!activeTableId || !elSubtableOverlay || !elSubtableTitle || !elSubtableContainer) return;
		elSubtableTitle.textContent = column + " — " + rowKey;
		elSubtableContainer.innerHTML = "<p style='padding:20px;color:var(--text-muted)'>Loading...</p>";
		elSubtableOverlay.classList.remove("hidden");

		apiGet("/api/subtable/" + encodeURIComponent(activeTableId) + "/" + encodeURIComponent(rowKey) + "/" + encodeURIComponent(column))
			.then(function (data) {
				if (!data.columns || data.columns.length === 0) {
					elSubtableContainer.innerHTML = "<p style='padding:20px;color:var(--text-muted)'>Empty array or unable to parse.</p>";
					return;
				}
				let html = '<table class="data-table"><thead><tr><th>#</th>';
				data.columns.forEach(function (c) {
					html += "<th>" + escHtml(c) + "</th>";
				});
				html += "</tr></thead><tbody>";
				data.rows.forEach(function (row) {
					html += "<tr>";
					html += '<td class="row-label">' + escHtml(row.row_label) + "</td>";
					data.columns.forEach(function (c) {
						const v = row.cells[c] !== undefined ? row.cells[c] : "";
						html += '<td><span class="cell-value" contenteditable="false">' + escHtml(String(v)) + "</span></td>";
					});
					html += "</tr>";
				});
				html += "</tbody></table>";
				elSubtableContainer.innerHTML = html;
			})
			.catch(function (e) {
				elSubtableContainer.innerHTML = "<p style='padding:20px;color:var(--danger)'>Failed to load: " + e.message + "</p>";
			});
	}

	function closeSubTable() {
		if (!elSubtableOverlay) return;
		elSubtableOverlay.classList.add("hidden");
	}

	// --- Utilities ---
	function escHtml(str) {
		if (typeof str !== "string") str = String(str);
		return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
	}

	function truncate(str, len) {
		if (typeof str !== "string") return str;
		return str.length > len ? str.substring(0, len) + "…" : str;
	}

	// --- Global click handler for cell notes ---
	document.addEventListener("click", function (e) {
		// Right-click on a cell-value opens it in the notes panel
		const cell = e.target.closest(".cell-value");
		if (cell && cell.dataset.rowKey && cell.dataset.column) {
			// Ctrl+click or middle-click opens notes for that cell
			if (e.ctrlKey || e.metaKey || e.button === 1) {
				e.preventDefault();
				openCellNote(activeTableId, cell.dataset.rowKey, cell.dataset.column);
			}
		}
	});

	// --- Event bindings ---
	document.addEventListener("DOMContentLoaded", function () {
		init();

		// Refresh button
		const btnRefresh = $("#btn-refresh");
		if (btnRefresh) btnRefresh.addEventListener("click", refreshAll);

		// Save All button
		const btnSaveAll = $("#btn-save-all");
		if (btnSaveAll) btnSaveAll.addEventListener("click", saveAll);

		// Notes panel
		const btnNotesClose = $("#btn-notes-close");
		if (btnNotesClose) btnNotesClose.addEventListener("click", closeNotesPanel);

		const btnNoteSave = $("#btn-note-save");
		if (btnNoteSave) btnNoteSave.addEventListener("click", saveNote);

		const btnNoteDelete = $("#btn-note-delete");
		if (btnNoteDelete) btnNoteDelete.addEventListener("click", deleteNote);

		// Sub-table overlay
		const btnSubClose = $("#btn-subtable-close");
		if (btnSubClose) btnSubClose.addEventListener("click", closeSubTable);

		elSubtableOverlay && elSubtableOverlay.addEventListener("click", function (e) {
			if (e.target === elSubtableOverlay) closeSubTable();
		});

		// Table search/filter
		if (elTableSearch) {
			elTableSearch.addEventListener("input", function () {
				const q = this.value.toLowerCase();
				elTableNav.querySelectorAll(".table-nav-item").forEach(function (btn) {
					const text = (btn.textContent || "").toLowerCase();
					btn.style.display = text.includes(q) ? "" : "none";
				});
				elTableNav.querySelectorAll(".table-nav-group").forEach(function (grp) {
					const nextItems = grp.nextElementSibling;
					let visible = false;
					let sib = grp.nextElementSibling;
					while (sib && sib.classList.contains("table-nav-item")) {
						if (sib.style.display !== "none") visible = true;
						sib = sib.nextElementSibling;
					}
					grp.style.display = visible ? "" : "none";
				});
			});
		}

		// Keyboard shortcuts
		document.addEventListener("keydown", function (e) {
			if (e.ctrlKey && e.key === "s") {
				e.preventDefault();
				saveAll();
			}
		});

		// Add click handler on table container for cell→notes interaction
		const elTableCont = $("#table-container");
		if (elTableCont) {
			elTableCont.addEventListener("dblclick", function (e) {
				const cell = e.target.closest(".cell-value");
				if (cell && cell.dataset.rowKey && cell.dataset.column && !cell.classList.contains("json-array") && !cell.classList.contains("bool")) {
					// Allow normal editing on double-click
				}
			});
			elTableCont.addEventListener("contextmenu", function (e) {
				const cell = e.target.closest(".cell-value");
				if (cell && cell.dataset.rowKey && cell.dataset.column) {
					e.preventDefault();
					openCellNote(activeTableId, cell.dataset.rowKey, cell.dataset.column);
				}
			});
		}
	});
})();
