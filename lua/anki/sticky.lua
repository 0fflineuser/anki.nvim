---
--- anki.sticky
---
--- Client-side sticky-field state, keyed by model name then field name.
---
--- AnkiConnect (version 6) exposes no action to read or write the model field
--- `sticky` flag, so the flag is persisted in Neovim for the session. Mirrors
--- Anki's add-note dialog: sticky fields keep their content when the editor is
--- reset for the next note, non-sticky fields are cleared. If a future
--- AnkiConnect adds a sticky-aware action, only this storage layer needs to
--- change.
---
--- The store is a module-local table (session-scoped: resets when Neovim
--- exits). A `vim.g`-backed store was rejected: assigning a Lua table to
--- `vim.g` converts it to a VimL dictionary and every read returns a fresh
--- copy, so mutations to a previously returned table are silently lost.
---
local M = {}

M._store = {}

--- Returns the table of sticky flags for a model: `table<string, boolean>` keyed by field name.
--- Creates and caches an empty table if the model is unknown.
---@param model_name string The model (note type) name.
---@return table<string, boolean> Sticky flags keyed by field name.
function M.get(model_name)
	if type(model_name) ~= "string" then
		error("[anki.nvim][sticky] get: model_name must be a string")
	end
	M._store[model_name] = M._store[model_name] or {}
	return M._store[model_name]
end

--- Toggles the sticky flag for one field of a model.
---@param model_name string The model (note type) name.
---@param field_name string The field name.
---@return boolean The new sticky state.
function M.toggle(model_name, field_name)
	if type(model_name) ~= "string" then
		error("[anki.nvim][sticky] toggle: model_name must be a string")
	end
	if type(field_name) ~= "string" then
		error("[anki.nvim][sticky] toggle: field_name must be a string")
	end
	local fields = M.get(model_name)
	fields[field_name] = not fields[field_name]
	return fields[field_name]
end

--- Returns the sticky state of one field (false when unknown).
---@param model_name string The model (note type) name.
---@param field_name string The field name.
---@return boolean
function M.is_sticky(model_name, field_name)
	if type(model_name) ~= "string" then
		error("[anki.nvim][sticky] is_sticky: model_name must be a string")
	end
	if type(field_name) ~= "string" then
		error("[anki.nvim][sticky] is_sticky: field_name must be a string")
	end
	local fields = M.get(model_name)
	return fields[field_name] == true
end

--- Clears all sticky flags of a model.
---@param model_name string The model (note type) name.
function M.clear(model_name)
	if type(model_name) ~= "string" then
		error("[anki.nvim][sticky] clear: model_name must be a string")
	end
	M._store[model_name] = nil
end

return M
