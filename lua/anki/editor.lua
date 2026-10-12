---
--- anki.editor
---
--- Provides functions for creating, displaying, and managing Anki notes and their buffers/windows in Neovim.
--- Each note opens in its own tab, allowing multiple notes to be edited simultaneously.
--- State is tracked per-tabpage in anki_state.current_notes, keyed by tabpage ID.
---
local anki_state = require("anki.state")
local EditorContext = require("anki.classes.editor_context")
local Field = require("anki.classes.field")
local Note = require("anki.classes.note")
local notification = require("anki.notification")
local sticky = require("anki.sticky")
local config = require("anki.config")

local M = {}

--- Returns the note for the current tabpage, or nil if none.
---@return Note|nil
local function get_current_note()
	local tabid = vim.api.nvim_get_current_tabpage()
	return anki_state.current_notes[tabid]
end

--- Finds which note (if any) owns the given buffer number, searching all open note editors.
---@param bufnr number The buffer number to search for.
---@return Note|nil The note that contains this buffer, or nil.
function M.find_note_by_bufnr(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][editor] find_note_by_bufnr: bufnr must be a number")
	end
	for _, note in pairs(anki_state.current_notes) do
		if note.tags.bufnr == bufnr then
			return note
		end
		for _, field in ipairs(note.fields) do
			if field.editor_context.bufnr == bufnr then
				return note
			end
		end
	end
	return nil
end

--- Searches for a note buffer by buffer number across all open note editors.
---@param bufnr number The buffer number to search for.
---@return number|nil 1 if found, nil otherwise.
function M.search_for_note(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][editor] search_for_note: bufnr must be a number")
	end
	local note = M.find_note_by_bufnr(bufnr)
	if note then
		return 1
	end
	return nil
end

--- Checks if a note with the given noteId is already open in an editor tab.
--- If found, switches to that tab and returns true.
---@param note_id any The note ID to check.
---@return boolean True if the note is already open (and tab was switched to).
function M.focus_note_by_id(note_id)
	if not note_id then
		return false
	end
	for tabid, note in pairs(anki_state.current_notes) do
		if note.id == note_id then
			if vim.api.nvim_tabpage_is_valid(tabid) then
				vim.api.nvim_set_current_tabpage(tabid)
				return true
			else
				anki_state.current_notes[tabid] = nil
			end
		end
	end
	return false
end

--- Creates a new note object with the given deck, model, and fields.
---@param deck_name string The name of the deck.
---@param model_name string The name of the model.
---@param field_names table List of field names.
---@param id any Optional note ID.
---@return Note The created note object.
function M.create_note(deck_name, model_name, field_names, id)
	if type(deck_name) ~= "string" then
		error("[anki.nvim][editor] create_note: deck_name must be a string")
	end
	if type(model_name) ~= "string" then
		error("[anki.nvim][editor] create_note: model_name must be a string")
	end
	if type(field_names) ~= "table" then
		error("[anki.nvim][editor] create_note: field_names must be a table")
	end
	local fields = {}

	for _, name in ipairs(field_names) do
		table.insert(
			fields,
			Field:new({
				editor_context = EditorContext:new({
					winid = 0,
					tabid = 0,
					bufnr = vim.api.nvim_create_buf(true, true),
				}),
				name = name,
			})
		)
	end

	local note = Note:new({
		fields = fields,
		tags = EditorContext:new({
			winid = 0,
			tabid = 0,
			bufnr = vim.api.nvim_create_buf(true, true),
		}),
		deck_name = deck_name,
		model_name = model_name,
		id = id,
	})

	return note
end

