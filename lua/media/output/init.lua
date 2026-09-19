---@module 'media.output'
---@brief Delivering a finished transcript: a buffer, a sidecar, or subtitles.
---@description
--- Four routes. `"buffer"` is the OCR precedent's own reasoning
--- (`images.ocr`'s module header, and `MEDIA-TO-TEXT.md` section 5): put the
--- text somewhere the reader can look at and correct it before spending a
--- network call translating it, rather than this plugin guessing whether the
--- transcript is already good enough to write straight to disk. `"sidecar"`
--- writes the `.transcript.md` this ecosystem's OCR established. `"srt"` and
--- `"vtt"` write subtitles — phase 1 of ROADMAP.md's "Transcription", and what
--- mandatory per-segment timestamps existed for all along.
---
--- **An unknown mode is an error, not a buffer.** This module used to treat
--- everything that was not `"sidecar"` as a request for a buffer, which meant
--- `:Media transcribe out=str` opened a scratch window and said nothing about
--- it — the reader waited minutes for subtitles and got a typo silently
--- honoured as something else. `M.is_mode` exists so the *caller* can reject
--- it before the run starts rather than after.

local M = {}

---@internal
--- The subtitle writers, by mode. Both modules expose the same two functions
--- (`path` and `serialize`), so a third format is a line here plus a module
--- rather than another branch in `deliver`.
local SUBTITLES = {
  srt = "media.output.srt",
  vtt = "media.output.vtt",
}

--- Every mode `M.deliver` accepts, in the order help text lists them.
---@type string[]
M.MODES = { "buffer", "sidecar", "srt", "vtt" }

--- Whether `mode` is one this module can deliver. `nil` and `""` mean "the
--- configured default", which always is one.
---
--- Meant to be called *before* a run starts, not after: transcription is
--- minutes (ROADMAP.md, "Risks and known traps"), and finding the typo in
--- `out=` once the engine has finished wastes the entire wait.
---@param mode string|nil
---@return boolean
function M.is_mode(mode)
  if mode == nil or mode == "" then return true end
  return mode == "buffer" or mode == "sidecar" or SUBTITLES[mode] ~= nil
end

--- The file `mode` writes for `path`, or `nil` when it writes none.
---
--- The one place that knows, so a caller can report "wrote …" for every
--- file-producing mode without keeping a copy of the mapping — which is how a
--- command ends up still naming the only file it knew about before subtitles
--- existed.
---@param path string
---@param mode string|nil
---@return string|nil
function M.written_path(path, mode)
  if mode == "sidecar" then return require("media.output.sidecar").path(path) end
  local subtitle = mode and SUBTITLES[mode] or nil
  if subtitle then return require(subtitle).path(path) end
  return nil
end

---@internal
---@param path string
---@param content string
---@return boolean ok
---@return string|nil err
local function write(path, content)
  local fd, err = io.open(path, "w")
  if not fd then return false, err or ("could not open " .. path) end
  local wok, werr = fd:write(content)
  local cok, cerr = fd:close()
  if not wok then return false, werr or ("could not write " .. path) end
  if not cok then return false, cerr or ("could not close " .. path) end
  return true, nil
end

---@param path string
---@param transcript Media.Transcript
---@param mode Media.Output.Mode|nil
---@return boolean ok
---@return string|nil err
function M.deliver(path, transcript, mode)
  if mode == "sidecar" then return require("media.output.sidecar").write(path, transcript) end

  local subtitle = mode and SUBTITLES[mode] or nil
  if subtitle then
    local writer = require(subtitle)
    return write(writer.path(path), writer.serialize(transcript))
  end

  if not M.is_mode(mode) then
    return false,
      ("unknown output mode %q — expected one of %s"):format(
        tostring(mode),
        table.concat(M.MODES, ", ")
      )
  end

  local ok, ui = pcall(require, "media.ui")
  if not ok then return false, "media.ui not available" end
  ui.show_text(
    require("media.core.segments").to_text(transcript.segments),
    (" media: %s — transcript "):format(vim.fn.fnamemodify(path, ":t"))
  )
  return true, nil
end

return M
