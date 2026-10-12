---
--- anki.api
---
--- Provides functions to send, pull, and delete notes in Anki via AnkiConnect.
--- All AnkiConnect calls are asynchronous using callbacks to avoid blocking Neovim's UI.
---
local config = require("anki.config")
local ankiconnect = require("anki.ankiconnect")
local anki_state = require("anki.state")
local notification = require("anki.notification")
local utils = require("anki.utils")
local editor = require("anki.editor")
local operations = require("anki.ui.operations")
local sticky = require("anki.sticky")

local M = {}

--- Checks if a note with the given ID exists in Anki.
-- @param note_id any The note ID to check.
-- @param on_result function Callback: on_result(exists)
local function validate_note_exists(note_id, on_result)
	if not note_id then
		on_result(false)
		return
	end
	local query = string.format("nid:%s", note_id)
	utils.async_safe_call(ankiconnect.find_notes, { query }, function(result, error)
		if error or not result then
			on_result(false)
			return
		end
		on_result(#result > 0)
	end)
end

--- Checks if a note can be added to Anki with the given parameters.
-- @param deck_name string The deck name.
-- @param model_name string The model name.
-- @param fields table The note fields.
-- @param tags table The note tags.
-- @param on_result function Callback: on_result(can_add)
local function can_add_note(deck_name, model_name, fields, tags, on_result)
	utils.async_safe_call(
		ankiconnect.can_add_notes_with_error_details,
		{ deck_name, model_name, fields, tags },
		function(result, error)
			if error or not result then
				on_result(false)
				return
			end
			on_result(result[1] and result[1].canAdd)
		end
	)
end

--- Handles opening the Anki GUI browser for a note, optionally updating it.
-- @param note table The note object.
-- @param is_new boolean Whether the note is new.
-- @param fields table The note fields.
-- @param tags table The note tags.
-- @param on_done function Callback called when done (no arguments).
local function handle_gui_browse(note, is_new, fields, tags, on_done)
	if not config.options.gui_browse_enabled then
		if on_done then
			on_done()
		end
		return
	end

	if is_new then
		local query = string.format('"deck:%s" nid:%s', utils.escape_search_query(note.deck_name), note.id)
		utils.async_safe_call(ankiconnect.gui_browse, { query }, function(_, _)
			if on_done then
				on_done()
			end
		end)
	else
		utils.async_safe_call(ankiconnect.gui_browse, { "nid:1" }, function(_, _)
			utils.async_safe_call(ankiconnect.update_note, { note.id, fields, tags }, function(_, _)
				local query2 = string.format('"deck:%s" nid:%s', utils.escape_search_query(note.deck_name), note.id)
				utils.async_safe_call(ankiconnect.gui_browse, { query2 }, function(_, _)
					if on_done then
						on_done()
					end
				end)
			end)
		end)
	end
end

--- Notifies the user whether a note was added or updated.
-- @param is_new boolean True if the note was added, false if updated.
local function notify_user(is_new)
	notification.info(is_new and "Note added" or "Note updated")
end

local function upload_media_entry(filename, entry, on_done)
	if entry.path then
		utils.async_safe_call(ankiconnect.store_media_file, { filename, { path = entry.path } }, function(_, _)
			if on_done then
				on_done()
			end
		end)
	elseif entry.url then
		utils.async_safe_call(ankiconnect.store_media_file, { filename, { url = entry.url } }, function(_, _)
			if on_done then
				on_done()
			end
		end)
	elseif entry.data then
		utils.async_safe_call(ankiconnect.store_media_file, { filename, { data = entry.data } }, function(_, _)
			if on_done then
				on_done()
			end
		end)
	else
		if on_done then
			on_done()
		end
	end
end

--- Uploads all pending media attachments for a note via storeMediaFile.
--- Calls on_done when all uploads are complete.
-- @param note table The note object with media attachments.
-- @param on_done function Callback called when all media uploads are complete.
local function upload_note_media(note, on_done)
	if not note.media then
		if on_done then
			on_done()
		end
		return
	end

	local uploads = {}
	for _, media_type in ipairs({ "picture", "audio", "video" }) do
		for _, entry in ipairs(note.media[media_type] or {}) do
			table.insert(uploads, { filename = entry.filename, entry = entry })
		end
	end

	if #uploads == 0 then
		if on_done then
			on_done()
		end
		return
	end

	local completed = 0
	for _, upload in ipairs(uploads) do
		upload_media_entry(upload.filename, upload.entry, function()
			completed = completed + 1
			if completed == #uploads and on_done then
				on_done()
			end
		end)
	end
end

--- Sends the current note to Anki, adding or updating as needed.
-- @param bufnr number The buffer number of the note.
-- @param kill boolean|nil Whether to kill the note buffer after sending.
-- @param new_note_after_send boolean|nil When true, resets the editor into a fresh
--   note after a successful send instead of closing it: note.id is nil-ed, non-sticky
--   field buffers are cleared (sticky fields kept, tags kept) and media attachments
--   are reset. Mutually exclusive with `kill` (kill wins if both set).
M.send_note = function(bufnr, kill, new_note_after_send)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][api] send_note: bufnr must be a number")
	end
	if kill ~= nil and type(kill) ~= "boolean" then
		error("[anki.nvim][api] send_note: kill must be a boolean or nil")
	end
	if new_note_after_send ~= nil and type(new_note_after_send) ~= "boolean" then
		error("[anki.nvim][api] send_note: new_note_after_send must be a boolean or nil")
	end
	local note_to_send = editor.find_note_by_bufnr(bufnr)
	if not note_to_send then
		notification.warn("[anki.nvim][api] No Anki note buffer found")
		return
	end

	local content = note_to_send:get_content_from_buffers()
	local fields = content.fields
	local tags = content.tags
	local is_new_note = note_to_send.id == nil

	local function cleanup_and_notify()
		if kill then
			editor.delete_note_buffers(note_to_send)
		elseif new_note_after_send then
			M._reset_for_new_note(note_to_send)
		end
		notify_user(is_new_note)
		operations.refresh_all()
	end

	local function send_new_note(can_add)
		if not can_add then
			notification.error("[anki.nvim][api] The note already exists but its ID is unknown by anki.nvim")
			return
		end

		local on_add_result = function(result_note_id, error)
			if error or not result_note_id then
				notification.error("[anki.nvim][api] Failed to add note to Anki (no note ID returned)")
				return
			end

			note_to_send.id = result_note_id
			handle_gui_browse(note_to_send, true, fields, tags, function()
				cleanup_and_notify()
			end)
		end

		utils.async_safe_call(
			ankiconnect.add_note,
			{ note_to_send.deck_name, note_to_send.model_name, fields, tags, note_to_send.media },
			on_add_result
		)
	end

	local function send_existing_note()
		upload_note_media(note_to_send, function()
			handle_gui_browse(note_to_send, false, fields, tags, function()
				utils.async_safe_call(
					ankiconnect.update_note,
					{ note_to_send.id, fields, tags },
					function(result, error)
						if error or not result then
							notification.error("[anki.nvim][api] Failed to update note")
							return
						end
						cleanup_and_notify()
					end
				)
			end)
		end)
	end

	local function process_send()
		can_add_note(note_to_send.deck_name, note_to_send.model_name, fields, tags, function(can_add)
			if is_new_note then
				send_new_note(can_add)
			else
				send_existing_note()
			end
		end)
	end

	local function do_send()
		if note_to_send.id then
			validate_note_exists(note_to_send.id, function(exists)
				if not exists then
					note_to_send.id = nil
					is_new_note = true
				end
				process_send()
			end)
		else
			process_send()
		end
	end

	do_send()
