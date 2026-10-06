local config = require("anki.config")
local help = require("anki.ui.help")
local editor = require("anki.editor")
local sticky = require("anki.sticky")
local anki_state = require("anki.state")

--- Creates a real note (with real buffers), registers it as the current tab's
--- note, and returns note plus the captured help bufnr/winid after opening help.
local function open_help_with_note()
	local note = editor.create_note("TestDeck", "TestModel", { "Front", "Back" })
	local tabid = vim.api.nvim_get_current_tabpage()
	anki_state.current_notes[tabid] = note
	note.tabid = tabid

	local help_bufnr, help_winid = nil, nil
	local saved_open_win = vim.api.nvim_open_win
	vim.api.nvim_open_win = function(buffer, enter, opts)
		help_bufnr, help_winid = buffer, saved_open_win(buffer, enter, opts)
		return help_winid
	end
	local ok, err = pcall(help.show_help, "editor")
	vim.api.nvim_open_win = saved_open_win
	if not ok then
		error(err)
	end

	return note, help_bufnr, help_winid
end

--- Clears all Anki Help buffers, note-editor buffers, per-tab state, and extra
--- tabpages left over from any previous test, keeping tests independent.
local function scrub_state()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name:find("anki://", 1, true) or name:find("Anki Help", 1, true) then
				pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
			end
		end
	end
	anki_state.current_notes = {}
	sticky._store = {}
end

local function cleanup(note, help_bufnr)
	scrub_state()
	-- Tests that call display_note create a dedicated editor tab; close it. Tests
	-- that only register the note in the base tab have no extra tab to close.
	if note and note.tabid and vim.api.nvim_tabpage_is_valid(note.tabid) and #vim.api.nvim_list_tabpages() > 1 then
		local cur = vim.api.nvim_get_current_tabpage()
		if cur == note.tabid then
			for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
				if tabid ~= note.tabid then
					vim.api.nvim_set_current_tabpage(tabid)
					break
				end
			end
		end
		-- The note editor tab holds only note windows (tag window + field splits),
		-- so closing the tab removes all of them; the help float (separate window
		-- over the current tab) already lost its buffer above and is gone.
		vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(note.tabid))
		if vim.api.nvim_tabpage_is_valid(cur) and cur ~= note.tabid then
			vim.api.nvim_set_current_tabpage(cur)
		end
	end
	-- Keep at least one tabpage alive.
	if #vim.api.nvim_list_tabpages() == 0 then
		vim.cmd("tabnew")
	end
end

--- Opens editor help without any note registered in the current tab.
local function open_help_without_note()
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
	return help_bufnr
end

describe("editor help sticky checkboxes", function()
	before_each(function()
		config.setup({})
		scrub_state()
	end)

	after_each(function()
		scrub_state()
	end)

	it("display_note leaves no winbar hint on editor windows", function()
		local note = editor.create_note("TestDeck", "TestModel", { "Front", "Back" })
		editor.display_note(note)
		assert.equals("", vim.api.nvim_get_option_value("winbar", { win = note.tags.winid }))
		for _, field in ipairs(note.fields) do
			assert.equals("", vim.api.nvim_get_option_value("winbar", { win = field.editor_context.winid }))
		end
		cleanup(note)
	end)

	it("editor help shows a checkbox per field, unchecked by default", function()
		local note, help_bufnr = open_help_with_note()
		local joined = table.concat(vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false), "\n")
		assert.truthy(
			joined:find(
				"Sticky fields %(press <C%-Space> on a field to toggle; sticky fields keep their content for the next note%)",
				1,
				false
			)
		)
		assert.truthy(joined:find("  %[% %] Front", 1, false))
		assert.truthy(joined:find("  %[% %] Back", 1, false))
		cleanup(note, help_bufnr)
	end)

	it("reflects toggled state and <C-Space> toggles the box", function()
		sticky.toggle("TestModel", "Front")
		local note, help_bufnr, help_winid = open_help_with_note()

		-- Toggled field renders checked.
		local lines = vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false)
		local joined = table.concat(lines, "\n")
		assert.truthy(joined:find("  %[x%] Front", 1, false))
		assert.truthy(joined:find("  %[% %] Back", 1, false))

		-- Buffer-local <C-Space> normal-mode keymap exists.
		local found = false
		for _, map in ipairs(vim.api.nvim_buf_get_keymap(help_bufnr, "n")) do
			if map.lhs == "<C-Space>" then
				found = true
			end
		end
		assert.is_true(found)

		-- Toggling on the Front line flips the store and rewrites the box.
		local first_line = vim.api.nvim_buf_get_var(help_bufnr, "anki_sticky_first_line")
		vim.api.nvim_win_set_cursor(help_winid, { first_line, 0 })
		help._toggle_sticky_field(help_bufnr)
		assert.is_false(sticky.is_sticky("TestModel", "Front"))
		assert.equals("  [ ] Front", vim.api.nvim_buf_get_lines(help_bufnr, first_line - 1, first_line, false)[1])

		-- Toggling on the Back line flips the store and rewrites the box.
		vim.api.nvim_win_set_cursor(help_winid, { first_line + 1, 0 })
		help._toggle_sticky_field(help_bufnr)
		assert.is_true(sticky.is_sticky("TestModel", "Back"))
		assert.equals("  [x] Back", vim.api.nvim_buf_get_lines(help_bufnr, first_line, first_line + 1, false)[1])

		cleanup(note, help_bufnr)
	end)

	it("ignores cursor presses outside the checkbox lines", function()
		local note, help_bufnr, help_winid = open_help_with_note()
		local first_line = vim.api.nvim_buf_get_var(help_bufnr, "anki_sticky_first_line")
		local lines_before = vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false)

		-- Cursor on the section header line.
		vim.api.nvim_win_set_cursor(help_winid, { first_line - 1, 0 })
		help._toggle_sticky_field(help_bufnr)

		-- Cursor on a non-field line near the top of the help text.
		vim.api.nvim_win_set_cursor(help_winid, { 3, 0 })
		help._toggle_sticky_field(help_bufnr)

		assert.are.equal(0, vim.tbl_count(sticky.get("TestModel")))
		local lines_after = vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false)
		assert.same(lines_before, lines_after)
		cleanup(note, help_bufnr)
	end)

	it("omits the sticky section when no note is open in the current tab", function()
		local help_bufnr = open_help_without_note()
		local joined = table.concat(vim.api.nvim_buf_get_lines(help_bufnr, 0, -1, false), "\n")
		assert.falsy(joined:find("Sticky fields", 1, true))
		assert.has_error(function()
			vim.api.nvim_buf_get_var(help_bufnr, "anki_sticky_model")
		end)
		vim.api.nvim_buf_delete(help_bufnr, { force = true })
	end)
end)
