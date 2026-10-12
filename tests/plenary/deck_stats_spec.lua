local deck_stats = require("anki.ui.deck_stats")
local anki_state = require("anki.state")
local config = require("anki.config")
local ankiconnect = require("anki.ankiconnect")
local notification = require("anki.notification")
local operations = require("anki.ui.operations")
local spy = require("luassert.spy")

local function is_stats_buf(bufnr)
	-- nvim_buf_get_name returns the resolved absolute path; match the basename.
	return vim.api.nvim_buf_is_valid(bufnr)
		and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t") == "Anki Deck Stats"
end

local function delete_stats_buffers()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_stats_buf(bufnr) then
			pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
		end
	end
end

local function stats_buf_count()
	local count = 0
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_stats_buf(bufnr) then
			count = count + 1
		end
	end
	return count
end

local function stats_bufnr()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_stats_buf(bufnr) then
			return bufnr
		end
	end
	return -1
end

describe("anki.ui.deck_stats", function()
	local saved_win_get_cursor
	local saved_get_deck_stats
	local saved_get_num_cards_reviewed_today
	local saved_get_num_cards_reviewed_by_day
	local warn_spy

	before_each(function()
		config.setup({})
		anki_state.ui.decks = {}
		delete_stats_buffers()

		saved_win_get_cursor = vim.api.nvim_win_get_cursor
		saved_get_deck_stats = ankiconnect.get_deck_stats
		saved_get_num_cards_reviewed_today = ankiconnect.get_num_cards_reviewed_today
		saved_get_num_cards_reviewed_by_day = ankiconnect.get_num_cards_reviewed_by_day
	end)

	after_each(function()
		vim.api.nvim_win_get_cursor = saved_win_get_cursor
		ankiconnect.get_deck_stats = saved_get_deck_stats
		ankiconnect.get_num_cards_reviewed_today = saved_get_num_cards_reviewed_today
		ankiconnect.get_num_cards_reviewed_by_day = saved_get_num_cards_reviewed_by_day
		if warn_spy then
			warn_spy:revert()
			warn_spy = nil
		end
		pcall(deck_stats.close)
		anki_state.ui.decks = {}
		delete_stats_buffers()
	end)

	describe("open", function()
		it("warns and opens nothing when the cursor is not on a deck line", function()
			vim.api.nvim_win_get_cursor = function()
				return { 4, 0 }
			end
			warn_spy = spy.on(notification, "warn")

			deck_stats.open()

			assert.spy(warn_spy).was_called_with("[anki.nvim][deck_stats] No deck selected")
			assert.are.equal(0, stats_buf_count())
		end)

		it("renders due counts, today, and a 7-day bar strip for the deck under the cursor", function()
			anki_state.ui.decks = { "TestDeck" }
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 1, 0 }
			end

			ankiconnect.get_deck_stats = function(decks, on_result)
				assert.are.same({ "TestDeck" }, decks)
				on_result({
					["1"] = {
						deck_id = 1,
						name = "TestDeck",
						new_count = 2,
						learn_count = 0,
						review_count = 0,
						total_in_deck = 2,
					},
				}, nil)
			end
			ankiconnect.get_num_cards_reviewed_today = function(on_result)
				on_result(42, nil)
			end
			ankiconnect.get_num_cards_reviewed_by_day = function(on_result)
				on_result({
					{ "2026-01-10", 30 },
					{ "2026-01-09", 15 },
					{ "2026-01-08", 0 },
					{ "2026-01-07", 3 },
					{ "2026-01-06", 1 },
					{ "2026-01-05", 0 },
					{ "2026-01-04", 5 },
					{ "2026-01-03", 2 },
				}, nil)
			end

			deck_stats.open()

			local bufnr = stats_bufnr()
			assert.is_true(vim.wait(1000, function()
				return vim.api.nvim_buf_is_valid(bufnr) and #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) > 1
			end))
			vim.wait(100, function()
				return false
			end)

			local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
			local joined = table.concat(lines, "\n")
			assert.is_true(joined:find("Deck: TestDeck", 1, true) ~= nil)
			assert.is_true(joined:find("Due (per deck):", 1, true) ~= nil)
			assert.is_true(joined:find("  New     2\n", 1, true) ~= nil)
			assert.is_true(joined:find("  Learn   0\n", 1, true) ~= nil)
			assert.is_true(joined:find("  Review  0\n", 1, true) ~= nil)
			assert.is_true(joined:find("  Total   2\n", 1, true) ~= nil)
			assert.is_true(joined:find("  Today   42  (reviewed across all decks)\n", 1, true) ~= nil)
			assert.is_true(
				joined:find(
					"History (all decks, last 7 days): counts are reviews per day; bar proportional to the busiest day",
					1,
					true
				) ~= nil
			)
			-- 7 of the 8 supplied days fit the strip; the 30-review day fills a
			-- full 20-wide bar, zero days render no bar at all.
			assert.is_true(joined:find("2026%-01%-10", 1, false) ~= nil)
			assert.is_true(joined:find("2026%-01%-04", 1, false) ~= nil)
			assert.is_true(joined:find("2026%-01%-03", 1, false) == nil)
			assert.is_true(joined:find(string.rep("█", 20), 1, true) ~= nil)
			assert.is_true(joined:find("Refresh: r - Close: <leader>k / q / <Esc>", 1, true) ~= nil)

			local winid = vim.api.nvim_get_current_win()
			local win_config = vim.api.nvim_win_get_config(winid)
			assert.are.equal(bufnr, vim.api.nvim_win_get_buf(winid))
			assert.are.equal("editor", win_config.relative)
			assert.is_true(win_config.border == "single" or type(win_config.border) == "table")

			-- Close keys are mapped buffer-locally.
			local mapped = {}
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
				mapped[map.lhs] = true
			end
			assert.is_true(mapped["q"] ~= nil)
			assert.is_true(mapped["<Esc>"] ~= nil)
		end)

		it("resolves a subdeck row by its short name", function()
			anki_state.ui.decks = { "Foo::demo" }
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 1, 0 }
			end
			ankiconnect.get_deck_stats = function(_, on_result)
				on_result({
					["1778330433742"] = {
						name = "demo",
						new_count = 0,
						learn_count = 1,
						review_count = 2,
						total_in_deck = 3,
					},
				}, nil)
			end
			ankiconnect.get_num_cards_reviewed_today = function(on_result)
				on_result(7, nil)
			end
			ankiconnect.get_num_cards_reviewed_by_day = function(on_result)
				on_result({}, nil)
			end

			deck_stats.open()

			local bufnr = stats_bufnr()
			assert.is_true(vim.wait(1000, function()
				return vim.api.nvim_buf_is_valid(bufnr) and #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) > 1
			end))
			vim.wait(100, function()
				return false
			end)

			local joined = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			assert.is_true(joined:find("Deck: Foo::demo", 1, true) ~= nil)
			assert.is_true(joined:find("  Learn   1\n", 1, true) ~= nil)
			assert.is_true(joined:find("  Total   3\n", 1, true) ~= nil)
			assert.is_true(joined:find("  Today   7", 1, true) ~= nil)
		end)

		it("deduplicates the popup buffer when reopened", function()
			anki_state.ui.decks = { "TestDeck" }
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 1, 0 }
			end
			ankiconnect.get_deck_stats = function(decks, on_result)
				on_result({
					["1"] = {
						name = "TestDeck",
						new_count = 1,
						learn_count = 1,
						review_count = 1,
						total_in_deck = 1,
					},
				}, nil)
			end
			ankiconnect.get_num_cards_reviewed_today = function(on_result)
				on_result(1, nil)
			end
			ankiconnect.get_num_cards_reviewed_by_day = function(on_result)
				on_result({}, nil)
			end

			deck_stats.open()
			deck_stats.open()

			assert.are.equal(1, stats_buf_count())
		end)

		it("closes and cleans up the popup buffer and window", function()
			anki_state.ui.decks = { "TestDeck" }
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 1, 0 }
			end
			ankiconnect.get_deck_stats = function(_, on_result)
				on_result({}, nil)
			end
			ankiconnect.get_num_cards_reviewed_today = function(on_result)
				on_result(0, nil)
			end
			ankiconnect.get_num_cards_reviewed_by_day = function(on_result)
				on_result({}, nil)
			end

			deck_stats.open()
			local bufnr = stats_bufnr()
			assert.is_true(vim.api.nvim_buf_is_valid(bufnr))

			deck_stats.close()

			assert.is_false(vim.api.nvim_buf_is_valid(bufnr))
			assert.are.equal(-1, stats_bufnr())
		end)

		it("ignores stale results from a previous popup after reopening", function()
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 1, 0 }
			end
			local pending_calls = {}
			ankiconnect.get_deck_stats = function(_, on_result)
				table.insert(pending_calls, on_result)
			end
			ankiconnect.get_num_cards_reviewed_today = function(on_result)
				table.insert(pending_calls, on_result)
			end
			ankiconnect.get_num_cards_reviewed_by_day = function(on_result)
				table.insert(pending_calls, on_result)
			end

			anki_state.ui.decks = { "DeckA", "DeckB" }
			deck_stats.open()
			-- Reopen on the second deck before any result arrives.
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 2, 0 }
			end
			deck_stats.open()

			local bufnr = stats_bufnr()
			assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
			-- Only the first popup's three callbacks deliver; the generation
			-- guard must discard them instead of rendering stale DeckA data.
			for i = 1, 3 do
				pending_calls[i](
					{ ["1"] = { name = "DeckA", new_count = 0, learn_count = 0, review_count = 0, total_in_deck = 0 } },
					nil
				)
			end
			vim.wait(100, function()
				return false
			end)
			if not vim.api.nvim_buf_is_valid(bufnr) then
				assert.fail("second popup was closed by a stale WinLeave")
			end

			local joined = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			assert.is_true(joined:find("Deck: DeckA", 1, true) == nil)
			assert.is_true(joined:find("Loading stats for 'DeckB'", 1, true) ~= nil)
		end)

		it("refresh re-resolves the current deck and keeps a single popup", function()
			anki_state.ui.decks = { "DeckA", "DeckB" }
			vim.api.nvim_win_get_cursor = function()
				return { operations.HEADER_LINES + 1, 0 }
			end
			ankiconnect.get_deck_stats = function(_, on_result)
				on_result({
					["1"] = { name = "DeckA", new_count = 1, learn_count = 0, review_count = 0, total_in_deck = 1 },
				}, nil)
			end
			ankiconnect.get_num_cards_reviewed_today = function(on_result)
				on_result(0, nil)
			end
			ankiconnect.get_num_cards_reviewed_by_day = function(on_result)
				on_result({}, nil)
			end

			deck_stats.open()
			local old_bufnr = stats_bufnr()
			assert.is_true(vim.wait(1000, function()
				return vim.api.nvim_buf_is_valid(old_bufnr) and #vim.api.nvim_buf_get_lines(old_bufnr, 0, -1, false) > 1
			end))

			-- Simulate the deck list changing under the popup: the refreshed
			-- render must show the new data for the same deck, and exactly one
			-- popup buffer must exist afterwards.
			ankiconnect.get_deck_stats = function(_, on_result)
				on_result({
					["2"] = { name = "DeckA", new_count = 5, learn_count = 0, review_count = 0, total_in_deck = 9 },
				}, nil)
			end
			deck_stats._refresh()

			local bufnr = stats_bufnr()
			assert.is_true(vim.wait(1000, function()
				return vim.api.nvim_buf_is_valid(bufnr) and #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) > 1
			end))
			vim.wait(100, function()
				return false
			end)

			assert.are.equal(1, stats_buf_count())
			local joined = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
			assert.is_true(joined:find("Deck: DeckA", 1, true) ~= nil)
			assert.is_true(joined:find("  New     5\n", 1, true) ~= nil)
		end)
	end)
end)
