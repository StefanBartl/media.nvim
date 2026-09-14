---@module 'media.engines'
---@brief Loads and registers every built-in transcription engine.
---@description
--- One entry today (`whisper_cpp`); `faster_whisper`, `openai_whisper`,
--- `openai_api` and `custom` join this list in a later phase (ROADMAP.md).
--- Idempotent and cheap to call more than once — `media.setup()` calls it
--- eagerly, `media.core.resolver` calls it again lazily for the caller that
--- never ran `setup()` at all.

local registry = require("media.core.registry")

local M = {}

---@type string[]
local BUILTIN = {
  "media.engines.whisper_cpp",
}

local _loaded = false

---@return nil
function M.load_all()
  if _loaded then return end
  _loaded = true

  for _, module_path in ipairs(BUILTIN) do
    local ok, engine = pcall(require, module_path)
    if ok and type(engine) == "table" then registry.register(engine) end
  end
end

return M