end

--- Resets a just-sent note's editor state so the next send creates a new note,
--- mirroring Anki's add-note dialog reset: note.id is nil-ed, media attachments
--- are cleared, tags are kept, and non-sticky field buffers are emptied while
--- sticky fields keep their content (see anki.sticky). Safe to call outside a
--- scheduled context: buffer writes are wrapped in vim.schedule.
-- @param note Note The note object to reset.
M._reset_for_new_note = function(note)
	if type(note) ~= "table" then
		error("[anki.nvim][api] _reset_for_new_note: note must be a table")
	end

	vim.schedule(function()
		for _, field in ipairs(note.fields) do
			local bufnr = field.editor_context.bufnr
			if sticky.is_sticky(note.model_name, field.name) then
				-- Sticky: keep the field's content.
			else
				vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
			end
		end
		notification.info("[anki.nvim][api] Ready for next note (sticky fields kept)")
	end)

	-- Media already uploaded during the send must not re-attach to the next note.
	note.media = { picture = {}, audio = {}, video = {} }
	note.id = nil
end

--- Pulls the latest content for the current note from Anki into the buffers.
-- @param bufnr number The buffer number of the note.
M.pull_note = function(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][api] pull_note: bufnr must be a number")
	end
	local note_to_pull = editor.find_note_by_bufnr(bufnr)
	if not note_to_pull then
		notification.warn("[anki.nvim][api] No Anki note buffer found")
		return
	end

	if not note_to_pull.id then
		notification.error("[anki.nvim][api] Cannot pull note, it was not sent to Anki yet")
		return
	end

	utils.async_safe_call(ankiconnect.notes_info, { { note_to_pull.id } }, function(notes_data, error)
		if error or not notes_data then
			notification.error("[anki.nvim][api] Failed to fetch note info from Anki")
			return
		end
		local first_note = notes_data[1]
		if not first_note then
			notification.error("[anki.nvim][api] Note not found in Anki")
			return
		end

		vim.schedule(function()
			vim.api.nvim_buf_set_lines(note_to_pull.tags.bufnr, 0, -1, false, first_note.tags)

			for key, field in pairs(first_note.fields) do
				local field_found_in_note = note_to_pull:find_field_by_name(key)
				if field_found_in_note then
					vim.api.nvim_buf_set_lines(
						note_to_pull.fields[field_found_in_note].editor_context.bufnr,
						0,
						-1,
						false,
						utils.split(field.value, "\n")
					)
				end
			end
			notification.info("[anki.nvim][api] Note pulled from Anki")
		end)
	end)
