local config = require("anki.config")
local curl = require("plenary.curl")

---
--- anki.ankiconnect
---
--- Provides low-level functions to communicate with the AnkiConnect API via HTTP.
--- All functions are asynchronous and use callbacks to avoid blocking Neovim's UI.
--- Wraps all AnkiConnect actions (decks, notes, models, etc.) for use by higher-level modules.
---
--- Callback signature: on_result(result, error)
---   - on success: on_result(result_data, nil)
---   - on failure: on_result(nil, error_message_string)
---
local M = {}

local LARGE_BODY_THRESHOLD = 100 * 1024

local function anki_connect_invoke_async(options, on_result)
	if type(options) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as argument")
	end
	if type(on_result) ~= "function" then
		error("[anki.nvim][ankiconnect] Expected a function as callback")
	end
	local action = options.action
	local version = options.version or 6
	local params = options.params or vim.empty_dict()

	if not action then
		error("[anki.nvim][ankiconnect] Missing required fields: action")
	end
	if type(version) ~= "number" then
		error("[anki.nvim][ankiconnect] Expected a number as version")
	end
	if type(params) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table or nil as params")
	end

	local data = {
		action = action,
		version = version,
		params = params,
	}

	local post_data = vim.json.encode(data, { escape_slash = true })

	local tmp_file

	local function handle_response(response)
		if tmp_file then
			os.remove(tmp_file)
		end

		if response.exit ~= 0 then
			on_result(
				nil,
				[=[Failed to send request, make sure Anki is running and AnkiConnect is installed. Please:
    1. Make sure Anki is running
    2. Verify AnkiConnect addon is installed in Anki
    3. Check that the URL in the config is correct]=]
			)
			return
		end

		local ok, decoded = pcall(vim.json.decode, response.body, { luanil = { objects = false, array = false } })
		if not ok then
			on_result(nil, "[anki.nvim][ankiconnect] Failed to decode JSON response: " .. tostring(decoded))
			return
		end

		if decoded.error ~= nil and decoded.error ~= vim.NIL then
			on_result(nil, vim.inspect(decoded.error))
			return
		end

		on_result(decoded.result, nil)
	end

	local post_opts = {
		headers = {
			content_type = "application/json",
		},
		timeout = config.options.timeout,
		callback = handle_response,
	}

	if #post_data > LARGE_BODY_THRESHOLD then
		tmp_file = vim.fn.tempname()
		local f = io.open(tmp_file, "wb")
		if not f then
			on_result(nil, "[anki.nvim][ankiconnect] Failed to create temp file for large request body")
			return
		end
		f:write(post_data)
		f:close()
		post_opts.body = tmp_file
	else
		post_opts.body = post_data
	end

	curl.post(config.options.url, post_opts)
end

M.deck_names = function(on_result)
	anki_connect_invoke_async({ action = "deckNames" }, on_result)
end

M.version = function(on_result)
	anki_connect_invoke_async({ action = "version" }, on_result)
end

M.request_permission = function(on_result)
	anki_connect_invoke_async({ action = "requestPermission" }, on_result)
end

---
--- Finds notes in Anki matching the given query string.
---
---@param query string The search query.
---@param on_result function Callback: on_result(note_ids, error)
M.find_notes = function(query, on_result)
	anki_connect_invoke_async({ action = "findNotes", params = { query = query } }, on_result)
end

---
--- Gets detailed information for a list of note IDs.
---
---@param notes table List of note IDs.
---@param on_result function Callback: on_result(notes_info, error)
M.notes_info = function(notes, on_result)
	anki_connect_invoke_async({ action = "notesInfo", params = { notes = notes } }, on_result)
end

---
--- Finds cards in Anki matching the given query string.
---
---@param query string The search query.
---@param on_result function Callback: on_result(card_ids, error)
M.find_cards = function(query, on_result)
	anki_connect_invoke_async({ action = "findCards", params = { query = query } }, on_result)
end

---
--- Gets detailed information for a list of card IDs.
---
---@param cards table List of card IDs.
---@param on_result function Callback: on_result(cards_info, error)
M.cards_info = function(cards, on_result)
	anki_connect_invoke_async({ action = "cardsInfo", params = { cards = cards } }, on_result)
end

M.create_deck = function(deck, on_result)
	anki_connect_invoke_async({ action = "createDeck", params = { deck = deck } }, on_result)
end

M.model_names = function(on_result)
	anki_connect_invoke_async({ action = "modelNames" }, on_result)
end

M.get_tags = function(on_result)
	anki_connect_invoke_async({ action = "getTags" }, on_result)
