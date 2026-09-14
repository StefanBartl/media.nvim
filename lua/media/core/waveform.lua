---@module 'media.core.waveform'
---@brief A picture of an audio track — waveform or spectrogram.
---@description
--- What `frame` is for a video, this is for the sound in one: a still that
--- says something about the file without playing it. `sheet` is the closer
--- relative — both read the whole file once rather than seek — and the same
--- ffmpeg process shape applies: one pass, one PNG, cached on disk.
---
--- **Two filters, one module**, because `showwavespic` and `showspectrumpic`
--- differ in exactly one argument (which picture they draw) and nothing else
--- about how they are run, cached or reported on — duplicating the module
--- around that one difference would be two copies of `sheet.lua`'s shape with
--- one line changed in each.
---
--- **What this is for.** An mp3 without cover art has nothing to show in a
--- hover today; a waveform gives it something, the way a video's poster frame
--- does. A spectrogram answers a different question — what frequencies are in
--- this clip — and costs nothing extra once the waveform's plumbing exists.
---
--- **No duration needed, unlike `sheet`.** Both filters read every sample of
--- the input and draw the whole thing; there is no interval to compute up
--- front, so a file that reports no duration is not a problem here the way it
--- is for a contact sheet.

local M = {}

--- The argv for one rendering.
---
--- Pure and public for the same reason `sheet.args` is: the filter string is
--- the entire content of this module, and it should be assertable without
--- ffmpeg installed or an audio file to feed it.
---@param spec { ffmpeg: string, path: string, out: string, width: integer, height: integer, mode: "wave"|"spectrum", colors: string|nil }
---@return string[]
function M.args(spec)
  local filter
  if spec.mode == "spectrum" then
    filter = ("showspectrumpic=s=%dx%d"):format(spec.width, spec.height)
  else
    -- `colors` is `showwavespic`'s own argument, not a generic ffmpeg one:
    -- left unset it defaults to white, which draws invisibly against a light
    -- terminal background — so a colour is always passed rather than left to
    -- ffmpeg's default.
    filter = ("showwavespic=s=%dx%d:colors=%s"):format(
      spec.width,
      spec.height,
      spec.colors or "white"
    )
  end

  return {
    spec.ffmpeg,
    "-nostdin",
    "-hide_banner",
    "-loglevel",
    "error",
    "-i",
    spec.path,
    "-filter_complex",
    filter,
    "-frames:v",
    "1",
    "-y",
    spec.out,
  }
end

---@internal
---@param mode "wave"|"spectrum"
---@param path string
---@param opts Media.WaveformOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
local function render(mode, path, opts, callback)
  opts = opts or {}
  local cfg = require("media.config").get()
  local width = math.max(64, math.floor(opts.width or cfg.waveform.width))
  local height = math.max(32, math.floor(opts.height or cfg.waveform.height))
  local colors = mode == "wave" and (opts.colors or cfg.waveform.colors) or nil

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
    if not probe.has_audio then
      callback(nil, "no audio stream in this file")
      return
    end

    local kind = mode == "wave" and "waveform" or "spectrogram"
    local out, cerr = require("media.core.cache").file(kind, path, { width, height, colors or "" })
    if not out then
      callback(nil, cerr)
      return
    end

    local argv = M.args({
      ffmpeg = bin,
      path = path,
      out = out,
      width = width,
      height = height,
      mode = mode,
      colors = colors,
    })

    require("media.core.cache").ensure(out, function(done)
      vim.system(argv, { text = true, timeout = cfg.waveform.timeout_ms }, function(result)
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

--- A PNG of `path`'s waveform.
---@param path string
---@param opts Media.WaveformOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.waveform(path, opts, callback)
  render("wave", path, opts, callback)
end

--- A PNG of `path`'s spectrogram.
---@param path string
---@param opts Media.WaveformOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.spectrogram(path, opts, callback)
  render("spectrum", path, opts, callback)
end

return M
