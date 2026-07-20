---@mod anki.config Configuration
---@brief [[
--- Configuration module for anki.nvim.
---
--- This module holds the default options and merges user-provided overrides
--- via `setup()`. See |AnkiConfig| for the full list of options.
---@brief ]]

---@class AnkiConfig
---@field url string AnkiConnect server URL.
---@field timeout number HTTP request timeout in milliseconds.
---@field prefix string Keymap prefix to open the Anki UI (default: `"<leader>a"`).
---@field default_mappings boolean Whether to auto-set the prefix keymap.
---@field gui_browse_enabled boolean Whether to open Anki GUI when sending/pulling notes.
---@field create_user_commands boolean Whether to create the `:Anki` user command.
---@field mappings AnkiMappings Buffer-local keymappings for deck browser, note browser, editor, and template contexts.
---@field note_formatter fun(note: table): string Function to format a note for display in the note list.
---@field card_formatter fun(card: table): string Function to format a card for display in the card list.
---@field media_browser_preview boolean Use floating media browser with image preview when browsing Anki media (default: `true`). Falls back to vim.ui.select if disabled or if snacks.nvim image is unavailable.
---@field media_browser AnkiMediaBrowserConfig Floating media browser window configuration.

---@class AnkiMediaBrowserConfig
---@field width number Total width as fraction of &columns (default: `0.85`).
---@field height number Total height as fraction of &lines (default: `0.8`).
---@field list_width number List pane width as fraction of total width (default: `0.35`).
---@field pane_gap number Column offset between the list and preview panes (default: `2`). Controls the space consumed by borders/spacing between the two windows.
---@field border string|table Border characters for nvim_open_win (default: `"single"`).
---@field list_title string Title for the media list window (default: `" Media "`).
---@field preview_title string Title for the preview window (default: `" Preview "`).
---@field list_win_opts table<string,any> Window-local options for the list pane (default: `{ cursorline = true, wrap = false }`).
---@field preview_win_opts table<string,any> Window-local options for the preview pane (default: `{ wrap = false, number = false, relativenumber = false, signcolumn = "no" }`).

---@class AnkiMappings
---@field deck AnkiDeckMappings Deck pane keymaps.
---@field note AnkiNoteMappings Note pane keymaps.
---@field editor AnkiEditorMappings Editor pane keymaps.
---@field template AnkiTemplateMappings Template editor keymaps.

---@class AnkiDeckMappings
---@field show_help string Show Help (default: `"g?"`)
---@field close string Close (default: `"<leader>k"`)
---@field select_deck string Select deck (default: `"<CR>"`)
---@field delete_deck string Delete deck (default: `"d"`)
---@field create_deck string Create deck (default: `"c"`)
---@field add_note string Add note (default: `"a"`)
---@field rename_deck string Rename deck (default: `"m"`)
---@field gui_deck string Open in Anki GUI (default: `"o"`)
---@field refresh_decks string Refresh decks (default: `"r"`)
---@field switch_profile string Switch profile (default: `"p"`)
---@field edit_templates string Edit card templates (default: `"t"`)
---@field create_model string Create new model/note type (default: `"T"`)

---@class AnkiNoteMappings
---@field show_help string Show Help (default: `"g?"`)
---@field close string Close (default: `"<leader>k"`)
---@field edit_note string Edit note (default: `"<CR>"`)
---@field delete_note string Delete note (default: `"d"`)
---@field gui_note string Open in Anki GUI (default: `"o"`)
---@field show_all_notes string Show all notes (default: `"a"`)
---@field refresh_notes string Refresh notes (default: `"r"`)
---@field move_note_to_deck string Move note's cards to another deck (default: `"m"`)
---@field search string Search notes by query (default: `"f"`)
---@field toggle_view_mode string Toggle between notes and cards view (default: `"<Tab>"`)

---@class AnkiEditorMappings
---@field close string Close note editor (default: `"<leader>k"`)
---@field send_note string Send note to Anki (default: `"<leader>w"`)
---@field pull_note string Pull note from Anki (default: `"<leader>p"`)
---@field delete_note string Delete note (default: `"<leader>r"`)
---@field show_help string Show help (default: `"g?"`)
---@field attach_media string Attach media to note (default: `"<leader>m"`)

---@class AnkiTemplateMappings
---@field save_template string Save template to Anki (default: `"<leader>w"`)
---@field pull_template string Pull template from Anki (default: `"<leader>p"`)
---@field switch_card string Switch card in multi-card models (default: `"<leader>s"`)
---@field close_template string Close template editor (default: `"<leader>k"`)
---@field show_help string Show help (default: `"g?"`)

local M = {}

---@type AnkiConfig
M.defaults = {
	url = "http://localhost:8765",
	timeout = 500,
	prefix = "<leader>a",
	default_mappings = true,
	gui_browse_enabled = true,
	create_user_commands = true,
	note_formatter = function(note)
		local card_count = note.cards and #note.cards or 0
		local card_word = card_count == 1 and "card" or "cards"
		local prefix = string.format("(%d %s) ", card_count, card_word)
		local display = ""
		for key, field in pairs(note.fields) do
			display = display .. " [" .. key .. "]> " .. string.gsub(field.value, "[\r\n]", " ")
		end
		return prefix .. display
	end,
	card_formatter = function(card)
		local front = ""
		if card.fields and card.fields.Front then
			front = string.gsub(card.fields.Front.value, "[\r\n]", " ")
		end
		local ease = card.factor and (card.factor / 1000) or "?"
		return string.format(
			"[%s] [%s] due:%s ivl:%s ease:%s  %s",
			card.cardId,
			card.modelName,
			tostring(card.due),
			tostring(card.interval),
			tostring(ease),
			front
		)
	end,
	media_browser_preview = true,
	media_browser = {
		width = 0.85,
		height = 0.8,
		list_width = 0.35,
		pane_gap = 2,
		border = "single",
		list_title = " Media ",
		preview_title = " Preview ",
		list_win_opts = { cursorline = true, wrap = false },
		preview_win_opts = { wrap = false, number = false, relativenumber = false, signcolumn = "no" },
	},
	mappings = {
		deck = {
			show_help = "g?",
			close = "<leader>k",
			select_deck = "<CR>",
			delete_deck = "d",
			create_deck = "c",
			add_note = "a",
			rename_deck = "m",
			gui_deck = "o",
			refresh_decks = "r",
			switch_profile = "p",
			edit_templates = "t",
			create_model = "T",
		},
		note = {
			show_help = "g?",
			close = "<leader>k",
			edit_note = "<CR>",
			delete_note = "d",
			gui_note = "o",
			show_all_notes = "a",
			refresh_notes = "r",
			move_note_to_deck = "m",
			search = "f",
			toggle_view_mode = "<Tab>",
		},
		editor = {
			close = "<leader>k",
			send_note = "<leader>w",
			pull_note = "<leader>p",
			delete_note = "<leader>r",
			show_help = "g?",
			attach_media = "<leader>m",
		},
		template = {
			save_template = "<leader>w",
			pull_template = "<leader>p",
			switch_card = "<leader>s",
			close_template = "<leader>k",
			show_help = "g?",
		},
	},
}

---@type AnkiConfig
M.options = vim.tbl_deep_extend("force", {}, M.defaults)

--- Merge user options with defaults (deep-extend).
---@param opts AnkiConfig|nil Partial or full configuration table to override defaults.
---@see AnkiConfig
M.setup = function(opts)
	if opts ~= nil and type(opts) ~= "table" then
		error("[anki.nvim][config] setup: opts must be a table or nil")
	end
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
