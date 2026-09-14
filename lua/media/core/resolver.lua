---@module 'media.core.resolver'
---@brief Engine selection and fallback-chain resolution.
---@description
--- Resolves the first available engine for a request: the one explicitly
--- asked for, then `transcribe.engine`, then `transcribe.fallback` in order.
--- Modelled on `pdfport.core.resolver`, which answers the identical question
--- for extraction backends.
---
--- **Loads the built-in engines lazily, here rather than only in `setup()`.**
--- `media.transcribe()` works without `setup()` ever having run — `NEW-24`,
--- the same convention `media.probe`/`media.frame` already follow — so the
--- registry has to be populated on first use regardless of whether `setup()`
--- happened to run first. `media.engines.load_all()` is idempotent, so
--- calling it here and again from `setup()` costs nothing.

local registry = require("media.core.registry")

local M = {}

--- The engine ids to try, in order: `requested` (or `transcribe.engine` when
--- there is none), then `transcribe.fallback` with any duplicate of the
--- first entry dropped.
---
--- Pure and public for the same reason `sheet.args` is: the ordering is the
--- entire content of this function, and it should be assertable without a
--- registered engine anywhere.
---@param requested string|nil
---@return string[]
function M.build_chain(requested)
  local cfg = require("media.config").get().transcribe
  local fallback = cfg.fallback or {}

  local first = requested or cfg.engine
  local chain = { first }
  for i = 1, #fallback do
    if fallback[i] ~= first then chain[#chain + 1] = fallback[i] end
  end
  return chain
end

--- The first available engine for `requested` (or the configured default),
--- walking the fallback chain.
---@param requested string|nil
---@return Media.Engine|nil engine
---@return string|nil err
function M.resolve(requested)
  require("media.engines").load_all()

  local chain = M.build_chain(requested)
  for i = 1, #chain do
    local engine = registry.get(chain[i])
    if engine then
      local ok, avail = pcall(engine.available)
      if ok and avail then return engine, nil end
    end
  end
  return nil,
    ("media: no available transcription engine. Tried: [%s]"):format(table.concat(chain, ", "))
end

return M
