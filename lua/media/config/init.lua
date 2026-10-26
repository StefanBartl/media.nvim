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
  -- the shared helper owns the shape; `preset` is this plugin's older spelling of the switch key.
  -- lib.nvim is a soft dependency: without it (or with a version lacking the helper) setup() must still not raise.
  local loaded, normalize = pcall(require, "lib.nvim.normalize")
  if loaded and type(normalize.normalize_switch_group) == "function" then
    out.keymaps = normalize.normalize_switch_group(value, "preset")
  elseif value == false then
    out.keymaps = { preset = false }
  else
    out.keymaps = nil
  end
  return out
end

--- The accepted type(s) of the scalar options, by dotted path (`|` separates alternatives). Only
--- keys with a fixed type are listed; keys that take several shapes (`player`, `keymaps.*`, ...)
--- are left alone on purpose.
---@type table<string, string>
local TYPES = {
  timeout_ms = "number",
  render_concurrency = "number",
  progress_style = "string",
  ["frame.at"] = "number|string",
  ["frame.width"] = "number",
  ["frames.fps"] = "number",
  ["frames.count"] = "number",
  ["frames.width"] = "number",
  ["sheet.rows"] = "number",
  ["sheet.cols"] = "number",
  ["sheet.width"] = "number",
  ["sheet.margin"] = "number",
  ["sheet.timeout_ms"] = "number",
  ["waveform.width"] = "number",
  ["waveform.height"] = "number",
  ["waveform.colors"] = "string",
  ["waveform.timeout_ms"] = "number",
  ["transcribe.engine"] = "string",
  ["transcribe.auto"] = "table",
  ["transcribe.fallback"] = "table",
  ["transcribe.lang"] = "string",
  ["transcribe.model"] = "string",
  ["transcribe.whisper_cpp.model"] = "string",
  ["transcribe.whisper_cpp.model_dir"] = "string",
  ["transcribe.openai_whisper.model"] = "string",
  ["transcribe.openai_whisper.model_dir"] = "string",
  ["transcribe.openai_whisper.device"] = "string",
  ["transcribe.openai_whisper.allow_download"] = "boolean",
  ["transcribe.faster_whisper.model"] = "string",
  ["transcribe.faster_whisper.model_dir"] = "string",
  ["transcribe.faster_whisper.device"] = "string",
  ["transcribe.faster_whisper.allow_download"] = "boolean",
  ["transcribe.task"] = "string",
  ["transcribe.output"] = "string",
  ["transcribe.cache"] = "boolean",
  ["transcribe.timeout_ms"] = "number",
  ["transcribe.normalize_timeout_ms"] = "number",
  ["cache.enabled"] = "boolean",
  ["cache.max_age_days"] = "number",
  ["cache.max_mb"] = "number",
  ["hub.exclude"] = "table",
  ["hub.max_entries"] = "number",
  ["window.autofit"] = "string",
  ["window.ontop"] = "boolean",
  ["window.args"] = "table",
}

--- Check the typed options of a user table. Nothing is raised: `setup()` runs at startup, where
--- an error would take the whole config with it. A wrongly typed value is reported and dropped,
--- so the default applies instead of a value the plugin cannot use.
---@param opts table  # the caller's table; never changed
---@return table clean  # `opts` without the offending keys (`opts` itself when all are fine)
---@return string[] problems
function M.validate(opts)
  local problems, clean = {}, nil
  for path, want in pairs(TYPES) do
    local parts = vim.split(path, ".", { plain = true })
    local parent = opts
    for i = 1, #parts - 1 do
      parent = type(parent) == "table" and parent[parts[i]] or nil
    end
    local leaf = parts[#parts]
    local value = type(parent) == "table" and parent[leaf] or nil
    if
      value ~= nil and not vim.list_contains(vim.split(want, "|", { plain = true }), type(value))
    then
      problems[#problems + 1] = ("%s must be %s, got %s"):format(
        path,
        (want:gsub("|", " or ")),
        type(value)
      )
      clean = clean or vim.deepcopy(opts)
      local node = clean
      for i = 1, #parts - 1 do
        node = node[parts[i]]
      end
      node[leaf] = nil
    end
  end
  table.sort(problems)
  return clean or opts, problems
end

---@param opts Media.Opts|nil
---@return nil
function M.setup(opts)
  opts = type(opts) == "table" and normalize_keymaps(opts) or {}
  local problems
  opts, problems = M.validate(opts)
  if #problems > 0 then
    require("media.util.notify").warn(
      "ignoring invalid option(s): " .. table.concat(problems, "; ")
    )
  end
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
