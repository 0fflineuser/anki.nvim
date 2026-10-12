local note_ops = require("anki.ui.note_ops")
local anki_state = require("anki.state")
local config = require("anki.config")
local ankiconnect = require("anki.ankiconnect")
local editor = require("anki.editor")
local operations = require("anki.ui.operations")
local notification = require("anki.notification")
local utils = require("anki.utils")
local spy = require("luassert.spy")

-- Sentinel note object returned by the editor.create_note stub so we never
-- create real buffers/windows during tests.
local SENTINEL_NOTE = { __sentinel = true }

local function make_stubs(overrides)
	overrides = overrides or {}
	return {
		nvim_win_get_cursor = overrides.nvim_win_get_cursor or function()
			return { 1, 0 }
		end,
		model_names = overrides.model_names or function(on_result)
			on_result({ "Basic", "Cloze" }, nil)
		end,
		model_field_names = overrides.model_field_names or function(_, on_result)
			on_result({ "Front", "Back" }, nil)
		end,
		create_note = overrides.create_note or function(deck_name, model_name, field_names)
			return SENTINEL_NOTE
		end,
		display_note = overrides.display_note or function() end,
		refresh_all = overrides.refresh_all or function() end,
		vim_ui_select = overrides.vim_ui_select or function(opts, on_result)
			on_result("Basic")
		end,
	}
end

local function apply_stubs(stubs)
	stubs._saved = {
		nvim_win_get_cursor = vim.api.nvim_win_get_cursor,
		model_names = ankiconnect.model_names,
		model_field_names = ankiconnect.model_field_names,
		create_note = editor.create_note,
		display_note = editor.display_note,
		refresh_all = operations.refresh_all,
		vim_ui_select = vim.ui.select,
	}
	vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor
	ankiconnect.model_names = stubs.model_names
	ankiconnect.model_field_names = stubs.model_field_names
	editor.create_note = stubs.create_note
	editor.display_note = stubs.display_note
	operations.refresh_all = stubs.refresh_all
	vim.ui.select = stubs.vim_ui_select
end

local function restore_stubs(stubs)
	if not stubs or not stubs._saved then
		return
	end
	vim.api.nvim_win_get_cursor = stubs._saved.nvim_win_get_cursor
	ankiconnect.model_names = stubs._saved.model_names
	ankiconnect.model_field_names = stubs._saved.model_field_names
	editor.create_note = stubs._saved.create_note
	editor.display_note = stubs._saved.display_note
	operations.refresh_all = stubs._saved.refresh_all
	vim.ui.select = stubs._saved.vim_ui_select
end

local function drain_async()
	vim.wait(50, function()
		return false
	end)
end

