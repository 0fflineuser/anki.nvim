local utils = require("anki.utils")
local ankiconnect = require("anki.ankiconnect")
local anki_state = require("anki.state")
local editor = require("anki.editor")
local operations = require("anki.ui.operations")
local notification = require("anki.notification")

local M = {}

local HEADER_LINES = operations.HEADER_LINES

--- Resolves the entry (note or card) at the current cursor line, accounting
--- for the header offset. In notes mode returns a notesInfo row; in cards
--- mode returns a cardsInfo row.
---@return table|nil
local function entry_at_cursor()
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local idx = line_num - HEADER_LINES
	if idx < 1 then
		return nil
	end
	if anki_state.ui.view_mode == "cards" then
		return anki_state.ui.cards[idx]
	end
	return anki_state.ui.notes[idx]
end

--- Collects entries across a visual range, accounting for the header offset.
---@return table entries list of notesInfo or cardsInfo rows
local function entries_in_range()
	local start_line, end_line = utils.get_visual_line_range()
	local start_idx = start_line - HEADER_LINES
	local end_idx = end_line - HEADER_LINES
	if start_idx > end_idx then
		start_idx, end_idx = end_idx, start_idx
	end
	local entries = {}
	local source = anki_state.ui.view_mode == "cards" and anki_state.ui.cards or anki_state.ui.notes
	for i = start_idx, end_idx do
		if source[i] then
			table.insert(entries, source[i])
		end
	end
	return entries
end

--- Adds a new note to the specified deck, prompting for model and opening in a new editor tab.
---@param deck_name string|nil The name of the deck to add the note to. If nil, looks up the deck at the cursor (header-aware); warns and aborts if no deck is under the cursor.
function M.add_note(deck_name)
	if not deck_name then
		local line_num = vim.api.nvim_win_get_cursor(0)[1]
		local idx = line_num - HEADER_LINES
		if idx >= 1 then
			deck_name = anki_state.ui.decks[idx]
		end
	end
	if not deck_name then
		notification.warn(
			"[anki.nvim][note_ops] add_note: no deck under the cursor; place the cursor on a deck line first."
		)
		return
	end

	utils.async_safe_call(ankiconnect.model_names, nil, function(model_names, error)
		if error or not model_names then
			return
		end

		local prompt = string.format("Add note to '%s' — select a model", deck_name)
		vim.ui.select(model_names, { prompt = prompt }, function(model_name)
			if not model_name then
				return
			end
			utils.async_safe_call(ankiconnect.model_field_names, { model_name }, function(field_names, err2)
				if err2 or not field_names then
					return
				end
				local note = editor.create_note(deck_name, model_name, field_names)
				editor.display_note(note)
				operations.refresh_all()
			end)
		end)
	end)
end

--- Edits the note at the current cursor line, opening it in a new editor tab.
--- If the note is already open in another tab, switches to that tab instead.
--- In cards mode, resolves the card's parent note and edits that.
function M.edit_note()
	local entry = entry_at_cursor()
	if not entry then
		return
	end

	local note = entry
	if anki_state.ui.view_mode == "cards" then
		-- cardsInfo rows include a noteId; fetch the note info to edit.
		if not entry.noteId then
			notification.warn("[anki.nvim][note_ops] Card has no noteId; cannot edit.")
			return
		end
		utils.async_safe_call(ankiconnect.notes_info, { { entry.noteId } }, function(notes_info, err)
			if err or not notes_info or not notes_info[1] then
				notification.error("[anki.nvim][note_ops] Could not fetch note info for card.")
				return
			end
			vim.schedule(function()
				note = notes_info[1]
				if editor.focus_note_by_id(note.noteId) then
					return
				end
				M.open_note_in_editor(note)
				operations.refresh_all()
			end)
		end)
		return
	end

	if editor.focus_note_by_id(note.noteId) then
		return
	end

	M.open_note_in_editor(note)
	operations.refresh_all()
end

--- Opens a note in a new editor tab with its content populated from Anki data.
---@param note table The note info object from AnkiConnect (with fields, tags, etc.).
function M.open_note_in_editor(note)
	local sorted_fields = {}
	for key, field in pairs(note.fields) do
		sorted_fields[field.order + 1] = {
			value = field.value,
			name = key,
		}
	end

	local fields_names = {}
	for i = 1, #sorted_fields do
		if sorted_fields[i] then
			table.insert(fields_names, sorted_fields[i].name)
		end
	end

	local deck_win_id = vim.fn.bufwinid(anki_state.ui.deck_buf_id)
	local deck_name
	if deck_win_id ~= -1 then
		local cursor_line = vim.api.nvim_win_get_cursor(deck_win_id)[1]
		deck_name = vim.api.nvim_buf_get_lines(anki_state.ui.deck_buf_id, cursor_line - 1, cursor_line, true)[1]
	else
		deck_name = note.deckName or note.modelName
	end

	local new_note = editor.create_note(deck_name, note.modelName, fields_names, note.noteId)

	vim.api.nvim_buf_set_lines(new_note.tags.bufnr, 0, -1, false, note.tags)

	for i, field_data in ipairs(sorted_fields) do
		if field_data then
			vim.api.nvim_buf_set_lines(
				new_note.fields[i].editor_context.bufnr,
				0,
				-1,
				false,
				utils.split(field_data.value, "\n")
			)
		end
	end

	editor.display_note(new_note)
