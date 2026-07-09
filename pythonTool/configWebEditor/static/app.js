/**
 * Config Web Editor — Frontend SPA
 * Multi-level headers, column-level notes, inline editing, save.
 */
(function () {
	"use strict";

	// --- State ---
	let tables = [];
	let activeTableId = null;
	let activeTableData = null;
	let dirtyCells = new Set();
	let activeNoteCell = null; // { table_id, column, config_key }

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
	const elBtnAddRow = $("#btn-add-row");
	const elAddrowOverlay = $("#addrow-overlay");
	const elAddrowKey = $("#addrow-key");
	const elAddrowFields = $("#addrow-fields");

	// --- Toast ---
	function toast(msg, type) {
		type = type || "info";
		const el = document.createElement("div");
		el.className = "toast " + type;
		el.textContent = msg;
		let container = document.getElementById("toast-container");
		if (!container) {
			container = document.createElement("div");
			container.id = "toast-container";
			document.body.appendChild(container);
		}
		container.appendChild(el);
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
			method: "PUT", headers: { "Content-Type": "application/json" },
			body: JSON.stringify(body),
		});
		if (!r.ok) throw new Error(r.status + " " + r.statusText);
		return r.json();
	}

	async function apiPost(url, body) {
		const opts = { method: "POST", headers: { "Content-Type": "application/json" } };
		if (body !== undefined) opts.body = JSON.stringify(body);
		const r = await fetch(url, opts);
		if (!r.ok) throw new Error(r.status + " " + r.statusText);
		return r.json();
	}

	async function apiDelete(url, body) {
		const opts = { method: "DELETE" };
		if (body !== undefined) {
			opts.headers = { "Content-Type": "application/json" };
			opts.body = JSON.stringify(body);
		}
		const r = await fetch(url, opts);
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
		const groups = {};
		tableList.forEach(function (t) {
			const parts = t.id.split("/");
			const group = parts.length > 1 ? parts[0] : "(root)";
			if (!groups[group]) groups[group] = [];
			groups[group].push(t);
		});

		let html = "";
		Object.keys(groups).sort().forEach(function (g) {
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

	// --- Multi-level header rendering ---
	function renderTable(data) {
		if (!elTableTitle || !elTableContainer || !elTableMeta) return;
		elTablePlaceholder.style.display = "none";

		elTableTitle.textContent = data.display_name || data.id;
		if (elBtnAddRow) {
			elBtnAddRow.classList.toggle("hidden", data.mode === "single-object");
		}
		elTableMeta.textContent = data.mode + " · " + data.rows.length + " rows · " + data.columns.length + " columns";

		const cols = data.columns;
		const rows = data.rows;
		const colTypes = data.column_types || {};
		const notes = data.notes || {};
		const tree = data.column_tree || [];

		// Build header rows from column_tree
		// Row 1: group headers (depth=1 nodes) + empty cells for flat columns
		// Row 2: leaf labels (depth=0 or depth=2 nodes) with note icon
		let headerRow1 = '<tr><th class="col-row-label group-header" rowspan="2">Row</th>';
		let headerRow2 = '<tr>';
		let leafColIndex = 0;

		for (let i = 0; i < tree.length; i++) {
			const node = tree[i];
			if (node.depth === 1) {
				// Group header — spans its children
				headerRow1 += '<th class="group-header" colspan="' + node.colspan + '">' + escHtml(node.label) + "</th>";
			} else if (node.depth === 0 || node.depth === 2) {
				// Leaf — needs a placeholder in row 1 if preceded by a group
				if (node.depth === 0) {
					// Flat column: rowspan=2 in headerRow1
					headerRow1 += '<th class="leaf-header" rowspan="2"><div>' + escHtml(node.label) + '</div><div class="header-note" data-column="' + escHtml(node.path) + '" title="Click to add note">' + renderNoteIndicator(notes, data.id, node.path) + "</div></th>";
				} else {
					// depth=2: label goes in row 2, row 1 was handled by group header
					headerRow2 += '<th class="leaf-header"><div>' + escHtml(node.label) + '</div><div class="header-note" data-column="' + escHtml(node.path) + '" title="Click to add note">' + renderNoteIndicator(notes, data.id, node.path) + "</div></th>";
				}
			}
		}
		headerRow1 += "</tr>";
		headerRow2 += "</tr>";

		let html = '<table class="data-table"><thead>' + headerRow1 + headerRow2 + "</thead><tbody>";

		// Build body rows
		rows.forEach(function (row) {
			html += "<tr>";
			html += '<td class="row-label">' + escHtml(row.row_label) + "</td>";
			cols.forEach(function (col) {
				const cellKey = row.row_key + ":" + col;
				const dirty = dirtyCells.has(cellKey);
				const colType = colTypes[col] || "str";
				const val = row.cells[col];

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
					html += '<span class="cell-value" contenteditable="' + (editable ? "true" : "false") + '"' + dataAttrs + ">" + escHtml(displayVal) + "</span>";
				}
				html += "</td>";
			});
			html += "</tr>";
		});
		html += "</tbody></table>";

		elTableContainer.innerHTML = html;

		// Bind cell editing
		bindCellEvents(data);
		// Bind header note clicks
		bindHeaderNotes(data);
	}

	function renderNoteIndicator(notes, tableId, columnPath) {
		const configKey = tableId + "/" + columnPath;
		const noteText = notes[configKey] && notes[configKey].trim();
		if (noteText) {
			const short = noteText.length > 30 ? noteText.substring(0, 28) + "…" : noteText;
			return '<span class="note-dot has-note" title="' + escHtml(noteText) + '">●</span><span class="note-text">' + escHtml(short) + '</span>';
		}
		return '<span class="note-dot" title="Click to add note">○</span>';
	}

	function bindHeaderNotes(data) {
		elTableContainer.querySelectorAll(".header-note").forEach(function (el) {
			el.addEventListener("click", function (e) {
				e.stopPropagation();
				const column = this.dataset.column;
				openColumnNote(data.id, column);
			});
		});
	}

	// --- Cell editing ---
	function bindCellEvents(data) {
		elTableContainer.querySelectorAll(".cell-value").forEach(function (span) {
			if (span.classList.contains("json-array")) {
				span.addEventListener("click", function () {
					openSubTable(span.dataset.rowKey, span.dataset.column);
				});
				return;
			}

			if (span.classList.contains("bool")) {
				span.addEventListener("click", function () {
					const current = span.classList.contains("true");
					setCellValue(data.id, span.dataset.rowKey, span.dataset.column, !current, span);
				});
				return;
			}

			const rowKey = span.dataset.rowKey;
			const column = span.dataset.column;

			span.addEventListener("focus", function () { span.classList.add("editing"); });

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
					e.preventDefault(); span.blur();
					const allCells = Array.from(elTableContainer.querySelectorAll(".cell-value:not(.bool):not(.json-array)"));
					const idx = allCells.indexOf(span);
					if (idx >= 0 && idx < allCells.length - 1) allCells[idx + 1].focus();
				} else if (e.key === "Enter" && !e.shiftKey) {
					e.preventDefault(); span.blur();
				}
			});
		});
	}

	function getOriginalValue(rowKey, column) {
		if (!activeTableData) return undefined;
		for (let i = 0; i < activeTableData.rows.length; i++) {
			if (activeTableData.rows[i].row_key === rowKey) return activeTableData.rows[i].cells[column];
		}
		return undefined;
	}

	function setCellValue(tableId, rowKey, column, value, spanEl) {
		if (activeTableData) {
			for (let i = 0; i < activeTableData.rows.length; i++) {
				if (activeTableData.rows[i].row_key === rowKey) {
					activeTableData.rows[i].cells[column] = value;
					break;
				}
			}
		}

		const cellKey = rowKey + ":" + column;
		dirtyCells.add(cellKey);
		if (spanEl) spanEl.classList.add("dirty");
		updateDirtyCounter();

		apiPut("/api/tables/" + encodeURIComponent(tableId) + "/cell", {
			row_key: rowKey, column: column, value: value,
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
		if (!activeTableId) { toast("No table selected", "info"); return; }
		try {
			const result = await apiPost("/api/tables/" + encodeURIComponent(activeTableId) + "/save");
			dirtyCells = new Set();
			updateDirtyCounter();
			elTableContainer.querySelectorAll(".dirty").forEach(function (el) { el.classList.remove("dirty"); });
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
			activeTableData = null; dirtyCells = new Set(); updateDirtyCounter();
			if (elTableContainer) elTableContainer.innerHTML = "";
			if (elTablePlaceholder) elTablePlaceholder.style.display = "";
			if (elTableTitle) elTableTitle.textContent = "Select a table";
			if (elTableMeta) elTableMeta.textContent = "";
			toast("Refreshed: " + result.table_count + " tables loaded", "success");
		} catch (e) {
			toast("Refresh failed: " + e.message, "error");
		}
	}

	// --- Column-level Notes ---
	function openColumnNote(tableId, column) {
		if (!elNotesPanel || !elNotesTextarea || !elNotesCellPath) return;
		const configKey = tableId + "/" + column;
		elNotesPanel.classList.remove("collapsed");
		activeNoteCell = { table_id: tableId, column: column, config_key: configKey };
		elNotesCellPath.textContent = configKey;

		const notes = activeTableData ? (activeTableData.notes || {}) : {};
		elNotesTextarea.value = notes[configKey] || "";
		elNotesTextarea.focus();
	}

	function saveNote() {
		if (!activeNoteCell || !elNotesTextarea) return;
		const configKey = activeNoteCell.config_key;
		if (!configKey) { toast("No column selected", "error"); return; }

		apiPut("/api/notes", { config_key: configKey, note_text: elNotesTextarea.value }
		).then(function () {
			toast("Note saved", "success");
			// Update notes in active table data and re-render header notes
			if (activeTableData) {
				if (!activeTableData.notes) activeTableData.notes = {};
				activeTableData.notes[configKey] = elNotesTextarea.value;
			}
			// Refresh note indicators in header
			refreshHeaderNotes(activeTableData);
		}).catch(function (e) {
			toast("Failed to save note: " + e.message, "error");
		});
	}

	function deleteNote() {
		if (!activeNoteCell || !elNotesTextarea) return;
		const configKey = activeNoteCell.config_key;
		if (!configKey) { toast("No column selected", "error"); return; }

		apiDelete("/api/notes", { config_key: configKey }
		).then(function () {
			elNotesTextarea.value = "";
			toast("Note deleted", "info");
			if (activeTableData && activeTableData.notes) {
				delete activeTableData.notes[configKey];
			}
			refreshHeaderNotes(activeTableData);
		}).catch(function (e) {
			toast("Failed to delete note: " + e.message, "error");
		});
	}

	function refreshHeaderNotes(data) {
		if (!data) return;
		const notes = data.notes || {};
		elTableContainer.querySelectorAll(".header-note").forEach(function (el) {
			const column = el.dataset.column;
			const configKey = data.id + "/" + column;
			const noteText = notes[configKey] && notes[configKey].trim();
			if (noteText) {
				const short = noteText.length > 30 ? noteText.substring(0, 28) + "…" : noteText;
				el.innerHTML = '<span class="note-dot has-note" title="' + escHtml(noteText) + '">●</span><span class="note-text">' + escHtml(short) + '</span>';
			} else {
				el.innerHTML = '<span class="note-dot" title="Click to add note">○</span>';
			}
		});
	}

	function closeNotesPanel() {
		if (!elNotesPanel) return;
		elNotesPanel.classList.add("collapsed");
		activeNoteCell = null;
		if (elNotesTextarea) elNotesTextarea.value = "";
	}

	// --- Add Row ---
	function openAddRowDialog() {
		if (!activeTableData || !elAddrowOverlay || !elAddrowFields || !elAddrowKey) return;
		const data = activeTableData;
		const colTypes = data.column_types || {};

		// Set key input label based on mode
		const keyLabel = data.mode === "key-as-row" ? "Key name:" : "Filename:";
		const keyPh = data.mode === "key-as-row" ? "e.g. NewBehavior" : "e.g. new_unit";
		elAddrowKey.value = "";
		elAddrowKey.placeholder = keyPh;

		// Build field inputs for each column
		let fieldsHtml = "";
		data.columns.forEach(function (col) {
			const ct = colTypes[col] || "str";
			let inputHtml;
			if (ct === "bool") {
				inputHtml = '<select><option value="false">false</option><option value="true">true</option></select>';
			} else if (ct === "json_array") {
				inputHtml = '<input type="text" value="[]">';
			} else if (ct === "int" || ct === "float") {
				inputHtml = '<input type="number" value="0" step="' + (ct === "float" ? "0.1" : "1") + '">';
			} else {
				inputHtml = '<input type="text" value="">';
			}
			fieldsHtml += '<div class="addrow-field"><label>' + escHtml(col) + '</label>' + inputHtml + '</div>';
		});
		elAddrowFields.innerHTML = fieldsHtml;
		elAddrowOverlay.classList.remove("hidden");
		elAddrowKey.focus();
	}

	function closeAddRowDialog() {
		if (!elAddrowOverlay) return;
		elAddrowOverlay.classList.add("hidden");
	}

	function submitAddRow() {
		if (!activeTableData || !elAddrowKey) return;
		const rowKey = elAddrowKey.value.trim();
		if (!rowKey) { toast("Please enter a key / filename", "error"); return; }

		// Collect cell values from form
		const cells = {};
		const fieldDivs = elAddrowFields.querySelectorAll(".addrow-field");
		const cols = activeTableData.columns;
		fieldDivs.forEach(function (div, idx) {
			const input = div.querySelector("input, select");
			if (input && idx < cols.length) {
				const col = cols[idx];
				const ct = (activeTableData.column_types || {})[col] || "str";
				let val = input.value;
				if (ct === "bool") val = val === "true";
				else if (ct === "int") val = parseInt(val, 10) || 0;
				else if (ct === "float") val = parseFloat(val) || 0.0;
				cells[col] = val;
			}
		});

		apiPost("/api/tables/" + encodeURIComponent(activeTableData.id) + "/add_row", {
			row_key: rowKey,
			cells: cells,
		}).then(function (result) {
			toast("Created: " + result.row_key, "success");
			closeAddRowDialog();
			loadTable(activeTableData.id);
		}).catch(function (e) {
			toast("Failed to create row: " + e.message, "error");
		});
	}

	// --- Sub-table ---
	function openSubTable(rowKey, column) {
		if (!activeTableId || !elSubtableOverlay || !elSubtableTitle || !elSubtableContainer) return;
		elSubtableTitle.textContent = column + " — " + rowKey;
		elSubtableContainer.innerHTML = "<p style='padding:20px;color:var(--text-muted)'>Loading...</p>";
		elSubtableOverlay.classList.remove("hidden");

		apiGet("/api/subtable?table_id=" + encodeURIComponent(activeTableId) + "&row_key=" + encodeURIComponent(rowKey) + "&column=" + encodeURIComponent(column))
			.then(function (data) {
				if (!data.columns || data.columns.length === 0) {
					elSubtableContainer.innerHTML = "<p style='padding:20px;color:var(--text-muted)'>Empty array or unable to parse.</p>";
					return;
				}
				let html = '<table class="data-table"><thead><tr><th>#</th>';
				data.columns.forEach(function (c) { html += "<th>" + escHtml(c) + "</th>"; });
				html += "</tr></thead><tbody>";
				data.rows.forEach(function (row) {
					html += "<tr><td class='row-label'>" + escHtml(row.row_label) + "</td>";
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

	// --- Event bindings ---
	document.addEventListener("DOMContentLoaded", function () {
		init();

		const btnRefresh = $("#btn-refresh");
		if (btnRefresh) btnRefresh.addEventListener("click", refreshAll);

		const btnSaveAll = $("#btn-save-all");
		if (btnSaveAll) btnSaveAll.addEventListener("click", saveAll);

		const btnNotesClose = $("#btn-notes-close");
		if (btnNotesClose) btnNotesClose.addEventListener("click", closeNotesPanel);

		const btnNoteSave = $("#btn-note-save");
		if (btnNoteSave) btnNoteSave.addEventListener("click", saveNote);

		const btnNoteDelete = $("#btn-note-delete");
		if (btnNoteDelete) btnNoteDelete.addEventListener("click", deleteNote);

		const btnSubClose = $("#btn-subtable-close");
		if (btnSubClose) btnSubClose.addEventListener("click", closeSubTable);

		elSubtableOverlay && elSubtableOverlay.addEventListener("click", function (e) {
			if (e.target === elSubtableOverlay) closeSubTable();
		});

	// Add row modal
	if (elBtnAddRow) elBtnAddRow.addEventListener("click", openAddRowDialog);
	$("#btn-addrow-close") && $("#btn-addrow-close").addEventListener("click", closeAddRowDialog);
	$("#btn-addrow-cancel") && $("#btn-addrow-cancel").addEventListener("click", closeAddRowDialog);
	$("#btn-addrow-submit") && $("#btn-addrow-submit").addEventListener("click", submitAddRow);
	elAddrowOverlay && elAddrowOverlay.addEventListener("click", function (e) {
		if (e.target === elAddrowOverlay) closeAddRowDialog();
	});

	if (elTableSearch) {
			elTableSearch.addEventListener("input", function () {
				const q = this.value.toLowerCase();
				elTableNav.querySelectorAll(".table-nav-item").forEach(function (btn) {
					btn.style.display = (btn.textContent || "").toLowerCase().includes(q) ? "" : "none";
				});
				elTableNav.querySelectorAll(".table-nav-group").forEach(function (grp) {
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

		document.addEventListener("keydown", function (e) {
			if (e.ctrlKey && e.key === "s") { e.preventDefault(); saveAll(); }
		});
	});
})();
