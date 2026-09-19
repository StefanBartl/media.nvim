---@module 'media.core.frames'
---@brief A run of stills at a fixed rate — the decode half of playback.
---@description
--- `frame` answers "what does this file look like at 10%"; this answers "what
--- do the next two seconds look like". It is the same `vim.system` shape
--- against the same binary with the same cache, and the difference that
--- justifies a second module is entirely in what a *sequence* needs:
---
--- **One process for all of them.** `-vf fps=N` with `-frames:v count` decodes
--- the run in a single pass from one seek. Calling `frame` in a loop would be
--- one process, one seek and one probe per still — and the numbers say what
--- that costs downstream too: sampling 24 PNGs into cells takes 186 ms in one
--- ImageMagick call and 1593 ms in twenty-four (measured 2026-09-08, see
--- `images.blocks`). A sequence that is assembled one item at a time is not a
--- slower sequence, it is the reason there would not be one.
---
--- **It has to be cancellable.** A still that nobody waits for any more is a
--- wasted fifth of a second; a run of frames for a hover that has already gone
--- is a decode that keeps a core busy for as long as it takes. `frame` never
--- needed a handle, this does — `frames()` returns one, and calling `cancel()`
--- kills the process and guarantees the callback never fires.
---
--- **Partial output is a result, not a failure.** Asking for 24 frames from a
--- point one second before the end returns however many exist. The caller gets
--- what was decoded, in order, and decides whether that is enough — refusing
--- the lot because the file ended would make the end of every video
--- unplayable.
---
--- What this does *not* do is play anything: it produces PNGs. The plugin's
--- position on playback is unchanged (see `media.init`) — what changed is that
--- a consumer able to draw cells can now be handed a run of stills to draw.

local M = {}

local uv = vim.uv or vim.loop