end

--- Deletes the current note from Anki and updates the UI.
-- @param bufnr number The buffer number of the note.
M.delete_note = function(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][api] delete_note: bufnr must be a number")
	end
	local note_to_delete = editor.find_note_by_bufnr(bufnr)
	if not note_to_delete then
		notification.warn("[anki.nvim][api] No Anki note buffer found")
		return
	end

	if note_to_delete.id == nil then
		notification.warn("[anki.nvim][api] Cannot delete note, it was not sent to Anki yet")
		return
	end

	utils.async_safe_call(ankiconnect.delete_notes, { { note_to_delete.id } }, function(result, error)
		if error or result == nil then
			notification.error("[anki.nvim][api] Failed to delete note from Anki")
			return
		end
		note_to_delete.id = nil
		notification.info("[anki.nvim][api] Note deleted")

		if config.options.gui_browse_enabled then
			local query = string.format('"deck:%s"', utils.escape_search_query(note_to_delete.deck_name))
			utils.async_safe_call(ankiconnect.gui_browse, { query }, function(_, _)
				operations.refresh_all()
			end)
		else
			operations.refresh_all()
		end
	end)
end

--- Pushes the content of the note editor owning the given buffer to the Anki
--- GUI Add dialog as a new draft. Does not send the note; Anki keeps the draft
--- in its Add dialog (returning 0 for the unsaved draft is passed through).
---@param bufnr number A buffer belonging to the note editor (tags or field buffer).
M.push_note_to_add_dialog = function(bufnr)
	if type(bufnr) ~= "number" then
		error("[anki.nvim][api] push_note_to_add_dialog: bufnr must be a number")
	end
	local note = editor.find_note_by_bufnr(bufnr)
	if not note then
		notification.warn("[anki.nvim][api] No Anki note buffer found")
		return
	end

	local content = note:get_content_from_buffers()
	local note_payload = {
		deckName = note.deck_name,
		modelName = note.model_name,
		fields = content.fields,
		tags = content.tags,
	}

	utils.async_safe_call(ankiconnect.gui_add_cards, { note_payload }, function(result, error)
		if error then
			notification.error("[anki.nvim][api] Failed to open the Anki Add dialog")
			return
		end
		notification.info("[anki.nvim][api] Note draft pushed to the Anki Add dialog")
	end)
end

return M
