---@module 'media.hub.text'
---@brief `:Media text` — one verb, four kinds, whatever tool each one needs.
---@description
--- The point of the whole hub (ROADMAP.md, "The hub"): an image goes to
--- `images.ocr.run`, a PDF to `pdfport.extract`, audio and video to this
--- plugin's own dispatcher, and anything else says so rather than guessing.
--- One thing to remember, four tools behind it.
---
--- **Every route out is a `pcall`, and none of them is required.** This is the
--- one module in the ecosystem allowed to know all four kinds; that permission
--- is exactly why no dependency here may be hard. A missing images.nvim costs
--- OCR and nothing else — it does not cost the PDF route, and it does not stop
--- a dashboard being drawn.
---
--- **A tool that is not there is reported, not hidden.** `M.tool(kind)` answers
--- with the reason and the fix rather than a bare false, because the useful
--- form of "no" here is the one a reader can act on: *which* thing is missing
--- and what installs it. The roadmap's action table asks for the same thing one
--- level up — a row whose tool is absent still shows its action, greyed, with
--- the reason beside it.
---
--- **What this module can and cannot know about availability.** For OCR it can
--- be precise: `images.ocr.bin()` is a public function that answers whether
--- tesseract was found. For PDFs it deliberately checks only that pdfport.nvim
--- is installed and exposes `extract` — whether any of its seven backends can
--- read *this* document is a question pdfport answers itself, in its own words,
--- when the run happens ("no available backend. Tried: …"). Reaching into
--- `pdfport.core.resolver` to pre-empt that would couple this to another
--- plugin's internals in order to produce a worse message.

local M = {}

--- Whether the tool a kind needs is here, and what to do when it is not.
---@class Media.Hub.Tool
---@field ok boolean
---@field tool string        # what does the work, named for a row and a message
---@field reason string|nil  # why it cannot run, when `ok` is false
---@field fix string|nil     # the one thing that would change that

--- What one run produced.
---
--- `transcript` is present only for audio and video, and it is the reason this
--- is a table rather than a bare string: SRT and VTT need the segments, and by
--- the time the text has been flattened they are gone.
---@class Media.Hub.Text
---@field kind Media.Hub.Kind
---@field text string
---@field tool string
---@field transcript Media.Transcript|nil
---@field detail string|nil  # what the tool wants to say about the run, e.g. "24 pages"

---@internal
---@return Media.Hub.Tool
local function image_tool()
  local ok, ocr = pcall(require, "images.ocr")
  if not ok or type(ocr) ~= "table" or type(ocr.run) ~= "function" then
    return {
      ok = false,
      tool = "tesseract",
      reason = "images.nvim is not installed",
      fix = "it is the plugin that owns OCR in this ecosystem",
    }
  end

  local found_ok, bin = pcall(ocr.bin)
  if not found_ok or not bin then
    return {
      ok = false,
      tool = "tesseract",
      reason = "tesseract was not found",
      fix = "install tesseract, or set images.nvim's `ocr.bin`",
    }
  end

  return { ok = true, tool = "tesseract" }
end

---@internal
---@return Media.Hub.Tool
local function pdf_tool()
  local ok, pdfport = pcall(require, "pdfport")
  if not ok or type(pdfport) ~= "table" or type(pdfport.extract) ~= "function" then
    return {
      ok = false,
      tool = "pdfport",
      reason = "pdfport.nvim is not installed",
      fix = "it is the plugin that owns PDF text in this ecosystem",
    }
  end
  -- Which of its backends can read this particular document is pdfport's own
  -- question; see the module header for why it is not pre-empted here.
  return { ok = true, tool = "pdfport" }
end

---@internal
---@return Media.Hub.Tool
local function transcribe_tool()
  local engine = require("media.config").get().transcribe.engine
  if require("media").transcribe_available() then return { ok = true, tool = engine } end
  return {
    ok = false,
    tool = engine,
    reason = ("no transcription engine is available (%s)"):format(engine),
    fix = "`:checkhealth media` says which of the binary and the model is missing",
  }
end

