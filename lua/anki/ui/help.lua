local config = require("anki.config")
local anki_state = require("anki.state")
local sticky = require("anki.sticky")

local M = {}

--- Renders a one-line hint string summarizing the keymaps for the given context.
--- Used as the first line of the deck/notes buffers.
---@param context string "decks", "notes", "editor", "templates", or "media_browser"
---@return string hint line
function M.render_hint_line(context)
	local m
	if context == "decks" then
		m = config.options.mappings.deck
		return string.format(
			"Hint: %s add note | %s close | %s create deck | %s delete | %s gui | %s help | %s model | %s profile | %s refresh | %s rename | %s review | %s select | %s templates",
			m.add_note,
			m.close,
			m.create_deck,
			m.delete_deck,
			m.gui_deck,
			m.show_help,
			m.create_model,
			m.switch_profile,
			m.refresh_decks,
			m.rename_deck,
			m.review_deck,
			m.select_deck,
			m.edit_templates
		)
	elseif context == "notes" then
		m = config.options.mappings.note
		return string.format(
			"Hint: %s all | %s cards/notes | %s close | %s delete | %s edit | %s gui | %s help | %s import | %s move | %s refresh | %s reveal | %s search | %s undo",
			m.show_all_notes,
			m.toggle_view_mode,
			m.close,
			m.delete_note,
			m.edit_note,
			m.gui_note,
			m.show_help,
			m.sync_selection_from_anki_browser,
			m.move_note_to_deck,
			m.refresh_notes,
			m.select_note_in_anki_browser,
			m.search,
			m.undo
		)
	end
	return ""
end

--- Builds one sticky checkbox line for the help buffer.
---@param field_name string The field name.
---@param is_sticky boolean The sticky state of the field.
---@return string The rendered checkbox line, e.g. "[x] Front".
local function sticky_checkbox_line(field_name, is_sticky)
	return "[" .. (is_sticky and "x" or " ") .. "] " .. field_name
end

--- Builds the sticky-fields section lines for the editor help context.
---@param note Note The note open in the current editor tab.
---@return string[] lines The checkbox section lines (blank line, header, one per field).
local function build_sticky_section(note)
	local lines = { "" }
	table.insert(
		lines,
		"Sticky fields (press <C-Space> on a field to toggle; sticky fields keep their content for the next note)"
	)
	for _, field in ipairs(note.fields) do
		table.insert(lines, sticky_checkbox_line(field.name, sticky.is_sticky(note.model_name, field.name)))
	end
	return lines
end

--- Closes the help window if it is open.
function M.close_help()
	-- Iterate through all buffers to find the help buffer
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local bufname = vim.api.nvim_buf_get_name(bufnr)
			if bufname:find("Anki Help") then
				-- Delete the buffer directly; window closes automatically
				vim.api.nvim_buf_delete(bufnr, { force = true })
				return
			end
		end
	end
end

