---
--- anki.ui.deck_stats
---
--- Floating popup that shows statistics for the deck under the cursor in the
--- deck pane: per-deck counts from getDeckStats, today's reviewed count from
--- getNumCardsReviewedToday, and a last-7-days bar strip from
--- getNumCardsReviewedByDay.
---
local ankiconnect = require("anki.ankiconnect")
local config = require("anki.config")
local notification = require("anki.notification")
local utils = require("anki.utils")

local M = {}

local state = {
	buf = nil,
	win = nil,
	deck = nil,
	generation = 0,
}

local function set_key(buf, mode, lhs, rhs)
	vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, { noremap = true, silent = true })
end

local function setup_keymaps(bufnr)
	local close_rhs = "<Cmd>lua require('anki.ui.deck_stats').close()<CR>"
	set_key(bufnr, "n", "r", "<Cmd>lua require('anki.ui.deck_stats')._refresh()<CR>")
	set_key(bufnr, "n", "<Esc>", close_rhs)
	set_key(bufnr, "n", "q", close_rhs)
	set_key(bufnr, "n", config.options.mappings.deck.close, close_rhs)
end

--- Formats a stat value as an integer string, tolerating string values from
--- unusual AnkiConnect versions.
---@param value any The raw count value.
---@return string
local function format_count(value)
	if type(value) == "number" then
		return string.format("%d", value)
	end
	if value == nil then
		return "n/a"
	end
	return tostring(value)
end

--- Builds the last-7-days bar lines from (dateString, count) pairs.
---@param by_day table|nil The raw getNumCardsReviewedByDay result.
---@return string[] lines One line per day, prefixed by the section indent.
local function build_bar_lines(by_day)
	local lines = {}
	if type(by_day) ~= "table" then
		return lines
	end

	local days = {}
	for i = 1, math.min(#by_day, 7) do
		table.insert(days, by_day[i])
	end

	local max = 1
	for _, day in ipairs(days) do
		local count = (day[2] or 0) + 0
		if count > max then
			max = count
		end
	end

	for _, day in ipairs(days) do
		local label = tostring(day[1]):sub(1, 10)
		local count = (day[2] or 0) + 0
		local bar_width = 20
		local filled = count == 0 and 0 or math.max(1, math.floor(count / max * bar_width + 0.5))
		table.insert(lines, string.format("  %s %4d %s", label, count, string.rep("█", filled)))
	end
	return lines
end

--- Finds the getDeckStats row for a deck. The response is keyed by each
--- deck's numeric deck-ID string and rows carry the (possibly short) deck
--- name, so match by name: any direct row under the deck name itself, then
--- an exact full-name row, then a short-name row (part after the last `::`).
---@param deck_name string The cursor deck's name.
---@param deck_stats table|nil The raw getDeckStats response.
---@return table|nil stats The matching row, or nil when absent.
local function lookup_deck_stats(deck_name, deck_stats)
	if type(deck_stats) ~= "table" then
		return nil
	end

	local direct = deck_stats[deck_name]
	if type(direct) == "table" then
		return direct
	end

	local short = deck_name:match("::([^:]+)$") or deck_name
	local exact_match, short_match = nil, nil
	for _, row in pairs(deck_stats) do
		if type(row) == "table" then
			local row_name = tostring(row.name or "")
			if row_name == deck_name and exact_match == nil then
				exact_match = row
			elseif row_name == short and short_match == nil then
				short_match = row
			end
		end
	end
	return exact_match or short_match
end

--- Builds the per-deck due block: labeled count rows in fixed order plus the
--- global "Today" reviews row. Missing data renders as `n/a` per line.
---@param deck_name string The cursor deck's name.
---@param deck_stats table|nil The raw getDeckStats response.
---@param today number|nil getNumCardsReviewedToday count (nil on error).
---@return string[] lines
local function build_due_lines(deck_name, deck_stats, today)
	local stats = lookup_deck_stats(deck_name, deck_stats)
	local function count(field)
		if stats == nil then
			return nil
		end
		return stats[field]
	end
	return {
		"Due (per deck):",
		string.format("  %-8s%s", "New", format_count(count("new_count"))),
		string.format("  %-8s%s", "Learn", format_count(count("learn_count"))),
		string.format("  %-8s%s", "Review", format_count(count("review_count"))),
		string.format("  %-8s%s", "Total", format_count(count("total_in_deck"))),
		string.format("  %-8s%s  (reviewed across all decks)", "Today", format_count(today)),
	}
end

--- Renders the stats popup contents and resizes the float to fit.
---
--- `deck_stats` is the whole getDeckStats response (keyed by deck ID); the
--- row for the shown deck is resolved by name.
---@param deck_name string The deck whose stats are shown.
---@param deck_stats table|nil getDeckStats response (nil on error).
---@param today number|nil getNumCardsReviewedToday count (nil on error).
---@param by_day table|nil getNumCardsReviewedByDay pairs (nil on error).
local function render(deck_name, deck_stats, today, by_day)
	local lines = {
		"Deck: " .. deck_name,
		"",
	}
	for _, line in ipairs(build_due_lines(deck_name, deck_stats, today)) do
		table.insert(lines, line)
	end

	table.insert(lines, "")
	table.insert(
		lines,
		"History (all decks, last 7 days): counts are reviews per day; bar proportional to the busiest day"
	)
	local bar_lines = build_bar_lines(by_day)
	if #bar_lines == 0 then
		table.insert(lines, "  n/a")
	else
		for _, line in ipairs(bar_lines) do
			table.insert(lines, line)
		end
	end

	table.insert(lines, "")
	table.insert(lines, "Refresh: r - Close: " .. config.options.mappings.deck.close .. " / q / <Esc>")

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end

	local bufnr = state.buf
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false

	local width = 30
	for _, line in ipairs(lines) do
		width = math.max(width, vim.api.nvim_strwidth(line))
	end
	width = math.min(width, vim.o.columns - 2)
	local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.8))
	vim.api.nvim_win_set_config(state.win, {
		width = width,
		height = height,
		relative = "editor",
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		anchor = "NW",
	})
