local anki_state = require("anki.state")
local config = require("anki.config")
local utils = require("anki.utils")
local ankiconnect = require("anki.ankiconnect")
local help = require("anki.ui.help")

local M = {}

-- Number of leading lines (hint + mode header + blank) above the first
-- content row in the deck and notes buffers. Note lookups must subtract
-- this offset from the cursor line.
local HEADER_LINES = 3
M.HEADER_LINES = HEADER_LINES

-- Buffer-local namespace used to highlight the hint line (line 1) of the
-- deck and notes buffers via extmarks: italic "Hint:" prefix + red keybinds.
local hint_ns = vim.api.nvim_create_namespace("anki_hint")

vim.api.nvim_set_hl(0, "AnkiHintLabel", { default = true, italic = true })
vim.api.nvim_set_hl(0, "AnkiHintKey", { default = true, fg = "Red" })

--- Parses a rendered hint line and returns byte-offset ranges for each
--- keybind token. The format is: "Hint: KEY1 label1 | KEY2 label2 | ..."
--- @param line string The rendered hint line.
--- @return table list of { start_col, end_col } (0-indexed, end_col exclusive)
local function find_key_ranges(line)
	local prefix = "Hint: "
	local prefix_len = #prefix
	if line:sub(1, prefix_len) ~= prefix then
		return {}
	end

	local ranges = {}
	local col = prefix_len + 1 -- 1-indexed for Lua string ops

	while col <= #line do
		-- Find end of key (first space at or after col)
		local space_pos = line:find(" ", col)
		local key_end = space_pos or (#line + 1)

		-- Convert to 0-indexed extmark columns (end_col is exclusive)
		table.insert(ranges, {
			start_col = col - 1,
			end_col = key_end - 1,
		})

		-- Find next "|" separator
		local pipe = line:find("|", key_end)
		if not pipe then
			break
		end

		-- Skip spaces after "|" to reach next key
		col = pipe + 1
		while col <= #line and line:sub(col, col) == " " do
			col = col + 1
		end
	end

	return ranges
end

--- Formats a note for display in the buffer.
-- @param note table The note object.
-- @return string The formatted note string.
local function format_note_display(note)
	return config.options.note_formatter(note)
end

--- Formats a card for display in the buffer.
-- @param card table The card object from cardsInfo.
-- @return string The formatted card string.
local function format_card_display(card)
	return config.options.card_formatter(card)
end

--- Builds the header lines (hint, mode header, blank) to prepend to content.
--- @param context string "decks" or "notes"
--- @return table list of header lines (length HEADER_LINES)
local function build_header(context)
	local hint = help.render_hint_line(context)
	local mode_line
	if context == "notes" then
		local filter = anki_state.ui.current_filter or "deck:*"
		local label = anki_state.ui.view_mode == "cards" and "Cards" or "Notes"
		mode_line = string.format("== %s | %s ==", label, filter)
	else
		mode_line = "== Decks =="
	end
	return { hint, mode_line, "" }
end

--- Writes lines into a buffer, preserving a header block at the top.
--- @param bufnr integer
--- @param context string "decks" or "notes"
--- @param content_lines table list of strings to display below the header
local function render_with_header(bufnr, context, content_lines)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local header = build_header(context)
	local all = {}
	for _, l in ipairs(header) do
		table.insert(all, l)
	end
	for _, l in ipairs(content_lines or {}) do
		table.insert(all, l)
	end
	-- Preserve cursor line if it was within the header region.
	local winid = vim.fn.bufwinid(bufnr)
	local cursor = nil
	if winid ~= -1 then
		cursor = vim.api.nvim_win_get_cursor(winid)
	end
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, all)
	-- Highlight the hint line (line 1): italic "Hint:" prefix + red keybinds.
	-- Styling refreshes on each render; namespace is cleared to avoid stale marks.
	vim.api.nvim_buf_clear_namespace(bufnr, hint_ns, 0, -1)
	local hint_line = all[1]
	if hint_line and #hint_line > 0 then
		local prefix_len = #"Hint:"
		if hint_line:sub(1, prefix_len) == "Hint:" then
			vim.api.nvim_buf_set_extmark(bufnr, hint_ns, 0, 0, {
				end_col = prefix_len,
				hl_group = "AnkiHintLabel",
				priority = 100,
			})
		end

		for _, range in ipairs(find_key_ranges(hint_line)) do
			vim.api.nvim_buf_set_extmark(bufnr, hint_ns, 0, range.start_col, {
				end_col = range.end_col,
				hl_group = "AnkiHintKey",
				priority = 100,
			})
		end
	end
	if winid ~= -1 and vim.api.nvim_win_is_valid(winid) and cursor then
		-- Keep cursor at least on the first content line.
		local row = math.max(cursor[1], HEADER_LINES + 1)
		pcall(vim.api.nvim_win_set_cursor, winid, { row, 0 })
	end
