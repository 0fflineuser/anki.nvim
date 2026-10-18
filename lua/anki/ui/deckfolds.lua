local M = {}

--- Computes the fold expression value for a deck buffer line.
-- NERDTree-style recipe: a parent line joins its child fold so that toggling
-- the fold on the parent line works. Depth is the count of leading tabs.
-- @param lnum number Line number (1-based)
-- @return number|string Fold level value for `foldexpr`
function M.deck_fold_expr(lnum)
	local bufnr = vim.api.nvim_get_current_buf()
	if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t") ~= "Anki Decks" then
		return 0
	end

	-- Count leading tabs in a line; missing line returns -1.
	-- Uses find() (single number return): a two-capture match() assigned as
	-- `local _, tabs = ...` puts the rest-of-line in `tabs`, so `#tabs` would
	-- measure the line length, not the tab prefix.
	local function leading_tabs(n)
		if n < 1 then
			return -1
		end
		local ok, lines = pcall(vim.api.nvim_buf_get_lines, 0, n - 1, n, false)
		if not ok or not lines or #lines == 0 then
			return -1
		end
		local first_non_tab = lines[1]:find("[^\t]")
		if not first_non_tab then
			return #lines[1]
		end
		return first_non_tab - 1
	end

	local c = leading_tabs(lnum)
	if c < 0 then
		return 0
	end
	local n = leading_tabs(lnum + 1)

	local ret
	if n > c then
		ret = n
	elseif n == c then
		ret = "="
	elseif n < 0 then
		ret = c
	else
		ret = "<" .. c
	end
	-- foldexpr evaluates numbers as decimal and strings with special prefixes;
	-- returning a string keeps "<N" semantics intact for every branch.
	if type(ret) == "number" then
		ret = tostring(ret)
	end
	return ret
end

--- Sets up expr folds on the deck window.
-- Window-local options: `foldmethod=expr` with the deck fold expression,
-- `foldenable`, and `foldminlines=0` (required so the parent line can join
-- its child fold and remain visible as the fold itself).
-- @param bufnr number Deck buffer number (unused, kept for symmetry)
-- @param win_id number Deck window id
function M.setup_deck_folds(bufnr, win_id)
	_G.anki_deck_fold_expr = M.deck_fold_expr
	vim.api.nvim_set_option_value("foldmethod", "expr", { win = win_id })
	vim.api.nvim_set_option_value("foldexpr", "v:lua.anki_deck_fold_expr(v:lnum)", { win = win_id })
	vim.api.nvim_set_option_value("foldenable", true, { win = win_id })
	vim.api.nvim_set_option_value("foldminlines", 0, { win = win_id })
end

--- Indents deck lines according to `::` nesting depth, Anki-GUI style.
-- Depth is derived from the deck name itself (number of `::` segments),
-- independent of list order. Each line shows only the deck's own name (the
-- text after the last `::`), prefixed with one `\t` per level; parent decks
-- above provide the path context.
-- @param deck_names string[] Deck names as returned by AnkiConnect
-- @return string[] Indented lines
function M.indent_deck_lines(deck_names)
	local lines = {}
	for _, name in ipairs(deck_names) do
		local _, segments = name:gsub("::", "::")
		local depth = segments
		local leaf = name:match(".*::(.*)$") or name
		table.insert(lines, ("\t"):rep(depth) .. leaf)
	end
	return lines
end

return M
