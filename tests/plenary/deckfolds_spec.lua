local deckfolds = require("anki.ui.deckfolds")

describe("anki.ui.deckfolds indent_deck_lines", function()
	it("indents by :: nesting depth, showing only the deck's own name", function()
		assert.are_same(
			{ "Foo", "\tBar", "\t\tBaz", "Other" },
			deckfolds.indent_deck_lines({ "Foo", "Foo::Bar", "Foo::Bar::Baz", "Other" })
		)
	end)

	it("returns an empty list for empty input", function()
		assert.are_same({}, deckfolds.indent_deck_lines({}))
	end)

	it("derives depth from the name, not list order", function()
		assert.are_same({ "\tBar", "Foo" }, deckfolds.indent_deck_lines({ "Foo::Bar", "Foo" }))
	end)

	it("shows identical rows for different decks with the same leaf name", function()
		assert.are_same({ "\tSub", "\tSub" }, deckfolds.indent_deck_lines({ "A::Sub", "B::Sub" }))
	end)
end)

describe("anki.ui.deckfolds deck_fold_expr", function()
	local bufnr

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, "Anki Decks")
		vim.api.nvim_set_current_buf(bufnr)
	end)

	after_each(function()
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)

	it("returns 0 for buffers other than 'Anki Decks'", function()
		local other = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(other, "Not Anki")
		vim.api.nvim_set_current_buf(other)
		vim.api.nvim_buf_set_lines(other, 0, -1, false, { "Foo", "\tFoo::Bar" })
		assert.equals(0, deckfolds.deck_fold_expr(1))
		vim.api.nvim_buf_delete(other, { force = true })
		vim.api.nvim_set_current_buf(bufnr)
	end)

	it("returns exact fold values for every branch", function()
		local fixture = {
			"Foo", --            1: c=0, n=1 -> "1"
			"\tFoo::Bar", --     2: c=1, n=2 -> "2"
			"\t\tFoo::Bar::Baz", -- 3: c=2, n=1 -> "<2"
			"\tFoo::Baz", --     4: c=1, n=0 -> "<1"
			"Other", --          5: c=0, n=1 -> "1"
			"\tOther::Sub", --   6: last line, line 7 missing -> n=-1 -> c=1
		}
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, fixture)
		assert.equals("1", deckfolds.deck_fold_expr(1))
		assert.equals("2", deckfolds.deck_fold_expr(2))
		assert.equals("<2", deckfolds.deck_fold_expr(3))
		assert.equals("<1", deckfolds.deck_fold_expr(4))
		assert.equals("1", deckfolds.deck_fold_expr(5))
		assert.equals("1", deckfolds.deck_fold_expr(6))
	end)

	it("returns '=' for sibling lines at equal depth", function()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "A", "\tA::B", "\tA::C" })
		assert.equals("=", deckfolds.deck_fold_expr(2))
	end)
end)

describe("anki.ui.deckfolds fold behavior", function()
	local bufnr, win_id

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(bufnr, "Anki Decks")
		win_id = vim.api.nvim_open_win(bufnr, true, { relative = "editor", row = 0, col = 0, width = 40, height = 10 })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Foo", "\tFoo::Bar", "\t\tFoo::Bar::Baz", "Other" })
		deckfolds.setup_deck_folds(bufnr, win_id)
	end)

	after_each(function()
		vim.api.nvim_win_close(win_id, true)
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end)

	it("fold options are set on the deck window", function()
		assert.equals("expr", vim.api.nvim_get_option_value("foldmethod", { win = win_id }))
		assert.equals(true, vim.api.nvim_get_option_value("foldenable", { win = win_id }))
		assert.equals(0, vim.api.nvim_get_option_value("foldminlines", { win = win_id }))
	end)

	it("zc on parent closes the whole subtree; za reopens", function()
		vim.api.nvim_win_set_cursor(win_id, { 1, 0 })
		vim.cmd("normal! zc")
		assert.equals(1, vim.fn.foldclosed(1))
		assert.equals(1, vim.fn.foldclosed(2))
		assert.equals(1, vim.fn.foldclosed(3))
		assert.equals(-1, vim.fn.foldclosed(4))
		assert.equals(3, vim.fn.foldclosedend(1))
		vim.cmd("normal! za")
		assert.equals(-1, vim.fn.foldclosed(1))
	end)

	it("fold survives a full-buffer re-render", function()
		vim.api.nvim_win_set_cursor(win_id, { 1, 0 })
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Foo", "\tFoo::Bar", "\t\tFoo::Bar::Baz", "Other" })
		vim.cmd("normal! zc")
		assert.equals(1, vim.fn.foldclosed(1))
		assert.equals(3, vim.fn.foldclosedend(1))
	end)
end)
