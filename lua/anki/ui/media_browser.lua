---
--- anki.ui.media_browser
---
--- Media browser UI for browsing and inserting Anki collection media files.
--- Displays a two-pane floating window with a file list and an image preview panel.
--- Image preview uses snacks.nvim when available; falls back to metadata display.
---
local ankiconnect = require("anki.ankiconnect")
local config = require("anki.config")
local media = require("anki.media")
local notification = require("anki.notification")
local utils = require("anki.utils")

local M = {}

local state = {
	list_buf = nil,
	preview_buf = nil,
	list_win = nil,
	preview_win = nil,
	media_files = {},
	target_bufnr = nil,
	cached_files = {},
	temp_dir = nil,
	preview_generation = 0,
	debounce_timer = nil,
	last_preview_filename = nil,
	preview_config = {
		total_width = 0,
		total_height = 0,
		preview_width = 0,
		start_row = 0,
		start_col = 0,
		list_width = 0,
		border = "single",
		list_title = " Media ",
		preview_title = " Preview ",
		list_win_opts = {},
		preview_win_opts = {},
	},
}

local function get_temp_dir()
	if not state.temp_dir then
		state.temp_dir = vim.fn.stdpath("cache") .. "/anki.nvim/media"
		vim.fn.mkdir(state.temp_dir, "p")
	end
	return state.temp_dir
end

local function check_snacks()
	local ok, mod = pcall(require, "snacks.image")
	if ok and mod and mod.supports and mod.supports_terminal() then
		return true
	end
	return false
end

local function cleanup_temp_files()
	if state.temp_dir then
		local files = vim.fn.readdir(state.temp_dir)
		for _, f in ipairs(files) do
			os.remove(state.temp_dir .. "/" .. f)
		end
	end
end

local function stop_debounce_timer()
	if state.debounce_timer then
		state.debounce_timer:stop()
		state.debounce_timer:close()
		state.debounce_timer = nil
	end
end

local function get_media_icon(filename)
	local media_type = media.detect_media_type(filename)
	if media_type == "image" then
		return "󰋩"
	elseif media_type == "audio" then
		return "󰎆"
	elseif media_type == "video" then
		return "󰎄"
	else
		return "󰈙"
	end
end

local function format_list_lines(filenames)
	local lines = {}
	for _, f in ipairs(filenames) do
		table.insert(lines, get_media_icon(f) .. " " .. f)
	end
	return lines
end

local function get_filename_from_line(line)
	local space_pos = line:find(" ")
	if space_pos then
		return line:sub(space_pos + 1)
	end
	return line
end

local function apply_win_opts(win, opts)
	for opt, val in pairs(opts) do
		vim.api.nvim_set_option_value(opt, val, { win = win })
	end
end

local function recreate_preview_buf()
	if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
		vim.api.nvim_win_close(state.preview_win, true)
	end
	if state.preview_buf and vim.api.nvim_buf_is_valid(state.preview_buf) then
		vim.api.nvim_buf_delete(state.preview_buf, { force = true })
	end

	state.preview_buf = nil
	state.preview_win = nil

	local cfg = state.preview_config

	state.preview_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.preview_buf, "Anki Media Preview")
	vim.bo[state.preview_buf].buftype = "nofile"

	state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, {
		relative = "editor",
		width = cfg.preview_width,
		height = cfg.total_height,
		row = cfg.start_row,
		col = cfg.start_col + cfg.list_width + cfg.pane_gap,
		style = "minimal",
		border = cfg.border,
		title = cfg.preview_title,
		title_pos = "center",
	})

	apply_win_opts(state.preview_win, cfg.preview_win_opts)
end

local function show_preview_metadata(filename)
	recreate_preview_buf()

	local media_type = media.detect_media_type(filename) or "unknown"
	local ext = filename:match("%.([%w]+)$") or ""

	local lines = {
		"  Media Preview",
		"",
		"  File:   " .. filename,
		"  Type:   " .. media_type,
		"  Exten:  " .. ext,
	}

	if media_type ~= "image" then
		table.insert(lines, "")
		if media_type == "audio" then
			table.insert(lines, "  Audio file - cannot be previewed")
			table.insert(lines, "  Press <Enter> to insert [sound:reference]")
		elseif media_type == "video" then
			table.insert(lines, "  Video file - cannot be previewed")
			table.insert(lines, "  Press <Enter> to insert [sound:reference]")
		else
			table.insert(lines, "  Unknown media type")
			table.insert(lines, "  Press <Enter> to insert reference")
		end
	end

	vim.bo[state.preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)
	vim.bo[state.preview_buf].modifiable = false
	vim.bo[state.preview_buf].filetype = "anki_media_preview"
