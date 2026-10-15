---@module 'media.core.cache'
---@brief Where rendered stills live, and the key that makes keeping them safe.
---@description
--- A cache of *files*, not of values — the artefact is a PNG, and every
--- consumer of it wants a path to hand to something else. `lib.nvim.cache.disk`
--- is the wrong shape for that (it serializes a table), so this is a directory
--- plus a naming rule.
---
--- **The key is a hash of every input that changes the picture**, the source
--- file's mtime among them. That is what makes an entry safe to keep forever
--- rather than expire: a file that has not changed produces the same key and
--- the same picture, and an edited one produces a different key and renders
--- again. Nothing has to decide when a cached still went stale, because a stale
--- one is never looked up.
---
--- **Concurrent requests for the same output are joined, not raced.** Two
--- hovers over the same path, a picker moving down and back up: the second
--- request arrives while the first render is still out. Two `ffmpeg` processes
--- writing the same file is a corrupt PNG, so the second caller waits on the
--- first instead — within one Neovim. A second Neovim is not joined the same
--- way (its own `inflight` table knows nothing of this one's), so a render
--- never writes `out` directly: it gets a private `<out>.tmp-<pid>` and the
--- rename onto `out` is the one step both sides share, atomically, so a
--- reader never sees a half-written file from either.
---
--- **And requests for *different* outputs are queued, not all started.** That
--- is the other half, and it was missing until 2026-09-17: joining protects one
--- output from two writers, but nothing bounded how many distinct renders were
--- in flight. Holding a paging key down in a video hover measured at **30
--- concurrent `ffmpeg` processes**, and 60 with `prefetch_frame` behind each
--- press. Every one of them is a decode competing with the others for the same
--- cores, so the storm is slower in wall time than the queue that replaces it —
--- and it takes the editor with it.
---
--- **Three priorities, because one of the callers has a deadline.** A plain
--- FIFO would put a playback window behind whatever stills were already
--- waiting: thirty of them at four at a time is about a second and a half,
--- against the one second of lead `hover.nvim`'s transport asks with. A late
--- window is a visible stutter, which is exactly what the rolling window was
--- built to remove. So `frames` jumps the queue, the things somebody is waiting
--- on come next, and a prefetch — work nobody has asked for yet — goes last.
---
--- A prefetch that never runs because the queue stayed busy is **not**
--- starvation to be fixed: the real request behind it does the work, which is
--- the state the plugin was in before prefetching existed.

local M = {}

local uv = vim.uv or vim.loop

---@return string
function M.dir()
  local cfg = require("media.config").get()
  local dir = cfg.cache.dir
  if type(dir) ~= "string" or dir == "" then dir = vim.fn.stdpath("cache") .. "/media.nvim" end
  local ok, mkdirp = pcall(require, "lib.nvim.fs.mkdirp")
  if ok then
    mkdirp(dir)
  else
    vim.fn.mkdir(dir, "p")
  end
  return dir
end

--- The file name for one rendering, without directory or extension.
---
--- A pure function, and public, so the key is assertable without ffmpeg
--- installed and without a media file. What has to hold is that every input
--- reaches the key: two renderings that differ in any argument must not share a
--- name, because a collision serves the wrong picture for as long as the cache
--- lives — which is forever.
---@param kind string  # "frame", "sheet"
---@param path string
---@param mtime integer seconds
---@param parts (string|number)[] everything else that changes the output
---@return string
function M.key(kind, path, mtime, parts)
  local fields = { kind, path, tostring(mtime) }
  for _, part in ipairs(parts) do
    fields[#fields + 1] = tostring(part)
  end
  return vim.fn.sha256(table.concat(fields, ":"))
end

--- Where the rendering for this key lives, whether or not it exists yet.
---@param kind string
---@param path string
---@param parts (string|number)[]
---@param ext string|nil  # "png" (default), "wav", "json", …
---@return string|nil out
---@return string|nil err
function M.file(kind, path, parts, ext)
  local stat = uv.fs_stat(path)
  if not stat then return nil, "no such file: " .. path end
  local key = M.key(kind, path, stat.mtime and stat.mtime.sec or 0, parts)
  return M.dir() .. "/" .. key .. "." .. (ext or "png"), nil
end

--- Where a render sits in the queue.
---
--- `"high"` is for a caller with a deadline — today that is `media.core.frames`
--- feeding a playback window, which must arrive before the one on screen runs
--- out. `"low"` is for work nobody has asked for yet, which today is
--- `media.core.frame.prefetch`. Everything in between is somebody looking at a
--- spinner.
---@alias Media.Cache.Priority "high"|"normal"|"low"

---@internal
--- One render waiting for a slot, or in one.
---@class Media.Cache.Entry
---@field waiters (fun(png: string|nil, err: string|nil): nil)[]
---@field render fun(done: fun(err: string|nil), tmp: string): nil
---@field priority Media.Cache.Priority
---@field started boolean

---@type table<string, Media.Cache.Entry> keyed by output path
local inflight = {}

--- Output paths waiting for a slot, highest priority first within each list.
---@type table<Media.Cache.Priority, string[]>
local queued = { high = {}, normal = {}, low = {} }

--- The order the queues are drained in.
local ORDER = { "high", "normal", "low" }

local running = 0

---@internal
--- A path beside `out` that only this process writes to — ffmpeg's real
--- destination, never `out` itself. Unique per output because `inflight`
--- already serialises this process's own callers onto one render per `out`;
--- what it cannot see is a second Neovim doing the same thing, and the pid
--- is what keeps the two from landing on the same name.
---
--- The pid goes *before* the extension, not after: ffmpeg (and every muxer
--- that picks its output format from the filename rather than an explicit
--- `-f`) needs the real extension last. `out.png.tmp-1234` ends in
--- `.tmp-1234`, which ffmpeg does not recognise, and it refuses to write —
--- "Unable to choose an output format" — for every renderer here, silently,
--- since none of them pass `-f`. Found via a video hover that never opened,
--- 2026-09-19.
---@param out string
---@return string
local function tmp_for(out)
  local base, ext = out:match("^(.*)%.([^./\\]+)$")
  if base then return base .. ".tmp-" .. uv.os_getpid() .. "." .. ext end
  return out .. ".tmp-" .. uv.os_getpid()
end

---@internal
--- How many renders may be in flight at once.
---@return integer
local function limit()
  local ok, cfg = pcall(function()
    return require("media.config").get().render_concurrency
  end)
  if ok and type(cfg) == "number" and cfg >= 1 then return math.floor(cfg) end
  return 4
end

---@internal
--- Remove `out` from whichever queue holds it.
---@param out string
---@return nil
local function dequeue(out)
  for _, priority in ipairs(ORDER) do
    local list = queued[priority]
    for i, waiting in ipairs(list) do
      if waiting == out then
        table.remove(list, i)
        return
      end
    end
  end
end

---@internal
--- The next output to render, or nil when every queue is empty.
---@return string|nil
local function take()
  for _, priority in ipairs(ORDER) do
    local list = queued[priority]
    if #list > 0 then return table.remove(list, 1) end
  end
  return nil
end

local pump

---@internal
--- Finish one render: hand the result to everyone waiting on it, free the slot,
--- and start whatever is next.
---@param out string
---@param tmp string where the render actually wrote, per `tmp_for`
---@param err string|nil
---@return nil
local function settle(out, tmp, err)
  local entry = inflight[out]
  inflight[out] = nil
  running = math.max(0, running - 1)

  -- The move onto `out` is the one step two racing Neovims share, and it is
  -- atomic (ERR-31): a reader never observes a half-written file from either
  -- side, and it folds in ffmpeg's "exited 0, wrote nothing" case below for
  -- free — renaming a `tmp` that nothing ever wrote simply fails. A renderer
  -- with its own multi-file promotion (`media.core.frames`) has already moved
  -- what it produced by the time this runs, so the rename here is then a
  -- harmless no-op against a `tmp` that was never a real path.
  if not err then uv.fs_rename(tmp, out) end
  uv.fs_unlink(tmp)

  -- A render that reported success but wrote nothing is a failure with a
  -- confusing face: the caller gets a path, hands it to an image drawer, and
  -- the error surfaces two plugins away as "cannot read PNG". ffmpeg does this
  -- when a seek lands past the last frame.
  ---@type string|nil
  local png = out
  ---@type string|nil
  local message = err
  if not err and not uv.fs_stat(out) then
    png, message = nil, "no frame was written — the offset may be past the end of the file"
  elseif err then
    png = nil
  end

  local waiters = entry and entry.waiters or {}
  vim.schedule(function()
    for _, cb in ipairs(waiters) do
      cb(png, message)
    end
  end)

  pump()
end

---@internal
--- Start renders until the slots are full or nothing is waiting.
---@return nil
function pump()
  while running < limit() do
    local out = take()
    if not out then return end

    local entry = inflight[out]
    -- Cancelled between being queued and reaching the front: its `inflight`
    -- row is already gone, so there is nobody to render for.
    if entry then
      entry.started = true
      running = running + 1

      -- `done` guarded against a second call: a render that reported twice
      -- would free two slots and let the queue run over its own limit, which
      -- is the one failure mode a concurrency bound must not have.
      local settled = false
      local tmp = tmp_for(out)
      local function finish(err)
        if settled then return end
        settled = true
        settle(out, tmp, err)
      end
      -- `pcall`ed: every renderer spawns a process with a bare `vim.system`,
      -- which raises rather than erroring when the binary cannot be spawned
      -- (a misconfigured `bin.ffmpeg`). Uncaught here, that raise would leave
      -- `running` incremented forever with nothing left to bring it back
      -- down — the queue wedges for the rest of the session.
      local ok, spawn_err = pcall(entry.render, finish, tmp)
      if not ok then finish(tostring(spawn_err)) end
    end
  end
end

--- Render `out` unless it is already there, and call back with its path.
---
--- `render(done, tmp)` is only ever invoked when the file is genuinely
--- missing, no other caller has it in flight, and a slot is free; it reports
--- through `done(err)`. `tmp` is where it must actually write — never `out`
--- itself, which a second Neovim process could be writing at the same moment
--- (ERR-31); `settle` moves the finished file onto `out` atomically once
--- `done` reports success.
---
--- The returned handle drops *this* caller's interest. It does not stop a
--- render that has already started — the caller's own process handle does that
--- (`media.core.frames`) — but a render still waiting for a slot that nobody
--- is left waiting on is removed from the queue rather than run for nobody.
---@param out string
---@param render fun(done: fun(err: string|nil), tmp: string): nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@param opts { priority: Media.Cache.Priority }|nil
---@return { cancel: fun(): nil }
function M.ensure(out, render, callback, opts)
  local noop = {
    cancel = function() end,
  }

  if uv.fs_stat(out) then
    vim.schedule(function()
      callback(out, nil)
    end)
    return noop
  end

  local entry = inflight[out]
  if entry then
    entry.waiters[#entry.waiters + 1] = callback
  else
    local priority = opts and opts.priority or "normal"
    if not queued[priority] then priority = "normal" end
    ---@type Media.Cache.Entry
    entry = { waiters = { callback }, render = render, priority = priority, started = false }
    inflight[out] = entry
    queued[priority][#queued[priority] + 1] = out
    pump()
  end

  return {
    cancel = function()
      local current = inflight[out]
      if current ~= entry then return end
      for i, waiter in ipairs(entry.waiters) do
        if waiter == callback then
          table.remove(entry.waiters, i)
          break
        end
      end
      -- Only once nobody is left, and only while it has not started: one
      -- caller giving up must not take a render away from another that has
      -- not, and a process already spawned is the caller's to stop.
      if #entry.waiters == 0 and not entry.started then
        dequeue(out)
        inflight[out] = nil
      end
    end,
  }
end

--- How many renders are running and waiting right now.
---
--- For tests and `:checkhealth`, not for callers to branch on: a queue depth
--- read a moment ago is not a fact a decision can rest on.
---@return integer running
---@return integer waiting
function M.load()
  local waiting = 0
  for _, priority in ipairs(ORDER) do
    waiting = waiting + #queued[priority]
  end
  return running, waiting
end

--- Extensions this cache is allowed to remove — every shape a rendering here
--- can take. An allowlist rather than "everything in the directory", even
--- though nothing else is meant to write there, for the same reason `M.file`
--- takes an explicit `ext`: a typo in a future caller should not turn
--- `:Media cache clear` into a directory wipe.
---@type table<string, true>
local CACHED_EXTENSIONS = { png = true, wav = true, json = true }

--- Delete every rendered still, converted audio track and cached transcript.
---
--- Also sweeps a `tmp_for` leftover: normally `settle` removes its own, but a
--- Neovim killed mid-render (not a graceful `:qa`) leaves one behind with no
--- extension this cache would otherwise recognise as its own.
---@return integer removed
function M.clear()
  local dir = M.dir()
  local removed = 0
  local handle = uv.fs_scandir(dir)
  if not handle then return 0 end
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then break end
    local ext = name:match("%.([^.]+)$")
    local orphaned_tmp = name:match("%.tmp%-%d+") ~= nil
    if kind == "file" and ((ext and CACHED_EXTENSIONS[ext]) or orphaned_tmp) then
      if uv.fs_unlink(dir .. "/" .. name) then removed = removed + 1 end
    end
  end
  return removed
end

-- ─── bounding the cache ─────────────────────────────────────────────────────
--
-- The key makes an entry safe to keep, not cheap to keep: one hour of audio
-- is a ~115 MB WAV, and an entry whose source changed is never read again and
-- never removed. So the directory is trimmed once per session, in the
-- background, by age and by total size (oldest first). The WAV stays a cache
-- entry rather than a throw-away intermediate: a second run with another
-- engine or language needs it again, and ffmpeg over an hour of audio costs
-- more than the disk; when the size limit bites, the oldest WAV goes first
-- like every other file.

---A leftover `<out>.tmp-<pid>` younger than this may belong to a render of another Neovim.
local ORPHAN_TMP_AGE = 3600

---@class Media.Cache.File
---@field path string
---@field name string
---@field size integer
---@field mtime integer seconds
---@field tmp boolean  # a `.tmp-<pid>` leftover

---@class Media.Cache.Limits
---@field max_age_days number|nil
---@field max_mb number|nil

---@param v any
---@return number|nil
local function positive(v)
  if type(v) == "number" and v > 0 then return v end
  return nil
end

---The configured limits; `nil` / `0` / anything not a positive number means unlimited.
---@return Media.Cache.Limits
function M.limits()
  local cfg = require("media.config").get().cache or {}
  return { max_age_days = positive(cfg.max_age_days), max_mb = positive(cfg.max_mb) }
end

---Which files to delete. Pure: no I/O, so the rule is assertable without a directory.
---Foreign files never appear in `files`; the caller filters by `CACHED_EXTENSIONS`.
---@param files Media.Cache.File[]
---@param now integer seconds
---@param limits Media.Cache.Limits
---@param busy? table<string, true>  # output paths being rendered right now: never touched
---@return Media.Cache.File[] doomed
function M.plan_prune(files, now, limits, busy)
  busy = busy or {}
  local doomed, keep = {}, {}
  local max_age = limits.max_age_days and limits.max_age_days * 86400
  for _, f in ipairs(files) do
    if f.tmp then
      local base, ext = f.path:match("^(.*)%.tmp%-%d+%.([^./\\]+)$")
      local out = base and (base .. "." .. ext) or f.path:match("^(.*)%.tmp%-%d+$")
      if not (out and busy[out]) and now - f.mtime > ORPHAN_TMP_AGE then doomed[#doomed + 1] = f end
    elseif not busy[f.path] then
      -- (an output being written right now is not ours to judge)
      if max_age and now - f.mtime > max_age then
        doomed[#doomed + 1] = f
      else
        keep[#keep + 1] = f
      end
    end
  end
  local max_bytes = limits.max_mb and limits.max_mb * 1048576
  if max_bytes then
    local total = 0
    for _, f in ipairs(keep) do
      total = total + f.size
    end
    if total > max_bytes then
      table.sort(keep, function(a, b)
        if a.mtime ~= b.mtime then return a.mtime < b.mtime end
        return a.path < b.path
      end)
      for _, f in ipairs(keep) do
        if total <= max_bytes then break end
        doomed[#doomed + 1] = f
        total = total - f.size
      end
    end
  end
  return doomed
end

---@param name string
---@return boolean tmp
---@return boolean ours
local function classify(name)
  -- Every file this cache writes is named after a sha256 key (`M.key`), a frame run adds `-NNN`: a name
  -- that does not start with 64 hex digits is somebody else's file (a custom `cache.dir` may hold the
  -- user's own png or json), and the automatic trim must never touch it.
  local hex = name:match("^(%x+)")
  if not hex or #hex < 64 then return false, false end
  local tmp = name:match("%.tmp%-%d+") ~= nil
  local ext = name:match("%.([^.]+)$")
  return tmp, tmp or (ext ~= nil and CACHED_EXTENSIONS[ext] == true)
end

---List the files of the cache directory this cache owns, without blocking the loop.
---@param dir string
---@param callback fun(files: Media.Cache.File[]): nil  # called from a libuv callback
local function scan(dir, callback)
  uv.fs_scandir(dir, function(err, handle)
    if err or not handle then return callback({}) end
    local names = {}
    while true do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then break end
      local _, ours = classify(name)
      if ours and (kind == "file" or kind == nil) then names[#names + 1] = name end
    end
    local files, pending = {}, #names
    if pending == 0 then return callback(files) end
    for _, name in ipairs(names) do
      local path = dir .. "/" .. name
      uv.fs_stat(path, function(_, st)
        if st and st.type == "file" then
          files[#files + 1] = {
            path = path,
            name = name,
            size = st.size,
            mtime = st.mtime and st.mtime.sec or 0,
            tmp = (classify(name)),
          }
        end
        pending = pending - 1
        if pending == 0 then callback(files) end
      end)
    end
  end)
end

---@class Media.Cache.PruneResult
---@field skipped? "busy"|"unlimited"
---@field removed integer
---@field freed integer  # bytes
---@field kept integer
---@field bytes integer  # bytes left

---Trim the cache by the configured limits (or `opts.limits`), oldest first.
---
---Does nothing while a render is running or queued, so nothing it is about to
---read or rename can disappear; the caller may try again later.
---@param opts? { limits?: Media.Cache.Limits, now?: integer }
---@param callback? fun(result: Media.Cache.PruneResult): nil  # on the main loop
---@return nil
function M.prune(opts, callback)
  opts = opts or {}
  callback = callback or function() end
  local limits = opts.limits or M.limits()
  local empty = { removed = 0, freed = 0, kept = 0, bytes = 0 }
  if not limits.max_age_days and not limits.max_mb then
    return vim.schedule(function()
      callback(vim.tbl_extend("force", empty, { skipped = "unlimited" }))
    end)
  end
  local running_now, waiting_now = M.load()
  if running_now > 0 or waiting_now > 0 then
    return vim.schedule(function()
      callback(vim.tbl_extend("force", empty, { skipped = "busy" }))
    end)
  end
  local dir = M.dir()
  local now = opts.now or os.time()
  scan(dir, function(files)
    local busy = {}
    for out in pairs(inflight) do
      busy[out] = true
    end
    local doomed = M.plan_prune(files, now, limits, busy)
    local gone, removed, freed = {}, 0, 0
    for _, f in ipairs(doomed) do
      if uv.fs_unlink(f.path) then
        gone[f.path] = true
        removed = removed + 1
        freed = freed + f.size
      end
    end
    local kept, bytes = 0, 0
    for _, f in ipairs(files) do
      if not gone[f.path] and not f.tmp then
        kept = kept + 1
        bytes = bytes + f.size
      end
    end
    vim.schedule(function()
      callback({ removed = removed, freed = freed, kept = kept, bytes = bytes })
    end)
  end)
end

local prune_state = { requested = false }

---Trim the cache once per session, shortly after startup, and only when nothing is rendering:
---a busy queue is retried a minute later, a few times, then left for the next session.
---@param delay_ms? integer  # default 5000
---@return nil
function M.prune_once(delay_ms)
  if prune_state.requested then return end
  local cfg = require("media.config").get().cache or {}
  if cfg.enabled == false then return end
  prune_state.requested = true
  local tries = 0
  local function attempt()
    tries = tries + 1
    M.prune(nil, function(result)
      if result.skipped == "busy" and tries < 5 then vim.defer_fn(attempt, 60000) end
    end)
  end
  vim.defer_fn(attempt, delay_ms or 5000)
end

---Number of cached files and their total size, for `:checkhealth`. Reads the directory
---synchronously: a health check is allowed to wait.
---@return integer files
---@return integer bytes
function M.stats()
  local dir = M.dir()
  local handle = uv.fs_scandir(dir)
  local files, bytes = 0, 0
  if not handle then return 0, 0 end
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then break end
    local tmp, ours = classify(name)
    if ours and not tmp and (kind == "file" or kind == nil) then
      local st = uv.fs_stat(dir .. "/" .. name)
      if st then
        files = files + 1
        bytes = bytes + st.size
      end
    end
  end
  return files, bytes
end

return M
