---@module 'media.config'
---@brief Configuration entry point.
---@description
--- Every configurable key, its type and the reasoning behind its default live
--- in `config/DEFAULTS.lua`; this module only merges a user table over them and
--- hands the result out.
---
--- **The merge starts from a deep copy.** `DEFAULTS` is a module-level table,
--- so it is created once per session and shared by everyone who requires it. A
--- merge that reuses its nested tables would let one `setup()` call leave marks
--- on the defaults a later one reads.

local M = {}

local DEFAULTS = require("media.config.DEFAULTS")

---@type Media.Config|nil
local _cfg = nil

---@param opts Media.Opts|nil
---@return nil
function M.setup(opts)
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts or {})
end

--- The effective configuration — the defaults when `setup()` never ran, which
--- is the supported way to use this plugin (`NEW-24`: nothing has to be
--- configured for anything to work).
---@return Media.Config
function M.get()
  return _cfg or vim.deepcopy(DEFAULTS)
end

return M
