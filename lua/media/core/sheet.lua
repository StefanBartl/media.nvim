---@module 'media.core.sheet'
---@brief A contact sheet — the whole file as one picture.
---@description
--- What a poster frame cannot answer: *what happens in this video?* A grid of
--- stills taken at even intervals answers it in one image, in one render, and
--- without anything that could be called playback.
---
--- **How the frames are selected, and why not `select`.** The obvious recipe is
--- `select='not(mod(n,X))'` — every Xth *decoded* frame — which needs a frame
--- count nobody has before decoding, and gives an interval in frames rather
--- than in seconds, so a 25 fps clip and a 60 fps clip with the same runtime
--- produce different coverage. `fps=N/duration` states the actual intent: N
--- frames spread evenly across the running time, whatever the source rate is.
---
--- **The grid always produces an image, even when the frame count is off by
--- one.** `fps` is a rational and a duration is a rounded float, so the last
--- tile is the one that may not arrive. The `tile` filter flushes what it has
--- at end-of-stream rather than dropping an incomplete grid, so the result is a
--- sheet with one empty cell instead of no sheet at all — which is the right
--- trade for something whose job is a quick look.
---
--- **Long files are sampled from keyframes only.** `-skip_frame nokey` makes
--- the decoder throw away everything but keyframes, which turns a pass over a
--- feature-length file from minutes into seconds — and costs nothing, because a
--- twelve-tile sheet of a two-hour film wants one frame every ten minutes and
--- keyframes come every few seconds. It is *not* used on short files: a clip
--- whose only keyframe is the first frame would yield twelve copies of it. The
--- threshold below is where a file is long enough that keyframes are
--- guaranteed denser than the sampling interval.

local M = {}

---@type number Seconds above which the keyframe-only decode is used.
--- Two minutes: the shortest running time at which a twelve-tile sheet samples
--- less often than every ten seconds, which every encoder's keyframe interval
--- beats by an order of magnitude.
local KEYFRAME_ONLY_ABOVE = 120

--- The argv for one contact sheet.
---
--- Pure and public for the same reason `frame.args` is: the filter chain is the
--- entire content of this module, and it should be assertable without ffmpeg.
---@param spec { ffmpeg: string, path: string, out: string, rows: integer, cols: integer, width: integer, margin: integer, duration: number, keyframes_only: boolean|nil }
---@return string[]
function M.args(spec)
  local tiles = spec.rows * spec.cols

  -- The width of one tile, derived from the width of the finished sheet: the
  -- caller asked for a picture of a certain size, and the grid is an internal
  -- detail of how it gets filled. Margins are laid outside each tile, so they
  -- have to come off the budget before dividing.
  local margins = spec.margin * (spec.cols + 1)
  local tile_width = math.max(16, math.floor((spec.width - margins) / spec.cols))

  local filter = ("fps=%d/%s,scale=%d:-2,tile=%dx%d:margin=%d:padding=%d"):format(
    tiles,
    -- Formatted rather than concatenated: a duration arrives as a float, and
    -- `tostring` on some of them yields exponent notation, which is not a
    -- rational and makes ffmpeg reject the whole filter graph.
    ("%.6f"):format(spec.duration),
    tile_width,
    spec.cols,
    spec.rows,
    spec.margin,
    spec.margin
  )

  local argv = {
    spec.ffmpeg,
    "-nostdin",
    "-hide_banner",
    "-loglevel",
    "error",
  }

  -- A decoder flag, so it belongs before the input it applies to.
  if spec.keyframes_only then
    argv[#argv + 1] = "-skip_frame"
    argv[#argv + 1] = "nokey"
  end

  return vim.list_extend(argv, {
    "-i",
    spec.path,
    "-vf",
    filter,
    "-frames:v",
    "1",
    "-y",
    spec.out,
  })
end

--- A PNG contact sheet of `path`.
---
--- Unlike `frame`, this one decodes the file from the beginning — that is what
--- sampling across the whole running time means — so it is seconds, not
--- milliseconds, on a long video. The disk cache is therefore not an
--- optimisation here but the thing that makes the feature usable twice.
---@param path string
---@param opts Media.SheetOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.sheet(path, opts, callback)
  opts = opts or {}
  local cfg = require("media.config").get()
  local rows = math.max(1, math.floor(opts.rows or cfg.sheet.rows))
  local cols = math.max(1, math.floor(opts.cols or cfg.sheet.cols))
  local width = math.max(64, math.floor(opts.width or cfg.sheet.width))
  local margin = math.max(0, math.floor(opts.margin or cfg.sheet.margin))

  local bin = require("media.core.bin").find("ffmpeg")
  if not bin then
    vim.schedule(function()
      callback(nil, "ffmpeg not found — install it, or set `bin.ffmpeg`")
    end)
    return
  end

  require("media.core.probe").probe(path, function(probe, perr)
    if not probe then
      callback(nil, perr)
      return
    end
    if not probe.has_video then
      callback(nil, "a contact sheet needs moving picture, and this file has none")
      return
    end
    if not probe.duration or probe.duration <= 0 then
      -- Without a duration there is no interval to spread the frames over, and
      -- guessing one produces a sheet of twelve stills from the first second.
      callback(nil, "this file reports no duration, so frames cannot be spread over it")
      return
    end

    local out, cerr = require("media.core.cache").file("sheet", path, { rows, cols, width, margin })
    if not out then
      callback(nil, cerr)
      return
    end

    local argv = M.args({
      ffmpeg = bin,
      path = path,
      out = out,
      rows = rows,
      cols = cols,
      width = width,
      margin = margin,
      duration = probe.duration,
      keyframes_only = probe.duration > KEYFRAME_ONLY_ABOVE,
    })

    require("media.core.cache").ensure(out, function(done)
      vim.system(argv, { text = true, timeout = cfg.sheet.timeout_ms }, function(result)
        if result.code ~= 0 then
          local stderr = (result.stderr or ""):gsub("%s+$", "")
          done(stderr ~= "" and stderr or ("ffmpeg exited with " .. tostring(result.code)))
          return
        end
        done(nil)
      end)
    end, callback)
  end)
end

return M
