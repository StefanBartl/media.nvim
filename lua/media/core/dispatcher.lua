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
--- **A second call for the same file/engine/language/task joins the first
--- one in flight**, the same principle `media.core.cache.ensure` applies to
--- PNG renders — added in review, 2026-09-14, after the previous shape let
--- two concurrent calls spawn two `whisper-cli` processes racing on the same
--- output file (`media.engines.whisper_cpp`'s own cleanup deleting the other
--- call's just-written result). Cancelling a joined call only removes that
--- caller's own waiter; the underlying run is only actually cancelled once
--- every joined caller has given up on it, so one caller's `cancel()` cannot
--- take a result away from another.

local uv = vim.uv or vim.loop

local M = {}

---@internal
---@param transcript Media.Transcript
---@return string
local function encode(transcript)
  return vim.json.encode(transcript)
end

---@internal
--- Read `path` off disk without blocking the main loop — libuv's async
--- filesystem calls rather than `io.open`/`read`, because this runs on
--- every cache-hit `media.transcribe` call and a long recording's transcript
--- can run to hundreds of KB; found as a main-loop stall risk in review,
--- 2026-09-14.
---@param path string
---@param callback fun(content: string|nil): nil
local function read_file_async(path, callback)
  uv.fs_open(path, "r", 438, function(open_err, fd)
    if open_err or not fd then
      vim.schedule(function()
        callback(nil)
      end)
      return
    end
    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat then
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          callback(nil)
        end)
        return
      end
      uv.fs_read(fd, stat.size, 0, function(read_err, data)
        uv.fs_close(fd, function() end)
        vim.schedule(function()
          callback((not read_err) and data or nil)
        end)
      end)
    end)
  end)
end

---@internal
---@param cache_path string
---@param callback fun(transcript: Media.Transcript|nil): nil
local function read_cached(cache_path, callback)
  read_file_async(cache_path, function(content)
    if not content then
      callback(nil)
      return
    end
    local ok, doc = pcall(vim.json.decode, content)
    callback((ok and type(doc) == "table") and doc or nil)
  end)
end

---@internal
--- A non-empty string, or `fallback` — collapses a `""` from an empty
--- `engine=`/`lang=` command argument to "use the configured default"
--- rather than letting Lua's `or` treat `""` as a real value (it is
--- truthy). Found in review, 2026-09-14.
---@param s string|nil
---@param fallback string|nil
---@return string|nil
local function nonempty_or(s, fallback)
  if type(s) == "string" and s ~= "" then return s end
  return fallback
end

---@class Media.Transcribe.Job
---@field waiters (fun(transcript: Media.Transcript|nil, err: string|nil): nil)[]
---@field cancel (fun(): nil)|nil

--- The in-flight run for one (path, engine, lang, task) tuple, so a second
--- identical request joins it instead of starting a second `whisper-cli`.
---@type table<string, Media.Transcribe.Job>
local inflight = {}

---@internal
---@param path string
---@param engine string
---@param lang string|nil
---@param task string
---@return string
local function inflight_key(path, engine, lang, task)
  return table.concat({ path, engine, lang or "", task }, "\0")
end

---@internal
--- Register `waiter` on `job` and hand back a handle that removes it again.
--- The one path every caller — the one that starts the job and every one
--- that joins it — registers through, so there is exactly one way a waiter
--- ends up in `job.waiters` and exactly one way it comes back out.
---@param job Media.Transcribe.Job
---@param waiter fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@return Media.Transcribe.Handle
local function join(job, waiter)
  job.waiters[#job.waiters + 1] = waiter
  return {
    cancel = function()
      for i, w in ipairs(job.waiters) do
        if w == waiter then
          table.remove(job.waiters, i)
          break
        end
      end
      -- Only stop the shared run once nobody is left waiting on it — one
      -- caller giving up must not take the result away from another that
      -- has not.
      if #job.waiters == 0 and job.cancel then job.cancel() end
    end,
  }
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

  local requested_engine = nonempty_or(opts.engine, nil) or cfg.engine
  local lang = nonempty_or(opts.lang, nil) or cfg.lang
  local task = nonempty_or(opts.task, nil) or cfg.task
  local cache_enabled = opts.cache ~= false and cfg.cache

  local key = inflight_key(path, requested_engine, lang, task)

  local existing = inflight[key]
  if existing then return join(existing, callback) end

  ---@type Media.Transcribe.Job
  local job = { waiters = {}, cancel = nil }
  inflight[key] = job
  local handle = join(job, callback)

  ---@param transcript Media.Transcript|nil
  ---@param err string|nil
  local function fan_out(transcript, err)
    inflight[key] = nil
    -- Snapshot first: a waiter's own callback may itself start a new
    -- `media.transcribe` on the same key, which would otherwise see a
    -- half-cleared `job.waiters` list.
    local waiters = job.waiters
    for _, waiter in ipairs(waiters) do
      waiter(transcript, err)
    end
  end

  local function run()
    local normalize_handle = require("media.core.normalize").normalize(path, function(wav, nerr)
      if not wav then
        fan_out(nil, nerr)
        return
      end

      local engine, rerr = require("media.core.resolver").resolve(requested_engine)
      if not engine then
        fan_out(nil, rerr)
        return
      end

      local engine_job = engine.transcribe(
        wav,
        { lang = lang, task = task },
        function(transcript, terr)
          if not transcript then
            fan_out(nil, terr)
            return
          end
          if cache_enabled then
            local out = (
              require("media.core.cache").file(
                "transcript",
                path,
                { requested_engine, lang or "auto", task },
                "json"
              )
            )
            if out then
              local fd = io.open(out, "w")
              if fd then
                fd:write(encode(transcript))
                fd:close()
              end
            end
          end
          fan_out(transcript, nil)
        end
      )
      -- The active phase now owns cancellation; normalize's own handle is
      -- no longer the one that matters.
      job.cancel = engine_job and engine_job.cancel or nil
    end)
    -- Cancellable from the moment normalize starts — the gap this closes:
    -- previously a cancel during WAV extraction only skipped the result,
    -- the ffmpeg process ran to completion regardless. Found in review,
    -- 2026-09-14.
    job.cancel = normalize_handle.cancel
  end

  if not cache_enabled then
    run()
    return handle
  end

  local out, cerr = require("media.core.cache").file(
    "transcript",
    path,
    { requested_engine, lang or "auto", task },
    "json"
  )
  if not out then
    vim.schedule(function()
      fan_out(nil, cerr)
    end)
    return handle
  end

  read_cached(out, function(cached)
    -- Every waiter may have cancelled while this async read was in flight —
    -- nothing left to hand a result to, and starting the pipeline now would
    -- be exactly the wasted work `normalize`'s own cancel handle exists to
    -- avoid.
    if #job.waiters == 0 then
      inflight[key] = nil
      return
    end
    if cached then
      fan_out(cached, nil)
      return
    end
    run()
  end)

  return handle
end

return M