end

M.model_field_names = function(modelName, on_result)
	anki_connect_invoke_async({ action = "modelFieldNames", params = { modelName = modelName } }, on_result)
end

---
--- Adds a note to Anki via AnkiConnect.
---
---@param deckName string The name of the deck.
---@param modelName string The name of the model.
---@param fields table The note fields.
---@param tags table The note tags.
---@param media table|nil Optional media attachments.
---@param on_result function Callback: on_result(note_id, error)
M.add_note = function(deckName, modelName, fields, tags, media, on_result)
	local note = {
		deckName = deckName,
		modelName = modelName,
		fields = fields,
		options = {
			allowDuplicate = false,
			duplicateScope = "deck",
			duplicateScopeOptions = {
				deckName = nil,
				checkChildren = false,
				checkAllModels = false,
			},
		},
		tags = tags,
	}
	if media then
		if media.picture then
			note.picture = media.picture
		end
		if media.audio then
			note.audio = media.audio
		end
		if media.video then
			note.video = media.video
		end
	end
	anki_connect_invoke_async({
		action = "addNote",
		params = {
			note = note,
		},
	}, on_result)
end

M.can_add_notes_with_error_details = function(deckName, modelName, fields, tags, on_result)
	anki_connect_invoke_async({
		action = "canAddNotesWithErrorDetail",
		params = {
			notes = { {
				deckName = deckName,
				modelName = modelName,
				fields = fields,
				tags = tags,
			} },
		},
	}, on_result)
end

M.update_note = function(id, fields, tags, on_result)
	anki_connect_invoke_async({
		action = "updateNote",
		params = {
			note = {
				id = id,
				fields = fields,
				tags = tags,
			},
		},
	}, on_result)
end

---
--- Deletes notes in Anki by note ID.
---
---@param notes table List of note IDs to delete.
---@param on_result function Callback: on_result(result, error)
M.delete_notes = function(notes, on_result)
	if type(notes) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as argument")
	end
	anki_connect_invoke_async({
		action = "deleteNotes",
		params = {
			notes = notes,
		},
	}, on_result)
end

M.delete_decks = function(decks, on_result)
	if type(decks) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as argument")
	end
	anki_connect_invoke_async({
		action = "deleteDecks",
		params = {
			decks = decks,
			cardsToo = true,
		},
	}, on_result)
end

M.gui_browse = function(query, on_result)
	anki_connect_invoke_async({
		action = "guiBrowse",
		params = {
			query = query,
		},
	}, on_result)
end

M.gui_selected_notes = function(on_result)
	anki_connect_invoke_async({ action = "guiSelectedNotes", params = vim.empty_dict() }, on_result)
end

--- Selects the given card in the Anki GUI browser.
---@param card number The card ID to select.
---@param on_result function Callback: on_result(result, error)
M.gui_select_card = function(card, on_result)
	if type(card) ~= "number" then
		error("[anki.nvim][ankiconnect] Expected a number as card")
	end
	anki_connect_invoke_async({ action = "guiSelectCard", params = { card = card } }, on_result)
end

--- Populates the Anki GUI Add dialog with the given note draft.
---@param note table Table with deckName, modelName, fields, tags and optional picture/audio/video (same `note` payload as addNote).
---@param on_result function Callback: on_result(result, error)
M.gui_add_cards = function(note, on_result)
	if type(note) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as note")
	end
	anki_connect_invoke_async({ action = "guiAddCards", params = { note = note } }, on_result)
end

--- Updates the open Anki GUI Add dialog draft with the given note data.
---@param note table Table with deckName, modelName, fields, tags (same `note` payload as addNote).
---@param append boolean|nil When true, concatenates field values and unions tags into the draft.
---@param on_result function Callback: on_result(result, error)
M.gui_add_note_set_data = function(note, append, on_result)
	if type(note) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as note")
	end
	local params = { note = note }
	if append ~= nil then
		params.append = append
	end
	anki_connect_invoke_async({ action = "guiAddNoteSetData", params = params }, on_result)
end

--- Opens the given note in the Anki GUI edit dialog.
---@param note_id number The note ID to edit.
---@param on_result function Callback: on_result(result, error)
M.gui_edit_note = function(note_id, on_result)
	if type(note_id) ~= "number" then
		error("[anki.nvim][ankiconnect] Expected a number as note_id")
	end
	anki_connect_invoke_async({ action = "guiEditNote", params = { note = note_id } }, on_result)
end