--- Whether `:Media text` could run on this kind right now.
---
--- Answered without starting anything, so a dashboard may ask once per row
--- while it draws.
---@param kind Media.Hub.Kind
---@return Media.Hub.Tool
function M.tool(kind)
  if kind == "image" then return image_tool() end
  if kind == "pdf" then return pdf_tool() end
  if kind == "audio" or kind == "video" then return transcribe_tool() end
  return {
    ok = false,
    tool = "none",
    reason = "nothing here turns this kind of file into text",
    fix = nil,
  }
end

--- The `out=` modes this kind can deliver to.
---
--- Subtitles need timestamps, so they are offered for audio and video and
--- nowhere else: a page of OCR has no segments to put a cue around, and an
--- `.srt` of one would be a single cue spanning nothing.
---@param kind Media.Hub.Kind
---@return string[]
function M.modes(kind)
  if kind == "audio" or kind == "video" then return require("media.output").MODES end
  return { "buffer", "sidecar" }
end

---@internal
--- Turn one image into text.
---@param path string
---@param callback fun(result: Media.Hub.Text|nil, err: string|nil): nil
---@return nil
local function run_image(path, callback)
  local tool = image_tool()
  if not tool.ok then return callback(nil, tool.reason) end

  require("images.ocr").run(path, nil, function(text, err)
    if not text then return callback(nil, err or "OCR failed") end
    callback({ kind = "image", text = text, tool = tool.tool }, nil)
  end)
end

---@internal
--- Turn one PDF into text.
---
--- `__callback` is how `pdfport.extract` reports — its own name for it, and
--- the one its `assert` requires.
---@param path string
---@param callback fun(result: Media.Hub.Text|nil, err: string|nil): nil
---@return nil
local function run_pdf(path, callback)
  local tool = pdf_tool()
  if not tool.ok then return callback(nil, tool.reason) end

  local ok, err = pcall(require("pdfport").extract, {
    path = path,
    __callback = function(result)
      if type(result) ~= "table" then return callback(nil, "pdfport returned nothing") end
      -- `"partial"` is a result, not a failure: a document whose last pages
      -- could not be read still answers most of what was asked, and throwing
      -- that away would be the same mistake as refusing a run of frames
      -- because the file ended (see `media.core.frames`).
      if result.status == "error" or not result.text then
        return callback(nil, result.error or "pdfport could not extract any text")
      end
      callback({
        kind = "pdf",
        text = result.text,
        tool = result.backend or tool.tool,
        detail = result.pages_processed and (result.pages_processed .. " pages") or nil,
      }, nil)
    end,
  })
  -- `extract` asserts on its arguments rather than returning an error, so a
  -- shape this module got wrong would otherwise surface as a raw Lua error out
  -- of a command.
  if not ok then callback(nil, tostring(err)) end
end

---@internal
--- Turn one audio or video file into text.
---@param path string
---@param kind Media.Hub.Kind
---@param opts table|nil
---@param callback fun(result: Media.Hub.Text|nil, err: string|nil): nil
---@return Media.Transcribe.Handle|nil
local function run_media(path, kind, opts, callback)
  local tool = transcribe_tool()
  if not tool.ok then
    callback(nil, tool.reason)
    return nil
  end

  return require("media").transcribe(path, opts, function(transcript, err)
    if not transcript then return callback(nil, err or "transcription failed") end
    callback({
      kind = kind,
      text = transcript.text or require("media.core.segments").to_text(transcript.segments),
      tool = transcript.engine or tool.tool,
      transcript = transcript,
    }, nil)
  end)
end

