local windows = require("anki.ui.windows")
local anki_state = require("anki.state")

describe("windows option setting", function()
	it("sets wrap option using window scope without error", function()
		vim.cmd("vnew")
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_win_get_buf(win)
		assert.has_no.errors(function()
			vim.api.nvim_set_option_value("wrap", false, { win = win })
		end)
		vim.api.nvim_win_close(win, true)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("errors when setting window-local wrap option with buf scope", function()
		local buf = vim.api.nvim_create_buf(false, true)
		assert.has_error(function()
			vim.api.nvim_set_option_value("wrap", false, { buf = buf })
		end)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("errors when setting window-local cursorline option with buf scope", function()
		local buf = vim.api.nvim_create_buf(false, true)
		assert.has_error(function()
			vim.api.nvim_set_option_value("cursorline", true, { buf = buf })
		end)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)

describe("anki.ui.windows create_layout", function()
	local created_tabpage

	before_each(function()
		-- Reset UI state so stubs from prior tests don't leak.
		anki_state.ui.deck_buf_id = nil
		anki_state.ui.note_buf_id = nil
		anki_state.ui.win_id = nil
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.decks = {}
		anki_state.ui.current_filter = nil
		anki_state.ui.view_mode = "notes"
		created_tabpage = nil
	end)

	after_each(function()
		-- Close the tab created by create_layout if it still exists.
		if created_tabpage and vim.api.nvim_tabpage_is_valid(created_tabpage) then
			if #vim.api.nvim_list_tabpages() > 1 then
				vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(created_tabpage))
			else
				vim.cmd("enew")
			end
		end
		-- Clean up buffers if still present.
		for _, bufnr in ipairs({ anki_state.ui.deck_buf_id, anki_state.ui.note_buf_id }) do
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
	end)

	it("creates the layout without error and returns the deck window", function()
		assert.has_no.errors(function()
			local deck_win_id = windows.create_layout()
			created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
			anki_state.ui.win_id = deck_win_id
		end)

		local deck_win_id = anki_state.ui.win_id
		assert.is_true(vim.api.nvim_win_is_valid(deck_win_id))
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
	end)

	it("creates valid deck and note buffers", function()
		local deck_win_id = windows.create_layout()
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
		anki_state.ui.win_id = deck_win_id

		assert.is_true(vim.api.nvim_buf_is_valid(anki_state.ui.deck_buf_id))
		assert.is_true(vim.api.nvim_buf_is_valid(anki_state.ui.note_buf_id))
		assert.is_true(vim.api.nvim_buf_get_name(anki_state.ui.deck_buf_id):find("Anki Decks") ~= nil)
		assert.is_true(vim.api.nvim_buf_get_name(anki_state.ui.note_buf_id):find("Anki Notes") ~= nil)
	end)

	it("sets wrap=false and cursorline=true on both windows (win scope)", function()
		local deck_win_id = windows.create_layout()
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
		anki_state.ui.win_id = deck_win_id

		-- Find the note window within the created tabpage.
		local note_win_id = nil
		for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(created_tabpage)) do
			if win_id ~= deck_win_id then
				note_win_id = win_id
				break
			end
		end
		assert.is_not_nil(note_win_id)

		assert.is_false(vim.api.nvim_get_option_value("wrap", { win = deck_win_id }))
		assert.is_false(vim.api.nvim_get_option_value("wrap", { win = note_win_id }))
		assert.is_true(vim.api.nvim_get_option_value("cursorline", { win = deck_win_id }))
		assert.is_true(vim.api.nvim_get_option_value("cursorline", { win = note_win_id }))
	end)

	it("sets modifiable=true and filetype=anki on both buffers (buf scope)", function()
		local deck_win_id = windows.create_layout()
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
		anki_state.ui.win_id = deck_win_id

		for _, bufnr in ipairs({ anki_state.ui.deck_buf_id, anki_state.ui.note_buf_id }) do
			assert.is_true(vim.api.nvim_get_option_value("modifiable", { buf = bufnr }))
			assert.are.equal("anki", vim.api.nvim_get_option_value("filetype", { buf = bufnr }))
		end
	end)
end)

describe("anki.ui.windows focus_existing_window", function()
	local created_tabpage

	before_each(function()
		anki_state.ui.deck_buf_id = nil
		anki_state.ui.note_buf_id = nil
		anki_state.ui.win_id = nil
		anki_state.ui.notes = {}
		anki_state.ui.cards = {}
		anki_state.ui.decks = {}
		anki_state.ui.current_filter = nil
		anki_state.ui.view_mode = "notes"
		created_tabpage = nil
	end)

	after_each(function()
		-- Close the created Anki tab if it still exists.
		if created_tabpage and vim.api.nvim_tabpage_is_valid(created_tabpage) then
			if vim.api.nvim_get_current_tabpage() == created_tabpage and #vim.api.nvim_list_tabpages() <= 1 then
				vim.cmd("enew")
			elseif #vim.api.nvim_list_tabpages() > 1 then
				vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(created_tabpage))
			else
				vim.cmd("enew")
			end
		end
		for _, bufnr in ipairs({ anki_state.ui.deck_buf_id, anki_state.ui.note_buf_id }) do
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
	end)

	it("returns false when no Anki UI is open", function()
		assert.is_false(windows.focus_existing_window())
	end)

	it("switches tab and focuses the deck window when on a different tab", function()
		local deck_win_id = windows.create_layout()
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
		anki_state.ui.win_id = deck_win_id

		-- Move to a new tab so we are not on the Anki tab.
		vim.cmd("tabnew")
		assert.are_not.equal(created_tabpage, vim.api.nvim_get_current_tabpage())

		local focused = windows.focus_existing_window()
		assert.is_true(focused)
		assert.are.equal(created_tabpage, vim.api.nvim_get_current_tabpage())
		assert.are.equal(deck_win_id, vim.api.nvim_get_current_win())
	end)

	it("does not move cursor when already on the Anki tab", function()
		local deck_win_id = windows.create_layout()
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
		anki_state.ui.win_id = deck_win_id

		-- Find the note window and move cursor to it.
		local note_win_id = nil
		for _, win_id in ipairs(vim.api.nvim_tabpage_list_wins(created_tabpage)) do
			if win_id ~= deck_win_id then
				note_win_id = win_id
				break
			end
		end
		assert.is_not_nil(note_win_id)
		vim.api.nvim_set_current_win(note_win_id)
		assert.are.equal(note_win_id, vim.api.nvim_get_current_win())

		local focused = windows.focus_existing_window()
		assert.is_true(focused)
		-- Cursor stays on the note window; tab unchanged.
		assert.are.equal(note_win_id, vim.api.nvim_get_current_win())
		assert.are.equal(created_tabpage, vim.api.nvim_get_current_tabpage())
	end)

	it("refocuses the deck window when on the Anki tab but in a different split", function()
		local deck_win_id = windows.create_layout()
		created_tabpage = vim.api.nvim_win_get_tabpage(deck_win_id)
		anki_state.ui.win_id = deck_win_id

		-- Create a new split on the same tab so the current window is neither
		-- the deck nor the note window.
		vim.api.nvim_set_current_win(deck_win_id)
		vim.cmd("vnew")
		local stray_win_id = vim.api.nvim_get_current_win()
		assert.are_not.equal(deck_win_id, stray_win_id)
		assert.are_not.equal(vim.fn.bufwinid(anki_state.ui.note_buf_id), stray_win_id)

		local focused = windows.focus_existing_window()
		assert.is_true(focused)
		assert.are.equal(deck_win_id, vim.api.nvim_get_current_win())
		assert.are.equal(created_tabpage, vim.api.nvim_get_current_tabpage())
	end)
end)