M.gui_review_active = function(on_result)
	anki_connect_invoke_async({ action = "guiReviewActive", params = vim.empty_dict() }, on_result)
end

M.gui_current_card = function(on_result)
	anki_connect_invoke_async({ action = "guiCurrentCard", params = vim.empty_dict() }, on_result)
end

M.gui_start_card_timer = function(on_result)
	anki_connect_invoke_async({ action = "guiStartCardTimer", params = vim.empty_dict() }, on_result)
end

M.gui_show_question = function(on_result)
	anki_connect_invoke_async({ action = "guiShowQuestion", params = vim.empty_dict() }, on_result)
end

M.gui_show_answer = function(on_result)
	anki_connect_invoke_async({ action = "guiShowAnswer", params = vim.empty_dict() }, on_result)
end

--- Answers the current reviewer card with the given ease.
---@param ease number The ease (1-4).
---@param on_result function Callback: on_result(result, error)
M.gui_answer_card = function(ease, on_result)
	if type(ease) ~= "number" then
		error("[anki.nvim][ankiconnect] Expected a number as ease")
	end
	anki_connect_invoke_async({ action = "guiAnswerCard", params = { ease = ease } }, on_result)
end

M.gui_play_audio = function(on_result)
	anki_connect_invoke_async({ action = "guiPlayAudio", params = vim.empty_dict() }, on_result)
end

M.gui_undo = function(on_result)
	anki_connect_invoke_async({ action = "guiUndo", params = vim.empty_dict() }, on_result)
end

--- Shows the overview screen of the given deck in the Anki GUI.
---@param name string The name of the deck.
---@param on_result function Callback: on_result(result, error)
M.gui_deck_overview = function(name, on_result)
	if type(name) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as name")
	end
	anki_connect_invoke_async({ action = "guiDeckOverview", params = { name = name } }, on_result)
end

M.gui_deck_browser = function(on_result)
	anki_connect_invoke_async({ action = "guiDeckBrowser", params = vim.empty_dict() }, on_result)
end

--- Starts a review session for the given deck in the Anki GUI.
---@param name string The name of the deck.
---@param on_result function Callback: on_result(result, error)
M.gui_deck_review = function(name, on_result)
	if type(name) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as name")
	end
	anki_connect_invoke_async({ action = "guiDeckReview", params = { name = name } }, on_result)
end

--- Opens the Anki GUI file import dialog, optionally pre-filled with a path.
---@param path string|nil Optional path to the file to import.
---@param on_result function Callback: on_result(result, error)
M.gui_import_file = function(path, on_result)
	if path ~= nil and type(path) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as path")
	end
	local params = path == nil and vim.empty_dict() or { path = path }
	anki_connect_invoke_async({ action = "guiImportFile", params = params }, on_result)
end

M.gui_check_database = function(on_result)
	anki_connect_invoke_async({ action = "guiCheckDatabase", params = vim.empty_dict() }, on_result)
end

M.gui_exit_anki = function(on_result)
	anki_connect_invoke_async({ action = "guiExitAnki", params = vim.empty_dict() }, on_result)
end

M.change_deck = function(cards, deck, on_result)
	anki_connect_invoke_async({ action = "changeDeck", params = { cards = cards, deck = deck } }, on_result)
end

---
--- Gets the list of available Anki profiles.
---
---@param on_result function Callback: on_result(profiles, error)
M.get_profiles = function(on_result)
	anki_connect_invoke_async({ action = "getProfiles" }, on_result)
end

---
--- Gets the name of the currently active Anki profile.
---
---@param on_result function Callback: on_result(profile_name, error)
M.get_active_profile = function(on_result)
	anki_connect_invoke_async({ action = "getActiveProfile" }, on_result)
end

---
--- Loads (switches to) the specified Anki profile.
---
---@param name string The name of the profile to load.
---@param on_result function Callback: on_result(result, error)
M.load_profile = function(name, on_result)
	if type(name) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as profile name")
	end
	anki_connect_invoke_async({ action = "loadProfile", params = { name = name } }, on_result)
end

M.store_media_file = function(filename, opts, on_result)
	opts = opts or vim.empty_dict()
	local params = { filename = filename }
	if opts.data then
		params.data = opts.data
	elseif opts.path then
		params.path = opts.path
	elseif opts.url then
		params.url = opts.url
	end
	if opts.delete_existing ~= nil then
		params.deleteExisting = opts.delete_existing
	end
	anki_connect_invoke_async({ action = "storeMediaFile", params = params }, on_result)
end