end

local function show_loading_placeholder()
	recreate_preview_buf()

	vim.bo[state.preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, {
		"  Loading preview...",
	})
	vim.bo[state.preview_buf].modifiable = false
	vim.bo[state.preview_buf].filetype = "anki_media_preview"
end

local function render_image(filepath)
	if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
		return
	end

	recreate_preview_buf()

	vim.bo[state.preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "" })
	vim.bo[state.preview_buf].modifiable = false
	vim.bo[state.preview_buf].filetype = "image"

	local buf = state.preview_buf
	local win = state.preview_win

	vim.schedule(function()
		if not buf or not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		if not win or not vim.api.nvim_win_is_valid(win) then
			return
		end
		local ok, img_mod = pcall(require, "snacks.image")
		if ok and img_mod and img_mod.buf and img_mod.buf.attach then
			img_mod.buf.attach(buf, { src = filepath })
		end
	end)
end

local function show_image_preview(filename, generation)
	if not check_snacks() then
		show_preview_metadata(filename)
		return
	end

	if state.cached_files[filename] then
		render_image(state.cached_files[filename])
		return
	end

	show_loading_placeholder()

	utils.async_safe_call(ankiconnect.retrieve_media_file, { filename }, function(data, err)
		if generation ~= state.preview_generation then
			return
		end

		if err or not data then
			vim.schedule(function()
				if generation ~= state.preview_generation then
					return
				end
				if not state.preview_buf or not vim.api.nvim_buf_is_valid(state.preview_buf) then
					return
				end

				recreate_preview_buf()

				vim.bo[state.preview_buf].modifiable = true
				vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, {
					"  Failed to load preview",
					"  " .. filename,
					"  " .. tostring(err or "unknown error"),
				})
				vim.bo[state.preview_buf].modifiable = false
			end)
			return
		end

		vim.schedule(function()
			if generation ~= state.preview_generation then
				return
			end

			local tmp_path = get_temp_dir() .. "/" .. filename
			local handle = io.open(tmp_path, "wb")
			if handle then
				local decoded = vim.base64.decode(data)
				handle:write(decoded)
				handle:close()
				state.cached_files[filename] = tmp_path
				render_image(tmp_path)
			else
				if not state.preview_buf or not vim.api.nvim_buf_is_valid(state.preview_buf) then
					return
				end

				recreate_preview_buf()

				vim.bo[state.preview_buf].modifiable = true
				vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, {
					"  Failed to write temp file for preview",
					"  " .. filename,
				})
				vim.bo[state.preview_buf].modifiable = false
			end
		end)
	end)
end

local function update_preview()
	if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
		return
	end
	if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(state.list_win)
	local line_idx = cursor[1]
	local line = vim.api.nvim_buf_get_lines(state.list_buf, line_idx - 1, line_idx, false)[1]

	if not line or line == "" then
		recreate_preview_buf()
		vim.bo[state.preview_buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "  No file selected" })
		vim.bo[state.preview_buf].modifiable = false
		state.last_preview_filename = nil
		return
	end

	local filename = get_filename_from_line(line)

	if filename == state.last_preview_filename then
		return
	end
	state.last_preview_filename = filename

	local media_type = media.detect_media_type(filename)

	state.preview_generation = state.preview_generation + 1
	local generation = state.preview_generation

	if media_type == "image" then
		show_image_preview(filename, generation)
	else
		show_preview_metadata(filename)
	end
end

local function select_and_insert()
	if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
		return
	end
	if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(state.list_win)
	local line_idx = cursor[1]
	local line = vim.api.nvim_buf_get_lines(state.list_buf, line_idx - 1, line_idx, false)[1]

	if not line or line == "" then
		notification.warn("[anki.nvim][media_browser] No file selected")
		return
	end

	local filename = get_filename_from_line(line)
	local bufnr = state.target_bufnr
	M.close()

	vim.schedule(function()
		media.insert_at_cursor(bufnr, media.media_reference(filename))
	end)
end

