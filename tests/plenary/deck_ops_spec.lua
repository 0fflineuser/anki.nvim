local deck_ops = require("anki.ui.deck_ops")
local anki_state = require("anki.state")
local config = require("anki.config")
local ankiconnect = require("anki.ankiconnect")
local operations = require("anki.ui.operations")
local notification = require("anki.notification")
local spy = require("luassert.spy")

describe("anki.ui.deck_ops.create_deck", function()
	local saved_win_get_cursor
	local saved_ui_input
	local saved_create_deck
	local saved_deck_names
	local saved_refresh_all
	local input_opts
	local input_callback
	local create_deck_calls
	local info_spy
	local error_spy

	before_each(function()
		config.setup({})
		anki_state.ui.decks = { "FooDeck", "BarDeck" }
		input_opts = nil
		input_callback = nil
		create_deck_calls = {}

		saved_win_get_cursor = vim.api.nvim_win_get_cursor
		saved_ui_input = vim.ui.input
		saved_create_deck = ankiconnect.create_deck
		saved_deck_names = ankiconnect.deck_names
		saved_refresh_all = operations.refresh_all

		vim.ui.input = function(opts, on_result)
			input_opts = opts
			input_callback = on_result
		end
		ankiconnect.create_deck = function(name, on_result)
			table.insert(create_deck_calls, name)
			on_result({ name = name }, nil)
		end
		-- Default deck_names stub returns the in-memory test cache; individual
		-- tests can override ankiconnect.deck_names to inject different lists.
		ankiconnect.deck_names = function(on_result)
			on_result(anki_state.ui.decks, nil)
		end
		operations.refresh_all = function() end
		info_spy = spy.on(notification, "info")
		error_spy = spy.on(notification, "error")
	end)

	after_each(function()
		vim.api.nvim_win_get_cursor = saved_win_get_cursor
		vim.ui.input = saved_ui_input
		ankiconnect.create_deck = saved_create_deck
		ankiconnect.deck_names = saved_deck_names
		operations.refresh_all = saved_refresh_all
		if info_spy then
			info_spy:revert()
			info_spy = nil
		end
		if error_spy then
			error_spy:revert()
			error_spy = nil
		end
	end)

	it("prefills the input with the deck under the cursor (line 4)", function()
		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		deck_ops.create_deck()
		assert.is_truthy(input_opts)
		assert.are.equal("FooDeck", input_opts.default)

		input_callback("FooDeck::Sub")
		vim.wait(50, function()
			return false
		end)

		assert.are.equal(1, #create_deck_calls)
		assert.are.equal("FooDeck::Sub", create_deck_calls[1])
	end)

	it("prefills the input with the second deck (line 5)", function()
		vim.api.nvim_win_get_cursor = function()
			return { 5, 0 }
		end

		deck_ops.create_deck()
		assert.are.equal("BarDeck", input_opts.default)
	end)

	it("does not prefill when cursor is on the hint line (line 1)", function()
		vim.api.nvim_win_get_cursor = function()
			return { 1, 0 }
		end

		deck_ops.create_deck()
		assert.is_truthy(input_opts)
		assert.is_nil(input_opts.default)

		input_callback("BrandNew")
		vim.wait(50, function()
			return false
		end)

		assert.are.equal(1, #create_deck_calls)
		assert.are.equal("BrandNew", create_deck_calls[1])
	end)

	it("does not prefill when cursor is on the == Mode == header line (line 2)", function()
		vim.api.nvim_win_get_cursor = function()
			return { 2, 0 }
		end

		deck_ops.create_deck()
		assert.is_nil(input_opts.default)
	end)

	it("does not prefill when cursor is on the blank header line (line 3)", function()
		vim.api.nvim_win_get_cursor = function()
			return { 3, 0 }
		end

		deck_ops.create_deck()
		assert.is_nil(input_opts.default)
	end)

	it("does not call create_deck when input is cancelled", function()
		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		deck_ops.create_deck()
		input_callback(nil)
		vim.wait(50, function()
			return false
		end)

		assert.are.equal(0, #create_deck_calls)
	end)

	it("does not call create_deck when input is empty", function()
		vim.api.nvim_win_get_cursor = function()
			return { 4, 0 }
		end

		deck_ops.create_deck()
		input_callback("")
		vim.wait(50, function()
			return false
		end)

		assert.are.equal(0, #create_deck_calls)
	end)

	describe("pre-flight deck_names existence check", function()
		it("does not call create_deck when the entered name already exists", function()
			ankiconnect.deck_names = function(on_result)
				on_result({ "FooDeck", "BarDeck" }, nil)
			end
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end

			deck_ops.create_deck()
			input_callback("FooDeck")
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(0, #create_deck_calls)
			-- Find the "already exists" info notification among spy calls.
			local found_exists = false
			for _, call in ipairs(info_spy.calls) do
				local msg = call.vals[1]
				if type(msg) == "string" and msg:find("already exists") then
					found_exists = true
					break
				end
			end
			assert.is_true(found_exists)
		end)

		it("proceeds with create_deck when deck_names returns a list without the entered name", function()
			ankiconnect.deck_names = function(on_result)
				on_result({ "OtherDeck" }, nil)
			end
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end

			deck_ops.create_deck()
			input_callback("NewDeck")
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(1, #create_deck_calls)
			assert.are.equal("NewDeck", create_deck_calls[1])
		end)

		it("does not call create_deck when the pre-flight deck_names lookup errors", function()
			ankiconnect.deck_names = function(on_result)
				on_result(nil, "network down")
			end
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end

			deck_ops.create_deck()
			input_callback("NewDeck")
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(0, #create_deck_calls)
			local found_error = false
			for _, call in ipairs(error_spy.calls) do
				local msg = call.vals[1]
				if type(msg) == "string" and msg:find("Failed to check existing decks") then
					found_error = true
					break
				end
			end
			assert.is_true(found_error)
		end)

		it("does not call create_deck when the pre-flight deck_names returns nil without error", function()
			ankiconnect.deck_names = function(on_result)
				on_result(nil, nil)
			end
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end

			deck_ops.create_deck()
			input_callback("NewDeck")
			vim.wait(50, function()
				return false
			end)

			assert.are.equal(0, #create_deck_calls)
		end)
	end)
end)
