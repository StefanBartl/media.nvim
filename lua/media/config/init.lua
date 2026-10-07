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

--- A deep copy of `DEFAULTS`, built once and reused — see `M.get()`.
---@type Media.Config|nil
local _default_snapshot = nil

--- `keymaps = false` is the usual way to say "bind nothing", but `keymaps` is a table here, and
--- `tbl_deep_extend` would let the boolean replace it -- the keymap setup then indexed `false`
--- and raised (REL-20). The boolean is translated into the table form instead, the same way the
--- other plugins of this family treat a switch group: `false` -> `{ preset = false }` (the
--- existing "bind nothing" switch), `true` -> `{}` (the defaults). Anything that is neither a
--- boolean nor a table is dropped, so it can only fall back to the defaults.
---@param opts table  # the caller's table; never changed, a shallow copy is returned when needed
---@return table
local function normalize_keymaps(opts)
  local value = opts.keymaps
  if value == nil or type(value) == "table" then return opts end
  local out = vim.tbl_extend("force", {}, opts)
  if value == false then
    out.keymaps = { preset = false }
  else
    out.keymaps = nil
  end
  return out
end

---@param opts Media.Opts|nil
---@return nil
function M.setup(opts)
  opts = type(opts) == "table" and normalize_keymaps(opts) or {}
  _cfg = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), opts)
end

--- The effective configuration — the defaults when `setup()` never ran, which
--- is the supported way to use this plugin (`NEW-24`: nothing has to be
--- configured for anything to work).
---
--- **The no-`setup()` snapshot is built once, not on every call.** Every
--- caller here only reads `cfg.*`, never mutates it, so one shared deep copy
--- is as safe as a fresh one each time — and the no-`setup()` path is exactly
--- the one `hover.nvim`-style consumers take on every cursor move
--- (`core.probe`, `core.frame`), which `DEFAULTS.lua`'s own header says the
--- numbers here were tuned against: "a hover must not stutter." A fresh
--- `vim.deepcopy(DEFAULTS)` per call would re-walk the whole config tree on
--- every one of those. Found in review, 2026-09-15.
---@return Media.Config
function M.get()
  if _cfg then return _cfg end
  if not _default_snapshot then _default_snapshot = vim.deepcopy(DEFAULTS) end
  return _default_snapshot
end

return M
