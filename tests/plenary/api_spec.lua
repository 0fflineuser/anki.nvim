local api = require("anki.api")
local Note = require("anki.classes.note")
local Field = require("anki.classes.field")
local EditorContext = require("anki.classes.editor_context")
local anki_state = require("anki.state")
local editor = require("anki.editor")
local ankiconnect = require("anki.ankiconnect")
local operations = require("anki.ui.operations")
local notification = require("anki.notification")
local spy = require("luassert.spy")

local function make_note_with_real_bufs()
	local field_bufnr = vim.api.nvim_create_buf(false, true)
	local tags_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(field_bufnr, 0, -1, false, { "hello" })
	vim.api.nvim_buf_set_lines(tags_bufnr, 0, -1, false, { "tag1" })

	local note = Note:new({
		deck_name = "TestDeck",
		model_name = "Basic",
		fields = {
			Field:new({
				editor_context = EditorContext:new({
					bufnr = field_bufnr,
					winid = 1000,
					tabid = 1001,
				}),
				name = "Front",
			}),
		},
		tags = EditorContext:new({
			bufnr = tags_bufnr,
			winid = 1002,
			tabid = 1003,
		}),
	})
	return note, field_bufnr, tags_bufnr
end

local function mock_ankiconnect_fn(fn_name, callback_fn)
	local original = ankiconnect[fn_name]
	ankiconnect[fn_name] = callback_fn
	return original
end

local function restore_ankiconnect_fn(fn_name, original)
	ankiconnect[fn_name] = original
end