M.retrieve_media_file = function(filename, on_result)
	anki_connect_invoke_async({ action = "retrieveMediaFile", params = { filename = filename } }, on_result)
end

M.get_media_files_names = function(pattern, on_result)
	anki_connect_invoke_async({
		action = "getMediaFilesNames",
		params = { pattern = pattern or "*" },
	}, on_result)
end

M.get_media_dir_path = function(on_result)
	anki_connect_invoke_async({ action = "getMediaDirPath" }, on_result)
end

M.delete_media_file = function(filename, on_result)
	anki_connect_invoke_async({ action = "deleteMediaFile", params = { filename = filename } }, on_result)
end

---
--- Gets the card templates for a model by name.
--- Returns a table mapping card names to { Front, Back } template strings.
---
---@param modelName string The name of the model.
---@param on_result function Callback: on_result(templates, error)
M.model_templates = function(modelName, on_result)
	if type(modelName) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as modelName")
	end
	anki_connect_invoke_async({ action = "modelTemplates", params = { modelName = modelName } }, on_result)
end

---
--- Gets the CSS styling for a model by name.
---
---@param modelName string The name of the model.
---@param on_result function Callback: on_result(styling, error)
M.model_styling = function(modelName, on_result)
	if type(modelName) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as modelName")
	end
	anki_connect_invoke_async({ action = "modelStyling", params = { modelName = modelName } }, on_result)
end

---
--- Updates the templates of an existing model.
--- Only specified cards and sides will be modified; unspecified ones are left unchanged.
---
---@param model table Table with `name` (string) and `templates` (table mapping card names to { Front, Back }).
---@param on_result function Callback: on_result(result, error)
M.update_model_templates = function(model, on_result)
	if type(model) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as model")
	end
	anki_connect_invoke_async({ action = "updateModelTemplates", params = { model = model } }, on_result)
end

---
--- Updates the CSS styling of an existing model.
---
---@param model table Table with `name` (string) and `css` (string).
---@param on_result function Callback: on_result(result, error)
M.update_model_styling = function(model, on_result)
	if type(model) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as model")
	end
	anki_connect_invoke_async({ action = "updateModelStyling", params = { model = model } }, on_result)
end

---
--- Creates a new model (note type) in Anki.
---
---@param modelName string The name for the new model.
---@param inOrderFields table List of field names in order.
---@param cardTemplates table List of card template tables. Each entry has optional `Name`, `Front`, and `Back` fields.
---@param css string|nil Optional CSS styling. Defaults to Anki's default if not provided.
---@param isCloze boolean|nil Whether this is a cloze model. Defaults to false.
---@param on_result function Callback: on_result(result, error)
M.create_model = function(modelName, inOrderFields, cardTemplates, css, isCloze, on_result)
	if type(modelName) ~= "string" then
		error("[anki.nvim][ankiconnect] Expected a string as modelName")
	end
	if type(inOrderFields) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as inOrderFields")
	end
	if type(cardTemplates) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as cardTemplates")
	end
	local params = {
		modelName = modelName,
		inOrderFields = inOrderFields,
		cardTemplates = cardTemplates,
	}
	if css ~= nil then
		params.css = css
	end
	if isCloze ~= nil then
		params.isCloze = isCloze
	end
	anki_connect_invoke_async({ action = "createModel", params = params }, on_result)
end

---
--- Gets per-deck statistics (new/learn/review/total counts) for a list of decks.
--- Returns a table keyed by numeric deck-ID strings, each value containing
--- `deck_id`, `name`, `new_count`, `learn_count`, `review_count`, `total_in_deck`.
---
---@param decks table List of deck names.
---@param on_result function Callback: on_result(deck_stats, error)
M.get_deck_stats = function(decks, on_result)
	if type(decks) ~= "table" then
		error("[anki.nvim][ankiconnect] Expected a table as decks")
	end
	anki_connect_invoke_async({ action = "getDeckStats", params = { decks = decks } }, on_result)
end

---
--- Gets the number of cards reviewed today across all decks.
---
---@param on_result function Callback: on_result(count, error)
M.get_num_cards_reviewed_today = function(on_result)
	anki_connect_invoke_async({ action = "getNumCardsReviewedToday" }, on_result)
end

---
--- Gets the number of cards reviewed per day across all decks.
--- Returns a list of (dateString, count) pairs, descending by day.
---
---@param on_result function Callback: on_result(days, error)
M.get_num_cards_reviewed_by_day = function(on_result)
	anki_connect_invoke_async({ action = "getNumCardsReviewedByDay" }, on_result)
end

return M