end

--- Displays a list of notes in the note buffer, updating state.
-- @param notes_info table List of note info tables.
-- @param filter_name string|nil The filter (deck) name.
local function display_notes_in_buffer(notes_info, filter_name)
	anki_state.ui.current_filter = filter_name
	anki_state.ui.notes = notes_info or {}

	local note_lines = {}
	for _, note in ipairs(notes_info or {}) do
		table.insert(note_lines, format_note_display(note))
	end
	render_with_header(anki_state.ui.note_buf_id, "notes", note_lines)
end

--- Displays a list of cards in the note buffer, updating state.
-- @param cards_info table List of card info tables.
-- @param filter_name string|nil The filter (deck) name.
local function display_cards_in_buffer(cards_info, filter_name)
	anki_state.ui.current_filter = filter_name
	anki_state.ui.cards = cards_info or {}

	local card_lines = {}
	for _, card in ipairs(cards_info or {}) do
		table.insert(card_lines, format_card_display(card))
	end
	render_with_header(anki_state.ui.note_buf_id, "notes", card_lines)
end

--- Retrieves note information for a given query string asynchronously.
-- @param query string The search query for notes.
-- @param on_result function Callback: on_result(notes_info)
local function get_notes_for_query(query, on_result)
	utils.async_safe_call(ankiconnect.find_notes, { query }, function(note_ids, error)
		if error or not note_ids then
			on_result(nil)
			return
		end
		utils.async_safe_call(ankiconnect.notes_info, { note_ids }, function(notes_info, err2)
			if err2 then
				on_result(nil)
				return
			end
			on_result(notes_info)
		end)
	end)
end

--- Retrieves card information for a given query string asynchronously.
-- @param query string The search query for cards.
-- @param on_result function Callback: on_result(cards_info)
local function get_cards_for_query(query, on_result)
	utils.async_safe_call(ankiconnect.find_cards, { query }, function(card_ids, error)
		if error or not card_ids then
			on_result(nil)
			return
		end
		if #card_ids == 0 then
			on_result({})
			return
		end
		utils.async_safe_call(ankiconnect.cards_info, { card_ids }, function(cards_info, err2)
			if err2 then
				on_result(nil)
				return
			end
			on_result(cards_info)
		end)
	end)
end

--- Updates the deck buffer with the latest deck names from Anki asynchronously.
-- @param on_done function|nil Optional callback called after update completes.
local function update_decks_view(on_done)
	utils.async_safe_call(ankiconnect.deck_names, nil, function(deck_names, error)
		if error or not deck_names then
			if on_done then
				on_done()
			end
			return
		end
		anki_state.ui.decks = deck_names
		vim.schedule(function()
			if anki_state.ui.deck_buf_id and vim.api.nvim_buf_is_valid(anki_state.ui.deck_buf_id) then
				render_with_header(anki_state.ui.deck_buf_id, "decks", deck_names)
			end
			if on_done then
				on_done()
			end
		end)
	end)
end

--- Refreshes the note buffer based on the current deck filter asynchronously.
-- @param on_done function|nil Optional callback called after refresh completes.
local function update_notes_view(on_done)
	local current_filter = anki_state.ui.current_filter
	local query = current_filter or "deck:*"
	if anki_state.ui.view_mode == "cards" then
		get_cards_for_query(query, function(cards_info)
			vim.schedule(function()
				display_cards_in_buffer(cards_info, query)
				if on_done then
					on_done()
				end
			end)
		end)
	else
		get_notes_for_query(query, function(notes_info)
			vim.schedule(function()
				display_notes_in_buffer(notes_info, query)
				if on_done then
					on_done()
				end
			end)
		end)
	end
