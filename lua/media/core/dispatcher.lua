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
--- **It reports which step it is on, and reports nothing else.** An hour of
--- audio is minutes of work, so a caller has to be able to say more than
--- "working" — but the indicator itself is not this module's business. What
--- crosses the line is `opts.on_phase`, a plain callback carrying a
--- `Media.Transcribe.Progress`; `media.bindings.usrcmds` is what turns that
--- into a `lib.nvim.progress` handle, because the *command* is the UI. Putting
--- the handle here would open a float over `hover.nvim` every time it asked
--- for a transcript in the background.
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
--- `vim.json.encode` can throw (a transcript field that is not
--- JSON-representable) — every other JSON round-trip in this codebase
--- (`read_cached` below, `media.engines.whisper_cpp`, `media.core.probe`) is
--- `pcall`-guarded, so this is too, for the same reason: a bad transcript
--- must fail as an error string, not as an uncaught Lua error out of a
--- libuv callback.
---@param transcript Media.Transcript
---@return string|nil json
---@return string|nil err
local function encode(transcript)
  local ok, result = pcall(vim.json.encode, transcript)
  if ok then return result, nil end
  return nil, tostring(result)
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
--- Write `content` to `path` without blocking the main loop — the write side
--- of `read_file_async` above, and needed for the same reason: a long
--- recording's transcript can run to hundreds of KB, and `io.open`/`write`
--- would stall the editor for the length of that write right after
--- transcription (already minutes long) finally finishes. Best-effort and
--- fire-and-forget: this is a cache write for a *future* call, so a failure
--- here costs the next call a cache hit, not this one its result — nothing
--- calls back. Found in review, 2026-09-15.
---@param path string
---@param content string
---@return nil
local function write_file_async(path, content)
  uv.fs_open(path, "w", 420, function(open_err, fd)
    if open_err or not fd then return end
    uv.fs_write(fd, content, 0, function()
      uv.fs_close(fd, function() end)
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

--- One caller waiting on a run: what to hand the result to, and — optionally
--- — what to tell about the step the run is currently on.
---
--- A table rather than the bare callback this used to be, because progress is
--- *per caller*. Two callers joining the same run each get their own
--- indicator, and a `hover.nvim` that asked for a transcript headlessly must
--- not inherit the float a `:Media transcribe` opened for itself.
---@class Media.Transcribe.Waiter
---@field done fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@field on_phase (fun(info: Media.Transcribe.Progress): nil)|nil

---@class Media.Transcribe.Job
---@field waiters Media.Transcribe.Waiter[]
---@field cancel (fun(): nil)|nil
---@field phase Media.Transcribe.Progress|nil  # the last step reported, replayed to a late joiner

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
--- Register `waiter` on `job` (tracked under `key` in `inflight`) and hand
--- back a handle that removes it again. The one path every caller — the one
--- that starts the job and every one that joins it — registers through, so
--- there is exactly one way a waiter ends up in `job.waiters` and exactly
--- one way it comes back out.
---@param key string
---@param job Media.Transcribe.Job
---@param waiter Media.Transcribe.Waiter
---@return Media.Transcribe.Handle
local function join(key, job, waiter)
  job.waiters[#job.waiters + 1] = waiter

  -- A caller that joins a run already under way is told where it is, rather
  -- than watching an indicator that says nothing until the next step happens
  -- to begin — which on a long file is minutes of a progress display that
  -- looks stuck.
  if job.phase and waiter.on_phase then
    local phase, on_phase = job.phase, waiter.on_phase
    vim.schedule(function()
      on_phase(phase)
    end)
  end

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
      if #job.waiters == 0 then
        if job.cancel then job.cancel() end
        -- `job.cancel` (normalize's or the engine's own handle) marks itself
        -- cancelled and then permanently suppresses its own callback — the
        -- only place this module clears `inflight` otherwise
        -- (`fan_out`) therefore never runs for a job every waiter gave up
        -- on. Without this, a later call for the same key would join a job
        -- that will never produce a result — a permanent, silent hang.
        -- Found in review, 2026-09-15.
        if inflight[key] == job then inflight[key] = nil end
      end
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

  ---@type Media.Transcribe.Waiter
  local waiter = { done = callback, on_phase = opts.on_phase }

  local existing = inflight[key]
  if existing then return join(key, existing, waiter) end

  ---@type Media.Transcribe.Job
  local job = { waiters = {}, cancel = nil, phase = nil }
  inflight[key] = job
  local handle = join(key, job, waiter)

  --- Tell every waiter which step the run has reached.
  ---
  --- Remembered on the job as well as announced, so a caller joining later
  --- learns it too (see `join`). Each `on_phase` is `pcall`ed: it is a
  --- consumer's UI callback, and a run that has already survived minutes of
  --- decoding must not be lost to an error in something drawing a spinner.
  ---@param phase Media.Transcribe.Phase
  ---@param engine string|nil
  local function fan_phase(phase, engine)
    ---@type Media.Transcribe.Progress
    local info = { phase = phase, engine = engine }
    job.phase = info
    -- Snapshot first, for the reason `fan_out` does: an `on_phase` may cancel
    -- its own handle — a float that gives up on the step it was just told
    -- about — and `join`'s cancel does a `table.remove` on this very list.
    -- Removing during `ipairs` skips the next waiter silently.
    local waiters = {}
    for i, w in ipairs(job.waiters) do
      waiters[i] = w
    end
    for _, w in ipairs(waiters) do
      if w.on_phase then pcall(w.on_phase, info) end
    end
  end

  ---@param transcript Media.Transcript|nil
  ---@param err string|nil
  local function fan_out(transcript, err)
    inflight[key] = nil
    -- Snapshot first: a waiter's own callback may itself start a new
    -- `media.transcribe` on the same key, which would otherwise see a
    -- half-cleared `job.waiters` list.
    local waiters = job.waiters
    for _, w in ipairs(waiters) do
      w.done(transcript, err)
    end
  end

  local function run()
    -- The first of the two long steps. Both are announced as they *start*,
    -- not as they finish: the point of the report is the wait that follows
    -- it, and a step named on completion labels the one already over.
    fan_phase("normalize", nil)

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

      -- The resolved engine, not the requested one: a fallback chain means
      -- the two can differ, and the id worth showing is the one actually
      -- about to spend the next several minutes.
      fan_phase("transcribe", engine.id)

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
              local json = encode(transcript)
              if json then write_file_async(out, json) end
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
