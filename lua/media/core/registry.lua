---@module 'media.core.registry'
---@brief Transcription engine registry.
---@description
--- One registry, one domain: engines that can turn a WAV into a
--- `Media.Transcript`. Modelled directly on `pdfport.core.registry`'s backend
--- registry, the proven shape in this ecosystem for "several interchangeable
--- external tools, resolved by availability and a fallback chain" — see
--- `media.core.resolver`. Registration is idempotent; every lookup is O(1).

local M = {}

---@type table<string, Media.Engine>
local _engines = {}

---@type string[]
local _order = {}

---@param engine Media.Engine
---@return nil
function M.register(engine)
  assert(type(engine) == "table", "engine must be a table")
  assert(type(engine.id) == "string" and engine.id ~= "", "engine.id must be a non-empty string")
  assert(type(engine.available) == "function", "engine.available must be a function")
  assert(type(engine.transcribe) == "function", "engine.transcribe must be a function")

  if not _engines[engine.id] then _order[#_order + 1] = engine.id end
  _engines[engine.id] = engine
end

---@param id string
---@return Media.Engine|nil
function M.get(id)
  return _engines[id]
end

---@return Media.Engine[]
function M.all()
  local result = {}
  for i = 1, #_order do
    result[i] = _engines[_order[i]]
  end
  return result
end

---@return string[]
function M.ids()
  local ids = {}
  for i = 1, #_order do
    ids[i] = _order[i]
  end
  return ids
end

---@param id string
---@return boolean
function M.has(id)
  return _engines[id] ~= nil
end

return M