--- Displays the given note in a new editor tab, setting up splits and keymaps.
---@param note Note The note object to display.
function M.display_note(note)
	if type(note) ~= "table" then
		error("[anki.nvim][editor] display_note: note must be a table")
	end
	anki_state.counter = anki_state.counter + 1

	vim.cmd("tabnew")
	local tabid = vim.api.nvim_get_current_tabpage()

	anki_state.current_notes[tabid] = note
	note.tabid = tabid

	local counter = anki_state.counter
	vim.api.nvim_buf_set_name(note.tags.bufnr, "anki://" .. tabid .. "/Tags_" .. counter)

	local tags_bufnr = note.tags.bufnr
	local tags_mappings = {
		close = string.format("<Cmd>lua require('anki.editor').kill_note(%d)<CR>", tags_bufnr),
		send_note = string.format("<Cmd>lua require('anki.api').send_note(%d)<CR>", tags_bufnr),
		new_note = string.format("<Cmd>lua require('anki.api').send_note(%d, false, true)<CR>", tags_bufnr),
		pull_note = string.format("<Cmd>lua require('anki.api').pull_note(%d)<CR>", tags_bufnr),
		delete_note = string.format("<Cmd>lua require('anki.api').delete_note(%d)<CR>", tags_bufnr),
		edit_in_anki = "<Cmd>lua require('anki.ui.note_ops').edit_in_anki()<CR>",
		push_note_to_add_dialog = string.format(
			"<Cmd>lua require('anki.api').push_note_to_add_dialog(%d)<CR>",
			tags_bufnr
		),
		show_help = string.format("<Cmd>lua require('anki.ui.help').show_help('editor')<CR>"),
		gui_note = "<Cmd>lua require('anki.ui.note_ops').gui_note()<CR>",
	}

	for action, key in pairs(config.options.mappings.editor) do
		if tags_mappings[action] then
			vim.api.nvim_buf_set_keymap(tags_bufnr, "n", key, tags_mappings[action], { noremap = true, silent = true })
		end
	end
	local tags_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(tags_win, tags_bufnr)
	note.tags.winid = tags_win
	note.tags.tabid = tabid

	for i = #note.fields, 1, -1 do
		vim.cmd("split")
		local new_win = vim.api.nvim_get_current_win()
		local field_bufnr = note.fields[i].editor_context.bufnr
		vim.api.nvim_set_option_value("filetype", "html", { buf = field_bufnr })
		vim.api.nvim_buf_set_name(field_bufnr, "anki://" .. tabid .. "/" .. note.fields[i].name .. "_" .. counter)
		vim.api.nvim_win_set_buf(new_win, field_bufnr)

		note.fields[i].editor_context.winid = new_win
		note.fields[i].editor_context.tabid = tabid

		local field_mappings = {
			close = string.format("<Cmd>lua require('anki.editor').kill_note(%d)<CR>", field_bufnr),
			send_note = string.format("<Cmd>lua require('anki.api').send_note(%d)<CR>", field_bufnr),
			new_note = string.format("<Cmd>lua require('anki.api').send_note(%d, false, true)<CR>", field_bufnr),
			pull_note = string.format("<Cmd>lua require('anki.api').pull_note(%d)<CR>", field_bufnr),
			delete_note = string.format("<Cmd>lua require('anki.api').delete_note(%d)<CR>", field_bufnr),
			edit_in_anki = "<Cmd>lua require('anki.ui.note_ops').edit_in_anki()<CR>",
			push_note_to_add_dialog = string.format(
				"<Cmd>lua require('anki.api').push_note_to_add_dialog(%d)<CR>",
				field_bufnr
			),
			show_help = string.format("<Cmd>lua require('anki.ui.help').show_help('editor')<CR>"),
			gui_note = "<Cmd>lua require('anki.ui.note_ops').gui_note()<CR>",
			attach_media = string.format("<Cmd>lua require('anki.media').attach_media(%d)<CR>", field_bufnr),
			toggle_sticky = string.format("<Cmd>lua require('anki.editor').toggle_sticky(%d)<CR>", field_bufnr),
		}

		for action, key in pairs(config.options.mappings.editor) do
			if field_mappings[action] then
				vim.api.nvim_buf_set_keymap(
					field_bufnr,
					"n",
					key,
					field_mappings[action],
					{ noremap = true, silent = true }
				)
			end
		end
	end
end

--- Toggles the sticky flag for the field rendered in the given buffer.
--- Sticky fields keep their content when the editor is reset for the next note
--- (see anki.api send_note with new_note_after_send).
---@param bufnr number The buffer number of a field buffer.
function M.toggle_sticky(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][editor] toggle_sticky: bufnr must be a number")
	end
	local note = M.find_note_by_bufnr(bufnr)
	if not note then
		notification.warn("[anki.nvim][editor] No Anki note buffer found")
		return
	end
	for _, field in ipairs(note.fields) do
		if field.editor_context.bufnr == bufnr then
			local new_state = sticky.toggle(note.model_name, field.name)
			notification.info(
				string.format("[anki.nvim][editor] Field '%s' sticky: %s", field.name, new_state and "on" or "off")
			)
			return
		end
	end
end

--- Deletes all buffers associated with a note and closes its tab.
---@param note Note The note object whose buffers and tab should be closed.
function M.delete_note_buffers(note)
	if type(note) ~= "table" then
		error("[anki.nvim][editor] delete_note_buffers: note must be a table")
	end

	local tabid = note.tabid

	vim.api.nvim_buf_delete(note.tags.bufnr, { force = true })
	for _, field in ipairs(note.fields) do
		vim.api.nvim_buf_delete(field.editor_context.bufnr, { force = true })
	end

	if tabid and vim.api.nvim_tabpage_is_valid(tabid) then
		local tab_number = vim.api.nvim_tabpage_get_number(tabid)
		vim.cmd("tabclose " .. tab_number)
	end

	anki_state.current_notes[tabid] = nil
end

--- Kills (closes) the note editor tab associated with the given buffer number.
---@param bufnr number The buffer number to kill.
function M.kill_note(bufnr)
	local note = M.find_note_by_bufnr(bufnr)
	if not note then
		notification.warn("No Anki note buffer found")
		return
	end

	M.delete_note_buffers(note)
	notification.info("Note editor closed")
end

--- Kills (closes) all active note editor tabs and cleans up state.
function M.kill_all()
	local tabids = {}
	for tabid, note in pairs(anki_state.current_notes) do
		vim.api.nvim_buf_delete(note.tags.bufnr, { force = true })
		for _, field in ipairs(note.fields) do
			vim.api.nvim_buf_delete(field.editor_context.bufnr, { force = true })
		end
		if vim.api.nvim_tabpage_is_valid(tabid) then
			table.insert(tabids, tabid)
		end
	end

	table.sort(tabids, function(a, b)
		return vim.api.nvim_tabpage_get_number(a) > vim.api.nvim_tabpage_get_number(b)
	end)

	for _, tabid in ipairs(tabids) do
		if vim.api.nvim_tabpage_is_valid(tabid) then
			local tab_number = vim.api.nvim_tabpage_get_number(tabid)
			vim.cmd("tabclose " .. tab_number)
		end
	end

	anki_state.current_notes = {}
	notification.info("All note editors closed")
end

return M
