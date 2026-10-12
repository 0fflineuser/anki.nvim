local sticky = require("anki.sticky")
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

local function make_note_with_real_bufs(fields_spec)
	-- fields_spec: list of { name, lines } — each field gets a real scratch buffer.
	local note_fields = {}
	local field_bufnrs = {}
	for _, spec in ipairs(fields_spec) do
		local bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, spec.lines or { "" })
		table.insert(field_bufnrs, bufnr)
		table.insert(
			note_fields,
			Field:new({
				editor_context = EditorContext:new({
					bufnr = bufnr,
					winid = 1000,
					tabid = 1001,
				}),
				name = spec.name,
			})
		)
	end

	local tags_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(tags_bufnr, 0, -1, false, { "tag1" })

	local note = Note:new({
		deck_name = "TestDeck",
		model_name = "TestModel",
		fields = note_fields,
		tags = EditorContext:new({
			bufnr = tags_bufnr,
			winid = 1002,
			tabid = 1003,
		}),
	})
	return note, field_bufnrs, tags_bufnr
end

local function mock_ankiconnect_fn(fn_name, callback_fn)
	local original = ankiconnect[fn_name]
	ankiconnect[fn_name] = callback_fn
	return original
end

local function restore_ankiconnect_fn(fn_name, original)
	ankiconnect[fn_name] = original
end

local function cleanup_note(note, field_bufnrs, tags_bufnr)
	for _, bufnr in ipairs(field_bufnrs) do
		pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
	end
	pcall(vim.api.nvim_buf_delete, tags_bufnr, { force = true })
end

describe("anki.sticky", function()
	before_each(function()
		sticky._store = {}
	end)
	after_each(function()
		sticky._store = {}
	end)

	describe("get", function()
		it("returns an empty table (not nil) for an unknown model", function()
			local fields = sticky.get("UnknownModel")
			assert.is_table(fields)
			assert.are.equal(0, vim.tbl_count(fields))
		end)

		it("caches the same table for the same model", function()
			assert.are.equal(sticky.get("Model"), sticky.get("Model"))
		end)

		it("errors on non-string model_name", function()
			assert.has_error(function()
				sticky.get(42)
			end)
		end)
	end)

	describe("toggle and is_sticky", function()
		it("flips false to true to false and is_sticky reflects it", function()
			assert.is_false(sticky.is_sticky("Model", "Front"))
			assert.is_true(sticky.toggle("Model", "Front"))
			assert.is_true(sticky.is_sticky("Model", "Front"))
			assert.is_false(sticky.toggle("Model", "Front"))
			assert.is_false(sticky.is_sticky("Model", "Front"))
		end)

		it("is per model: toggling model A does not affect model B", function()
			sticky.toggle("ModelA", "Front")
			assert.is_true(sticky.is_sticky("ModelA", "Front"))
			assert.is_false(sticky.is_sticky("ModelB", "Front"))
		end)

		it("is per field within one model", function()
			sticky.toggle("ModelA", "Front")
			assert.is_true(sticky.is_sticky("ModelA", "Front"))
			assert.is_false(sticky.is_sticky("ModelA", "Back"))
		end)
	end)

	describe("clear", function()
		it("removes all flags of one model only", function()
			sticky.toggle("ModelA", "Front")
			sticky.toggle("ModelB", "Front")
			sticky.clear("ModelA")
			assert.is_false(sticky.is_sticky("ModelA", "Front"))
			assert.is_true(sticky.is_sticky("ModelB", "Front"))
		end)
	end)
end)

describe("anki.editor.toggle_sticky", function()
	before_each(function()
		sticky._store = {}
	end)
	after_each(function()
		sticky._store = {}
	end)

	it("flips the flag for the field owning the buffer and notifies", function()
		local note, field_bufnrs, tags_bufnr = make_note_with_real_bufs({ { name = "Front", lines = { "hello" } } })
		local field_bufnr = field_bufnrs[1]
		local tabid = 9996
		anki_state.current_notes[tabid] = note
		note.tabid = tabid

		local info_spy = spy.on(notification, "info")
		assert.is_false(sticky.is_sticky("TestModel", "Front"))
		editor.toggle_sticky(field_bufnr)
		assert.is_true(sticky.is_sticky("TestModel", "Front"))
		assert.spy(info_spy).was_called_with("[anki.nvim][editor] Field 'Front' sticky: on")

		editor.toggle_sticky(field_bufnr)
		assert.is_false(sticky.is_sticky("TestModel", "Front"))
		assert.spy(info_spy).was_called_with("[anki.nvim][editor] Field 'Front' sticky: off")

		anki_state.current_notes[tabid] = nil
		cleanup_note(note, field_bufnrs, tags_bufnr)
	end)

	it("errors on non-number bufnr", function()
		assert.has_error(function()
			editor.toggle_sticky("x")
		end)
	end)
end)