local function setup_keymaps()
	local function set_key(buf, mode, lhs, rhs)
		vim.api.nvim_buf_set_keymap(buf, mode, lhs, rhs, { noremap = true, silent = true })
	end

	set_key(state.list_buf, "n", "<CR>", "<Cmd>lua require('anki.ui.media_browser').select_and_insert()<CR>")
	set_key(state.list_buf, "n", "<leader>k", "<Cmd>lua require('anki.ui.media_browser').close()<CR>")
	set_key(state.list_buf, "n", "<Esc>", "<Cmd>lua require('anki.ui.media_browser').close()<CR>")
	set_key(state.list_buf, "n", "g?", "<Cmd>lua require('anki.ui.help').show_help('media_browser')<CR>")
end

function M.select_and_insert()
	select_and_insert()
end

---@param bufnr number Target buffer number to insert media reference into.
---@param media_files table List of media filename strings from the Anki collection.
function M.open(bufnr, media_files)
	if not media_files or #media_files == 0 then
		notification.info("[anki.nvim][media_browser] No media files found in Anki collection")
		return
	end

	M.close()

	table.sort(media_files)

	state.media_files = media_files
	state.target_bufnr = bufnr
	state.cached_files = {}
	state.preview_generation = 0
	state.last_preview_filename = nil

	local mb = config.options.media_browser
	local total_width = math.floor(vim.o.columns * mb.width)
	local total_height = math.floor(vim.o.lines * mb.height)
	local list_width = math.floor(total_width * mb.list_width)
	local preview_width = total_width - list_width - mb.pane_gap

	local start_col = math.floor((vim.o.columns - total_width) / 2)
	local start_row = math.floor((vim.o.lines - total_height) / 2)

	state.preview_config = {
		total_width = total_width,
		total_height = total_height,
		preview_width = preview_width,
		start_row = start_row,
		start_col = start_col,
		list_width = list_width,
		pane_gap = mb.pane_gap,
		border = mb.border,
		list_title = mb.list_title,
		preview_title = mb.preview_title,
		list_win_opts = mb.list_win_opts,
		preview_win_opts = mb.preview_win_opts,
	}

	state.list_buf = vim.api.nvim_create_buf(false, true)
	state.preview_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_name(state.list_buf, "Anki Media List")
	vim.api.nvim_buf_set_name(state.preview_buf, "Anki Media Preview")

	local lines = format_list_lines(media_files)
	vim.bo[state.list_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
	vim.bo[state.list_buf].modifiable = false
	vim.bo[state.list_buf].filetype = "anki_media_list"
	vim.bo[state.list_buf].buftype = "nofile"

	vim.bo[state.preview_buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, { "  Select a file to preview" })
	vim.bo[state.preview_buf].modifiable = false
	vim.bo[state.preview_buf].buftype = "nofile"

	state.list_win = vim.api.nvim_open_win(state.list_buf, true, {
		relative = "editor",
		width = list_width,
		height = total_height,
		row = start_row,
		col = start_col,
		style = "minimal",
		border = mb.border,
		title = mb.list_title,
		title_pos = "center",
	})

	state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, {
		relative = "editor",
		width = preview_width,
		height = total_height,
		row = start_row,
		col = start_col + list_width + mb.pane_gap,
		style = "minimal",
		border = mb.border,
		title = mb.preview_title,
		title_pos = "center",
	})

	apply_win_opts(state.list_win, mb.list_win_opts)
	apply_win_opts(state.preview_win, mb.preview_win_opts)

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = state.list_buf,
		callback = function()
			stop_debounce_timer()
			state.debounce_timer = vim.uv.new_timer()
			state.debounce_timer:start(
				50,
				0,
				vim.schedule_wrap(function()
					update_preview()
					if state.debounce_timer then
						state.debounce_timer:close()
						state.debounce_timer = nil
					end
				end)
			)
		end,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = state.list_buf,
		once = true,
		callback = function()
			vim.schedule(function()
				if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
					return
				end
				M.close()
			end)
		end,
	})

	setup_keymaps()
	vim.schedule(update_preview)
end

--- Closes the media browser, cleaning up windows, buffers, and temp files.
function M.close()
	stop_debounce_timer()

	for _, win in ipairs({ state.list_win, state.preview_win }) do
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	for _, buf in ipairs({ state.list_buf, state.preview_buf }) do
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end

	state.list_buf = nil
	state.preview_buf = nil
	state.list_win = nil
	state.preview_win = nil
	state.media_files = {}
	state.target_bufnr = nil
	state.cached_files = {}
	state.preview_generation = 0
	state.last_preview_filename = nil
	state.preview_config = {}

	cleanup_temp_files()
end

return M
