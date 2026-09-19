---@module 'media.core.frame'
---@brief One still out of a media file, as a PNG on disk.
---@description
--- The one operation that makes a video showable to something that can only
--- draw pictures. Everything above it — a hover float, a picker preview, a
--- gallery — carries on treating the result as an ordinary image file, because
--- by then it is one.
---
--- **`-ss` goes before `-i`, and that is the whole performance story.** As an
--- input option it is a seek: ffmpeg jumps to the nearest keyframe before the
--- offset and starts decoding there. After `-i` it is an output option, and
--- ffmpeg decodes the file from the beginning and discards everything up to the
--- offset — same picture, and on a two-hour file the difference is between a
--- fifth of a second and half a minute. The cost of the fast form is that the
--- still can land a keyframe early; for a poster frame that is not a cost at
--- all.
---
--- **Rotation needs no argument.** ffmpeg auto-rotates from the display matrix
--- on decode, so a portrait phone video comes out upright here, and
--- `media.core.probe` reports the matching display dimensions. The two agree
--- because both defer to the file.
---
--- **Cover art is extracted, not seeked.** An mp3's album art is a
--- single-frame video stream; asking to seek ten percent into it lands past its
--- only frame and writes nothing.

local M = {}

--- The argv for one extraction.
---
--- Pure, and public, for the reason `pdfport.core.rasterize.args` is: the
--- interesting decisions in this module are all in the argument order, and an
--- assertion about them should not need ffmpeg installed, a video file, or a
--- successful decode.
---@param spec { ffmpeg: string, path: string, out: string, at: number|string|nil, width: integer|nil, cover: boolean|nil }
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

  -- The seek belongs before `-i` (see the module note) — and is skipped
  -- entirely for cover art, which has exactly one frame at offset zero.
  if not spec.cover and spec.at ~= nil then
    argv[#argv + 1] = "-ss"
    argv[#argv + 1] = tostring(spec.at)
  end

  argv[#argv + 1] = "-i"
  argv[#argv + 1] = spec.path

  if spec.cover then
    -- The first video stream by explicit selection: a file with cover art
    -- usually leads with the audio stream, and ffmpeg's default mapping for a
    -- single image output would pick that.
    argv[#argv + 1] = "-map"
    argv[#argv + 1] = "0:v"
  end

  argv[#argv + 1] = "-frames:v"
  argv[#argv + 1] = "1"

  if spec.width and spec.width > 0 then
    -- `-2` rather than `-1` for the height: it keeps the aspect ratio and
    -- rounds to an even number. PNG does not care, but this filter string is
    -- the one people copy into a pipeline that encodes video, where an odd
    -- height is a hard error in most encoders.
    argv[#argv + 1] = "-vf"
    argv[#argv + 1] = ("scale=%d:-2"):format(spec.width)
  end

  -- `-y`: the output path is a cache entry keyed by content, so anything
  -- already there is either identical or a leftover from a run that died
  -- mid-write. Prompting about it would hang the process.
  argv[#argv + 1] = "-y"
  argv[#argv + 1] = spec.out

  return argv
end

--- Turn a configured offset into something `-ss` accepts.
---
--- Three shapes, and the third is why this is not `tonumber`: a number is
--- seconds, `"10%"` is a fraction of the duration and needs one, and anything
--- else is handed to ffmpeg untouched — which makes `"00:01:23.5"` work,
--- because that is a timestamp ffmpeg has always understood and there is no
--- reason for this plugin to be the one that rejects it.
---
--- The clamp matters more than it looks: a percentage of a duration that
--- ffprobe rounded up lands past the last frame, ffmpeg then writes no file at
--- all, and the failure reads as "the renderer is broken" rather than "the seek
--- was one frame too far".
---@param at number|string|nil
---@param duration number|nil
---@return number|string|nil resolved
---@return string|nil err
function M.resolve_at(at, duration)
  if at == nil then return nil, nil end

  local seconds
  if type(at) == "number" then
    seconds = at
  elseif type(at) == "string" then
    local percent = at:match("^%s*([%d%.]+)%s*%%%s*$")
    if percent then
      local fraction = tonumber(percent)
      if not fraction then return nil, "not a percentage: " .. at end
      if not duration then
        return nil, "a percentage offset needs a duration, and this file reports none"
      end
      seconds = duration * fraction / 100
    else
      return at, nil
    end
  else
    return nil, "offset must be a number or a string"
  end

  if seconds < 0 then seconds = 0 end
  if duration and duration > 0 and seconds >= duration then
    seconds = math.max(0, duration - 0.25)
  end
  return seconds, nil
end

--- A PNG of one still out of `path`.
---
--- The callback runs exactly once, on the main loop. A cache hit is the common
--- case after the first look at a file and costs one `fs_stat`.
---@param path string
---@param opts Media.FrameOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.frame(path, opts, callback)
  opts = opts or {}
  local cfg = require("media.config").get()
  local at = opts.at ~= nil and opts.at or cfg.frame.at
  local width = opts.width or cfg.frame.width

  local bin = require("media.core.bin").find("ffmpeg")
  if not bin then
    vim.schedule(function()
      callback(nil, "ffmpeg not found — install it, or set `bin.ffmpeg`")
    end)
    return
  end

  -- The probe comes first even when the offset needs no duration, because its
  -- other answer decides the argv: a file whose only picture is cover art must
  -- not be seeked into. It is cached, so this is free from the second call on.
  require("media.core.probe").probe(path, function(probe, perr)
    if not probe then
      callback(nil, perr)
      return
    end
    if not probe.has_video and not probe.has_cover then
      callback(nil, "no picture in this file")
      return
    end

    local cover = not probe.has_video and probe.has_cover
    local resolved, aerr = M.resolve_at(cover and 0 or at, probe.duration)
    if aerr then
      callback(nil, aerr)
      return
    end

    local out, cerr = require("media.core.cache").file("frame", path, {
      tostring(resolved),
      width,
      cover and "cover" or "video",
    })
    if not out then
      callback(nil, cerr)
      return
    end

    require("media.core.cache").ensure(out, function(done, tmp)
      local argv = M.args({
        ffmpeg = bin,
        path = path,
        out = tmp,
        at = resolved,
        width = width,
        cover = cover,
      })
      vim.system(argv, { text = true, timeout = cfg.timeout_ms }, function(result)
        if result.code ~= 0 then
          local stderr = (result.stderr or ""):gsub("%s+$", "")
          done(stderr ~= "" and stderr or ("ffmpeg exited with " .. tostring(result.code)))
          return
        end
        done(nil)
      end)
    end, callback, { priority = opts.priority })
  end)
end

--- Render a still nobody has asked for yet, and forget about it.
---
--- **The offer, not the decision.** A consumer stepping through a file knows
--- where the reader is going next and this module does not; the state belongs
--- to whoever owns the window, because two consumers scrubbing the same file
--- must not share a cursor (ROADMAP.md, "Frame stepping"). So `media.nvim`
--- offers this and `hover.nvim` decides when to call it — with the offset it
--- would ask for on the next press, while the reader is still looking at this
--- one.
---
--- **Why this needs no machinery of its own.** `media.core.cache.ensure`
--- already joins a render that is in flight, and answers a finished one from a
--- single `fs_stat`; `probe` is cached too. So the real call that follows a
--- prefetch either finds the PNG on disk or waits on the process this started
--- — never a second ffmpeg for the same still. That is the whole feature: it
--- is `frame` with nobody listening.
---
--- The playback path has done this for its own windows since
--- `hover.nvim@9442f96` — a decode plus its sampling was measured at ~0.6 s,
--- so asking at the last frame arrives late every time. This is the same idea
--- one level down, for the still-stepping path that never got it.
---
--- Errors are swallowed deliberately. A prefetch that fails costs the reader
--- nothing, and the real call behind it reports properly; a notification about
--- work nobody asked for would be the only visible consequence.
---@param path string
---@param opts Media.FrameOpts|nil
---@return nil
function M.prefetch(path, opts)
  -- `"low"`: this is the one caller in the plugin whose work nobody has asked
  -- for yet, so it is the one that should give way. A prefetch that never runs
  -- because the queue stayed busy has lost nothing — the real request behind
  -- it does the work, which is where the plugin was before prefetching
  -- existed.
  M.frame(path, vim.tbl_extend("force", opts or {}, { priority = "low" }), function() end)
end

return M
