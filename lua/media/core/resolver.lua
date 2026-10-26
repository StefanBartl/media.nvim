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
---
--- **`"auto"`** is not an engine id but a request: try `transcribe.auto` in
--- order and take the first engine that is *ready* — installed and able to
--- run with the requested model (`engine.ready`, where an engine has one) —
--- rather than merely installed. The difference is the point: a whisper.cpp
--- with no GGML model configured is "available", and picking it would end
--- every run in "no model configured" while a working openai-whisper sits
--- next to it. An explicitly named engine keeps the plain `available()` test,
--- so its own, specific error reaches the user instead of a fallback.

local registry = require("media.core.registry")

local M = {}

--- The engine ids to try, in order: `requested` (or `transcribe.engine` when
--- there is none) — expanded to `transcribe.auto` when it is `"auto"` — then
--- `transcribe.fallback`, with any id already in the chain dropped.
---
--- Pure and public for the same reason `sheet.args` is: the ordering is the
--- entire content of this function, and it should be assertable without a
--- registered engine anywhere.
---
--- **An empty string is treated as "none given", not as a real id.** Lua's
--- `or` sees `""` as truthy, so `requested or cfg.engine` alone would let a
--- blank `:Media transcribe path engine=` silently try to resolve engine id
--- `""` instead of falling back to the configured default — found in
--- review, 2026-09-14.
---@param requested string|nil
---@return string[]
function M.build_chain(requested)
  local cfg = require("media.config").get().transcribe
  local fallback = cfg.fallback or {}

  local first = M.requested(requested)
  local head = first == "auto" and (cfg.auto or {}) or { first }

  local chain, seen = {}, {}
  local function add(id)
    if type(id) == "string" and id ~= "" and not seen[id] then
      seen[id] = true
      chain[#chain + 1] = id
    end
  end
  for i = 1, #head do
    add(head[i])
  end
  for i = 1, #fallback do
    add(fallback[i])
  end
  return chain
end

--- The engine request after defaults: `requested` when it is a real value,
--- `transcribe.engine` otherwise. `"auto"` stays `"auto"`.
---@param requested string|nil
---@return string
function M.requested(requested)
  if type(requested) == "string" and requested ~= "" then return requested end
  return require("media.config").get().transcribe.engine
end

--- Whether `engine` can take a run: `available()`, and with `strict` also
--- `ready(opts)` where the engine defines one.
---@param engine Media.Engine
---@param strict boolean
---@param opts { model: string|nil }|nil
---@return boolean ok
---@return string|nil reason
local function usable(engine, strict, opts)
  local ok, avail = pcall(engine.available)
  if not (ok and avail) then return false, "not installed" end
  if not strict or type(engine.ready) ~= "function" then return true, nil end
  local rok, ready, why = pcall(engine.ready, opts)
  if not rok then return false, tostring(ready) end
  if ready then return true, nil end
  return false, why or "not ready"
end

--- The first usable engine for `requested` (or the configured default),
--- walking the chain — see the module note for what "usable" means under
--- `"auto"`.
---@param requested string|nil
---@param opts { model: string|nil }|nil  # what the run will ask of the engine
---@return Media.Engine|nil engine
---@return string|nil err
function M.resolve(requested, opts)
  require("media.engines").load_all()

  local strict = M.requested(requested) == "auto"
  local chain = M.build_chain(requested)
  local reasons = {}
  for i = 1, #chain do
    local engine = registry.get(chain[i])
    if engine then
      local ok, why = usable(engine, strict, opts)
      if ok then return engine, nil end
      reasons[#reasons + 1] = ("%s: %s"):format(chain[i], why)
    else
      reasons[#reasons + 1] = chain[i] .. ": not registered"
    end
  end
  local err = ("media: no available transcription engine. Tried: [%s]"):format(
    table.concat(chain, ", ")
  )
  if #reasons > 0 then err = err .. " — " .. table.concat(reasons, "; ") end
  return nil, err
end

return M
