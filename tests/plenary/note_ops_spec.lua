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
