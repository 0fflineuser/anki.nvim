---
--- anki.media
---
--- Provides functions for uploading, referencing, and browsing media files
--- (images, audio, video) in Anki via AnkiConnect's media API.
--- All AnkiConnect calls are asynchronous using callbacks.
---
local ankiconnect = require("anki.ankiconnect")
local config = require("anki.config")
local notification = require("anki.notification")
local utils = require("anki.utils")

local M = {}

local IMAGE_EXTS = {
	png = true,
	jpg = true,
	jpeg = true,
	gif = true,
	bmp = true,
	svg = true,
	webp = true,
	avif = true,
	tiff = true,
	tif = true,
	ico = true,
}

local AUDIO_EXTS = {
	mp3 = true,
	wav = true,
	ogg = true,
	wma = true,
	flac = true,
	m4a = true,
	aac = true,
	opus = true,
}

local VIDEO_EXTS = {
	mp4 = true,
	mov = true,
	avi = true,
	mkv = true,
	webm = true,
	m4v = true,
	mpg = true,
	mpeg = true,
}

--- Detects the media type from a file extension.
---@param filename string The filename or path with extension.
---@return string|nil "image", "audio", or "video"
function M.detect_media_type(filename)
	local ext = filename:match("%.([%w]+)$")
	if not ext then
		return nil
	end
	ext = ext:lower()
	if IMAGE_EXTS[ext] then
		return "image"
	end
	if AUDIO_EXTS[ext] then
		return "audio"
	end
	if VIDEO_EXTS[ext] then
		return "video"
	end
	return nil
end

--- Generates the Anki reference string for a media filename.
---@param filename string The stored filename in Anki's media collection.
---@return string The reference string to insert into a field.
function M.media_reference(filename)
	local media_type = M.detect_media_type(filename)
	if media_type == "image" then
		return string.format('<img src="%s">', filename)
	elseif media_type == "audio" or media_type == "video" then
		return string.format("[sound:%s]", filename)
	else
		return string.format("[sound:%s]", filename)
	end
end

--- Extracts just the filename from a path.
---@param filepath string The full file path.
---@return string The filename component.
function M.basename(filepath)
	return filepath:match("([^/\\]+)$") or filepath
end

--- Uploads a local file to Anki's media collection using storeMediaFile asynchronously.
--- Uses the `path` parameter for local files on the same machine as Anki.
---@param filepath string Absolute path to the local file.
---@param filename string|nil Optional filename to store as (defaults to basename).
---@param on_result function Callback: on_result(stored_filename) or on_result(nil) on failure.
function M.upload_local_file(filepath, filename, on_result)
	filename = filename or M.basename(filepath)
	utils.async_safe_call(ankiconnect.store_media_file, { filename, { path = filepath } }, function(result, error)
		if result then
			notification.info(string.format("Uploaded media: %s", filename))
			if on_result then
				on_result(result)
			end
		else
			notification.error(string.format("Failed to upload media: %s", filepath))
			if on_result then
				on_result(nil)
			end
		end
	end)
end

--- Uploads a file from a URL to Anki's media collection using storeMediaFile asynchronously.
---@param url string The URL to download the file from.
---@param filename string The filename to store in Anki's media collection.
---@param on_result function Callback: on_result(stored_filename) or on_result(nil) on failure.
function M.upload_from_url(url, filename, on_result)
	utils.async_safe_call(ankiconnect.store_media_file, { filename, { url = url } }, function(result, error)
		if result then
			notification.info(string.format("Downloaded media: %s", filename))
			if on_result then
				on_result(result)
			end
		else
			notification.error(string.format("Failed to download media from URL: %s", url))
			if on_result then
				on_result(nil)
			end
		end
	end)
end

