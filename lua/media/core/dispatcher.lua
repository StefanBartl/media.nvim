---@module 'media.core.dispatcher'
---@brief probe → normalize → transcribe → cache, behind one cancellable call.
---@description
--- The whole of what `media.transcribe` does, in one place, because a caller
--- does not care which of "still extracting the WAV" and "whisper.cpp is
--- still running" is the current step when it wants to give up — one handle,
--- one `cancel()`.
---
--- **A cache hit skips both steps entirely**, read back from the JSON this
--- module itself wrote on a previous run. Keyed like every other cache entry
--- here — the source file's mtime, plus the engine/language/task that
--- produced it — so an edited file, a different engine or a different
--- language each get their own entry rather than serving a stale answer.
---
--- **Not de-duplicated against a second call in flight**, unlike
--- `media.core.cache.ensure`'s PNG renders. A transcription is a real
--- external process running for minutes; joining a second request onto the
--- first would need to hand back a shared job whose `cancel()` cannot belong
--- to only one caller. Phase 0 accepts a caller triggering a second
--- transcription of the same file as a caller's own mistake, the way
--- `media.frame` would if called twice with two different offsets — this can
--- be revisited if it turns out to matter in practice.

local M = {}

---@internal
---@param transcript Media.Transcript
---@return string
local function encode(transcript)
  return vim.json.encode(transcript)
end

---@internal
---@param cache_path string
---@return Media.Transcript|nil
local function read_cached(cache_path)
  local fd = io.open(cache_path, "r")
  if not fd then return nil end
  local content = fd:read("*a")
  fd:close()
  local ok, doc = pcall(vim.json.decode, content)
  if not ok or type(doc) ~= "table" then return nil end
  return doc
end

--- Transcribe `path`: probe it, extract a WAV, run it through the resolved
--- engine, cache the result.
---@param path string
---@param opts Media.TranscribeOpts|nil
---@param callback fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@return Media.Transcribe.Handle
function M.transcribe(path, opts, callback)
  opts = opts or {}
  local cfg = require("media.config").get().transcribe

  local cancelled = false
  ---@type (fun(): nil)|nil
  local cancel_job = nil
  local handle = {
    cancel = function()
      cancelled = true
      if cancel_job then
        pcall(cancel_job)
        cancel_job = nil
      end
    end,
  }

  ---@param transcript Media.Transcript|nil
  ---@param err string|nil
  local function finish(transcript, err)
    if cancelled then return end
    callback(transcript, err)
  end

  local requested_engine = opts.engine or cfg.engine
  local lang = opts.lang or cfg.lang
  local task = opts.task or cfg.task
  local cache_enabled = opts.cache ~= false and cfg.cache

  local cache_path
  if cache_enabled then
    local out, cerr = require("media.core.cache").file(
      "transcript",
      path,
      { requested_engine, lang or "auto", task },
      "json"
    )
    if out then
      cache_path = out
      local cached = read_cached(out)
      if cached then
        vim.schedule(function()
          finish(cached, nil)
        end)
        return handle
      end
    elseif cerr then
      vim.schedule(function()
        finish(nil, cerr)
      end)
      return handle
    end
  end

  require("media.core.normalize").normalize(path, function(wav, nerr)
    if cancelled then return end
    if not wav then
      finish(nil, nerr)
      return
    end

    local engine, rerr = require("media.core.resolver").resolve(requested_engine)
    if not engine then
      finish(nil, rerr)
      return
    end

    local job = engine.transcribe(wav, { lang = lang, task = task }, function(transcript, terr)
      if not transcript then
        finish(nil, terr)
        return
      end
      if cache_enabled and cache_path then
        local fd = io.open(cache_path, "w")
        if fd then
          fd:write(encode(transcript))
          fd:close()
        end
      end
      finish(transcript, nil)
    end)
    cancel_job = job and job.cancel or nil
  end)

  return handle
end

return M