describe("anki.ui.note_ops.add_note", function()
	local stubs
	local warn_spy
	local created
	local select_opts

	before_each(function()
		config.setup({})
		anki_state.ui.decks = { "FooDeck", "BarDeck" }
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.view_mode = "notes"
		created = {}
		select_opts = {}
		warn_spy = spy.on(notification, "warn")

		stubs = make_stubs({
			create_note = function(deck_name, model_name, field_names)
				table.insert(created, { deck_name = deck_name, model_name = model_name, field_names = field_names })
				return SENTINEL_NOTE
			end,
			vim_ui_select = function(items, opts, on_result)
				select_opts.opts = opts
				if opts._test_cancel then
					on_result(nil)
				else
					on_result(opts._test_model or "Basic")
				end
			end,
		})
		apply_stubs(stubs)
	end)

	after_each(function()
		restore_stubs(stubs)
		if warn_spy then
			warn_spy:revert()
			warn_spy = nil
		end
	end)

	describe("header lines (no deck under cursor)", function()
		it("warns and aborts on the hint line (line 1)", function()
			stubs.nvim_win_get_cursor = function()
				return { 1, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_called(1)
			assert.are.equal(0, #created)
		end)

		it("warns and aborts on the == Mode | filter == header line (line 2)", function()
			stubs.nvim_win_get_cursor = function()
				return { 2, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_called(1)
			assert.are.equal(0, #created)
		end)

		it("warns and aborts on the blank line below the header (line 3)", function()
			stubs.nvim_win_get_cursor = function()
				return { 3, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_called(1)
			assert.are.equal(0, #created)
		end)
	end)

	describe("deck lines", function()
		it("creates a note on the first deck (line 4) with a deck-bearing prompt", function()
			stubs.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_not_called()
			assert.are.equal(1, #created)
			assert.are.equal("FooDeck", created[1].deck_name)
			assert.are.equal("Basic", created[1].model_name)
			assert.is_truthy(select_opts.opts)
			assert.is_truthy(select_opts.opts.prompt:find("Add note to 'FooDeck'"))
		end)

		it("creates a note on the second deck (line 5)", function()
			stubs.nvim_win_get_cursor = function()
				return { 5, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_not_called()
			assert.are.equal(1, #created)
			assert.are.equal("BarDeck", created[1].deck_name)
		end)

		it("warns and aborts when cursor is past the end of the deck list", function()
			stubs.nvim_win_get_cursor = function()
				return { 100, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_called(1)
			assert.are.equal(0, #created)
		end)

		it("warns and aborts when decks list is empty", function()
			anki_state.ui.decks = {}
			stubs.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.spy(warn_spy).was_called(1)
			assert.are.equal(0, #created)
		end)
	end)

	describe("explicit deck_name argument", function()
		it("bypasses cursor lookup and uses the provided deck name", function()
			stubs.nvim_win_get_cursor = function()
				return { 1, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note("ExplicitDeck")
			drain_async()

			assert.spy(warn_spy).was_not_called()
			assert.are.equal(1, #created)
			assert.are.equal("ExplicitDeck", created[1].deck_name)
			assert.is_truthy(select_opts.opts.prompt:find("Add note to 'ExplicitDeck'"))
		end)
	end)

	describe("async error paths", function()
		it("does not create a note when model_names returns an error", function()
			stubs.model_names = function(on_result)
				on_result(nil, "network error")
			end
			ankiconnect.model_names = stubs.model_names
			stubs.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.are.equal(0, #created)
		end)

		it("does not create a note when model_names returns nil without error", function()
			stubs.model_names = function(on_result)
				on_result(nil, nil)
			end
			ankiconnect.model_names = stubs.model_names
			stubs.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.are.equal(0, #created)
		end)

		it("does not create a note when the user cancels model selection", function()
			stubs.vim_ui_select = function(items, opts, on_result)
				select_opts.opts = opts
				on_result(nil)
			end
			vim.ui.select = stubs.vim_ui_select
			stubs.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.are.equal(0, #created)
		end)

		it("does not create a note when model_field_names returns an error", function()
			stubs.model_field_names = function(_, on_result)
				on_result(nil, "boom")
			end
			ankiconnect.model_field_names = stubs.model_field_names
			stubs.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			vim.api.nvim_win_get_cursor = stubs.nvim_win_get_cursor

			note_ops.add_note()
			drain_async()

			assert.are.equal(0, #created)
		end)
	end)
end)

describe("anki.ui.note_ops undo/select/sync", function()
	local stubs
	local info_spy
	local error_spy
	local warn_spy
	local undo_calls
	local select_calls
	local selected_notes_result

	before_each(function()
		config.setup({})
		anki_state.ui.decks = { "FooDeck" }
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.view_mode = "notes"
		anki_state.ui.current_filter = nil
		undo_calls = {}
		select_calls = {}
		selected_notes_result = {}

		stubs = make_stubs({})
		apply_stubs(stubs)

		stubs._saved.gui_undo = ankiconnect.gui_undo
		stubs._saved.gui_select_card = ankiconnect.gui_select_card
		stubs._saved.gui_selected_notes = ankiconnect.gui_selected_notes
		stubs._saved.notes_info = ankiconnect.notes_info
		stubs._saved.refresh_notes = operations.refresh_notes

		ankiconnect.gui_undo = function(on_result)
			table.insert(undo_calls, true)
			on_result(true, nil)
		end
		ankiconnect.gui_select_card = function(card, on_result)
			table.insert(select_calls, card)
			on_result(true, nil)
		end
		ankiconnect.gui_selected_notes = function(on_result)
			on_result(selected_notes_result, nil)
		end
		operations.refresh_notes = function() end

		info_spy = spy.on(notification, "info")
		error_spy = spy.on(notification, "error")
		warn_spy = spy.on(notification, "warn")
	end)

	after_each(function()
		restore_stubs(stubs)
		ankiconnect.gui_undo = stubs._saved.gui_undo
		ankiconnect.gui_select_card = stubs._saved.gui_select_card
		ankiconnect.gui_selected_notes = stubs._saved.gui_selected_notes
		ankiconnect.notes_info = stubs._saved.notes_info
		operations.refresh_notes = stubs._saved.refresh_notes
		info_spy:revert()
		error_spy:revert()
		warn_spy:revert()
	end)

	describe("undo_anki_action", function()
		it("notifies info and refreshes when Anki reports something undone", function()
			local refresh_calls = {}
			operations.refresh_all = function()
				table.insert(refresh_calls, true)
			end

			note_ops.undo_anki_action()
			drain_async()

			assert.are.equal(1, #undo_calls)
			assert.spy(info_spy).was_called_with("[anki.nvim][note_ops] Undo accepted by Anki")
			assert.are.equal(1, #refresh_calls)
		end)

		it("does not notify or refresh when Anki reports nothing to undo", function()
			local refresh_calls = {}
			operations.refresh_all = function()
				table.insert(refresh_calls, true)
			end
			ankiconnect.gui_undo = function(on_result)
				on_result(false, nil)
			end

			note_ops.undo_anki_action()
			drain_async()

			assert.spy(info_spy).was_not_called()
			assert.are.equal(0, #refresh_calls)
		end)

		it("notifies error when the undo call fails", function()
			ankiconnect.gui_undo = function(on_result)
				on_result(nil, "offline")
			end

			note_ops.undo_anki_action()
			drain_async()

			assert.spy(error_spy).was_called_with("[anki.nvim][note_ops] Failed to undo last Anki action")
		end)
	end)

	describe("select_note_in_anki_browser", function()
		it("warns when the cursor is not on a note row", function()
			anki_state.ui.notes = {}
			vim.api.nvim_win_get_cursor = function()
				return { 1, 0 }
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert.are.equal(0, #select_calls)
			assert
				.spy(warn_spy)
				.was_called_with("[anki.nvim][note_ops] No note under cursor (place the cursor on a note row)")
		end)

		it("selects the card directly in cards mode", function()
			anki_state.ui.view_mode = "cards"
			anki_state.ui.cards = { { cardId = 77 } }
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert.are.equal(1, #select_calls)
			assert.are.equal(77, select_calls[1])
		end)

		it("resolves the note's first card in notes mode", function()
			anki_state.ui.view_mode = "notes"
			anki_state.ui.notes = { { noteId = 42, cards = { 900, 901 } } }
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			ankiconnect.notes_info = function(notes, on_result)
				on_result({ { cards = { 900, 901 } } }, nil)
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert.are.equal(1, #select_calls)
			assert.are.equal(900, select_calls[1])
		end)

		it("warns when the note has no cards", function()
			anki_state.ui.notes = { { noteId = 42, cards = {} } }
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			ankiconnect.notes_info = function(notes, on_result)
				on_result({ { cards = {} } }, nil)
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert.are.equal(0, #select_calls)
			assert.spy(warn_spy).was_called_with("[anki.nvim][note_ops] Note under cursor has no cards")
		end)

		it("notifies error when the select call fails", function()
			anki_state.ui.view_mode = "cards"
			anki_state.ui.cards = { { cardId = 77 } }
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			ankiconnect.gui_select_card = function(card, on_result)
				on_result(nil, "browser closed")
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert
				.spy(error_spy)
				.was_called_with(
					"[anki.nvim][note_ops] Failed to select the note's card in the Anki browser (is the Anki browser open?)"
				)
		end)

		it("warns when Anki reports the browser is not open in cards mode", function()
			anki_state.ui.view_mode = "cards"
			anki_state.ui.cards = { { cardId = 77 } }
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			ankiconnect.gui_select_card = function(card, on_result)
				table.insert(select_calls, card)
				on_result(false, nil)
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert.are.equal(1, #select_calls)
			assert
				.spy(warn_spy)
				.was_called_with("[anki.nvim][note_ops] Anki browser is not open — open it in Anki and try again")
		end)

		it("does not warn when the select call succeeds in notes mode", function()
			anki_state.ui.view_mode = "notes"
			anki_state.ui.notes = { { noteId = 42, cards = { 900, 901 } } }
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			ankiconnect.notes_info = function(notes, on_result)
				on_result({ { cards = { 900, 901 } } }, nil)
			end
			ankiconnect.gui_select_card = function(card, on_result)
				table.insert(select_calls, card)
				on_result(true, nil)
			end

			note_ops.select_note_in_anki_browser()
			drain_async()

			assert.are.equal(1, #select_calls)
			assert.spy(warn_spy).was_not_called()
		end)
	end)

	describe("sync_selection_from_anki_browser", function()
		it("builds an nid filter, forces notes mode and refreshes", function()
			selected_notes_result = { 111, 222 }
			local refresh_calls = {}
			operations.refresh_notes = function()
				table.insert(refresh_calls, true)
			end
			anki_state.ui.view_mode = "cards"

			note_ops.sync_selection_from_anki_browser()
			drain_async()

			assert.are.equal("nid:111 or nid:222", anki_state.ui.current_filter)
			assert.are.equal("notes", anki_state.ui.view_mode)
			assert.are.equal(1, #refresh_calls)
		end)

		it("notifies info and leaves the filter alone when nothing is selected", function()
			local saved_filter = anki_state.ui.current_filter
			selected_notes_result = {}

			note_ops.sync_selection_from_anki_browser()
			drain_async()

			assert.spy(info_spy).was_called_with("[anki.nvim][note_ops] Nothing selected in the Anki browser")
			assert.are.equal(saved_filter, anki_state.ui.current_filter)
		end)

		it("notifies error when the selection fetch fails", function()
			ankiconnect.gui_selected_notes = function(on_result)
				on_result(nil, "offline")
			end

			note_ops.sync_selection_from_anki_browser()
			drain_async()

			assert
				.spy(error_spy)
				.was_called_with("[anki.nvim][note_ops] Failed to get the selection from the Anki browser")
		end)
	end)
end)

describe("anki.ui.note_ops.gui_note from the editor tab", function()
	local stubs
	local browse_calls
	local info_spy
	local error_spy
	local warn_spy
	local browse_error

	--- Builds a real note (with real buffers) for the current tab.
	local function make_note(id)
		local note = editor.create_note("TestDeck", "TestModel", { "Front" })
		note.id = id
		local tabid = vim.api.nvim_get_current_tabpage()
		anki_state.current_notes[tabid] = note
		note.tabid = tabid
		return note
	end

	--- Deletes the note's buffers (make_note never opens windows or tabs).
	local function cleanup_buffers(note)
		if note.tags then
			pcall(vim.api.nvim_buf_delete, note.tags.bufnr, { force = true })
		end
		for _, field in ipairs(note.fields or {}) do
			pcall(vim.api.nvim_buf_delete, field.editor_context.bufnr, { force = true })
		end
	end

	before_each(function()
		config.setup({})
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				local name = vim.api.nvim_buf_get_name(bufnr)
				if name:find("anki://", 1, true) then
					pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
				end
			end
		end
		anki_state.current_notes = {}
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.view_mode = "notes"
		anki_state.ui.current_filter = nil

		browse_calls = {}
		browse_error = nil

		stubs = make_stubs({})
		apply_stubs(stubs)

		stubs._saved.gui_browse = ankiconnect.gui_browse
		ankiconnect.gui_browse = function(query, on_result)
			table.insert(browse_calls, query)
			if browse_error then
				on_result(nil, browse_error)
			else
				on_result({ 123 }, nil)
			end
		end

		info_spy = spy.on(notification, "info")
		error_spy = spy.on(notification, "error")
		warn_spy = spy.on(notification, "warn")
	end)

	after_each(function()
		restore_stubs(stubs)
		ankiconnect.gui_browse = stubs._saved.gui_browse
		info_spy:revert()
		error_spy:revert()
		warn_spy:revert()
		anki_state.current_notes = {}
	end)

	it("calls gui_browse with nid:<id> and notifies info with the preview hint", function()
		local note = make_note(123)

		note_ops.gui_note()
		drain_async()

		assert.are.equal(1, #browse_calls)
		assert.are.equal("nid:123", browse_calls[1])
		assert
			.spy(info_spy)
			.was_called_with("[anki.nvim][note_ops] Note revealed in the Anki Browser — press Ctrl+Shift+P there to preview")
		assert.spy(error_spy).was_not_called()
		cleanup_buffers(note)
	end)

	it("warns on an unsaved note and does not call gui_browse", function()
		local note = make_note(nil)

		note_ops.gui_note()
		drain_async()

		assert.are.equal(0, #browse_calls)
		assert
			.spy(warn_spy)
			.was_called_with("[anki.nvim][note_ops] Note is not saved to Anki yet — send it first (<leader>w)")
		cleanup_buffers(note)
	end)

	it("notifies error when the browser call fails", function()
		local note = make_note(123)
		browse_error = "offline"

		note_ops.gui_note()
		drain_async()

		assert.are.equal(1, #browse_calls)
		assert.spy(error_spy).was_called_with("[anki.nvim][note_ops] Failed to open the note in the Anki Browser")
		assert.spy(info_spy).was_not_called()
		cleanup_buffers(note)
	end)

	it("keeps the browser-pane nid path untouched when no note is being edited", function()
		local saved_cursor = vim.api.nvim_win_get_cursor
		anki_state.ui.notes = { { noteId = 42, cards = { 900 } } }
		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		note_ops.gui_note()
		drain_async()

		vim.api.nvim_win_get_cursor = saved_cursor
		assert.are.equal(1, #browse_calls)
		assert.are.equal("nid:42", browse_calls[1])
		assert.spy(info_spy).was_not_called()
		assert.spy(warn_spy).was_not_called()
	end)
end)

describe("anki.ui.note_ops.gui_note editor keymap wiring", function()
	before_each(function()
		config.setup({})
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				local name = vim.api.nvim_buf_get_name(bufnr)
				if name:find("anki://", 1, true) then
					pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
				end
			end
		end
		anki_state.current_notes = {}
	end)

	after_each(function()
		anki_state.current_notes = {}
	end)

	it("maps gui_note on the tags buffer and every field buffer", function()
		local note = editor.create_note("TestDeck", "TestModel", { "Front", "Back" })
		editor.display_note(note)

		for _, bufnr in ipairs({
			note.tags.bufnr,
			note.fields[1].editor_context.bufnr,
			note.fields[2].editor_context.bufnr,
		}) do
			local found = false
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
				if tostring(map.rhs or map.callback):find("gui_note", 1, true) then
					found = true
				end
			end
			assert.is_true(found)
		end

		editor.delete_note_buffers(note)
	end)
end)

describe("anki.ui.note_ops.gui_note editor help text", function()
	before_each(function()
		config.setup({})
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(bufnr) then
				local name = vim.api.nvim_buf_get_name(bufnr)
				if name:find("anki://", 1, true) or name:find("Anki Help", 1, true) then
					pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
				end
			end
		end
		anki_state.current_notes = {}
	end)

	after_each(function()
		anki_state.current_notes = {}
	end)

	it("lists the gui_note reveal hint in the editor help", function()
		local help = require("anki.ui.help")
		local note = editor.create_note("TestDeck", "TestModel", { "Front" })
		local tabid = vim.api.nvim_get_current_tabpage()
		anki_state.current_notes[tabid] = note
		note.tabid = tabid

		local help_bufnr = nil
		local saved_open_win = vim.api.nvim_open_win
		vim.api.nvim_open_win = function(buffer, enter, opts)
			help_bufnr = buffer
			return saved_open_win(buffer, enter, opts)
		end
		local ok, err = pcall(help.show_help, "editor")
		vim.api.nvim_open_win = saved_open_win
		if not ok then
			error(err)
		end

		local joined = table.concat(vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false), "\n")
		assert.truthy(
			joined:find("Reveal this note in the Anki Browser %(Ctrl%+Shift%+P there previews the card%)", 1, false)
		)
		vim.api.nvim_buf_delete(help_bufnr, { force = true })
	end)
end)

describe("anki.ui.note_ops.edit_note", function()
	local stubs
	local warn_spy
	local error_spy
	local notes_info_calls
	local notes_info_result
	local notes_info_error
	local focus_calls
	local focus_result
	local open_calls
	local refresh_calls

	before_each(function()
		config.setup({})
		anki_state.ui.decks = {}
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.view_mode = "notes"
		notes_info_calls = {}
		notes_info_result = nil
		notes_info_error = nil
		focus_calls = {}
		focus_result = false
		open_calls = {}
		refresh_calls = {}

		stubs = make_stubs({})
		apply_stubs(stubs)

		-- Save and stub the pieces edit_note uses directly.
		stubs._saved.notes_info = ankiconnect.notes_info
		stubs._saved.focus_note_by_id = editor.focus_note_by_id
		stubs._saved.open_note_in_editor = note_ops.open_note_in_editor

		ankiconnect.notes_info = function(note_ids, on_result)
			table.insert(notes_info_calls, note_ids)
			if notes_info_error then
				on_result(nil, notes_info_error)
			else
				on_result(notes_info_result, nil)
			end
		end
		editor.focus_note_by_id = function(note_id)
			table.insert(focus_calls, note_id)
			return focus_result
		end
		note_ops.open_note_in_editor = function(note)
			table.insert(open_calls, note)
		end
		operations.refresh_all = function()
			table.insert(refresh_calls, true)
		end

		warn_spy = spy.on(notification, "warn")
		error_spy = spy.on(notification, "error")
	end)

	after_each(function()
		ankiconnect.notes_info = stubs._saved.notes_info
		editor.focus_note_by_id = stubs._saved.focus_note_by_id
		note_ops.open_note_in_editor = stubs._saved.open_note_in_editor
		restore_stubs(stubs)
		warn_spy:revert()
		error_spy:revert()
		anki_state.current_notes = {}
	end)

	it("resolves the parent note via entry.note in cards mode (focus path)", function()
		anki_state.ui.cards = { { cardId = 77, note = 42 } }
		anki_state.ui.view_mode = "cards"
		notes_info_result = {
			{ noteId = 42, modelName = "Basic", tags = {}, fields = { Front = { value = "q", order = 0 } } },
		}
		focus_result = true

		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		note_ops.edit_note()
		drain_async()

		assert.are.same({ { 42 } }, notes_info_calls)
		assert.are.same({ 42 }, focus_calls)
		assert.are.equal(0, #open_calls)
		assert.are.equal(0, #refresh_calls)
		assert.spy(warn_spy).was_not_called()
	end)

	it("opens the parent note in the editor when not already open", function()
		anki_state.ui.cards = { { cardId = 77, note = 42 } }
		anki_state.ui.view_mode = "cards"
		notes_info_result = {
			{ noteId = 42, modelName = "Basic", tags = {}, fields = { Front = { value = "q", order = 0 } } },
		}
		focus_result = false

		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		note_ops.edit_note()
		drain_async()

		assert.are.equal(1, #open_calls)
		assert.are.equal(42, open_calls[1].noteId)
		assert.are.same({ true }, refresh_calls)
	end)

	it("warns when the card row has no note key", function()
		anki_state.ui.cards = { {} }
		anki_state.ui.view_mode = "cards"

		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		note_ops.edit_note()
		drain_async()

		assert.spy(warn_spy).was_called_with("[anki.nvim][note_ops] Card not found in Anki — refresh the browser (r)")
		assert.are.equal(0, #notes_info_calls)
		assert.are.equal(0, #open_calls)
	end)

	it("errors when notes_info returns an empty row", function()
		anki_state.ui.cards = { { cardId = 77, note = 42 } }
		anki_state.ui.view_mode = "cards"
		notes_info_result = {}

		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		note_ops.edit_note()
		drain_async()

		assert.spy(error_spy).was_called_with("[anki.nvim][note_ops] Could not fetch note info for card.")
		assert.are.equal(0, #open_calls)
	end)

	it("warns on a dead row in notes mode", function()
		anki_state.ui.notes = { {} }
		anki_state.ui.view_mode = "notes"

		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		note_ops.edit_note()
		drain_async()

		assert.are.equal(0, #notes_info_calls)
		assert.are.equal(0, #open_calls)
		assert.spy(warn_spy).was_called_with("[anki.nvim][note_ops] Note not found in Anki — refresh the browser (r)")
	end)
end)

describe("anki.ui.note_ops.delete_note", function()
	local stubs
	local saved_win_id
	local input_calls
	local input_answer
	local delete_calls
	local delete_error
	local refresh_calls

	before_each(function()
		config.setup({})
		anki_state.ui.decks = {}
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.view_mode = "cards"
		saved_win_id = anki_state.win_id
		anki_state.win_id = -1
		input_calls = {}
		input_answer = "y"
		delete_calls = {}
		delete_error = nil
		refresh_calls = {}

		stubs = make_stubs({ refresh_all = function() end })
		apply_stubs(stubs)
		operations.refresh_all = function()
			table.insert(refresh_calls, true)
		end

		stubs._saved.delete_notes = ankiconnect.delete_notes
		ankiconnect.delete_notes = function(note_ids, on_result)
			table.insert(delete_calls, note_ids)
			if delete_error then
				on_result(nil, delete_error)
			else
				on_result({}, nil)
			end
		end

		stubs._saved.vim_ui_input = vim.ui.input
		vim.ui.input = function(opts, on_result)
			table.insert(input_calls, opts.prompt)
			on_result(input_answer)
		end

		stubs._saved.get_visual_line_range = utils.get_visual_line_range
		utils.get_visual_line_range = function()
			return 4, 5
		end
	end)

	after_each(function()
		vim.ui.input = stubs._saved.vim_ui_input
		utils.get_visual_line_range = stubs._saved.get_visual_line_range
		ankiconnect.delete_notes = stubs._saved.delete_notes
		anki_state.win_id = saved_win_id
		restore_stubs(stubs)
	end)

	it("deletes the deduplicated parent notes of selected cards", function()
		anki_state.ui.cards = { { cardId = 77, note = 42 }, { cardId = 78, note = 52 } }
		anki_state.ui.view_mode = "cards"

		note_ops.delete_note()
		drain_async()

		assert.are.same({ { 42, 52 } }, delete_calls)
		assert.are.same({ true }, refresh_calls)
		assert.are.equal(1, #input_calls)
	end)

	it("dedups multiple cards of one note to the single parent note", function()
		anki_state.ui.cards = { { cardId = 77, note = 42 }, { cardId = 78, note = 42 } }
		anki_state.ui.view_mode = "cards"

		note_ops.delete_note()
		drain_async()

		assert.are.same({ { 42 } }, delete_calls)
		assert.are.same({ true }, refresh_calls)
	end)
end)

describe("anki.ui.windows note-pane p/y keymap wiring", function()
	local windows = require("anki.ui.windows")
	local saved_note_mappings
	local bufnr

	before_each(function()
		config.setup({})
		saved_note_mappings = vim.deepcopy(config.options.mappings.note)
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == "" and vim.bo[b].buftype == "" then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "placeholder" })
		windows.setup_note_keymaps(bufnr)
	end)

	after_each(function()
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
		config.setup({})
	end)

	local function mapped_lhs(buf, mode)
		local set = {}
		for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
			set[map.lhs] = true
		end
		return set
	end

	-- Finds the lhs a given action (matched by rhs substring) is mapped to.
	-- nvim_buf_set_keymap expands <leader> in the lhs at set time, so custom
	-- "<leader>P" style mappings are stored as e.g. "\P".
	local function lhs_for(buf, mode, rhs_needle)
		for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
			if map.rhs and map.rhs:find(rhs_needle, 1, true) then
				return map.lhs
			end
		end
	end

	local function fresh_note_buf()
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "placeholder" })
		windows.setup_note_keymaps(bufnr)
		return mapped_lhs(bufnr, "n")
	end

	it("maps p to select_note_in_anki_browser and unbinds s", function()
		local set = mapped_lhs(bufnr, "n")
		assert.is_true(set["p"] == true)
		assert.is_true(set["s"] == nil)
	end)

	it("maps y to sync_selection_from_anki_browser and unbinds S", function()
		local set = mapped_lhs(bufnr, "n")
		assert.is_true(set["y"] == true)
		assert.is_true(set["S"] == nil)
	end)

	it("respects custom remaps for both actions", function()
		config.setup({ mappings = { note = { select_note_in_anki_browser = "<leader>P" } } })
		local set = fresh_note_buf()
		assert.are.equal((vim.g.mapleader or "\\") .. "P", lhs_for(bufnr, "n", "select_note_in_anki_browser"))
		assert.is_true(set["p"] == nil)
		assert.is_true(set["y"] == true)
	end)

	it("respects a custom yank remap while other notes keep defaults", function()
		config.setup({ mappings = { note = { sync_selection_from_anki_browser = "<leader>Y" } } })
		local set = fresh_note_buf()
		assert.are.equal((vim.g.mapleader or "\\") .. "Y", lhs_for(bufnr, "n", "sync_selection_from_anki_browser"))
		assert.is_true(set["p"] == true)
		assert.is_true(set["y"] == nil)
	end)

	it("pressing p invokes select_note_in_anki_browser", function()
		local saved_select = note_ops.select_note_in_anki_browser
		local calls = 0
		note_ops.select_note_in_anki_browser = function()
			calls = calls + 1
		end

		local win = vim.api.nvim_get_current_win()
		pcall(vim.api.nvim_win_set_buf, win, bufnr)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("p", true, false, true), "mx", false)
		drain_async()

		note_ops.select_note_in_anki_browser = saved_select
		assert.are.equal(1, calls)
	end)

	it("pressing y invokes sync_selection_from_anki_browser", function()
		local saved_sync = note_ops.sync_selection_from_anki_browser
		local calls = 0
		note_ops.sync_selection_from_anki_browser = function()
			calls = calls + 1
		end

		local win = vim.api.nvim_get_current_win()
		pcall(vim.api.nvim_win_set_buf, win, bufnr)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("y", true, false, true), "mx", false)
		drain_async()

		note_ops.sync_selection_from_anki_browser = saved_sync
		assert.are.equal(1, calls)
	end)
end)
