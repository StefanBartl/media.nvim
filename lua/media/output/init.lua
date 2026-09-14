---@module 'media.output'
---@brief Delivering a finished transcript: a buffer, or a sidecar file.
---@description
--- Two routes for phase 0 (ROADMAP.md's command grammar names `srt`, `vtt`
--- and `clipboard` for later phases, once `core.segments` can serialise
--- them). `"buffer"` is the OCR precedent's own reasoning
--- (`images.ocr`'s module header, and `MEDIA-TO-TEXT.md` section 5): put the
--- text somewhere the reader can look at and correct it before spending a
--- network call translating it, rather than this plugin guessing whether the
--- transcript is already good enough to write straight to disk.

local M = {}

---@param path string
---@param transcript Media.Transcript
---@param mode "buffer"|"sidecar"
---@return boolean ok
---@return string|nil err
function M.deliver(path, transcript, mode)
  if mode == "sidecar" then return require("media.output.sidecar").write(path, transcript) end

  local ok, ui = pcall(require, "media.ui")
  if not ok then return false, "media.ui not available" end
  ui.show_text(
    require("media.core.segments").to_text(transcript.segments),
    (" media: %s — transcript "):format(vim.fn.fnamemodify(path, ":t"))
  )
  return true, nil
end

return M
