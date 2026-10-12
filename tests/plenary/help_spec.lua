local config = require("anki.config")
local help = require("anki.ui.help")

local function get_help_lines(context)
	local bufnr = nil
	local saved_open_win = vim.api.nvim_open_win

	vim.api.nvim_open_win = function(buffer, enter, opts)
		bufnr = buffer
		return saved_open_win(buffer, enter, opts)
	end

	local ok, err = pcall(help.show_help, context)

	local lines = {}
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_buf_delete(bufnr, { force = true })
	end

	vim.api.nvim_open_win = saved_open_win

	if not ok then
		return nil, err
	end
	return lines
end

local function cleanup_help_buffers()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name:find("Anki Help") then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end
	end
end

describe("anki.ui.help", function()
	before_each(function()
		config.setup({})
		cleanup_help_buffers()
	end)

	describe("help window sizing", function()
		local function open_capturing(context)
			local longest = 0
			local captured_width = nil
			local bufnr = nil
			local saved_open_win = vim.api.nvim_open_win
			vim.api.nvim_open_win = function(buffer, enter, opts)
				bufnr = buffer
				captured_width = opts.width
				for _, line in ipairs(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)) do
					longest = math.max(longest, vim.api.nvim_strwidth(line))
				end
				return saved_open_win(buffer, enter, opts)
			end
			local ok, err = pcall(help.show_help, context)
			vim.api.nvim_open_win = saved_open_win
			assert.is_true(ok)
			assert.is_nil(err)
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
			return captured_width, longest
		end

		local saved_columns

		before_each(function()
			saved_columns = vim.o.columns
		end)

		after_each(function()
			vim.o.columns = saved_columns
		end)

		it("sizes the float to the longest line when it fits the screen", function()
			vim.o.columns = 200
			local captured_width, longest = open_capturing("notes")
			assert.is_true(longest > 60, "expected long help lines for this scenario")
			assert.are.equal(longest, captured_width)
		end)

		it("clamps the float width so no line exceeds the screen", function()
			vim.o.columns = 20
			local captured_width, _ = open_capturing("notes")
			assert.are.equal(vim.o.columns - 2, captured_width)
		end)
	end)

	describe("help window close keymaps", function()
		local function close_lhs_set(context)
			local bufnr = nil
			local saved_open_win = vim.api.nvim_open_win
			vim.api.nvim_open_win = function(buffer, enter, opts)
				bufnr = buffer
				return saved_open_win(buffer, enter, opts)
			end
			local ok, err = pcall(help.show_help, context)
			vim.api.nvim_open_win = saved_open_win
			assert.is_true(ok)
			assert.is_nil(err)

			local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
			vim.api.nvim_buf_delete(bufnr, { force = true })
			return maps
		end

		local function assert_close_maps(maps)
			local close_count = 0
			local has_q = false
			for _, map in ipairs(maps) do
				if map.rhs and map.rhs:find("close_help", 1, true) then
					close_count = close_count + 1
					if map.lhs == "q" then
						has_q = true
					end
				end
			end
			assert.are.equal(2, close_count)
			assert.is_true(has_q)
		end

		it("notes context maps q and the note close key to close_help", function()
			assert_close_maps(close_lhs_set("notes"))
		end)

		it("templates context maps q and close_template", function()
			assert_close_maps(close_lhs_set("templates"))
		end)
	end)

	describe("show_help for decks", function()
		it("does not error", function()
			local _, err = get_help_lines("decks")
			assert.is_nil(err)
		end)

		it("returns help lines referencing deck mappings", function()
			local lines, err = get_help_lines("decks")
			assert.is_nil(err)
			assert.is_table(lines)
			assert.is_true(#lines > 0)

			local found = {}
			for _, line in ipairs(lines) do
				found[line] = true
			end
			local m = config.options.mappings.deck
			assert.is_true(found[m.show_help .. " - Show this help window"] ~= nil)
			assert.is_true(found[m.close .. " - Close the Anki UI tab"] ~= nil)
			assert.is_true(found[m.select_deck .. " - Select a deck and show its notes"] ~= nil)
		end)
	end)

	describe("show_help for notes", function()
		it("does not error", function()
			local _, err = get_help_lines("notes")
			assert.is_nil(err)
		end)

		it("returns help lines referencing note mappings", function()
			local lines, err = get_help_lines("notes")
			assert.is_nil(err)
			assert.is_table(lines)

			local found = {}
			for _, line in ipairs(lines) do
				found[line] = true
			end
			local m = config.options.mappings.note
			assert.is_true(found[m.show_help .. " - Show this help window"] ~= nil)
			assert.is_true(found[m.close .. " - Close the Anki UI tab"] ~= nil)
			assert.is_true(found[m.edit_note .. " - Edit note"] ~= nil)
			assert.is_true(found[m.search .. " - Search notes by query"] ~= nil)
			assert.is_true(found[m.toggle_view_mode .. " - Toggle between notes and cards view"] ~= nil)
			assert.is_true(found[m.move_note_to_deck .. " - Move note's cards to another deck"] ~= nil)
		end)

		it("mentions the distinction between notes and cards", function()
			local lines, err = get_help_lines("notes")
			assert.is_nil(err)
			local has_blurb = false
			for _, line in ipairs(lines) do
				if line:find("A note is the content") then
					has_blurb = true
					break
				end
			end
			assert.is_true(has_blurb)
		end)
	end)

	describe("show_help for editor", function()
		it("does not error", function()
			local _, err = get_help_lines("editor")
			assert.is_nil(err)
		end)

		it("returns help lines referencing editor mappings", function()
			local lines, err = get_help_lines("editor")
			assert.is_nil(err)
			assert.is_table(lines)

			local found = {}
			for _, line in ipairs(lines) do
				found[line] = true
			end
			local m = config.options.mappings.editor
			assert.is_true(found[m.show_help .. " - Show this help window"] ~= nil)
			assert.is_true(found[m.send_note .. " - Write/Send note to Anki"] ~= nil)
			assert.is_true(found[m.close .. " - Close the note editor"] ~= nil)
			assert.is_true(found[m.send_note .. " - Write/Send note to Anki"] ~= nil)
			assert.is_true(found[m.attach_media .. " - Attach media (image/audio/video) [field buffers only]"] ~= nil)
			assert.is_true(found[m.edit_in_anki .. " - Open this note in the Anki GUI edit dialog"] ~= nil)
			assert.is_true(
				found[m.push_note_to_add_dialog .. " - Push the editor content as a draft into the Anki Add dialog"]
					~= nil
			)
		end)

		it("does not reference a 'kill_note' mapping key for editor context", function()
			assert.is_nil(config.options.mappings.editor.kill_note)
		end)
	end)

	describe("show_help for templates", function()
		it("does not error", function()
			local _, err = get_help_lines("templates")
			assert.is_nil(err)
		end)

		it("returns help lines referencing template mappings", function()
			local lines, err = get_help_lines("templates")
			assert.is_nil(err)
			assert.is_table(lines)
			assert.is_true(#lines > 0)

			local found = {}
			for _, line in ipairs(lines) do
				found[line] = true
			end
			local m = config.options.mappings.template
			assert.is_true(found[m.save_template .. " - Save template changes to Anki"] ~= nil)
			assert.is_true(found[m.pull_template .. " - Pull latest template from Anki"] ~= nil)
			assert.is_true(found[m.switch_card .. " - Switch card (for multi-card models)"] ~= nil)
			assert.is_true(found[m.close_template .. " - Close the template editor"] ~= nil)
		end)
	end)

	describe("show_help for media_browser", function()
		it("does not error", function()
			local _, err = get_help_lines("media_browser")
			assert.is_nil(err)
		end)

		it("returns help lines referencing media browser keymaps", function()
			local lines, err = get_help_lines("media_browser")
			assert.is_nil(err)
			assert.is_table(lines)

			local found = {}
			for _, line in ipairs(lines) do
				found[line] = true
			end
			assert.is_true(found["g? - Show this help window"] ~= nil)
			assert.is_true(found["<Enter> - Insert selected media reference"] ~= nil)
			assert.is_true(found["<leader>k / <Esc> - Close the media browser"] ~= nil)
		end)
	end)

	describe("show_help with custom mappings", function()
		it("reflects overridden mapping keys in help text", function()
			config.setup({
				mappings = {
					deck = {
						show_help = "gh",
					},
				},
			})
			cleanup_help_buffers()
			local lines, err = get_help_lines("decks")
			assert.is_nil(err)
			local found = false
			for _, line in ipairs(lines) do
				if line:find("gh") and line:find("Show this help window") then
					found = true
				end
			end
			assert.is_true(found)
		end)
	end)

	describe("render_hint_line", function()
		it("returns a non-empty string for decks", function()
			local line = help.render_hint_line("decks")
			assert.is_string(line)
			assert.is_true(#line > 0)
			assert.is_true(line:find("Hint:") ~= nil)
		end)

		it("returns a non-empty string for notes", function()
			local line = help.render_hint_line("notes")
			assert.is_string(line)
			assert.is_true(#line > 0)
			assert.is_true(line:find("Hint:") ~= nil)
		end)

		it("reflects custom mappings in the hint line", function()
			config.setup({ mappings = { note = { search = "X" } } })
			local line = help.render_hint_line("notes")
			assert.is_true(line:find("X") ~= nil)
		end)

		it("includes the deck review key in the decks hint line", function()
			config.setup({})
			local line = help.render_hint_line("decks")
			assert.is_true(line:find(" review ") ~= nil)
		end)

		it("includes the deck stats key in the decks hint line", function()
			config.setup({})
			local line = help.render_hint_line("decks")
			assert.is_true(line:find(" stats ") ~= nil)
		end)

		it("includes undo/reveal/import labels in the notes hint line", function()
			config.setup({})
			local m = config.options.mappings.note
			local line = help.render_hint_line("notes")
			assert.is_true(line:find(" " .. m.select_note_in_anki_browser .. " reveal ") ~= nil)
			assert.is_true(line:find(" " .. m.sync_selection_from_anki_browser .. " import ") ~= nil)
			assert.is_true(line:find(" " .. m.undo .. " undo$") ~= nil)
		end)
	end)

	describe("render_hint_line alphabetical order", function()
		-- Extracts the label words from a hint line, in order.
		-- e.g. "Hint: a add | b close" -> { "add", "close" }
		local function extract_labels(line)
			local rest = line:gsub("^%w+: ", "")
			local labels = {}
			for segment in rest:gmatch("[^|]+") do
				segment = segment:gsub("^%s+", ""):gsub("%s+$", "")
				-- First token is the key, second is the label.
				local label = segment:match("^%S+%s+(%S+)")
				if label then
					table.insert(labels, label)
				end
			end
			return labels
		end

		it("lists deck actions in alphabetical order", function()
			config.setup({})
			local line = help.render_hint_line("decks")
			local labels = extract_labels(line)
			assert.is_true(#labels > 1)
			for i = 1, #labels - 1 do
				assert.is_true(
					string.lower(labels[i]) <= string.lower(labels[i + 1]),
					string.format("out of order: %q before %q", labels[i], labels[i + 1])
				)
			end
		end)

		it("lists note actions in alphabetical order", function()
			config.setup({})
			local line = help.render_hint_line("notes")
			local labels = extract_labels(line)
			assert.is_true(#labels > 1)
			for i = 1, #labels - 1 do
				assert.is_true(
					string.lower(labels[i]) <= string.lower(labels[i + 1]),
					string.format("out of order: %q before %q", labels[i], labels[i + 1])
				)
			end
		end)
	end)

	describe("close_help", function()
		it("does not error when no help buffer exists", function()
			assert.has_no.errors(function()
				help.close_help()
			end)
		end)
	end)

	describe("decks hint/help wording", function()
		it("uses 'add note' in the decks hint line", function()
			config.setup({})
			local line = help.render_hint_line("decks")
			assert.is_truthy(line:find("add note"))
		end)

		it("uses 'create deck' in the decks hint line", function()
			config.setup({})
			local line = help.render_hint_line("decks")
			assert.is_truthy(line:find("create deck"))
		end)

		it("documents cursor-on-deck behavior for add_note in the help window", function()
			config.setup({})
			cleanup_help_buffers()
			local lines, err = get_help_lines("decks")
			assert.is_nil(err)
			assert.is_table(lines)

			local found = false
			for _, line in ipairs(lines) do
				if line:find("creates on the deck under the cursor") then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)
	end)

	describe("close key defaults", function()
		it("uses '<leader>k' as the deck close key", function()
			config.setup({})
			assert.are.equal("<leader>k", config.options.mappings.deck.close)
		end)

		it("uses '<leader>k' as the note close key", function()
			config.setup({})
			assert.are.equal("<leader>k", config.options.mappings.note.close)
		end)

		it("uses '<leader>k' as the editor close key", function()
			config.setup({})
			assert.are.equal("<leader>k", config.options.mappings.editor.close)
		end)

		it("uses '<leader>k' as the template close_template key", function()
			config.setup({})
			assert.are.equal("<leader>k", config.options.mappings.template.close_template)
		end)
	end)
end)