end

--- Refreshes both the deck and note buffers asynchronously.
function M.refresh_all()
	update_decks_view(function()
		update_notes_view()
	end)
end

--- Refreshes the deck buffer asynchronously.
function M.refresh_decks()
	update_decks_view()
end

--- Refreshes the note buffer asynchronously.
function M.refresh_notes()
	update_notes_view()
end

--- Shows all notes, ignoring any deck filter, asynchronously.
function M.show_all_notes()
	anki_state.ui.view_mode = "notes"
	anki_state.ui.current_filter = "deck:*"
	get_notes_for_query("deck:*", function(notes_info)
		vim.schedule(function()
			display_notes_in_buffer(notes_info, "deck:*")
		end)
	end)
end

--- Prompts for a search query and updates the notes view to match it.
function M.search_notes()
	local default = anki_state.ui.current_filter or ""
	vim.ui.input({ prompt = "Search query:", default = default }, function(query)
		if not query or query == "" then
			return
		end
		anki_state.ui.current_filter = query
		update_notes_view()
	end)
end

--- Toggles between notes view and cards view for the current filter.
function M.toggle_view_mode()
	if anki_state.ui.view_mode == "cards" then
		anki_state.ui.view_mode = "notes"
	else
		anki_state.ui.view_mode = "cards"
	end
	update_notes_view()
end

--- Updates the note buffer based on the currently selected deck asynchronously.
function M.select_deck()
	local line_num = vim.api.nvim_win_get_cursor(0)[1]
	local idx = line_num - HEADER_LINES
	if idx < 1 then
		return
	end
	local deck_name = anki_state.ui.decks[idx]
	if deck_name then
		local query = string.format('"deck:%s"', utils.escape_search_query(deck_name))
		anki_state.ui.current_filter = query
		update_notes_view()
	end
end

--- Opens the Anki UI, creating windows and initializing state.
function M.open()
	local windows = require("anki.ui.windows")

	if windows.focus_existing_window() then
		return
	end

	windows.check_anki_permissions(ankiconnect, function(granted)
		if not granted then
			return
		end

		vim.schedule(function()
			local deck_win_id = windows.create_layout()
			windows.setup_deck_keymaps(anki_state.ui.deck_buf_id)
			windows.setup_note_keymaps(anki_state.ui.note_buf_id)

			anki_state.ui.current_filter = "deck:*"
			anki_state.ui.view_mode = "notes"
			update_decks_view(function()
				update_notes_view()
			end)

			anki_state.ui.win_id = deck_win_id
		end)
	end)
end

--- Closes the Anki UI window and cleans up buffers.
function M.close()
	local close_tabid = nil
	if anki_state.ui.win_id and vim.api.nvim_win_is_valid(anki_state.ui.win_id) then
		close_tabid = vim.api.nvim_win_get_tabpage(anki_state.ui.win_id)
	end

	if anki_state.ui.deck_buf_id and vim.api.nvim_buf_is_valid(anki_state.ui.deck_buf_id) then
		vim.api.nvim_buf_delete(anki_state.ui.deck_buf_id, { force = true })
	end
	if anki_state.ui.note_buf_id and vim.api.nvim_buf_is_valid(anki_state.ui.note_buf_id) then
		vim.api.nvim_buf_delete(anki_state.ui.note_buf_id, { force = true })
	end
	anki_state.ui.win_id = nil
	anki_state.ui.deck_buf_id = nil
	anki_state.ui.note_buf_id = nil

	if close_tabid and vim.api.nvim_tabpage_is_valid(close_tabid) then
		-- Guard against closing the last tab (E784).
		if #vim.api.nvim_list_tabpages() <= 1 then
			-- Switch to an empty buffer first if the closed tab is the only one.
			vim.cmd("enew")
		else
			local tab_number = vim.api.nvim_tabpage_get_number(close_tabid)
			vim.cmd("tabclose " .. tab_number)
		end
	end
end

return M
