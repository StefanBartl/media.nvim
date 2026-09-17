---@module 'media.hub.kinds'
---@brief What sort of file this is, and what turning it into text would mean.
---@description
--- The dashboard's vocabulary, and the reason this plugin is called `media`
--- rather than `transcribe` (ROADMAP.md, "The hub"): one list that shows
--- images, PDFs, audio and video side by side has to be allowed to know all
--- four, while none of the four is forced to know the others. This module is
--- where that knowledge is allowed to sit, and every route out of it is a
--- `pcall`.
---
--- **Classification never depends on a tool being installed.** A `.png` is an
--- image whether or not tesseract is on the machine, and a dashboard that
--- silently omitted it would answer a question nobody asked — "what can I do
--- right now" instead of "what is here". Availability belongs to the *action*
--- (a row whose tool is missing still shows what it would do, and why it
--- cannot), which is what the roadmap's own action table says.
---
--- **Three text operations, three sidecar names, and that is deliberate.**
--- `.ocr.md`, `.transcript.md` and `.text.md` are not three spellings of one
--- thing: OCR misreads, transcription mishears, and extraction is exact. A
--- reader who finds a sidecar should be able to tell from its name how much to
--- trust it — and a corpus tool should be able to exclude the two lossy ones
--- without excluding the third (`case/similar.lua` already does exactly that
--- for OCR, and ROADMAP.md's "Risks" section extends the rule to transcripts).
---
--- The first two are the ecosystem's, unchanged: `casedesk.nvim`'s
--- `ocr.sidecar_path` writes `.ocr.md`, `media.output.sidecar` writes
--- `.transcript.md`. `.text.md` is new here, because pdfport has no sidecar
--- convention at all — it hands extracted text back and the caller decides.

local M = {}

--- What a path is, for the dashboard's purposes.
---
--- `"other"` is a real answer, not a failure: a scan of a directory sees
--- source files and READMEs, and the honest thing is to say they are not this
--- plugin's business rather than to guess a kind for them.
---@alias Media.Hub.Kind "image"|"pdf"|"audio"|"video"|"other"

---@internal
--- Image extensions used when images.nvim is not installed.
---
--- **A second list, on purpose, and only as a fallback.** images.nvim owns
--- this question — its `extensions` setting is the user's own answer to it,
--- and `images.integrations.picker.is_image` is the entry point it publishes
--- for exactly this kind of host. That is asked first, always. This list only
--- decides what a dashboard on a machine *without* images.nvim calls an image,
--- and the alternative to having it is worse: every `.png` in the directory
--- classified as `"other"`, so the row that would have said "OCR is available
--- once you install images.nvim" is never printed at all.
---@type table<string, true>
local IMAGE = {
  png = true,
  jpg = true,
  jpeg = true,
  gif = true,
  webp = true,
  bmp = true,
  tif = true,
  tiff = true,
  svg = true,
}

---@internal
--- Whether images.nvim calls this an image, falling back to `IMAGE` above.
---@param path string
---@param ext string
---@return boolean
local function is_image(path, ext)
  local ok, picker = pcall(require, "images.integrations.picker")
  if ok and type(picker) == "table" and type(picker.is_image) == "function" then
    local answered, result = pcall(picker.is_image, path)
    if answered then return result == true end
  end
  return IMAGE[ext] == true
end

--- What `path` is.
---
--- Audio and video are answered first and from this plugin's own tables: they
--- are the two kinds `media.nvim` is the authority on, and `media.formats`
--- explains at length why they are separate lists rather than one flag.
---@param path string|nil
---@return Media.Hub.Kind
function M.of(path)
  if type(path) ~= "string" or path == "" then return "other" end

  local formats = require("media.formats")
  if formats.is_video(path) then return "video" end
  if formats.is_audio(path) then return "audio" end

  local ext = formats.extension(path)
  if not ext then return "other" end

  -- The extension alone, deliberately — not `images.integrations.picker
  -- .is_pdf`, which also asks whether this machine can *rasterize* it. That is
  -- the right question before promising to draw a page and the wrong one here:
  -- a PDF whose text cannot be extracted today is still a PDF, and the row is
  -- how the reader finds out what is missing.
  if ext == "pdf" then return "pdf" end

  if is_image(path, ext) then return "image" end
  return "other"
end

---@internal
--- The sidecar suffix per kind — nil for a kind with no text operation.
---@type table<Media.Hub.Kind, string>
local SIDECAR = {
  image = ".ocr.md",
  pdf = ".text.md",
  audio = ".transcript.md",
  video = ".transcript.md",
}

--- The file that would hold `path`'s text, or `nil` when nothing here turns
--- this kind into text.
---
--- Appended to the *full* file name rather than swapping the extension, the
--- convention `media.output.sidecar` argues for and `casedesk.nvim` already
--- follows: `talk.mp4` and `talk.mov` in one directory do not collide, and a
--- grep hit explains itself.
---@param path string
---@param kind Media.Hub.Kind|nil  # computed from `path` when omitted
---@return string|nil
function M.sidecar(path, kind)
  local suffix = SIDECAR[kind or M.of(path)]
  return suffix and (path .. suffix) or nil
end

--- Whether `path` is one of the sidecars this hub knows about.
---
--- A scan has to skip these or the dashboard lists its own output: a
--- `.transcript.md` is a markdown file, and the next scan would offer to turn
--- it into text.
---@param path string|nil
---@return boolean
function M.is_sidecar(path)
  if type(path) ~= "string" then return false end
  for _, suffix in pairs(SIDECAR) do
    if #path > #suffix and path:sub(-#suffix) == suffix then return true end
  end
  return false
end

--- The verb this kind's text operation goes by, for a dashboard row and for
--- the message when it cannot run.
---
--- Three different words because they are three different operations, and the
--- name is the only warning a reader gets about how much to trust the result.
---@param kind Media.Hub.Kind
---@return string|nil
function M.verb(kind)
  if kind == "image" then return "ocr" end
  if kind == "pdf" then return "text" end
  if kind == "audio" or kind == "video" then return "transcript" end
  return nil
end

return M
