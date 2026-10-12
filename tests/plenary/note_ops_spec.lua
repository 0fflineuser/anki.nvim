local note_ops = require("anki.ui.note_ops")
local anki_state = require("anki.state")
local config = require("anki.config")
local ankiconnect = require("anki.ankiconnect")
local editor = require("anki.editor")
local operations = require("anki.ui.operations")
local notification = require("anki.notification")
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