describe("anki.api._reset_for_new_note", function()
	before_each(function()
		sticky._store = {}
	end)
	after_each(function()
		sticky._store = {}
	end)

	it("clears non-sticky field buffers, keeps sticky ones, keeps tags, nils id, resets media", function()
		local note, field_bufnrs, tags_bufnr = make_note_with_real_bufs({
			{ name = "Front", lines = { "front content" } },
			{ name = "Back", lines = { "back content", "line2" } },
		})
		sticky.toggle("TestModel", "Back") -- Back sticky, Front non-sticky

		note.id = 555
		note:add_media("picture", { filename = "img.png", path = "/tmp/img.png" })
		note:add_media("audio", { filename = "a.mp3", path = "/tmp/a.mp3" })
		note:add_media("video", { filename = "v.mp4", path = "/tmp/v.mp4" })

		api._reset_for_new_note(note)
		vim.wait(100, function()
			return false
		end)

		assert.are.same({ "" }, vim.api.nvim_buf_get_lines(field_bufnrs[1], 0, -1, false))
		assert.are.same({ "back content", "line2" }, vim.api.nvim_buf_get_lines(field_bufnrs[2], 0, -1, false))
		assert.are.same({ "tag1" }, vim.api.nvim_buf_get_lines(tags_bufnr, 0, -1, false))
		assert.is_nil(note.id)
		assert.are.same({ picture = {}, audio = {}, video = {} }, note.media)
		cleanup_note(note, field_bufnrs, tags_bufnr)
	end)
end)

describe("anki.api.send_note with new_note_after_send", function()
	before_each(function()
		sticky._store = {}
	end)
	after_each(function()
		sticky._store = {}
	end)

	it("sends, then resets: id nil-ed, non-sticky field cleared, sticky kept, tags kept", function()
		local note, field_bufnrs, tags_bufnr = make_note_with_real_bufs({
			{ name = "Front", lines = { "front content" } },
			{ name = "Back", lines = { "back sticky" } },
		})
		sticky.toggle("TestModel", "Back")

		local tabid = 9995
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
		local original_add_note = mock_ankiconnect_fn(
			"add_note",
			function(deckName, modelName, fields, tags, media, on_result)
				received_media = media
				on_result(12345, nil)
			end
		)

		local original_gui_browse = mock_ankiconnect_fn("gui_browse", function(query, on_result)
			on_result(nil, nil)
		end)

		local original_refresh = operations.refresh_all
		operations.refresh_all = function() end

		api.send_note(field_bufnrs[1], false, true)
		vim.wait(200, function()
			return false
		end)

		assert.are.equal("table", type(received_media))
		assert.is_nil(note.id)
		assert.are.same({ "" }, vim.api.nvim_buf_get_lines(field_bufnrs[1], 0, -1, false))
		assert.are.same({ "back sticky" }, vim.api.nvim_buf_get_lines(field_bufnrs[2], 0, -1, false))
		assert.are.same({ "tag1" }, vim.api.nvim_buf_get_lines(tags_bufnr, 0, -1, false))

		editor.find_note_by_bufnr = original_find
		restore_ankiconnect_fn("can_add_notes_with_error_details", original_can_add)
		restore_ankiconnect_fn("add_note", original_add_note)
		restore_ankiconnect_fn("gui_browse", original_gui_browse)
		operations.refresh_all = original_refresh
		anki_state.current_notes[tabid] = nil
		cleanup_note(note, field_bufnrs, tags_bufnr)
	end)

	it("does not reset when add fails (duplicate note path)", function()
		local note, field_bufnrs, tags_bufnr = make_note_with_real_bufs({
			{ name = "Front", lines = { "front content" } },
		})
		local tabid = 9994
		anki_state.current_notes[tabid] = note
		note.tabid = tabid

		local original_find = editor.find_note_by_bufnr
		editor.find_note_by_bufnr = function()
			return note
		end

		local original_can_add = mock_ankiconnect_fn(
			"can_add_notes_with_error_details",
			function(deckName, modelName, fields, tags, on_result)
				on_result({ { canAdd = false } }, nil)
			end
		)

		local add_note_called = false
		local original_add_note = mock_ankiconnect_fn("add_note", function()
			add_note_called = true
		end)

		local original_refresh = operations.refresh_all
		operations.refresh_all = function() end

		api.send_note(field_bufnrs[1], false, true)
		vim.wait(200, function()
			return false
		end)

		assert.is_false(add_note_called)
		assert.are.same({ "front content" }, vim.api.nvim_buf_get_lines(field_bufnrs[1], 0, -1, false))
		assert.is_nil(note.id) -- note.id stayed nil; nothing changed

		editor.find_note_by_bufnr = original_find
		restore_ankiconnect_fn("can_add_notes_with_error_details", original_can_add)
		restore_ankiconnect_fn("add_note", original_add_note)
		operations.refresh_all = original_refresh
		anki_state.current_notes[tabid] = nil
		cleanup_note(note, field_bufnrs, tags_bufnr)
	end)

	it("errors on non-boolean new_note_after_send", function()
		local note, field_bufnrs, tags_bufnr = make_note_with_real_bufs({ { name = "Front" } })
		local tabid = 9993
		anki_state.current_notes[tabid] = note
		note.tabid = tabid

		local original_find = editor.find_note_by_bufnr
		editor.find_note_by_bufnr = function()
			return note
		end

		assert.has_error(function()
			api.send_note(field_bufnrs[1], false, "yes")
		end)

		editor.find_note_by_bufnr = original_find
		anki_state.current_notes[tabid] = nil
		cleanup_note(note, field_bufnrs, tags_bufnr)
	end)
end)
