local ankiconnect = require("anki.ankiconnect")

describe("anki.ankiconnect template methods", function()
	describe("model_templates", function()
		it("throws error when modelName is not a string", function()
			assert.has_error(function()
				ankiconnect.model_templates(123, function() end)
			end, "[anki.nvim][ankiconnect] Expected a string as modelName")
		end)
	end)

	describe("model_styling", function()
		it("throws error when modelName is not a string", function()
			assert.has_error(function()
				ankiconnect.model_styling(123, function() end)
			end, "[anki.nvim][ankiconnect] Expected a string as modelName")
		end)
	end)

	describe("update_model_templates", function()
		it("throws error when model is not a table", function()
			assert.has_error(function()
				ankiconnect.update_model_templates("not a table", function() end)
			end, "[anki.nvim][ankiconnect] Expected a table as model")
		end)
	end)

	describe("update_model_styling", function()
		it("throws error when model is not a table", function()
			assert.has_error(function()
				ankiconnect.update_model_styling("not a table", function() end)
			end, "[anki.nvim][ankiconnect] Expected a table as model")
		end)
	end)

	describe("create_model", function()
		it("throws error when modelName is not a string", function()
			assert.has_error(function()
				ankiconnect.create_model(123, {}, {}, nil, nil, function() end)
			end, "[anki.nvim][ankiconnect] Expected a string as modelName")
		end)

		it("throws error when inOrderFields is not a table", function()
			assert.has_error(function()
				ankiconnect.create_model("Test", "not a table", {}, nil, nil, function() end)
			end, "[anki.nvim][ankiconnect] Expected a table as inOrderFields")
		end)

		it("throws error when cardTemplates is not a table", function()
			assert.has_error(function()
				ankiconnect.create_model("Test", {}, "not a table", nil, nil, function() end)
			end, "[anki.nvim][ankiconnect] Expected a table as cardTemplates")
		end)
	end)
end)

describe("anki.ankiconnect card wrappers", function()
	it("exposes find_cards as a function", function()
		assert.is_function(ankiconnect.find_cards)
	end)

	it("exposes cards_info as a function", function()
		assert.is_function(ankiconnect.cards_info)
	end)
end)

describe("anki.ankiconnect graphical action wrappers", function()
	local wrappers = {
		"gui_browse",
		"gui_selected_notes",
		"gui_select_card",
		"gui_add_cards",
		"gui_add_note_set_data",
		"gui_edit_note",
		"gui_review_active",
		"gui_current_card",
		"gui_start_card_timer",
		"gui_show_question",
		"gui_show_answer",
		"gui_answer_card",
		"gui_play_audio",
		"gui_undo",
		"gui_deck_overview",
		"gui_deck_browser",
		"gui_deck_review",
		"gui_import_file",
		"gui_check_database",
		"gui_exit_anki",
	}

	for _, name in ipairs(wrappers) do
		it("exposes " .. name .. " as a function", function()
			assert.is_function(ankiconnect[name])
		end)
	end

	it("throws error when gui_select_card card is not a number", function()
		assert.has_error(function()
			ankiconnect.gui_select_card("123", function() end)
		end, "[anki.nvim][ankiconnect] Expected a number as card")
	end)

	it("throws error when gui_add_cards note is not a table", function()
		assert.has_error(function()
			ankiconnect.gui_add_cards("not a table", function() end)
		end, "[anki.nvim][ankiconnect] Expected a table as note")
	end)

	it("throws error when gui_add_note_set_data note is not a table", function()
		assert.has_error(function()
			ankiconnect.gui_add_note_set_data("not a table", nil, function() end)
		end, "[anki.nvim][ankiconnect] Expected a table as note")
	end)

	it("throws error when gui_edit_note note_id is not a number", function()
		assert.has_error(function()
			ankiconnect.gui_edit_note("x", function() end)
		end, "[anki.nvim][ankiconnect] Expected a number as note_id")
	end)

	it("throws error when gui_answer_card ease is not a number", function()
		assert.has_error(function()
			ankiconnect.gui_answer_card("easy", function() end)
		end, "[anki.nvim][ankiconnect] Expected a number as ease")
	end)

	it("throws error when gui_deck_overview name is not a string", function()
		assert.has_error(function()
			ankiconnect.gui_deck_overview(42, function() end)
		end, "[anki.nvim][ankiconnect] Expected a string as name")
	end)

	it("throws error when gui_deck_review name is not a string", function()
		assert.has_error(function()
			ankiconnect.gui_deck_review(42, function() end)
		end, "[anki.nvim][ankiconnect] Expected a string as name")
	end)

	it("throws error when gui_import_file path is not a string", function()
		assert.has_error(function()
			ankiconnect.gui_import_file(42, function() end)
		end, "[anki.nvim][ankiconnect] Expected a string as path")
	end)
end)
