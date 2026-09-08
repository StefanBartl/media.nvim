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

--- Where the PNG for this rendering lives, whether or not it exists yet.
---@param kind string
---@param path string
---@param parts (string|number)[]
---@return string|nil out
---@return string|nil err
function M.file(kind, path, parts)
  local stat = uv.fs_stat(path)
  if not stat then return nil, "no such file: " .. path end
  local key = M.key(kind, path, stat.mtime and stat.mtime.sec or 0, parts)
  return M.dir() .. "/" .. key .. ".png", nil
end

---@type table<string, (fun(png: string|nil, err: string|nil))[]> keyed by output path
local inflight = {}

--- Render `out` unless it is already there, and call back with its path.
---
--- `render(done)` is only ever invoked when the file is genuinely missing and
--- no other caller has it in flight; it reports through `done(err)`.
---@param out string
---@param render fun(done: fun(err: string|nil)): nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.ensure(out, render, callback)
  if uv.fs_stat(out) then
    vim.schedule(function()
      callback(out, nil)
    end)
    return
  end

  local waiting = inflight[out]
  if waiting then
    waiting[#waiting + 1] = callback
    return
  end
  inflight[out] = { callback }

  render(function(err)
    local waiters = inflight[out] or {}
    inflight[out] = nil

    -- A render that reported success but wrote nothing is a failure with a
    -- confusing face: the caller gets a path, hands it to an image drawer, and
    -- the error surfaces two plugins away as "cannot read PNG". ffmpeg does
    -- this when a seek lands past the last frame.
    ---@type string|nil
    local png = out
    ---@type string|nil
    local message = err
    if not err and not uv.fs_stat(out) then
      png, message = nil, "no frame was written — the offset may be past the end of the file"
    elseif err then
      png = nil
    end

    vim.schedule(function()
      for _, cb in ipairs(waiters) do
        cb(png, message)
      end
    end)
  end)
end

--- Delete every rendered still.
---@return integer removed
function M.clear()
  local dir = M.dir()
  local removed = 0
  local handle = uv.fs_scandir(dir)
  if not handle then return 0 end
  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then break end
    if kind == "file" and name:match("%.png$") then
      if uv.fs_unlink(dir .. "/" .. name) then removed = removed + 1 end
    end
  end
  return removed
end

return M