--- Turn `path` into text, whatever sort of file it is.
---
--- The callback runs exactly once, on the main loop, as every callback in this
--- plugin does. The handle is `nil` for everything but audio and video —
--- neither OCR nor PDF extraction offers one to give back, and inventing a
--- no-op `cancel()` would be a promise this cannot keep.
---@param path string
---@param opts table|nil  # forwarded to `media.transcribe` for audio and video
---@param callback fun(result: Media.Hub.Text|nil, err: string|nil): nil
---@return Media.Transcribe.Handle|nil
function M.run(path, opts, callback)
  local kind = require("media.hub.kinds").of(path)

  if kind == "image" then
    run_image(path, callback)
    return nil
  end
  if kind == "pdf" then
    run_pdf(path, callback)
    return nil
  end
  if kind == "audio" or kind == "video" then return run_media(path, kind, opts, callback) end

  -- The roadmap's own wording for the fourth branch: "anything else → a notify
  -- saying so". Said as an error to the caller rather than notified here, so
  -- the command owns every message it prints.
  vim.schedule(function()
    callback(nil, ("nothing here turns a %s into text"):format(vim.fn.fnamemodify(path, ":e")))
  end)
  return nil
end

---@internal
--- The sidecar document for an OCR or extraction result.
---
--- The same shape and the same honesty as `media.output.sidecar.content`: a
--- title, a line saying what made this and when, and an instruction to correct
--- the sidecar rather than the source. The wording differs per kind because the
--- failure modes do — a misread word and an unreadable page are not the same
--- warning.
---@param path string
---@param result Media.Hub.Text
---@return string
local function sidecar_content(path, result)
  local name = vim.fn.fnamemodify(path, ":t")
  local made = result.detail and ("%s, %s"):format(result.tool, result.detail) or result.tool

  local title, caveat
  if result.kind == "image" then
    title = ("# OCR — %s"):format(name)
    caveat = "Machine-read with %s on %s. Recognition errors are possible —"
  else
    title = ("# Text — %s"):format(name)
    caveat = "Extracted with %s on %s. A page with no text layer may be missing —"
  end

  return table.concat({
    title,
    "",
    ("> " .. caveat):format(made, os.date("%Y-%m-%d")),
    "> correct this file rather than the source; nothing regenerates it unless",
    "> the source itself changes.",
    "",
    result.text,
    "",
  }, "\n")
end

--- The file `mode` writes for `path`, or `nil` when it writes none.
---
--- The counterpart of `media.output.written_path`, one kind wider: for audio
--- and video it *is* that function, because those go through `media.output`
--- unchanged; for an image or a PDF it is the sidecar `media.hub.kinds` names.
--- One place that knows, so a command reporting "wrote …" cannot fall behind a
--- kind added later.
---@param path string
---@param kind Media.Hub.Kind
---@param mode string|nil
---@return string|nil
function M.written_path(path, kind, mode)
  if kind == "audio" or kind == "video" then
    return require("media.output").written_path(path, mode)
  end
  if mode == "sidecar" then return require("media.hub.kinds").sidecar(path, kind) end
  return nil
end

--- Put `result` where `mode` says.
---
--- Audio and video go through `media.output` unchanged, so `srt` and `vtt`
--- reach the serialisers with their segments intact — flattening first and
--- handing the string here would lose exactly what a subtitle file is made of.
--- The other two kinds have no segments and so no subtitle modes; `M.modes`
--- is the list, and a caller checks it before the run rather than after.
---@param path string
---@param result Media.Hub.Text
---@param mode string|nil  # default `transcribe.output`
---@return boolean ok
---@return string|nil err
function M.deliver(path, result, mode)
  mode = (mode and mode ~= "") and mode or require("media.config").get().transcribe.output

  if result.transcript then
    return require("media.output").deliver(path, result.transcript, mode)
  end

  if mode == "sidecar" then
    local out = require("media.hub.kinds").sidecar(path, result.kind)
    if not out then return false, "this kind of file has no sidecar" end
    local fd, err = io.open(out, "w")
    if not fd then return false, err or ("could not open " .. out) end
    fd:write(sidecar_content(path, result))
    fd:close()
    return true, nil
  end

  if mode ~= "buffer" then
    return false,
      ("out=%s is not available for this kind (%s) — expected one of %s"):format(
        tostring(mode),
        result.kind,
        table.concat(M.modes(result.kind), ", ")
      )
  end

  local ok, ui = pcall(require, "media.ui")
  if not ok then return false, "media.ui not available" end
  ui.show_text(result.text, (" media: %s — text "):format(vim.fn.fnamemodify(path, ":t")))
  return true, nil
end

return M