end

--- Deletes the note at the current cursor line after user confirmation.
--- In cards mode, deletes the parent note of the selected card(s).
function M.delete_note()
	local entries = entries_in_range()

	if #entries == 0 then
		notification.warn("[anki.nvim][note_ops] No notes selected.")
		return
	end

	-- In cards mode, resolve unique parent note ids.
	local note_ids = {}
	if anki_state.ui.view_mode == "cards" then
		local seen = {}
		for _, card in ipairs(entries) do
			if card.noteId and not seen[card.noteId] then
				seen[card.noteId] = true
				table.insert(note_ids, card.noteId)
			end
		end
	else
		for _, info in ipairs(entries) do
			if info.noteId then
				table.insert(note_ids, info.noteId)
			end
		end
	end

	if #note_ids == 0 then
		notification.warn("[anki.nvim][note_ops] No note id found for selected entries.")
		return
	end

	vim.ui.input(
		{ prompt = "Are you sure you want to delete " .. tostring(#note_ids) .. " note? (Y/n)" },
		function(input)
			if input == nil then
				return
			end
			if input == "Y" or input == "y" then
				utils.async_safe_call(ankiconnect.delete_notes, { note_ids }, function(result, error)
					if error or result == nil then
						notification.error("[anki.nvim][note_ops] Failed to delete note.")
						return
					end
					notification.info("[anki.nvim][note_ops] Deleted " .. tostring(#note_ids) .. " note.")
					vim.schedule(function()
						operations.refresh_all()
					end)
				end)
			end
		end
	)
end

---
--- Move selected note(s) to another deck (supports normal and visual mode)
---
--- Moves the selected note(s) cards to another deck, supporting both normal
--- and visual mode selection. In cards mode, operates on the selected cards
--- directly; in notes mode, resolves the note's cards first.
function M.move_note_to_deck()
	local entries = entries_in_range()
	if #entries == 0 then
		notification.warn("[anki.nvim][note_ops] No entries selected.")
		return
	end

	utils.async_safe_call(ankiconnect.deck_names, nil, function(deck_names, error)
		if error or not deck_names or #deck_names == 0 then
			notification.error("[anki.nvim][note_ops] Could not fetch deck names.")
			return
		end

		vim.ui.select(deck_names, { prompt = "Move to which deck?" }, function(target_deck)
			if not target_deck then
				return
			end

			local function do_change_deck(card_ids)
				if #card_ids == 0 then
					notification.warn("[anki.nvim][note_ops] No cards found to move.")
					return
				end
				utils.async_safe_call(ankiconnect.change_deck, { card_ids, target_deck }, function(result, err3)
					if err3 or result == nil then
						notification.error("[anki.nvim][note_ops] Failed to move cards to deck " .. target_deck)
						return
					end
					notification.info(
						"[anki.nvim][note_ops] Moved "
							.. tostring(#card_ids)
							.. " card(s) to deck '"
							.. target_deck
							.. "'."
					)
					vim.schedule(function()
						operations.refresh_notes()
					end)
				end)
			end

			if anki_state.ui.view_mode == "cards" then
				local card_ids = {}
				for _, card in ipairs(entries) do
					if card.cardId then
						table.insert(card_ids, card.cardId)
					end
				end
				do_change_deck(card_ids)
			else
				local note_ids = {}
				for _, note in ipairs(entries) do
					table.insert(note_ids, note.noteId)
				end
				utils.async_safe_call(ankiconnect.notes_info, { note_ids }, function(notes_info, err2)
					if err2 or not notes_info then
						notification.error("[anki.nvim][note_ops] Could not fetch note info.")
						return
					end
					local card_ids = {}
					for _, info in ipairs(notes_info) do
						if info.cards then
							for _, cid in ipairs(info.cards) do
								table.insert(card_ids, cid)
							end
						end
					end
					do_change_deck(card_ids)
				end)
			end
		end)
	end)
end

--- Opens the GUI browser for the entry at the current cursor line in Anki.
--- In notes mode uses nid:<noteId>; in cards mode uses cid:<cardId>.
function M.gui_note()
	local entry = entry_at_cursor()
	if not entry then
		return
	end
	local query
	if anki_state.ui.view_mode == "cards" then
		query = string.format("cid:%s", entry.cardId)
	else
		query = string.format("nid:%s", entry.noteId)
	end
	utils.async_safe_call(ankiconnect.gui_browse, { query }, function(_, _) end)
end

return M
