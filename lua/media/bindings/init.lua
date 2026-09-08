---@module 'media.bindings'
---@brief One entry point for keymaps, commands and autocommands.
---@description
--- Called by `media.setup()`, and idempotent: a reload or a second `setup()`
--- must not leave two copies of anything behind. The command is re-created by
--- name (Neovim replaces it), the autocommand group is cleared on creation, and
--- lib.nvim's keymap registry replaces a plugin's previous registration rather
--- than stacking a second one on top.

local M = {}

---@return nil
function M.setup()
  local cfg = require("media.config").get()
  require("media.bindings.usrcmds").register()
  require("media.bindings.keymaps").setup(cfg.keymaps)
  require("media.bindings.autocmds").setup()
end

return M
