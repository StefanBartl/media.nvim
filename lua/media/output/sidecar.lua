---@module 'media.output.sidecar'
---@brief `<file>.transcript.md` — the sidecar convention this ecosystem's
---OCR already established, generalised to any transcript.
---@description
--- Same shape as `images.ocr`'s consumer, `case/ocr.lua`: the suffix is
--- appended to the *full* file name, not swapped for the extension, so
--- `talk.mp4` and `talk.mov` do not collide and a grep hit explains itself —
--- every `*.md`-walking tool picks it up with no changes of its own.
---
--- **Staleness is by mtime, not existence.** A source video edited after its
--- sidecar was written is stale — the same rule `case/ocr.is_stale` applies,
--- for the same reason: a transcript describing an older cut of the file is
--- worse than none once it disagrees with what is actually there.

local M = {}

local SUFFIX = ".transcript.md"

---@param path string
---@return string
function M.path(path)
  return path .. SUFFIX
end

---@param path string
---@return boolean
function M.is_stale(path)
  local uv = vim.uv or vim.loop
  local sidecar = uv.fs_stat(M.path(path))
  if not sidecar then return true end
  local source = uv.fs_stat(path)
  if not source then return false end
  return (source.mtime and source.mtime.sec or 0) > (sidecar.mtime and sidecar.mtime.sec or 0)
end

--- The sidecar document for one transcript.
---
--- Pure, and public, for the same reason `sidecar_content` in `case/ocr.lua`
--- is worth keeping separate from the write: the shape is assertable without
--- touching disk.
---@param path string
---@param transcript Media.Transcript
---@return string
function M.content(path, transcript)
  local name = vim.fn.fnamemodify(path, ":t")
  local by = transcript.model and (transcript.engine .. " (" .. transcript.model .. ")")
    or transcript.engine

  return table.concat({
    ("# Transcript — %s"):format(name),
    "",
    ("> Machine-transcribed with %s on %s. Recognition errors are possible —"):format(
      by,
      os.date("%Y-%m-%d")
    ),
    "> correct this file rather than the source; nothing regenerates it unless",
    "> the media file itself changes.",
    "",
    require("media.core.segments").to_text(transcript.segments),
    "",
  }, "\n")
end

---@param path string
---@param transcript Media.Transcript
---@return boolean ok
---@return string|nil err
function M.write(path, transcript)
  local fd, err = io.open(M.path(path), "w")
  if not fd then return false, err or ("could not open " .. M.path(path)) end
  fd:write(M.content(path, transcript))
  fd:close()
  return true, nil
end

return M
