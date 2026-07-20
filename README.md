# Anki.nvim

Anki.nvim is a Neovim plugin that allows you to interact with Anki using [AnkiConnect](https://git.sr.ht/~foosoft/anki-connect).
It allows you to create, edit, and manage your Anki notes and decks directly from neovim.

## Table of Contents

-   [*Features*](#features)
-   [*Quick Start (Nix)*](#quick-start-nix)
-   [*Dependencies*](#dependencies)
-   [*Installation*](#installation)
-   [*Configuration*](#configuration)
-   [*Usage*](#usage)
-   [*Deck Browser Keymaps*](#deck-browser-keymaps)
-   [*Note Browser Keymaps*](#note-browser-keymaps)
-   [*Note Editor Keymaps*](#note-editor-keymaps)
-   [*Template Editor Keymaps*](#template-editor-keymaps)
-   [*Media Browser Keymaps*](#media-browser-keymaps)

## Features

-   Tab-based UI: Browse decks and notes in a two-pane browser tab (Decks on top, Notes on bottom), with note editing and template editing each opening in their own dedicated tabs. Multiple notes and templates can be edited simultaneously.
-   Persistent 'Default' Deck: The 'Default' deck will always appear in the deck pane, even if deleted, because Anki automatically recreates it as needed.
-   Deck Management: Create, rename, and delete Anki decks from within Neovim.
-   Note Management: Create, edit, move and delete notes in any deck.
-   Notes & Cards Views: Toggle between a notes view and a cards view of the current deck, like the Anki GUI's browser modes.
-   Search: Run an arbitrary AnkiConnect search query from within the notes view.
-   In-buffer Hints: Each browser pane shows a one-line key hint at the top, so you don't need to open help to remember the keys.
-   Model Selection: Choose the note model when creating notes.
-   Profile Switching: Switch between different Anki profiles without leaving Neovim.
-   Open in Anki GUI: Jump directly to the selected deck or note in the Anki desktop application.
-   Media Attachments: Attach images, audio, and video to notes from local files, URLs, clipboard, or Anki's media collection.
-   Media Browser: Browse Anki's media collection in a floating two-pane window with image preview support via [snacks.nvim](https://github.com/folke/snacks.nvim).

## Quick Start (Nix)

If you have [Nix](https://nixos.org) installed, you can try out the plugin without installing anything else.
You will need two terminal sessions — one for Anki and one for Neovim:

```bash
# Terminal 1: Start Anki (with AnkiConnect pre-installed)
nix develop github:0fflineuser/anki.nvim -c anki
```

```bash
# Terminal 2: Start Neovim with the plugin pre-configured
nix develop github:0fflineuser/anki.nvim -c nvim
```

The dev shell provides:

-   **Neovim** — with anki.nvim, plenary.nvim, and snacks.nvim pre-installed and configured
-   **Anki** — with the AnkiConnect add-on pre-installed
-   **stylua** — Lua formatter (for development)
-   **vimcats** — documentation generator (for development)

Inside Neovim, press `\a` (default `<leader>a` mapping with Neovim's default leader key `\`) or run `:Anki` to open the UI.

## Dependencies

-   [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
-   [AnkiConnect](https://ankiweb.net/shared/info/2055492159) (Anki Add-on)

### Optional

-   [snacks.nvim](https://github.com/folke/snacks.nvim) — For image preview in the media browser. Falls back to a metadata-only display if not installed or if the terminal does not support image protocols.

## Installation

Using `lazy.nvim`:

``` lua
{
  "0fflineuser/anki.nvim",
   dependencies = {
       "nvim-lua/plenary.nvim",
       "folke/snacks.nvim" -- optional, for image preview
   },
  opts = {
    -- Your custom configuration goes here
  },
  config = true
}
```

## Configuration

You can customize the plugin by passing a table to the `setup()` function. Here are the default options:

``` lua
require("anki").setup({
  -- The URL of your AnkiConnect server
  url = "http://localhost:8765",
  -- The timeout for requests to AnkiConnect, in milliseconds
  timeout = 500,
  -- The key to open the 'Anki UI' tab
  prefix = "<leader>a",
  -- Automatically map the 'Anki UI' to 'prefix'
  default_mappings = true,
  -- Whether to automatically open the Anki GUI to the relevant deck/note
  gui_browse_enabled = true,
  -- Whether to create the 'Anki' command
  create_user_commands = true,
  -- Use the floating media browser with image preview when browsing Anki media.
  -- Falls back to vim.ui.select if disabled or if snacks.nvim is unavailable.
  media_browser_preview = true,
  -- Function to format a note for display in the note list
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
  -- Function to format a card for display in the card list (cards view mode)
  card_formatter = function(card)
    local front = ""
    if card.fields and card.fields.Front then
      front = string.gsub(card.fields.Front.value, "[\r\n]", " ")
    end
    local ease = card.factor and (card.factor / 1000) or "?"
    return string.format("[%s] [%s] due:%s ivl:%s ease:%s  %s",
      card.cardId, card.modelName, tostring(card.due), tostring(card.interval), tostring(ease), front)
  end,
  -- Floating media browser window configuration
  media_browser = {
    -- Total width as fraction of &columns
    width = 0.85,
    -- Total height as fraction of &lines
    height = 0.8,
    -- List pane width as fraction of total width
    list_width = 0.35,
    -- Column offset between list and preview panes (accounts for borders/spacing)
    pane_gap = 2,
    -- Border style for nvim_open_win (see :help nvim_open_win)
    border = "single",
    -- Window titles
    list_title = " Media ",
    preview_title = " Preview ",
    -- Window-local options for the list pane
    list_win_opts = { cursorline = true, wrap = false },
    -- Window-local options for the preview pane
    preview_win_opts = { wrap = false, number = false, relativenumber = false, signcolumn = "no" },
  },
  -- Keymappings for the deck browser, note browser, editor, and template contexts
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
      show_help = "g?",
      send_note = "<leader>w",
      pull_note = "<leader>p",
      delete_note = "<leader>r",
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
})
```

## Usage

The plugin is centered around a single command, `:Anki`, which opens a dedicated UI in a new tab.

This browser tab has a horizontal split layout:

-   **Decks** (top): A list of your Anki decks.
-   **Notes** (bottom): A list of notes in the selected deck.

Each pane prepends a one-line key hint at the top, followed by a mode header and a blank line, so the available keys are always visible.

The bottom pane has two view modes: **notes** (default) and **cards**. Press `<Tab>` (default) to toggle between them — notes mode shows one row per note with its field values and card count, cards mode shows one row per reviewable card with its due date, interval, and ease. Press `f` to run an arbitrary AnkiConnect search query (e.g. `deck:Foo tag:bar`).

Editing notes and templates opens in their own separate tabs, and multiple notes or templates can be edited at the same time.

Each context (deck browser, note browser, note editor, template editor) has its own set of keymaps.
You can press `g?` in any context to see the available shortcuts for that specific context.
These keymaps are configurable, see the `Configuration` section.

### Deck Browser Keymaps

 | Keymap | Description                             |
 |--------|-----------------------------------------|
 | `g?`   | Show this help window                   |
 | `<leader>k` | Close the Anki UI tab                   |
 | `<CR>` | Select a deck and show its notes        |
 | `d`    | Delete deck under cursor                |
 | `c`    | Create a deck                           |
 | `a`    | Add a note to the deck under the cursor |
 | `m`    | Rename deck under the cursor            |
 | `o`    | Open the selected deck in the Anki GUI  |
 | `r`    | Refresh decks                           |
 | `p`    | Switch Anki profile                     |
 | `t`    | Edit card templates for the model       |
 | `T`    | Create a new model/note type            |

### Note Browser Keymaps

  | Keymap   | Description                                    |
  |----------|------------------------------------------------|
  | `g?`     | Show this help window                          |
  | `<leader>k` | Close the Anki UI tab                          |
  | `<CR>`   | Edit the selected note in a new tab            |
  | `d`      | Delete the selected note                       |
  | `o`      | Open the selected note in the Anki GUI         |
  | `a`      | Show all notes across decks                    |
  | `r`      | Refresh notes                                  |
  | `m`      | Move the selected note's cards to another deck |
  | `f`      | Search notes by AnkiConnect query              |
  | `<Tab>`  | Toggle between notes and cards view            |

### Note Editor Keymaps

  | Keymap       | Description                                       |
  |--------------|---------------------------------------------------|
  | `g?`         | Show this help window                             |
  | `<leader>k`  | Close the note editor tab                        |
  | `<leader>w`  | \*W\*rite/Send the current note to Anki           |
  | `<leader>p`  | \*P\*ull the latest version of the note from Anki |
  | `<leader>r`  | \*R\*emove/Delete the note from Anki              |
  | `<leader>m`  | \*M\*edia/Attach media to the current field        |

### Template Editor Keymaps

  | Keymap       | Description                                       |
  |--------------|---------------------------------------------------|
  | `g?`         | Show this help window                             |
  | `<leader>k`  | Close the template editor tab                    |
  | `<leader>w`  | Save template changes to Anki                     |
  | `<leader>p`  | Pull the latest template from Anki                |
  | `<leader>s`  | Switch card (for multi-card models)                |

### Media Browser Keymaps

The media browser is a floating two-pane window (file list on the left, preview on the right) that opens when you select "Browse Anki media" from the media attachment menu. Images are previewed inline when [snacks.nvim](https://github.com/folke/snacks.nvim) is installed and the terminal supports image protocols; otherwise, file metadata (name, type, extension) is shown.

  | Keymap    | Description                              |
  |-----------|------------------------------------------|
  | `<CR>`    | Insert the selected media reference      |
  | `<leader>k` | Close the media browser                  |
  | `<Esc>`   | Close the media browser                  |
  | `g?`      | Show help window                              |
  | `j`/`k`   | Navigate the file list (standard movement) |

The media browser can be disabled (falling back to `vim.ui.select`) by setting `media_browser_preview = false` in the config. The window layout and appearance can be customized via the `media_browser` config table (see [Configuration](#configuration)).