--- Shows the help window for the given context (decks, notes, or editor).
--- For the "editor" context, when a note is open in the current tab, a sticky-fields
--- section is appended: one `[x]`/`[ ]` checkbox line per field, read live from
--- anki.sticky. Pressing <C-Space> with the cursor on a checkbox line toggles that
--- field's sticky flag and flips the box in place.
---@param context string|nil "decks", "notes", "editor", "templates", or "media_browser"; defaults to "decks".
function M.show_help(context)
	context = context or "decks"
	local note_anchored = nil

	-- Check if cursor is already on the help window
	local current_bufnr = vim.api.nvim_win_get_buf(0)
	local current_bufname = vim.api.nvim_buf_get_name(current_bufnr)
	if current_bufname:find("Anki Help") then
		M.close_help()
		return
	end

	-- Close existing help window if open
	M.close_help()

	local help_lines = {}

	if context == "decks" then
		local m = config.options.mappings.deck
		help_lines = {
			"Anki.nvim Help - Decks",
			"",
			m.show_help .. " - Show this help window",
			m.close .. " - Close the Anki UI tab",
			m.select_deck .. " - Select a deck and show its notes",
			m.delete_deck .. " - Delete Deck",
			m.create_deck .. " - Create Deck",
			m.add_note .. " - Add Note (creates on the deck under the cursor)",
			m.rename_deck .. " - Rename Deck",
			m.gui_deck .. " - Open in the Anki GUI",
			m.review_deck .. " - Start review for this deck in the Anki GUI",
			m.refresh_decks .. " - Refresh Decks",
			m.switch_profile .. " - Switch Profile",
			m.edit_templates .. " - Edit card templates",
			m.create_model .. " - Create new model/note type",
		}
	elseif context == "notes" then
		local m = config.options.mappings.note
		help_lines = {
			"Anki.nvim Help - Notes",
			"",
			"A note is the content you write; a card is a reviewable instance.",
			"One note can produce multiple cards (e.g. Front/Back, reversed).",
			"",
			m.show_help .. " - Show this help window",
			m.close .. " - Close the Anki UI tab",
			m.edit_note .. " - Edit note",
			m.show_all_notes .. " - Show all notes",
			m.delete_note .. " - Delete note",
			m.gui_note .. " - Open in the Anki GUI",
			m.refresh_notes .. " - Refresh Notes",
			m.search .. " - Search notes by query",
			m.toggle_view_mode .. " - Toggle between notes and cards view",
			m.move_note_to_deck .. " - Move note's cards to another deck",
			m.undo .. " - Undo the last Anki action",
			m.select_note_in_anki_browser .. " - Reveal this note's first card in the open Anki browser",
			m.sync_selection_from_anki_browser
				.. " - Import the current selection from the open Anki browser as the notes filter",
		}
	elseif context == "editor" then
		local m = config.options.mappings.editor
		help_lines = {
			"Anki.nvim Help - Editor",
			"",
			m.show_help .. " - Show this help window",
			m.close .. " - Close the note editor",
			m.send_note .. " - Write/Send note to Anki",
			m.pull_note .. " - Pull note from Anki",
			m.delete_note .. " - Remove/Delete note from Anki",
			m.attach_media .. " - Attach media (image/audio/video) [field buffers only]",
			m.new_note .. " - Send note, then reset editor for a new note (sticky fields kept)",
			m.toggle_sticky .. " - Toggle sticky field (kept when adding next note) [field buffers only]",
			m.edit_in_anki .. " - Open this note in the Anki GUI edit dialog",
			m.push_note_to_add_dialog .. " - Push the editor content as a draft into the Anki Add dialog",
			m.gui_note .. " - Reveal this note in the Anki Browser (Ctrl+Shift+P there previews the card)",
		}
		-- Append the per-field sticky checkbox section when a note is open in this tab.
		local note = anki_state.current_notes[vim.api.nvim_get_current_tabpage()]
		if note then
			help_lines = vim.list_extend(help_lines, build_sticky_section(note))
			note_anchored = note
		end
	elseif context == "media_browser" then
		help_lines = {
			"Anki.nvim Help - Media Browser",
			"",
			"g? - Show this help window",
			"<Enter> - Insert selected media reference",
			"<leader>k / <Esc> - Close the media browser",
			"j/k - Navigate the file list",
		}
	elseif context == "templates" then
		local m = config.options.mappings.template
		help_lines = {
			"Anki.nvim Help - Templates",
			"",
			m.show_help .. " - Show this help window",
			m.save_template .. " - Save template changes to Anki",
			m.pull_template .. " - Pull latest template from Anki",
			m.switch_card .. " - Switch card (for multi-card models)",
			m.close_template .. " - Close the template editor",
		}
	end

	local help_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(help_bufnr, "Anki Help")
	vim.api.nvim_buf_set_lines(help_bufnr, 0, -1, false, help_lines)
	local width = 0
	for _, line in ipairs(help_lines) do
		width = math.max(width, vim.api.nvim_strwidth(line))
	end
	width = math.max(math.min(width, vim.o.columns - 2), 1)
	local height = #help_lines + 2
	vim.api.nvim_open_win(help_bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		col = (vim.o.columns - width) / 2,
		row = (vim.o.lines - height) / 2,
		anchor = "NW",
		style = "minimal",
		border = "single",
		title = "Anki Help",
	})
	-- Close via the context's close mapping and the universal `q`.
	local close_keys = {
		decks = config.options.mappings.deck.close,
		notes = config.options.mappings.note.close,
		editor = config.options.mappings.editor.close,
		templates = config.options.mappings.template.close_template,
		media_browser = "<leader>k",
	}
	local close_rhs = "<Cmd>lua require('anki.ui.help').close_help()<CR>"
	for _, key in ipairs({ close_keys[context] or "<leader>k", "q" }) do
		vim.api.nvim_buf_set_keymap(help_bufnr, "n", key, close_rhs, { noremap = true, silent = true })
	end

	if note_anchored then
		local fields = {}
		for _, field in ipairs(note_anchored.fields) do
			table.insert(fields, field.name)
		end
		vim.api.nvim_buf_set_var(help_bufnr, "anki_sticky_model", note_anchored.model_name)
		vim.api.nvim_buf_set_var(help_bufnr, "anki_sticky_fields", fields)
		vim.api.nvim_buf_set_var(help_bufnr, "anki_sticky_first_line", #help_lines - #fields + 1)
		vim.api.nvim_buf_set_keymap(
			help_bufnr,
			"n",
			"<C-Space>",
			string.format("<Cmd>lua require('anki.ui.help')._toggle_sticky_field(%d)<CR>", help_bufnr),
			{ noremap = true, silent = true }
		)
	end
end

--- Toggles the sticky flag of the field whose checkbox line is under the cursor
--- in the editor help window, rewriting the box in place. Silently does nothing
--- when the buffer vars are missing or the cursor is not on a checkbox line.
---@param help_bufnr number The help buffer number.
function M._toggle_sticky_field(help_bufnr)
	if type(help_bufnr) ~= "number" then
		error("[anki.nvim][help] _toggle_sticky_field: bufnr must be a number")
	end
	if not vim.api.nvim_buf_is_valid(help_bufnr) then
		return
	end
	local ok, model = pcall(vim.api.nvim_buf_get_var, help_bufnr, "anki_sticky_model")
	if not ok or type(model) ~= "string" then
		return
	end
	local ok_fields, fields = pcall(vim.api.nvim_buf_get_var, help_bufnr, "anki_sticky_fields")
	if not ok_fields or type(fields) ~= "table" or #fields == 0 then
		return
	end
	local ok_first, first_line = pcall(vim.api.nvim_buf_get_var, help_bufnr, "anki_sticky_first_line")
	if not ok_first or type(first_line) ~= "number" then
		return
	end

	local line = vim.api.nvim_win_get_cursor(0)[1]
	if line < first_line or line > first_line + #fields - 1 then
		return
	end
	local field = fields[line - first_line + 1]
	local new_state = sticky.toggle(model, field)
	vim.api.nvim_buf_set_lines(help_bufnr, line - 1, line, false, { sticky_checkbox_line(field, new_state) })
end

return M