end

--- Validates the resolved deck name and opens the stats popup for it.
---@param deck_name string|nil Resolved deck name from the deck pane cursor.
local function open_for_deck(deck_name)
	if type(deck_name) ~= "string" or deck_name == "" then
		notification.warn("[anki.nvim][deck_stats] No deck selected")
		return
	end

	M.close()
	state.generation = state.generation + 1
	local gen = state.generation

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(bufnr, "Anki Deck Stats")
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Loading stats for '" .. deck_name .. "' ..." })
	vim.bo[bufnr].modifiable = false

	state.buf = bufnr
	state.deck = deck_name

	local width = 40
	local height = 5
	local winid = vim.api.nvim_open_win(bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		anchor = "NW",
		style = "minimal",
		border = "single",
		title = "Anki Stats",
		title_pos = "center",
	})
	state.win = winid
	setup_keymaps(bufnr)

	local pending = 3
	local got_deck_stats, got_today, got_by_day

	local function on_section(on_result)
		return function(result, error)
			if state.generation ~= gen or not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
				return
			end
			pending = pending - 1
			if on_result then
				on_result(result, error)
			end
			if pending == 0 then
				render(state.deck, got_deck_stats, got_today, got_by_day)
			end
		end
	end

	utils.async_safe_call(
		ankiconnect.get_deck_stats,
		{ { deck_name } },
		on_section(function(result, _)
			got_deck_stats = result
		end)
	)
	utils.async_safe_call(
		ankiconnect.get_num_cards_reviewed_today,
		nil,
		on_section(function(result, _)
			got_today = result
		end)
	)
	utils.async_safe_call(
		ankiconnect.get_num_cards_reviewed_by_day,
		nil,
		on_section(function(result, _)
			got_by_day = result
		end)
	)

	-- Close the popup when it loses focus. The callback is pinned to this
	-- popup's buffer and generation so a scheduled WinLeave fired by tearing
	-- this popup down (buffer already invalid or replaced by a reopen) cannot
	-- close the newer popup.
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = bufnr,
		once = true,
		callback = function()
			vim.schedule(function()
				if state.generation ~= gen or state.buf ~= bufnr then
					return
				end
				if not vim.api.nvim_buf_is_valid(state.buf) then
					return
				end
				M.close()
			end)
		end,
	})
end

--- Opens the deck stats popup for the deck under the cursor in the deck pane.
function M.open()
	local deck_ops = require("anki.ui.deck_ops")
	open_for_deck(deck_ops.deck_at_cursor())
end

--- Re-opens the popup for the deck it is currently showing (`r` inside the
--- popup). A no-op when no popup is open.
function M._refresh()
	if type(state.deck) ~= "string" or state.deck == "" then
		return
	end
	open_for_deck(state.deck)
end

--- Closes the stats popup, cleaning up the floating window and buffer.
function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
	end
	state.buf = nil
	state.win = nil
	state.deck = nil
	-- Bump, never reset: a zero-reset could collide a late callback from a
	-- previous popup with a freshly opened one sharing the same generation.
	state.generation = state.generation + 1
end

return M
