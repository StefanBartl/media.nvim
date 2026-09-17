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
--- first instead.
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
---@field render fun(done: fun(err: string|nil)): nil
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
---@param err string|nil
---@return nil
local function settle(out, err)
  local entry = inflight[out]
  inflight[out] = nil
  running = math.max(0, running - 1)

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
      entry.render(function(err)
        if settled then return end
        settled = true
        settle(out, err)
      end)
    end
  end
end

--- Render `out` unless it is already there, and call back with its path.
---
--- `render(done)` is only ever invoked when the file is genuinely missing, no
--- other caller has it in flight, and a slot is free; it reports through
--- `done(err)`.
---
--- The returned handle drops *this* caller's interest. It does not stop a
--- render that has already started — the caller's own process handle does that
--- (`media.core.frames`) — but a render still waiting for a slot that nobody
--- is left waiting on is removed from the queue rather than run for nobody.
---@param out string
---@param render fun(done: fun(err: string|nil)): nil
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
    if kind == "file" and ext and CACHED_EXTENSIONS[ext] then
      if uv.fs_unlink(dir .. "/" .. name) then removed = removed + 1 end
    end
  end
  return removed
end

return M