describe("anki.api", function()
	describe("send_note", function()
		it("calls process_send without error when note has no id (new note path)", function()
			local note, field_bufnr, tags_bufnr = make_note_with_real_bufs()
			local tabid = 9999
			anki_state.current_notes[tabid] = note
			note.tabid = tabid

			local original_find = editor.find_note_by_bufnr
			editor.find_note_by_bufnr = function()
				return note
			end

			local original_can_add = mock_ankiconnect_fn(
				"can_add_notes_with_error_details",
				function(deckName, modelName, fields, tags, on_result)
					on_result({ { canAdd = true } }, nil)
				end
			)

			local received_media = nil
			local received_on_result_type = nil
			local original_add_note = mock_ankiconnect_fn(
				"add_note",
				function(deckName, modelName, fields, tags, media, on_result)
					received_media = media
					received_on_result_type = type(on_result)
					on_result(12345, nil)
				end
			)

			local original_gui_browse = mock_ankiconnect_fn("gui_browse", function(query, on_result)
				on_result(nil, nil)
			end)

			local original_refresh = operations.refresh_all
			operations.refresh_all = function() end

			local original_delete_note_buffers = editor.delete_note_buffers
			editor.delete_note_buffers = function() end

			assert.has_no.errors(function()
				api.send_note(field_bufnr, false)
			end)

			vim.wait(100, function()
				return false
			end)

			assert.are.equal("table", type(received_media))
			assert.are.equal("function", received_on_result_type)

			editor.find_note_by_bufnr = original_find
			restore_ankiconnect_fn("can_add_notes_with_error_details", original_can_add)
			restore_ankiconnect_fn("add_note", original_add_note)
			restore_ankiconnect_fn("gui_browse", original_gui_browse)
			operations.refresh_all = original_refresh
			editor.delete_note_buffers = original_delete_note_buffers
			anki_state.current_notes[tabid] = nil

			pcall(vim.api.nvim_buf_delete, field_bufnr, { force = true })
			pcall(vim.api.nvim_buf_delete, tags_bufnr, { force = true })
		end)

		it("calls process_send without error when note has an id that exists", function()
			local note, field_bufnr, tags_bufnr = make_note_with_real_bufs()
			note.id = 999
			local tabid = 9998
			anki_state.current_notes[tabid] = note
			note.tabid = tabid

			local original_find = editor.find_note_by_bufnr
			editor.find_note_by_bufnr = function()
				return note
			end

			local original_find_notes = mock_ankiconnect_fn("find_notes", function(query, on_result)
				on_result({ 999 }, nil)
			end)

			local original_can_add = mock_ankiconnect_fn(
				"can_add_notes_with_error_details",
				function(deckName, modelName, fields, tags, on_result)
					on_result({ { canAdd = true } }, nil)
				end
			)

			local original_update_note = mock_ankiconnect_fn("update_note", function(id, fields, tags, on_result)
				on_result(nil, nil)
			end)

			local original_gui_browse = mock_ankiconnect_fn("gui_browse", function(query, on_result)
				on_result(nil, nil)
			end)

			local original_refresh = operations.refresh_all
			operations.refresh_all = function() end

			local original_delete_note_buffers = editor.delete_note_buffers
			editor.delete_note_buffers = function() end

			assert.has_no.errors(function()
				api.send_note(field_bufnr, false)
			end)

			vim.wait(200, function()
				return false
			end)

			editor.find_note_by_bufnr = original_find
			restore_ankiconnect_fn("find_notes", original_find_notes)
			restore_ankiconnect_fn("can_add_notes_with_error_details", original_can_add)
			restore_ankiconnect_fn("update_note", original_update_note)
			restore_ankiconnect_fn("gui_browse", original_gui_browse)
			operations.refresh_all = original_refresh
			editor.delete_note_buffers = original_delete_note_buffers
			anki_state.current_notes[tabid] = nil

			pcall(vim.api.nvim_buf_delete, field_bufnr, { force = true })
			pcall(vim.api.nvim_buf_delete, tags_bufnr, { force = true })
		end)

		it("calls process_send without error when note id no longer exists in Anki", function()
			local note, field_bufnr, tags_bufnr = make_note_with_real_bufs()
			note.id = 999
			local tabid = 9997
			anki_state.current_notes[tabid] = note
			note.tabid = tabid

			local original_find = editor.find_note_by_bufnr
			editor.find_note_by_bufnr = function()
				return note
			end

			local original_find_notes = mock_ankiconnect_fn("find_notes", function(query, on_result)
				on_result({}, nil)
			end)

			local original_can_add = mock_ankiconnect_fn(
				"can_add_notes_with_error_details",
				function(deckName, modelName, fields, tags, on_result)
					on_result({ { canAdd = true } }, nil)
				end
			)

			local received_media = nil
			local received_on_result_type = nil
			local original_add_note = mock_ankiconnect_fn(
				"add_note",
				function(deckName, modelName, fields, tags, media, on_result)
					received_media = media
					received_on_result_type = type(on_result)
					on_result(12345, nil)
				end
			)

			local original_gui_browse = mock_ankiconnect_fn("gui_browse", function(query, on_result)
				on_result(nil, nil)
			end)

			local original_refresh = operations.refresh_all
			operations.refresh_all = function() end

			local original_delete_note_buffers = editor.delete_note_buffers
			editor.delete_note_buffers = function() end

			assert.has_no.errors(function()
				api.send_note(field_bufnr, false)
			end)

			vim.wait(200, function()
				return false
			end)

			assert.are.equal("table", type(received_media))
			assert.are.equal("function", received_on_result_type)

			editor.find_note_by_bufnr = original_find
			restore_ankiconnect_fn("find_notes", original_find_notes)
			restore_ankiconnect_fn("can_add_notes_with_error_details", original_can_add)
			restore_ankiconnect_fn("add_note", original_add_note)
			restore_ankiconnect_fn("gui_browse", original_gui_browse)
			operations.refresh_all = original_refresh
			editor.delete_note_buffers = original_delete_note_buffers
			anki_state.current_notes[tabid] = nil

			pcall(vim.api.nvim_buf_delete, field_bufnr, { force = true })
			pcall(vim.api.nvim_buf_delete, tags_bufnr, { force = true })
		end)
	end)

	describe("push_note_to_add_dialog", function()
		it("forwards the editor content as a guiAddCards payload without an id", function()
			local note, field_bufnr, tags_bufnr = make_note_with_real_bufs()
			note.id = 42

			local original_find = editor.find_note_by_bufnr
			editor.find_note_by_bufnr = function()
				return note
			end

			local received_payload = nil
			local original_gui_add_cards = mock_ankiconnect_fn("gui_add_cards", function(note_payload, on_result)
				received_payload = note_payload
				on_result(0, nil)
			end)

			local original_refresh = operations.refresh_all
			operations.refresh_all = function() end

			api.push_note_to_add_dialog(field_bufnr)

			vim.wait(200, function()
				return false
			end)

			assert.is_table(received_payload)
			assert.are.equal("TestDeck", received_payload.deckName)
			assert.are.equal("Basic", received_payload.modelName)
			assert.are.same({ Front = "hello" }, received_payload.fields)
			assert.are.same({ "tag1" }, received_payload.tags)
			assert.is_nil(received_payload.id)

			editor.find_note_by_bufnr = original_find
			restore_ankiconnect_fn("gui_add_cards", original_gui_add_cards)
			operations.refresh_all = original_refresh

			pcall(vim.api.nvim_buf_delete, field_bufnr, { force = true })
			pcall(vim.api.nvim_buf_delete, tags_bufnr, { force = true })
		end)

		it("notifies error when gui_add_cards fails", function()
			local note, field_bufnr, tags_bufnr = make_note_with_real_bufs()

			local original_find = editor.find_note_by_bufnr
			editor.find_note_by_bufnr = function()
				return note
			end

			mock_ankiconnect_fn("gui_add_cards", function(note_payload, on_result)
				on_result(nil, "add dialog unavailable")
			end)

			local error_spy = spy.on(notification, "error")

			api.push_note_to_add_dialog(field_bufnr)

			vim.wait(200, function()
				return false
			end)

			assert.spy(error_spy).was_called_with("[anki.nvim][api] Failed to open the Anki Add dialog")

			error_spy:revert()
			editor.find_note_by_bufnr = original_find
			restore_ankiconnect_fn("gui_add_cards", nil)

			pcall(vim.api.nvim_buf_delete, field_bufnr, { force = true })
			pcall(vim.api.nvim_buf_delete, tags_bufnr, { force = true })
		end)
	end)
end)