--- Uploads base64-encoded data to Anki's media collection using storeMediaFile asynchronously.
---@param filename string The filename to store in Anki's media collection.
---@param data string The base64-encoded file content.
---@param on_result function Callback: on_result(stored_filename) or on_result(nil) on failure.
function M.upload_from_data(filename, data, on_result)
	utils.async_safe_call(ankiconnect.store_media_file, { filename, { data = data } }, function(result, error)
		if result then
			notification.info(string.format("Uploaded media: %s", filename))
			if on_result then
				on_result(result)
			end
		else
			notification.error(string.format("Failed to upload media from data: %s", filename))
			if on_result then
				on_result(nil)
			end
		end
	end)
end

--- Reads a local file and returns its base64-encoded content.
---@param filepath string Path to the file.
---@return string|nil Base64-encoded content, or nil on error.
function M.read_file_as_base64(filepath)
	local handle = io.open(filepath, "rb")
	if not handle then
		notification.error(string.format("Cannot read file: %s", filepath))
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return vim.base64.encode(content)
end

--- Inserts text at the cursor position in the given buffer.
---@param bufnr number The buffer number.
---@param text string The text to insert.
function M.insert_at_cursor(bufnr, text)
	local winid = vim.fn.bufwinid(bufnr)
	if winid == -1 then
		notification.error("[anki.nvim][media] Buffer is not visible in any window")
		return
	end
	vim.api.nvim_win_set_cursor(winid, { vim.api.nvim_win_get_cursor(winid)[1], 0 })
	local line = vim.api.nvim_win_get_cursor(winid)[1]
	local col = vim.api.nvim_win_get_cursor(winid)[2]
	local current_line = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
	local before = current_line:sub(1, col)
	local after = current_line:sub(col + 1)
	vim.api.nvim_buf_set_lines(bufnr, line - 1, line, false, { before .. text .. after })
	vim.api.nvim_win_set_cursor(winid, { line, col + #text })
end

--- Prompts the user to select a media source and inserts the reference.
--- This is the main interactive entry point for the attach_media keymap.
---@param bufnr number The buffer number of the field where media will be inserted.
function M.attach_media(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][media] attach_media: bufnr must be a number")
	end

	vim.ui.select({ "Local file", "URL", "Clipboard image", "Browse Anki media" }, {
		prompt = "Attach media:",
	}, function(choice)
		if not choice then
			return
		end

		if choice == "Local file" then
			M._attach_local_file(bufnr)
		elseif choice == "URL" then
			M._attach_url(bufnr)
		elseif choice == "Clipboard image" then
			M._attach_clipboard(bufnr)
		elseif choice == "Browse Anki media" then
			M._attach_browse(bufnr)
		end
	end)
end

--- Handles attaching a local file by prompting for a path.
---@param bufnr number The buffer to insert the reference into.
function M._attach_local_file(bufnr)
	vim.ui.input({ prompt = "File path: ", completion = "file" }, function(filepath)
		if not filepath or filepath == "" then
			return
		end
		filepath = vim.fn.expand(filepath)
		if vim.fn.filereadable(filepath) ~= 1 then
			notification.error(string.format("File not found or not readable: %s", filepath))
			return
		end
		local filename = M.basename(filepath)
		M.upload_local_file(filepath, filename, function(result)
			if result then
				vim.schedule(function()
					M.insert_at_cursor(bufnr, M.media_reference(result))
				end)
			end
		end)
	end)
end

--- Handles attaching media from a URL by prompting for URL and filename.
---@param bufnr number The buffer to insert the reference into.
function M._attach_url(bufnr)
	vim.ui.input({ prompt = "URL: " }, function(url)
		if not url or url == "" then
			return
		end
		local default_filename = url:match("([^/]+)$") or "download"
		vim.ui.input({ prompt = "Filename to store as: ", default = default_filename }, function(filename)
			if not filename or filename == "" then
				return
			end
			M.upload_from_url(url, filename, function(result)
				if result then
					vim.schedule(function()
						M.insert_at_cursor(bufnr, M.media_reference(result))
					end)
				end
			end)
		end)
	end)
end

--- Handles attaching an image from the system clipboard.
---@param bufnr number The buffer to insert the reference into.
function M._attach_clipboard(bufnr)
	local has_wayland = vim.env.WAYLAND_DISPLAY ~= nil
	local has_xclip = vim.fn.executable("xclip") == 1
	local has_xsel = vim.fn.executable("xsel") == 1
	local has_powersetclipboard = vim.fn.executable("powershell.exe") == 1 or vim.fn.executable("pwsh") == 1
	local has_pngpaste = vim.fn.executable("pngpaste") == 1
	local has_pbcopy = vim.fn.executable("pbpaste") == 1

	local tmp_file = vim.fn.tempname()
	local success = false

	if has_pngpaste then
		vim.fn.system((string.format("pngpaste %s 2>/dev/null", vim.fn.shellescape(tmp_file))))
		success = vim.v.shell_error == 0
	elseif has_wayland and vim.fn.executable("wl-paste") == 1 then
		vim.fn.system(string.format("wl-paste --type image/png > %s 2>/dev/null", vim.fn.shellescape(tmp_file)))
		success = vim.v.shell_error == 0
	elseif has_xclip then
		vim.fn.system(
			string.format("xclip -selection clipboard -t image/png -o > %s 2>/dev/null", vim.fn.shellescape(tmp_file))
		)
		success = vim.v.shell_error == 0
	elseif has_xsel then
		vim.fn.system(string.format("xsel --clipboard --input -o > %s 2>/dev/null", vim.fn.shellescape(tmp_file)))
		success = vim.v.shell_error == 0
	elseif has_pbcopy then
		vim.fn.system(string.format("pbpaste > %s 2>/dev/null", vim.fn.shellescape(tmp_file)))
		success = vim.v.shell_error == 0
	elseif has_powersetclipboard then
		tmp_file = tmp_file .. ".png"
		local escaped_path = tmp_file:gsub("\\", "\\\\"):gsub("'", "''")
		vim.fn.system(
			string.format(
				"powershell.exe -NoProfile -Command \"Get-Clipboard -Format Image | ForEach-Object { $_.Save('%s') }\" 2>/dev/null",
				escaped_path
			)
		)
		success = vim.v.shell_error == 0
	end

	if not success then
		notification.error(
			"[anki.nvim][media] Failed to read image from clipboard. Is a supported clipboard tool installed?"
		)
		os.remove(tmp_file)
		return
	end

	local filesize = vim.fn.getfsize(tmp_file)
	if filesize <= 0 then
		notification.error("[anki.nvim][media] No image data found in clipboard")
		os.remove(tmp_file)
		return
	end

	local filename = "clipboard_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
	local data = M.read_file_as_base64(tmp_file)
	os.remove(tmp_file)

	if not data then
		notification.error("[anki.nvim][media] Failed to read clipboard image file")
		return
	end

	M.upload_from_data(filename, data, function(result)
		if result then
			vim.schedule(function()
				M.insert_at_cursor(bufnr, M.media_reference(result))
			end)
		end
	end)
end

--- Handles browsing and inserting existing media from Anki's collection.
--- Uses the floating media browser with image preview when available,
--- falls back to vim.ui.select otherwise.
---@param bufnr number The buffer to insert the reference into.
function M._attach_browse(bufnr)
	utils.async_safe_call(ankiconnect.get_media_files_names, { "*" }, function(media_files, error)
		if error or not media_files then
			notification.error("[anki.nvim][media] Failed to list Anki media files")
			return
		end
		if type(media_files) ~= "table" or #media_files == 0 then
			notification.info("[anki.nvim][media] No media files found in Anki collection")
			return
		end

		if config.options.media_browser_preview then
			local media_browser = require("anki.ui.media_browser")
			vim.schedule(function()
				media_browser.open(bufnr, media_files)
			end)
		else
			table.sort(media_files)
			vim.ui.select(media_files, {
				prompt = "Select media file:",
			}, function(filename)
				if not filename then
					return
				end
				vim.schedule(function()
					M.insert_at_cursor(bufnr, M.media_reference(filename))
				end)
			end)
		end
	end)
end

return M