--- The argv for one run.
---
--- Pure and public for the same reason `frame.args` is: every interesting
--- decision here is an argument-order decision, and asserting them should not
--- need ffmpeg, a video file or a successful decode.
---
--- `-ss` before `-i` for the keyframe seek (the reasoning is in `frame`), and
--- the two filters go in one `-vf` chain: `fps` first so the scaler runs on
--- the frames that survive rather than on every decoded one.
---@param spec { ffmpeg: string, path: string, pattern: string, from: number|string|nil, count: integer, fps: number, width: integer|nil }
---@return string[]
function M.args(spec)
  local argv = {
    spec.ffmpeg,
    -- Without this ffmpeg inherits Neovim's stdin and can block on it forever
    -- waiting for an answer to a prompt nobody will ever see.
    "-nostdin",
    "-hide_banner",
    "-loglevel",
    "error",
  }

  if spec.from ~= nil then
    argv[#argv + 1] = "-ss"
    argv[#argv + 1] = tostring(spec.from)
  end

  argv[#argv + 1] = "-i"
  argv[#argv + 1] = spec.path

  local filters = { ("fps=%s"):format(spec.fps) }
  if spec.width and spec.width > 0 then
    -- `-2` keeps the aspect ratio and rounds the height to an even number,
    -- as in `frame.args` — harmless for PNG, and the filter string people
    -- copy into an encoder pipeline where an odd height is a hard error.
    filters[#filters + 1] = ("scale=%d:-2"):format(spec.width)
  end
  argv[#argv + 1] = "-vf"
  argv[#argv + 1] = table.concat(filters, ",")

  argv[#argv + 1] = "-frames:v"
  argv[#argv + 1] = tostring(spec.count)

  -- `-y`: every output path is a cache entry keyed by content, so anything
  -- already there is either identical or a leftover from a run that died
  -- mid-write. Prompting about it would hang the process.
  argv[#argv + 1] = "-y"
  argv[#argv + 1] = spec.pattern

  return argv
end

--- The output paths for a run, and the `%0Nd` pattern ffmpeg writes them with.
---
--- Numbered inside the existing cache directory rather than in a directory of
--- their own: `cache.clear()` already removes `*.png` there, and a run that
--- left a directory behind would need its own sweep.
---@param base string cache path for frame 1, ending in ".png"
---@param count integer
---@return string pattern, string[] outs
function M.outputs(base, count)
  local stem = base:gsub("%.png$", "")
  local outs = {}
  for i = 1, count do
    outs[i] = ("%s-%03d.png"):format(stem, i)
  end
  return ("%s-%%03d.png"):format(stem), outs
end

--- The leading run of paths that exist, stopping at the first gap.
---
--- Stopping at the gap rather than collecting everything is deliberate: ffmpeg
--- writes these in order, so a gap means the run ended there. Skipping it and
--- taking later files would hand back a sequence with a jump in it, which
--- plays as a glitch nobody can trace back to here.
---@param outs string[]
---@return string[]
local function existing_prefix(outs)
  local found = {}
  for _, out in ipairs(outs) do
    if not uv.fs_stat(out) then break end
    found[#found + 1] = out
  end
  return found
end

--- A run of stills out of `path`, as PNGs on disk in order.
---
--- The callback runs at most once, on the main loop: exactly once normally,
--- and never after `cancel()`. A fully cached run costs one `fs_stat` per
--- frame and no process at all.
---@param path string
---@param opts Media.FramesOpts|nil
---@param callback fun(pngs: string[]|nil, err: string|nil): nil
---@return Media.Frames.Handle
function M.frames(path, opts, callback)
  opts = opts or {}
  local cfg = require("media.config").get()
  local count = math.max(1, math.floor(opts.count or cfg.frames.count))
  local fps = opts.fps or cfg.frames.fps
  local width = opts.width or cfg.frames.width
  local from = opts.from

  local cancelled = false
  ---@type vim.SystemObj|nil
  local proc = nil
  --- The queue slot, while this is waiting for one. Giving up on a run that has
  --- not started yet has to take it out of the queue, or the decode happens
  --- later for a hover that is long gone.
  ---@type { cancel: fun(): nil }|nil
  local queued_render = nil

  local handle = {
    cancel = function()
      cancelled = true
      if queued_render then
        pcall(queued_render.cancel)
        queued_render = nil
      end
      if proc then
        pcall(function()
          require("media.core.proc").stop(proc)
        end)
        proc = nil
      end
    end,
  }

  ---@param pngs string[]|nil
  ---@param err string|nil
  local function finish(pngs, err)
    if cancelled then return end
    callback(pngs, err)
  end

  local bin = require("media.core.bin").find("ffmpeg")
  if not bin then
    vim.schedule(function()
      finish(nil, "ffmpeg not found — install it, or set `bin.ffmpeg`")
    end)
    return handle
  end

  -- The probe first, for the two things it decides: a percentage `from` needs
  -- a duration, and a file with no moving picture has no run to extract. It is
  -- cached, so this is free from the second call on.
  require("media.core.probe").probe(path, function(probe, perr)
    if cancelled then return end
    if not probe then
      finish(nil, perr)
      return
    end
    if not probe.has_video then
      finish(nil, "no video stream in this file")
      return
    end

    local resolved, aerr = require("media.core.frame").resolve_at(from, probe.duration)
    if aerr then
      finish(nil, aerr)
      return
    end

    local base, cerr = require("media.core.cache").file("frames", path, {
      tostring(resolved),
      count,
      fps,
      width,
    })
    if not base then
      finish(nil, cerr)
      return
    end

    local _, outs = M.outputs(base, count)

    -- Frame 1 is the sentinel the cache joins on: ffmpeg writes the run in
    -- order, so if it exists the run was started, and `existing_prefix` says
    -- how far it got. Using the *last* frame instead would re-render every
    -- run that legitimately produced fewer frames than asked for.
    -- `"high"`: a playback window has a deadline the other renders do not. The
    -- transport asks a second before it needs the next one, and a queue of
    -- stills ahead of it is longer than that. See `media.core.cache`'s header.
    queued_render = require("media.core.cache").ensure(outs[1], function(done, tmp)
      -- `outs[1]`'s own tmp path becomes the base for a whole tmp run: ffmpeg
      -- writes the numbered sequence there, never onto `pattern`/`outs`
      -- directly, for the reason `media.core.cache`'s header gives — a second
      -- Neovim rendering the same key must not land frames in the same place
      -- at the same time.
      local tmp_pattern, tmp_outs = M.outputs(tmp, count)
      local argv = M.args({
        ffmpeg = bin,
        path = path,
        pattern = tmp_pattern,
        from = resolved,
        count = count,
        fps = fps,
        width = width,
      })
      proc = vim.system(argv, { text = true, timeout = cfg.timeout_ms }, function(result)
        proc = nil
        if result.code ~= 0 then
          for _, tout in ipairs(tmp_outs) do
            uv.fs_unlink(tout)
          end
          local stderr = (result.stderr or ""):gsub("%s+$", "")
          done(stderr ~= "" and stderr or ("ffmpeg exited with " .. tostring(result.code)))
          return
        end
        -- Promote the leading run that actually exists, mirroring
        -- `existing_prefix` below: ffmpeg stops writing at end of stream, so a
        -- gap here is where the run ended, not damage. Each rename is atomic,
        -- so a reader following along mid-promotion sees a complete earlier
        -- run or this one, never a half-written frame from either.
        for i, tout in ipairs(tmp_outs) do
          if uv.fs_stat(tout) then
            uv.fs_rename(tout, outs[i])
          else
            break
          end
        end
        for _, tout in ipairs(tmp_outs) do
          uv.fs_unlink(tout)
        end
        done(nil)
      end)
    end, function(_, err)
      queued_render = nil
      if err then
        finish(nil, err)
        return
      end
      local pngs = existing_prefix(outs)
      if #pngs == 0 then
        finish(nil, "no frames were written — the offset may be past the end of the file")
        return
      end
      finish(pngs, nil)
    end, { priority = "high" })
  end)

  return handle
end

return M
