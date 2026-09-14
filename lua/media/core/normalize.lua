---@module 'media.core.normalize'
---@brief Any file with sound, reduced to 16 kHz mono WAV.
---@description
--- What `frame` is to a still, this is to a speech model's input: whisper.cpp
--- (and everything derived from it) was trained on 16 kHz mono and accepts
--- nothing else directly. One ffmpeg pass — `-vn -ac 1 -ar 16000` — into a
--- WAV cached the same way every other rendering here is.
---
--- **No seek, unlike `frame`.** Transcription wants the whole file; there is
--- no offset to resolve, which is what makes this simpler than either half of
--- `frame`/`frames`.

local M = {}

--- The argv for one conversion.
---
--- Pure and public for the same reason `frame.args` is: the argument order is
--- the entire content of this module, and it should be assertable without
--- ffmpeg installed or a file to feed it.
---@param spec { ffmpeg: string, path: string, out: string }
---@return string[]
function M.args(spec)
  return {
    spec.ffmpeg,
    "-nostdin",
    "-hide_banner",
    "-loglevel",
    "error",
    "-i",
    spec.path,
    -- No picture in the output, one channel, the sample rate whisper.cpp's
    -- models were trained on.
    "-vn",
    "-ac",
    "1",
    "-ar",
    "16000",
    "-y",
    spec.out,
  }
end

--- A 16 kHz mono WAV of `path`'s audio, cached on disk.
---
--- Cancellable, like `frames()` — unlike `frame()`, which never needed a
--- handle. A caller giving up on a transcription mid-normalize must be able
--- to stop the ffmpeg process rather than let it run to completion for a
--- result nobody reads; found missing in review, 2026-09-14.
---@param path string
---@param callback fun(wav: string|nil, err: string|nil): nil
---@return Media.Transcribe.Handle
function M.normalize(path, callback)
  local cfg = require("media.config").get()

  local cancelled = false
  ---@type vim.SystemObj|nil
  local proc = nil
  local handle = {
    cancel = function()
      cancelled = true
      if proc then
        pcall(function()
          require("media.core.proc").stop(proc)
        end)
        proc = nil
      end
    end,
  }

  ---@param wav string|nil
  ---@param err string|nil
  local function finish(wav, err)
    if cancelled then return end
    callback(wav, err)
  end

  local bin = require("media.core.bin").find("ffmpeg")
  if not bin then
    vim.schedule(function()
      finish(nil, "ffmpeg not found — install it, or set `bin.ffmpeg`")
    end)
    return handle
  end

  require("media.core.probe").probe(path, function(probe, perr)
    if cancelled then return end
    if not probe then
      finish(nil, perr)
      return
    end
    if not probe.has_audio then
      finish(nil, "no audio stream in this file")
      return
    end

    local out, cerr = require("media.core.cache").file("wav", path, {}, "wav")
    if not out then
      finish(nil, cerr)
      return
    end

    local argv = M.args({ ffmpeg = bin, path = path, out = out })

    require("media.core.cache").ensure(out, function(done)
      proc = vim.system(
        argv,
        { text = true, timeout = cfg.transcribe.normalize_timeout_ms },
        function(result)
          proc = nil
          if result.code ~= 0 then
            local stderr = (result.stderr or ""):gsub("%s+$", "")
            done(stderr ~= "" and stderr or ("ffmpeg exited with " .. tostring(result.code)))
            return
          end
          done(nil)
        end
      )
    end, finish)
  end)

  return handle
end

return M
